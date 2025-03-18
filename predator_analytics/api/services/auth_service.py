import os
from datetime import datetime, timedelta, date, time
from jose import jwt, JWTError
from api.config import settings
import asyncpg
from fastapi import HTTPException
from passlib.context import CryptContext
import re
import logging
from uuid import uuid4
from typing import List, Optional, Dict
from asyncpg import create_pool
from functools import wraps
import secrets
import pyotp
import geoip2.database
import pandas as pd
import numpy as np

SECRET_KEY = os.getenv("SECRET_KEY")  # Ключ повинен бути заданий через змінну оточення
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Додаємо константи для блокування
MAX_LOGIN_ATTEMPTS = 3
BLOCK_TIME_MINUTES = 15

# Налаштування логування
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Створюємо пул з'єднань
_pool = None


async def get_pool():
    global _pool
    if _pool is None:
        _pool = await create_pool(
            host=settings.POSTGRES_HOST,
            database=settings.POSTGRES_DB,
            user=settings.POSTGRES_USER,
            password=settings.POSTGRES_PASSWORD,
            port=settings.POSTGRES_PORT,
            min_size=5,
            max_size=20,
        )
    return _pool


def with_connection(func):
    @wraps(func)
    async def wrapper(*args, **kwargs):
        pool = await get_pool()
        async with pool.acquire() as conn:
            async with conn.transaction():
                # Усі зміни автоматично комітяться після успішного виконання функції
                result = await func(conn, *args, **kwargs)
                return result
    return wrapper


def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password):
    return pwd_context.hash(password)


def validate_password(password: str) -> bool:
    if len(password) < 8:
        return False
    if not re.search(r"[A-Z]", password):
        return False
    if not re.search(r"[a-z]", password):
        return False
    if not re.search(r"\d", password):
        return False
    return True


async def check_login_attempts(conn, username: str) -> bool:
    query = """
    SELECT login_attempts, last_attempt_time 
    FROM user_login_attempts 
    WHERE username = $1
    """
    result = await conn.fetchrow(query, username)

    if result:
        attempts, last_attempt = result
        if attempts >= MAX_LOGIN_ATTEMPTS:
            block_until = last_attempt + timedelta(minutes=BLOCK_TIME_MINUTES)
            if datetime.utcnow() < block_until:
                return False
            await reset_login_attempts(conn, username)
    return True


async def update_login_attempts(conn, username: str, success: bool):
    if success:
        await reset_login_attempts(conn, username)
    else:
        query = """
        INSERT INTO user_login_attempts (username, login_attempts, last_attempt_time)
        VALUES ($1, 1, $2)
        ON CONFLICT (username) DO UPDATE SET 
            login_attempts = user_login_attempts.login_attempts + 1,
            last_attempt_time = $2
        """
        await conn.execute(query, username, datetime.utcnow())


async def reset_login_attempts(conn, username: str):
    query = "DELETE FROM user_login_attempts WHERE username = $1"
    await conn.execute(query, username)


@with_connection
async def authenticate_user(
    conn, username: str, password: str, totp_token: str = None, ip_address: str = None
):
    try:
        # Перевіряємо чи не заблокований користувач
        if not await check_login_attempts(conn, username):
            raise HTTPException(
                status_code=429,
                detail=f"Забагато невдалих спроб. Спробуйте через {BLOCK_TIME_MINUTES} хвилин",
            )

        query = "SELECT username, password_hash FROM users WHERE username = $1"
        user = await conn.fetchrow(query, username)

        if not user or not verify_password(password, user["password_hash"]):
            await update_login_attempts(conn, username, False)
            logger.warning(f"Невдала спроба входу для користувача: {username}")
            raise HTTPException(status_code=401, detail="Невірні облікові дані")

        await update_login_attempts(conn, username, True)
        logger.info(f"Успішний вхід користувача: {username}")

        # Перевіряємо чи увімкнено 2FA
        tfa_status = await conn.fetchrow(
            "SELECT is_enabled FROM two_factor_auth WHERE username = $1", username
        )

        if tfa_status and tfa_status["is_enabled"]:
            if not totp_token:
                raise HTTPException(status_code=403, detail="Потрібна двофакторна автентифікація")
            if not await verify_2fa_token(conn, username, totp_token):
                raise HTTPException(
                    status_code=401, detail="Невірний код двофакторної автентифікації"
                )

        # Перевіряємо локацію
        if ip_address:
            location_data = await log_user_location(conn, username, ip_address)
            if location_data:
                anomaly = await detect_location_anomalies(conn, username, location_data)
                if anomaly:
                    logger.warning(f"Виявлено аномалію для користувача {username}: {anomaly}")

        # Оновлюємо статистику після успішної автентифікації
        await update_auth_statistics(conn, username, True, ip_address)

        # Аналізуємо поведінку та розраховуємо ризик
        current_activity = {
            "ip_address": ip_address,
            "location_data": (
                await log_user_location(conn, username, ip_address) if ip_address else None
            ),
        }

        risk_score = await calculate_risk_score(conn, username, current_activity)

        # Якщо ризик високий, вимагаємо додаткову автентифікацію
        if risk_score >= 60 and not totp_token:
            raise HTTPException(
                status_code=403, detail="Потрібна додаткова автентифікація через підвищений ризик"
            )

        # Перевіряємо на шаблони атак
        activity_data = {
            "type": "authentication",
            "username": username,
            "ip_address": ip_address,
            "timestamp": datetime.utcnow().isoformat(),
            "success": True,
        }

        detected_patterns = await detect_attack_patterns(conn, username, activity_data)
        if detected_patterns:
            logger.warning(f"Виявлено потенційні атаки для {username}: {detected_patterns}")

        return {"username": user["username"]}

    except HTTPException as e:
        # Оновлюємо статистику після невдалої спроби
        await update_auth_statistics(conn, username, False)
        raise
    except Exception as e:
        logger.error(f"Помилка при автентифікації: {str(e)}")
        raise HTTPException(status_code=500, detail="Внутрішня помилка сервера")


def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    if SECRET_KEY is None:
        raise HTTPException(status_code=500, detail="SECRET_KEY не налаштований")
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


