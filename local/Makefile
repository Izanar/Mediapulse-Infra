ARGOCD_REPO_PATH ?= ../../Mediapulse-Gitops/local
ARGOCD_APP_TIMEOUT ?= 600s

.PHONY: help cluster-up cluster-down cluster-status helm-up argocd-up vault-up secrets-init wait-application wait-application-synced dashboard-up cloudflare-tunnel-up all-up
.NOTPARALLEL: all-up

help: ## Показать список доступных команд
	@echo "Доступные команды в mediapulse-infra:"
	@echo "  make cluster-up             - Создать Kind-кластер"
	@echo "  make cluster-down           - Удалить Kind-кластер"
	@echo "  make cluster-status         - Проверить статус нод кластера"
	@echo "  make helm-up                - Установить Helm CLI"
	@echo "  make argocd-up              - Установить Argo CD и последовательно приложения"
	@echo "  make dashboard-up           - Проверить маршруты и вывести данные доступа"
	@echo "  make vault-up               - Установить HashiCorp Vault и External Secrets Operator"
	@echo "  make secrets-init           - Заполнить локальные секреты в Vault скриптом"
	@echo "  make cloudflare-tunnel-up   - Проверить Cloudflare Tunnel в Kubernetes"
	@echo "  make all-up                 - Полный цикл: кластер -> приложения -> Cloudflare Tunnel"

cluster-up: ## Создать Kind-кластер, если он ещё не существует
	@if kind get clusters | grep -Fxq mediapulse-cluster; then \
		echo "✅ Кластер mediapulse-cluster уже существует; обновляю kubeconfig."; \
		kind export kubeconfig --name mediapulse-cluster; \
	else \
		echo "🚀 Запуск Kind-кластера mediapulse-cluster..."; \
		kind create cluster --config ./kind-config.yaml; \
	fi

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
	@test -f $(ARGOCD_REPO_PATH)/manifests/argocd/values.yaml || { echo "❌ Не найден файл $(ARGOCD_REPO_PATH)/manifests/argocd/values.yaml"; exit 1; }
	@kubectl get ns argocd >/dev/null 2>&1 || kubectl create namespace argocd
	helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 7.0.0 \
		--namespace argocd --values $(ARGOCD_REPO_PATH)/manifests/argocd/values.yaml

	@echo "⏳ Ожидание запуска ArgoCD API сервер..."
	@kubectl -n argocd rollout status deploy/argocd-server --timeout=180s

	@echo "🔄 Последовательная регистрация инфраструктурных приложений в Argo CD..."
	kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/traefik-app.yaml
	@$(MAKE) wait-application APP=traefik
	
	# Добавляем установку Vault и ESO
	@$(MAKE) vault-up

	# Создаём Kubernetes Secret до запуска PostgreSQL
	kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/secrets-app.yaml
	@$(MAKE) wait-application APP=mediapulse-secrets
	@kubectl -n default wait --for=condition=Ready externalsecrets.external-secrets.io/mediapulse-app-secrets --timeout=$(ARGOCD_APP_TIMEOUT)

	kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/databases-app.yaml
	@$(MAKE) wait-application APP=mediapulse-databases

	kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/mediapulse-app.yaml
	@$(MAKE) wait-application APP=mediapulse-app
	kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/kubernetes-dashboard-app.yaml
	@$(MAKE) wait-application APP=kubernetes-dashboard

	kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/cloudflare-tunnel-app.yaml
	@$(MAKE) wait-application-synced APP=cloudflare-tunnel
	@$(MAKE) wait-application APP=cloudflare-tunnel

	@echo "🔄 Передача управления Application-манифестами корневому App of Apps..."
	kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/root.yaml
	@kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced application/root-app --timeout=300s

vault-up: ## Установить HashiCorp Vault и External Secrets Operator через ArgoCD
	@echo "🔒 Установка Vault и External Secrets Operator..."
	@kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/external-secrets-app.yaml
	@$(MAKE) wait-application APP=external-secrets
	@kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/vault-app.yaml
	@$(MAKE) wait-application-synced APP=vault
	@$(MAKE) secrets-init
	@$(MAKE) wait-application APP=vault

secrets-init: ## Инициализировать секреты в Vault
	@echo "🔐 Инициализация Vault и загрузка локальных секретов..."
	bash ./init-local-secrets.sh

wait-application:
	@test -n "$(APP)" || { echo "❌ Укажите APP, например: make wait-application APP=traefik"; exit 1; }
	@echo "⏳ Ожидание синхронизации и готовности Application $(APP)..."
	@$(MAKE) wait-application-synced APP=$(APP)
	@kubectl -n argocd wait --for=jsonpath='{.status.health.status}'=Healthy application/$(APP) --timeout=$(ARGOCD_APP_TIMEOUT) || { \
		echo "❌ Application $(APP) не стало Healthy. Диагностика:"; \
		kubectl -n argocd describe application $(APP); \
		exit 1; \
	}
wait-application-synced:
	@test -n "$(APP)" || { echo "❌ Укажите APP, например: make wait-application-synced APP=vault"; exit 1; }
	@kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced application/$(APP) --timeout=$(ARGOCD_APP_TIMEOUT) || { \
		echo "❌ Application $(APP) не синхронизировалось. Диагностика:"; \
		kubectl -n argocd describe application $(APP); \
		exit 1; \
	}

dashboard-up: ## Запустить скрипт настройки маршрутов и дашбордов
	@echo "🌐 Запуск скрипта конфигурации окружения..."
	@chmod +x ./dev-dashboard.sh
	./dev-dashboard.sh

cloudflare-tunnel-up: ## Проверить удалённо управляемый Cloudflare Tunnel в Kubernetes
	@kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/cloudflare-tunnel-app.yaml
	@$(MAKE) wait-application-synced APP=cloudflare-tunnel
	@bash ./cloudflare-tunnel-up.sh

all-up: cluster-up helm-up argocd-up dashboard-up cloudflare-tunnel-up ## Полный идемпотентный цикл развертывания
	@echo "🎉 Кластер, Argo CD, Vault и приложения успешно развернуты."
	@echo "   Публичный HTTPS доступен через Cloudflare Tunnel."