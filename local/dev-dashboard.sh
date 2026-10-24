#!/usr/bin/env bash
set -euo pipefail

ARGOCD_HOST="argocd.izanar.dev"
TRAEFIK_HOST="traefik.izanar.dev"
MEDIAPULSE_HOST="mediapulse.izanar.dev"
KIND_HOST="kind.izanar.dev"

echo "🚀 Настройка локальных дашбордов и Ingress-маршрутов..."

# 1. Проверяем CRD Traefik, прежде чем использовать маршруты на их основе.
echo "⏳ Ожидание установки Traefik и его CRD в кластере..."
kubectl wait --for=condition=Established crd/ingressroutes.traefik.io --timeout=180s
echo "✅ CRD Traefik обнаружены!"

# 2. Ждём готовности Dashboard и Traefik.
echo "⏳ Ожидание создания namespace kubernetes-dashboard ArgoCD..."
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/kubernetes-dashboard --timeout=180s
kubectl -n kubernetes-dashboard rollout status deployment/kubernetes-dashboard --timeout=180s
kubectl -n traefik rollout status deployment/traefik --timeout=180s

# Убедимся, что маршруты установлены; проверка HTTP с хоста ненадёжна для сети Kind/WSL2.
kubectl -n argocd get ingress argocd-server-ingress
kubectl -n traefik get ingressroute traefik-dashboard
kubectl -n kubernetes-dashboard get ingressroute k8s-dashboard-ingress

# 3. Проверяем, что Traefik доступен только как внутренний Kubernetes Service.
echo "⏳ Проверка внутреннего ClusterIP-сервиса Traefik..."
TRAEFIK_SERVICE_TYPE=$(kubectl get svc -n traefik traefik -o jsonpath='{.spec.type}')
if [ "$TRAEFIK_SERVICE_TYPE" != "ClusterIP" ]; then
    echo "❌ Сервис Traefik должен быть ClusterIP; обнаружено: $TRAEFIK_SERVICE_TYPE" >&2
    exit 1
fi
echo "✅ Traefik доступен Cloudflare Tunnel внутри кластера."

# 4. Вывод учетных данных
echo "🔑 Данные для доступа:"
echo "------------------------------------------------------------------------"
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "• ArgoCD пароль (admin): $ARGOCD_PWD"

DASHBOARD_TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)
echo "• K8s Dashboard токен (admin-user): $DASHBOARD_TOKEN"

echo "------------------------------------------------------------------------"

echo "================================================================"
echo "🎉 ОКРУЖЕНИЕ ГОТОВО — адреса после подключения Cloudflare Tunnel:"
echo "================================================================"
echo ""
echo "      https://$ARGOCD_HOST/       (ArgoCD; требуется Cloudflare Access)"
echo "      https://$KIND_HOST/         (Kubernetes Dashboard; требуется Cloudflare Access)"
echo "      https://$MEDIAPULSE_HOST/   (Mediapulse)"
echo "      https://$TRAEFIK_HOST/dashboard/ (Traefik UI; требуется Cloudflare Access)"
echo ""
echo "Cloudflare Tunnel направляется на http://traefik.traefik.svc.cluster.local:80."
echo "Cloudflare Tunnel запускается командой: make cloudflare-tunnel-up"

echo "================================================================"