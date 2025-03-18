# Налаштування Google Kubernetes Engine (GKE) для Predator 5.0

Цей документ містить інструкції з налаштування Predator 5.0 у середовищі GKE, з наступними компонентами:
- Kubernetes-кластер із автоматичним масштабуванням
- PostgreSQL у Google Cloud SQL
- Google Cloud Storage для зберігання даних
- Інтеграція з Ollama для AI-обробки
- CI/CD через GitHub Actions

## Передумови

1. Встановлений та налаштований [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
2. Активний проєкт у Google Cloud Platform
3. Увімкнені API:
   - container.googleapis.com
   - sqladmin.googleapis.com
   - logging.googleapis.com
4. Права на створення кластерів та ресурсів

## Швидкий старт

### 1. Налаштування кластера GKE

Запустіть скрипт:
```bash
chmod +x gke-setup.sh
./gke-setup.sh
```

### 2. Розгортання Predator 5.0

Запустіть скрипт для деплойменту:
```bash
chmod +x gke-deploy.sh
./gke-deploy.sh
```

### 3. CI/CD через GitHub Actions

Створіть файл `.github/workflows/deploy-predator.yml` (див. нижче).

## Моніторинг та Логи

- Логування: Stackdriver
- Моніторинг: Prometheus + Grafana (доступ через port-forward)

## Додаткова інформація

- Для підключення до бази даних, PostgreSQL запускається у Cloud SQL.
- Для зберігання даних використовується Google Cloud Storage.

*Якщо виникнуть проблеми – надайте логи для подальшої діагностики.*
