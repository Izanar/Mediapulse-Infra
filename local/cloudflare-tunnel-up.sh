#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=default
DEPLOYMENT=cloudflare-tunnel
CONNECT_TIMEOUT="${CLOUDFLARE_TUNNEL_CONNECT_TIMEOUT:-60}"

echo "⏳ Ожидание Cloudflare token из Vault через External Secrets..."
kubectl -n "$NAMESPACE" wait \
    --for=condition=Ready externalsecret/cloudflare-tunnel-token \
    --timeout=600s
kubectl -n "$NAMESPACE" rollout status "deployment/$DEPLOYMENT" --timeout=180s

CONNECTION_DEADLINE=$((SECONDS + CONNECT_TIMEOUT))
while (( SECONDS < CONNECTION_DEADLINE )); do
    if kubectl -n "$NAMESPACE" logs "deployment/$DEPLOYMENT" --tail=100 |
        grep -Eq 'Registered tunnel connection|Connection .*registered'; then
        echo "✅ Cloudflare Tunnel зарегистрирован из Kubernetes."
        exit 0
    fi
    sleep 2
done

echo "❌ Cloudflare Tunnel не зарегистрировал соединение за ${CONNECT_TIMEOUT}s. Последние логи:" >&2
kubectl -n "$NAMESPACE" logs "deployment/$DEPLOYMENT" --tail=40 >&2
exit 1
