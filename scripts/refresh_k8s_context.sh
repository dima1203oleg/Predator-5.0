#!/bin/bash
set -e

echo "🔍 Перевірка Kubernetes-кластеру через kubectl..."

# Перевірка інформації про кластер
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Не вдалося отримати інформацію про кластер (connection refused)."
    echo "🔄 Спробуйте запустити локальний кластер (Minikube)..."
    
    if command -v minikube &> /dev/null; then
        echo "🚀 Запуск minikube..."
        minikube start
        kubectl config use-context minikube
    else
        echo "❌ Minikube не встановлено. Переконайтеся, що ви підключені до GKE або іншого кластера."
        exit 1
    fi
fi

echo "✅ Інформація про кластер:"
kubectl cluster-info

echo "🔍 Перевірка вузлів:"
kubectl get nodes

echo "🔍 Перевірка подів у всіх просторах:"
kubectl get pods -A

# Викликаємо команду для оновлення Cloud Explorer у VS Code (якщо ваша версія VS Code підтримує цей виклик)
code --command "vscode-kubernetes-tools.refreshCloudExplorer" || echo "Не вдалося викликати команду оновлення Cloud Explorer"

echo "✅ Оновлення контексту Kubernetes завершено! Якщо кластер все ще не відображається, перезапустіть VS Code."
