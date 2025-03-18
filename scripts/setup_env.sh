#!/bin/bash

echo "🔧 Налаштування середовища розробки..."

# Встановлюємо Xcode Command Line Tools
echo "📦 Перевірка Command Line Tools..."
if ! command -v xcode-select &> /dev/null; then
    xcode-select --install
fi

# Налаштовуємо змінні середовища для компіляції
export CFLAGS="-I$(pyenv prefix)/include/python3.12"
export LDFLAGS="-L$(pyenv prefix)/lib"

# Створюємо віртуальне середовище
echo "🐍 Створення віртуального середовища..."
python -m venv venv
source venv/bin/activate

# Оновлюємо pip та встановлюємо базові інструменти
echo "📚 Встановлення базових пакетів..."
pip install --upgrade pip wheel setuptools

# Встановлюємо numpy окремо
echo "🔢 Встановлення numpy..."
pip install numpy

# Встановлюємо всі залежності
echo "📦 Встановлення залежностей..."
pip install -r requirements.txt

# Перевіряємо встановлення
echo "✅ Перевірка встановлення..."
python -c "import pandas; import asyncpg; print('Встановлення успішне!')"

echo "🎉 Налаштування завершено!"
