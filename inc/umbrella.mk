# Umbrella repo for vault project work
SHELL:=/bin/bash
.DEFAULT_GOAL:=help

ROOT_PATH := $(abspath $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
PROFILE ?= default
CONFIG_FILE ?= $(ROOT_PATH)/$(PROFILE).yml
SKIP_ERRORS ?= 2>/dev/null || true
HOME_PATH := $(ROOT_PATH)/.local
APP_PATH := $(HOME_PATH)/apps
PROJECT_BIN_PATH := $(HOME_PATH)/bin
SCRIPT_PATH ?= $(ROOT_PATH)/scripts
VAULTLOGIN_VERSION := 0.7.2
GITLAB_CI_JSON := $(shell jq --raw-input --slurp < $(ROOT_PATH)/.gitlab-ci.yml || true)
TF_MODULE_FILTER := terraform-module-

# Generic shared variables
ifeq ($(shell uname -m),x86_64)
ARCH ?= amd64
endif
ifeq ($(shell uname -m),i686)
ARCH ?= 386
endif
ifeq ($(shell uname -m),aarch64)
ARCH ?= arm
endif
ifeq ($(OS),Windows_NT)
OS := Windows
else
OS := $(shell sh -c 'uname -s 2>/dev/null || echo not' | tr '[:upper:]' '[:lower:]')
endif

ifdef CI
yq := $(shell which yq || echo $(PROJECT_BIN_PATH)/yq)
jq := $(shell which jq || echo $(PROJECT_BIN_PATH)/jq)
gomplate := $(shell which gomplate || echo $(PROJECT_BIN_PATH)/gomplate)
task := $(shell which task || echo $(PROJECT_BIN_PATH)/task)
else
yq := $(PROJECT_BIN_PATH)/yq
jq := $(PROJECT_BIN_PATH)/jq
gomplate := $(PROJECT_BIN_PATH)/gomplate
task := $(PROJECT_BIN_PATH)/task
endif

ENV ?= poc
INSTANCE_IP ?= <instance_ip>
AWS_CONFIG ?= ${HOME}/.aws/config

# Import target env vars
ENVIRONMENT_VARS ?= environments/$(ENV).env
ifneq (,$(wildcard $(ENVIRONMENT_VARS)))
include ${ENVIRONMENT_VARS}
export $(shell sed 's/=.*//' ${ENVIRONMENT_VARS})
endif

# Import env locally defined env vars
OVERRIDE_VARS ?= environments/$(ENV).override.env
ifneq (,$(wildcard $(OVERRIDE_VARS)))
include ${OVERRIDE_VARS}
export $(shell sed 's/=.*//' ${OVERRIDE_VARS})
endif

VAULTLOGIN_ENV ?= nonprod
VAULT_VERSION := 1.7.2

ifneq (,$(wildcard $(yq)))
WORKSPACE ?= $(shell $(yq) r $(CONFIG_FILE) workspace)
PROJECT ?= $(shell $(yq) r $(CONFIG_FILE) project)
REPO_LIST ?= $(shell $(yq) r $(CONFIG_FILE) 'repos.*.url')
MODULE_LIST ?= $(shell $(yq) r $(CONFIG_FILE) 'repos.*.name' | grep '$(TF_MODULE_FILTER)' )
REPO_COUNT ?= $(shell $(yq) r $(CONFIG_FILE) 'repos.*.url' --collect --length)
REPO_PATHS ?= $(shell $(yq) r $(CONFIG_FILE) 'repos.*.name')
else
WORKSPACE ?= workspace
PROJECT ?= project
REPO_LIST ?=
MODULE_LIST ?= 
REPO_COUNT ?= 0
endif

WORKSPACE_PATH ?= $(WORKSPACE)/$(PROJECT)

# Gitlab
CICD_VERSION?=v0.1.99
GITLAB_ID:=87437
GITLAB_PATH ?= idam-pxm/tools/util-umbrella
GITLAB_UI_PATH ?= https://gitlab.com/$(GITLAB_PATH)
GITLAB_API_PATH ?= https://gitlab.com/api/v4

.PHONY: help
help: ## Help
	@grep --no-filename -E '^[a-zA-Z_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: .prompt/workspace_yesno
.prompt/workspace_yesno: ## Are you sure
	@( read -p "This will blow away all of your $(WORKSPACE) folders. Are you sure? [y/N]: " sure && case "$$sure" in [yY]) true;; *) false;; esac )

