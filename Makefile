SHELL = bash

GIT_COMMIT?=$(shell git rev-parse --short HEAD)

################
# CI Variables #
################
CI_DEV_DOCKER_NAMESPACE?=hashicorpdev
CI_DEV_DOCKER_IMAGE_NAME?=consul-ecs
CI_DEV_DOCKER_WORKDIR?=.
CONSUL_K8S_IMAGE_VERSION?=latest
################

build-image:
	GOOS=linux GOARCH=amd64 go build -o output/ ./...
	docker build -t lkysow/consul-ecs .


# In CircleCI, the linux binary will be attached from a previous step at pkg/bin/linux_amd64/. This make target
# should only run in CI and not locally.
ci.dev-docker:
	@echo "Pulling consul-ecs container image - $(CONSUL_K8S_IMAGE_VERSION)"
	@docker pull hashicorp/$(CI_DEV_DOCKER_IMAGE_NAME):$(CONSUL_K8S_IMAGE_VERSION) >/dev/null
	@echo "Building consul-k8s Development container - $(CI_DEV_DOCKER_IMAGE_NAME)"
	@docker build -t '$(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):$(GIT_COMMIT)' \
	--build-arg CONSUL_K8S_IMAGE_VERSION=$(CONSUL_K8S_IMAGE_VERSION) \
	--label COMMIT_SHA=$(CIRCLE_SHA1) \
	--label PULL_REQUEST=$(CIRCLE_PULL_REQUEST) \
	--label CIRCLE_BUILD_URL=$(CIRCLE_BUILD_URL) \
	$(CI_DEV_DOCKER_WORKDIR) -f $(CURDIR)/build-support/docker/Dev.dockerfile
	@echo $(DOCKER_PASS) | docker login -u="$(DOCKER_USER)" --password-stdin
	@echo "Pushing dev image to: https://cloud.docker.com/u/$(CI_DEV_DOCKER_NAMESPACE)/repository/docker/$(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME)"
	@docker push $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):$(GIT_COMMIT)
ifeq ($(CIRCLE_BRANCH), master)
	@docker tag $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):$(GIT_COMMIT) $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):latest
	@docker push $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):latest
endif
ifeq ($(CIRCLE_BRANCH), crd-controller-base)
	@docker tag $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):$(GIT_COMMIT) $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):crd-controller-base-latest
	@docker push $(CI_DEV_DOCKER_NAMESPACE)/$(CI_DEV_DOCKER_IMAGE_NAME):crd-controller-base-latest
endif

.PHONY: build-image ci.dev-docker