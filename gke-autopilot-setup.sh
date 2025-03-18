#!/bin/bash

# Кольори для виводу
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Змінні для налаштування
PROJECT_NAME="predator-k8s"
CLUSTER_NAME="predator-cluster"
REGION="us-central1"
NAMESPACE="predator"

# Функція перевірки помилок
check_error() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Помилка виконання команди${NC}"
    exit 1
  else
    echo -e "${GREEN}✓ Команда виконана успішно${NC}"
  fi
}

print_section() {
  echo -e "\n${BLUE}=======================================================================================${NC}"
  echo -e "${CYAN}🔹 $1${NC}"
  echo -e "${BLUE}=======================================================================================${NC}"
}

# СЕКЦІЯ 1: НАЛАШТУВАННЯ GOOGLE CLOUD
print_section "1️⃣ Налаштування Google Cloud"

echo -e "${YELLOW}Перевірка наявності gcloud...${NC}"
if ! command -v gcloud &> /dev/null; then
    echo -e "${YELLOW}Встановлення Google Cloud SDK...${NC}"
    curl https://sdk.cloud.google.com | bash
    exec -l $SHELL
    gcloud init
    check_error
else
    echo -e "${GREEN}✓ Google Cloud SDK вже встановлено${NC}"
fi

echo -e "${YELLOW}Створення нового проекту (якщо не існує)...${NC}"
gcloud projects describe $PROJECT_NAME &> /dev/null || gcloud projects create $PROJECT_NAME
check_error
gcloud config set project $PROJECT_NAME
check_error

echo -e "${YELLOW}Увімкнення необхідних API сервісів...${NC}"
gcloud services enable container.googleapis.com
check_error
gcloud services enable compute.googleapis.com
check_error
gcloud services enable monitoring.googleapis.com
check_error
gcloud services enable logging.googleapis.com
check_error

# СЕКЦІЯ 2: СТВОРЕННЯ KUBERNETES КЛАСТЕРА В РЕЖИМІ AUTOPILOT
print_section "2️⃣ Автоматичне створення Kubernetes-кластера"

echo -e "${YELLOW}Створення GKE Autopilot кластера ${CLUSTER_NAME}...${NC}"
echo -e "${BLUE}Це може зайняти 5-10 хвилин...${NC}"
gcloud container clusters create-auto $CLUSTER_NAME \
    --region $REGION \
    --project $PROJECT_NAME \
    --release-channel=regular
check_error

echo -e "${YELLOW}Налаштування kubectl для роботи з кластером...${NC}"
gcloud container clusters get-credentials $CLUSTER_NAME \
    --region $REGION \
    --project $PROJECT_NAME
check_error

echo -e "${YELLOW}Перевірка доступу до кластера...${NC}"
kubectl get nodes
check_error

# СЕКЦІЯ 3: АВТОМАТИЗАЦІЯ РОЗГОРТАННЯ (HELM + ARGOCD)
print_section "3️⃣ Автоматизація розгортання (Helm + ArgoCD)"

echo -e "${YELLOW}Встановлення Helm (якщо не встановлено)...${NC}"
if ! command -v helm &> /dev/null; then
    echo -e "${YELLOW}Встановлення Helm...${NC}"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    check_error
else
    echo -e "${GREEN}✓ Helm вже встановлено${NC}"
fi

echo -e "${YELLOW}Додавання репозиторію Helm...${NC}"
helm repo add stable https://charts.helm.sh/stable
helm repo update
check_error

echo -e "${YELLOW}Створення namespace для ArgoCD...${NC}"
kubectl create namespace argocd
check_error

echo -e "${YELLOW}Встановлення ArgoCD...${NC}"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
check_error

echo -e "${YELLOW}Очікування запуску ArgoCD...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
check_error

