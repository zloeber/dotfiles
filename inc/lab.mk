SHELL := /bin/bash
ROOT_PATH := $(abspath $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))

.DEFAULT_GOAL := help

docker_cmd := $(shell if ! command -v -- "docker" > /dev/null 2>&1; then echo "echo docker"; else echo $$(which docker); fi)

## Shared
SECRETS ?= $(ROOT_PATH)/.SECRETS
ifneq (,$(wildcard $(SECRETS)))
include ${SECRETS}
export $(shell sed 's/=.*//' $(SECRETS))
endif
PROJECT := provision-local
LOCAL_PATH := $(ROOT_PATH)/.local
DEPLOY_PATH := $(ROOT_PATH)/deploy
DOCS_PATH := $(ROOT_PATH)/docs
PUBLIC_PATH := $(ROOT_PATH)/public
CONFIG_PATH := $(ROOT_PATH)/config
PYTHON_VENV_PATH := $(ROOT_PATH)/venv
TEMP_STATE_PATH := $(LOCAL_PATH)/state 
APP_PATH := $(LOCAL_PATH)/apps
INC_PATH := $(ROOT_PATH)/inc
SCRIPT_PATH := $(ROOT_PATH)/scripts
PROJECT_BIN_PATH := $(LOCAL_PATH)/bin
BUILD_DATE := $(shell date '+%Y-%m-%d-%H:%M:%S')

## System
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

## Git
GITLAB_PATH ?= $(shell git remote get-url origin | sed -Ee 's/.*:(.+)\.git/\1/')
GITLAB_HOST ?= git.gitlab.com
GITLAB_URL ?= https://$(GITLAB_HOST)
GITLAB_UI_PATH ?= $(GITLAB_URL)/$(GITLAB_PATH)
GIT_URL ?= git@$(GITLAB_HOST):$(GITLAB_PATH).git

ifeq ($(IS_CI),"TRUE")
IS_CI ?= ${IS_CI}
TASKSETS := versions terraform vault kube lab controller
else
TASKSETS := versions terraform vault kube docker lab controller openldap pki dynamodb splunk
endif

INCLUDES := $(foreach taskset, $(TASKSETS), $(addprefix $(INC_PATH)/, $(taskset).mk))
-include $(INCLUDES)

ifdef ENT
VAULTRC_CONFIG := $(ROOT_PATH)/.vaultrc.config.ent.yml
VAULT_IMAGE := registry.nmlv.nml.com/idam-pxm/images/docker-vault:$(VAULT_VERSION)_ent
else
VAULTRC_CONFIG := $(ROOT_PATH)/.vaultrc.config.yml
VAULT_IMAGE := registry.nmlv.nml.com/idam-pxm/images/docker-vault:$(VAULT_VERSION)
endif

CONTROLLER_BRANCH ?= master
VAULT_ENVIRONMENT ?= local

hvault-helper:=$(PYTHON_VENV_PATH)/bin/hvault-helper
hvault-helper-cmd:=$(hvault-helper) -c $(VAULTRC_CONFIG)
vault-cli:=$(PYTHON_VENV_PATH)/bin/vault-cli
mkdocs := $(PYTHON_VENV_PATH)/bin/mkdocs

DOCKER_IMAGE?=$(PROJECT)

.PHONY: help
help: ## Help (standard)
	@grep --no-filename -E '^[a-zA-Z_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: deps
ifeq ($(IS_CI),"TRUE")
deps: venv .dep/vault .dep/terraform .dep/kind .dep/kubectl .dep/jq .dep/helm ## Install dependant apps and images in CI
else
deps: .dep/hvault-helper .dep/vault .dep/terraform .dep/kind .dep/kubectl .dep/jq .dep/helm vault/build ## Install dependant apps and images
endif

.PHONY: clean
clean: clean/state clean/bundle ## Clean up the environment

.PHONY: .dep/hvault-helper
.dep/hvault-helper: ## Install hvault-helper from Nexus
	@python3 -m venv $(PYTHON_VENV_PATH)
	@source $(PYTHON_VENV_PATH)/bin/activate && \
		$(PYTHON_VENV_PATH)/bin/pip3 install -q pip wheel --upgrade --index-url=https://pypi.org/simple/ && \
		$(PYTHON_VENV_PATH)/bin/pip3 install -q -r $(ROOT_PATH)/requirements.txt && \
		$(PYTHON_VENV_PATH)/bin/pip3 install -q \
			--default-timeout=120 \
			--extra-index-url https://nexus.nmlv.nml.com/repository/pypi-nmlv/simple/ \
			--upgrade \
			--disable-pip-version-check \
			-I hvault-helper==$(HVAULT_HELPER_VERSION) \
			--no-warn-conflicts
	@echo "HVAULT_HELPER_VERSION: $(HVAULT_HELPER_VERSION)"

