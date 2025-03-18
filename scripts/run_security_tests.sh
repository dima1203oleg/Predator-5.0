#!/bin/bash

echo "🔍 Запуск тестів безпеки..."

# Встановлюємо тестові змінні оточення
export SONAR_HOST_URL="http://localhost:9000"
export SONAR_TOKEN="test-token"
export SNYK_TOKEN="test-snyk-token"
export GITHUB_TOKEN="test-github-token"

# Запускаємо тести
pytest tests/test_security_setup.py -v

# Запускаємо перевірки
python scripts/verify_security.py
python scripts/verify_system.py
python scripts/verify_all.py

echo "✅ Тестування завершено"
