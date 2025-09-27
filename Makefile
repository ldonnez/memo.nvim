IMAGE_NAME := memo-nvim
CONTAINER_NAME := $(IMAGE_NAME)
VOLUME_MOUNT := -v $(shell pwd):/opt
MEMO_PATH := $(shell which memo)
VOLUME_MOUNT_MEMO := -v $(shell readlink -f $(MEMO_PATH)):/root/.local/bin/memo
OS ?= $(shell uname -s | tr '[:upper:]' '[:lower:]')

ifeq ($(shell uname -m),arm64)
    ARCH ?= arm64
else
    ARCH ?= x64
endif


EMMYLUA_REF := 0.18.0
EMMYLUA_RELEASE_URL := https://github.com/EmmyLuaLs/emmylua-analyzer-rust/releases/download/$(EMMYLUA_REF)/emmylua_check-$(OS)-$(ARCH).tar.gz
EMMYLUA_RELEASE_TAR := deps/emmylua_check-$(EMMYLUA_REF)-$(OS)-$(ARCH).tar.gz
EMMYLUA_DIR := deps/emmylua
EMMYLUA_BIN := $(EMMYLUA_DIR)/emmylua_check

# Run all test files
test: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run test from file at `$FILE` environment variable
test_file: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim $@

deps/memo:
	@echo "Installing memo..."
	@mkdir -p $(HOME)/.local/bin
	@git clone --depth 1 https://github.com/ldonnez/memo /tmp/memo && \
	install -m 0755 /tmp/memo/memo.sh $(HOME)/.local/bin/memo && \
	rm -rf /tmp/memo

# Download 'emmylua_check' to lint
deps/emmylua_check:
	@mkdir -p deps
	mkdir -p $(EMMYLUA_DIR)
	curl -L $(EMMYLUA_RELEASE_URL) -o $(EMMYLUA_RELEASE_TAR)
	tar -xzf $(EMMYLUA_RELEASE_TAR) -C $(EMMYLUA_DIR)
	rm $(EMMYLUA_RELEASE_TAR)

docker/build-image:
	@docker build -t $(IMAGE_NAME) .

docker/shell:
	@docker run --rm -it --name $(CONTAINER_NAME) $(VOLUME_MOUNT) $(VOLUME_MOUNT_MEMO) $(IMAGE_NAME) /bin/bash; \

EMMYLUA_CFG := $(CURDIR)/.emmyrc.json
NVIM_RUNTIME := /usr/share/nvim/runtime

# Conditional assignment for macOS
ifeq ($(UNAME_S),darwin)
    # Darwin is the kernel name for macOS
    NVIM_RUNTIME := /usr/local/share/nvim/runtime/
endif

emmylua_check: $(EMMYLUA_BIN)
	env VIMRUNTIME=$(NVIM_RUNTIME) \
		$(EMMYLUA_BIN) \
		--config $(EMMYLUA_CFG) \
		.
