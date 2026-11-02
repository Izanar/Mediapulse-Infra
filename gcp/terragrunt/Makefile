TG ?= terragrunt
TG_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: help init plan apply destroy destroy-all output clean

help:
	@echo "Terragrunt управление (GCP инфраструктура)"
	@echo "  make init      - terragrunt run -- run-all init"
	@echo "  make plan      - terragrunt run -- run-all plan"
	@echo "  make apply     - terragrunt run -- run-all apply -auto-approve"
	@echo "  make destroy   - terragrunt run -- run-all destroy -auto-approve"
	@echo "  make output    - terragrunt run -- run-all output"
	@echo "  make clean     - удалить локальный кэш"

init:
	@echo "🔧 terragrunt run -- run-all init"
	cd $(TG_ROOT) && TG_CONFIG=root.hcl $(TG) run -- run-all init

plan:
	@echo "📋 terragrunt run -- run-all plan"
	cd $(TG_ROOT) && TG_CONFIG=root.hcl $(TG) run -- run-all plan

apply:
	@echo "🚀 terragrunt run -- run-all apply -auto-approve"
	cd $(TG_ROOT) && TG_CONFIG=root.hcl $(TG) run -- run-all apply -auto-approve

destroy destroy-all:
	@echo "⚠️  terragrunt run -- run-all destroy -auto-approve"
	cd $(TG_ROOT) && TG_CONFIG=root.hcl $(TG) run -- run-all destroy -auto-approve

output:
	@echo "📤 terragrunt run -- run-all output"
	cd $(TG_ROOT) && TG_CONFIG=root.hcl $(TG) run -- run-all output

clean:
	@echo "🧹 Очистка локального кэша..."
	find . -type d -name ".terragrunt-cache" -exec rm -rf {} +
	find . -type d -name ".terraform" -exec rm -rf {} +
	find . -name ".terraform.lock.hcl" -delete
	@echo "✨ Готово."
