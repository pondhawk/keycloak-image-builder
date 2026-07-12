# KIB Makefile — developer tooling only (lint / test / package).
# `make` is dev-only (lint / test / package). On the model instance you run
# `sudo ./bootstrap.sh` to put kcimage on PATH; `kcimage install` then bakes the
# Keycloak runtime. `make` is not needed on the model instance.
VERSION := $(shell cat VERSION)
SH_FILES := scripts/kcimage bootstrap.sh $(wildcard lib/*.sh) $(wildcard scripts/subcommands/*.sh) $(wildcard boot/*.sh)

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n", $$1, $$2}'

.PHONY: check
check: ## ShellCheck + shfmt (no changes)
	shellcheck -x -P SCRIPTDIR $(SH_FILES)
	shfmt -i 2 -ci -sr -d $(SH_FILES)

.PHONY: fmt
fmt: ## Format scripts in place
	shfmt -i 2 -ci -sr -w $(SH_FILES)

.PHONY: test
test: ## Run Bats tests
	bats tests/bats

.PHONY: package
package: ## Build the release tarball
	@tar czf kcimage-$(VERSION).tar.gz \
		--transform 's,^,kcimage-$(VERSION)/,' \
		scripts lib boot systemd selinux templates bootstrap.sh VERSION README.md
	@sha256sum kcimage-$(VERSION).tar.gz > kcimage-$(VERSION).tar.gz.sha256
	@echo "built kcimage-$(VERSION).tar.gz"

.PHONY: clean
clean: ## Remove build artifacts
	rm -f kcimage-*.tar.gz kcimage-*.tar.gz.sha256
