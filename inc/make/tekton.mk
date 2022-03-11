TEKTON_VERSION ?= 0.20.0
TEKTON_NS ?= tekton

tkn := $(PROJECT_BIN_PATH)/tkn

.PHONY: tekton
tekton: .dep/tkn ## Bootstrap tekton on kube

.PHONY: .dep/tkn
.dep/tkn: ## Install local tekton binary
ifeq (,$(wildcard $(tkn)))
	@echo "Attempting to install tkn - $(TEKTON_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@mkdir -p /tmp/tekton
	@curl --retry 3 --retry-delay 5 --fail -sSL -o - \
		https://github.com/tektoncd/cli/releases/download/v${TEKTON_VERSION}/tkn_${TEKTON_VERSION}_${OS}_${ARCH}.tar.gz | tar -zx -C '/tmp/tekton'
	@find /tmp/tekton -type f -name 'tkn*' | xargs -I {} cp -f {} $(tkn)
	@chmod +x $(tkn)
endif
	@echo "tkn binary: $(tkn)"