.PHONY: workspace
workspace: ## Clone all repos in project to $(WORKSPACE_PATH)
	@mkdir -p $(WORKSPACE_PATH)
	@yq=$(yq) BASE_PATH=$(ROOT_PATH) CONFIG_FILE=$(CONFIG_FILE) $(SCRIPT_PATH)/workspace.sh

.PHONY: workspace/update
workspace/update: workspace ## Update all workspace repos

#workspace/update: ## Update all workspace repos
# @find $(WORKSPACE_PATH) -type d -name .git -exec git --git-dir={} --work-tree={}/.. pull --all \;
# @echo "Workspace Updated: $(WORKSPACE_PATH)"

.PHONY: workspace/remove
workspace/remove: .prompt/workspace_yesno ## Removes entire workspace
	rm -rf $(WORKSPACE_PATH) || true

.PHONY: .update/self
.update/self: ## Update local repo
	@git pull --all --tags || true

.PHONY: update
update: .update/self workspace/update ## Shortcut for workspace/update

.PHONY: show
show: ## Show standard env vars
	@echo "OS: $(OS)"
	@echo "ENV: $(ENV)"
	@echo "ROOT_PATH=$(ROOT_PATH)"
	@echo "WORKSPACE=$(WORKSPACE)"
	@echo "WORKSPACE_PATH=$(WORKSPACE_PATH)"
	@echo "PROJECT=$(PROJECT)"
	@echo "WORKSPACE_PATH=$(WORKSPACE_PATH)"
	@echo "REPO_COUNT=$(REPO_COUNT)"
	@echo "VAULT_ADDR=$(VAULT_ADDR)"
	@echo "AWS_PROFILE=$(AWS_PROFILE)"
	@echo "AWS_CONFIG=$(AWS_CONFIG)"
	@echo "ENVIRONMENT_VARS=$(ENVIRONMENT_VARS)"
	@echo "GITLAB_API_PATH=${GITLAB_API_PATH}"

.PHONY: show/repos
show/repos: ## Show repositories in your workspace
	@$(yq) r $(CONFIG_FILE) 'repos.*.url' | cut -d "|" -f 2

.PHONY: show/workspace/tree
show/workspace/tree: ## Show a tree view of workspace
	@tree $(WORKSPACE_PATH) -d --prune -L 2 || true

.PHONY: deps
deps: $(yq) $(vault) $(jq) $(gomplate) ## Install dependant apps
#deps: .dep/githubapps .dep/yq .dep/vault .dep/jq .dep/vaultlogin ## Install dependant apps

# .PHONY: .dep/githubapps
# .dep/githubapps: ## Install githubapp (ghr-installer)
# ifeq (,$(wildcard $(APP_PATH)/githubapp))
# 	@rm -rf $(APP_PATH)
# 	@mkdir -p $(APP_PATH)
# 	@git clone https://github.com/zloeber/ghr-installer $(APP_PATH)/githubapp
# endif

# .PHONY: .dep/yq
# .dep/yq: ## Install yq
# ifeq (,$(wildcard $(yq)))
# 	@$(MAKE) --no-print-directory -C $(APP_PATH)/githubapp auto mikefarah/yq INSTALL_PATH=$(PROJECT_BIN_PATH)
# endif

# .PHONY: .dep/yq
# .dep/yq: ## Install yq
# ifeq (,$(wildcard $(yq)))
# 	@$(MAKE) --no-print-directory -C $(APP_PATH)/githubapp auto mikefarah/yq INSTALL_PATH=$(PROJECT_BIN_PATH)
# endif

YQ_VERSION ?= 3.4.1
$(yq): ## Install yq
	@echo "Attempting to install yq - $(YQ_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL \
		-o $(yq) https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH)
	@chmod +x $(yq)
	@echo "Binary requirement: $(yq)"

JQ_VERSION ?= 1.6
#.PHONY: .dep/jq
$(jq): ## Install jq
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
	@echo "Binary requirement: $(jq)"

.PHONY: .dep/aws-support-tools
.dep/aws-support-tools: ## Install aws-support-tools
	git clone https://github.com/awslabs/aws-support-tools $(APP_PATH)/aws-support-tools

.PHONY: aws/find-lambda-eni/%
aws/find-lambda-eni/%: ## uses aws support tools to find eni for lambda
	$(APP_PATH)/aws-support-tools/Lambda/FindEniMappings/findEniAssociations --eni $(subst aws/find-lambda-eni/,,$@) --region $(AWS_DEFAULT_REGION)