echo -e "${YELLOW}Отримання пароля адміністратора ArgoCD...${NC}"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo -e "${GREEN}ArgoCD пароль адміністратора: ${ARGOCD_PASSWORD}${NC}"
echo "$ARGOCD_PASSWORD" > argocd-admin-password.txt
echo -e "${GREEN}Пароль збережено у файлі argocd-admin-password.txt${NC}"

echo -e "${YELLOW}Налаштування доступу до ArgoCD через Port-Forward...${NC}"
echo -e "${BLUE}Щоб отримати доступ до веб-інтерфейсу ArgoCD, виконайте команду:${NC}"
echo -e "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo -e "${BLUE}Після цього відкрийте у браузері: https://localhost:8080${NC}"
echo -e "${BLUE}Логін: admin, Пароль: ${ARGOCD_PASSWORD}${NC}"

# СЕКЦІЯ 4: БАЛАНСУВАННЯ НАВАНТАЖЕННЯ (NGINX INGRESS CONTROLLER)
print_section "4️⃣ Балансування навантаження (Nginx Ingress)"

echo -e "${YELLOW}Створення namespace для Nginx Ingress...${NC}"
kubectl create namespace ingress-nginx
check_error

echo -e "${YELLOW}Встановлення Nginx Ingress Controller...${NC}"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --set controller.publishService.enabled=true
check_error

echo -e "${YELLOW}Очікування запуску Ingress Controller...${NC}"
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s
check_error

echo -e "${YELLOW}Отримання зовнішньої IP Ingress Controller...${NC}"
INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo -e "${GREEN}Ingress Controller IP: ${INGRESS_IP}${NC}"
echo "$INGRESS_IP" > ingress-ip.txt
echo -e "${GREEN}IP збережено у файлі ingress-ip.txt${NC}"

# СЕКЦІЯ 5: СТВОРЕННЯ РОБОЧОГО ПРОСТОРУ ТА ОСНОВНИХ РЕСУРСІВ
print_section "5️⃣ Створення робочого простору та основних ресурсів"

echo -e "${YELLOW}Створення namespace для додатків...${NC}"
kubectl create namespace $NAMESPACE
check_error

# Створення базового deplyment.yaml
cat > deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: predator-app
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: predator
  template:
    metadata:
      labels:
        app: predator
    spec:
      containers:
      - name: predator
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: "0.5"
            memory: "512Mi"
          requests:
            cpu: "0.2"
            memory: "256Mi"
EOF

echo -e "${YELLOW}Створення Deployment...${NC}"
kubectl apply -f deployment.yaml
check_error

# Створення service.yaml
cat > service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: predator-service
  namespace: $NAMESPACE
spec:
  selector:
    app: predator
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF

echo -e "${YELLOW}Створення Service...${NC}"
kubectl apply -f service.yaml
check_error

# Створення ingress.yaml
cat > ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: predator-ingress
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: predator.example.com  # Змініть на власний домен
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: predator-service
            port:
              number: 80
EOF

echo -e "${YELLOW}Створення Ingress...${NC}"
kubectl apply -f ingress.yaml
check_error

# СЕКЦІЯ 6: ЗБЕРЕЖЕННЯ ДАНИХ (PERSISTENT STORAGE)
print_section "6️⃣ Збереження даних (Persistent Storage)"

cat > pvc.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: predator-data
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

echo -e "${YELLOW}Створення PersistentVolumeClaim...${NC}"
kubectl apply -f pvc.yaml
check_error

# СЕКЦІЯ 7: МОНІТОРИНГ ТА ЛОГИ (PROMETHEUS + GRAFANA)
print_section "7️⃣ Моніторинг та Логи (Prometheus + Grafana)"

echo -e "${YELLOW}Створення namespace для моніторингу...${NC}"
kubectl create namespace monitoring
check_error

echo -e "${YELLOW}Встановлення Prometheus і Grafana...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring
check_error

echo -e "${YELLOW}Очікування запуску Prometheus і Grafana...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/prometheus-kube-prometheus-operator -n monitoring
check_error

