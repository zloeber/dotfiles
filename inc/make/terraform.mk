tflint := $(PROJECT_BIN_PATH)/tflint
terraform := $(PROJECT_BIN_PATH)/terraform

TF_VERSION ?= 0.15.3
TFLINT_VERSION ?= 0.22.0

TF_PATH ?= $(ROOT_PATH)/deploy
TF_PLAN_NAME ?= $(shell basename $(TF_PATH))

### Terraform tasks
.PHONY: .dep/terraform
.dep/terraform: ## Install local terraform binary
ifeq (,$(wildcard $(terraform)))
	@echo "Attempting to install terraform - $(TF_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL -o /tmp/terraform.zip https://releases.hashicorp.com/terraform/$(TF_VERSION)/terraform_$(TF_VERSION)_$(OS)_$(ARCH).zip
	@unzip -d $(PROJECT_BIN_PATH) /tmp/terraform.zip && rm /tmp/terraform.zip
endif
	@echo "terraform binary: $(terraform)"

rover:=$(PROJECT_BIN_PATH)/rover
ROVER_VERSION:=0.2.2
.PHONY: .dep/rover
.dep/rover: ## Install rover
ifeq (,$(wildcard $(rover)))
	@rm -rf "/tmp/rover"	
	@mkdir -p $(PROJECT_BIN_PATH)
	@mkdir -p /tmp/rover
	@curl --retry 3 --retry-delay 5 --fail -sSL -L -o /tmp/rover/rover.zip \
		https://github.com/im2nguyen/rover/releases/download/v$(ROVER_VERSION)/rover_$(ROVER_VERSION)_$(OS)_$(ARCH).zip
	@unzip /tmp/rover/rover.zip -d /tmp/rover
	@mv /tmp/rover/rover_v$(ROVER_VERSION) $(rover)
	@chmod +x $(rover)
endif
	@echo "rover binary: $(rover)"
# .PHONY: tflint
# tf/lint: .dep/tflint ## Perform tflint on current terraform
# 	$(tflint) $(TF_PATH)

.PHONY: tf/format
tf/format: ## Auto-format terraform files
	$(terraform) fmt -recursive -write=true $(TF_PATH)

.PHONY: tf/clean
tf/clean: ## Clean local cached terreform elements
	@echo "** TERRAFORM - CLEAN $(TF_PATH) **"
	@rm -rf $(TF_PATH)/.terraform || true
	@rm -rf $(TF_PATH)/.terraform.tfstate || true

.PHONY: tf/init
tf/init: ## Initialize terraform
	@echo "** TERRAFORM - INIT $(TF_PATH) **"
	@$(terraform) -chdir=$(TF_PATH) init

.PHONY: tf/taint
tf/taint: ## Taint a state element
	$(terraform) -chdir=$(TF_PATH) taint $(TF_TAINT)

.PHONY: tf/plan
tf/plan: ## Plan deployment
	@echo "** TERRAFORM - PLAN $(TF_PATH) **"
	$(terraform) -chdir=$(TF_PATH) plan -state=$(TF_PATH)/terraform.tfstate -out=$(TF_PATH)/tfplan.plan
	$(terraform) -chdir=$(TF_PATH) show -json $(TF_PATH)/tfplan.plan > $(TF_PATH)/tfplan.json

DOCS_PATH ?= $(ROOT_PATH)/docs
.PHONY: tf/visualize
tf/visualize: .dep/rover ## Visualize deployment
	@echo "** TERRAFORM - Visualize ($($(TF_PLAN_NAME))) **"
	$(rover) -workingDir $(TF_PATH) \
		-tfPath $(terraform) \
		-standalone \
		-name $(TF_PLAN_NAME) \
		-planPath $(TF_PATH)/tfplan.plan \
		-zipFileName $(TF_PATH)/plan_map
	@rm -rf $(DOCS_PATH)/planmap/$(TF_PLAN_NAME)
	@mkdir -p $(DOCS_PATH)/planmap/$(TF_PLAN_NAME)
	@unzip -d $(DOCS_PATH)/planmap/$(TF_PLAN_NAME) $(TF_PATH)/plan_map.zip && rm $(TF_PATH)/plan_map.zip

.PHONY: tf/apply
tf/apply: ## Apply deployment
	@echo "** TERRAFORM - APPLY: $(TF_PATH) **"
	$(terraform) -chdir=$(TF_PATH) apply -state=$(TF_PATH)/terraform.tfstate -auto-approve

.PHONY: tf/graph
tf/graph: ## graph deployment
	@$(terraform) graph -type=apply $(TF_PATH)

.PHONY: tf/upgrade
tf/upgrade: ## Apply terraform 0.13upgrade
	$(terraform) 0.13upgrade $(TF_PATH)

.PHONY: tf/destroy
tf/destroy: ## Destroy the environment
	$(terraform) destroy -state=$(TF_PATH)/terraform.tfstate -auto-approve $(TF_PATH)

.PHONY: tf/state/list
tf/state/list: ## Show tf state list
	$(terraform) state list -state=$(TF_PATH)/terraform.tfstate

.PHONY: tf/state/show
tf/state/show: ## Show tf state
	$(terraform) state show -state=$(TF_PATH)/terraform.tfstate