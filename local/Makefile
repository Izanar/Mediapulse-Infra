.PHONY: help cluster-up cluster-down cluster-status helm-up argocd-up dashboard-up all-up

help: ## Показать список доступных команд
	@echo "Доступные команды в mediapulse-infra:"
	@echo "  make cluster-up     - Создать Kind-кластер"
	@echo "  make cluster-down   - Удалить Kind-кластер"
	@echo "  make cluster-status - Проверить статус нод кластера"
	@echo "  make helm-up        - Установить Helm CLI"
	@echo "  make argocd-up      - Установить ArgoCD и применить root.yaml"
	@echo "  make dashboard-up   - Запустить скрипт настройки Ingress и дашбордов"
	@echo "  make all-up         - Полный цикл: кластер -> helm -> argocd -> дашборды"

cluster-up: ## Создать Kind-кластер
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

argocd-up: ## Установить ArgoCD и применить корневой App-of-Apps
	@echo "📦 Установка ArgoCD..."
	@command -v helm >/dev/null 2>&1 || { echo "❌ Helm не найден. Выполни: make helm-up"; exit 1; }
	@kubectl get ns argocd >/dev/null 2>&1 || kubectl create namespace argocd
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update
	helm upgrade --install argocd argo/argo-cd --namespace argocd
	
	@echo "⏳ Ожидание запуска ArgoCD API сервер..."
	@kubectl -n argocd rollout status deploy/argocd-server --timeout=120s || true
	
	@echo "🔄 Применение корневого манифеста (root.yaml)..."
	kubectl apply -f ../../Mediapulse-Gitops/argocd/root.yaml

dashboard-up: ## Запустить скрипт настройки маршрутов и дашбордов
	@echo "🌐 Запуск скрипта конфигурации окружения..."
	@chmod +x ./dev-dashboard.sh
	./dev-dashboard.sh

all-up: cluster-up helm-up argocd-up dashboard-up ## Полный цикл развертывания
	@echo "🎉 Вся инфраструктура, ArgoCD и локальные дашборды успешно запущены!"