.PHONY: lint test fmt fmt-check check install clean help dry-run

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

dry-run: ## Preview what easywork install would do
	./bin/easywork install --dry-run --yes

install: ## Install CLI to /usr/local/bin (requires sudo)
	@echo "==> Installing easywork..."
	@if [ -w /usr/local/bin ]; then \
		cp bin/easywork /usr/local/bin/easywork && chmod +x /usr/local/bin/easywork && ln -sf easywork /usr/local/bin/ew; \
	elif [ -d "$$HOME/.local/bin" ] || mkdir -p "$$HOME/.local/bin" 2>/dev/null; then \
		cp bin/easywork "$$HOME/.local/bin/easywork" && chmod +x "$$HOME/.local/bin/easywork" && ln -sf easywork "$$HOME/.local/bin/ew"; \
	else \
		echo "Cannot install. Please copy bin/easywork to a directory in your PATH manually."; \
		exit 1; \
	fi
	@echo "✅ easywork installed (short alias: ew). Run: ew help"

clean: ## Remove temporary files
	rm -f *.tmp *.bak
	rm -f lib/*.tmp lib/*.bak

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
