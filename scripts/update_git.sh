#!/bin/bash

echo "🔄 Оновлення коду з Git..."

# Зберігаємо поточні зміни
if [ -n "$(git status --porcelain)" ]; then
    echo "📦 Зберігаємо поточні зміни..."
    git stash save "Автоматичне збереження перед оновленням"
fi

# Перевіряємо поточну гілку
current_branch=$(git branch --show-current)
echo "📍 Поточна гілка: $current_branch"

# Отримуємо останні зміни
echo "⬇️ Отримуємо останні зміни..."
git fetch origin

# Оновлюємо main
echo "🔄 Оновлюємо main..."
git checkout main
git pull origin main

# Повертаємося на робочу гілку
if [ "$current_branch" != "main" ]; then
    echo "🔄 Повертаємося на гілку $current_branch..."
    git checkout $current_branch
    git merge main --no-ff
fi

# Відновлюємо збережені зміни
if [ -n "$(git stash list)" ]; then
    echo "📦 Відновлюємо збережені зміни..."
    git stash pop
fi

# Перевіряємо статус
echo "✅ Статус репозиторію:"
git status

echo "🎉 Оновлення завершено!"
