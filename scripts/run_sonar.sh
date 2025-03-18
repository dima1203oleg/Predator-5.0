#!/bin/bash

echo "🔄 Запуск аналізу SonarQube..."

# Перевіряємо наявність налаштувань
if [ ! -f "sonar-project.properties" ]; then
    echo "❌ Відсутній файл налаштувань sonar-project.properties"
    echo "🔄 Запускаємо налаштування..."
    python scripts/setup_sonar.py
fi

# Генеруємо звіт покриття
pytest tests/ --cov=predator_analytics --cov-report=xml

# Запускаємо сканування
sonar-scanner

echo "✅ Аналіз завершено"
