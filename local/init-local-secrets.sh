#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_PATH="$SCRIPT_DIR/../../Mediapulse-App/.env"

if [ ! -f "$ENV_PATH" ]; then
    echo "❌ Файл .env не найден по пути $ENV_PATH!"
    exit 1
fi

# Подтягиваем переменные
set -a
source "$ENV_PATH"
set +a

echo "⏳ Ожидание запуска Vault в кластере..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=60s

VAULT_POD=$(kubectl get pod -l app.kubernetes.io/name=vault -n vault -o jsonpath="{.items[0].metadata.name}")

echo "📝 Запись секретов из локального .env в Vault..."
python3 - <<'PY' | kubectl exec -i "$VAULT_POD" -n vault -- sh -c '
set -eu
umask 077
secret_file=/tmp/mediapulse-secrets.json
trap "rm -f $secret_file" EXIT
cat > "$secret_file"

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"
vault kv put secret/mediapulse "@$secret_file"

vault policy write mediapulse-eso - <<POLICY
path "secret/data/mediapulse" {
  capabilities = ["read"]
}
POLICY
'
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
json.dump({key.lower(): os.environ[key] for key in keys}, sys.stdout)
PY

echo "🔑 Создание ограниченного токена для External Secrets Operator..."
ESO_TOKEN="$(kubectl exec "$VAULT_POD" -n vault -- sh -c '
  export VAULT_ADDR="http://127.0.0.1:8200"
  export VAULT_TOKEN="root"
  vault token create -orphan -no-default-policy -policy=mediapulse-eso -ttl=720h -field=token
')"

printf '%s' "$ESO_TOKEN" | kubectl create secret generic vault-token \
    --namespace=default \
    --from-file=token=/dev/stdin \
    --dry-run=client -o yaml | kubectl apply -f -
unset ESO_TOKEN

echo "✅ Локальные секреты успешно переданы в Vault!"