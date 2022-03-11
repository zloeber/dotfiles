VAULT_VERSION ?= 1.7.3
VAULT_ADDRESS ?= $(shell $(docker_cmd) inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vault 2> /dev/null)
VAULT_LOCAL_CONFIG := '{"listener": [{"tcp":{"address": "0.0.0.0:8200","tls_disable":"true"}}], "default_lease_ttl": "168h", "max_lease_ttl": "720h"}, "ui": true}'
PROJECT_BIN_PATH ?= $(ROOT_PATH)/.local/bin
VAULT_CONFIG ?= $(shell cat $(CONFIG_PATH)/vaultconf.json | jq -rc .)

vault := $(PROJECT_BIN_PATH)/vault
vault_ent := $(PROJECT_BIN_PATH)/vault_ent
vault-monitor := $(PROJECT_BIN_PATH)/vault-monitor

# Used in some specific terraform modules (ssh)
export TF_VAR_vault_environment=$(VAULT_ENVIRONMENT)

# Setup proper vault provider variables
VAULT_ADDR:=http://127.0.0.1:8200
VAULT_TOKEN:=root
DOCKER_NETWORK?=

VAULT_RUNNER_NS=vault-config

.PHONY: .dep/vault/oss
.dep/vault/oss: ## Install local terraform binary
ifeq (,$(wildcard $(vault)))
	@echo "Attempting to install vault $(VAULT_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL -o /tmp/vault.zip https://nexus.nmlv.nml.com/repository/nmlv-artifacts/idampxm/vault/vault_$(VAULT_VERSION)_$(OS)_$(ARCH).zip 
	@unzip -d $(PROJECT_BIN_PATH) /tmp/vault.zip && rm /tmp/vault.zip
endif
	@echo "vault binary: $(vault)"

.PHONY: .dep/vault
.dep/vault: ## Install local vault binary
ifeq (,$(wildcard $(vault)))
	@echo "Attempting to install vault $(VAULT_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL \
		-o /tmp/vault_ent.zip \
		https://nexus.nmlv.nml.com/repository/nmlv-artifacts/idampxm/vault/vault-enterprise_$(VAULT_VERSION)+prem_$(OS)_$(ARCH).zip 
	@unzip -d $(PROJECT_BIN_PATH) /tmp/vault_ent.zip && rm /tmp/vault_ent.zip
endif
	@echo "vault binary: $(vault)"

.PHONY: vault/env
vault/env: ## Show local vault vars for export to env vars
	@echo "export VAULT_ADDR=$(VAULT_ADDR)"
	@echo "export VAULT_TOKEN=$(VAULT_TOKEN)"

.PHONY: vault/show
vault/show: ## Show local vault vars
	@echo "VAULT_ADDR=$(VAULT_ADDR)"
	@echo "VAULT_ADDRESS=$(VAULT_ADDRESS)"
	@echo "VAULT_TOKEN=$(VAULT_TOKEN)"
	@echo "VAULT_CONFIG=$(VAULT_CONFIG)"

.PHONY: vault/start
vault/start: ## Start a local vault dev server in docker
ifndef IS_CI
	docker run --name vault \
		--cap-add=IPC_LOCK --detach --rm \
		-e 'VAULT_LOCAL_CONFIG=$(VAULT_CONFIG)' \
		-e 'VAULT_DEV_ROOT_TOKEN_ID=root' \
		-e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200' \
		-p 8200:8200 $(DOCKER_NETWORK) \
		$(VAULT_IMAGE)
endif
ifdef IS_CI
	vault server -dev \
		-dev-root-token-id="root" \
		-dev-listen-address="0.0.0.0:8200"
endif

.PHONY: .dep/vault-monitor
.dep/vault-monitor:
ifeq (,$(wildcard $(vault-monitor)))
	@mkdir -p /tmp/hashicorp-vault-monitor
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL -L -o /tmp/hashicorp-vault-monitor/hashicorp-vault-monitor.zip https://github.com/madrisan/hashicorp-vault-monitor/releases/download/v0.8.5/darwin_amd64.zip
	@unzip /tmp/hashicorp-vault-monitor/hashicorp-vault-monitor.zip -d /tmp/hashicorp-vault-monitor
	@find /tmp/hashicorp-vault-monitor -type f -name hashicorp-vault-monitor | xargs -I {} cp -f {} $(vault-monitor)
	@chmod +x $(vault-monitor)
	@[ -n "/tmp" ] && [ -n "hashicorp-vault-monitor" ] && rm -rf "/tmp/hashicorp-vault-monitor"
endif
	@echo "vault-monitor binary: $(vault-monitor)"

.PHONY: vault/metrics
vault/metrics: ## Stop a local vault dev server in docker
	vault read sys/metrics format="prometheus"

