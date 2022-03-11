AWX_VERSION?=0.12.0
SECRET_NAME?=app1/helloworld
SECRET_MOUNT?=controller/kv
SECRET_DATA?=username=foobaruser password=foobarbazpass
SECRET_SA?=app1-svc
SECRET_NS?=app1
VAULT_KV_PATH:=controller/kv
VAULT_KV_SECRET:=kube/kind
# VAULT_KV_SECRET_NAME:=token_reviewer_jwt
# VAULT_KV_SECRET_VALUE:=$(shell cat $(LOCAL_PATH)/token_reviewer_jwt.txt 2> /dev/null)
# Path used deep within a running docker container in a kube deployment
SECRET_INJECTION_PATH?=/vault/secrets/secrets-store
VAULT_ROLE?=kubernetes_kind_$(SECRET_NS)_$(SECRET_SA)
VAULT_CERTMANAGER_NS?=cert-manager
VAULT_CERTMANAGER_AUTH?=token
VAULT_APPROLE_ID?=$(cat $(CONFIG_PATH)/app1_role_id.txt)

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root

.PHONY: lab
lab: lab/start ## Start kube/vault lab environment

.PHONY: lab/start/network
lab/start/network: ## Create a kind network if one does not already exist
ifeq (,$(shell docker network list | grep kind))
	@echo "Attempting to install kind network..."
	@docker network create kind
else
	@echo "Docker kind network for lab ready!"
endif

.PHONY: lab/stop
lab/stop: ## Stop lab environment
	@$(MAKE) controller/stop openldap/stop .kube/helm/clean

.PHONY: lab/start
lab/start:
export DOCKER_NETWORK=--net kind
lab/start: lab/start/network lab/stop ## Start lab environment (openldap/kube/vault)
	echo "DOCKER_NETWORK: $(DOCKER_NETWORK)"
	@$(MAKE) \
		deps \
		lab/start/network \
		lab/openldap
	@$(MAKE) \
		kube/start \
		docker/build
	@$(MAKE) \
		vault/start \
		vault/disable/kv \
		bundle \
		vault/deploy/baseconfig \
		vault/deploy/resources
	@$(MAKE) \
		kube/vault/cronjob \
		kube/vault/cronjob/run \
		kube/export
	@$(MAKE) \
		kube/vault/auth/seed \
		vault/deploy/triggered \
		vault/deploy/auth \
		vault/deploy/other

.PHONY: lab/openldap
lab/openldap:
export DOCKER_NETWORK=--net kind
lab/openldap: ## Deploy OpenLDAP container on kind network
	@$(MAKE) \
		openldap/stop \
		openldap/start
	@echo "Sleeping for 15 seconds to ensure OpenLDAP has started before initializing with some users/groups/ous.."
	@sleep 15
	@$(MAKE) \
		openldap/init

.PHONY: lab/openldap/ui
lab/openldap/ui: ## Reset local openladp container on kind network and open the UI
	@$(MAKE) \
		openldap/ui \
		DOCKER_NETWORK="--net kind"

.PHONY: lab/vault/reset
lab/vault/reset:
export DOCKER_NETWORK=--net kind
lab/vault/reset: ## Redeploy existing tf bundle files to vault
	@$(MAKE) vault/stop tf/clean \
		vault/start \
		vault/disable/kv \
		vault/deploy \
		VAULT_IMAGE=$(VAULT_IMAGE)

.PHONY: lab/show
lab/show: ## Show some lab info
	@echo "VAULT_IMAGE: $(VAULT_IMAGE)"
	@echo "VAULT_ADDRESS: $(VAULT_ADDRESS)"
	@echo "SECRET_NS: $(SECRET_NS)"
	@echo "SECRET_SA: $(SECRET_SA)"
	@echo "SECRET_NAME: $(SECRET_NAME)"
	@echo "SECRET_MOUNT: $(SECRET_MOUNT)"
	@echo "SECRET_INJECTION_PATH: $(SECRET_INJECTION_PATH)"
	@echo "VAULT_ROLE: $(VAULT_ROLE)"
	@echo "ENT: $(ENT)"
	@echo "VAULTRC_CONFIG: $(VAULTRC_CONFIG)"

