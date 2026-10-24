#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mediapulse/cloudflare"
TOKEN_FILE="$STATE_DIR/tunnel-token"
CONTAINER_NAME=mediapulse-cloudflared
IMAGE="${CLOUDFLARED_IMAGE:-cloudflare/cloudflared:latest}"
RUN_AS_USER="$(id -u):$(id -g)"

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
    STATE="$(docker container inspect --format '{{.State.Status}}' "$CONTAINER_NAME")"
    CONTAINER_USER="$(docker container inspect --format '{{.Config.User}}' "$CONTAINER_NAME")"
    if [ "$STATE" = running ] && [ "$CONTAINER_USER" = "$RUN_AS_USER" ]; then
        echo "✅ Cloudflare Tunnel уже запущен."
        exit 0
    fi
    docker rm --force "$CONTAINER_NAME" >/dev/null
fi

docker run --detach \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --network host \
    --user "$RUN_AS_USER" \
    --mount "type=bind,source=$TOKEN_FILE,target=/run/secrets/cloudflare-tunnel-token,readonly" \
    "$IMAGE" \
    tunnel --no-autoupdate run --token-file /run/secrets/cloudflare-tunnel-token >/dev/null

CONNECTION_DEADLINE=$((SECONDS + 30))
while (( SECONDS < CONNECTION_DEADLINE )); do
    STATE="$(docker container inspect --format '{{.State.Status}}' "$CONTAINER_NAME")"
    if [ "$STATE" != running ]; then
        echo "❌ Cloudflare Tunnel завершился при запуске. Последние логи:" >&2
        docker logs --tail 40 "$CONTAINER_NAME" >&2 || echo "❌ Не удалось прочитать логи connector." >&2
        docker rm --force "$CONTAINER_NAME" >/dev/null || echo "❌ Не удалось удалить остановленный connector." >&2
        exit 1
    fi
    if docker logs --since 45s "$CONTAINER_NAME" 2>&1 |
        grep -Eq 'Registered tunnel connection|Connection .*registered'; then
        echo "✅ Cloudflare Tunnel подключён в контейнере $CONTAINER_NAME."
        exit 0
    fi
    sleep 1
done

if [ "$(docker container inspect --format '{{.State.Status}}' "$CONTAINER_NAME")" != running ]; then
    echo "❌ Cloudflare Tunnel завершился при запуске. Последние логи:" >&2
    docker logs --tail 40 "$CONTAINER_NAME" >&2 || echo "❌ Не удалось прочитать логи connector." >&2
    docker rm --force "$CONTAINER_NAME" >/dev/null || echo "❌ Не удалось удалить остановленный connector." >&2
    exit 1
fi

echo "❌ Cloudflare Tunnel запущен, но не зарегистрировал соединение за 30 секунд. Последние логи:" >&2
docker logs --tail 40 "$CONTAINER_NAME" >&2 || echo "❌ Не удалось прочитать логи connector." >&2
docker rm --force "$CONTAINER_NAME" >/dev/null || echo "❌ Не удалось удалить connector без соединения." >&2
exit 1
