name: CI/CD Pipeline

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  POSTGRES_HOST: localhost
  POSTGRES_PORT: 5432
  POSTGRES_DB: test_db
  POSTGRES_USER: test_user
  POSTGRES_PASSWORD: test_password

jobs:
  build-and-test:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout repository
      uses: actions/checkout@v2

    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: '3.9'

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r requirements.txt

    - name: Run tests
      run: |
        pytest tests/docker-compose run --rm app pytest tests/docker-compose run --rm app pytest tests/git add .
git commit -m "Fix CI/CD issues"
git push origin mainimport pytest
import asyncio
import os
from datetime import datetime
from api.services.auth_service import get_pool

@pytest.fixture(scope="session")
def event_loop():
    """Фікстура для асинхронного циклу подій"""
    loop = asyncio.get_event_loop()
    yield loop
    loop.close()

@pytest.fixture(scope="session")
async def test_pool():
    """Фікстура для тестового пулу з'єднань"""
    pool = await get_pool()
    yield pool
    await pool.close()

@pytest.fixture(autouse=True)
async def setup_test_db(test_pool):
    """Налаштування тестової бази даних"""
    async with test_pool.acquire() as conn:
        # Очищаємо тестові дані
        await conn.execute("""
            DO $$ 
            BEGIN
                PERFORM truncate_tables();
            END $$;
        """)
        
        # Додаємо тестового користувача
        await conn.execute("""
            INSERT INTO users (username, password_hash, email)
            VALUES ($1, $2, $3)
        """, "test_user", "test_hash", "test@example.com")
    
    yield

@pytest.fixture(scope="function", autouse=True)
async def cleanup_database(test_pool):
    """Очищення бази даних перед кожним тестом"""
    async with test_pool.acquire() as conn:
        # Вимикаємо перевірку foreign key для очищення
        await conn.execute("SET session_replication_role = 'replica';")
        
        # Отримуємо всі таблиці
        tables = await conn.fetch("""
            SELECT tablename FROM pg_tables 
            WHERE schemaname = 'public'
        """)
        
        # Очищаємо кожну таблицю
        for table in tables:
            await conn.execute(f"TRUNCATE TABLE {table['tablename']} CASCADE;")
            
        # Повертаємо перевірку foreign key
        await conn.execute("SET session_replication_role = 'origin';")
        
    yield

@pytest.fixture(scope="function")
def sonarqube_mock():
    """Фікстура для моку SonarQube"""
    os.environ['SONAR_HOST_URL'] = 'http://localhost:9000'
    os.environ['SONAR_TOKEN'] = 'test-token'
    yield
    del os.environ['SONAR_HOST_URL']
    del os.environ['SONAR_TOKEN']
