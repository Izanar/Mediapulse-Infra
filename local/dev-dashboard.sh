#!/usr/bin/env bash
set -e

echo "🚀 Автоматический запуск инфраструктурных GUI & Дашбордов через Ingress..."

# 1. Установка Kubernetes Dashboard, если он еще не развернут
if ! kubectl get ns kubernetes-dashboard &>/dev/null; then
    echo "📦 Установка Kubernetes Dashboard..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
    
    echo "🔐 Настройка сервисного аккаунта администратора..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
fi

# 2. Применение Ingress манифестов для дашбордов
echo "🌐 Применение Ingress маршрутизации..."
kubectl apply -f local/argocd-ingress.yaml 2>/dev/null || kubectl apply -f argocd-ingress.yaml || true
kubectl apply -f local/dashboard-ingress.yaml 2>/dev/null || kubectl apply -f dashboard-ingress.yaml || true

# 3. Ожидание готовности подов Dashboard
echo "⏳ Проверка готовности Kubernetes Dashboard..."
kubectl wait --namespace kubernetes-dashboard \
  --for=condition=ready pod \
  --selector=k8s-app=kubernetes-dashboard \
  --timeout=60s &>/dev/null || true

# 4. Генерация токена доступа для K8s Dashboard
echo "🔑 Ваш авторизационный токен для Kubernetes Dashboard:"
echo "------------------------------------------------------------------------"
TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)
echo "$TOKEN"
echo "------------------------------------------------------------------------"

echo "✅ Вся инфраструктура и Ingress маршрутизаторы успешно запущены!"
echo "  • ArgoCD UI:           https://argocd.local"
echo "  • K8s Dashboard:       https://dashboard.local"

# Копируем токен в буфер обмена Windows, если доступно
if command -v clip.exe &> /dev/null; then
    echo "$TOKEN" | clip.exe
    echo "📋 Токен автоматически скопирован в буфер обмена!"
fi