.PHONY: lab/kube/shell
lab/kube/shell: ## Create a pod and enter a bash shell in the cluster vault namespace
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(VAULT_NS) || true
	@$(kind) load docker-image $(DOCKER_IMAGE):local || true
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) run test-shell \
		--rm -i --tty --image $(DOCKER_IMAGE):local \
		--env="VAULT_ADDR=http://$(VAULT_ADDRESS):8200" \
		--env="VAULT_AUTH_METHOD=token" \
		--env="KUBE_CLUSTER=kind" \
		--env="KUBE_OWNER=controller" \
		--env="KUBE_URL=$(KUBE_URL)" \
		--env="VAULT_KV_PATH=controller/kv" \
		--env="VAULT_KV_SECRET=controller/kind/vault_auth" \
		--env="VAULT_AWS_ROLE=" \
		--env="VAULT_AWS_MOUNT=aws" \
		--env="VAULT_ENVIRONMENT=local" \
		--env="VAULT_TOKEN=root" \
		-- /bin/bash

.PHONY: lab/status
lab/status: ## Show some lab info
	@echo "CSI Version:	$(shell $(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) \
		get daemonset \
		-l app=secrets-store-csi-driver \
		-o jsonpath="{.items[0].spec.template.spec.containers[1].image}" \
		--all-namespaces)"
	@echo ""
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) get pods \
		-l app=secrets-store-csi-driver \
		--all-namespaces
	@echo ""
	@echo "CSI Vault Provider Deployment Info"
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) get pods -l app=secrets-store-csi-driver --all-namespaces
	@echo ""
	@echo "CSI Helm Chart Info"
	@$(helm) --kubeconfig $(KIND_KUBE_CONFIG) list --all-namespaces

.PHONY: lab/kube/token
lab/kube/token: ## Seed kube jwt reviewer token
	@echo "Seeding jwt_token to kv"
	@$(SCRIPT_PATH)/kv-seed.sh

.PHONY: lab/kube/token/test
lab/kube/token/test: ## Test seeded jwt secrets
	@$(SCRIPT_PATH)/kv-to-env.sh

.PHONY: lab/app1/approle/export/wrapped
lab/app1/approle/export/wrapped: ## Create config/app1_secret_id.txt
	@$(vault) write -wrap-ttl=360s -f auth/approle/role/app1_issuer/secret-id -format=json | jq -r '.data.wrapping_token'

.PHONY: lab/app1/approle/secret/export
lab/app1/approle/secret/export: ## Create config/app1_secret_id.txt
	@$(vault) write -f auth/approle/role/app1_issuer/secret-id -format=json | jq -r '.data.secret_id'

.PHONY: lab/app1/approle/role/export
lab/app1/approle/role/export: ## Create config/app1_secret_id.txt
	@$(vault) read auth/approle/role/app1_issuer/role-id -format=json | jq -r '.data.role_id'

.PHONY: lab/certmanager/sa/export
lab/certmanager/sa/export: ## Export the cert-manager service account token
	@$(kubectl) -n $(VAULT_CERTMANAGER_NS) --kubeconfig $(KIND_KUBE_CONFIG) \
		get serviceaccount cert-manager -o json | jq -r ".secrets[].name"

.PHONY: lab/app1/secrets
lab/app1/secrets: ## Seed app1 secrets
	@echo "Seeding app1 secret"
	@$(vault) kv put $(SECRET_MOUNT)/$(SECRET_NAME) $(SECRET_DATA)
	@$(vault) kv get $(SECRET_MOUNT)/$(SECRET_NAME)

.PHONY: lab/app1/certificate
lab/app1/certificate: ## Request a cert from certmanager declaratively
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(SECRET_NS) || true
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) -n $(SECRET_NS) apply -f $(CONFIG_PATH)/app1-certificate.yml

.PHONY: .lab/app1/testuser
.lab/app1/testuser: ## Create testuser local account with rights to app1 kv as consumer
	@$(vault) write auth/userpass/users/testuser1 password=password1 policies=kv_controller_internal,default
	@echo "To login as 'testuser1' use the following (and enter 'password1' when prompted)"
	@echo "export VAULT_TOKEN=$(vault) login -token-only -method=userpass username=testuser"

