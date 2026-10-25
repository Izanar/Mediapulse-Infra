ARGOCD_REPO_PATH ?= ../../Mediapulse-Gitops/local
ARGOCD_APP_TIMEOUT ?= 600s
PUBLIC_URL ?= https://mediapulse.izanar.dev/
PUBLIC_CHECK_TIMEOUT ?= 180

.PHONY: help cluster-up cluster-down cluster-status helm-up argocd-install vault-init-env argocd-up vault-secrets apps-up public-check wait-application wait-application-synced all-up
.NOTPARALLEL: all-up

help: ## Показать список доступных команд
	@echo "Доступные команды в mediapulse-infra:"
	@echo "  make cluster-up             - Создать Kind-кластер"
	@echo "  make cluster-down           - Удалить Kind-кластер"
	@echo "  make cluster-status         - Проверить статус нод кластера"
	@echo "  make helm-up                - Установить Helm CLI"
	@echo "  make argocd-install         - Установить только Argo CD (Helm)"
	@echo "  make argocd-up              - Применить корневой App-of-Apps (управляет всеми приложениями)"
	@echo "  make all-up                 - Полный цикл с проверкой публичного HTTPS"

cluster-up: ## Создать Kind-кластер, если он ещё не существует
	@echo ""
	@echo "▶ [1/6] Создание Kind-кластера..."
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
	@echo ""
	@echo "▶ [2/6] Установка Helm CLI..."
	@if command -v helm >/dev/null 2>&1; then \
		echo "✅ Helm уже установлен: $$(helm version --short)"; \
	else \
		echo "📦 Установка Helm CLI..."; \
		curl -fsSL -o /tmp/get-helm-3 https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
		chmod 700 /tmp/get-helm-3 && /tmp/get-helm-3; \
	fi

argocd-install: ## Установить только Argo CD (Helm)
	@echo ""
	@echo "▶ [3/6] Установка Argo CD..."
	@echo "📦 Установка Argo CD..."
	@command -v helm >/dev/null 2>&1 || { echo "❌ Helm не найден. Выполни: make helm-up"; exit 1; }
	@test -f $(ARGOCD_REPO_PATH)/manifests/argocd/values.yaml || { echo "❌ Не найден файл $(ARGOCD_REPO_PATH)/manifests/argocd/values.yaml"; exit 1; }
	@kubectl get ns argocd >/dev/null 2>&1 || kubectl create namespace argocd
	helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 7.0.0 \
		--namespace argocd --values $(ARGOCD_REPO_PATH)/manifests/argocd/values.yaml
	@echo "⏳ Ожидание запуска ArgoCD API сервер..."
	@kubectl -n argocd rollout status deploy/argocd-server --timeout=180s

vault-init-env: ## Создать K8s Secret из .env до запуска Job vault-init
	@test -f ../../Mediapulse-App/.env || { echo "❌ Файл .env не найден: ../../Mediapulse-App/.env"; exit 1; }
	@echo "🔐 Создание Secret vault-init-env из .env..."
	@kubectl create secret generic vault-init-env \
		--namespace=default \
		--from-env-file=../../Mediapulse-App/.env \
		--dry-run=client -o=yaml | kubectl apply -f -
	@echo "✅ Secret vault-init-env создан/обновлен"

argocd-up: ## Применить корневой App-of-Apps (управляет всеми приложениями)
	@echo ""
	@echo "▶ [4/6] Применение App-of-Apps (ArgoCD)..."
	@echo "🔄 Применение корневого App-of-Apps..."
	@kubectl apply -f $(ARGOCD_REPO_PATH)/argocd/root.yaml
	@$(MAKE) --no-print-directory wait-application-synced APP=root-app
	@echo "✅ root-app применён. ArgoCD синхронизирует все дочерние Application."
	@echo "   Ожидание готовности Vault, External Secrets и Image Updater..."
	@$(MAKE) --no-print-directory wait-application APP=vault
	@$(MAKE) --no-print-directory wait-application APP=external-secrets
	@$(MAKE) --no-print-directory wait-application APP=argocd-image-updater

