ARGOCD_REPO_PATH ?= ../../Mediapulse-Gitops/local
ARGOCD_APP_TIMEOUT ?= 600s

.PHONY: help cluster-up cluster-down cluster-status helm-up argocd-install argocd-up infra-up apps-up secrets-init wait-application wait-application-synced dashboard-up cloudflare-tunnel-up all-up
.NOTPARALLEL: all-up

help: ## Показать список доступных команд
	@echo "Доступные команды в mediapulse-infra:"
	@echo "  make cluster-up             - Создать Kind-кластер"
	@echo "  make cluster-down           - Удалить Kind-кластер"
	@echo "  make cluster-status         - Проверить статус нод кластера"
	@echo "  make helm-up                - Установить Helm CLI"
	@echo "  make argocd-install         - Установить только Argo CD (Helm)"
	@echo "  make argocd-up              - Применить корневой App-of-Apps (управляет всеми приложениями)"
	@echo "  make infra-up               - Дождаться готовности инфраструктуры (Traefik, Vault, ESO)"
	@echo "  make apps-up                - Дождаться готовности приложений (Бэкенд, БД, Дашборд, Туннель)"
	@echo "  make secrets-init           - Загрузить секреты из .env в Vault через Kubernetes Job"
	@echo "  make dashboard-up           - Проверить маршруты и вывести данные доступа"
	@echo "  make cloudflare-tunnel-up   - Проверить Cloudflare Tunnel в Kubernetes"
	@echo "  make all-up                 - Полный цикл: кластер -> ArgoCD -> инфраструктура -> секреты -> приложения"

cluster-up: ## Создать Kind-кластер, если он ещё не существует
	@if kind get clusters | grep -Fxq mediapulse-cluster; then \
		echo "✅ Кластер mediapulse-cluster уже существует; обновляю kubeconfig."; \
		kind export kubeconfig --name mediapulse-cluster; \
	else \
		echo "🚀 Запуск Kind-кластера mediapulse-cluster..."; \
		kind create cluster --config ./kind-config.yaml; \
	fi
	@echo "🔧 Настройка лимита inotify для kube-proxy..."
	@docker exec mediapulse-cluster-control-plane sysctl -w fs.inotify.max_user_instances=1024
	@unready_pods=$$(kubectl -n kube-system get pods -l k8s-app=kube-proxy --no-headers | awk '$$2 != "1/1" {print $$1}'); \
	if [ -n "$$unready_pods" ]; then \
		echo "🔄 Перезапуск неготовых kube-proxy pods..."; \
		echo "$$unready_pods" | xargs -r kubectl -n kube-system delete pod --wait=false; \
	fi
	@kubectl -n kube-system rollout status daemonset/kube-proxy --timeout=180s

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

argocd-install: ## Установить только Argo CD (Helm)
	@echo "📦 Установка Argo CD..."
	@command -v helm >/dev/null 2>&1 || { echo "❌ Helm не найден. Выполни: make helm-up"; exit 1; }
	@test -f $(ARGOCD_REPO_PATH)/manifests/argocd/values.yaml || { echo "❌ Не найден файл $(ARGOCD_REPO_PATH)/manifests/argocd/values.yaml"; exit 1; }
	@kubectl get ns argocd >/dev/null 2>&1 || kubectl create namespace argocd
	helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 7.0.0 \
		--namespace argocd --values $(ARGOCD_REPO_PATH)/manifests/argocd/values.yaml
	@echo "⏳ Ожидание запуска ArgoCD API сервер..."
	@kubectl -n argocd rollout status deploy/argocd-server --timeout=180s

argocd-up: ## Применить корневой App-of-Apps (управляет всеми приложениями)
	@echo "🔄 Применение корневого App-of-Apps..."
	@kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/root.yaml
	@kubectl -n argocd wait --for=jsonpath='{.status.sync.status}'=Synced application/root-app --timeout=300s
	@echo "✅ root-app применён. ArgoCD синхронизирует все дочерние Application."
	@echo "⏳ Ожидание готовности инфраструктурных приложений..."
	@$(MAKE) wait-application APP=traefik
	@$(MAKE) wait-application APP=vault
	@$(MAKE) wait-application APP=external-secrets

secrets-init: ## Загрузить секреты из .env в Vault через Kubernetes Job
	@test -f ../../Mediapulse-App/.env || { echo "❌ Файл .env не найден: ../../Mediapulse-App/.env"; exit 1; }
	@echo "🔐 Создание Secret vault-init-env из .env..."
	@kubectl create secret generic vault-init-env \
		--namespace=default \
		--from-env-file=../../Mediapulse-App/.env \
		--dry-run=client -o=yaml | kubectl apply -f -
	@echo "📦 Применение ArgoCD Application vault-init..."
	@kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/vault-init-app.yaml
	@echo "🔄 Перезапуск Job vault-init..."
	@kubectl delete job vault-init --namespace=default --ignore-not-found
	@echo "⏳ Ожидание завершения Job vault-init..."
	@kubectl wait --namespace=default --for=condition=Complete job/vault-init --timeout=300s || { \
		echo "❌ Job vault-init не завершён успешно. Логи:"; \
		kubectl logs --namespace=default job/vault-init --tail=50; \
		exit 1; \
	}
	@echo "✅ Секреты загружены в Vault"
	@echo "⏳ Ожидание готовности прикладных приложений..."
	@$(MAKE) wait-application APP=mediapulse-databases
	@$(MAKE) wait-application APP=mediapulse-app
	@$(MAKE) wait-application APP=kubernetes-dashboard
	@$(MAKE) wait-application APP=cloudflare-tunnel

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

all-up: cluster-up helm-up argocd-install argocd-up secrets-init dashboard-up ## Полный идемпотентный цикл развертывания
	@echo "🎉 Кластер, Argo CD, Vault и приложения успешно развернуты."
	@echo "   Публичный HTTPS доступен через Cloudflare Tunnel."
