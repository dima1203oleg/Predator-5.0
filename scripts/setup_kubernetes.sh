#!/bin/bash
set -e

echo "🔍 Перевірка встановлення розширення Kubernetes для VS Code..."
if ! code --list-extensions | grep -q ms-kubernetes-tools.vscode-kubernetes-tools; then
    echo "🚀 Встановлення розширення Kubernetes..."
    code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
else
    echo "✅ Розширення Kubernetes вже встановлено"
fi

echo "🔍 Перевірка підключення до Kubernetes-кластеру..."
# Якщо використовується GKE:
if command -v gcloud &> /dev/null; then
    echo "🔄 Авторизація у Google Cloud..."
    gcloud auth login
    echo "📋 Список кластерів:"
    gcloud container clusters list
    echo "🔄 Підключення до кластера predator-cluster..."
    gcloud container clusters get-credentials predator-cluster --zone us-central1-a
else
    # Якщо використовується локальний Kubernetes (Minikube)
    echo "🔄 Запуск локального Kubernetes (minikube)..."
    if ! command -v minikube &> /dev/null; then
        echo "❌ minikube не встановлено. Встановіть minikube."
        exit 1
    fi
    minikube start
    kubectl config use-context minikube
fi

echo "🔍 Перевірка підключення до кластера..."
kubectl cluster-info
kubectl get nodes

echo "🚀 Розгортання Predator 5.0 у Kubernetes..."
kubectl apply -f ../kubernetes/predator-deployment.yaml
kubectl apply -f ../kubernetes/predator-service.yaml

echo "🔍 Перевірка розгортання..."
kubectl get pods
kubectl get services

echo "🔍 Запуск Kubernetes Dashboard..."
if command -v minikube &> /dev/null; then
    minikube dashboard
else
    kubectl proxy &
    echo "Відкрийте у браузері: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
fi

echo "✅ Налаштування Kubernetes завершено!"