.PHONY: vault/stop
vault/stop: ## Stop a local vault dev server in docker
ifndef IS_CI
	@echo "Stopping vault container: vault"
	@docker stop vault 2>/dev/null || true
endif
	@echo "Local vault image stopped: $(VAULT_IMAGE)"

.PHONY: vault/deploy/baseconfig
vault/deploy/baseconfig: ## Deploys the baseconfig for a local environment
	@$(MAKE) TF_PATH=$(DEPLOY_PATH)/baseconfig tf/init tf/plan tf/visualize tf/apply

.PHONY: vault/deploy/triggered
vault/deploy/triggered: ## Deploys the kube auth mount for a local environment
	@$(MAKE) TF_PATH=$(DEPLOY_PATH)/triggered tf/init tf/plan tf/apply

.PHONY: vault/deploy/resources
vault/deploy/resources: ## Deploys vault resources for local environment
	@$(MAKE) TF_PATH=$(DEPLOY_PATH)/resources tf/init tf/plan tf/visualize tf/apply

.PHONY: vault/deploy/other
vault/deploy/other: ## Deploys other for local environment (for pki).
	@$(MAKE) TF_PATH=$(DEPLOY_PATH)/other tf/init tf/plan  tf/visualize tf/apply

.PHONY: vault/deploy/manual
vault/deploy/manual: ## Deploys manual elements for local environment (for development).
	@$(MAKE) TF_PATH=$(DEPLOY_PATH)/manual tf/init tf/plan tf/visualize tf/apply

.PHONY: vault/deploy/auth
vault/deploy/auth: ## Deploys vault auth for local environment
	@$(MAKE) TF_PATH=$(DEPLOY_PATH)/auth tf/init tf/plan tf/visualize tf/apply

.PHONY: vault/deploy/seed
vault/deploy/seed: ## Deploys vault seeds for local environment
	@$(MAKE) TF_PATH=$(DEPLOY_PATH)/seed \
	TF_VAR_minikubedemo199_kubeconfig='$(shell cat $(KIND_KUBE_CONFIG) || echo "NA")' \
	TF_VAR_localcluster_kubeconfig='$(shell cat $(KIND_KUBE_CONFIG) || echo "NA")' \
	tf/init tf/plan tf/visualize tf/apply

.PHONY: vault/deploy
vault/deploy: ## deploys vault configuration
	@$(MAKE) vault/deploy/baseconfig \
		vault/deploy/resources \
		vault/deploy/seed \
		vault/deploy/triggered \
		vault/deploy/other \
		vault/deploy/auth

.PHONY: .vault/ui/start
.vault/ui/start: ## Start a local alternate vault ui
ifndef IS_CI
	docker run --detach --rm \
		-e VAULT_URL_DEFAULT=http://$(shell docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(VAULT_IMAGE)):8200 \
		-e VAULT_AUTH_DEFAULT=TOKEN \
		-p 8000:8000 $(DOCKER_NETWORK) \
		--name vault-ui \
		djenriquez/vault-ui
endif

.PHONY: .vault/ui/stop
.vault/ui/stop: ## Stop local alternate vault ui
	@$(docker_cmd) stop vault-ui || true

.PHONY: .vault/ui/show
.vault/ui/show: ## Show local alternate vault ui (password=root)
	@open http://127.0.0.1:8000

.PHONY: vault/ui
vault/ui: ## Show local vault ui (password=root)
	@open $(VAULT_ADDR)

.PHONY: vault/build
vault/build: ## Creates local vault images
ifndef IS_CI
	$(docker_cmd) pull $(VAULT_IMAGE)
#	@$(MAKE) --no-print-directory -C $(ROOT_PATH)/images/docker-vault build VAULT_VERSION=$(VAULT_VERSION)
endif

.PHONY: vault/status
vault/status: ## Show status of current vault deployment
	@$(vault) status

.PHONY: vault/disable/kv
vault/disable/kv: ## Removes default kv secret mount if exists
	@$(vault) secret disable secret || true

.PHONY: vault/reset
vault/reset: \
	vault/stop \
	vault/start \
	clean/state \
	vault/deploy ## Reset and reconfigure vault instance

.PHONY: vault/runner/deploy
vault/runner/deploy: ## Deploy vault runner helm chart
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(VAULT_RUNNER_NS) || true
	@$(helm) -n $(VAULT_RUNNER_NS) --kubeconfig $(KIND_KUBE_CONFIG) \
		upgrade -i vault-config-admin $(ROOT_PATH)/charts/vault-config \
		--set "vault.name=vault-config-admin" \
		--set "serviceAccount.name=vault-config-admin" \
		--set "vault.address=http://$(VAULT_ADDRESS):8200" \
		--set "vault.csi=true" \
		--set "vault.role=kubernetes_kind_vault-config_vault_config_admin"