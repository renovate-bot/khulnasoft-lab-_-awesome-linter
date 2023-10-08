# Inspired by https://github.com/jessfraz/dotfiles

.PHONY: all
all: info test ## Run all targets.

.PHONY: test
test: info clean inspec kcov prepare-test-reports ## Run tests

# if this session isn't interactive, then we don't want to allocate a
# TTY, which would fail, but if it is interactive, we do want to attach
# so that the user can send e.g. ^C through.
INTERACTIVE := $(shell [ -t 0 ] && echo 1 || echo 0)
ifeq ($(INTERACTIVE), 1)
	DOCKER_FLAGS += -t
endif

.PHONY: info
info: ## Gather information about the runtime environment
	echo "whoami: $$(whoami)"; \
	echo "pwd: $$(pwd)"; \
	echo "ls -ahl: $$(ls -ahl)"; \
	docker images; \
	docker ps

.PHONY: kcov
kcov: ## Run kcov
	docker run --rm $(DOCKER_FLAGS) \
		--user "$$(id -u)":"$$(id -g)" \
		-v "$(CURDIR)":/workspace \
		-w="/workspace" \
		kcov/kcov \
		kcov \
		--bash-parse-files-in-dir=/workspace \
		--clean \
		--exclude-pattern=.coverage,.git \
		--include-pattern=.sh \
		/workspace/test/.coverage \
		/workspace/test/runTests.sh

COBERTURA_REPORTS_DESTINATION_DIRECTORY := "$(CURDIR)/test/reports/cobertura"

.PHONY: prepare-test-reports
prepare-test-reports: ## Prepare the test reports for consumption
	mkdir -p $(COBERTURA_REPORTS_DESTINATION_DIRECTORY); \
	COBERTURA_REPORTS="$$(find "$$(pwd)" -name 'cobertura.xml')"; \
	for COBERTURA_REPORT_FILE_PATH in $$COBERTURA_REPORTS ; do \
		COBERTURA_REPORT_DIRECTORY_PATH="$$(dirname "$$COBERTURA_REPORT_FILE_PATH")"; \
		COBERTURA_REPORT_DIRECTORY_NAME="$$(basename "$$COBERTURA_REPORT_DIRECTORY_PATH")"; \
		COBERTURA_REPORT_DIRECTORY_NAME_NO_SUFFIX="$${COBERTURA_REPORT_DIRECTORY_NAME%.*}"; \
		mkdir -p "$(COBERTURA_REPORTS_DESTINATION_DIRECTORY)"/"$$COBERTURA_REPORT_DIRECTORY_NAME_NO_SUFFIX"; \
		cp "$$COBERTURA_REPORT_FILE_PATH" "$(COBERTURA_REPORTS_DESTINATION_DIRECTORY)"/"$$COBERTURA_REPORT_DIRECTORY_NAME_NO_SUFFIX"/cobertura.xml; \
	done

.PHONY: clean
clean: ## Clean the workspace
	rm -rf $(CURDIR)/test/.coverage; \
	rm -rf $(CURDIR)/test/reports

.PHONY: help
help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: inspec-check
inspec-check: ## Validate inspec profiles
	docker run $(DOCKER_FLAGS) \
		--rm \
		-v "$(CURDIR)":/workspace \
		-w="/workspace" \
		chef/inspec check \
		--chef-license=accept \
		test/inspec/awesome-linter

AWESOME_LINTER_TEST_CONTAINER_NAME := "awesome-linter-test"
AWESOME_LINTER_TEST_CONTINER_URL := ''
DOCKERFILE := ''
IMAGE := ''
ifeq ($(IMAGE),slim)
	AWESOME_LINTER_TEST_CONTINER_URL := "ghcr.io/khulnasoft-lab/awesome-linter:slim"
	IMAGE := "slim"
else
	AWESOME_LINTER_TEST_CONTINER_URL := "ghcr.io/khulnasoft-lab/awesome-linter:standard"
	IMAGE := "standard"
endif

.PHONY: inspec
inspec: inspec-check ## Run InSpec tests
	LOCAL_IMAGE="$$(docker images $(AWESOME_LINTER_TEST_CONTINER_URL) |grep 'ghcr.io/khulnasoft-lab/awesome-linter')"; \
	if [ "$$?" -ne 0 ]; then docker build -t $(AWESOME_LINTER_TEST_CONTINER_URL) -f Dockerfile .; fi && \
	DOCKER_CONTAINER_STATE="$$(docker inspect --format "{{.State.Running}}" "$(AWESOME_LINTER_TEST_CONTAINER_NAME)" 2>/dev/null || echo "")"; \
	if [ "$$DOCKER_CONTAINER_STATE" = "true" ]; then docker kill "$(AWESOME_LINTER_TEST_CONTAINER_NAME)"; fi && \
	docker tag $(AWESOME_LINTER_TEST_CONTINER_URL) $(AWESOME_LINTER_TEST_CONTAINER_NAME) && \
	AWESOME_LINTER_TEST_CONTAINER_ID="$$(docker run -d --name "$(AWESOME_LINTER_TEST_CONTAINER_NAME)" --rm -it --entrypoint /bin/ash "$(AWESOME_LINTER_TEST_CONTAINER_NAME)" -c "while true; do sleep 1; done")" \
	&& docker run $(DOCKER_FLAGS) \
		--rm \
		-v "$(CURDIR)":/workspace \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-e IMAGE=$(IMAGE) \
		-w="/workspace" \
		chef/inspec exec test/inspec/awesome-linter\
		--chef-license=accept \
		--diagnose \
		--log-level=debug \
		-t "docker://$${AWESOME_LINTER_TEST_CONTAINER_ID}" \
	&& docker ps \
	&& docker kill "$(AWESOME_LINTER_TEST_CONTAINER_NAME)"

.phony: docker
docker:
	@if [ -z "${GITHUB_TOKEN}" ]; then echo "GITHUB_TOKEN environment variable not set. Please set your GitHub Personal Access Token."; exit 1; fi
	DOCKER_BUILDKIT=1 docker buildx build --load \
		--build-arg BUILD_DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ') \
		--build-arg BUILD_REVISION=$(shell git rev-parse --short HEAD) \
		--build-arg BUILD_VERSION=$(shell git rev-parse --short HEAD) \
		--secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
		-t ghcr.io/khulnasoft-lab/awesome-linter .