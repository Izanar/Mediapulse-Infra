#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/routes"
ARGOCD_HOST="argocd.local"
TRAEFIK_HOST="traefik.local"

echo "🚀 Настройка локальных дашбордов и Ingress-маршрутов..."

# 1. Установка Kubernetes Dashboard и прав доступа
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

# 2. # Ждем, пока ArgoCD установит Traefik и появятся его CRD
echo "⏳ Ожидание установки Traefik и его CRD в кластере..."
for _ in $(seq 1 60); do
    if kubectl get crd ingressroutes.traefik.io &>/dev/null; then
        echo "✅ CRD Traefik обнаружены!"
        break
    fi
    sleep 3
done

# 3. Применение локальных Ingress манифестов из папки routes
echo "🌐 Применение Ingress маршрутизации..."
kubectl apply -f "$MANIFESTS_DIR/argocd-ingress.yaml"
kubectl apply -f "$MANIFESTS_DIR/k8s-dashboard-ingress.yaml"
kubectl apply -f "$MANIFESTS_DIR/mediapulse-ingress.yaml"
kubectl apply -f "$MANIFESTS_DIR/traefik-ingress.yaml"

# 4. Проверка доступности ArgoCD UI
echo "🔍 Проверка доступности UI..."
code="000"
for _ in $(seq 1 12); do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
        --resolve "$ARGOCD_HOST:443:127.0.0.1" "https://$ARGOCD_HOST/" || echo 000)
    [ "$code" = "200" ] && break
    sleep 3
done

if [ "$code" != "200" ]; then
    echo "❌ ArgoCD UI недоступен (код $code)."
    kubectl -n argocd get ingressroute || true
    exit 1
fi

# 5. Вывод учетных данных
echo "🔑 Данные для доступа:"
echo "------------------------------------------------------------------------"
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Секрет создается")
echo "• ArgoCD пароль (admin): $ARGOCD_PWD"

TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || echo "")
echo "• K8s Dashboard Token:   $TOKEN"
echo "------------------------------------------------------------------------"

echo "✅ Окружение полностью готово!"
echo "  • Traefik Dashboard: https://$TRAEFIK_HOST/dashboard/"
echo "  • ArgoCD UI:         https://$ARGOCD_HOST"
echo "  • K8s Dashboard:     https://k8s.local"