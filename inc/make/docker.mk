# Enable buildkit for docker
export DOCKER_BUILDKIT=1

DOCKER_SERVER:=registry.nmlv.nml.com
DOCKER_FILE?=Dockerfile
DOCKER_PATH?=$(ROOT_PATH)
DOCKER_IMAGE?=$(PROJECT)
DOCKER_BUILD_ARGS ?= --build-arg BASE_IMAGE_TAG=$(CONTROLLER_TAG) --build-arg VAULT_ENVIRONMENT=$(VAULT_ENVIRONMENT)

## Docker tasks
.PHONY: docker/start
docker/login: ## Login to container registry
	docker login $(DOCKER_SERVER)

.PHONY: docker/tag
docker/tag: ## Tag container image
	docker tag $(DOCKER_IMAGE):local $(DOCKER_SERVER)/$(DOCKER_IMAGE):$(GIT_COMMIT)
	docker tag $(DOCKER_IMAGE):local $(DOCKER_SERVER)/$(DOCKER_IMAGE):${VERSION}
	docker tag $(DOCKER_IMAGE):local $(DOCKER_SERVER)/$(DOCKER_IMAGE):latest

.PHONY: docker/push
docker/push: docker/tag  ## Push tagged images to registry
	@echo "Pushing container image to registry: latest ${VERSION} $(GIT_COMMIT)"
	docker push $(DOCKER_SERVER)/$(DOCKER_IMAGE):$(GIT_COMMIT)
	docker push $(DOCKER_SERVER)/$(DOCKER_IMAGE):${VERSION}
	docker push $(DOCKER_SERVER)/$(DOCKER_IMAGE):latest

.PHONY: docker/run
docker/run: ## Run a local container image for the app
	docker run -t --rm -i --name=$(PROJECT) $(DOCKER_IMAGE):local

.PHONY: docker/scan
docker/scan: ## Run a docker snyk security scan
	docker scan $(DOCKER_SERVER)/$(DOCKER_IMAGE):latest

.PHONY: docker/shell
docker/shell: ## Run a local container image for the app
	docker run -t --rm -i --name=$(PROJECT) $(DOCKER_IMAGE):local /bin/bash

.PHONY: docker/build
docker/build: ## Build docker image
ifeq ($(IS_CI),"TRUE")
	@echo "IS_CI: TRUE"
else
	docker build $(DOCKER_BUILD_ARGS) -t $(DOCKER_IMAGE):local -f $(DOCKER_FILE) $(DOCKER_PATH)
endif