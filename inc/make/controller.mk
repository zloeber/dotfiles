### Code bundle tasks for local vault deployment

CONTROLLER_DEPLOY_FOLDERS:=baseconfig resources triggered other manual auth seed secret apps manual

.PHONY: clean/state
clean/state: ## Clean out any terraform state files and modules
	@$(foreach deploypath, $(CONTROLLER_DEPLOY_FOLDERS), $(shell $(MAKE) TF_PATH=$(DEPLOY_PATH)/$(deploypath) tf/clean))

.PHONY: clean/bundle
clean/bundle: ## Remove generated manifests entirely
	@rm -rf $(DEPLOY_PATH)
	@mkdir -p $(DEPLOY_PATH)
	@$(foreach deploypath,$(CONTROLLER_DEPLOY_FOLDERS), mkdir -p $(DEPLOY_PATH)/$(deploypath);)
	@$(foreach deploypath, $(CONTROLLER_DEPLOY_FOLDERS), cp $(CONFIG_PATH)/providers.tf $(DEPLOY_PATH)/$(deploypath);)
	@$(foreach deploypath, $(CONTROLLER_DEPLOY_FOLDERS), cp $(CONFIG_PATH)/versions.tf $(DEPLOY_PATH)/$(deploypath);)
	@echo "Recreated Deployment Path: $(DEPLOY_PATH)"

.PHONY: codebundle/pull
codebundle/pull: ## download code generated from controller
	@VAULT_ENVIRONMENT=$(VAULT_ENVIRONMENT) \
		TARGET_PATH=$(TEMP_STATE_PATH) \
		BRANCH=$(CONTROLLER_BRANCH) \
		DEPLOY_PATH=$(DEPLOY_PATH) \
		$(SCRIPT_PATH)/get-controller-state.sh

.PHONY: codebundle
codebundle: clean/bundle codebundle/pull ## Setup deployment folders from codebundle state
	@mv $(DEPLOY_PATH)/*.resource.namespace.tf $(DEPLOY_PATH)/baseconfig || true
	@mv $(DEPLOY_PATH)/*.mount.kubernetes.tf $(DEPLOY_PATH)/triggered || true
	@mv $(DEPLOY_PATH)/*.seed.*.tf $(DEPLOY_PATH)/seed || true
	@rm -rf $(DEPLOY_PATH)/seed/*.init.tf
	@rm -rf $(DEPLOY_PATH)/resources/*.resource.provider.kube.tf
	@rm -rf $(DEPLOY_PATH)/resources/*.ad.tf
	@mv $(DEPLOY_PATH)/*.mount.*.tf $(DEPLOY_PATH)/baseconfig || true
	@mv $(DEPLOY_PATH)/appconfig.policy.*.tf $(DEPLOY_PATH)/auth 2>/dev/null || true
	@mv $(DEPLOY_PATH)/*.resource.pki.tf $(DEPLOY_PATH)/other || true
	@mv $(DEPLOY_PATH)/*.resource.provider.*.tf $(DEPLOY_PATH)/other || true
	@mv $(DEPLOY_PATH)/*.resource.*.tf $(DEPLOY_PATH)/resources || true
	@mv $(DEPLOY_PATH)/*.role.*.tf $(DEPLOY_PATH)/auth 2>/dev/null || true
#mv $(DEPLOY_PATH)/*.binding.*.tf $(DEPLOY_PATH)/auth 2>/dev/null || true
	@mv $(DEPLOY_PATH)/*.secret.*.tf $(DEPLOY_PATH)/secret 2>/dev/null || true
	@mv $(DEPLOY_PATH)/*.trigger.pki.role.*.tf $(DEPLOY_PATH)/auth 2>/dev/null || true

### Local code generation tasks
.PHONY: bundle
bundle: clean/bundle .dep/hvault-helper ## create local code bundle from .vaultrc.yml
	@$(hvault-helper-cmd) generate \
		--save --savepath=$(DEPLOY_PATH)/baseconfig \
		appconfig --template=policy
	@$(hvault-helper-cmd) generate resource --template=namespace > $(DEPLOY_PATH)/baseconfig/namespaces.tf
	@$(hvault-helper-cmd) generate resource --template=provider > $(DEPLOY_PATH)/baseconfig/provider_aliases.tf
#@cp $(DEPLOY_PATH)/baseconfig/provider_aliases.tf $(DEPLOY_PATH)/other/provider_aliases.tf
#@cp $(DEPLOY_PATH)/baseconfig/provider_aliases.tf $(DEPLOY_PATH)/resources/provider_aliases.tf
	@$(hvault-helper-cmd) generate mount --template=approle > $(DEPLOY_PATH)/baseconfig/mounts.tf
	@$(hvault-helper-cmd) generate mount --template=cert >> $(DEPLOY_PATH)/baseconfig/mounts.tf
	@$(hvault-helper-cmd) generate mount --template=userpass >> $(DEPLOY_PATH)/baseconfig/mounts.tf
	@$(hvault-helper-cmd) generate mount --template=jwt >> $(DEPLOY_PATH)/baseconfig/mounts.tf
	@$(hvault-helper-cmd) generate mount --template=gitlab >> $(DEPLOY_PATH)/baseconfig/mounts.tf
	@$(hvault-helper-cmd) generate mount --template=transit >> $(DEPLOY_PATH)/baseconfig/mounts.tf
	@$(hvault-helper-cmd) generate mount --template=openldap >> $(DEPLOY_PATH)/baseconfig/mounts.tf
	@$(hvault-helper-cmd) generate mount --template=kubernetes > $(DEPLOY_PATH)/triggered/kube.mounts.tf
	@$(hvault-helper-cmd) generate seed --template=kube_auth_mount > $(DEPLOY_PATH)/seed/kube_auth_mount.tf
	@$(hvault-helper-cmd) generate seed --template=kube_provider > $(DEPLOY_PATH)/seed/kube_provider.tf
	@$(hvault-helper-cmd) generate seed --template=kube_config > $(DEPLOY_PATH)/seed/kube_config.tf
	@$(hvault-helper-cmd) generate resource --template=transit > $(DEPLOY_PATH)/resources/transit.tf
	@$(hvault-helper-cmd) generate resource --template=kv > $(DEPLOY_PATH)/resources/kv.tf
	@$(hvault-helper-cmd) generate resource --template=kube > $(DEPLOY_PATH)/auth/kube.tf
	@$(hvault-helper-cmd) generate resource --template=pki > $(DEPLOY_PATH)/other/pki.tf
	@$(hvault-helper-cmd) generate role --template=approle > $(DEPLOY_PATH)/auth/approle.tf
	@$(hvault-helper-cmd) generate trigger --template=pki.role > $(DEPLOY_PATH)/auth/pki_role.tf
	@$(hvault-helper-cmd) generate secret > $(DEPLOY_PATH)/secret/secrets.tf
	@$(hvault-helper-cmd) generate --save --savepath $(DEPLOY_PATH)/apps app

## Catch all tasks
.PHONY: controller/start
controller/start: codebundle ## Start a local vault instance and deploy things to it
	@$(MAKE) lab/start/network vault/start vault/deploy ENT=true

.PHONY: bundle/start
bundle/start: bundle ## Start a local vault instance and deploy the local VUM bundle to it
	@$(MAKE) vault/start vault/deploy ENT=true

## Catch all tasks
.PHONY: controller/stop
controller/stop: ## Start a local vault instance and deploy things to it
	@$(MAKE) vault/stop ENT=true
	@$(MAKE) vault/stop
	@$(MAKE) kube/stop
	@$(MAKE) clean/bundle