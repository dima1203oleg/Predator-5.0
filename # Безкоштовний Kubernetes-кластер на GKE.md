# Безкоштовний Kubernetes-кластер на GKE Autopilot

Цей посібник допоможе вам налаштувати та використовувати безкоштовний Kubernetes-кластер на Google Kubernetes Engine в режимі Autopilot.

## 📚 Зміст

- [Передумови](#передумови)
- [Швидкий старт](#швидкий-старт)
- [Компоненти системи](#компоненти-системи)
- [Доступ до веб-інтерфейсів](#доступ-до-веб-інтерфейсів)
- [Розгортання застосунків](#розгортання-застосунків)
- [Моніторинг](#моніторинг)
- [Збереження даних](#збереження-даних)
- [Масштабування](#масштабування)
- [Обмеження безкоштовного рівня](#обмеження-безкоштовного-рівня)
- [Поширені проблеми](#поширені-проблеми)

## 📋 Передумови

1. Акаунт Google Cloud (можна створити безкоштовно)
2. Активована платіжна картка (для верифікації, гроші не списуються в рамках Free Tier)
3. Встановлений Google Cloud SDK
4. Встановлений kubectl

## 🚀 Швидкий старт

### Автоматичне налаштування

Для автоматичного налаштування всього кластера виконайте:

```bash
# Зробіть скрипт виконуваним
chmod +x gke-autopilot-setup.sh

# Запустіть скрипт
./gke-autopilot-setup.sh
```

Скрипт виконає:
1. Створення проекту в Google Cloud
2. Створення кластера GKE Autopilot
3. Налаштування Nginx Ingress
4. Встановлення ArgoCD
5. Встановлення Prometheus і Grafana
6. Налаштування Persistent Storage
7. Налаштування Horizontal Pod Autoscaler

### Ручне налаштування

Якщо ви хочете налаштувати окремі компоненти вручну:

#### 1. Створення кластера GKE Autopilot

```bash
gcloud container clusters create-auto predator-cluster \
    --region us-central1 \
    --project your-project-id
```

#### 2. Підключення до кластера

```bash
gcloud container clusters get-credentials predator-cluster \
    --region us-central1 \
    --project your-project-id
```

## 🧩 Компоненти системи

Після налаштування у вас буде доступно:

- **GKE Autopilot кластер** - автоматично керований Kubernetes кластер
- **ArgoCD** - GitOps інструмент для автоматичного розгортання
- **Nginx Ingress** - контролер для маршрутизації HTTP-трафіку
- **Prometheus** - система збору метрик
- **Grafana** - система візуалізації метрик
- **Persistent Storage** - постійне сховище для даних
- **HPA** - автоматичне горизонтальне масштабування подів

## 🌐 Доступ до веб-інтерфейсів

### ArgoCD

```bash
# Перенаправлення порту
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Отримання пароля (якщо ви не зберегли його під час налаштування)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Відкрийте у браузері: https://localhost:8080 (логін: admin)

### Grafana

```bash
# Перенаправлення порту
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Отримання пароля (якщо ви не зберегли його під час налаштування)
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

Відкрийте у браузері: http://localhost:3000 (логін: admin)

## 📦 Розгортання застосунків

### Через kubectl

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
```

### Через ArgoCD

1. Увійдіть у веб-інтерфейс ArgoCD
2. Натисніть "NEW APP"
3. Заповніть форму:
   - Application Name: my-app
   - Project: default
   - Repository URL: URL вашого Git-репозиторію
   - Path: шлях до маніфестів K8s в репозиторії
   - Cluster: https://kubernetes.default.svc (для поточного кластера)
   - Namespace: predator (або ваш namespace)
4. Натисніть "CREATE"

## 📊 Моніторинг

Після налаштування ви маєте доступ до повноцінного моніторингу через Grafana:

1. Відкрийте Grafana (див. розділ "Доступ до веб-інтерфейсів")
2. Перегляньте готові дашборди для:
   - Kubernetes Cluster
   - Kubernetes Pods
   - Kubernetes Nodes
   - Prometheus

## 💾 Збереження даних

Для збереження даних використовуйте Persistent Volume Claims:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
  namespace: predator
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

Приклад використання PVC у деплойменті:

```yaml
volumes:
- name: data-volume
  persistentVolumeClaim:
    claimName: my-data
containers:
- name: app
  volumeMounts:
  - mountPath: "/data"
    name: data-volume
```

## ⚖️ Масштабування

Система підтримує автоматичне масштабування через HPA:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

## ⚠️ Обмеження безкоштовного рівня

GKE Autopilot Free Tier має такі обмеження:
- 2 vCPU
- 1 GB RAM
- 30 GB дискового простору
- 1 безкоштовний балансувальник навантаження

Після перевищення цих лімітів починається тарифікація.

## 🔧 Поширені проблеми

### Помилка "Quota exceeded"

Можливе рішення: перевірте ліміти квот у Google Cloud Console і за потреби запросіть збільшення.

### Недоступний Ingress

Можливе рішення:
1. Перевірте статус Ingress: `kubectl get ingress -n predator`
2. Перевірте логи контролера: `kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller`

### Невдале створення PVC

Можливе рішення: 
1. Перевірте статус PVC: `kubectl get pvc -n predator`
2. Переконайтеся, що розмір PVC не перевищує безкоштовні 30 GB
```

Це автоматично налаштована безкоштовна система Kubernetes, яка містить всі необхідні компоненти для розробки та тестування.
