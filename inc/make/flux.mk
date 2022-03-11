FLUX2_VERSION ?= 0.12.3
FLUX_NS ?= fluxcd

flux2 := $(PROJECT_BIN_PATH)/flux

OS ?= darwin
ARCH ?= amd64
FLUX_SSH_KEY ?= $(ROOT_PATH)/.local/flux_lab_identity

.PHONY: flux
flux: .dep/fluxctl .dep/flux/sshkey flux/deploy flux/key ## Bootstrap flux on kube

.PHONY: .dep/flux2
.dep/flux2: ## Install local flux binary
ifeq (,$(wildcard $(flux2)))
	@echo "Attempting to install flux2 - $(FLUX2_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@mkdir -p /tmp/flux
	@curl --retry 3 --retry-delay 5 --fail -sSL -o - \
		https://github.com/fluxcd/flux2/releases/download/v${FLUX2_VERSION}/flux_${FLUX2_VERSION}_${OS}_${ARCH}.tar.gz \
		| tar -C /tmp/flux -zx flux
	@mv /tmp/flux/flux $(flux2)
	@chmod +x $(flux2)
endif
	@echo "flux2 binary: $(flux2)"

# .PHONY: .dep/flux/sshkey
# .dep/flux/sshkey: ## Create ssh key if one does not already exist
# ifeq (,$(wildcard $(FLUX_SSH_KEY)))
# 	@echo "Attempting to create SSH key - $(FLUX_SSH_KEY)"
# 	@ssh-keygen -q -N "" -f $(FLUX_SSH_KEY)
# endif
# 	@echo "FLUX_SSH_KEY: $(FLUX_SSH_KEY)"

.PHONY: flux/deploy/gitlab
flux/deploy/gitlab: .dep/flux2 ## Deploy flux2 to local cluster for gitlab repo
ifndef GITLAB_TOKEN
	@echo "GITLAB_TOKEN is not defined!" && exit 1
endif
	@echo "GITLAB_HOST: $(GITLAB_HOST)"
	$(flux2) --kubeconfig $(KUBECONFIG) check --pre
	docker pull ghcr.io/fluxcd/helm-controller:v0.9.0
	$(kind) load docker-image ghcr.io/fluxcd/helm-controller:v0.9.0
	docker pull ghcr.io/fluxcd/kustomize-controller:v0.11.0
	$(kind) load docker-image ghcr.io/fluxcd/kustomize-controller:v0.11.0
	docker pull ghcr.io/fluxcd/notification-controller:v0.12.0
	$(kind) load docker-image ghcr.io/fluxcd/notification-controller:v0.12.0
	docker pull ghcr.io/fluxcd/source-controller:v0.11.0
	$(kind) load docker-image ghcr.io/fluxcd/source-controller:v0.11.0
	docker pull ghcr.io/stefanprodan/podinfo:5.2.0
	$(kind) load docker-image ghcr.io/stefanprodan/podinfo:5.2.0
	$(kubectl) create ns podinfo 
	$(flux2) --kubeconfig $(KUBECONFIG) bootstrap gitlab \
		--hostname=$(GITLAB_HOST) \
		--owner=idam-pxm/vault-ops \
		--repository=provision-local \
		--branch=master \
		--path=clusters/kind \
		--branch=master \
		--token-auth
# @$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) \
# 	create ns $(FLUX_NS) || true
# @$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) \
# 	create secret generic flux-ssh --from-file=$(FLUX_SSH_KEY) || true
# @$(helm) repo add fluxcd https://charts.fluxcd.io || true
# @$(helm) -n $(FLUX_NS) \
# 	upgrade -i flux fluxcd/flux \
# 	--set git.url=$(GIT_URL) || true
# @$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) \
# 	apply -f https://raw.githubusercontent.com/fluxcd/helm-operator/master/deploy/crds.yaml
# @$(helm) -n $(FLUX_NS) \
# 	upgrade -i helm-operator fluxcd/helm-operator \
# 	--set git.ssh.secretName=flux-ssh \
# 	--set helm.versions=v3 || true
# @echo ""
# @echo "Copy This and use for gitlab auth:"
# @$(fluxctl) identity --k8s-fwd-ns $(FLUX_NS)

.PHONY: flux/key
flux/key: ## Show flux deploy key
	@$(fluxctl) identity --k8s-fwd-ns $(FLUX_NS)

.PHONY: flux/reset
flux/reset: flux/delete flux ## Reset the flux configuration on kube

.PHONY: flux/delete
flux/delete: ## Delete the flux configuration on kube
	@$(kubectl) --kubeconfig $(KIND_KUBE_CONFIG) delete ns $(FLUX_NS) || true

.PHONY: flux/gitlab
flux/gitlab: ## Attempt to use GITLAB_TOKEN to upload the current fluxcd deploy ssh key
	@GITLAB_URL=$(GITLAB_URL) \
		GITLAB_TOKEN=${GITLAB_TOKEN} \
		SSH_PUB_KEY="$(shell $(MAKE) flux/key)" \
		$(SCRIPT_PATH)/gitlab-add-ssh-key.sh