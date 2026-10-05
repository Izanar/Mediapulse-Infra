#!/usr/bin/env bash
set -e

echo "🚀 Автоматический запуск инфраструктурных GUI & Дашбордов..."

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

# 2. Ожидание готовности подов Dashboard
echo "⏳ Проверка готовности Kubernetes Dashboard..."
kubectl wait --namespace kubernetes-dashboard \
  --for=condition=ready pod \
  --selector=k8s-app=kubernetes-dashboard \
  --timeout=60s &>/dev/null || true

# 3. Генерация токена доступа
echo "🔑 Ваша авторизационный токен для Kubernetes Dashboard:"
echo "------------------------------------------------------------------------"
TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)
echo "$TOKEN"
echo "------------------------------------------------------------------------"

# 4. Фоновый проброс портов для ArgoCD и K8s Dashboard
echo "🌐 Запуск веб-интерфейсов..."
echo "  • ArgoCD UI: https://localhost:8080"
echo "  • K8s Dashboard: https://localhost:8443"

# Убиваем прошлые процессы port-forward, если они висели
pkill -f "port-forward.*argocd-server" || true
pkill -f "port-forward.*kubernetes-dashboard" || true

# Запускаем фоновые туннели
kubectl port-forward svc/argocd-server -n argocd 8080:443 &>/dev/null &
kubectl port-forward svc/kubernetes-dashboard -n kubernetes-dashboard 8443:443 &>/dev/null &

echo "✅ Все сервисы подняты и доступны в браузере!"
# Копируем токен прямо в буфер обмена Windows
echo "$TOKEN" | clip.exe
echo "📋 Токен автоматически скопирован в буфер обмена! Просто нажмите Ctrl+V в браузере."