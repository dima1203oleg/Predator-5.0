#!/bin/bash

set -e

echo "────────────────────────────────────────────"
echo "1. Оновлення локальної гілки"
echo "────────────────────────────────────────────"
# Виконуємо оновлення з Git
git pull
git checkout main  # або твоя робоча гілка
git merge origin/main

echo "────────────────────────────────────────────"
echo "2. Перевірка файлів GitHub Actions"
echo "────────────────────────────────────────────"
ls -la .github/workflows/

echo "────────────────────────────────────────────"
echo "3. Запуск локальних тестів"
echo "────────────────────────────────────────────"
pytest --maxfail=3 --disable-warnings --tb=short --cov=.

echo "────────────────────────────────────────────"
echo "4. Перевірка змінних середовища (SONAR)"
echo "────────────────────────────────────────────"
printenv | grep SONAR

echo "────────────────────────────────────────────"
echo "5. Перевірка версій Docker та Docker Compose"
echo "────────────────────────────────────────────"
docker --version
docker-compose --version

echo "────────────────────────────────────────────"
echo "6. Перевірка конфігурації Docker (тестове середовище)"
echo "────────────────────────────────────────────"
docker-compose -f docker-compose.test.yml up --build --abort-on-container-exit

echo "────────────────────────────────────────────"
echo "7. Перевірка SonarQube"
echo "────────────────────────────────────────────"
python scripts/verify_sonar_secrets.py

echo "────────────────────────────────────────────"
echo "8. Завершальна перевірка GitHub Actions"
echo "────────────────────────────────────────────"
echo "Перевірте результати у вкладці Actions на GitHub."
echo "Якщо всі кроки успішні, можна пушити main для продакшн-розгортання."

chmod +x scripts/complete_ci_cd_check.sh
./scripts/complete_ci_cd_check.sh
