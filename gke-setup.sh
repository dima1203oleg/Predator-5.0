#!/bin/bash

# Кольори для виводу
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Змінні для налаштування GKE
PROJECT_ID="predator-project" # Змініть на ваш Project ID в GCP
CLUSTER_NAME="predator-cluster"
REGION="europe-west4" # Змініть на потрібний регіон
ZONE="${REGION}-a" # Зона в регіоні
MACHINE_TYPE="e2-standard-2" # Тип машини
NODE_COUNT="3" # Кількість вузлів
K8S_VERSION="1.27" # Версія Kubernetes

# Функція перевірки помилок
check_error() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Помилка виконання команди${NC}"
    exit 1
  fi
}

echo -e "${BLUE}=======================================================================================${NC}"
echo -e "${GREEN}🚀 Початок налаштування Google Kubernetes Engine (GKE) для Predator 5.0${NC}"
echo -e "${BLUE}=======================================================================================${NC}"

# Перевірка наявності gcloud
echo -e "${YELLOW}Перевірка наявності Google Cloud SDK...${NC}"
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Google Cloud SDK не знайдено. Встановіть gcloud:${NC}"
    echo "https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Перевірка аутентифікації
echo -e "${YELLOW}Перевірка аутентифікації в Google Cloud...${NC}"
gcloud auth list | grep -q "ACTIVE"
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Необхідно авторизуватися в Google Cloud${NC}"
    gcloud auth login
    check_error
fi

# Встановлення активного проекту
echo -e "${YELLOW}Налаштування проекту...${NC}"
gcloud config set project ${PROJECT_ID}
check_error

# Увімкнення необхідних API
echo -e "${YELLOW}Увімкнення необхідних API...${NC}"
gcloud services enable container.googleapis.com
check_error

# Створення кластера
echo -e "${YELLOW}Створення GKE кластера ${CLUSTER_NAME}...${NC}"
echo -e "${BLUE}Це може зайняти кілька хвилин...${NC}"
gcloud container clusters create ${CLUSTER_NAME} \
    --region ${REGION} \
    --node-locations ${ZONE} \
    --num-nodes ${NODE_COUNT} \
    --machine-type ${MACHINE_TYPE} \
    --release-channel stable \
    --cluster-version ${K8S_VERSION} \
    --enable-ip-alias \
    --enable-autoscaling \
    --min-nodes 1 \
    --max-nodes 5 \
    --enable-autorepair \
    --enable-autoupgrade \
    --enable-network-policy \
    --workload-pool=${PROJECT_ID}.svc.id.goog
check_error

# Налаштування kubectl
echo -e "${YELLOW}Налаштування kubectl для роботи з кластером...${NC}"
gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION}
check_error

# Створення namespace для Predator
echo -e "${YELLOW}Створення namespace для Predator...${NC}"
kubectl create namespace predator
check_error

# Створення секрету для підключення до бази даних
echo -e "${YELLOW}Створення секрету для бази даних...${NC}"
kubectl create secret generic predator-db-credentials \
    --namespace=predator \
    --from-literal=password="$(openssl rand -base64 16)"
check_error

# Розгортання за допомогою Helm
echo -e "${YELLOW}Розгортання Predator 5.0 за допомогою Helm...${NC}"
helm upgrade --install predator ./helm/predator \
    --namespace predator \
    --set ingress.hosts[0].host=predator.${PROJECT_ID}.cloud.goog \
    --set ingress.enabled=true \
    --set ingress.className=gce \
    --set service.type=ClusterIP
check_error

echo -e "${BLUE}=======================================================================================${NC}"
echo -e "${GREEN}✅ Налаштування GKE для Predator 5.0 завершено!${NC}"
echo -e "${YELLOW}Ваш кластер: ${CLUSTER_NAME}${NC}"
echo -e "${YELLOW}Команда для отримання інформації про кластер: gcloud container clusters describe ${CLUSTER_NAME} --region ${REGION}${NC}"
echo -e "${YELLOW}Команда для перевірки подів: kubectl get pods -n predator${NC}"
echo -e "${BLUE}=======================================================================================${NC}"
