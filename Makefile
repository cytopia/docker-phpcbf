ifneq (,)
.error This Makefile requires GNU Make.
endif

# Ensure additional Makefiles are present
MAKEFILES = Makefile.docker Makefile.lint
$(MAKEFILES): URL=https://raw.githubusercontent.com/devilbox/makefiles/master/$(@)
$(MAKEFILES):
	@if ! (curl --fail -sS -o $(@) $(URL) || wget -O $(@) $(URL)); then \
		echo "Error, curl or wget required."; \
		echo "Exiting."; \
		false; \
	fi
include $(MAKEFILES)

# Set default Target
.DEFAULT_GOAL := help

DOCKER_PULL_VARIABLES = PHP_IMG_TAG=$(PHP_IMG_TAG)


# -------------------------------------------------------------------------------------------------
# Default configuration
# -------------------------------------------------------------------------------------------------
# Own vars
TAG = latest

# Makefile.docker overwrites
NAME       = phpcbf
VERSION    = latest
IMAGE      = cytopia/phpcbf
FLAVOUR    = latest
FILE       = Dockerfile.${FLAVOUR}
DIR        = Dockerfiles

# Extract PHP- and PCS- version from VERSION string
ifeq ($(strip $(VERSION)),latest)
	PHP_VERSION = latest
	PBF_VERSION = latest
	PHP_IMG_TAG = "cli-alpine"
else
	PHP_VERSION = $(subst PHP-,,$(shell echo "$(VERSION)" | grep -Eo 'PHP-([.0-9]+|latest)'))
	PBF_VERSION = $(subst PBF-,,$(shell echo "$(VERSION)" | grep -Eo 'PBF-([.0-9]+|latest)'))
	PHP_IMG_TAG = $(PHP_VERSION)-cli-alpine
endif

# Extract Image version
ifeq ($(strip $(PHP_VERSION)),latest)
	PHP_IMG_TAG = "cli-alpine"
endif

# Building from master branch: Tag == 'latest'
ifeq ($(strip $(TAG)),latest)
	ifeq ($(strip $(VERSION)),latest)
		DOCKER_TAG = $(FLAVOUR)
	else
		ifeq ($(strip $(FLAVOUR)),latest)
			ifeq ($(strip $(PHP_VERSION)),latest)
				DOCKER_TAG = $(PBF_VERSION)
else
				DOCKER_TAG = $(PBF_VERSION)-php$(PHP_VERSION)
			endif
		else
			ifeq ($(strip $(PHP_VERSION)),latest)
				DOCKER_TAG = $(FLAVOUR)-$(PBF_VERSION)
			else
				DOCKER_TAG = $(FLAVOUR)-$(PBF_VERSION)-php$(PHP_VERSION)
			endif
		endif
	endif
# Building from any other branch or tag: Tag == '<REF>'
else
	ifeq ($(strip $(VERSION)),latest)
		ifeq ($(strip $(FLAVOUR)),latest)
			DOCKER_TAG = latest-$(TAG)
		else
			DOCKER_TAG = $(FLAVOUR)-latest-$(TAG)
		endif
	else
		ifeq ($(strip $(FLAVOUR)),latest)
			ifeq ($(strip $(PHP_VERSION)),latest)
				DOCKER_TAG = $(PBF_VERSION)-$(TAG)
			else
				DOCKER_TAG = $(PBF_VERSION)-php$(PHP_VERSION)-$(TAG)
			endif
		else
			ifeq ($(strip $(PHP_VERSION)),latest)
				DOCKER_TAG = $(FLAVOUR)-$(PBF_VERSION)-$(TAG)
			else
				DOCKER_TAG = $(FLAVOUR)-$(PBF_VERSION)-php$(PHP_VERSION)-$(TAG)
			endif
		endif
	endif
endif

# Makefile.lint overwrites
FL_IGNORES  = .git/,.github/,tests/
SC_IGNORES  = .git/,.github/,tests/
JL_IGNORES  = .git/,.github/,./tests/


# -------------------------------------------------------------------------------------------------
#  Default Target
# -------------------------------------------------------------------------------------------------
.PHONY: help
help:
	@echo "lint                                     Lint project files and repository"
	@echo
	@echo "build [ARCH=...] [TAG=...]               Build Docker image"
	@echo "rebuild [ARCH=...] [TAG=...]             Build Docker image without cache"
	@echo "push [ARCH=...] [TAG=...]                Push Docker image to Docker hub"
	@echo
	@echo "manifest-create [ARCHES=...] [TAG=...]   Create multi-arch manifest"
	@echo "manifest-push [TAG=...]                  Push multi-arch manifest"
	@echo
	@echo "test [ARCH=...]                          Test built Docker image"
	@echo


