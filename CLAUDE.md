# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`terminals.nvim` is a Neovim plugin that manages terminal buffers as terminal tabs with a tab strip rendered in `winbar`s. Key features include session persistence per project (CWD-based), backend support (Neovim, Zellij, Tmux), and mouse interaction.

## Commands

```sh
# Run Neovim with plugin
make nvim

# Run with Zellij backend
make zellij

# Run with Tmux backend
make tmux

# Run tests
make test

# Format code
make fmt

# Lint
make lint

# Clean session data
make clean
```

## Architecture

### Core Modules

- **`lua/terminals/init.lua`** - Plugin entry point: setup, configuration, commands, keymaps, autocmds
- **`lua/terminals/terminal.lua`** - Terminal operations: create, show, hide, toggle, cycle, send, rename, close
- **`lua/terminals/state.lua`** - State management: CWD-based project isolation, terminal tracking, window management, serialization

### UI Modules

- **`lua/terminals/ui/winbar.lua`** - Terminal tab strip rendering in winbar
- **`lua/terminals/ui/drag.lua`** - Mouse drag handling for reordering terminals

### Key Architecture Concepts

1. **CWD-based project isolation**: Each project directory has isolated terminal state stored in `~/.local/share/nvim/terminals.nvim/state_<hash>.json`

2. **Terminal window model**: Each tabpage has a primary terminal window (`primary_terminal_winid`) and can have multiple managed terminal windows (`terminal_winids`)

3. **Winbar click handlers**: `_G.TerminalsWinbarClick` handles left/middle/right clicks and wheel; `_G.TerminalsWinbarAdd` handles the `+` button

4. **Backend abstraction**: Terminal commands are generated differently based on `backend` config (`none`, `zellij`, `tmux`). Backends use minimal config files for raw terminal appearance

5. **Session persistence**: On `QuitPre`/`VimLeavePre`, state is serialized; on `VimEnter`/`SessionLoadPost`, state is restored

6. **Title sync**: OSC 0/2 sequences are parsed and synced via timer (`ensure_title_sync_timer`)

### Configuration

Main config in `init.lua`:

- `keymaps`: close, move_left, move_right, new, next, prev, toggle
- `terminal_position`: bottom, top, left, right, float
- `float`: width, height, border, row, col
- `backend`: none, zellij, tmux
- `auto_restore`: enable session persistence

### API

```lua
-- Setup
require("terminals").setup(opts)

-- Tab policy (per-tabpage window config)
require("terminals").get_tab_policy()
require("terminals").set_tab_policy(policy)
require("terminals").replace_tab_policy(policy)
require("terminals").clear_tab_policy()

-- Terminal operations
local terminal = require("terminals.terminal")
terminal.create({ cmd, cwd, title })
terminal.show(id)
terminal.toggle()
terminal.cycle(step)
terminal.pick({ backend = "telescope" })
terminal.send(text)
terminal.send_current_line()
terminal.send_visual_selection()
terminal.rename(id, title)
terminal.close(id)

-- State
local state = require("terminals.state")
state.list(tabpage)
state.active(tabpage)
state.move_left(id)
state.move_right(id)
state.save()
state.load()
state.clean()
```

## Testing

Tests use `plenary.nvim` test harness. Test file: `tests/terminals_spec.lua`. Minimal init at `tests/minimal_init.lua` adds plenary to runtimepath.

## Development Notes

- Dev config at `dev/init.lua` sets up runtimepath and basic keymaps
- Esc in terminal-mode mapped to normal-mode for development
- Mouse must be enabled (`set mouse=a`) for winbar interaction
- Terminal buffers are unlisted (`buflisted = false`)

## Git Worktree

When working in a git worktree, use the worktree directory as the base for all file operations. The working directory set by the worktree is the reference point for reading, writing, and editing files.
