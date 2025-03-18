#!/bin/bash

# Кольори для виводу
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Змінні для налаштування
DEFAULT_CLUSTER_NAME="predator-cluster"
DEFAULT_REGION="us-central1"

print_header() {
  echo -e "\n${BLUE}⸻${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${BLUE}⸻${NC}\n"
}

check_success() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Успішно${NC}"
    return 0
  else
    echo -e "${RED}❌ Помилка${NC}"
    return 1
  fi
}

create_cluster_prompt() {
  echo -e "${YELLOW}Кластер не знайдено. Бажаєте створити новий? (y/n)${NC}"
  read -p "> " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Створення кластера ${DEFAULT_CLUSTER_NAME} у регіоні ${DEFAULT_REGION}...${NC}"
    echo -e "${YELLOW}Це може зайняти 5-10 хвилин...${NC}"
    gcloud container clusters create-auto ${DEFAULT_CLUSTER_NAME} --region ${DEFAULT_REGION}
    if check_success; then
      echo -e "${GREEN}Кластер успішно створено!${NC}"
    else
      echo -e "${RED}Не вдалося створити кластер. Перевірте наявність прав та інших помилок.${NC}"
    fi
  else
    echo -e "${YELLOW}Ви обрали не створювати кластер. Для продовження потрібен активний Kubernetes-кластер.${NC}"
  fi
}

# 1. Перевірка наявності Google Cloud SDK
print_header "1️⃣ Перевірка наявності Google Cloud SDK"
echo -n "Перевірка версії gcloud: "
gcloud --version | head -n 1
check_success

if [ $? -ne 0 ]; then
  echo -e "${RED}Google Cloud SDK не встановлено. Будь ласка, встановіть його за інструкцією:${NC}"
  echo -e "https://cloud.google.com/sdk/docs/install"
  exit 1
fi

# 2. Перевірка автентифікації
print_header "2️⃣ Перевірка автентифікації в Google Cloud"
echo -n "Поточний обліковий запис: "
ACCOUNT=$(gcloud config list account --format="value(core.account)")
if [ -z "$ACCOUNT" ]; then
  echo -e "${YELLOW}Ви не увійшли до облікового запису Google Cloud. Увійдіть зараз:${NC}"
  gcloud auth login
  check_success
  if [ $? -ne 0 ]; then
    echo -e "${RED}Не вдалося увійти до облікового запису. Спробуйте знову пізніше.${NC}"
    exit 1
  fi
  ACCOUNT=$(gcloud config list account --format="value(core.account)")
fi
echo -e "${GREEN}$ACCOUNT${NC}"

# 3. Перевірка вибраного проекту
print_header "3️⃣ Перевірка вибраного проєкту"
echo -n "Поточний проєкт: "
PROJECT=$(gcloud config list project --format="value(core.project)")
if [ -z "$PROJECT" ]; then
  echo -e "${YELLOW}Проєкт не вибрано. Доступні проєкти:${NC}"
  gcloud projects list
  echo -e "${YELLOW}Введіть ID проєкту, який бажаєте використовувати:${NC}"
  read -p "> " project_id
  gcloud config set project $project_id
  check_success
  if [ $? -ne 0 ]; then
    echo -e "${RED}Не вдалося встановити проєкт. Перевірте правильність введеного ID.${NC}"
    exit 1
  fi
  PROJECT=$project_id
fi
echo -e "${GREEN}$PROJECT${NC}"

# 4. Перевірка активації Kubernetes Engine API
print_header "4️⃣ Перевірка активації Kubernetes Engine API"
echo -n "Перевірка активації API: "
if gcloud services list --enabled | grep -q container.googleapis.com; then
  echo -e "${GREEN}API активовано${NC}"
else
  echo -e "${YELLOW}Kubernetes Engine API не активовано. Активуємо його:${NC}"
  gcloud services enable container.googleapis.com
  check_success
  if [ $? -ne 0 ]; then
    echo -e "${RED}Не вдалося активувати API. Перевірте наявність необхідних прав.${NC}"
    exit 1
  fi
fi

# 5. Перевірка наявності кластера
print_header "5️⃣ Перевірка наявності Kubernetes-кластера"
echo -e "Пошук доступних кластерів:"
gcloud container clusters list
if [ $? -ne 0 ] || [ -z "$(gcloud container clusters list 2>/dev/null)" ]; then
  echo -e "${YELLOW}Кластери не знайдено.${NC}"
  create_cluster_prompt