async def refresh_token(refresh_token: str):
    try:
        if SECRET_KEY is None:
            raise HTTPException(status_code=500, detail="SECRET_KEY не налаштований")
        payload = jwt.decode(refresh_token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if not username:
            raise HTTPException(status_code=401, detail="Невалідний токен оновлення")

        new_access_token = create_access_token({"sub": username})
        return {"access_token": new_access_token}
    except JWTError:
        raise HTTPException(status_code=401, detail="Невалідний токен оновлення")
    except Exception as e:
        logger.error(f"Помилка при оновленні токену: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при оновленні токену")


async def deactivate_token(token: str):
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            query = "INSERT INTO deactivated_tokens (token) VALUES ($1)"
            await conn.execute(query, token)
    except Exception as e:
        logger.error(f"Помилка при деактивації токена: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при деактивації токену")


@with_connection
async def verify_token(conn, token: str):
    try:
        if SECRET_KEY is None:
            raise HTTPException(status_code=500, detail="SECRET_KEY не налаштований")
        if await is_token_deactivated(conn, token):
            raise HTTPException(status_code=401, detail="Токен деактивовано")

        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if username is None:
            raise HTTPException(status_code=401, detail="Невалідний токен")

        roles = await get_user_roles(conn, username)
        return {"username": username, "roles": roles}

    except JWTError:
        raise HTTPException(status_code=401, detail="Невалідний токен")
    except Exception as e:
        logger.error(f"Помилка при перевірці токену: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при перевірці токену")


async def create_user_session(conn, username: str, token: str):
    session_id = str(uuid4())
    query = """
    INSERT INTO user_sessions (session_id, username, token, created_at)
    VALUES ($1, $2, $3, $4)
    """
    await conn.execute(query, session_id, username, token, datetime.utcnow())
    return session_id


async def is_token_deactivated(conn, token: str) -> bool:
    query = "SELECT EXISTS(SELECT 1 FROM deactivated_tokens WHERE token = $1)"
    return await conn.fetchval(query, token)


async def terminate_all_sessions(username: str):
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            # Отримуємо всі активні токени користувача
            query = "SELECT token FROM user_sessions WHERE username = $1"
            tokens = await conn.fetch(query, username)

            # Деактивуємо всі токени
            for record in tokens:
                await deactivate_token(record["token"])

            # Видаляємо сесії
            await conn.execute("DELETE FROM user_sessions WHERE username = $1", username)

            logger.info(f"Всі сесії користувача {username} завершено")
    except Exception as e:
        logger.error(f"Помилка при завершенні сесій: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при завершенні сесій")


@with_connection
async def cleanup_expired_data(conn):
    """Очищення застарілих даних"""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            # Очищення старих деактивованих токенів (старші 7 днів)
            await conn.execute(
                """
                DELETE FROM deactivated_tokens 
                WHERE deactivated_at < NOW() - INTERVAL '7 days'
            """
            )

            # Очищення застарілих сесій
            await conn.execute(
                """
                DELETE FROM user_sessions 
                WHERE created_at < NOW() - INTERVAL '30 days'
            """
            )

            # Очищення старих токенів скидання паролю
            await conn.execute(
                """
                DELETE FROM password_reset_tokens 
                WHERE (used = TRUE AND created_at < NOW() - INTERVAL '24 hours')
                OR expires_at < NOW()
            """
            )

            # Очищення 2FA даних
            await cleanup_2fa_data()

            # Очищення старих метрик (старші 90 днів)
            await conn.execute(
                """
                DELETE FROM security_metrics 
                WHERE measured_at < NOW() - INTERVAL '90 days'
            """
            )

            # Очищення вирішених сповіщень (старші 30 днів)
            await conn.execute(
                """
                DELETE FROM security_alerts
                WHERE is_resolved = TRUE 
                AND resolved_at < NOW() - INTERVAL '30 days'
            """
            )

            logger.info("Очищення застарілих даних завершено")
    except Exception as e:
        logger.error(f"Помилка при очищенні даних: {str(e)}")


async def create_user(conn, username: str, password: str, email: str):
    try:
        password_hash = get_password_hash(password)
        query = """
        INSERT INTO users (username, password_hash, email)
        VALUES ($1, $2, $3)
        RETURNING id
        """
        user_id = await conn.fetchval(query, username, password_hash, email)
        return user_id
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=400, detail="Користувач з таким ім'ям вже існує")
    except Exception as e:
        logger.error(f"Помилка при створенні користувача: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при створенні користувача")


async def get_user_roles(conn, username: str) -> List[str]:
    query = """
    SELECT r.role_name
    FROM user_roles ur
    JOIN roles r ON ur.role_id = r.role_id
    WHERE ur.username = $1
    """
    roles = await conn.fetch(query, username)
    return [role["role_name"] for role in roles]


async def check_permission(conn, username: str, required_permission: str) -> bool:
    query = """
    SELECT EXISTS (
        SELECT 1 FROM user_roles ur
        JOIN role_permissions rp ON ur.role_id = rp.role_id
        JOIN permissions p ON rp.permission_id = p.permission_id
        WHERE ur.username = $1 AND p.permission_name = $2
    )
    """
    return await conn.fetchval(query, username, required_permission)


@with_connection
async def assign_role(conn, username: str, role_name: str):
    try:
        query = """
        INSERT INTO user_roles (username, role_id)
        SELECT $1, role_id FROM roles WHERE role_name = $2
        """
        await conn.execute(query, username, role_name)
        logger.info(f"Роль {role_name} призначено користувачу {username}")
    except Exception as e:
        logger.error(f"Помилка при призначенні ролі: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при призначенні ролі")


def require_permission(permission: str):
    def decorator(func):
        async def wrapper(*args, **kwargs):
            token = kwargs.get("token")
            if not token:
                raise HTTPException(status_code=401, detail="Токен не надано")

            pool = await get_pool()
            async with pool.acquire() as conn:
                user_data = await verify_token(conn, token)
                if not await check_permission(conn, user_data["username"], permission):
                    raise HTTPException(
                        status_code=403, detail="Недостатньо прав для виконання операції"
                    )
                return await func(*args, **kwargs)

        return wrapper

    return decorator


@with_connection
async def get_all_roles(conn) -> List[dict]:
    try:
        query = "SELECT role_id, role_name, description FROM roles"
        roles = await conn.fetch(query)
        return [dict(role) for role in roles]
    except Exception as e:
        logger.error(f"Помилка при отриманні ролей: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при отриманні ролей")


@with_connection
async def create_role(conn, role_name: str, description: str = None):
    try:
        query = """
        INSERT INTO roles (role_name, description)
        VALUES ($1, $2)
        RETURNING role_id
        """
        role_id = await conn.fetchval(query, role_name, description)
        logger.info(f"Створено нову роль: {role_name}")
        return role_id
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=400, detail="Роль з таким ім'ям вже існує")
    except Exception as e:
        logger.error(f"Помилка при створенні ролі: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при створенні ролі")


