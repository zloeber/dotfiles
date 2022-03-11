ROOT_PATH ?= $(abspath $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
LOCAL_PATH ?= $(ROOT_PATH)/.local
PROJECT_BIN_PATH ?= $(LOCAL_PATH)/bin

### Kind (kubernetes in docker) Tasks
kind := $(PROJECT_BIN_PATH)/kind
kubectl := $(PROJECT_BIN_PATH)/kubectl
helm := $(PROJECT_BIN_PATH)/helm
jq := $(PROJECT_BIN_PATH)/jq
k9s := $(PROJECT_BIN_PATH)/k9s

KIND_VERSION ?= 0.10.0
KUBECTL_VERSION ?= 1.20.1
HELM_VERSION ?= 3.4.2
JQ_VERSION ?= 1.6
K9S_VERSION ?= 0.24.2
# KUBE_BUILD_IMAGE ?= registry.nmlv.nml.com/idam-pxm/tools/hvault-cicd
# KUBE_BUILD_IMAGE_TAG ?= alpine-tf14
KIND_KUBE_CONFIG ?= $(LOCAL_PATH)/kubeconfig
VAULT_NS ?= vault
VAULT_CSI_NS ?= csi
export HELM_CACHE_HOME=$(ROOT_PATH)/.local/helm
export HELM_CONFIG_HOME=$(ROOT_PATH)/.local/helm
export HELM_DATA_HOME=$(ROOT_PATH)/.local/helm
export KUBECONFIG=$(KIND_KUBE_CONFIG)

.PHONY: .dep/kind
.dep/kind: ## Install local kind binary
ifeq (,$(wildcard $(kind)))
	@echo "Attempting to install kind - $(KIND_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	curl --retry 3 --retry-delay 5 --fail -sSL -o $(kind) https://github.com/kubernetes-sigs/kind/releases/download/v$(KIND_VERSION)/kind-$(OS)-$(ARCH)
	@chmod +x $(kind)
endif
	@echo "kind binary: $(kind)"


.PHONY: .dep/kind/node
.dep/kind/node: ## Create the kind node image locally
	@echo "Attempting to clone and build from kubernetes source repo."
	@mkdir -p $$GOPATH/src/k8s.io
	cd $$GOPATH/src/k8s.io && git clone https://github.com/kubernetes/kubernetes || echo "clone exists, skipping!"
	@$(kind) build node-image --image kindest/node:main --kube-root $$GOPATH/src/k8s.io/kubernetes

.PHONY: .dep/kubectl
.dep/kubectl: ## Install local kubectl binary
ifeq (,$(wildcard $(kubectl)))
	@echo "Attempting to install kubectl - $(KUBECTL_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL -o $(kubectl) https://storage.googleapis.com/kubernetes-release/release/v$(KUBECTL_VERSION)/bin/$(OS)/$(ARCH)/kubectl
	@chmod +x $(kubectl)
endif
	@echo "kubectl binary: $(kubectl)"

.PHONY: .dep/helm
.dep/helm: ## Install local helm binary
ifeq (,$(wildcard $(helm)))
	@echo "Attempting to install helm - $(HELM_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@mkdir -p /tmp/helm
	@curl --retry 3 --retry-delay 5 --fail -sSL -o - https://get.helm.sh/helm-v$(HELM_VERSION)-$(OS)-$(ARCH).tar.gz | tar -C /tmp/helm -zx $(OS)-$(ARCH)/helm
	@mv /tmp/helm/$(OS)-$(ARCH)/helm $(helm)
	@chmod +x $(helm)
endif
	@echo "helm binary: $(helm)"

.PHONY: .dep/jq
.dep/jq: ## Install jq
ifndef IS_CI
ifeq (,$(wildcard $(jq)))
	@echo "Attempting to install jq - $(JQ_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
ifeq ($(OS),darwin)
	@curl --retry 3 --retry-delay 5 --fail -sSL \
		-o $(jq) https://github.com/stedolan/jq/releases/download/jq-$(JQ_VERSION)/jq-osx-$(ARCH)
else
	@curl --retry 3 --retry-delay 5 --fail -sSL \
		-o $(jq) https://github.com/stedolan/jq/releases/download/jq-$(JQ_VERSION)/jq-$(OS)-$(ARCH)
endif
	@chmod +x $(jq)
endif
endif
	@echo "jq binary: $(jq)"

.PHONY: kube/start
kube/start: ## Start a local kind cluster
	@$(kind) create cluster --kubeconfig $(KIND_KUBE_CONFIG) --wait 60s
	@$(kind) load docker-image $(DOCKER_IMAGE):local || true
	@docker pull vault:$(VAULT_VERSION) 2>/dev/null || true
	@$(kind) load docker-image vault:$(VAULT_VERSION) || true

.PHONY: kube/stop
kube/stop: .kube/helm/clean ## Stop a local kind cluster
	@$(kind) delete cluster

.PHONY: kube/build/kind
kube/build/kind: ## Creates local kind images
ifndef IS_CI
	@$(MAKE) --no-print-directory -C $(ROOT_PATH)/images/kind build VAULT_VERSION=$(VAULT_VERSION)
endif

.PHONY: kube/export
kube/export: ## Extract a CA cert from kubeconfig
	@echo "https://$$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kind-control-plane):6443" > $(LOCAL_PATH)/kube_server.txt
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) \
		config view --raw -o=jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 --decode > $(LOCAL_PATH)/kube_ca.pem
	@$(MAKE) kube/vault/token > $(LOCAL_PATH)/token_reviewer_jwt.txt

