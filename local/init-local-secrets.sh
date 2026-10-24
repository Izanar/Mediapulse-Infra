#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="$SCRIPT_DIR/../../Mediapulse-App/.env"
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mediapulse/vault"
CLOUDFLARE_STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mediapulse/cloudflare"
CLOUDFLARE_TOKEN_FILE="$CLOUDFLARE_STATE_DIR/tunnel-token"
NAMESPACE=vault
POD_NAME=vault-0
ROOT_TOKEN=

if [ ! -f "$ENV_PATH" ]; then
    echo "❌ Файл .env не найден по пути $ENV_PATH!" >&2
    exit 1
fi

if [ -L "$STATE_DIR" ]; then
    echo "❌ Каталог Vault state не должен быть символической ссылкой: $STATE_DIR" >&2
    exit 1
fi
install -d -m 700 "$STATE_DIR"
chmod 700 "$STATE_DIR"

set -a
source "$ENV_PATH"
set +a

for name in POSTGRES_SERVER POSTGRES_PORT POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB \
    REDIS_HOST REDIS_PORT SECRET_KEY S3_ENDPOINT_URL S3_ACCESS_KEY S3_SECRET_KEY S3_BUCKET_NAME; do
    if [ -z "${!name:-}" ]; then
        echo "❌ Переменная $name не задана в $ENV_PATH" >&2
        exit 1
    fi
done
if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    echo "❌ Переменная CLOUDFLARE_TUNNEL_TOKEN не задана в $ENV_PATH" >&2
    echo "   Скопируйте строку из .env.example и вставьте connector token локально." >&2
    exit 1
fi

vault_exec_with_token() {
    local token=$1
    shift
    printf '%s\n' "$token" | kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- sh -c '
        IFS= read -r VAULT_TOKEN || exit 1
        export VAULT_TOKEN
        export VAULT_ADDR="http://127.0.0.1:8200"
        exec vault "$@"
    ' mediapulse-vault "$@"
}

vault_write_policy() {
    local token=$1
    local name=$2
    local policy=$3
    {
        printf '%s\n' "$token"
        printf '%s\n' "$policy"
    } | kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- sh -c '
        IFS= read -r VAULT_TOKEN || exit 1
        export VAULT_TOKEN
        export VAULT_ADDR="http://127.0.0.1:8200"
        umask 077
        policy_file=$(mktemp)
        trap "rm -f \"$policy_file\"" EXIT
        cat > "$policy_file"
        vault policy write "$1" "$policy_file"
    ' mediapulse-policy "$name"
}

write_private_file() {
    local path=$1
    local value=$2
    local temporary="${path}.tmp.$$"
    printf '%s\n' "$value" > "$temporary"
    chmod 600 "$temporary"
    mv -f "$temporary" "$path"
}

if [ -L "$CLOUDFLARE_STATE_DIR" ]; then
    echo "❌ Каталог Cloudflare state не должен быть символической ссылкой: $CLOUDFLARE_STATE_DIR" >&2
    exit 1
fi
if [ -L "$CLOUDFLARE_TOKEN_FILE" ]; then
    echo "❌ Tunnel token не должен быть символической ссылкой: $CLOUDFLARE_TOKEN_FILE" >&2
    exit 1
fi
install -d -m 700 "$CLOUDFLARE_STATE_DIR"
chmod 700 "$CLOUDFLARE_STATE_DIR"
write_private_file "$CLOUDFLARE_TOKEN_FILE" "$CLOUDFLARE_TUNNEL_TOKEN"
unset CLOUDFLARE_TUNNEL_TOKEN
echo "🔐 Cloudflare Tunnel token сохранён вне Git в $CLOUDFLARE_TOKEN_FILE (права 0600)."

revoke_temporary_root() {
    if [ -n "$ROOT_TOKEN" ]; then
        vault_exec_with_token "$ROOT_TOKEN" token revoke -self >/dev/null 2>&1 || true
        ROOT_TOKEN=
    fi
}
trap revoke_temporary_root EXIT

