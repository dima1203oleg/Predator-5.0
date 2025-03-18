#!/bin/bash
set -e

echo "🔍 Перевірка статусу контейнера PostgreSQL (predator50-db-1)..."
docker ps -a | grep predator50-db-1 || echo "Контейнер не знайдено"

# Якщо контейнер існує, перевіримо його стан та запустимо або перезапустимо, якщо потрібно
if docker ps -a | grep -q predator50-db-1; then
    status=$(docker inspect -f '{{.State.Status}}' predator50-db-1)
    echo "Статус контейнера: $status"
    if [ "$status" != "running" ]; then
        echo "🚀 Запуск контейнера predator50-db-1..."
        docker start predator50-db-1 || docker restart predator50-db-1
    else
        echo "✅ Контейнер вже запущений."
    fi
else
    echo "Контейнер predator50-db-1 відсутній. Розгортаємо через docker-compose..."
    docker-compose up -d
fi

echo "🔍 Перевірка логів контейнера:"
docker logs predator50-db-1

echo "Якщо в логах є критичні помилки (наприклад, FATAL: database files are corrupted):"
echo "   1. Зупиніть контейнер: docker stop predator50-db-1"
echo "   2. Видаліть контейнер: docker rm predator50-db-1"
echo "   3. Перезапустіть його: docker-compose up -d"

echo "🔍 Перевірка підключення до PostgreSQL..."
docker exec -it predator50-db-1 psql -U postgres || echo "Не вдалося підключитися до PostgreSQL"
