#!/bin/bash

echo "🔧 Налаштування тестового середовища..."

# Встановлюємо необхідні інструменти
xcode-select --install

# Налаштовуємо змінні середовища для компіляції
export CFLAGS="-I$(pyenv prefix)/include/python3.12"
export LDFLAGS="-L$(pyenv prefix)/lib"

# Створюємо віртуальне середовище
python -m venv venv
source venv/bin/activate

# Встановлюємо залежності
pip install --upgrade pip wheel setuptools
pip install numpy  # Встановлюємо numpy перед pandas
pip install -r requirements.txt

# Встановлюємо тестові залежності
pip install pytest pytest-asyncio pytest-cov pytest-mock pytest-env

echo "✅ Тестове середовище налаштовано"

# Запускаємо тести
pytest tests/ -v --maxfail=3 --disable-warnings --tb=short --cov=.
