#!/usr/bin/env bash
set -euo pipefail

echo "🔑 Данные для доступа:"
echo "------------------------------------------------------------------------"
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "недоступно (ArgoCD ещё не развёрнут)")
echo "• ArgoCD пароль (admin): $ARGOCD_PWD"

DASHBOARD_TOKEN=$(kubectl -n kubernetes-dashboard create token admin-user 2>/dev/null || echo "недоступен (подождите готовности kubernetes-dashboard)")
echo "• K8s Dashboard токен (admin-user): $DASHBOARD_TOKEN"

echo "------------------------------------------------------------------------"
echo ""
echo "📋 Состояние приложений в ArgoCD:"
kubectl -n argocd get applications 2>/dev/null || echo "ArgoCD ещё не развёрнут — выполните make argocd-up"


echo ""
echo "Публичные адреса (через Cloudflare Tunnel):"
echo "  https://argocd.izanar.dev/          (ArgoCD; Cloudflare Access)"
echo "  https://kind.izanar.dev/            (Kubernetes Dashboard; Cloudflare Access)"
echo "  https://mediapulse.izanar.dev/      (Mediapulse)"
echo "  https://traefik.izanar.dev/dashboard/ (Traefik UI; Cloudflare Access)"
