.PHONY: all check fix lint-markdown lint-yaml check-links validate-manifest tools

all: check

tools:
	@echo "Installing python tools..."
	@if command -v uv >/dev/null 2>&1; then \
		echo "Using uv to install yamllint..."; \
		uv venv .venv; \
		uv pip install yamllint; \
	else \
		echo "Using pip to install yamllint..."; \
		python3 -m venv .venv; \
		.venv/bin/pip install yamllint; \
	fi
	@echo "Installing node tools..."
	@npm install
	@echo "Checking for yq..."
	@if ! command -v yq >/dev/null 2>&1 && [ ! -f "bin/yq" ]; then \
		echo "yq not found. Downloading to bin/yq..."; \
		mkdir -p bin; \
		curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_$$(uname | tr '[:upper:]' '[:lower:]')_$$(uname -m | sed 's/x86_64/amd64/g' | sed 's/aarch64/arm64/g') -o bin/yq; \
		chmod +x bin/yq; \
	fi

check: lint-markdown lint-yaml check-links validate-manifest
	@echo "All checks passed successfully!"

fix:
	@echo "Fixing common markdown formatting issues..."
	@npx markdownlint-cli2 --fix "**/*.md" "#node_modules" "#.venv"

lint-markdown:
	@echo "Running markdown lint..."
	@npx markdownlint-cli2 "**/*.md" "#node_modules" "#.venv"

lint-yaml:
	@echo "Running yaml lint..."
	@if [ -x ".venv/bin/yamllint" ]; then \
		.venv/bin/yamllint .; \
	else \
		echo "yamllint not found in .venv! Please run 'make tools'."; \
		exit 1; \
	fi

check-links:
	@echo "Running link checker..."
	@find . -name "*.md" -not -path "./node_modules/*" -not -path "./.venv/*" -print0 | xargs -0 -n1 npx markdown-link-check -c .mlc_config.json

validate-manifest:
	@echo "Validating apm.yml..."
	@if [ -x "bin/yq" ]; then \
		PATH="$$(pwd)/bin:$$PATH" ./scripts/validate-manifest.sh; \
	else \
		./scripts/validate-manifest.sh; \
	fi