.PHONY: aws/lambda-enis/%
aws/lambda-enis/%: ## uses aws to find lambda enis based on security group
	aws ec2 describe-network-interfaces --filter 'Name=description,Values="AWS Lambda VPC ENI*", Name=group-id,Values=$(subst lambda-enis/,,$@)'

GOMPLATE_VERSION ?= 3.7.0
$(gomplate): ## Install gomplate
	@echo "Attempting to install gomplate - $(GOMPLATE_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL \
		-o $(gomplate) \
		https://github.com/hairyhenderson/gomplate/releases/download/v$(GOMPLATE_VERSION)/gomplate_$(OS)-$(ARCH)
	@chmod +x $(gomplate)
	@echo "Binary requirement: $(gomplate)"

# .PHONY: .dep/vault
$(vault): ## Install local vault binary
	@echo "Attempting to install vault $(VAULT_VERSION)"
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL \
		-o /tmp/vault_ent.zip \
		https://nexus.nmlv.nml.com/repository/nmlv-artifacts/idampxm/vault/vault-enterprise_$(VAULT_VERSION)+prem_$(OS)_$(ARCH).zip 
	@unzip -d $(PROJECT_BIN_PATH) /tmp/vault_ent.zip && rm /tmp/vault_ent.zip
	@echo "Binary requirement: $(vault)"

.PHONY: .dep/aws-cli/mac
.dep/aws-cli/mac: .dep/gomplate ## Install aws cli v2 for mac and add to $HOME/.local/bin path
	tmpdir=$$(mktemp -d) && \
	curl https://awscli.amazonaws.com/AWSCLIV2.pkg -o $${tmpdir}/AWSCLIV2.pkg && \
	$(gomplate) \
		--file $(ROOT_PATH)/extras/aws-mac.xml \
		--out "$${tmpdir}/choices.xml" && \
	installer -pkg $${tmpdir}/AWSCLIV2.pkg \
		-target CurrentUserHomeDirectory \
		-applyChoiceChangesXML "$${tmpdir}/choices.xml"
	@mkdir -p ${HOME}/.local/bin/
	@ln -sf ${HOME}/aws-cli/aws ${HOME}/.local/bin/aws
	@ln -sf ${HOME}/aws-cli/aws-cli/aws_completer ${HOME}/.local/bin/aws_completer

$(vaultlogin): ## Install and run vault login
	@rm -rf /tmp/vaultlogin && mkdir -p /tmp/vaultlogin
	@mkdir -p $(PROJECT_BIN_PATH)
	@curl -o /tmp/vaultlogin/vaultlogin.zip https://nexus.nmlv.nml.com/repository/nmlv-artifacts/ix/vaultlogin/v$(VAULTLOGIN_VERSION)/vaultlogin_v$(VAULTLOGIN_VERSION).zip
	@cd /tmp/vaultlogin && unzip -q vaultlogin.zip && mv ./vaultlogin $(vaultlogin)
	@echo "Binary requirement: $(vaultlogin)"

.PHONY: vaultlogin/token
vaultlogin/token: .dep/vaultlogin ## Run vaultlogin for current environment
	@echo $(shell $(vaultlogin) --env $(VAULTLOGIN_ENV) token --overrideVaultURL=$(VAULT_ADDR) | grep "Vault token is" | cut -d " " -f 4)

.PHONY: vaultlogin/token/cmd
vaultlogin/token/cmd: .dep/vaultlogin ## Spit out the vaultlogin command to use for this environment
	@echo "$(vaultlogin) --env $(VAULTLOGIN_ENV) token --overrideVaultURL=$(VAULT_ADDR)"

.PHONY: vaultlogin/ssh
vaultlogin/ssh: ## Run vaultlogin for signed SSH key generation
	$(vaultlogin) ssh \
		--sshKey $(SSH_KEY_PATH) \
		--pubWritePath $(ROOT_PATH)/.local \
		--role $(SSH_ROLE) \
		--env $(VAULTLOGIN_ENV)

.PHONY: vaultlogin/ssh/cmd
vaultlogin/ssh/cmd: ## Spit out the vaultlogin ssh command to use for this environment
	@echo "$(vaultlogin) ssh \
		--sshKey $(SSH_KEY_PATH) \
		--pubWritePath $(ROOT_PATH)/.local \
		--role $(SSH_ROLE) \
		--env $(VAULTLOGIN_ENV)"