@with_connection
async def assign_permission_to_role(conn, role_name: str, permission_name: str):
    try:
        query = """
        INSERT INTO role_permissions (role_id, permission_id)
        SELECT r.role_id, p.permission_id
        FROM roles r, permissions p
        WHERE r.role_name = $1 AND p.permission_name = $2
        """
        await conn.execute(query, role_name, permission_name)
        logger.info(f"Додано дозвіл {permission_name} до ролі {role_name}")
    except Exception as e:
        logger.error(f"Помилка при призначенні дозволу: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при призначенні дозволу")


@with_connection
async def get_role_permissions(conn, role_name: str) -> List[str]:
    try:
        query = """
        SELECT p.permission_name
        FROM permissions p
        JOIN role_permissions rp ON p.permission_id = rp.permission_id
        JOIN roles r ON rp.role_id = r.role_id
        WHERE r.role_name = $1
        """
        permissions = await conn.fetch(query, role_name)
        return [p["permission_name"] for p in permissions]
    except Exception as e:
        logger.error(f"Помилка при отриманні дозволів: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при отриманні дозволів")


@with_connection
async def update_role(conn, role_id: int, role_name: str, description: str = None):
    try:
        query = """
        UPDATE roles 
        SET role_name = $2, description = $3
        WHERE role_id = $1
        RETURNING role_id
        """
        updated = await conn.fetchval(query, role_id, role_name, description)
        if not updated:
            raise HTTPException(status_code=404, detail="Роль не знайдено")
        logger.info(f"Оновлено роль: {role_name}")
        return updated
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=400, detail="Роль з таким ім'ям вже існує")
    except Exception as e:
        logger.error(f"Помилка при оновленні ролі: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при оновленні ролі")


@with_connection
async def delete_role(conn, role_name: str):
    try:
        query = "DELETE FROM roles WHERE role_name = $1 RETURNING role_id"
        deleted = await conn.fetchval(query, role_name)
        if not deleted:
            raise HTTPException(status_code=404, detail="Роль не знайдено")
        logger.info(f"Видалено роль: {role_name}")
    except Exception as e:
        logger.error(f"Помилка при видаленні ролі: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при видаленні ролі")


@with_connection
async def remove_permission_from_role(conn, role_name: str, permission_name: str):
    try:
        query = """
        DELETE FROM role_permissions 
        WHERE role_id = (SELECT role_id FROM roles WHERE role_name = $1)
        AND permission_id = (SELECT permission_id FROM permissions WHERE permission_name = $2)
        """
        await conn.execute(query, role_name, permission_name)
        logger.info(f"Видалено дозвіл {permission_name} з ролі {role_name}")
    except Exception as e:
        logger.error(f"Помилка при видаленні дозволу: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при видаленні дозволу")


@with_connection
async def log_user_activity(
    conn, username: str, action: str, details: dict = None, ip_address: str = None
):
    try:
        query = """
        INSERT INTO user_activity (username, action, details, ip_address)
        VALUES ($1, $2, $3, $4)
        """
        await conn.execute(query, username, action, details, ip_address)
        logger.info(f"Активність користувача {username}: {action}")
    except Exception as e:
        logger.error(f"Помилка при логуванні активності: {str(e)}")


@with_connection
async def get_user_activity(
    conn, username: str = None, start_date: date = None, end_date: date = None
) -> List[dict]:
    try:
        conditions = []
        params = []
        if username:
            conditions.append("username = $1")
            params.append(username)
        if start_date:
            conditions.append("created_at >= $" + str(len(params) + 1))
            params.append(start_date)
        if end_date:
            conditions.append("created_at <= $" + str(len(params) + 1))
            params.append(end_date)

        where_clause = " AND ".join(conditions) if conditions else "TRUE"

        query = f"""
        SELECT username, action, details, ip_address, created_at
        FROM user_activity
        WHERE {where_clause}
        ORDER BY created_at DESC
        """

        activities = await conn.fetch(query, *params)
        return [dict(activity) for activity in activities]
    except Exception as e:
        logger.error(f"Помилка при отриманні активності: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при отриманні активності")


@with_connection
async def block_user(conn, username: str, blocked_by: str):
    try:
        query = "UPDATE users SET is_blocked = TRUE WHERE username = $1"
        result = await conn.execute(query, username)
        if result == "UPDATE 0":
            raise HTTPException(status_code=404, detail="Користувача не знайдено")

        await log_user_activity(conn, blocked_by, "block_user", {"blocked_username": username})

        await terminate_all_sessions(username)
        logger.info(f"Користувача {username} заблоковано користувачем {blocked_by}")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Помилка при блокуванні користувача: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при блокуванні користувача")


@with_connection
async def remove_user_role(conn, username: str, role_name: str):
    try:
        query = """
        DELETE FROM user_roles 
        WHERE username = $1 AND role_id = (
            SELECT role_id FROM roles WHERE role_name = $2
        )
        """
        await conn.execute(query, username, role_name)
        logger.info(f"Видалено роль {role_name} у користувача {username}")
    except Exception as e:
        logger.error(f"Помилка при видаленні ролі користувача: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при видаленні ролі")


# Додаємо нові константи
PASSWORD_RESET_TOKEN_EXPIRE_MINUTES = 30
MIN_PASSWORD_LENGTH = 8


@with_connection
async def create_password_reset_token(conn, username: str) -> str:
    try:
        # Генеруємо токен
        token = secrets.token_urlsafe(32)
        expires_at = datetime.utcnow() + timedelta(minutes=PASSWORD_RESET_TOKEN_EXPIRE_MINUTES)

        # Деактивуємо старі токени
        await conn.execute(
            "UPDATE password_reset_tokens SET used = TRUE WHERE username = $1", username
        )

        # Створюємо новий токен
        await conn.execute(
            """
            INSERT INTO password_reset_tokens (token, username, expires_at)
            VALUES ($1, $2, $3)
        """,
            token,
            username,
            expires_at,
        )

        return token
    except Exception as e:
        logger.error(f"Помилка при створенні токену скидання паролю: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при створенні токену")


@with_connection
async def verify_password_reset_token(conn, token: str) -> str:
    try:
        result = await conn.fetchrow(
            """
            SELECT username, used, expires_at
            FROM password_reset_tokens
            WHERE token = $1
        """,
            token,
        )

        if not result:
            raise HTTPException(status_code=400, detail="Невірний токен")

        if result["used"]:
            raise HTTPException(status_code=400, detail="Токен вже використано")

        if datetime.utcnow() > result["expires_at"]:
            raise HTTPException(status_code=400, detail="Токен прострочено")

        return result["username"]
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Помилка при перевірці токену: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при перевірці токену")


