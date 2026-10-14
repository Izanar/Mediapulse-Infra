#!/usr/bin/env bash
set -euo pipefail

# Скрипт должен работать независимо от того, из какой директории его вызвали.
# Makefile вызывает его как ./dev-dashboard.sh из каталога local/, поэтому
# использование относительных путей вида local/manifests/... приводило к
# ошибке "path does not exist" и ingress не создавался (UI отдавал 404).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"
ARGOCD_HOST="argocd.local"

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

# 2. Применение Ingress манифестов для дашбордов и ArgoCD.
# Своего TLS-сертификата нет намеренно: секции tls в манифесте нет, поэтому
# ingress-nginx отдаёт свой дефолтный самоподписанный сертификат, а браузер
# показывает предупреждение. Так в репозитории не появляется приватный ключ,
# который пришлось бы скрывать от Git.
# Ошибки больше не подавляются: если ingress не создастся, упадет здесь,
# а не тихо оставит UI недоступным.
echo "🌐 Применение Ingress маршрутизации..."
kubectl apply -f "$MANIFESTS_DIR/argocd-ingress.yaml"
kubectl apply -f "$MANIFESTS_DIR/dashboard-ingress.yaml"

# 3. Контрольная проверка: убеждаемся, что ingress реально создан и отвечает.
echo "🔍 Проверка доступности UI..."
for _ in $(seq 1 12); do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
        --resolve "$ARGOCD_HOST:443:127.0.0.1" "https://$ARGOCD_HOST/" || echo 000)
    [ "$code" = "200" ] && break
    sleep 3
done

if [ "$code" != "200" ]; then
    echo "❌ ArgoCD UI недоступен (код $code). Диагностика:"
    kubectl -n argocd get ingress
    kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=30 || true
    exit 1
fi

# 4. Получение начального пароля ArgoCD и токена K8s Dashboard
echo "🔑 Данные для доступа:"
echo "------------------------------------------------------------------------"
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Секрет еще создается")
echo "• ArgoCD пароль (admin): $ARGOCD_PWD"

TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || echo "")
echo "• K8s Dashboard Token:   $TOKEN"
echo "------------------------------------------------------------------------"

echo "✅ Вся инфраструктура и Ingress маршрутизаторы успешно запущены!"
echo "  • ArgoCD UI:         https://argocd.local"
echo "  • K8s Dashboard:     https://dashboard.local"
echo "  • ArgoCD UI (проверено, HTTP $code)"

# Копируем токен/пароль в буфер обмена Windows, если доступно
if command -v clip.exe &> /dev/null && [ -n "$TOKEN" ]; then
    echo "$TOKEN" | clip.exe
    echo "📋 Токен K8s Dashboard автоматически скопирован в буфер обмена!"
fi