.PHONY: ssh/instance
ssh/instance: ## ssh to an instance after running vaultlogin
	ssh -i $(SSH_KEY_PATH) -i $(ROOT_PATH)/.local/signed-public-key-$(VAULTLOGIN_ENV).pem centos@$(INSTANCE_IP)

.PHONY: ssh/instance/cmd
ssh/instance/cmd: ## Spit out the ssh command to use to login to an instance after running vaultlogin
	@echo "ssh -i $(SSH_KEY_PATH) -i $(ROOT_PATH)/.local/signed-public-key-$(VAULTLOGIN_ENV).pem centos@$(INSTANCE_IP)"

.PHONY: vault/login
vault/login: ## export VAULT_TOKEN=xxxxxxx
	@echo "export VAULT_TOKEN=$(shell $(MAKE) vaultlogin/token)"

.PHONY: vault/ui
vault/ui: ## Open vault ui for current environment
	@open $(VAULT_ADDR)/ui

.PHONY: vault/addr
vault/addr: ## export VAULT_ADDR=xxxxxx
	@echo "export VAULT_ADDR=$(VAULT_ADDR)"

.PHONY: .dep/aws-nm-login
.dep/aws-nm-login: ## Install aws-nm-login via npm
	npm install -g aws-nm-login --registry https://sinopia.nmlv.nml.com

.PHONY: aws-nm-login/config
aws-nm-login/config: ## configure profile for nm-login
	aws-nm-login --configure --profile $(AWS_PROFILE)

.PHONY: aws-nm-login
aws-nm-login: ## runs aws-nm-login for current ENV
	aws-nm-login --keychain --profile $(AWS_PROFILE) --session-duration 28800

.PHONY: aws/profile
aws/profile: ## Setup default values for current env (run only once!)
	@echo '' >> $(AWS_CONFIG)
	@echo '[profile $(AWS_PROFILE)]' >> $(AWS_CONFIG)
	@aws configure set region $(AWS_DEFAULT_REGION)
	@aws configure set output $(AWS_DEFAULT_OUTPUT)
	@aws configure set default_username $(shell whoami)
	@aws configure set role_arn $(AWS_DEFAULT_ROLE_ARN)
	@aws configure set source_profile $(AWS_PROFILE)
	@echo "Aws profile configured with default values: $(AWS_PROFILE)"

.PHONY: show/aws
show/aws: ## Show aws env vars for environment
	@echo "export AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION)"
	@echo "export AWS_PAGER="
	@echo "export AWS_ROLE_ARN=$(AWS_DEFAULT_ROLE_ARN)"
	@cat "${HOME}/.aws/session_env"

.PHONY: aws/ec2/instances
aws/ec2/instances: ## List vault instances for environment
	aws --profile $(AWS_PROFILE) --output text \
		ec2 describe-instances \
		--query 'Reservations[*].Instances[*].[Tags[?Key==`environment` && contains(Value, `$(ENV)`)].Value | [0],Tags[?Key==`Name`].Value | [0],State.Name,PrivateIpAddress]' | \
		column -t | sort

.PHONY: .aws/assume-role
.aws/assume-role: ## Assume role for the environment for aws cli
	@tmpsession=`aws sts assume-role --role-arn "$(AWS_DEFAULT_ROLE_ARN)" --role-session-name AWSCLI-$(ENV)-Session`; \
		echo "export AWS_ACCESS_KEY_ID=`echo $$tmpsession | jq -r '.Credentials.AccessKeyId'`"; \
		echo "export AWS_SECRET_ACCESS_KEY=`echo $$tmpsession | jq -r '.Credentials.SecretAccessKey'`"; \
		echo "export AWS_SESSION_TOKEN=`echo $$tmpsession | jq -r '.Credentials.SessionToken'`"

.PHONY: vault/report
vault/report: ## Download autogenerated vault report from s3
	@aws --profile $(AWS_PROFILE) s3 sync s3://vault-reports-$(ENV) $(HOME_PATH)/vault-reports-$(ENV)
	@echo synced reports to $(HOME_PATH)/vault-reports-$(ENV)

.PHONY: .tower-cli
.tower-cli: ## Setup towercli
	pip3 install --user https://releases.ansible.com/ansible-tower/cli/ansible-tower-cli-latest.tar.gz
	tower-cli config host tower.nml.com
	tower-cli config verify_ssl false
#tower-cli login <LANID>

.PHONY: .gitlab-cli
.gitlab-cli: ## Setup towercli
	pip3 install --user -U python-gitlab --user --upgrade

