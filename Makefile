.PHONY: test test_file

PLENARY_DIR ?= deps/plenary.nvim

test: $(PLENARY_DIR)
	nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua', sequential = true }"

test_file: $(PLENARY_DIR)
	nvim --headless --noplugin -u tests/minimal_init.lua -c "lua require('plenary.busted').run('$(FILE)')"

$(PLENARY_DIR):
	@mkdir -p deps
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)
