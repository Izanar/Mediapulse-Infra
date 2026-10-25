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
   При каждом запуске также настраивает лимит inotify, необходимый `kube-proxy`,
   и ждёт готовности сетевого прокси.
2. Проверяет наличие Helm.
3. Устанавливает Argo CD без зависимости от ещё не установленного Traefik.
4. Через Argo CD разворачивает Traefik, Vault и External Secrets Operator.
   Загружает секреты из `.env` в Vault,
   создаёт из них Kubernetes Secret, и только затем запускает базы и приложение.
   В конце разворачивает Kubernetes Dashboard.
   Vault работает в одноузловом Raft-режиме с PVC. При первом запуске
   `make all-up` автоматически инициализирует и разблокирует Vault, настраивает
   KV v2 secrets engine и ограниченные AppRole для загрузчика и ESO, а временный
   root-токен отзывает. Если KV v2 не был создан при первом запуске, скрипт
   временно восстанавливает root-доступ с локального unseal-ключа, создаёт engine
   и снова отзывает токен.
   Unseal-ключ и локальный credential загрузчика хранятся вне репозиториев в
   `~/.config/mediapulse/vault/` с правами `0700/0600`; не удаляйте этот каталог,
   пока используется соответствующий PVC. Потеря каталога при сохранённом PVC
   потребует ручного восстановления. Это упрощённая конфигурация только для
   локального Kind, не production. Данные хранилища остаются внутри локального
   Kind PVC; удаление кластера удалит данные Vault. Unseal-конфигурация 1-of-1
   и plaintext bootstrap credential на хосте выбраны ради автоматического
   локального запуска и не подходят для production.
5. Передаёт Application-манифесты под управление `root-app`, запускает
   Cloudflare Tunnel connector в Kubernetes и выводит данные для доступа.

### 📋 Доступные команды (Makefile)

Выполняйте команды из каталога `local/`.

```bash
make help
```

Показывает список всех доступных команд.

Также доступны `make cluster-up`, `make cluster-down`, `make cluster-status`,
`make argocd-up`, `make dashboard-up` и `make cloudflare-tunnel-up`.

### 🔑 Доступ к панелям управления

После выполнения `make all-up` данные для входа выводятся в терминал:

- Argo CD UI: `https://argocd.izanar.dev/`, логин `admin`; требуется Cloudflare Access.
- Kubernetes Dashboard: `https://kind.izanar.dev/`; требуется Cloudflare Access и токен Dashboard.
- Mediapulse app: `https://mediapulse.izanar.dev/`.
- Traefik UI: `https://traefik.izanar.dev/dashboard/`; требуется Cloudflare Access.

#### Однократная настройка Cloudflare Tunnel

1. В аккаунте уже настроен remotely-managed Tunnel
   `ALbert-mediapulse-cluster-tunnel`. Для него созданы Published application
   routes и DNS-записи для четырёх hostname ниже. Для каждого route укажите
   origin `http://traefik.traefik.svc.cluster.local:80`; connector в Kubernetes
   разрешает это внутреннее имя. Внешний IP, MetalLB, NodePort и проброс
   портов на роутере не нужны. HTTPS для посетителей завершается на Cloudflare.
2. Cloudflare Access application `MediaPulse Admin Interfaces` защищает
   `argocd.izanar.dev`, `kind.izanar.dev` и `traefik.izanar.dev` политикой
   **Allow** только для настроенного адреса владельца. Не публикуйте
   административные панели без Access. `mediapulse.izanar.dev` оставлен
   публичным; вход в само приложение контролируется его авторизацией.
3. В скопированном `Mediapulse-App/.env` задайте `CLOUDFLARE_TUNNEL_TOKEN`
   значением connector token из Tunnel Dashboard. Добавьте строку из
   `.env.example`, затем вставьте token локально. Не передавайте его в чат и
   не коммитьте: `.env` игнорируется Git. Во время `make all-up` скрипт
   `init-local-secrets.sh` запишет его в Vault рядом с остальными локальными
   секретами. External Secrets Operator создаст Kubernetes Secret, который
   монтируется в Pod `cloudflared`; token не помещается в Git, а временный
   root-токен Vault отзывается после bootstrap:

   ```bash
   cp -n ../../Mediapulse-App/.env.example ../../Mediapulse-App/.env
   # В .env установите CLOUDFLARE_TUNNEL_TOKEN=<connector-token>
   ```

После этого `make all-up` запустит connector Pod `cloudflare/cloudflared` в
кластере, а `make cloudflare-tunnel-up` можно использовать для повторной
проверки и запуска. Публичные адреса:

| Сервис | URL | Защита |
| --- | --- | --- |
| Mediapulse | `https://mediapulse.izanar.dev/` | Авторизация приложения |
| Argo CD | `https://argocd.izanar.dev/` | Cloudflare Access |
| Traefik Dashboard | `https://traefik.izanar.dev/dashboard/` | Cloudflare Access |
| Kubernetes Dashboard | `https://kind.izanar.dev/` | Cloudflare Access и токен Dashboard |

Cloudflare Tunnel маршрутизирует origin на внутренний HTTP Service
`traefik.traefik.svc.cluster.local:80`; исходное имя хоста используется Traefik
для выбора сервиса. Публичный TLS заканчивается на Cloudflare, а connector
устанавливает только исходящие соединения с Cloudflare. В текущей конфигурации
участок от `cloudflared` до Traefik работает по HTTP; внутренний CA и
автоматическая выдача сертификатов подам не настроены. TLS между Traefik и
приложением определяется настройками конкретного маршрута и сервиса, а не
Cloudflare Tunnel. Поэтому эта схема шифрует публичный участок до Cloudflare,
но не обеспечивает сквозной HTTPS внутри кластера.



📁 Структура репозитория
Plaintext
mediapulse-infra/
├── local/
│   ├── kind-config.yaml       # Топология Kind-кластера (1 Master + 3 Workers)
│   ├── dev-dashboard.sh       # Проверка готовности маршрутов и вывод токенов
│   └── Makefile               # Точки входа для автоматизации
└── README.md                  # Документация проекта