KUBE_KV_NAME?=controller/kind/vault_auth
KUBE_KV_MOUNT?=controller/kv
KUBE_TOKEN:=$(shell cat $(LOCAL_PATH)/token_reviewer_jwt.txt 2> /dev/null || echo "" )
KUBE_CA:=$(shell cat $(LOCAL_PATH)/kube_ca.pem 2> /dev/null || echo "" )
KUBE_URL:=$(shell cat $(LOCAL_PATH)/kube_server.txt 2> /dev/null || echo "" )
KUBE_SERVICE_ACCOUNT=$(shell $(kubectl) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) get secrets --output=json | $(jq) -r '.items[].metadata | select(.name|startswith("vault-token-jwt-reviewer")).name' 2> /dev/null || echo "NA" )
KUBE_KV_DATA?=name='$(KUBE_URL)' token='$(KUBE_TOKEN)' certificate='$(KUBE_CA)'

.PHONY: kube/vault/auth/seed
kube/vault/auth/seed: ## Seed initial vault secrets for kube mount integration
	@echo "Seeding kube secrets..."
	@echo "KUBE_KV_NAME: $(KUBE_KV_NAME)"
	@echo "KUBE_KV_MOUNT: $(KUBE_KV_MOUNT)"
	@echo "KUBE_URL: $(KUBE_URL)"
	@$(vault) kv put $(KUBE_KV_MOUNT)/$(KUBE_KV_NAME) $(KUBE_KV_DATA) || true

.PHONY: kube/vault/cronjob
kube/vault/cronjob: ## Helm deploy the vault cronjob deployment
	@mkdir -p $(HELM_CACHE_HOME)
	@echo "VAULT_ADDRESS: ${VAULT_ADDRESS}"
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) create ns $(VAULT_NS) || true
	@$(helm) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) upgrade -i \
		vault-integration $(ROOT_PATH)/charts/vault-integration \
		--set "default.kubeClusterId=kind" \
		--set "vault.owner=controller" \
		--set "vault.initEnabled=false" \
		--set "vault.namespace=$(VAULT_NS)" \
		--set "vault.image.repository=$(DOCKER_IMAGE)" \
		--set "vault.image.tag=local" \
		--set "vault.imagePullPolicy=Never" \
		--set "vault.address=http://$(VAULT_ADDRESS):8200" \
		--set "vault.kubeURL=$(KUBE_URL)" \
		--set "vault.kv.path=controller/kv" \
		--set "vault.kv.secret=controller/kind/vault_auth" \
		--set "vault.authMethod=token" \
		--set "vault.token=root"
	@$(MAKE) kube/vault/token > $(LOCAL_PATH)/token_reviewer_jwt.txt