ensure_kv_v2_mount() {
    local mounts mount_info
    mounts="$(vault_exec_with_token "$ROOT_TOKEN" secrets list -format=json)"
    mount_info="$(printf '%s' "$mounts" | python3 -c '
import json,sys
mounts=json.load(sys.stdin)
mount=mounts.get("secret/")
if mount is None:
    print("missing")
else:
    print("{}:{}".format(mount.get("type",""), mount.get("options",{}).get("version","")))
')"
    case "$mount_info" in
        missing)
            vault_exec_with_token "$ROOT_TOKEN" secrets enable -path=secret kv-v2
            ;;
        kv:2)
            ;;
        *)
            echo "❌ Vault mount secret/ должен быть KV v2; обнаружено: $mount_info" >&2
            return 1
            ;;
    esac
}

generate_temporary_root() {
    local init_json nonce otp key response encoded_token
    if [ ! -s "$STATE_DIR/unseal-key" ]; then
        echo "❌ Для восстановления временного root-токена не найден unseal-ключ: $STATE_DIR/unseal-key" >&2
        return 1
    fi

    echo "🔐 KV engine отсутствует; временно восстанавливаю root-доступ unseal-ключом..."
    init_json="$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- sh -c \
        'VAULT_ADDR="http://127.0.0.1:8200" vault operator generate-root -init -format=json')"
    nonce="$(printf '%s' "$init_json" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["nonce"])')"
    otp="$(printf '%s' "$init_json" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["otp"])')"
    unset init_json

    response="$(kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- sh -c '
        VAULT_ADDR="http://127.0.0.1:8200" vault operator generate-root -format=json -nonce="$1" -
    ' mediapulse-root "$nonce" < "$STATE_DIR/unseal-key")"
    unset nonce
    encoded_token="$(printf '%s' "$response" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["encoded_token"])')"
    unset response

    ROOT_TOKEN="$(
        {
            printf '%s\n' "$otp"
            printf '%s\n' "$encoded_token"
        } | kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- sh -c '
            IFS= read -r otp || exit 1
            VAULT_ADDR="http://127.0.0.1:8200" vault operator generate-root -decode=- -otp="$otp"
        '
    )"
    unset encoded_token otp
    if [ -z "$ROOT_TOKEN" ]; then
        echo "❌ Vault не вернул временный root-токен." >&2
        return 1
    fi
}

echo "⏳ Ожидание создания Vault pod..."
POD_CREATE_DEADLINE=$((SECONDS + 600))
until kubectl get pod "$POD_NAME" -n "$NAMESPACE" >/dev/null 2>&1; do
    if (( SECONDS >= POD_CREATE_DEADLINE )); then
        echo "❌ Pod $POD_NAME не был создан за 600 секунд. Состояние StatefulSet Vault:" >&2
        kubectl get statefulset vault -n "$NAMESPACE" -o wide >&2 || true
        kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp >&2 || true
        exit 1
    fi
    sleep 2
done

echo "⏳ Ожидание запуска Vault pod..."
kubectl wait --for=jsonpath='{.status.phase}'=Running "pod/$POD_NAME" \
    -n "$NAMESPACE" --timeout=600s

STATUS="$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- sh -c \
    'VAULT_ADDR="http://127.0.0.1:8200" vault status -format=json' 2>/dev/null || true)"
if [ -z "$STATUS" ]; then
    echo "❌ Не удалось получить статус Vault." >&2
    exit 1
fi
INITIALIZED="$(printf '%s' "$STATUS" | python3 -c \
    'import json,sys; print(str(json.load(sys.stdin)["initialized"]).lower())')"
SEALED="$(printf '%s' "$STATUS" | python3 -c \
    'import json,sys; print(str(json.load(sys.stdin)["sealed"]).lower())')"

if [ "$INITIALIZED" = false ]; then
    echo "🚀 Первый запуск: инициализация одноузлового Vault..."
    INIT_JSON="$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- sh -c \
        'VAULT_ADDR="http://127.0.0.1:8200" vault operator init -key-shares=1 -key-threshold=1 -format=json')"
    UNSEAL_KEY="$(printf '%s' "$INIT_JSON" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["unseal_keys_b64"][0])')"
    ROOT_TOKEN="$(printf '%s' "$INIT_JSON" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["root_token"])')"
    unset INIT_JSON
    write_private_file "$STATE_DIR/unseal-key" "$UNSEAL_KEY"
    chmod 600 "$STATE_DIR/unseal-key"
    printf '%s\n' "$UNSEAL_KEY" | kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- sh -c '
        IFS= read -r key || exit 1
        VAULT_ADDR="http://127.0.0.1:8200" vault operator unseal "$key" >/dev/null
    '
    unset UNSEAL_KEY

    ensure_kv_v2_mount

    ESO_POLICY='path "secret/data/mediapulse" { capabilities = ["read"] }