# -------------------------------------------------------------------------------------------------
#  Docker Targets
# -------------------------------------------------------------------------------------------------
.PHONY: build
build: ARGS+=--build-arg PBF_VERSION=$(PBF_VERSION)
build: ARGS+=--build-arg PHP_IMG_TAG=$(PHP_IMG_TAG)
build: docker-arch-build

.PHONY: rebuild
rebuild: ARGS+=--build-arg PBF_VERSION=$(PBF_VERSION)
rebuild: ARGS+=--build-arg PHP_IMG_TAG=$(PHP_IMG_TAG)
rebuild: docker-arch-rebuild

.PHONY: push
push: docker-arch-push


# -------------------------------------------------------------------------------------------------
#  Manifest Targets
# -------------------------------------------------------------------------------------------------
.PHONY: manifest-create
manifest-create: docker-manifest-create

.PHONY: manifest-push
manifest-push: docker-manifest-push


# -------------------------------------------------------------------------------------------------
#  Test Targets
# -------------------------------------------------------------------------------------------------
.PHONY: test
test:
test: _test-phpcbf-version
test: _test-php-version
test: _test-run

.PHONY: _test-phpcbf-version
_test-phpcbf-version:
	@echo "------------------------------------------------------------"
	@echo "- Testing correct phpcbf version"
	@echo "------------------------------------------------------------"
	@if [ "$(PBF_VERSION)" = "latest" ]; then \
		echo "Fetching latest version from GitHub"; \
		LATEST="$$( \
		curl -L -sS https://github.com/squizlabs/PHP_CodeSniffer/releases \
			| tac | tac \
			| grep -Eo '/[.0-9]+?\.[.0-9]+"' \
			| grep -Eo '[.0-9]+' \
			| sort -V \
			| tail -1 \
		)"; \
		echo "Testing for latest: $${LATEST}"; \
		if ! docker run --rm --platform $(ARCH) $(IMAGE):$(DOCKER_TAG) --version | grep -E "^PHP_CodeSniffer[[:space:]]+version[[:space:]]+v?$${LATEST}"; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	else \
		echo "Testing for tag: $(PBF_VERSION).x.x"; \
		if ! docker run --rm --platform $(ARCH) $(IMAGE):$(DOCKER_TAG) --version | grep -E "^PHP_CodeSniffer[[:space:]]+version[[:space:]]+v?$(PBF_VERSION)\.[.0-9]+"; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	fi; \
	echo "Success"; \

.PHONY: _test-php-version
_test-php-version: _get-php-version
	@echo "------------------------------------------------------------"
	@echo "- Testing correct PHP version"
	@echo "------------------------------------------------------------"
	@echo "Testing for tag: $(CURRENT_PHP_VERSION)"
	@if ! docker run --rm --platform $(ARCH) --entrypoint=php $(IMAGE):$(DOCKER_TAG) --version | head -1 | grep -E "^PHP[[:space:]]+$(CURRENT_PHP_VERSION)([.0-9]+)?"; then \
		echo "Failed"; \
		exit 1; \
	fi; \
	echo "Success";

.PHONY: _test-run
_test-run:
	@echo "------------------------------------------------------------"
	@echo "- Testing phpcbf (success)"
	@echo "------------------------------------------------------------"
	@if ! docker run --rm --platform $(ARCH) -v $(CURRENT_DIR)/tests/ok:/data $(IMAGE):$(DOCKER_TAG) .; then \
		echo "Failed"; \
		exit 1; \
	fi; \
	echo "Success";
	@echo "------------------------------------------------------------"
	@echo "- Testing phpcbf (failure)"
	@echo "------------------------------------------------------------"
	@if docker run --rm --platform $(ARCH) -v $(CURRENT_DIR)/tests/fail:/data --entrypoint=/bin/sh $(IMAGE):$(DOCKER_TAG) -c 'cat fail.php | phpcbf -'; then \
		echo "Failed"; \
		exit 1; \
	fi; \
	echo "Success";

# Fetch latest available PHP version for cli-alpine
.PHONY: _get-php-version
_get-php-version:
	$(eval CURRENT_PHP_VERSION = $(shell \
		if [ "$(PHP_VERSION)" = "latest" ]; then \
			curl -L -sS https://hub.docker.com/api/content/v1/products/images/php \
				| tac | tac \
				| grep -Eo '`[.0-9]+-cli-alpine' \
				| grep -Eo '[.0-9]+' \
				| sort -u \
				| tail -1; \
		else \
			echo $(PHP_VERSION); \
		fi; \
	))
