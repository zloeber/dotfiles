SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT_PATH := $(abspath $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST))))))
BIN_PATH := ${HOME}/.local/bin
APP_PATH := ${HOME}/.local/app

# Generic shared variables
ifeq ($(shell uname -m),x86_64)
ARCH ?= "amd64"
endif
ifeq ($(shell uname -m),i686)
ARCH ?= "386"
endif
ifeq ($(shell uname -m),aarch64)
ARCH ?= "arm"
endif
ifeq ($(OS),Windows_NT)
OS := Windows
else
OS := $(shell sh -c 'uname -s 2>/dev/null || echo not' | tr '[:upper:]' '[:lower:]')
endif

.PHONY: help
help: ## Help
	@echo 'Commands:'
	@grep -E '^[a-zA-Z1-9_%/-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

deps: .dep/githubapp .dep/direnv .dep/asdf .dep/xpanes .dep/broot ## Dependencies

.dep/githubapp: ## Install githubapp
ifeq (,$(wildcard $(APP_PATH)/ghr-installer/Makefile))
	@mkdir -p $(APP_PATH)
	rm -rf $(APP_PATH)/ghr-installer
	git clone https://github.com/zloeber/ghr-installer.git $(APP_PATH)/ghr-installer
endif

.dep/direnv: .dep/githubapp ## Install direnv
ifeq (,$(wildcard $(BIN_PATH)/direnv))
	@$(MAKE) -C $(APP_PATH)/ghr-installer install direnv
endif

.dep/xpanes: ## Install xpanes
ifeq (,$(wildcard $(BIN_PATH)/xpanes))
	wget https://raw.githubusercontent.com/greymd/tmux-xpanes/v4.1.1/bin/xpanes -O $(BIN_PATH)/xpanes
	chmod +x $(BIN_PATH)/xpanes
endif

.dep/asdf: ## Install asdf-vm
ifeq (,$(wildcard ${HOME}/.asdf/bin/asdf))
	rm -rf ${HOME}/.asdf
	git clone https://github.com/asdf-vm/asdf.git ${HOME}/.asdf
	cd ${HOME}/.asdf && git checkout `git describe --abbrev=0 --tags`
endif

.dep/broot: ## Install broot directory lister (https://dystroy.org/broot)
ifeq (,$(wildcard $(BIN_PATH)/broot))
	curl --retry 3 --retry-delay 5 --fail -sSL -o $(BIN_PATH)/broot https://dystroy.org/broot/download/x86_64-linux/broot
	chmod +x $(BIN_PATH)/broot
endif

show: ## Show some settings
	@echo "OS: $(OS)"
	@echo "ARCH: $(ARCH)"
	@echo "HOME: ${HOME}"