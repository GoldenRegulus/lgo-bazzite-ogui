.DEFAULT_GOAL := install

PLUGIN_ID ?= $(shell grep 'plugin\.id' plugin.json | grep -o ':.*' | grep -o '"[^"]\+"' | sed 's/"//g')
PLUGIN_NAME ?= $(shell grep 'plugin\.name' plugin.json | grep -o ':.*' | grep -o '"[^"]\+"' | sed 's/"//g')

GODOT ?= /usr/bin/godot
OPENGAMEPAD_UI_REPO ?= https://github.com/ShadowBlip/OpenGamepadUI.git
OPENGAMEPAD_UI_BASE ?= ../OpenGamepadUI
EXPORT_PRESETS ?= $(OPENGAMEPAD_UI_BASE)/export_presets.cfg
PLUGINS_DIR := $(OPENGAMEPAD_UI_BASE)/plugins
INSTALL_DIR := $(HOME)/.local/share/opengamepadui/plugins
BACKEND_MANIFEST := backend/Cargo.toml
BACKEND_PAYLOAD_DIR := backend/payload
CARGO ?= cargo

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Source installation

.PHONY: install
install: backend $(PLUGINS_DIR)/$(PLUGIN_ID) export_preset ## Build and install the plugin from source.
	@test "`id -u`" != 0 || (echo "Run make as a regular user, not root." >&2; exit 1)
	@echo "Exporting plugin package"
	cd $(OPENGAMEPAD_UI_BASE) && $(MAKE) extensions
	mkdir -p "$(INSTALL_DIR)"
	rm -f "$(INSTALL_DIR)/$(PLUGIN_ID).zip"
	rm -rf "$(INSTALL_DIR)/$(PLUGIN_ID)"
	$(GODOT) --headless \
		--path $(OPENGAMEPAD_UI_BASE) \
		--export-pack "$(PLUGIN_NAME)" \
		"$(INSTALL_DIR)/$(PLUGIN_ID).zip"
	rm -rf "$(BACKEND_PAYLOAD_DIR)"
	@echo "Installed plugin to $(INSTALL_DIR)"

.PHONY: backend
backend: ## Build local backend payloads.
	@test "`uname -s`" = "Linux" || (echo "Backend builds require Linux." >&2; exit 1)
	@test "`uname -m`" = "x86_64" || (echo "Backend builds require x86_64." >&2; exit 1)
	@set -e; target_dir="$$(mktemp -d --tmpdir legion-go-ogui-cargo.XXXXXXXX)"; \
	trap 'rm -rf -- "$$target_dir"' EXIT; \
	CARGO_TARGET_DIR="$$target_dir" $(CARGO) build --manifest-path $(BACKEND_MANIFEST) --release --locked; \
	mkdir -p "$(BACKEND_PAYLOAD_DIR)"; \
	for name in legion-go-ogui-helper legion-go-ogui-controller legion-go-ogui-fan; do \
		base64 --wrap=0 "$$target_dir/release/$$name" > "$(BACKEND_PAYLOAD_DIR)/$$name.b64"; \
	done

.PHONY: clean
clean: ## Remove local build payloads.
	rm -rf "$(BACKEND_PAYLOAD_DIR)"

$(OPENGAMEPAD_UI_BASE):
	git clone $(OPENGAMEPAD_UI_REPO) $@

$(PLUGINS_DIR)/$(PLUGIN_ID): $(OPENGAMEPAD_UI_BASE)
	if ! [ -L $(PLUGINS_DIR)/$(PLUGIN_ID) ]; then ln -s $(PWD) $(PLUGINS_DIR)/$(PLUGIN_ID); fi

.PHONY: export_preset
export_preset: $(OPENGAMEPAD_UI_BASE) ## Configure plugin export preset.
	$(eval LAST_PRESET=$(shell grep -oEi '^\[preset\.([0-9]+)]' $(EXPORT_PRESETS) | tail -n 1))
	$(eval LAST_PRESET_NUM=$(shell echo "$(LAST_PRESET)" | grep -oE '([0-9]+)'))
	$(eval PRESET_NUM=$(shell echo "$(LAST_PRESET_NUM)+1" | bc))
	@if grep 'name="$(PLUGIN_NAME)"' $(EXPORT_PRESETS) > /dev/null; then \
		echo "Export preset already configured"; \
	else \
		echo "Preset not configured"; \
		sed 's/PRESET_NUM/$(PRESET_NUM)/g; s/PLUGIN_NAME/$(PLUGIN_NAME)/g; s/PLUGIN_ID/$(PLUGIN_ID)/g' export_presets.cfg >> $(EXPORT_PRESETS); \
	fi