else
  echo -e "${GREEN}Знайдено кластер(и).${NC}"
  
  # Якщо є більше одного кластера, запитати, який використовувати
  if [ $(gcloud container clusters list --format="value(name)" | wc -l) -gt 1 ]; then
    echo -e "${YELLOW}Доступно кілька кластерів. Введіть назву кластера, який хочете використовувати:${NC}"
    gcloud container clusters list --format="table(name, location, status)"
    read -p "> " cluster_name
    read -p "Введіть регіон кластера: " cluster_region
  else
    cluster_name=$(gcloud container clusters list --format="value(name)")
    cluster_region=$(gcloud container clusters list --format="value(location)")
    echo -e "${YELLOW}Буде використано кластер: ${cluster_name} у регіоні ${cluster_region}${NC}"
  fi
fi

# 6. Перевірка підключення до кластера
print_header "6️⃣ Перевірка з'єднання з Kubernetes-кластером"
echo -e "${YELLOW}Отримання облікових даних для кластера...${NC}"
if [ -z "$cluster_name" ]; then
  cluster_name=$DEFAULT_CLUSTER_NAME
  cluster_region=$DEFAULT_REGION
fi

gcloud container clusters get-credentials $cluster_name --region $cluster_region
check_success
if [ $? -ne 0 ]; then
  echo -e "${RED}Не вдалося отримати облікові дані для кластера.${NC}"
  exit 1
fi

echo -e "${YELLOW}Перевірка доступу до кластера:${NC}"
kubectl get nodes
check_success
if [ $? -ne 0 ]; then
  echo -e "${RED}Не вдалося отримати доступ до вузлів кластера.${NC}"
  exit 1
fi

# 7. Розгортання тестового додатку
print_header "7️⃣ Розгортання тестового додатку для перевірки"
echo -e "${YELLOW}Бажаєте розгорнути тестовий додаток для перевірки функціональності кластера? (y/n)${NC}"
read -p "> " deploy_test

if [[ "$deploy_test" =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Створення тестового розгортання...${NC}"
  
  # Використовуємо існуючі файли з проекту
  kubectl apply -f deployment.yaml
  kubectl apply -f service.yaml
  
  echo -e "${YELLOW}Перевірка успішності розгортання:${NC}"
  kubectl get deployment my-application
  kubectl get pods -l app=my-application
  kubectl get service my-application-service
  
  echo -e "${YELLOW}Тестування доступу до додатку через port-forwarding:${NC}"
  echo -e "${YELLOW}(Запускаємо на 5 секунд)${NC}"
  kubectl port-forward service/my-application-service 8080:80 &
  PF_PID=$!
  sleep 2
  curl -s -m 3 http://localhost:8080 > /dev/null && echo -e "${GREEN}✅ HTTP-запит успішний${NC}" || echo -e "${RED}❌ Помилка HTTP-запиту${NC}"
  sleep 3
  kill $PF_PID 2>/dev/null
fi

# Підсумок
print_header "📊 Підсумок перевірки Google Cloud та Kubernetes"
echo -e "${GREEN}✅ Google Cloud SDK встановлено та налаштовано${NC}"
echo -e "${GREEN}✅ Обліковий запис: ${ACCOUNT}${NC}"
echo -e "${GREEN}✅ Поточний проєкт: ${PROJECT}${NC}"
echo -e "${GREEN}✅ Kubernetes Engine API активовано${NC}"
echo -e "${GREEN}✅ Кластер ${cluster_name} доступний у регіоні ${cluster_region}${NC}"
echo -e "${GREEN}✅ Підключення до Kubernetes функціонує${NC}"

echo -e "\n${BLUE}⸻${NC}"
echo -e "${GREEN}🎉 Всі перевірки успішні! Ваше середовище Google Cloud та Kubernetes налаштовано правильно.${NC}"
echo -e "${BLUE}⸻${NC}\n"

# Рекомендації щодо подальших дій
echo -e "${CYAN}Рекомендації щодо подальших дій:${NC}"
echo -e "1. Розгортайте додатки у кластері за допомогою ${YELLOW}kubectl apply -f your-manifest.yaml${NC}"
echo -e "2. Налаштуйте CI/CD за допомогою ${YELLOW}ArgoCD${NC} чи ${YELLOW}Google Cloud Build${NC}"
echo -e "3. Використовуйте ${YELLOW}Helm${NC} для розгортання складних додатків"
echo -e "4. Налаштуйте моніторинг за допомогою ${YELLOW}Prometheus та Grafana${NC}"
echo -e "5. Вивчіть ${YELLOW}kubectl${NC} команди: get, describe, logs, port-forward, exec"

echo -e "\n${YELLOW}Для отримання додаткової інформації про ваш кластер:${NC}"
echo -e "  kubectl cluster-info"
echo -e "  kubectl get all --all-namespaces"
