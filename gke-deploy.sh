#!/bin/bash

# Скрипт для розгортання Predator 5.0 на GKE

# Кольори для виводу
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Змінні для налаштування
PROJECT_ID="predator-project" # Замініть на ваш Project ID в GCP
CLUSTER_NAME="predator-cluster"
REGION="europe-west4"
NAMESPACE="predator"

# Логін і пароль
LOGIN="Dima1203"
PASSWORD="Emma0707@"

# Функція перевірки помилок
check_error() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Помилка виконання команди${NC}"
    exit 1
  fi
}

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

# Перевіряємо підключення до кластера
echo -e "${YELLOW}Перевірка підключення до кластера...${NC}"
kubectl get nodes || { echo -e "${RED}Помилка: кластер недоступний${NC}"; exit 1; }

# Налаштування Cloud SQL
echo -e "${YELLOW}Створення секрету для сервісного акаунта Cloud SQL...${NC}"
kubectl create namespace ${NAMESPACE} 2>/dev/null || true
kubectl create secret generic cloudsql-service-account \
    --namespace=${NAMESPACE} \
    --from-file=credentials.json=./service-account.json
if [ $? -ne 0 ]; then
    echo -e "${RED}Помилка створення секрету. Переконайтесь що файл service-account.json існує${NC}"
    exit 1
fi

# Розгортання Cloud SQL Proxy
echo -e "${YELLOW}Розгортання Cloud SQL Proxy...${NC}"
sed -i "s/PROJECT_ID:REGION:INSTANCE_NAME/${PROJECT_ID}:${REGION}:predator-db/" cloudsql-proxy.yaml
kubectl apply -f cloudsql-proxy.yaml
if [ $? -ne 0 ]; then
    echo -e "${RED}Помилка розгортання Cloud SQL Proxy${NC}"
    exit 1
fi

# Створення секрету для бази даних
echo -e "${YELLOW}Створення секрету для бази даних...${NC}"
DB_PASSWORD=$(openssl rand -base64 16)
kubectl create secret generic predator-db-credentials \
    --namespace=${NAMESPACE} \
    --from-literal=password=${DB_PASSWORD}
check_error
echo "${DB_PASSWORD}" > db-password.txt
echo -e "${GREEN}Пароль бази даних збережено у файлі db-password.txt${NC}"

# Створення постійного IP для Ingress
echo -e "${YELLOW}Створення постійного IP для Ingress...${NC}"
gcloud compute addresses create predator-static-ip --global
IP_ADDRESS=$(gcloud compute addresses describe predator-static-ip --global --format="value(address)")
echo -e "${GREEN}Створено IP: ${IP_ADDRESS}${NC}"

# Налаштування сертифіката
echo -e "${YELLOW}Налаштування сертифіката для домену...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: predator-certificate
  namespace: ${NAMESPACE}
spec:
  domains:
    - predator.example.com  # Замініть на власний домен
EOF

# Розгортання за допомогою Helm
echo -e "${YELLOW}Розгортання Predator 5.0 за допомогою Helm на GKE...${NC}"
helm upgrade --install predator ./helm/predator \
    --namespace=${NAMESPACE} \
    --values=./helm/predator/values-gke.yaml \
    --set ingress.hosts[0].host=predator.example.com \
    --set cloudsql.instanceConnectionName=${PROJECT_ID}:${REGION}:predator-db

echo -e "${BLUE}=======================================================================================${NC}"
echo -e "${GREEN}✅ Розгортання Predator 5.0 на GKE завершено!${NC}"
echo -e "${YELLOW}Ваш зовнішній IP: ${IP_ADDRESS}${NC}"
echo -e "${YELLOW}Налаштуйте DNS запис для predator.example.com, що вказує на ${IP_ADDRESS}${NC}"
echo -e "${YELLOW}Перевірити статус розгортання: kubectl get pods -n ${NAMESPACE}${NC}"
echo -e "${BLUE}=======================================================================================${NC}"
