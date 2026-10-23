.PHONY: lint test fmt fmt-check check check-all install clean help dry-run conform build gotest acceptance update-e2e bootstrap-e2e install-e2e retire-check

# ── EasyWork Makefile ──────────────────────────────────────────
#
# 引擎：Go（`cmd/ew` + `internal/*`），Bash 引擎已于 0.3.0 退役
# （存档 tag: legacy-bash-0.3.0）。仓库内剩余的 shell 脚本只有
# 引导/安装/验收/CI 辅助，仍受 ShellCheck + shfmt 约束。

SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
SHFMT      := $(shell command -v shfmt 2>/dev/null)
BATS       := $(shell command -v bats 2>/dev/null)

SHELL_FILES := bootstrap.sh scripts/*.sh

.DEFAULT_GOAL := help

lint: ## Run ShellCheck（bootstrap.sh + scripts/）
	@echo "==> Running ShellCheck..."
ifdef SHELLCHECK
	$(SHELLCHECK) $(SHELL_FILES)
	@echo "✅ ShellCheck passed"
else
	$(error "shellcheck not found. Install: brew install shellcheck or apt install shellcheck")
endif

test: ## Run black-box conformance against the Go binary
	@echo "==> Running conformance..."
ifdef BATS
	BATS="$(BATS)" tests/conformance/run.sh go && echo "✅ Conformance passed"
else
	$(error "bats not found. Install: brew install bats-core or see https://github.com/bats-core/bats-core")
endif

fmt: ## Format shell scripts with shfmt
	@echo "==> Formatting..."
ifdef SHFMT
	$(SHFMT) -w -i 4 -bn -ci -sr $(SHELL_FILES)
	@echo "✅ Formatting done"
else
	$(error "shfmt not found. Install: brew install shfmt or go install mvdan.cc/sh/v3/cmd/shfmt@latest")
endif

fmt-check: ## Check formatting without modifying files
	@echo "==> Checking formatting..."
ifdef SHFMT
	$(SHFMT) -d -i 4 -bn -ci -sr $(SHELL_FILES)
	@echo "✅ Formatting check done"
else
	$(error "shfmt not found")
endif

check: lint fmt-check gotest test install-e2e ## Run all checks (shell + Go + conformance + 安装链路)
	@echo "✅ All checks passed"

check-all: check ## 兼容旧习惯：check-all 等同 check

build: ## Build the Go binary into .build/ew
	mkdir -p .build
	go build -o .build/ew ./cmd/ew

gotest: ## Run Go unit tests
	go test ./...

acceptance: ## Run the full acceptance suite (静态检查 + 测试 + 安装链路 + 交叉编译)
	bash scripts/acceptance.sh

update-e2e: ## End-to-end self-upgrade test via a local mirror
	bash scripts/update-e2e.sh

bootstrap-e2e: ## End-to-end install test for bootstrap.sh (local mirror, no network)
	bash scripts/bootstrap-e2e.sh

install-e2e: bootstrap-e2e update-e2e ## Install/upgrade chain e2e (bootstrap + update)

retire-check: ## Verify the Bash engine is fully retired (no leftovers)
	bash scripts/retire-check.sh

dry-run: build ## Preview what easywork install would do
	./.build/ew install --dry-run --yes

conform: ## Run black-box conformance（Go）
	bash tests/conformance/run.sh go

install: build ## Install Go CLI (Unix: /usr/local/bin; Windows: ~/.local/bin + PATH/PATHEXT)
	@bash scripts/install.sh

clean: ## Remove temporary files
	rm -f *.tmp *.bak
	rm -rf .build

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
