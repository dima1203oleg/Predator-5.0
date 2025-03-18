#!/bin/bash

echo "🔍 Перевіряємо налаштування GitHub Actions..."

# Перевіряємо наявність файлів
files=(".github/workflows/ci.yml" ".github/workflows/deploy.yml" "sonar-project.properties" ".snyk")
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ Файл $file існує"
    else
        echo "❌ Файл $file відсутній"
        exit 1
    fi
done

# Перевіряємо токени
tokens=("GITHUB_TOKEN" "SONAR_TOKEN" "SNYK_TOKEN")
for token in "${tokens[@]}"; do
    if [ -z "${!token}" ]; then
        echo "❌ Відсутній $token"
        exit 1
    else
        echo "✅ $token налаштований"
    fi
done

# Запускаємо Python перевірки
python scripts/check_github_actions.py
python scripts/check_sonar_connection.py

echo "✅ Перевірка завершена"
