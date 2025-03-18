#!/bin/bash
set -e

echo "=== Налаштування Python-середовища ==="
# Перевірка наявності Python3, якщо не встановлено – встановити через brew
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 не знайдено. Встановіть його через brew:"
    echo "brew install python"
    exit 1
fi
python3 --version

echo "Перевірка pip та venv..."
python3 -m ensurepip --upgrade
python3 -m venv venv

echo "Активуємо віртуальне середовище..."
source venv/bin/activate

echo "Оновлюємо pip..."
pip install --upgrade pip

echo "Встановлення залежностей з requirements.txt..."
if [ -f requirements.txt ]; then
    pip install -r requirements.txt
else
    echo "❌ Файл requirements.txt відсутній"
    exit 1
fi

echo "Перевірка модуля requests..."
python3 -c "import requests; print('Requests version:', requests.__version__)"

echo "=== Налаштування Kubernetes (kubectl) ==="
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl не знайдено. Встановіть його через brew:"
    echo "brew install kubectl"
    exit 1
fi
kubectl version --client

echo "Перевірка підключення до Kubernetes-кластера..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Кластер недоступний."
    echo "Якщо використовуєте GKE, виконайте:"
    echo "gcloud container clusters get-credentials <cluster-name> --zone <your-zone> --project <your-project>"
    echo "Або запустіть локальний Kubernetes (Minikube):"
    echo "minikube start && kubectl config use-context minikube"
    exit 1
else
    echo "✅ Кластер доступний"
fi

echo "Розгортання Predator 5.0 у Kubernetes..."
if [ -f deploy.yaml ]; then
    kubectl apply -f deploy.yaml
else
    echo "❌ Файл deploy.yaml відсутній, перевірте налаштування розгортання!"
fi

echo "Перевірка запущених подів та сервісів..."
kubectl get pods
kubectl get services

echo "=== Інтеграція з VS Code ==="
echo "Встановлення розширень VS Code..."
code --install-extension ms-vscode-remote.remote-containers || true
code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools || true
code --install-extension ms-python.python || true

echo "Перезапустіть VS Code для застосування змін."
echo "=== Налаштування завершено ==="