echo -e "${YELLOW}Отримання пароля Grafana...${NC}"
GRAFANA_PASSWORD=$(kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
echo -e "${GREEN}Grafana пароль адміністратора: ${GRAFANA_PASSWORD}${NC}"
echo "$GRAFANA_PASSWORD" > grafana-admin-password.txt
echo -e "${GREEN}Пароль збережено у файлі grafana-admin-password.txt${NC}"

echo -e "${YELLOW}Налаштування доступу до Grafana через Port-Forward...${NC}"
echo -e "${BLUE}Щоб отримати доступ до веб-інтерфейсу Grafana, виконайте команду:${NC}"
echo -e "kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80"
echo -e "${BLUE}Після цього відкрийте у браузері: http://localhost:3000${NC}"
echo -e "${BLUE}Логін: admin, Пароль: ${GRAFANA_PASSWORD}${NC}"

# СЕКЦІЯ 8: АВТОМАТИЧНЕ МАСШТАБУВАННЯ (HPA)
print_section "8️⃣ Автоматичне масштабування (HPA)"

cat > hpa.yaml << EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: predator-hpa
  namespace: $NAMESPACE
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: predator-app
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
EOF

echo -e "${YELLOW}Створення Horizontal Pod Autoscaler...${NC}"
kubectl apply -f hpa.yaml
check_error

# СЕКЦІЯ 9: ПЕРЕВІРКА СТАТУСУ ВСТАНОВЛЕНИХ КОМПОНЕНТІВ
print_section "9️⃣ Перевірка статусу встановлених компонентів"

echo -e "${YELLOW}Перевірка статусу подів...${NC}"
kubectl get pods -n $NAMESPACE
echo -e "\n${YELLOW}Перевірка статусу подів ArgoCD...${NC}"
kubectl get pods -n argocd
echo -e "\n${YELLOW}Перевірка статусу подів Nginx Ingress...${NC}"
kubectl get pods -n ingress-nginx
echo -e "\n${YELLOW}Перевірка статусу подів моніторингу...${NC}"
kubectl get pods -n monitoring
echo -e "\n${YELLOW}Перевірка статусу PVC...${NC}"
kubectl get pvc -n $NAMESPACE
echo -e "\n${YELLOW}Перевірка статусу HPA...${NC}"
kubectl get hpa -n $NAMESPACE
echo -e "\n${YELLOW}Перевірка статусу сервісів...${NC}"
kubectl get services -n $NAMESPACE
echo -e "\n${YELLOW}Перевірка статусу Ingress...${NC}"
kubectl get ingress -n $NAMESPACE

# ФІНАЛЬНЕ ПОВІДОМЛЕННЯ
print_section "📌 Висновок"

echo -e "${GREEN}✅ GKE Autopilot кластер успішно створено і налаштовано!${NC}"
echo -e "${GREEN}✅ Встановлено всі необхідні компоненти:${NC}"
echo -e "   - ArgoCD для автоматичного розгортання"
echo -e "   - Nginx Ingress для маршрутизації трафіку"
echo -e "   - Prometheus і Grafana для моніторингу"
echo -e "   - Persistent Storage для збереження даних"
echo -e "   - Horizontal Pod Autoscaler для автоматичного масштабування"

echo -e "\n${YELLOW}Важлива інформація для доступу:${NC}"
echo -e "Кластер: ${CLUSTER_NAME} в регіоні ${REGION}"
echo -e "IP адреса Ingress: ${INGRESS_IP}" 
echo -e "ArgoCD пароль адміністратора збережено у файлі argocd-admin-password.txt"
echo -e "Grafana пароль адміністратора збережено у файлі grafana-admin-password.txt"

echo -e "\n${YELLOW}Для доступу до веб-інтерфейсів:${NC}"
echo -e "ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo -e "Grafana: kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80"

echo -e "\n${GREEN}🚀 Ваш безкоштовний Kubernetes-кластер готовий до використання!${NC}"
echo -e "${BLUE}=======================================================================================${NC}"