@with_connection
async def reset_password(conn, token: str, new_password: str):
    try:
        username = await verify_password_reset_token(conn, token)

        # Перевіряємо складність пароля
        if not validate_password(new_password):
            raise HTTPException(status_code=400, detail="Пароль не відповідає вимогам безпеки")

        # Оновлюємо пароль
        password_hash = get_password_hash(new_password)
        await conn.execute(
            "UPDATE users SET password_hash = $1 WHERE username = $2", password_hash, username
        )

        # Позначаємо токен як використаний
        await conn.execute("UPDATE password_reset_tokens SET used = TRUE WHERE token = $1", token)

        # Логуємо подію
        await log_user_activity(conn, username, "password_reset")

        # Завершуємо всі сесії користувача
        await terminate_all_sessions(username)

        logger.info(f"Пароль успішно скинуто для користувача: {username}")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Помилка при скиданні паролю: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при скиданні паролю")


@with_connection
async def change_password(conn, username: str, current_password: str, new_password: str):
    try:
        # Перевіряємо поточний пароль
        user = await conn.fetchrow("SELECT password_hash FROM users WHERE username = $1", username)

        if not user or not verify_password(current_password, user["password_hash"]):
            raise HTTPException(status_code=400, detail="Невірний поточний пароль")

        # Перевіряємо новий пароль
        if not validate_password(new_password):
            raise HTTPException(
                status_code=400, detail="Новий пароль не відповідає вимогам безпеки"
            )

        # Оновлюємо пароль
        password_hash = get_password_hash(new_password)
        await conn.execute(
            "UPDATE users SET password_hash = $1 WHERE username = $2", password_hash, username
        )

        # Логуємо подію
        await log_user_activity(conn, username, "password_change")

        logger.info(f"Пароль успішно змінено для користувача: {username}")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Помилка при зміні паролю: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при зміні паролю")


@with_connection
async def setup_2fa(conn, username: str) -> dict:
    """Налаштування 2FA для користувача"""
    try:
        # Генеруємо секретний ключ
        secret = pyotp.random_base32()

        # Створюємо резервні коди
        backup_codes = [secrets.token_hex(4) for _ in range(8)]

        query = """
        INSERT INTO two_factor_auth (username, secret_key, backup_codes)
        VALUES ($1, $2, $3)
        ON CONFLICT (username) DO UPDATE 
        SET secret_key = $2, backup_codes = $3, updated_at = CURRENT_TIMESTAMP
        """
        await conn.execute(query, username, secret, backup_codes)

        # Створюємо URI для QR-коду
        totp = pyotp.TOTP(secret)
        provisioning_uri = totp.provisioning_uri(username, issuer_name="Predator Analytics")

        return {
            "secret": secret,
            "provisioning_uri": provisioning_uri,
            "backup_codes": backup_codes,
        }
    except Exception as e:
        logger.error(f"Помилка при налаштуванні 2FA: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при налаштуванні 2FA")


@with_connection
async def verify_2fa_token(conn, username: str, token: str) -> bool:
    """Перевірка 2FA токену"""
    try:
        result = await conn.fetchrow(
            "SELECT secret_key, backup_codes FROM two_factor_auth WHERE username = $1", username
        )

        if not result:
            return False

        # Перевіряємо чи це не резервний код
        if token in result["backup_codes"]:
            # Видаляємо використаний резервний код
            new_backup_codes = [code for code in result["backup_codes"] if code != token]
            await conn.execute(
                "UPDATE two_factor_auth SET backup_codes = $1 WHERE username = $2",
                new_backup_codes,
                username,
            )
            return True

        # Перевіряємо TOTP токен
        totp = pyotp.TOTP(result["secret_key"])
        return totp.verify(token)
    except Exception as e:
        logger.error(f"Помилка при перевірці 2FA: {str(e)}")
        return False


@with_connection
async def enable_2fa(conn, username: str, token: str) -> bool:
    """Активація 2FA після підтвердження"""
    if await verify_2fa_token(conn, username, token):
        try:
            await conn.execute(
                "UPDATE two_factor_auth SET is_enabled = TRUE WHERE username = $1", username
            )
            await log_user_activity(conn, username, "enable_2fa")
            return True
        except Exception as e:
            logger.error(f"Помилка при активації 2FA: {str(e)}")
            raise HTTPException(status_code=500, detail="Помилка при активації 2FA")
    return False


@with_connection
async def disable_2fa(conn, username: str):
    """Вимкнення 2FA"""
    try:
        await conn.execute(
            "UPDATE two_factor_auth SET is_enabled = FALSE WHERE username = $1", username
        )
        await log_user_activity(conn, username, "disable_2fa")
    except Exception as e:
        logger.error(f"Помилка при вимкненні 2FA: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при вимкненні 2FA")


@with_connection
async def get_2fa_status(conn, username: str) -> dict:
    """Отримання статусу 2FA для користувача"""
    try:
        result = await conn.fetchrow(
            """
            SELECT is_enabled, created_at, updated_at 
            FROM two_factor_auth 
            WHERE username = $1
        """,
            username,
        )

        if not result:
            return {"is_enabled": False, "is_configured": False}

        return {
            "is_enabled": result["is_enabled"],
            "is_configured": True,
            "created_at": result["created_at"],
            "updated_at": result["updated_at"],
        }
    except Exception as e:
        logger.error(f"Помилка при отриманні статусу 2FA: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при отриманні статусу 2FA")


async def cleanup_2fa_data():
    """Очищення старих даних 2FA"""
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            # Очищення відключених 2FA старших 30 днів
            await conn.execute(
                """
                DELETE FROM two_factor_auth 
                WHERE is_enabled = FALSE 
                AND updated_at < NOW() - INTERVAL '30 days'
            """
            )

            logger.info("Очищення старих даних 2FA завершено")
    except Exception as e:
        logger.error(f"Помилка при очищенні даних 2FA: {str(e)}")


@with_connection
async def regenerate_backup_codes(conn, username: str) -> List[str]:
    """Генерація нових резервних кодів для 2FA"""
    try:
        new_backup_codes = [secrets.token_hex(4) for _ in range(8)]
        await conn.execute(
            "UPDATE two_factor_auth SET backup_codes = $1 WHERE username = $2",
            new_backup_codes,
            username,
        )
        await log_user_activity(conn, username, "regenerate_2fa_backup_codes")
        return new_backup_codes
    except Exception as e:
        logger.error(f"Помилка при генерації резервних кодів: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при генерації резервних кодів")


