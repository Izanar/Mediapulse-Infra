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
kubectl rollout status deployment/vault -n vault --timeout=120s

VAULT_POD=$(kubectl get pod -l app.kubernetes.io/name=vault -n vault -o jsonpath="{.items[0].metadata.name}")

echo "🔑 Передача токена для External Secrets Operator..."
kubectl create secret generic vault-token \
    --namespace=default \
    --from-literal=token="root" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "📝 Запись секретов из локального .env в Vault..."
kubectl exec -i "$VAULT_POD" -n vault -- sh -c "
  export VAULT_ADDR='http://127.0.0.1:8200'
  export VAULT_TOKEN='root'
  
  vault kv put secret/mediapulse \
    postgres_server='$POSTGRES_SERVER' \
    postgres_port='$POSTGRES_PORT' \
    postgres_user='$POSTGRES_USER' \
    postgres_password='$POSTGRES_PASSWORD' \
    postgres_db='$POSTGRES_DB' \
    redis_host='$REDIS_HOST' \
    redis_port='$REDIS_PORT' \
    secret_key='$SECRET_KEY' \
    s3_endpoint_url='$S3_ENDPOINT_URL' \
    s3_access_key='$S3_ACCESS_KEY' \
    s3_secret_key='$S3_SECRET_KEY' \
    s3_bucket_name='$S3_BUCKET_NAME'
"

echo "✅ Локальные секреты успешно переданы в Vault!"