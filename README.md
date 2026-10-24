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
4. Устанавливает cert-manager и локальный CA, получает TLS-сертификаты для
   локальных хостов, затем через Argo CD разворачивает MetalLB, Traefik,
   Vault и External Secrets Operator. Загружает секреты из `.env` в Vault,
   создаёт из них Kubernetes Secret, и только затем запускает базы и приложение.
   В конце разворачивает Kubernetes Dashboard.
   Vault работает в одноузловом Raft-режиме с PVC. При первом запуске
   `make all-up` автоматически инициализирует и разблокирует Vault, настраивает
   ограниченные AppRole для загрузчика и ESO, а временный root-токен отзывает.
   Unseal-ключ и локальный credential загрузчика хранятся вне репозиториев в
   `~/.config/mediapulse/vault/` с правами `0700/0600`; не удаляйте этот каталог,
   пока используется соответствующий PVC. Потеря каталога при сохранённом PVC
   потребует ручного восстановления. Это упрощённая конфигурация только для
   локального Kind, не production. Данные хранилища остаются внутри локального
   Kind PVC; удаление кластера удалит данные Vault. Unseal-конфигурация 1-of-1
   и plaintext bootstrap credential на хосте выбраны ради автоматического
   локального запуска и не подходят для production.
5. Передаёт Application-манифесты под управление `root-app`, публикует HTTPS
   на порту 443 и выводит данные для доступа.

### 📋 Доступные команды (Makefile)

Выполняйте команды из каталога `local/`.

```bash
make help
```

Показывает список всех доступных команд.

Также доступны `make cluster-up`, `make cluster-down`, `make cluster-status`,
`make argocd-up`, `make dashboard-up` и `make traefik-https-proxy`.

### 🔑 Доступ к панелям управления

После выполнения `make all-up` данные для входа выводятся в терминал:

- Argo CD UI: `https://argocd.local/`, логин `admin`.
- Kubernetes Dashboard: `https://k8s.local/`, вход по выведенному токену.
- Mediapulse app: `https://mediapulse.local/`.

> [!NOTE]
> Команда `make all-up` автоматически публикует HTTPS Traefik на порту 443;
> port-forward запускать не нужно. В Windows добавьте в
> `C:\Windows\System32\drivers\etc\hosts` строку, подставив адрес
> WSL2, который вывел `make all-up`:
> ```
> <WSL2_IP> argocd.local traefik.local k8s.local mediapulse.local
> ```
> Запросы направляются в Traefik через WSL2; имена доменов маршрутизируются
> внутри Traefik по Host header.
> Для имён `.local` используется локальный CA: публичные CA не выдают для них
> сертификаты. `make all-up` запускает cert-manager, который выпускает и
> обновляет сертификаты для хостов и внутреннего HTTPS Dashboard. Чтобы убрать
> предупреждение браузера, установите `~/.config/mediapulse/pki/ca.crt` в
> доверенные корневые сертификаты ОС/браузера. Приватный ключ CA не хранится в Git.



📁 Структура репозитория
Plaintext
mediapulse-infra/
├── local/
│   ├── kind-config.yaml       # Топология Kind-кластера (1 Master + 3 Workers)
│   ├── dev-dashboard.sh       # Проверка готовности маршрутов и вывод токенов
│   └── Makefile               # Точки входа для автоматизации
└── README.md                  # Документация проекта