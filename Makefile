.PHONY: help cluster-up cluster-down cluster-status ingress-up argocd-up dev-gui

help: ## Показать список доступных команд
	@echo "Доступные команды в mediapulse-infra:"
	@echo "  make cluster-up     - Создать Kind-кластер (1 Master + 3 Workers)"
	@echo "  make cluster-down   - Удалить Kind-кластер"
	@echo "  make cluster-status - Проверить статус нод кластера"
	@echo "  make ingress-up    - Установить NGINX Ingress Controller"
	@echo "  make argocd-up     - Развернуть ArgoCD в кластере"
	@echo "  make dev-gui        - Запустить Kubernetes Dashboard & ArgoCD UI"

cluster-up: ## Создать Kind-кластер по конфигу kind-config.yaml
	@echo "🚀 Запуск Kind-кластера mediapulse-cluster..."
	kind create cluster --config local/kind-config.yaml

cluster-down: ## Удалить Kind-кластер
	@echo "🛑 Удаление Kind-кластера mediapulse-cluster..."
	kind delete cluster --name mediapulse-cluster

cluster-status: ## Проверить статус нод Kubernetes
	kubectl get nodes -o wide

ingress-up: ## Установить NGINX Ingress Controller
	@echo "🌐 Установка NGINX Ingress Controller..."
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	kubectl wait --namespace ingress-nginx \
	  --for=condition=ready pod \
	  --selector=app.kubernetes.io/component=controller \
	  --timeout=90s

argocd-up: ## Установить ArgoCD
	@echo "🐙 Разворачивание ArgoCD..."
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl wait --namespace argocd \
	  --for=condition=ready pod \
	  --all \
	  --timeout=120s

dev-gui: ## Запустить скрипт дашбордов и проброса портов
	@echo "📊 Запуск UI & Дашбордов..."
	./local/dev-dashboard.sh