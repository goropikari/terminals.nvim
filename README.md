# terminals.nvim

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/goropikari/terminals.nvim)

`terminals.nvim` is a Neovim plugin that manages terminal buffers as terminal tabs.
It renders a terminal tab strip in managed terminal window `winbar`s, supports mouse interaction, and keeps terminal groups isolated per project.

## Features

- Independent terminal groups per project (isolated by git worktree root when available, otherwise by CWD)
- Dedicated terminal area per tabpage
- Managed terminal splits with independent terminal views per window
- Terminal tabs rendered only in managed terminal window `winbar`s
- Click to switch terminals
- Right click to rename a terminal
- Middle click to close a terminal
- Drag in the `winbar` to reorder terminals
- Toggle managed terminal windows without killing running processes
- Auto-close finished terminals
- OSC 0 / OSC 2 title updates
- Terminal picker via `vim.ui.select()` or optional Telescope
  Telescope previews terminal output from the latest lines with `bash` highlighting
- Tab-local window policies for split or float placement
- Configurable split position or floating window
- Command API and Lua API

## Requirements

- Neovim 0.11+
- `set mouse=a` if you want mouse support

## Installation

Using `lazy.nvim`:

```lua
{
  "goropikari/terminals.nvim",
  lazy = false,  -- Session persistence may not work properly with lazy loading
  opts = {
    auto_close_on_exit = true,
    focus_terminal_on_open = true,
    keymaps = {
      toggle = { lhs = "<C-t>", modes = { "n", "t" } },
      new = { lhs = "<C-n>", modes = { "n", "t" } },
      next = { lhs = "<A-l>", modes = { "n", "t" } },
      prev = { lhs = "<A-h>", modes = { "n", "t" } },
      move_left = { lhs = "<C-A-h>", modes = { "n", "t" } },
      move_right = { lhs = "<C-A-l>", modes = { "n", "t" } },
      close = { lhs = "<A-w>", modes = { "n", "t" } },
    },
    osc_title = true,
    start_in_insert = true,
    terminal_position = "bottom",
    terminal_height = 12,
    terminal_width = 80,
    float = {
      width = 0.9,
      height = 0.3,
      border = "rounded",
    },
  },
}
```

## Configuration

Available options:

- `auto_close_on_exit`: close a managed terminal automatically after its job exits
- `focus_terminal_on_open`: move focus to a managed terminal window when opening/showing a terminal
- `keymaps`: default keymaps; unspecified entries keep their defaults
- `osc_title`: update managed terminal titles from OSC 0 / OSC 2 sequences emitted by terminal programs
- `shell`: default shell or command used by `TerminalNew` when no command is passed; defaults to `vim.o.shell`
- `start_in_insert`: enter terminal-mode after opening a terminal
- `terminal_position`: one of `bottom`, `top`, `left`, `right`, `float`
- `terminal_height`: used only when `terminal_position` is `bottom` or `top`
- `terminal_width`: used only when `terminal_position` is `left` or `right`
- `float.width`: used only when `terminal_position` is `float`; absolute number or ratio
- `float.height`: used only when `terminal_position` is `float`; absolute number or ratio
- `float.border`: used only when `terminal_position` is `float`
- `float.row`: optional float row; used only when `terminal_position` is `float`
- `float.col`: optional float column; used only when `terminal_position` is `float`

Notes about `keymaps`:

- Omit an entry to keep the default keymap
- Set an entry to `false` to disable it
- Override only the entries you care about; the rest keep their defaults

Example:

```lua
require("terminals").setup({
  keymaps = {
    next = { lhs = "<A-n>", modes = { "n", "t" } },
    move_right = { lhs = "<C-A-n>", modes = { "n", "t" } },
    close = false,
  },
})
```

By default, the plugin uses `vim.o.shell`.
To override it explicitly:

```lua
require("terminals").setup({
  shell = "/bin/zsh",
})
```

## API

### Create / Open / Toggle

