.PHONY: nvim fmt lint test clean

nvim:
	nvim -u $(CURDIR)/dev/init.lua

fmt:
	stylua -g '*.lua' -- .
	dprint fmt

lint:
	typos

test:
	nvim --headless --clean -u $(CURDIR)/tests/minimal_init.lua \
		-c "lua require('plenary.test_harness').test_directory('$(CURDIR)/tests', { minimal_init = '$(CURDIR)/tests/minimal_init.lua', sequential = true })"

clean:
	rm -f nvim.log
