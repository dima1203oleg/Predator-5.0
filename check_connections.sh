#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Логін і пароль
LOGIN="Dima1203"
PASSWORD="Emma0707@"

# Функція для перевірки логіна та пароля
verify_credentials() {
  echo -e "${YELLOW}Перевірка логіна та пароля...${NC}"
  if [ "$LOGIN" != "Dima1203" ] || [ "$PASSWORD" != "Emma0707@" ]; then
    echo -e "${RED}⚠️ Невірний логін або пароль. Міняємо місцями...${NC}"
    TEMP=$LOGIN
    LOGIN=$PASSWORD
    PASSWORD=$TEMP
    echo -e "${YELLOW}Новий логін: $LOGIN, Новий пароль: $PASSWORD${NC}"
  else
    echo -e "${GREEN}Логін і пароль коректні${NC}"
  fi
}

verify_credentials

echo -e "${YELLOW}Перевірка підключень для Predator 5.0 DevContainer${NC}"
echo "======================================================="

# Перевірка PostgreSQL
echo -n "Перевірка підключення до PostgreSQL: "
if pg_isready -h db -U postgres > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}ПОМИЛКА${NC}"
    echo "Спроба очікування запуску PostgreSQL..."
    for i in {1..30}; do
        if pg_isready -h db -U postgres > /dev/null 2>&1; then
            echo -e "${GREEN}PostgreSQL доступний після очікування!${NC}"
            break
        fi
        echo -n "."
        sleep 1
    done
    if ! pg_isready -h db -U postgres > /dev/null 2>&1; then
        echo -e "\n${RED}PostgreSQL недоступний після очікування${NC}"
    fi
fi

# Перевірка Redis
echo -n "Перевірка підключення до Redis: "
if redis-cli -h redis ping > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}ПОМИЛКА${NC}"
    echo "Спроба очікування запуску Redis..."
    for i in {1..30}; do
        if redis-cli -h redis ping > /dev/null 2>&1; then
            echo -e "${GREEN}Redis доступний після очікування!${NC}"
            break
        fi
        echo -n "."
        sleep 1
    done
    if ! redis-cli -h redis ping > /dev/null 2>&1; then
        echo -e "\n${RED}Redis недоступний після очікування${NC}"
    fi
fi

# Перевірка OpenSearch
echo -n "Перевірка підключення до OpenSearch: "
if curl -s -o /dev/null -w "%{http_code}" http://opensearch:9200 | grep -q "200"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}ПОМИЛКА${NC}"
    echo "Спроба очікування запуску OpenSearch..."
    for i in {1..30}; do
        if curl -s -o /dev/null -w "%{http_code}" http://opensearch:9200 | grep -q "200"; then
            echo -e "${GREEN}OpenSearch доступний після очікування!${NC}"
            break
        fi
        echo -n "."
        sleep 1
    done
    if ! curl -s -o /dev/null -w "%{http_code}" http://opensearch:9200 | grep -q "200"; then
        echo -e "\n${RED}OpenSearch недоступний після очікування${NC}"
    fi
fi

echo "======================================================="
echo -e "${GREEN}Середовище розробки Predator 5.0 готове до роботи!${NC}"
echo "Запустіть свій API-сервер командою: python manage.py runserver 0.0.0.0:8000"
echo "======================================================="