@with_connection
async def get_auth_statistics(conn, username: str) -> dict:
    """Отримання статистики автентифікації користувача"""
    try:
        result = await conn.fetchrow(
            """
            SELECT successful_logins, failed_logins, 
                   last_successful_login, last_failed_login,
                   last_ip_address
            FROM auth_statistics
            WHERE username = $1
        """,
            username,
        )

        if not result:
            return {
                "successful_logins": 0,
                "failed_logins": 0,
                "last_successful_login": None,
                "last_failed_login": None,
                "last_ip_address": None,
            }

        return dict(result)
    except Exception as e:
        logger.error(f"Помилка при отриманні статистики: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при отриманні статистики")


@with_connection
async def update_auth_statistics(conn, username: str, success: bool, ip_address: str = None):
    """Оновлення статистики автентифікації"""
    try:
        if success:
            query = """
            INSERT INTO auth_statistics (
                username, last_successful_login, successful_logins, last_ip_address
            ) VALUES ($1, NOW(), 1, $2)
            ON CONFLICT (username) DO UPDATE SET
                last_successful_login = NOW(),
                successful_logins = auth_statistics.successful_logins + 1,
                last_ip_address = EXCLUDED.last_ip_address
            """
            await conn.execute(query, username, ip_address)
        else:
            query = """
            INSERT INTO auth_statistics (
                username, last_failed_login, failed_logins
            ) VALUES ($1, NOW(), 1)
            ON CONFLICT (username) DO UPDATE SET
                last_failed_login = NOW(),
                failed_logins = auth_statistics.failed_logins + 1
            """
            await conn.execute(query, username)
    except Exception as e:
        logger.error(f"Помилка при оновленні статистики: {str(e)}")


@with_connection
async def update_session_activity(conn, session_id: str, ip_address: str = None):
    """Оновлення часу останньої активності сесії"""
    try:
        query = """
        UPDATE user_sessions 
        SET last_activity = NOW(), ip_address = COALESCE($2, ip_address)
        WHERE session_id = $1
        """
        await conn.execute(query, session_id, ip_address)
    except Exception as e:
        logger.error(f"Помилка при оновленні активності сесії: {str(e)}")


@with_connection
async def get_active_sessions(conn, username: str) -> List[dict]:
    """Отримання всіх активних сесій користувача"""
    try:
        query = """
        SELECT session_id, created_at, last_activity, ip_address, device_info, is_suspicious
        FROM user_sessions
        WHERE username = $1 AND last_activity > NOW() - INTERVAL '24 hours'
        ORDER BY last_activity DESC
        """
        sessions = await conn.fetch(query, username)
        return [dict(session) for session in sessions]
    except Exception as e:
        logger.error(f"Помилка при отриманні активних сесій: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при отриманні сесій")


@with_connection
async def mark_session_suspicious(conn, session_id: str, activity_type: str, details: dict = None):
    """Позначення сесії як підозрілої"""
    try:
        async with conn.transaction():
            # Позначаємо сесію
            await conn.execute(
                "UPDATE user_sessions SET is_suspicious = TRUE WHERE session_id = $1", session_id
            )

            # Записуємо деталі підозрілої активності
            query = """
            INSERT INTO suspicious_activity (session_id, username, activity_type, details)
            SELECT $1, username, $2, $3 FROM user_sessions WHERE session_id = $1
            """
            await conn.execute(query, session_id, activity_type, details)

    except Exception as e:
        logger.error(f"Помилка при позначенні підозрілої сесії: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при обробці підозрілої активності")


@with_connection
async def analyze_user_sessions(conn, username: str) -> dict:
    """Аналіз сесій користувача на предмет підозрілої активності"""
    try:
        # Перевіряємо одночасні сесії з різних IP
        query = """
        SELECT COUNT(DISTINCT ip_address) as ip_count
        FROM user_sessions
        WHERE username = $1 
        AND last_activity > NOW() - INTERVAL '1 hour'
        """
        ip_count = await conn.fetchval(query, username)

        if ip_count > 3:  # Якщо більше 3 різних IP за годину
            await mark_session_suspicious(conn, None, "multiple_ips", {"ip_count": ip_count})

        # Отримуємо статистику підозрілої активності
        query = """
        SELECT activity_type, COUNT(*) as count
        FROM suspicious_activity
        WHERE username = $1
        AND created_at > NOW() - INTERVAL '24 hours'
        GROUP BY activity_type
        """
        activity_stats = await conn.fetch(query, username)

        return {
            "suspicious_ips": ip_count > 3,
            "activity_stats": [dict(stat) for stat in activity_stats],
        }
    except Exception as e:
        logger.error(f"Помилка при аналізі сесій: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при аналізі сесій")


# Додаємо константи для аналізу аномалій
UNUSUAL_TIME_START = time(23, 0)  # 23:00
UNUSUAL_TIME_END = time(5, 0)  # 05:00
MAX_DISTANCE_KM = 500  # Максимальна відстань між логінами
GEOIP_DATABASE = "/path/to/GeoLite2-City.mmdb"


@with_connection
async def log_user_location(conn, username: str, ip_address: str) -> dict:
    """Логування та аналіз географічної локації користувача"""
    try:
        with geoip2.database.Reader(GEOIP_DATABASE) as reader:
            response = reader.city(ip_address)
            location_data = {
                "country_code": response.country.iso_code,
                "city": response.city.name,
                "latitude": response.location.latitude,
                "longitude": response.location.longitude,
            }

            query = """
            INSERT INTO user_locations (username, ip_address, country_code, city, latitude, longitude)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id
            """
            await conn.execute(
                query,
                username,
                ip_address,
                location_data["country_code"],
                location_data["city"],
                location_data["latitude"],
                location_data["longitude"],
            )

            return location_data
    except Exception as e:
        logger.error(f"Помилка при логуванні локації: {str(e)}")
        return None


