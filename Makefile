# KDT Makefile — developer tooling only (lint / test / package).
# There is NO 'install' target: the model instance runs `kcadmin` straight from
# the extracted tarball, and `kcadmin install` bakes the runtime (units, boot
# script, config, build, SELinux). `make` is not needed on the model instance.
VERSION := $(shell cat VERSION)
SH_FILES := scripts/kcadmin $(wildcard lib/*.sh) $(wildcard scripts/subcommands/*.sh) $(wildcard boot/*.sh)

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
	@tar czf kcadmin-$(VERSION).tar.gz \
		--transform 's,^,kcadmin-$(VERSION)/,' \
		scripts lib boot systemd selinux templates VERSION README.md
	@sha256sum kcadmin-$(VERSION).tar.gz > kcadmin-$(VERSION).tar.gz.sha256
	@echo "built kcadmin-$(VERSION).tar.gz"

.PHONY: clean
clean: ## Remove build artifacts
	rm -f kcadmin-*.tar.gz kcadmin-*.tar.gz.sha256
