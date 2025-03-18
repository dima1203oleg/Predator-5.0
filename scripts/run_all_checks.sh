#!/bin/bash

echo "🔄 Запуск комплексної перевірки..."

# Перевіряємо SonarQube
python scripts/verify_connections.py

# Перевіряємо тести
pytest tests/test_security_setup.py -v

# Перевіряємо налаштування безпеки
python scripts/verify_security.py

# Запускаємо сканування
if [ $? -eq 0 ]; then
    echo "🔄 Запуск сканування..."
    sonar-scanner
else
    echo "❌ Перевірки не пройдені. Сканування відмінено."
    exit 1
fi