@with_connection
async def detect_location_anomalies(conn, username: str, current_location: dict) -> Optional[dict]:
    """Виявлення аномалій на основі географічної локації"""
    try:
        query = """
        SELECT latitude, longitude, last_seen
        FROM user_locations
        WHERE username = $1
        ORDER BY last_seen DESC
        LIMIT 1
        """
        last_location = await conn.fetchrow(query, username)

        if last_location:
            from geopy.distance import geodesic

            last_point = (last_location["latitude"], last_location["longitude"])
            current_point = (current_location["latitude"], current_location["longitude"])

            distance = geodesic(last_point, current_point).kilometers
            time_diff = datetime.utcnow() - last_location["last_seen"]

            if distance > MAX_DISTANCE_KM and time_diff.total_seconds() < 3600:
                await create_anomaly(
                    conn,
                    username,
                    "impossible_travel",
                    3,
                    {
                        "distance": distance,
                        "time_diff": time_diff.total_seconds(),
                        "from_location": last_point,
                        "to_location": current_point,
                    },
                )
                return {
                    "type": "impossible_travel",
                    "distance": distance,
                    "time_diff": time_diff.total_seconds(),
                }
    except Exception as e:
        logger.error(f"Помилка при виявленні аномалій локації: {str(e)}")
    return None


@with_connection
async def create_anomaly(
    conn, username: str, anomaly_type: str, severity: int, details: dict = None
):
    """Створення запису про аномалію"""
    try:
        query = """
        INSERT INTO user_anomalies (username, anomaly_type, severity, details)
        VALUES ($1, $2, $3, $4)
        RETURNING id
        """
        anomaly_id = await conn.fetchval(query, username, anomaly_type, severity, details)

        if severity >= 3:  # Висока серйозність
            await mark_session_suspicious(conn, None, anomaly_type, details)

        return anomaly_id
    except Exception as e:
        logger.error(f"Помилка при створенні аномалії: {str(e)}")
        return None


@with_connection
async def resolve_anomaly(conn, anomaly_id: int, resolved_by: str):
    """Позначення аномалії як вирішеної"""
    try:
        query = """
        UPDATE user_anomalies 
        SET resolved_at = NOW(), resolved_by = $2
        WHERE id = $1
        """
        await conn.execute(query, anomaly_id, resolved_by)
    except Exception as e:
        logger.error(f"Помилка при вирішенні аномалії: {str(e)}")


@with_connection
async def analyze_user_behavior(conn, username: str) -> dict:
    """Аналіз поведінки користувача та створення патернів"""
    try:
        # Аналізуємо часові патерни входу
        query = """
        SELECT EXTRACT(HOUR FROM created_at) as hour,
               COUNT(*) as login_count
        FROM user_sessions
        WHERE username = $1 
        AND created_at > NOW() - INTERVAL '30 days'
        GROUP BY EXTRACT(HOUR FROM created_at)
        """
        time_patterns = await conn.fetch(query, username)

        # Визначаємо типові години активності
        typical_hours = [
            int(record["hour"]) for record in time_patterns if record["login_count"] > 5
        ]

        # Зберігаємо патерн
        await conn.execute(
            """
            INSERT INTO user_behavior_patterns (username, pattern_type, pattern_data, confidence)
            VALUES ($1, 'login_time', $2, $3)
            ON CONFLICT (username, pattern_type) 
            DO UPDATE SET pattern_data = $2, confidence = $3, last_updated = NOW()
        """,
            username,
            {"typical_hours": typical_hours},
            0.8,
        )

        return {"typical_hours": typical_hours}
    except Exception as e:
        logger.error(f"Помилка при аналізі поведінки: {str(e)}")
        return None


@with_connection
async def calculate_risk_score(conn, username: str, current_activity: dict) -> int:
    """Розрахунок оцінки ризику для поточної активності"""
    try:
        risk_score = 0
        risk_factors = []

        # Перевіряємо час доступу
        current_hour = datetime.utcnow().hour
        patterns = await conn.fetchrow(
            """
            SELECT pattern_data
            FROM user_behavior_patterns
            WHERE username = $1 AND pattern_type = 'login_time'
        """,
            username,
        )

        if patterns and current_hour not in patterns["pattern_data"].get("typical_hours", []):
            risk_score += 20
            risk_factors.append("unusual_time")

        # Перевіряємо геолокацію
        if current_activity.get("ip_address"):
            location_check = await detect_location_anomalies(
                conn, username, current_activity.get("location_data", {})
            )
            if location_check:
                risk_score += 40
                risk_factors.append("suspicious_location")

        # Зберігаємо оцінку ризику
        await conn.execute(
            """
            INSERT INTO risk_assessments (username, risk_score, risk_factors)
            VALUES ($1, $2, $3)
        """,
            username,
            risk_score,
            {"factors": risk_factors},
        )

        return risk_score

    except Exception as e:
        logger.error(f"Помилка при розрахунку ризику: {str(e)}")
        return 0


@with_connection
async def get_user_risk_history(conn, username: str) -> List[dict]:
    """Отримання історії оцінок ризику для користувача"""
    try:
        query = """
        SELECT risk_score, risk_factors, assessed_at
        FROM risk_assessments
        WHERE username = $1
        ORDER BY assessed_at DESC
        LIMIT 10
        """
        history = await conn.fetch(query, username)
        return [dict(record) for record in history]
    except Exception as e:
        logger.error(f"Помилка при отриманні історії ризиків: {str(e)}")
        return []


@with_connection
async def record_security_metric(
    conn, metric_name: str, value: float, dimension: dict = None
) -> int:
    """Запис метрики безпеки"""
    try:
        query = """
        INSERT INTO security_metrics (metric_name, metric_value, dimension)
        VALUES ($1, $2, $3)
        RETURNING id
        """
        metric_id = await conn.fetchval(query, metric_name, value, dimension)

        # Перевіряємо пороги
        thresholds = await conn.fetchrow(
            """
            SELECT warning_threshold, critical_threshold 
            FROM metric_thresholds 
            WHERE metric_name = $1
        """,
            metric_name,
        )

        if thresholds:
            if value >= thresholds["critical_threshold"]:
                await create_security_alert(
                    conn,
                    "metric_threshold_exceeded",
                    5,
                    {
                        "metric": metric_name,
                        "value": value,
                        "threshold": thresholds["critical_threshold"],
                        "level": "critical",
                    },
                )
            elif value >= thresholds["warning_threshold"]:
                await create_security_alert(
                    conn,
                    "metric_threshold_exceeded",
                    3,
                    {
                        "metric": metric_name,
                        "value": value,
                        "threshold": thresholds["warning_threshold"],
                        "level": "warning",
                    },
                )

        return metric_id
    except Exception as e:
        logger.error(f"Помилка при записі метрики: {str(e)}")
        return None


