#!/bin/bash
set -e

echo "🔄 Активація GitHub CLI (gh)..."

if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) не встановлено. Встановіть його, наприклад, через Homebrew:"
    echo "brew install gh"
    exit 1
fi

echo "✅ GitHub CLI знайдено. Запускаємо авторизацію..."
gh auth login

echo "✅ GitHub авторизація завершена. Перевірте статус:"
gh auth status
