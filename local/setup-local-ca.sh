#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mediapulse/pki"
CA_KEY="$CERT_DIR/ca.key"
CA_CERT="$CERT_DIR/ca.crt"

umask 077
mkdir -p "$CERT_DIR"

if [[ ! -s "$CA_KEY" && ! -s "$CA_CERT" ]]; then
    openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
        -keyout "$CA_KEY" \
        -out "$CA_CERT" \
        -subj "/CN=Mediapulse Local Development CA" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign"
    chmod 600 "$CA_KEY"
    chmod 644 "$CA_CERT"
elif [[ ! -s "$CA_KEY" || ! -s "$CA_CERT" ]]; then
    echo "❌ Неполная пара локального CA: проверьте $CERT_DIR." >&2
    exit 1
fi

kubectl -n cert-manager create secret tls mediapulse-local-ca \
    --cert="$CA_CERT" \
    --key="$CA_KEY" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

echo "✅ CA secret установлен в cert-manager."
echo "   Корневой сертификат для установки в доверенные CA: $CA_CERT"
