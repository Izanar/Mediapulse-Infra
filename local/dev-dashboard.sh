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

# 3. Ждём, пока Traefik получит IP origin для Cloudflare Tunnel.
echo "⏳ Ожидание внешнего IP у сервиса Traefik (MetalLB)..."
TRAEFIK_IP=$(kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for _ in $(seq 1 60); do
    if [ -n "$TRAEFIK_IP" ]; then
        echo "✅ Traefik IP: $TRAEFIK_IP"
        break
    fi
    sleep 3
    TRAEFIK_IP=$(kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done
if [ -z "$TRAEFIK_IP" ]; then
    echo "❌ У сервиса Traefik не появился IP MetalLB за 180 секунд." >&2
    exit 1
fi
curl --fail --silent --show-error --max-time 5 \
    -H "Host: $MEDIAPULSE_HOST" "http://$TRAEFIK_IP/" >/dev/null

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
echo "Cloudflare Tunnel направляется на HTTP origin Traefik $TRAEFIK_IP:80."
echo "Cloudflare Tunnel запускается командой: make cloudflare-tunnel-up"

echo "================================================================"