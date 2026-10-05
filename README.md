# 🚀 MediaPulse Infrastructure (`mediapulse-infra`)

![Kubernetes](https://img.shields.io/badge/kubernetes-v1.29.2-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Kind](https://img.shields.io/badge/kind-local--cluster-2088FF?style=for-the-badge&logo=docker&logoColor=white)
![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)
![NGINX Ingress](https://img.shields.io/badge/Ingress-NGINX-009639?style=for-the-badge&logo=nginx&logoColor=white)

Декларативное описание локальной Kubernetes-инфраструктуры для облачной платформы обработки медиа-контента **MediaPulse**.

---

## 🏗 Architecture Topology

Локальный кластер разворачивается с помощью **Kind** (Kubernetes in Docker) поверх WSL2/Ubuntu:

* **1 Control-Plane Node:** Служит единой точкой входа для управления и проброса HTTP(80)/HTTPS(443) трафика.
* **3 Worker Nodes:** Для обеспечения высокой доступности и горизонтального масштабирования микросервисов приложения.

---

## 🛠 Быстрый старт

Управление кластером и инструментами полностью автоматизировано через `make`.

### 1. Развертывание кластера

make cluster-up

### 2. Установка NGINX Ingress & ArgoCD

make ingress-up
make argocd-up

### 3. Запуск веб-интерфейсов (UI)

make dev-gui
Команда автоматически запустит проброс портов и скопирует токен доступа в буфер обмена:

ArgoCD UI: https://localhost:8080 (Логин: admin)

K8s Dashboard: https://localhost:8443

📁 Структура репозитория
Plaintext
mediapulse-infra/
├── local/
│   ├── kind-config.yaml       # Топология Kind-кластера (1 Master + 3 Workers)
│   └── dev-dashboard.sh       # Скрипт проброса портов и генерации токена K8s Dashboard
├── Makefile                   # Точки входа для автоматизации
└── README.md                  # Документация проекта