path "auth/token/lookup-self" { capabilities = ["read"] }'
    PROVISIONER_POLICY='path "secret/data/mediapulse" { capabilities = ["create", "update"] }'
    vault_write_policy "$ROOT_TOKEN" mediapulse-eso "$ESO_POLICY"
    vault_write_policy "$ROOT_TOKEN" mediapulse-provisioner "$PROVISIONER_POLICY"

    MOUNTS="$(vault_exec_with_token "$ROOT_TOKEN" auth list -format=json)"
    if ! printf '%s' "$MOUNTS" | python3 -c \
        'import json,sys; sys.exit(0 if "approle/" in json.load(sys.stdin) else 1)'; then
        vault_exec_with_token "$ROOT_TOKEN" auth enable approle
    fi

    vault_exec_with_token "$ROOT_TOKEN" write auth/approle/role/mediapulse-provisioner \
        token_policies=mediapulse-provisioner token_no_default_policy=true \
        token_ttl=1h token_max_ttl=1h secret_id_ttl=0
    vault_exec_with_token "$ROOT_TOKEN" write auth/approle/role/mediapulse-eso \
        token_policies=mediapulse-eso token_no_default_policy=true \
        token_ttl=1h token_max_ttl=1h secret_id_ttl=0

    PROVISIONER_ROLE_ID_JSON="$(vault_exec_with_token "$ROOT_TOKEN" read -format=json \
        auth/approle/role/mediapulse-provisioner/role-id)"
    PROVISIONER_ROLE_ID="$(printf '%s' "$PROVISIONER_ROLE_ID_JSON" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["data"]["role_id"])')"
    PROVISIONER_SECRET_JSON="$(vault_exec_with_token "$ROOT_TOKEN" write -format=json -f \
        auth/approle/role/mediapulse-provisioner/secret-id)"
    PROVISIONER_SECRET_ID="$(printf '%s' "$PROVISIONER_SECRET_JSON" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["data"]["secret_id"])')"
    ESO_ROLE_ID_JSON="$(vault_exec_with_token "$ROOT_TOKEN" read -format=json \
        auth/approle/role/mediapulse-eso/role-id)"
    ESO_ROLE_ID="$(printf '%s' "$ESO_ROLE_ID_JSON" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["data"]["role_id"])')"
    ESO_SECRET_JSON="$(vault_exec_with_token "$ROOT_TOKEN" write -format=json -f \
        auth/approle/role/mediapulse-eso/secret-id)"
    ESO_SECRET_ID="$(printf '%s' "$ESO_SECRET_JSON" | python3 -c \
        'import json,sys; print(json.load(sys.stdin)["data"]["secret_id"])')"
    unset PROVISIONER_ROLE_ID_JSON PROVISIONER_SECRET_JSON ESO_ROLE_ID_JSON ESO_SECRET_JSON

    write_private_file "$STATE_DIR/provisioner-role-id" "$PROVISIONER_ROLE_ID"
    write_private_file "$STATE_DIR/provisioner-secret-id" "$PROVISIONER_SECRET_ID"
    write_private_file "$STATE_DIR/eso-role-id" "$ESO_ROLE_ID"
    write_private_file "$STATE_DIR/eso-secret-id" "$ESO_SECRET_ID"
    unset PROVISIONER_SECRET_ID ESO_SECRET_ID
elif [ "$SEALED" = true ]; then
    if [ ! -s "$STATE_DIR/unseal-key" ]; then
        echo "❌ Vault запечатан, но ключ разблокировки отсутствует: $STATE_DIR/unseal-key" >&2
        exit 1
    fi
    echo "🔓 Разблокировка Vault сохранённым локальным ключом..."
    kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- sh -c '
        IFS= read -r key || exit 1
        VAULT_ADDR="http://127.0.0.1:8200" vault operator unseal "$key" >/dev/null
    ' < "$STATE_DIR/unseal-key"