@with_connection
async def calculate_security_metrics(conn) -> dict:
    """Розрахунок метрик безпеки"""
    try:
        metrics = {}

        # Коефіцієнт невдалих входів
        login_stats = await conn.fetchrow(
            """
            SELECT 
                COALESCE(SUM(failed_logins), 0) as total_failed,
                COALESCE(SUM(successful_logins), 0) as total_successful
            FROM auth_statistics
            WHERE last_successful_login > NOW() - INTERVAL '24 hours'
            OR last_failed_login > NOW() - INTERVAL '24 hours'
        """
        )

        total_attempts = login_stats["total_failed"] + login_stats["total_successful"]
        if total_attempts > 0:
            failed_rate = login_stats["total_failed"] / total_attempts
            await record_security_metric(conn, "failed_login_rate", failed_rate)
            metrics["failed_login_rate"] = failed_rate

        # Відсоток підозрілих сесій
        session_stats = await conn.fetchrow(
            """
            SELECT 
                COUNT(*) FILTER (WHERE is_suspicious) as suspicious,
                COUNT(*) as total
            FROM user_sessions
            WHERE last_activity > NOW() - INTERVAL '24 hours'
        """
        )

        if session_stats["total"] > 0:
            suspicious_rate = session_stats["suspicious"] / session_stats["total"]
            await record_security_metric(conn, "suspicious_sessions_rate", suspicious_rate)
            metrics["suspicious_sessions_rate"] = suspicious_rate

        return metrics
    except Exception as e:
        logger.error(f"Помилка при розрахунку метрик: {str(e)}")
        return {}


@with_connection
async def create_security_alert(conn, alert_type: str, severity: int, details: dict) -> int:
    """Створення сповіщення безпеки"""
    try:
        query = """
        INSERT INTO security_alerts (alert_type, severity, details)
        VALUES ($1, $2, $3)
        RETURNING id
        """
        alert_id = await conn.fetchval(query, alert_type, severity, details)
        logger.warning(f"Створено сповіщення безпеки: {alert_type} (severity: {severity})")
        return alert_id
    except Exception as e:
        logger.error(f"Помилка при створенні сповіщення: {str(e)}")
        return None


@with_connection
async def get_active_alerts(conn) -> List[dict]:
    """Отримання активних сповіщень"""
    try:
        query = """
        SELECT id, alert_type, severity, details, created_at
        FROM security_alerts
        WHERE NOT is_resolved
        ORDER BY severity DESC, created_at DESC
        """
        alerts = await conn.fetch(query)
        return [dict(alert) for alert in alerts]
    except Exception as e:
        logger.error(f"Помилка при отриманні сповіщень: {str(e)}")
        return []


@with_connection
async def resolve_alert(conn, alert_id: int, resolved_by: str):
    """Позначення сповіщення як вирішеного"""
    try:
        query = """
        UPDATE security_alerts
        SET is_resolved = TRUE, 
            resolved_at = NOW(),
            resolved_by = $2
        WHERE id = $1
        """
        await conn.execute(query, alert_id, resolved_by)
        logger.info(f"Сповіщення {alert_id} позначено як вирішене користувачем {resolved_by}")
    except Exception as e:
        logger.error(f"Помилка при вирішенні сповіщення: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при вирішенні сповіщення")


@with_connection
async def detect_attack_patterns(conn, username: str, activity_data: dict) -> List[dict]:
    """Виявлення шаблонів атак у активності користувача"""
    try:
        detected_patterns = []

        # Отримуємо всі шаблони атак
        patterns = await conn.fetch(
            """
            SELECT id, pattern_name, pattern_type, detection_rules, severity
            FROM attack_patterns
        """
        )

        for pattern in patterns:
            rules = pattern["detection_rules"]
            confidence = await evaluate_pattern_match(conn, username, rules, activity_data)

            if confidence > 0.7:  # Поріг впевненості
                attack_id = await conn.fetchval(
                    """
                    INSERT INTO detected_attacks 
                    (pattern_id, username, attack_data, confidence)
                    VALUES ($1, $2, $3, $4)
                    RETURNING id
                """,
                    pattern["id"],
                    username,
                    activity_data,
                    confidence,
                )

                detected_patterns.append(
                    {
                        "pattern_name": pattern["pattern_name"],
                        "confidence": confidence,
                        "severity": pattern["severity"],
                        "attack_id": attack_id,
                    }
                )

                # Створюємо сповіщення для серйозних атак
                if pattern["severity"] >= 4:
                    await create_security_alert(
                        conn,
                        f"attack_pattern_detected_{pattern['pattern_type']}",
                        pattern["severity"],
                        {
                            "pattern": pattern["pattern_name"],
                            "confidence": confidence,
                            "attack_data": activity_data,
                        },
                    )

        return detected_patterns
    except Exception as e:
        logger.error(f"Помилка при виявленні шаблонів атак: {str(e)}")
        return []


@with_connection
async def evaluate_pattern_match(conn, username: str, rules: dict, activity_data: dict) -> float:
    """Оцінка відповідності активності шаблону атаки"""
    try:
        confidence = 0.0
        conditions = rules.get("conditions", {})

        if "failed_attempts" in conditions:
            # Перевірка брутфорсу
            failed_count = await conn.fetchval(
                """
                SELECT COUNT(*) FROM user_activity
                WHERE username = $1 
                AND action = 'failed_login'
                AND created_at > NOW() - INTERVAL '1 minute' * $2
            """,
                username,
                conditions["time_window"].replace("m", ""),
            )

            if failed_count >= conditions["failed_attempts"]:
                confidence = 0.8 + (failed_count - conditions["failed_attempts"]) * 0.01

        if "unique_users" in conditions:
            # Перевірка password spray
            unique_users = await conn.fetchval(
                """
                SELECT COUNT(DISTINCT username) FROM user_activity
                WHERE action = 'failed_login'
                AND created_at > NOW() - INTERVAL '1 minute' * $1
            """,
                conditions["time_window"].replace("m", ""),
            )

            if unique_users >= conditions["unique_users"]:
                confidence = max(confidence, 0.9)

        return min(confidence, 1.0)
    except Exception as e:
        logger.error(f"Помилка при оцінці шаблону: {str(e)}")
        return 0.0


@with_connection
async def mark_false_positive(conn, attack_id: int, reviewer: str):
    """Позначення виявленої атаки як хибного спрацювання"""
    try:
        await conn.execute(
            """
            UPDATE detected_attacks
            SET is_false_positive = TRUE,
                reviewed_by = $2,
                reviewed_at = NOW()
            WHERE id = $1
        """,
            attack_id,
            reviewer,
        )

        logger.info(f"Атаку {attack_id} позначено як хибне спрацювання користувачем {reviewer}")
    except Exception as e:
        logger.error(f"Помилка при позначенні хибного спрацювання: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при оновленні статусу атаки")