.PHONY: .vscode
.vscode: % ## Launch vscode editor for umbrella element specified as a task name
	code ./$(WORKSPACE_PATH)/$(filter-out $@,$(MAKECMDGOALS))/

.PHONY: vscode/select
vscode/select: ## Use fzf to select a workspace to launch vscode against
	@SELECTION=./$(shell find $(WORKSPACE_PATH) -type d -depth 1 -not -path '*/\.*' -prune -print | sort | fzf) && \
	[ "$$SELECTION" != "./" ] && code "$$SELECTION" || true

.PHONY: select
select: ## Use fzf to select a workspace to cd into
	@SELECTION=./$(shell find $(WORKSPACE_PATH) -type d -depth 1 -not -path '*/\.*' -prune -print | sort | fzf) && \
	[ "$$SELECTION" != "./" ] && echo "cd $$SELECTION" || true

.PHONY: vscode/workspace
vscode/workspace: ## Create vscode workspace file
	$(shell CONFIG_FILE=$(CONFIG_FILE) REPO_PATHS="$(REPO_PATHS)" WORKSPACE=$(WORKSPACE) PROJECT=$(PROJECT) $(SCRIPT_PATH)/create-vscode-workspace.sh > $(ROOT_PATH)/umbrella.code-workspace)

.PHONY: module/versions
module/versions: ## Return all terraform modules latest tagged release
	@MODULE_LIST="$(MODULE_LIST)" WORKSPACE_PATH="$(WORKSPACE_PATH)" $(SCRIPT_PATH)/latest-git-tags.sh

.PHONY: module/versions/update
module/versions/update: workspace ## Return all terraform modules latest tagged release, update repos beforehand
	@GIT_UPDATE="TRUE" MODULE_LIST="$(MODULE_LIST)" WORKSPACE_PATH="$(WORKSPACE_PATH)" $(SCRIPT_PATH)/latest-git-tags.sh

.PHONY: cd/repo
cd/repo: ## Use fzf to select a workspace to cd into
	@echo "cd ./$(shell find $(WORKSPACE_PATH) -type d -depth 1 -not -path '*/\.*' -prune -print | sort | fzf)"

.PHONY: .gitlab/projects
.gitlab/projects: ## Use gitlab cli to pull all project info in json format
	@echo "Gitlab project export (uses GITLAB_TOKEN)"
	@echo "Starting export, can take some time to complete..."
	@gitlab -o json project list --all --archived false2>/dev/null | jq '.[] | select(.empty_repo != "true")' > $(HOME_PATH)/gitlab_projects.json
	@echo "Complete, output file: $(HOME_PATH)/gitlab_projects.json"

.PHONY: .gitlab/project/jobs/%
.gitlab/project/jobs/%: ## Use gitlab cli to pull all project job info in json format
	@echo "Gitlab project export (uses GITLAB_TOKEN)"
	@echo "Starting export, can take some time to complete..."
	@gitlab -o json project-job list --project-id $(subst .gitlab/project/jobs/,,$@) --all 2>/dev/null | jq '.[] | select(.empty_repo != "true")' > $(HOME_PATH)/gitlab_project-jobs.json
	@echo "Complete, output file: $(HOME_PATH)/gitlab_projects.json"

.PHONY: .gitlab/project/pipelines/%
.gitlab/project/pipelines/%: ## Use gitlab cli to pull all active pipelines into json format
	@echo "Gitlab project export (uses GITLAB_TOKEN)"
	@echo "Starting export, can take some time to complete..."
	@gitlab -o json project-pipeline list \
		--project-id $(subst .gitlab/project/pipelines/,,$@) \
		--all 2>/dev/null | jq '.[] | select((.status != "success") and (.status != "complete") and (.status != "failed") and (.status != "canceled") and (.status != "skipped")).id'

.PHONY: .gitlab/cancel/project/pipelines/%
.gitlab/cancel/project/pipelines/%: ## Use gitlab cli to cancel active pipelines for a project
	@echo "Gitlab project export (uses GITLAB_TOKEN)"
	@echo "Starting export, can take some time to complete..."
	@for pipelineid in $$(gitlab -o json project-pipeline list \
		--project-id $(subst .gitlab/cancel/project/pipelines/,,$@) \
		--all 2>/dev/null | jq -c '.[] | select((.status != "success") and (.status != "complete") and (.status != "failed") and (.status != "canceled") and (.status != "skipped")).id'); do \
		echo "Cancelling pipeline id: $$pipelineid"; \
		gitlab project-pipeline cancel --project-id $(subst .gitlab/cancel/project/pipelines/,,$@) --id "$$pipelineid" 2>/dev/null; \
	done

