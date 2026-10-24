#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mediapulse/cloudflare"
TOKEN_FILE="$STATE_DIR/tunnel-token"
CONTAINER_NAME=mediapulse-cloudflared
IMAGE="${CLOUDFLARED_IMAGE:-cloudflare/cloudflared:latest}"

if [ -L "$STATE_DIR" ]; then
    echo "❌ Каталог Cloudflare state не должен быть символической ссылкой: $STATE_DIR" >&2
    exit 1
fi

if [ ! -s "$TOKEN_FILE" ]; then
    echo "❌ Не найден Cloudflare Tunnel token: $TOKEN_FILE" >&2
    echo "   Создайте remotely-managed Tunnel, настройте его hostname routes и Access policies," >&2
    echo "   затем сохраните connector token в этот файл с правами 0600." >&2
    exit 1
fi

chmod 700 "$STATE_DIR"
if [ -L "$TOKEN_FILE" ]; then
    echo "❌ Tunnel token не должен быть символической ссылкой: $TOKEN_FILE" >&2
    exit 1
fi

chmod 600 "$TOKEN_FILE"
command -v docker >/dev/null 2>&1 || {
    echo "❌ Docker не найден." >&2
    exit 1
}

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    if [ "$(docker container inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" = true ]; then
        echo "✅ Cloudflare Tunnel уже запущен."
        exit 0
    fi
    docker start "$CONTAINER_NAME" >/dev/null
else
    docker run --detach \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --network host \
        --mount "type=bind,source=$TOKEN_FILE,target=/run/secrets/cloudflare-tunnel-token,readonly" \
        "$IMAGE" \
        tunnel --no-autoupdate run --token-file /run/secrets/cloudflare-tunnel-token >/dev/null
fi

sleep 3
if [ "$(docker container inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" != true ]; then
    echo "❌ Cloudflare Tunnel завершился при запуске. Последние логи:" >&2
    docker logs --tail 40 "$CONTAINER_NAME" >&2
    exit 1
fi

echo "✅ Cloudflare Tunnel запущен в контейнере $CONTAINER_NAME."
docker logs --since 5s "$CONTAINER_NAME" 2>&1 | grep -E 'Connection .*registered|Registered tunnel connection|error' || true