@with_connection
async def generate_security_report(
    conn, report_type: str, period_start: datetime, period_end: datetime, generated_by: str
) -> dict:
    """Генерація аналітичного звіту безпеки"""
    try:
        metrics = {}
        insights = []
        recommendations = []

        # Збираємо базові метрики
        auth_metrics = await calculate_period_metrics(conn, period_start, period_end)
        metrics.update(auth_metrics)

        # Аналізуємо тенденції
        trends = await analyze_security_trends(conn, period_start, period_end)
        if trends:
            metrics["trends"] = trends

        # Генеруємо інсайти
        if metrics["failed_login_rate"] > 0.2:
            insights.append(
                {
                    "type": "high_failure_rate",
                    "description": "Високий рівень невдалих спроб входу",
                    "severity": "high",
                }
            )
            recommendations.append(
                {
                    "type": "security_measure",
                    "description": "Розглянути можливість впровадження додаткових заходів захисту",
                }
            )

        # Зберігаємо звіт
        report_id = await conn.fetchval(
            """
            INSERT INTO security_reports (
                report_type, period_start, period_end, 
                metrics, insights, recommendations, generated_by
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING id
        """,
            report_type,
            period_start,
            period_end,
            metrics,
            insights,
            recommendations,
            generated_by,
        )

        return {
            "id": report_id,
            "metrics": metrics,
            "insights": insights,
            "recommendations": recommendations,
        }
    except Exception as e:
        logger.error(f"Помилка при генерації звіту: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при генерації звіту")


@with_connection
async def calculate_period_metrics(conn, start: datetime, end: datetime) -> dict:
    """Розрахунок метрик за період"""
    try:
        metrics = {}

        # Статистика автентифікації
        auth_stats = await conn.fetchrow(
            """
            SELECT 
                COUNT(*) FILTER (WHERE action = 'login' AND details->>'success' = 'true') as successful_logins,
                COUNT(*) FILTER (WHERE action = 'login' AND details->>'success' = 'false') as failed_logins,
                COUNT(DISTINCT username) as unique_users,
                COUNT(DISTINCT ip_address) as unique_ips
            FROM user_activity
            WHERE created_at BETWEEN $1 AND $2
        """,
            start,
            end,
        )

        if auth_stats:
            total_attempts = auth_stats["successful_logins"] + auth_stats["failed_logins"]
            metrics.update(
                {
                    "successful_logins": auth_stats["successful_logins"],
                    "failed_logins": auth_stats["failed_logins"],
                    "unique_users": auth_stats["unique_users"],
                    "unique_ips": auth_stats["unique_ips"],
                    "failed_login_rate": (
                        auth_stats["failed_logins"] / total_attempts if total_attempts > 0 else 0
                    ),
                }
            )

        # Аномалії та підозріла активність
        anomaly_stats = await conn.fetchrow(
            """
            SELECT 
                COUNT(*) as total_anomalies,
                COUNT(*) FILTER (WHERE severity >= 4) as high_severity_anomalies
            FROM user_anomalies
            WHERE created_at BETWEEN $1 AND $2
        """,
            start,
            end,
        )

        if anomaly_stats:
            metrics.update(
                {
                    "total_anomalies": anomaly_stats["total_anomalies"],
                    "high_severity_anomalies": anomaly_stats["high_severity_anomalies"],
                }
            )

        return metrics
    except Exception as e:
        logger.error(f"Помилка при розрахунку метрик: {str(e)}")
        return {}


@with_connection
async def analyze_security_trends(conn, start: datetime, end: datetime) -> Optional[dict]:
    """Аналіз тенденцій безпеки"""
    try:
        # Отримуємо щоденні метрики
        daily_metrics = await conn.fetch(
            """
            SELECT 
                DATE_TRUNC('day', created_at) as day,
                COUNT(*) FILTER (WHERE details->>'success' = 'true') as successes,
                COUNT(*) FILTER (WHERE details->>'success' = 'false') as failures
            FROM user_activity
            WHERE created_at BETWEEN $1 AND $2
            AND action = 'login'
            GROUP BY DATE_TRUNC('day', created_at)
            ORDER BY day
        """,
            start,
            end,
        )

        if not daily_metrics:
            return None

        # Конвертуємо в pandas DataFrame для аналізу
        df = pd.DataFrame(
            [
                {
                    "day": record["day"],
                    "success_rate": (
                        record["successes"] / (record["successes"] + record["failures"])
                        if (record["successes"] + record["failures"]) > 0
                        else 0
                    ),
                }
                for record in daily_metrics
            ]
        )

        # Аналізуємо тренд
        trend_data = {
            "direction": (
                "increasing"
                if df["success_rate"].is_monotonic_increasing
                else "decreasing" if df["success_rate"].is_monotonic_decreasing else "fluctuating"
            ),
            "mean": float(df["success_rate"].mean()),
            "std": float(df["success_rate"].std()),
            "days_analyzed": len(df),
        }

        # Зберігаємо тренд
        await conn.execute(
            """
            INSERT INTO security_trends (
                trend_type, metric_name, trend_data, confidence
            )
            VALUES ($1, $2, $3, $4)
        """,
            "auth_success_rate",
            "login_success_rate",
            trend_data,
            0.8,
        )

        return trend_data
    except Exception as e:
        logger.error(f"Помилка при аналізі тенденцій: {str(e)}")
        return None


@with_connection
async def get_report_history(
    conn, report_type: str = None, start_date: date = None, end_date: date = None
) -> List[dict]:
    """Отримання історії звітів"""
    try:
        conditions = []
        params = []

        if report_type:
            conditions.append("report_type = $1")
            params.append(report_type)

        if start_date:
            conditions.append("period_start >= $" + str(len(params) + 1))
            params.append(start_date)

        if end_date:
            conditions.append("period_end <= $" + str(len(params) + 1))
            params.append(end_date)

        where_clause = " AND ".join(conditions) if conditions else "TRUE"

        query = f"""
        SELECT id, report_type, period_start, period_end,
               metrics, insights, recommendations, 
               created_at, generated_by
        FROM security_reports
        WHERE {where_clause}
        ORDER BY created_at DESC
        """

        reports = await conn.fetch(query, *params)
        return [dict(report) for report in reports]
    except Exception as e:
        logger.error(f"Помилка при отриманні звітів: {str(e)}")
        raise HTTPException(status_code=500, detail="Помилка при отриманні звітів")