wait-application:
	@test -n "$(APP)" || { echo "❌ Укажите APP, например: make wait-application APP=traefik"; exit 1; }
	@echo "⏳ [$(APP)] Ожидание синхронизации и готовности..."
	@$(MAKE) --no-print-directory wait-application-synced APP=$(APP)
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

vault-secrets: ## Дождаться инициализации Vault
	@echo ""
	@echo "▶ [5/6] Секреты и инициализация Vault..."
	@echo "🔄 Запуск синхронизации vault-init в ArgoCD..."
	@kubectl -n argocd patch application vault-init --type merge --patch '{"spec":{"source":{"targetRevision":"HEAD"}}}' || true
	@echo "⏳ Ожидание завершения Job vault-init (инициализация Vault)..."
	@kubectl wait --namespace=default --for=condition=Complete job/vault-init --timeout=300s || { \
		echo "❌ Job vault-init не завершён успешно. Логи:"; \
		kubectl logs --namespace=default job/vault-init --tail=50; \
		exit 1; \
	}
	@echo "✅ Vault инициализирован"

apps-up: ## Дождаться готовности всех прикладных приложений (через ArgoCD)
	@echo ""
	@echo "▶ [6/6] Ожидание готовности приложений..."
	@$(MAKE) --no-print-directory wait-application APP=mediapulse-databases
	@$(MAKE) --no-print-directory wait-application APP=mediapulse-app
	@$(MAKE) --no-print-directory wait-application APP=kubernetes-dashboard
	@$(MAKE) --no-print-directory wait-application APP=cloudflare-tunnel

public-check: ## Проверить доступность приложения через публичный HTTPS
	@echo "🌐 Проверка публичного HTTPS: $(PUBLIC_URL)"
	@deadline=$$(( $$(date +%s) + $(PUBLIC_CHECK_TIMEOUT) )); \
	until curl --fail --silent --show-error --location --max-time 15 --output /dev/null "$(PUBLIC_URL)"; do \
		if [ $$(date +%s) -ge $$deadline ]; then \
			echo "❌ $(PUBLIC_URL) недоступен после $(PUBLIC_CHECK_TIMEOUT)."; \
			exit 1; \
		fi; \
		echo "⏳ Публичный маршрут ещё не готов; повтор через 5 секунд..."; \
		sleep 5; \
	done
	@echo "✅ Публичный HTTPS доступен: $(PUBLIC_URL)"

all-up: cluster-up helm-up argocd-install vault-init-env argocd-up vault-secrets apps-up public-check ## Полный цикл: кластер -> секреты -> ArgoCD -> приложения -> публичный HTTPS
	@echo "🎉 Кластер, Argo CD и приложения успешно развернуты."
	@echo "   Секреты загружены из .env в Vault, External Secrets Operator синхронизирует их в K8s."
	@echo "   Публичный HTTPS доступен через Cloudflare Tunnel."
	@echo ""
	@echo "🖼️  Авто-обновление тегов образов: ArgoCD Image Updater (уже установлен в кластере)."
	@echo "   В текущем режиме (write-back-method: file) Image Updater мониторит GHCR,"
	@echo "   но не пушит теги в Git. Чтобы включить авто-обновление тегов в GitOps:"
	@echo "   1. В UI ArgoCD → Settings → Repositories добавьте credentials к"
	@echo "      https://github.com/Izanar/Mediapulse-Gitops.git (HTTPS: username + PAT,"
	@echo "      или SSH: приватный ключ)."
	@echo "   2. В файле local/charts/backend/templates/api.yaml замените аннотацию"
	@echo "      write-back-method: file на write-back-method: git и раскомментируйте"
	@echo "      git-branch / commit-message."
	@echo "   3. Сделайте git push изменений в Mediapulse-Gitops — ArgoCD поднимет Image"
	@echo "      Updater с правами на запись в репозиторий."
	@echo "   Кластер при этом полностью рабочий и без этих настроек."
