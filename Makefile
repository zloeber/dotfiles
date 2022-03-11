SHELL := /bin/bash
.DEFAULT_GOAL := help
PROJECT:=dotfiles

ROOT_PATH := $(abspath $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
LOCAL_BIN_PATH := ${HOME}/.local/bin
APP_PATH := ${HOME}/.local/app

# Generic shared variables
ifeq ($(shell uname -m),x86_64)
ARCH?=amd64
endif
ifeq ($(shell uname -m),i686)
ARCH?=386
endif
ifeq ($(shell uname -m),aarch64)
ARCH?=arm
endif
ifeq ($(OS),Windows_NT)
OS:=Windows
else
OS:=$(shell sh -c 'uname -s 2>/dev/null || echo not' | tr '[:upper:]' '[:lower:]')
endif

DOCKER_SERVER:=localhost
DOCKER_FILE:=Dockerfile
DOCKER_PATH:=$(ROOT_PATH)
DOCKER_IMAGE:=${PROJECT}
#DOCKER_BUILD_ARGS ?= --build-arg VERSION=$(VERSION) --build-arg GIT_COMMIT=$(GIT_COMMIT)

.PHONY: help
help: ## Help
	@grep --no-filename -E '^[a-zA-Z_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

## Docker Tasks
dive := $(BIN_PATH)/dive

.PHONY: .dep/dive
.dep/dive: ## Install docker image exploration tool, dive
	@[ -n "/tmp" ] && [ -n "dive" ] && rm -rf "/tmp/dive"
	@mkdir -p /tmp/dive $(BIN_PATH)
	@curl --retry 3 --retry-delay 5 --fail -sSL -o - https://github.com/wagoodman/dive/releases/download/v0.9.2/dive_0.9.2_$(OS)_$(ARCH).tar.gz | tar -zx -C '/tmp/dive'
	@find /tmp/dive -type f -name 'dive*' | xargs -I {} cp -f {} $(dive)
	@chmod +x $(dive)
	@[ -n "/tmp" ] && [ -n "dive" ] && rm -rf "/tmp/dive"

.dep/direnv: .dep/githubapp ## Install direnv
ifeq (,$(wildcard $(LOCAL_BIN_PATH)/direnv))
	@$(MAKE) -C $(APP_PATH)/ghr-installer install direnv
endif

.dep/xpanes: ## Install xpanes
ifeq (,$(wildcard $(LOCAL_BIN_PATH)/xpanes))
	wget https://raw.githubusercontent.com/greymd/tmux-xpanes/v4.1.1/bin/xpanes -O $(LOCAL_BIN_PATH)/xpanes
	chmod +x $(LOCAL_BIN_PATH)/xpanes
endif
.PHONY: docker/login
docker/login: ## Login to container registry
	docker login $(DOCKER_SERVER)

.PHONY: docker/build
docker/build: ## Build docker image
	docker build \
		$(DOCKER_BUILD_ARGS) -t $(DOCKER_IMAGE):local -f $(DOCKER_FILE) $(DOCKER_PATH)

.PHONY: docker/tag
docker/tag: ## Tag container image
	docker tag $(DOCKER_IMAGE):local $(DOCKER_SERVER)/$(DOCKER_IMAGE):$(GIT_COMMIT)
	docker tag $(DOCKER_IMAGE):local $(DOCKER_SERVER)/$(DOCKER_IMAGE):${VERSION}
	docker tag $(DOCKER_IMAGE):local $(DOCKER_SERVER)/$(DOCKER_IMAGE):latest

.dep/broot: ## Install broot directory lister (https://dystroy.org/broot)
ifeq (,$(wildcard $(LOCAL_BIN_PATH)/broot))
	curl --retry 3 --retry-delay 5 --fail -sSL -o $(LOCAL_BIN_PATH)/broot https://dystroy.org/broot/download/x86_64-linux/broot
	chmod +x $(LOCAL_BIN_PATH)/broot
endif
.PHONY: docker/push
docker/push: docker/tag  ## Push tagged images to registry
	@echo "Pushing container image to registry: latest ${VERSION} $(GIT_COMMIT)"
	docker push $(DOCKER_SERVER)/$(DOCKER_IMAGE):$(GIT_COMMIT)
	docker push $(DOCKER_SERVER)/$(DOCKER_IMAGE):${VERSION}
	docker push $(DOCKER_SERVER)/$(DOCKER_IMAGE):latest

.PHONY: docker/run
docker/run: ## Run a local container image for the app
	docker run -t --rm -i --name=$(PROJECT) $(DOCKER_IMAGE):local

.PHONY: docker/shell
docker/shell: ## Run a local container image for the app
	docker run -t --rm -i --name=$(PROJECT) $(DOCKER_IMAGE):local /bin/zsh

.PHONY: docker/root/shell
docker/root/shell: ## Run a local container image for the app
	docker run --user root -t --rm -i --name=$(PROJECT) $(DOCKER_IMAGE):local /bin/bash

.PHONY: docker/dive
docker/dive: .dep/dive ## Examine the image with the dive
	$(dive) $(DOCKER_IMAGE):local

.PHONY: docker/clean
docker/clean: ## Build docker image
	docker image rm $(DOCKER_IMAGE):local

.PHONY: .setupstream
.setupstream: ## Set the current git branch upstream to a branch by the same name on the origin
	@git branch --set-upstream-to=origin/$(GIT_BRANCH) $(GIT_BRANCH)

.PHONY: .syncmaster
.syncmaster: .setupstream ## Sync up branch with master updates
	@git pull --all --tags
	@git merge master