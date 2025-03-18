#!/bin/bash
set -e

echo "🔍 Перевірка пайплайнів CI/CD..."

# Перевірка наявності конфігураційних файлів для пайплайнів
files=(
  ".github/workflows/ci.yml"
  ".github/workflows/deploy.yml"
  "sonar-project.properties"
  ".snyk"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ Файл $file існує"
    else
        echo "❌ Файл $file відсутній"
    fi
done

# Виклик перевірки конфігурації GitHub Actions (з уже існуючим скриптом)
python scripts/check_github_actions.py

echo "✅ Перевірка пайплайнів завершена"
