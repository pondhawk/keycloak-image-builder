# KDT Makefile — install / check / test / package
PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
LIBDIR  = $(PREFIX)/lib/kcadmin
SYSTEMD_DIR ?= /usr/lib/systemd/system

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

.PHONY: install
install: ## Install kcadmin onto this host (golden instance)
	install -d $(DESTDIR)$(LIBDIR)/lib $(DESTDIR)$(LIBDIR)/subcommands \
		$(DESTDIR)$(LIBDIR)/templates $(DESTDIR)$(LIBDIR)/boot
	install -m 0644 lib/*.sh $(DESTDIR)$(LIBDIR)/lib/
	install -m 0644 scripts/subcommands/*.sh $(DESTDIR)$(LIBDIR)/subcommands/
	install -m 0755 boot/*.sh $(DESTDIR)$(LIBDIR)/boot/
	install -d $(DESTDIR)$(LIBDIR)/selinux
	install -m 0644 selinux/* $(DESTDIR)$(LIBDIR)/selinux/
	install -m 0644 templates/* $(DESTDIR)$(LIBDIR)/templates/
	install -m 0644 VERSION $(DESTDIR)$(LIBDIR)/VERSION
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 scripts/kcadmin $(DESTDIR)$(BINDIR)/kcadmin
	install -d $(DESTDIR)$(SYSTEMD_DIR)
	install -m 0644 systemd/*.service $(DESTDIR)$(SYSTEMD_DIR)/

.PHONY: package
package: ## Build the release tarball
	@tar czf kcadmin-$(VERSION).tar.gz \
		--transform 's,^,kcadmin-$(VERSION)/,' \
		scripts lib boot systemd selinux templates Makefile VERSION README.md
	@sha256sum kcadmin-$(VERSION).tar.gz > kcadmin-$(VERSION).tar.gz.sha256
	@echo "built kcadmin-$(VERSION).tar.gz"

.PHONY: clean
clean: ## Remove build artifacts
	rm -f kcadmin-*.tar.gz kcadmin-*.tar.gz.sha256
