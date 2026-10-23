.PHONY: lint test fmt fmt-check check check-all install clean help dry-run conform-bash conform build gotest acceptance update-e2e bootstrap-e2e install-e2e retire-check

# ── EasyWork Makefile ──────────────────────────────────────────

SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
SHFMT     := $(shell command -v shfmt 2>/dev/null)
BATS      := $(shell command -v bats 2>/dev/null)

.DEFAULT_GOAL := help

lint: ## Run ShellCheck static analysis
	@echo "==> Running ShellCheck..."
ifdef SHELLCHECK
	$(SHELLCHECK) bin/easywork lib/*.sh tests/helpers/mocks.bash
	@echo "✅ ShellCheck passed"
else
	$(error "shellcheck not found. Install: brew install shellcheck or apt install shellcheck")
endif

test: ## Run BATS tests (parallel across files; JOBS=N to override)
	@echo "==> Running tests..."
ifdef BATS
	BATS="$(BATS)" tests/run.sh && echo "✅ Tests passed"
else
	$(error "bats not found. Install: brew install bats-core or see https://github.com/bats-core/bats-core")
endif

fmt: ## Format shell scripts with shfmt
	@echo "==> Formatting..."
ifdef SHFMT
	$(SHFMT) -w -i 4 -bn -ci -sr bin/easywork lib/*.sh
	@echo "✅ Formatting done"
else
	$(error "shfmt not found. Install: brew install shfmt or go install mvdan.cc/sh/v3/cmd/shfmt@latest")
endif

fmt-check: ## Check formatting without modifying files
	@echo "==> Checking formatting..."
ifdef SHFMT
	$(SHFMT) -d -i 4 -bn -ci -sr bin/easywork lib/*.sh
	@echo "✅ Formatting check done"
else
	$(error "shfmt not found")
endif

check: lint fmt-check test ## Run all checks (lint + format-check + test)
	@echo "✅ All checks passed"

build: ## Build the Go binary into .build/ew
	mkdir -p .build
	go build -o .build/ew ./cmd/ew

gotest: ## Run Go unit tests
	go test ./...

check-all: lint fmt-check test gotest conform-bash install-e2e ## Full check: shell + Go + conformance + 安装链路
	@echo "✅ All checks passed (with Go conformance)"

acceptance: ## Run the full migration acceptance suite (M0–M7)
	bash scripts/acceptance.sh

update-e2e: ## End-to-end self-upgrade test via a local mirror
	bash scripts/update-e2e.sh

bootstrap-e2e: ## End-to-end install test for bootstrap.sh (local mirror, no network)
	bash scripts/bootstrap-e2e.sh

install-e2e: bootstrap-e2e update-e2e ## Install/upgrade chain e2e (bootstrap + update)

retire-check: ## Check preconditions for retiring the Bash engine
	bash scripts/retire-check.sh

dry-run: build ## Preview what easywork install would do (Go engine)
	./.build/ew install --dry-run --yes

conform-bash: ## Run black-box conformance against the Bash implementation
	bash tests/conformance/run.sh bash

conform: ## Run black-box conformance against Bash and Go implementations
	bash tests/conformance/run.sh all

install: build ## Install Go CLI (Unix: /usr/local/bin; Windows: ~/.local/bin + PATH/PATHEXT)
	@bash scripts/install.sh

clean: ## Remove temporary files
	rm -f *.tmp *.bak
	rm -f lib/*.tmp lib/*.bak

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
