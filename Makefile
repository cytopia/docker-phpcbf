ifneq (,)
.error This Makefile requires GNU Make.
endif

.PHONY: build rebuild lint test _test-phpcbf-version _test-php-version _test-run _get-php-version tag pull login push enter

CURRENT_DIR = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

DIR = .
FILE = Dockerfile
IMAGE = cytopia/phpcbf
TAG = latest

PHP   = latest
PHPCBF = latest

build:
ifeq ($(PHP),latest)
	docker build --build-arg PHP=7-cli-alpine --build-arg PHPCBF=$(PHPCBF) -t $(IMAGE) -f $(DIR)/$(FILE) $(DIR)
else
	docker build --build-arg PHP=$(PHP)-cli-alpine --build-arg PHPCBF=$(PHPCBF) -t $(IMAGE) -f $(DIR)/$(FILE) $(DIR)
endif

rebuild: pull
ifeq ($(PHP),latest)
	docker build --no-cache --build-arg PHP=7-cli-alpine --build-arg PHPCBF=$(PHPCBF) -t $(IMAGE) -f $(DIR)/$(FILE) $(DIR)
else
	docker build --no-cache --build-arg PHP=$(PHP)-cli-alpine --build-arg PHPCBF=$(PHPCBF) -t $(IMAGE) -f $(DIR)/$(FILE) $(DIR)
endif

lint:
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint file-cr --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint file-crlf --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint file-trailing-single-newline --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint file-trailing-space --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint file-utf8 --text --ignore '.git/,.github/,tests/' --path .
	@docker run --rm -v $(CURRENT_DIR):/data cytopia/file-lint file-utf8-bom --text --ignore '.git/,.github/,tests/' --path .

test:
	@$(MAKE) --no-print-directory _test-phpcbf-version
	@$(MAKE) --no-print-directory _test-php-version
	@$(MAKE) --no-print-directory _test-run

_test-phpcbf-version:
	@echo "------------------------------------------------------------"
	@echo "- Testing correct phpcbf version"
	@echo "------------------------------------------------------------"
	@if [ "$(PHPCBF)" = "latest" ]; then \
		echo "Fetching latest version from GitHub"; \
		LATEST="$$( \
		curl -L -sS https://github.com/squizlabs/PHP_CodeSniffer/releases \
			| tac | tac \
			| grep -Eo '/[.0-9]+?\.[.0-9]+/' \
			| grep -Eo '[.0-9]+' \
			| sort -V \
			| tail -1 \
		)"; \
		echo "Testing for latest: $${LATEST}"; \
		if ! docker run --rm $(IMAGE) --version | grep -E "^PHP_CodeSniffer[[:space:]]+version[[:space:]]+v?$${LATEST}"; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	else \
		echo "Testing for tag: $(PHPCBF).x.x"; \
		if ! docker run --rm $(IMAGE) --version | grep -E "^PHP_CodeSniffer[[:space:]]+version[[:space:]]+v?$(PHPCBF)\.[.0-9]+"; then \
			echo "Failed"; \
			exit 1; \
		fi; \
	fi; \
	echo "Success"; \

_test-php-version: _get-php-version
	@echo "------------------------------------------------------------"
	@echo "- Testing correct PHP version"
	@echo "------------------------------------------------------------"
	@echo "Testing for tag: $(CURRENT_PHP_VERSION)"
	@if ! docker run --rm --entrypoint=php $(IMAGE) --version | head -1 | grep -E "^PHP[[:space:]]+$(CURRENT_PHP_VERSION)([.0-9]+)?"; then \
		echo "Failed"; \
		exit 1; \
	fi; \
	echo "Success";

_test-run:
	@echo "------------------------------------------------------------"
	@echo "- Testing phpcbf (success)"
	@echo "------------------------------------------------------------"
	@if ! docker run --rm -v $(CURRENT_DIR)/tests/ok:/data $(IMAGE) .; then \
		echo "Failed"; \
		exit 1; \
	fi; \
	echo "Success";
	@echo "------------------------------------------------------------"
	@echo "- Testing phpcbf (failure)"
	@echo "------------------------------------------------------------"
	@if docker run --rm -v $(CURRENT_DIR)/tests/fail:/data --entrypoint=/bin/sh $(IMAGE) -c 'cat fail.php | phpcbf -'; then \
		echo "Failed"; \
		exit 1; \
	fi; \
	echo "Success";

tag:
	docker tag $(IMAGE) $(IMAGE):$(TAG)

pull:
	@echo "Pull base image"
	@grep -E '^\s*FROM' Dockerfile \
		| sed -e 's/^FROM//g' -e 's/[[:space:]]*as[[:space:]]*.*$$//g' \
		| head -1 \
		| xargs -n1 docker pull;
	@echo "Pull target image"
	docker pull php:$(PHP)-cli-alpine

login:
	yes | docker login --username $(USER) --password $(PASS)

push:
	@$(MAKE) tag TAG=$(TAG)
	docker push $(IMAGE):$(TAG)

enter:
	docker run --rm --name $(subst /,-,$(IMAGE)) -it --entrypoint=/bin/sh $(ARG) $(IMAGE):$(TAG)

# Fetch latest available PHP version for cli-alpine
_get-php-version:
	$(eval CURRENT_PHP_VERSION = $(shell \
		if [ "$(PHP)" = "latest" ]; then \
			curl -L -sS https://hub.docker.com/api/content/v1/products/images/php \
				| tac | tac \
				| grep -Eo '`[.0-9]+-cli-alpine' \
				| grep -Eo '[.0-9]+' \
				| sort -u \
				| tail -1; \
		else \
			echo $(PHP); \
		fi; \
	))
