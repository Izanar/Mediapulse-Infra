.PHONY: help cluster-up cluster-down cluster-status helm-up ingress-up argocd-up dev-gui all-up

help: ## Показать список доступных команд
	@echo "Доступные команды в mediapulse-infra:"
	@echo "  make cluster-up     - Создать Kind-кластер (1 Master + 3 Workers)"
	@echo "  make cluster-down   - Удалить Kind-кластер"
	@echo "  make cluster-status - Проверить статус нod кластера"
	@echo "  make helm-up      - Установить Helm CLI
	@echo "  make argocd-up    - Установить ArgoCD"
	@echo "  make ingress-up    - Установить NGINX Ingress Controller"
	@echo "  make dev-gui        - Запустить Kubernetes Dashboard & ArgoCD UI"
	@echo "  make all-up         - Полный цикл: кластер -> helm -> argocd -> ingress -> UI"

cluster-up: ## Создать Kind-кластер по конфигу kind-config.yaml
	@echo "🚀 Запуск Kind-кластера mediapulse-cluster..."
	kind create cluster --config ./kind-config.yaml

cluster-down: ## Удалить Kind-кластер
	@echo "🛑 Удаление Kind-кластера mediapulse-cluster..."
	kind delete cluster --name mediapulse-cluster

cluster-status: ## Проверить статус нод Kubernetes
	kubectl get nodes -o wide

helm-up: ## Установить Helm CLI, если его ещё нет
	@if command -v helm >/dev/null 2>&1; then \
		echo "✅ Helm уже установлен: $$(helm version --short)"; \
	else \
		echo "📦 Установка Helm CLI..."; \
		curl -fsSL -o /tmp/get-helm-3 https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
		chmod 700 /tmp/get-helm-3 && /tmp/get-helm-3; \
	fi

ingress-up: ## Установить NGINX Ingress Controller
	@echo "🌐 Установка NGINX Ingress Controller..."
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	@echo "📌 Привязка ingress-nginx к control-plane (где проброшены порты 80/443 в kind-config.yaml)..."
	kubectl -n ingress-nginx patch deploy ingress-nginx-controller --type='json' \
	  -p='[{"op":"add","path":"/spec/template/spec/nodeSelector/ingress-ready","value":"true"}]'
	kubectl wait --namespace ingress-nginx \
	  --for=condition=ready pod \
	  --selector=app.kubernetes.io/component=controller \
	  --timeout=90s

argocd-up: ## Установить ArgoCD через Helm (идемпотентно)
	@echo "📦 Установка ArgoCD через Helm..."
	@command -v helm >/dev/null 2>&1 || { echo "❌ Helm не найден. Выполни: make helm-up"; exit 1; }
	@kubectl get ns argocd >/dev/null 2>&1 || kubectl create namespace argocd
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update
	helm upgrade --install argocd argo/argo-cd --namespace argocd
	@echo "🔑 Пароль admin: $$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"

dev-gui: ## Запустить скрипт дашбордов и проброса портов
	@echo "📊 Запуск UI & Дашбордов..."
	./dev-dashboard.sh

all-up: cluster-up helm-up argocd-up ingress-up dev-gui ## Поднять всю инфраструктуру с нуля
	@echo "🎉 Вся инфраструктура MediaPulse успешно развернута и готова к работе!"