.PHONY: venv
venv:  ## Configure python virtual environment for environment
	@python3 -m venv $(PYTHON_VENV_PATH)
	@source $(PYTHON_VENV_PATH)/bin/activate && \
		$(PYTHON_VENV_PATH)/bin/pip3 install --quiet pip wheel --upgrade --index-url=https://pypi.org/simple/ && \
		$(PYTHON_VENV_PATH)/bin/pip3 install --quiet -r $(ROOT_PATH)/requirements.txt

.PHONY: show
show: ## Show environment information
	@echo "VAULT_ENVIRONMENT: $(VAULT_ENVIRONMENT)"
	@echo "VAULT_VERSION: $(VAULT_VERSION)"
	@echo "VAULT_ADDR: $(VAULT_ADDR)"
	@echo "VAULT_ADDRESS: $(VAULT_ADDRESS)"
	@echo "HVAULT_HELPER_VERSION: $(HVAULT_HELPER_VERSION)"
	@echo "PROJECT: $(PROJECT)"
	@echo "ENT: $(ENT)"
	@echo "TF_VERSION: $(TF_VERSION)"
	@echo "VAULT_IMAGE: $(VAULT_IMAGE)"
	@echo "VAULTRC_CONFIG: $(VAULTRC_CONFIG)"
	@echo "OS: $(OS)"
	@echo "ARCH: $(ARCH)"
	@echo "CONTROLLER_BRANCH: $(CONTROLLER_BRANCH)"
	@echo "DOCKER_IMAGE: $(DOCKER_IMAGE)"
	@echo "GIT_URL: $(GIT_URL)"
	@echo "PUBLIC_PATH: $(PUBLIC_PATH)"
	@echo "docker_cmd: $(docker_cmd)"
	@echo "IS_CI: $(IS_CI)"

.PHONY: show/versions
show/versions: ## Show all versions defined
	@echo "VAULT_VERSION: $(VAULT_VERSION)"
	@echo "HVAULT_HELPER_VERSION: $(HVAULT_HELPER_VERSION)"
	@echo "TF_VERSION: $(TF_VERSION)"
	@echo "KIND_VERSION: $(KIND_VERSION)"
	@echo "KUBECTL_VERSION: $(KUBECTL_VERSION)"
	@echo "HELM_VERSION: $(HELM_VERSION)"
	@echo "JQ_VERSION: $(JQ_VERSION)"

## Catch all tasks
.PHONY: start
start: stop controller/start ## Start a local vault instance and deploy things to it

.PHONY: stop
stop: lab/stop ## Stop and destroy the local vault dev instance

.PHONY: status
status: kube/status vault/status ## Show status of existing environment

.PHONY: .toc
.toc: ## Insert table of contents into README.md
	@python3 -m venv venv
	@source venv/bin/activate && \
		venv/bin/pip3 install --quiet pip mdtoc --upgrade --index-url=https://pypi.org/simple/
	@$(ROOT_PATH)/venv/bin/mdtoc $(ROOT_PATH)/README.md

.PHONY: gitlab/ui
gitlab/ui: ## Open gitlab ui for current project
	@open $(GITLAB_UI_PATH)/-/pipelines

.PHONY: docs
docs: venv ## Create public documentation
	$(PYTHON_VENV_PATH)/bin/pip3 install --quiet mkdocs mkdocs-material
	@mkdir -p $(PUBLIC_PATH)
	@mkdir -p $(DOCS_PATH)/docs
	@ln -sf $(ROOT_PATH)/README.md $(DOCS_PATH)/README.md
	@ln -sf $(DOCS_PATH)/kubernetes.md $(DOCS_PATH)/docs/kubernetes.md
	@ln -sf $(DOCS_PATH)/kubernetes-csi.md $(DOCS_PATH)/docs/kubernetes-csi.md
	@ln -sf $(DOCS_PATH)/kubernetes-flux.md $(DOCS_PATH)/docs/kubernetes-flux.md
	@$(ROOT_PATH)/venv/bin/mkdocs build -d $(PUBLIC_PATH)

.PHONY: deps/reset
deps/reset: ## Removes downloaded binary dependencies
	@rm -rf $(PROJECT_BIN_PATH)/*

.PHONY: %
%: ## A parameter
	@true