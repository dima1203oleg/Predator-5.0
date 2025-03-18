import pytest
from api.services.auth_service import get_pool


@pytest.mark.asyncio
async def test_database_connection():
    """Тест підключення до бази даних"""
    pool = await get_pool()
    async with pool.acquire() as conn:
        # Перевіряємо підключення
        result = await conn.fetchval("SELECT 1")
        assert result == 1

        # Перевіряємо наявність основних таблиць
        tables = await conn.fetch(
            """
            SELECT tablename FROM pg_tables 
            WHERE schemaname = 'public'
        """
        )
        table_names = {t["tablename"] for t in tables}

        required_tables = {"users", "roles", "permissions", "user_sessions", "security_alerts"}

        assert required_tables.issubset(
            table_names
        ), f"Відсутні необхідні таблиці: {required_tables - table_names}"

    await pool.close()
