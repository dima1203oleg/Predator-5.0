#!/bin/bash
set -e

echo "🔍 Перевірка підключення до Kubernetes..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Не вдалося отримати інформацію про кластер. Переконайтеся, що Kubernetes запущено."
    exit 1
fi
echo "✅ Підключення до кластера встановлено."

echo "🚀 Розгортання Predator 5.0..."
kubectl apply -f ../kubernetes/predator-deployment.yaml
kubectl apply -f ../kubernetes/predator-service.yaml

echo "🔍 Перевірка статусу розгортання..."
kubectl get pods
kubectl get services

echo "🔄 Оновлення Cloud Explorer у VS Code..."
code --command "vscode-kubernetes-tools.refreshCloudExplorer" || echo "Не вдалося оновити Cloud Explorer."

echo "✅ Розгортання завершено успішно!"
