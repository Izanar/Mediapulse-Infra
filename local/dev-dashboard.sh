#!/usr/bin/env bash
set -euo pipefail

ARGOCD_HOST="argocd.local"
TRAEFIK_HOST="traefik.local"

echo "🚀 Настройка локальных дашбордов и Ingress-маршрутов..."

# 1. Проверяем CRD Traefik, прежде чем использовать маршруты на их основе.
echo "⏳ Ожидание установки Traefik и его CRD в кластере..."
kubectl wait --for=condition=Established crd/ingressroutes.traefik.io crd/serverstransports.traefik.io --timeout=180s
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

# 3. Ждем, пока Traefik получит внешний IP от MetalLB
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
    echo "⚠️  Traefik не получил внешний IP от MetalLB. Для доступа используйте port-forward."
fi

# 4. Рекомендация по hosts (скрипт НЕ правит hosts автоматически).
# При доступе через port-forward WSL2 использует localhost, Windows — IP WSL2.
WSL2_IP=$(ip -4 -o addr show dev eth0 2>/dev/null | awk '{split($4, address, "/"); print address[1]}' || true)
if [ -z "$WSL2_IP" ]; then
    WSL2_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
fi

echo "RECOMMENDATION: добавьте записи hosts вручную:"
echo "   WSL2 /etc/hosts:"
echo "   127.0.0.1 $ARGOCD_HOST $TRAEFIK_HOST k8s.local mediapulse.local"
echo "   Windows C:\\Windows\\System32\\drivers\\etc\\hosts (от имени администратора):"
echo "   $WSL2_IP $ARGOCD_HOST $TRAEFIK_HOST k8s.local mediapulse.local"
if [ -n "$TRAEFIK_IP" ]; then
    echo "   MetalLB IP Traefik (для прямого доступа, если маршрут доступен): $TRAEFIK_IP"
fi

# 5. Вывод учетных данных
echo "🔑 Данные для доступа:"
echo "------------------------------------------------------------------------"
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "• ArgoCD пароль (admin): $ARGOCD_PWD"

DASHBOARD_TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user)
echo "• K8s Dashboard токен (admin-user): $DASHBOARD_TOKEN"

echo "------------------------------------------------------------------------"

echo "================================================================"
echo "🎉 ОКРУЖЕНИЕ ГОТОВО — шаги для доступа из Windows браузера:"
echo "================================================================"
echo ""
echo "1️⃣  В файле C:\\Windows\\System32\\drivers\\etc\\hosts"
echo "    (от имени администратора) добавьте строку:"
echo "      $WSL2_IP $ARGOCD_HOST $TRAEFIK_HOST k8s.local mediapulse.local"
echo "    Скрипт hosts не правит — добавьте строку вручную."
echo ""
echo "2️⃣  HTTPS Traefik опубликован на стандартном порту 443."
echo "    Для повторного запуска публикации используйте: make traefik-https-proxy"
echo ""
echo "3️⃣  Откройте в браузере Windows:"
echo "      https://argocd.local/       (ArgoCD)"
echo "      https://k8s.local/          (K8s Dashboard)"
echo "      https://mediapulse.local/   (Mediapulse)"
echo "      https://traefik.local/dashboard/  (Traefik UI)"

echo "================================================================"