.PHONY: lab/app1/inject/deploy
lab/app1/inject/deploy: lab/inject/deploy lab/app1/secrets ## Deploy app1 to local kube cluster via helm chart
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(SECRET_NS) || true
	@$(helm) -n $(SECRET_NS) --kubeconfig $(KIND_KUBE_CONFIG) \
		upgrade -i app1 $(ROOT_PATH)/charts/app1 \
		--set "vault.name=app1" \
		--set "serviceAccount.name=$(SECRET_SA)" \
		--set "vault.address=http://$(VAULT_ADDRESS):8200" \
		--set "vault.inject=true" \
		--set "vault.csi=false" \
		--set "vault.secret=$(SECRET_NAME)" \
		--set "vault.kvPath=$(SECRET_MOUNT)" \
		--set "vault.role=$(VAULT_ROLE)"

.PHONY: lab/app1/inject/template
lab/app1/inject/template: ## Create deployment template for app1
	@$(helm) -n $(SECRET_NS) template --kubeconfig $(KIND_KUBE_CONFIG) \
		app1 $(ROOT_PATH)/charts/app1 \
		--set "vault.name=app1" \
		--set "serviceAccount.name=$(SECRET_SA)" \
		--set "vault.address=http://$(VAULT_ADDRESS):8200" \
		--set "vault.inject=true" \
		--set "vault.csi=false" \
		--set "vault.secret=$(SECRET_NAME)" \
		--set "vault.kvPath=$(SECRET_MOUNT)" \
		--set "vault.role=$(VAULT_ROLE)"

.PHONY: lab/app1/destroy
lab/app1/destroy: ## Deploy app1 to local kube cluster
	@$(helm) -n app1 uninstall app1 || true
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) delete ns app1 || true

.PHONY: lab/app1/inject/redeploy
lab/app1/inject/redeploy: lab/app1/destroy lab/app1/inject/deploy ## Redeploy app1 to local kube cluster via helm chart

.PHONY: lab/inject/deploy
lab/inject/deploy: ## Configure vault injection method on server
	@docker pull hashicorp/vault-k8s:0.10.0
	@$(kind) load docker-image hashicorp/vault-k8s:0.10.0 || true
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(VAULT_NS) || true
	@$(helm) repo add hashicorp \
		https://helm.releases.hashicorp.com || true
	@$(helm) repo update
	@$(helm) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) \
		upgrade -i vault hashicorp/vault \
		--set "server.enabled=false" \
		--set "injector.enabled=true" \
		--set="injector.authPath=auth/kubernetes/kind" \
		--set="injector.externalVaultAddr=http://$$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(VAULT_IMAGE) || true):8200" \
		--set "csi.enabled=false"

## CSI Tasks
.PHONY: lab/csi/driver/deploy
lab/csi/driver/deploy: ## Deploy csi driver on local cluster
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(VAULT_CSI_NS) || true
	@$(helm) repo add secrets-store-csi-driver \
		https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts || true
	@$(helm) repo add hashicorp \
		https://helm.releases.hashicorp.com || true
	@$(helm) repo update
	@$(helm) upgrade -i -n $(VAULT_CSI_NS) --kubeconfig $(KIND_KUBE_CONFIG) \
		vault-csi-driver secrets-store-csi-driver/secrets-store-csi-driver || true

.PHONY: lab/csi/driver/template
lab/csi/driver/template: ## Template of csi driver deployment
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(VAULT_CSI_NS) || true
	@$(helm) repo add secrets-store-csi-driver \
		https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts || true
	@$(helm) repo add hashicorp https://helm.releases.hashicorp.com || true
	@$(helm) repo update
	@$(helm) -n $(VAULT_CSI_NS) --kubeconfig $(KIND_KUBE_CONFIG) template \
		vault-csi-driver secrets-store-csi-driver/secrets-store-csi-driver

.PHONY: lab/csi/provider/deploy
lab/csi/provider/deploy: ## Deploy vault csi provider
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(VAULT_CSI_NS) || true
	@$(helm) repo add hashicorp https://helm.releases.hashicorp.com || true
	@$(helm) repo update
	@$(helm) upgrade -i -n $(VAULT_CSI_NS) --kubeconfig $(KIND_KUBE_CONFIG) vault hashicorp/vault \
		--set "server.enabled=false" \
		--set "server.readinessProbe.enabled=false" \
		--set "server.service.enabled=false" \
		--set "injector.enabled=false" \
		--set "csi.enabled=true" || true