| Command                | Lua                                                                      |
| ---------------------- | ------------------------------------------------------------------------ |
| `:TerminalNew [cmd]`   | `require("terminals.terminal").create({ cmd = "cmd", title = "title" })` |
| `:TerminalOpen`        | `require("terminals.terminal").show(id)`                                 |
| `:TerminalToggle`      | `require("terminals.terminal").toggle()`                                 |
| `:TerminalClose`       | `require("terminals.terminal").close(id)`                                |
| `:TerminalCloseWindow` | `require("terminals").clear_tab_policy()`                                |
| `:TerminalSplit`       | `require("terminals").set_tab_policy({ terminal_position = "bottom" })`  |
| `:TerminalVSplit`      | `require("terminals").set_tab_policy({ terminal_position = "left" })`    |

### Navigation

| Command              | Lua                                         |
| -------------------- | ------------------------------------------- |
| `:TerminalNext`      | `require("terminals.terminal").cycle(1)`    |
| `:TerminalPrev`      | `require("terminals.terminal").cycle(-1)`   |
| `:TerminalMoveLeft`  | `require("terminals.state").move_left(id)`  |
| `:TerminalMoveRight` | `require("terminals.state").move_right(id)` |

### Terminal Picker

| Command                                          | Lua                                                          |
| ------------------------------------------------ | ------------------------------------------------------------ |
| `:TerminalPicker [ui_select\|snacks\|telescope]` | `require("terminals.terminal").pick({ backend = "snacks" })` |

### Terminal Operations

| Command                   | Lua                                                     |
| ------------------------- | ------------------------------------------------------- |
| `:TerminalRename {title}` | `require("terminals.terminal").rename(id, "title")`     |
| `:TerminalSendLine`       | `require("terminals.terminal").send_current_line()`     |
| `:TerminalSendSelection`  | `require("terminals.terminal").send_visual_selection()` |

### Window Configuration

| Command                                                  | Lua                                                                                     |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `:TerminalSetPosition {bottom\|top\|left\|right\|float}` | `require("terminals").set_tab_policy({ terminal_position = "float", float = { ... } })` |

### Setup

```lua
require("terminals").setup(opts)
```

## Keymap Examples

Using commands:

```lua
vim.keymap.set("n", "<leader>tl", "<cmd>TerminalSendLine<cr>", { desc = "Send line to terminal" })
vim.keymap.set("v", "<leader>ts", ":'<,'>TerminalSendSelection<cr>", { desc = "Send selection to terminal" })
```

Using the Lua API:

```lua
local terminal = require("terminals.terminal")

vim.keymap.set("n", "<leader>tl", function()
  terminal.send_current_line()
end, { desc = "Send line to terminal" })

vim.keymap.set("v", "<leader>ts", function()
  terminal.send_visual_selection()
end, { desc = "Send selection to terminal" })
```

## Mouse Behavior

Inside the terminal `winbar`:

- Left click switches to a terminal
- Right click renames it
- Middle click closes it
- Mouse wheel on the `winbar` switches to the previous or next terminal
- Left drag reorders it
- Click `+` to create a new terminal

## Behavior Notes

- Terminal buffers are unlisted, so they do not appear in normal `:ls`
- `:ls!` can still show them, which is standard Neovim behavior
- `TerminalToggle` hides and shows the managed terminal windows without killing terminal jobs
- Manual window resizing is preserved across `TerminalToggle`
- Managed terminal windows use `winfixbuf`, so regular buffers are rejected there
- In terminal windows, `:split` and `:vsplit` also create managed terminal splits
- In terminal windows, `:q` and `:quit` close only the current managed terminal window
- `TerminalClose` switches to the next available terminal when possible
- Closing the last managed terminal creates a fresh terminal in the same managed window
- During `:qa` / `:qa!`, terminal jobs are stopped so Neovim can exit cleanly
- `terminal_height` and `terminal_width` do nothing when `terminal_position = "float"`
- `float.*` settings do nothing unless `terminal_position = "float"`

## Development

This repository includes a small dev config used by `make nvim`.

```sh
make nvim
```

That launches Neovim with:

- this plugin added to `runtimepath`
- a small test setup from [`dev/init.lua`](/home/ubuntu/workspace/github/terminals.nvim/dev/init.lua)
- `Esc` in terminal-mode mapped to normal-mode
