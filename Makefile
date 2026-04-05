.PHONY: nvim zellij tmux fmt lint test clean

nvim:
	nvim -u $(CURDIR)/dev/init.lua

zellij:
	TERMINALS_BACKEND=zellij nvim -u $(CURDIR)/dev/init.lua

tmux:
	TERMINALS_BACKEND=tmux nvim -u $(CURDIR)/dev/init.lua

fmt:
	stylua -g '*.lua' -- .
	dprint fmt

lint:
	typos

test:
	nvim --headless --clean -u $(CURDIR)/tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('$(CURDIR)/tests', { minimal_init = '$(CURDIR)/tests/minimal_init.lua', sequential = true })"

clean:
	rm -rf ~/.local/share/nvim/terminals.nvim