.PHONY: kube/vault/cronjob/run
kube/vault/cronjob/run: ## Create a new job from the cronjob and run it
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) -n $(VAULT_NS) \
		create job --from=cronjob/vault-integration-update vault-integration-manual-run || true

.PHONY: kube/vault/cronjob/template
kube/vault/cronjob/template: ## Helm template the vault cronjob deployment
	@$(helm) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) template \
		vault-integration $(ROOT_PATH)/charts/vault-integration \
		--set "default.kubeClusterId=kind" \
		--set "vault.owner=controller" \
		--set "vault.initialize=false" \
		--set "vault.namespace=$(VAULT_NS)" \
		--set "vault.image.repository=$(DOCKER_IMAGE)" \
		--set "vault.image.tag=local" \
		--set "vault.imagePullPolicy=Never" \
		--set "vault.address=http://$(VAULT_ADDRESS):8200" \
		--set "vault.kubeURL=$(KUBE_URL)" \
		--set "vault.kv.path=controller/kv" \
		--set "vault.kv.secret=controller/kind/vault_auth" \
		--set "vault.authMethod=token" \
		--set "vault.token=root"

.PHONY: kube/vault/certmanager
kube/vault/certmanager: ## Helm deploy the vault certmanager integration
	@mkdir -p $(HELM_CACHE_HOME)
	@echo "VAULT_ADDRESS: ${VAULT_ADDRESS}"
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) \
		create ns $(VAULT_CERTMANAGER_NS) 2> /dev/null || true
	@$(helm) -n $(VAULT_CERTMANAGER_NS) --kubeconfig $(KIND_KUBE_CONFIG) upgrade -i \
		vault-certmanager-integration $(ROOT_PATH)/charts/vault-integration \
		--set "default.kubeClusterId=kind" \
		--set "vault.environment=local" \
		--set "vault.address=http://$(VAULT_ADDRESS):8200" \
		--set "vault.isEnabled=false" \
		--set "vault.initialize=false" \
		--set "certmanager.enabled=true" \
		--set "certmanager.auth=$(VAULT_CERTMANAGER_AUTH)" \
		--set "certmanager.kubernetes.role=kubernetes_kind_cert-manager_cert-manager" \
		--set "certmanager.kubernetes.secret=$(shell $(MAKE) lab/certmanager/sa/export)" \
		--set "certmanager.pki.role=app1_issuer" \
		--set "certmanager.pki.mount=pki/caint" \
		--set 'certmanager.pki.caBundle=$(shell curl -s \
			-X GET http://127.0.0.1:8200/v1/pki/caint/ca_chain \
			-H "accept: */*" \
			-H  "X-Vault-Token: ${VAULT_TOKEN}" | base64)' \
		--set "certmanager.approle.role_id=$(shell $(MAKE) lab/app1/approle/role/export)" \
		--set "certmanager.approle.role=app1_issuer" \
		--set "certmanager.approle.secret=$(shell $(MAKE) lab/app1/approle/secret/export)"
#--set "certmanager.pki.caBundle=$(shell cat ./.local/kube_ca.pem | base64)" \

.PHONY: kube/vault/certmanager/template
kube/vault/certmanager/template: ## Helm template the vault certmanager integration
	$(helm) -n $(VAULT_CERTMANAGER_NS) template \
		vault-certmanager-integration $(ROOT_PATH)/charts/vault-integration \
		--set "default.kubeClusterId=kind" \
		--set "vault.environment=local" \
		--set "vault.address=http://$(VAULT_ADDRESS):8200" \
		--set "vault.isEnabled=false" \
		--set "vault.initialize=false" \
		--set "certmanager.enabled=true" \
		--set "certmanager.auth=$(VAULT_CERTMANAGER_AUTH)" \
		--set "certmanager.kubernetes.role=kubernetes_kind_cert-manager_cert-manager" \
		--set "certmanager.kubernetes.secret=$(shell $(MAKE) lab/certmanager/sa/export)" \
		--set "certmanager.pki.role=app1_issuer" \
		--set "certmanager.pki.mount=pki/caint" \
		--set "certmanager.pki.caBundle=$(shell curl -s -X GET "http://127.0.0.1:8200/v1/pki/caint/ca_chain" -H  "accept: */*" -H  "X-Vault-Token: ${VAULT_TOKEN}" | base64)" \
		--set "certmanager.approle.role_id=$(shell $(MAKE) lab/app1/approle/role/export)" \
		--set "certmanager.approle.role=app1_issuer" \
		--set "certmanager.approle.secret=$(shell $(MAKE) lab/app1/approle/secret/export)"