.PHONY: lab/csi/provider/template
lab/csi/provider/template: ## Template deploy vault csi provider
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(VAULT_CSI_NS) || true
	@$(helm) repo add hashicorp https://helm.releases.hashicorp.com || true
	@$(helm) repo update
	@$(helm) -n $(VAULT_CSI_NS) --kubeconfig $(KIND_KUBE_CONFIG) template vault hashicorp/vault \
		--set "server.enabled=false" \
		--set "server.readinessProbe.enabled=false" \
		--set "server.service.enabled=false" \
		--set "injector.enabled=false" \
		--set "csi.enabled=true"

.PHONY: lab/csi/deploy
lab/csi/deploy: lab/csi/driver/deploy lab/csi/provider/deploy ## Configure csi driver on local cluster

.PHONY: lab/app1/csi/deploy
lab/app1/csi/deploy: lab/csi/deploy lab/app1/secrets ## Configure app1 csi configuration on local cluster
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(SECRET_NS) || true
	$(helm) -n $(SECRET_NS) \
		upgrade -i app1 $(ROOT_PATH)/charts/app1 \
		--set "vault.name=app1" \
		--set "serviceAccount.name=$(SECRET_SA)" \
		--set "vault.address=http://$(VAULT_ADDRESS):8200" \
		--set "vault.inject=false" \
		--set "vault.csi=true" \
		--set "vault.secret=$(SECRET_NAME)" \
		--set "vault.kvPath=$(SECRET_MOUNT)" \
		--set "vault.role=$(VAULT_ROLE)" || true

.PHONY: lab/app1/csi/template
lab/app1/csi/template: ## Helm template app1 csi configuration on local cluster
	@$(helm) -n $(SECRET_NS) --kubeconfig $(KIND_KUBE_CONFIG) template \
		app1 $(ROOT_PATH)/charts/app1 \
			-f $(CONFIG_PATH)/app1.csi.yml

.PHONY: lab/app1/csi
lab/app1/csi: lab/app1/destroy lab/app1/csi/deploy ## Deploy app1 csi full lab

.PHONY: lab/app1/csi/redeploy
lab/app1/csi/redeploy: lab/app1/destroy lab/csi/deploy lab/app1/csi/deploy ## Redeploy app1 to local kube cluster via helm chart

.PHONY: lab/app1/validate
lab/app1/validate: ## Validate injected secrets
	@echo "Contents of app1 container file path - $(SECRET_INJECTION_PATH)"
	@$(kubectl) -n $(SECRET_NS) exec \
		`$(kubectl) -n app1 get pod -l app.kubernetes.io/name=app1 -o jsonpath="{.items[0].metadata.name}"` \
		--container app1 -- cat $(SECRET_INJECTION_PATH)

.PHONY: lab/awx/deploy
lab/awx/deploy: ## Deploy awx-operator to the lab kind cluster
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) \
		apply -f https://raw.githubusercontent.com/ansible/awx-operator/$(AWX_VERSION)/deploy/awx-operator.yaml
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) \
		apply -f $(CONFIG_PATH)/awx.yml

.PHONY: lab/certmanager/deploy
lab/certmanager/deploy: ## Deploy cert-manager via helm
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) apply \
		--validate=false -f https://github.com/jetstack/cert-manager/releases/latest/download/cert-manager.crds.yaml
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(VAULT_CERTMANAGER_NS) || true
	@$(helm) repo add jetstack https://charts.jetstack.io || true
	@$(helm) repo update
	@$(helm) -n $(VAULT_CERTMANAGER_NS) --kubeconfig $(KIND_KUBE_CONFIG) \
		upgrade -i cert-manager jetstack/cert-manager \
		--set "serviceAccount.name=cert-manager" || true

.PHONY: lab/certmanager
lab/certmanager: lab/certmanager/deploy ## Deploy cert-manager crds, chart, and integration
	@echo "Waiting a few seconds to ensure certmanager CRDs are ready to rock..."
	@sleep 8
	@$(MAKE) kube/vault/certmanager lab/app1/certificate