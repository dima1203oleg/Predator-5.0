#!/bin/bash
set -e

echo "🔄 Запуск локального Kubernetes (minikube)..."
if ! minikube status &> /dev/null; then
    minikube start
fi
kubectl config use-context minikube

echo "🔍 Перевірка підключення до кластера..."
kubectl cluster-info || { echo "❌ Не вдалося підключитися до кластера"; exit 1; }

echo "✅ Кластер запущено та налаштовано"