.PHONY: kube/vault/certmanager/status
kube/vault/certmanager/status: ## Validate cert-manager issuers
	@$(kubectl) -n $(VAULT_CERTMANAGER_NS) --kubeconfig $(KIND_KUBE_CONFIG)	get clusterissuers.cert-manager.io -o wide

.PHONY: kube/vault/rbac
kube/vault/rbac: ## Configure kube with vault required rbac rules
	@$(kubectl) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) apply --filename $(ROOT_PATH)/config/token-reviewer.yml

.PHONY: kube/vault/token/test
kube/vault/token/test: ## Retrieves a reviewer token
	@$(kubectl) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) get secret \
	$$($(kubectl) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) get secrets --output=json | $(jq) -r '.items[].metadata | select(.name|startswith("vault-token-jwt-reviewer")).name')

.PHONY: kube/vault/token
kube/vault/token: ## Retrieves a reviewer token
	@$(kubectl) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) \
		get secret $(KUBE_SERVICE_ACCOUNT) \
		--output='go-template={{ .data.token }}' | base64 --decode

.PHONY: .kube/vault/external
.kube/vault/external: ## Configure kube to point to an external endpoint for vault
	@$(kubectl) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) \
	apply --filename $(ROOT_PATH)/config/external-vault.yml

.PHONY: .kube/helm/clean
.kube/helm/clean: ## Clean up helm deployment cache
	@rm -rf $(ROOT_PATH)/.local/helm

.PHONY: kube/helm/config
kube/helm/config: ## Configure helm to access remote vault instance
	@mkdir -p $(HELM_CACHE_HOME)
	@$(helm) repo add hashicorp https://helm.releases.hashicorp.com || true
	@$(helm) repo update || true
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) \
		create ns $(VAULT_NS) || true
	@$(helm) -n $(VAULT_NS) --kubeconfig $(KIND_KUBE_CONFIG) \
		upgrade -i vault hashicorp/vault \
		--set "server.enabled=false" \
		--set "server.readinessProbe.enabled=false" \
		--set "server.service.enabled=false" \
		--set "csi.enabled=false"
	@$(MAKE) kube/vault/token > $(LOCAL_PATH)/token_reviewer_jwt.txt

.PHONY: kube/show
kube/show: helm/export ## Export current kube/helm vars to source in shell

.PHONY: kube/status
kube/status: ## Show kubernetes status
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) cluster-info

.PHONY: kube/info
kube/info: ## Some extra kube info
	@echo "VAULT_ADDRESS: ${VAULT_ADDRESS}"
	@echo "KUBE_TOKEN: ${KUBE_TOKEN}"
	@echo "KUBE_CA: ${KUBE_CA}"
	@echo "KUBE_URL: ${KUBE_URL}"
	@echo "KUBE_SERVICE_ACCOUNT: ${KUBE_SERVICE_ACCOUNT}"

.PHONY: helm/export
helm/export: ## Export current kube/helm vars to source in shell
	@echo "export HELM_CACHE_HOME=$(HELM_CACHE_HOME)"
	@echo "export HELM_CONFIG_HOME=$(HELM_CONFIG_HOME)"
	@echo "export HELM_DATA_HOME=$(HELM_DATA_HOME)"
	@echo "export KUBECONFIG=$(KIND_KUBE_CONFIG)"

