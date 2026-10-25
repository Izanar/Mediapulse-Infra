#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=default
DEPLOYMENT=cloudflare-tunnel

echo "⏳ Ожидание готовности Cloudflare Tunnel Deployment..."
kubectl -n "$NAMESPACE" rollout status "deployment/$DEPLOYMENT" --timeout=300s

echo "✅ Cloudflare Tunnel запущен."
echo "   Регистрация туннеля в Cloudflare происходит автоматически через cloudflared."
echo "   Проверьте подключение в веб-интерфейсе Cloudflare Zero Trust."
