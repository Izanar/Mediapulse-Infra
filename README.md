# 🏗️ MediaPulse Infrastructure (`mediapulse-infra`)

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.30+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Kind](https://img.shields.io/badge/Kind-Local%20Cluster-000000?logo=docker&logoColor=white)](https://kind.sigs.k8s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)](https://argoproj.github.io/)
[![NGINX Ingress](https://img.shields.io/badge/NGINX-Ingress-009639?logo=nginx&logoColor=white)](https://kubernetes.github.io/ingress-nginx/)

Инфраструктурный репозиторий проекта **MediaPulse**. Содержит конфигурации кластера Kubernetes (Kind), сетевые манифесты, настройки Ingress и средства автоматизации развертывания (GitOps / ArgoCD).

---

## 🚀 Быстрый старт (Одна команда)

Убедитесь, что у вас установлены `Docker`, `kubectl` и `kind`, затем выполните:

```bash
make all-up
Эта команда автоматически:
1. Создаст локальный мульти-нодовый кластер Kind (1 Control-Plane + 3 Worker ноды).
2. Развернет NGINX Ingress Controller.
3. Установит ArgoCD в отдельный namespace.
4. Запустит дашборды и пробросит порты.

📋 Доступные команды (Makefile)
make help
Показать список всех доступных команд

make cluster-up
Развернуть локальный Kind-кластер

make cluster-down
Удалить кластер и освободить ресурсы

make cluster-status
Вывести статус нод кластера (kubectl get nodes)

make ingress-up
Установить NGINX Ingress Controller

make argocd-up
Установить и настроить ArgoCD

make dev-gui
Запустить скрипт мониторинга и веб-интерфейсов

🔑 Доступ к панелям управления (GUI)
После выполнения make dev-gui вам будут доступны:
ArgoCD UI: https://localhost:8080
Логин: admin
Пароль: Выведется в терминале при запуске make argocd-up (или извлекается секретом: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

Kubernetes Dashboard: https://localhost:8443
Токен: Автоматически копируется в буфер обмена (или выводится в терминал скриптом).

📁 Структура репозитория
Plaintext
mediapulse-infra/
├── local/
│   ├── kind-config.yaml       # Топология Kind-кластера (1 Master + 3 Workers)
│   └── dev-dashboard.sh       # Скрипт проброса портов и генерации токена K8s Dashboard
├── Makefile                   # Точки входа для автоматизации
└── README.md                  # Документация проекта