.PHONY: .gitlab/project/count
.gitlab/project/count: ## count of projects found in json output (non-archived and non-empty)
	@$(jq) -c 'select( .empty_repo == false and .archived == false).id' $(HOME_PATH)/gitlab_projects.json | wc -l

.PHONY: .gitlab/group/count
.gitlab/group/count: ## count of groups found in json output (non-archived and non-empty)
	@$(jq) -c 'select( .empty_repo == false and .archived == false).namespace.id'  $(HOME_PATH)/gitlab_projects.json | uniq | wc -l

.PHONY: gitlab/lint
gitlab/lint: ## lint current .gitlab-ci.yml file
	@LINT_REPORT=`$(jq) --null-input --arg yaml "$$(<$(ROOT_PATH)/.gitlab-ci.yml)" '.content=$$yaml' \
		| curl  -s '$(GITLAB_API_PATH)/ci/lint?include_merged_yaml=true' \
		--header 'Content-Type: application/json' \
		--data @-` && echo $$LINT_REPORT | jq . --raw-output

.PHONY: gitlab/ui
gitlab/ui: ## Open gitlab ui for current project
	@open $(GITLAB_UI_PATH)

# .PHONY: tf/module/versions
# tf/module/versions: ## Show all referenced module versions in workspace
# 	@find $(WORKSPACE_PATH) -name "*.tf" -print0 -type f -not -path "*/.terraform/*" | xargs -I {}  -0 grep -H --color -e "v[0-9]\+.[0-9]\+.[0-9]\+.*" "{}"

search/workspace/%: ## Search workspace for references to %
	find $(WORKSPACE_PATH) -name "*.tf" -print0 -type f -not -path "**/.local/*" | xargs -I {}  -0 grep -H --color -e "$(subst search/workspace/,,$@)" "{}"

# .PHONY: show/vaultmodules
# show/vaultmodules: ## Show hvault tagged modules
# 	@$(MAKE) -S -C $(WORKSPACE_PATH)/vault_modules show/module/releases

.PHONY: .dep/dive
.dep/dive: ## Install docker image exploration tool, dive
ifeq (,$(wildcard $(dive)))
	@$(MAKE) --no-print-directory -C $(APP_PATH)/githubapp auto wagoodman/dive INSTALL_PATH=$(PROJECT_BIN_PATH)
endif

.PHONY: docker/dive
docker/dive: .dep/dive ## Examine the image with the dive
	$(dive) $(DOCKER_IMAGE):local

.PHONY: backup/state
backup/state: ## Backup the state for an environment
	@mkdir -p $(HOME_PATH)/$(ENV)/state
	@aws --profile $(AWS_PROFILE) s3 sync s3://nwm-vault-${ENV}-tf-state $(HOME_PATH)/$(ENV)/state
	@echo synced reports to $(HOME_PATH)/$(ENV)/state

.PHONY: vault/agent
vault/agent: ## Authenticate with vault agent
	vault agent -config=$(ROOT_PATH)/environments/vault-agent.$(ENV).hcl
	@cat $(ROOT_PATH)/.local/VaultToken

.PHONY: git/lint
git/lint: ## Find merge request conflict detrius
	@echo "Looking for merge request conflict detrius"
	@failedfiles=$$(find . -type f \( -iname "*.tf" -o -iname "*.yml" -o ! -iname "workspace" ! -iname ".local" ! -iname "venv*" ! -iname ".git" ! -iname "Makefile" \) -exec grep -l "<<<<<<< HEAD" {} \;); \
	if [ "$$failedfiles" ]; then echo "Failed git/lint files: $${failedfiles} "; exit 1; fi

.PHONY: find/ref
find/ref: ## Find ref statements
	@find $(WORKSPACE_PATH) -type f \( -iname ".gitlab-ci.yml" \) -exec grep "ref:" {} \;

.PHONY: update/ref
update/ref: ## Update ref statements
	find $(WORKSPACE_PATH) -type f  \( -iname ".gitlab-ci.yml" \) -exec sed -i 's/ref:.+/ref: $(CICD_VERSION)/g' {} \;

.PHONY: .bump/provisioners
.bump/provisioners: ## Update ref statements
	$(ROOT_PATH)/scripts/bump-provisioners.sh

%: ## A parameter
	@true