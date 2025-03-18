#!/bin/bash

echo "🔄 Налаштування SonarScanner..."

# Перевіряємо наявність sonar-scanner
if ! command -v sonar-scanner &> /dev/null; then
    echo "❌ SonarScanner не встановлено"
    exit 1
fi

# Створюємо конфігурацію
mkdir -p ~/.sonar
cat > ~/.sonar/sonar-scanner.properties << EOF
sonar.host.url=http://localhost:9000
sonar.login=ae5fe5168d12c610c7b94cdb641b53e1c54c0654
sonar.sourceEncoding=UTF-8
EOF

echo "✅ SonarScanner налаштовано"

# Тестуємо підключення
python scripts/verify_sonar.py
