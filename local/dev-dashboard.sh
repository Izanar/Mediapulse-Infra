#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_HOST="argocd.local"
TRAEFIK_HOST="traefik.local"

echo "🚀 Настройка локальных дашбордов и Ingress-маршрутов..."

# 1. Ждем, пока ArgoCD установит Traefik и появятся его CRD
echo "⏳ Ожидание установки Traefik и его CRD в кластере..."
for _ in $(seq 1 60); do
    if kubectl get crd ingressroutes.traefik.io &>/dev/null; then
        echo "✅ CRD Traefik обнаружены!"
        break
    fi
    sleep 3
done

# 2. Ждем, пока ArgoCD создаст namespace kubernetes-dashboard (устанавливает Dashboard)
echo "⏳ Ожидание создания namespace kubernetes-dashboard ArgoCD..."
for _ in $(seq 1 60); do
    if kubectl get ns kubernetes-dashboard &>/dev/null; then
        echo "✅ Namespace kubernetes-dashboard найден!"
        break
    fi
    sleep 3
done

# 3. Ждем, пока Traefik получит внешний IP от MetalLB
echo "⏳ Ожидание внешнего IP у сервиса Traefik (MetalLB)..."
TRAEFIK_IP=""
for _ in $(seq 1 60); do
    TRAEFIK_IP=$(kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [ -n "$TRAEFIK_IP" ]; then
        echo "✅ Traefik IP: $TRAEFIK_IP"
        break
    fi
    sleep 3
done

if [ -z "$TRAEFIK_IP" ]; then
    echo "⚠️  Traefik не получил внешний IP от MetalLB. Будем использовать localhost."
    TRAEFIK_IP="127.0.0.1"
fi

# 4. Рекомендация по hosts (скрипт НЕ правит hosts автоматически).
# WSL2 IP — адрес, по которому Windows достучится до WSL2 через port-forward.
# Для доступа из WSL2 используйте MetalLB IP (внутри видна кластерная сеть),
# для доступа из Windows — WSL2 IP (Kind-сеть изолирована, нужен port-forward).
WSL2_IP=$(ip addr show eth0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 || true)
if [ -z "$WSL2_IP" ]; then
    WSL2_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
fi

echo "RECOMMENDATION: добавьте записи hosts вручную:"
echo "   WSL2 /etc/hosts:"
echo "   $TRAEFIK_IP $ARGOCD_HOST $TRAEFIK_HOST k8s.local mediapulse.local"
echo "   Windows C:\\Windows\\System32\\drivers\\etc\\hosts (от имени администратора):"
echo "   $WSL2_IP $ARGOCD_HOST $TRAEFIK_HOST k8s.local mediapulse.local"

# 5. Проверка доступности ArgoCD UI
echo "🔍 Проверка доступности UI..."
RESOLVE_IP="$TRAEFIK_IP"
if [ "$TRAEFIK_IP" = "127.0.0.1" ]; then
    echo "⚠️  MetalLB IP не получен, проверка через localhost (нужен отдельный port-forward)."
fi

code="000"
for _ in $(seq 1 12); do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
        --resolve "$ARGOCD_HOST:443:$RESOLVE_IP" "https://$ARGOCD_HOST/" || echo 000)
    [ "$code" = "200" ] && break
    sleep 3
done

if [ "$code" != "200" ]; then
    echo "❌ ArgoCD UI недоступен (код $code)."
    if [ "$TRAEFIK_IP" = "127.0.0.1" ]; then
        echo "💡 Запустите в другом терминале:"
        echo "   kubectl port-forward service/traefik 8443:443 -n traefik"
        echo "   затем откройте https://localhost:8443/"
    fi
    kubectl -n argocd get ingressroute || true
    exit 1
fi

# 6. Вывод учетных данных
echo "🔑 Данные для доступа:"
echo "------------------------------------------------------------------------"
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Секрет создается")
echo "• ArgoCD пароль (admin): $ARGOCD_PWD"

DASHBOARD_TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || echo "Создайте вручную: kubectl -n kubernetes-dashboard create token admin-user")
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
echo "2️⃣  В отдельном терминале WSL2 запустите port-forward:"
echo "      kubectl port-forward --address 0.0.0.0 service/traefik 8443:443 -n traefik"
echo "    Или используйте: make traefik-port-forward"
echo ""
echo "3️⃣  Откройте в браузере Windows:"
echo "      https://argocd.local:8443/       (ArgoCD)"
echo "      https://traefik.local:8443/dashboard/  (Traefik UI)"
echo "      https://k8s.local:8443/          (K8s Dashboard)"

echo "================================================================"