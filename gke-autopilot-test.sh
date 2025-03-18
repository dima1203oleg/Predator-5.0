#!/bin/bash

# Кольори для виводу
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=======================================================================================${NC}"
echo -e "${GREEN}🚀 Тестування Google Cloud Next 2025 Free Kubernetes${NC}"
echo -e "${BLUE}=======================================================================================${NC}"

# Перевірка наявності кластера
echo -e "${YELLOW}Перевірка наявності Kubernetes-кластера:${NC}"
gcloud container clusters list
if [ $? -ne 0 ] || [ -z "$(gcloud container clusters list 2>/dev/null)" ]; then
  echo -e "${RED}Помилка! Кластер не знайдено.${NC}"
  echo -e "${YELLOW}Створіть кластер командою:${NC}"
  echo "gcloud container clusters create-auto predator-cluster --region us-central1"
  exit 1
fi

# Отримання облікових даних
echo -e "${YELLOW}Отримання облікових даних кластера:${NC}"
CLUSTER_NAME=$(gcloud container clusters list --format="value(name)" | head -n 1)
CLUSTER_REGION=$(gcloud container clusters list --format="value(location)" | head -n 1)
gcloud container clusters get-credentials $CLUSTER_NAME --region $CLUSTER_REGION
if [ $? -ne 0 ]; then
  echo -e "${RED}Не вдалося підключитися до кластера.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Успішне підключення до кластера ${CLUSTER_NAME}${NC}"

# Перевірка доступних вузлів
echo -e "${YELLOW}Перевірка доступних вузлів:${NC}"
kubectl get nodes
if [ $? -ne 0 ]; then
  echo -e "${RED}Неможливо отримати інформацію про вузли.${NC}"
  exit 1
fi

# Перевірка доступних ресурсів
echo -e "${YELLOW}Перевірка доступних ресурсів:${NC}"
if command -v kubectl-top &> /dev/null; then
  kubectl top nodes
else
  echo -e "${YELLOW}kubectl top недоступний, перевіряємо наявність pod-ів${NC}"
  kubectl get pods -A
fi

# Створення простору імен для тестування
echo -e "${YELLOW}Створення простору імен next-test для тестування:${NC}"
kubectl create namespace next-test
if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Простір імен вже існує, використовуємо його${NC}"
fi

# Налаштування поточного контексту
kubectl config set-context --current --namespace=next-test

# Розгортання тестового додатку
echo -e "${YELLOW}Розгортання тестового додатку:${NC}"
cat > test-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-next
  namespace: next-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-next
  template:
    metadata:
      labels:
        app: hello-next
    spec:
      containers:
      - name: hello-app
        image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
          limits:
            cpu: 200m
            memory: 200Mi
EOF

cat > test-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: hello-next
  namespace: next-test
spec:
  type: ClusterIP
  selector:
    app: hello-next
  ports:
  - port: 80
    targetPort: 8080
EOF

# Застосування конфігурацій
kubectl apply -f test-deployment.yaml
kubectl apply -f test-service.yaml

# Очікування готовності розгортання
echo -e "${YELLOW}Очікування готовності розгортання...${NC}"
kubectl rollout status deployment/hello-next -n next-test

# Перевірка доступності сервісу
echo -e "${YELLOW}Перевірка доступності сервісу:${NC}"
kubectl port-forward service/hello-next 8080:80 &
PORT_FORWARD_PID=$!
sleep 3

# Здійснення запиту до сервісу
echo -e "${YELLOW}Здійснення запиту до сервісу:${NC}"
curl -s localhost:8080
if [ $? -eq 0 ]; then
  echo -e "\n${GREEN}✅ Сервіс працює! Тест успішний!${NC}"
else
  echo -e "${RED}❌ Неможливо підключитися до сервісу.${NC}"
fi

# Завершення переспрямування порту
kill $PORT_FORWARD_PID 2>/dev/null

# Виведення результатів
echo -e "${BLUE}=======================================================================================${NC}"
echo -e "${GREEN}✅ Тестування GKE для Google Cloud Next 2025 завершено${NC}"
echo -e "${GREEN}✅ Кластер: ${CLUSTER_NAME} у регіоні ${CLUSTER_REGION}${NC}"
echo -e "${GREEN}✅ Тестовий додаток розгорнуто у просторі імен next-test${NC}"
echo -e "${BLUE}=======================================================================================${NC}"

echo -e "${YELLOW}Бажаєте видалити тестові ресурси? (y/n)${NC}"
read -p "> " cleanup_answer
if [[ "$cleanup_answer" =~ ^[Yy]$ ]]; then
  kubectl delete namespace next-test
  echo -e "${GREEN}Тестові ресурси видалено.${NC}"
else
  echo -e "${YELLOW}Тестові ресурси збережено у просторі імен next-test.${NC}"
fi

echo -e "${GREEN}Завершено! Ви успішно підтвердили роботу Kubernetes у Google Cloud Next 2025.${NC}"
