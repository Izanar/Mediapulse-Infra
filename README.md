# 🏗️ MediaPulse Infrastructure (`mediapulse-infra`)

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.30+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Kind](https://img.shields.io/badge/Kind-Local%20Cluster-000000?logo=docker&logoColor=white)](https://kind.sigs.k8s.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo&logoColor=white)](https://argoproj.github.io/)
[![Traefik](https://img.shields.io/badge/Traefik-Ingress%20Controller-24A1C1?logo=traefikproxy&logoColor=white)](https://doc.traefik.io/traefik/)

Инфраструктурный репозиторий проекта **MediaPulse**. Содержит конфигурации кластера Kubernetes (Kind), сетевые манифесты, настройки Ingress и средства автоматизации развертывания (GitOps / ArgoCD).

---

## 🚀 Быстрый старт (Одна команда)

Убедитесь, что у вас установлены `Docker`, `kubectl` и `kind`, затем выполните
из каталога `local/`:

```bash
cd local
make all-up
```

Команда идемпотентна: использует существующий кластер `mediapulse-cluster`,
если он уже создан, и выполняет шаги по порядку:
1. Создаёт Kind-кластер, если его ещё нет.
2. Проверяет наличие Helm.
3. Устанавливает Argo CD без зависимости от ещё не установленного Traefik.
4. Через Argo CD последовательно разворачивает MetalLB, Traefik, базы данных,
   backend и Kubernetes Dashboard, затем передаёт Application-манифесты под
   управление `root-app`.
5. Проверяет готовность компонентов и выводит данные для доступа.

### 📋 Доступные команды (Makefile)

Выполняйте команды из каталога `local/`.

```bash
make help
```

Показывает список всех доступных команд.

Также доступны `make cluster-up`, `make cluster-down`, `make cluster-status`,
`make argocd-up`, `make dashboard-up` и `make traefik-port-forward`.

### 🔑 Доступ к панелям управления

После выполнения `make all-up` данные для входа выводятся в терминал:

- Argo CD UI: `https://argocd.local:8443/`, логин `admin`.
- Kubernetes Dashboard: `https://k8s.local:8443/`, вход по выведенному токену.
- Mediapulse backend: `https://mediapulse.local:8443/`.

> [!NOTE]
> Запустите `make traefik-port-forward` в отдельном терминале. В Windows
> добавьте в `C:\Windows\System32\drivers\etc\hosts` строку, подставив адрес
> WSL2, который вывел `make all-up`:
> ```
> <WSL2_IP> argocd.local traefik.local k8s.local mediapulse.local
> ```
> Для доступа из WSL2 через port-forward используйте `127.0.0.1` в `/etc/hosts`.
> TLS-сертификат самоподписанный; при первом заходе браузер покажет предупреждение.



📁 Структура репозитория
Plaintext
mediapulse-infra/
├── local/
│   ├── kind-config.yaml       # Топология Kind-кластера (1 Master + 3 Workers)
│   ├── dev-dashboard.sh       # Проверка готовности маршрутов и вывод токенов
│   └── Makefile               # Точки входа для автоматизации
└── README.md                  # Документация проекта