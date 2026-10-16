# 🏗️ MediaPulse Infrastructure (`mediapulse-infra`)

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.30+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Kind](https://img.shields.io/badge/Kind-Local%20Cluster-000000?logo=docker&logoColor=white)](https://kind.sigs.k8s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)](https://argoproj.github.io/)
[![Traefik](https://img.shields.io/badge/Traefik-Ingress%20Controller-24A1C1?logo=traefikproxy&logoColor=white)](https://doc.traefik.io/traefik/)

Инфраструктурный репозиторий проекта **MediaPulse**. Содержит конфигурации кластера Kubernetes (Kind), сетевые манифесты, настройки Ingress и средства автоматизации развертывания (GitOps / ArgoCD).

---

## 🚀 Быстрый старт (Одна команда)

Убедитесь, что у вас установлены `Docker`, `kubectl` и `kind`, затем выполните:

```bash
make all-up
Эта команда автоматически:
1. Создаст локальный мульти-нодовый кластер Kind (1 Control-Plane + 3 Worker ноды).
2. Развернет Traefik Ingress Controller.
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
Установить Traefik Ingress Controller

make argocd-up
Установить ArgoCD через Helm (идемпотентно). Единственная точка установки ArgoCD —
скрипт dev-dashboard.sh её не дублирует, а только проверяет, что ArgoCD развёрнут.

make dev-gui
Развернуть веб-интерфейсы (ArgoCD + Kubernetes Dashboard) через Ingress.
⚠️ Требует, чтобы ArgoCD уже был установлен командой make argocd-up.

🔑 Доступ к панелям управления (GUI)
После выполнения make dev-gui вам будут доступны:
ArgoCD UI: https://argocd.local
Логин: admin
Пароль: Выведется в терминале при запуске make argocd-up (или извлекается секретом: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

Kubernetes Dashboard: https://dashboard.local
Токен: Автоматически копируется в буфер обмена (или выводится в терминал скриптом).
> [!NOTE]
> Оба адреса работают через Traefik Ingress Controller, который пробрасывает
> порты 80/443 из Kind-ноды на хост (см. `extraPortMappings` в `kind-config.yaml`).
> Убедитесь, что в `/etc/hosts` (Windows: `C:\Windows\System32\drivers\etc\hosts`)
> есть строка:
> ```
> 127.0.0.1 argocd.local dashboard.local
> ```
> Своего TLS-сертификата нет намеренно: секции `tls` в манифестах нет, поэтому
> Traefik отдаёт свой дефолтный самоподписанный сертификат, и браузер при
> первом заходе покажет предупреждение — его нужно принять один раз. Так в
> кластере и репозитории не появляется секрет с приватным ключом. Когда появится
> домен или cert-manager, достаточно добавить секцию `tls` в `argocd-ingress.yaml`.



📁 Структура репозитория
Plaintext
mediapulse-infra/
├── local/
│   ├── kind-config.yaml       # Топология Kind-кластера (1 Master + 3 Workers)
│   └── dev-dashboard.sh       # Скрипт развёртывания веб-интерфейсов (Ingress + токен K8s Dashboard).
                               # ArgoCD здесь НЕ устанавливается — только make argocd-up это делает.
├── Makefile                   # Точки входа для автоматизации
└── README.md                  # Документация проекта