fi

for file in provisioner-role-id provisioner-secret-id eso-role-id eso-secret-id; do
    if [ ! -s "$STATE_DIR/$file" ]; then
        echo "❌ Не найден локальный Vault bootstrap credential: $STATE_DIR/$file" >&2
        echo "   Не удаляйте PVC Vault или файлы состояния; для восстановления потребуется повторный bootstrap." >&2
        exit 1
    fi
done

PROVISIONER_ROLE_ID="$(<"$STATE_DIR/provisioner-role-id")"
PROVISIONER_SECRET_ID="$(<"$STATE_DIR/provisioner-secret-id")"
ESO_ROLE_ID="$(<"$STATE_DIR/eso-role-id")"
ESO_SECRET_ID="$(<"$STATE_DIR/eso-secret-id")"

LOGIN_JSON="$(
    {
        printf '%s\n' "$PROVISIONER_ROLE_ID"
        printf '%s\n' "$PROVISIONER_SECRET_ID"
    } | kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- sh -c '
        IFS= read -r role_id || exit 1
        IFS= read -r secret_id || exit 1
        export VAULT_ADDR="http://127.0.0.1:8200"
        vault write -format=json auth/approle/login "role_id=$role_id" "secret_id=$secret_id"
    '
)"
PROVISIONER_TOKEN="$(printf '%s' "$LOGIN_JSON" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["auth"]["client_token"])')"
unset LOGIN_JSON PROVISIONER_SECRET_ID

echo "🔑 Обновление Kubernetes credential для read-only External Secrets роли..."
kubectl create secret generic vault-approle \
    --namespace=default \
    --from-file=role-id="$STATE_DIR/eso-role-id" \
    --from-file=secret-id="$STATE_DIR/eso-secret-id" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "📝 Запись секретов из .env в Vault..."
write_secret_to_vault() {
    {
        printf '%s\n' "$PROVISIONER_TOKEN"
        python3 - <<'PY'
import json
import os
import sys

keys = (
    "POSTGRES_SERVER",
    "POSTGRES_PORT",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "POSTGRES_DB",
    "REDIS_HOST",
    "REDIS_PORT",
    "SECRET_KEY",
    "S3_ENDPOINT_URL",
    "S3_ACCESS_KEY",
    "S3_SECRET_KEY",
    "S3_BUCKET_NAME",
)
json.dump({"data": {key.lower(): os.environ[key] for key in keys}}, sys.stdout)
PY
    } | kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- sh -c '
        IFS= read -r VAULT_TOKEN || exit 1
        export VAULT_TOKEN
        export VAULT_ADDR="http://127.0.0.1:8200"
        umask 077
        secret_file=$(mktemp)
        trap "rm -f \"$secret_file\"" EXIT
        cat > "$secret_file"
        vault write secret/data/mediapulse "@$secret_file"
    '
}
if ! WRITE_OUTPUT="$(write_secret_to_vault 2>&1)"; then
    if [[ "$WRITE_OUTPUT" == *'no handler for route "secret/data/mediapulse"'* ]]; then
        generate_temporary_root
        ensure_kv_v2_mount
        vault_exec_with_token "$ROOT_TOKEN" token revoke -self >/dev/null
        ROOT_TOKEN=
        if ! WRITE_OUTPUT="$(write_secret_to_vault 2>&1)"; then
            printf '%s\n' "$WRITE_OUTPUT" >&2
            exit 1
        fi
    else
        printf '%s\n' "$WRITE_OUTPUT" >&2
        exit 1
    fi
fi
printf '%s\n' "$WRITE_OUTPUT"
unset WRITE_OUTPUT
unset PROVISIONER_TOKEN

if [ -n "$ROOT_TOKEN" ]; then
    echo "🔐 Отзыв временного root-токена..."
    vault_exec_with_token "$ROOT_TOKEN" token revoke -self >/dev/null
    ROOT_TOKEN=
fi

echo "✅ Vault разблокирован; секреты загружены, root-токен отозван."
echo "ℹ️ Локальные bootstrap credentials находятся в $STATE_DIR (права 0700/0600)."
