# terminals.nvim

`terminals.nvim` is a Neovim plugin that manages terminal buffers as terminal tabs.
It renders a terminal tab strip in managed terminal window `winbar`s, supports mouse interaction, and keeps terminal groups isolated per tabpage.

## Features

- Independent terminal groups per tabpage
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

If you only want the raw `setup()` example:

```lua
require("terminals").setup({
  shell = vim.o.shell,
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
})
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

## Commands

- `:TerminalNew [cmd]`
- `:TerminalOpen`
- `:TerminalToggle`
- `:TerminalCloseWindow`
- `:TerminalSplit`
- `:TerminalVSplit`
- `:TerminalSetPosition {bottom|top|left|right|float}`
- `:TerminalNext`
- `:TerminalPrev`
- `:TerminalClose`
- `:TerminalPicker [ui_select|telescope]`
- `:TerminalRename {title}`
- `:TerminalMoveLeft`
- `:TerminalMoveRight`
- `:TerminalSendLine`
- `:TerminalSendSelection`

## Lua API

Main setup module:

```lua
require("terminals").setup(opts)
require("terminals").get_tab_policy()
require("terminals").set_tab_policy({
  terminal_position = "float",
  float = {
    width = 0.8,
    height = 0.35,
  },
})
require("terminals").replace_tab_policy({
  terminal_position = "left",
  terminal_width = 40,
})
require("terminals").clear_tab_policy()
```

Terminal operations:

```lua
local terminal = require("terminals.terminal")

terminal.create({ cmd = "htop", cwd = vim.loop.cwd(), title = "monitor" })
terminal.show(id)
terminal.toggle()
terminal.cycle(1)   -- next
terminal.cycle(-1)  -- prev
terminal.pick()
terminal.pick({ backend = "telescope" })
terminal.send("npm test")
terminal.send_current_line()
terminal.send_visual_selection()
terminal.rename(id, "server")
terminal.close(id)
```

Useful helpers:

```lua
local terminal = require("terminals.terminal")
local state = require("terminals.state")

local current = terminal.current_or_active()
local active_id = terminal.active_id()

local terminals = state.list()
local active = state.active()
state.move_left(active.id)
state.move_right(active.id)
```

Common examples:

Create a new terminal from Lua:

```lua
require("terminals.terminal").create()
```

Open a specific command:

```lua
require("terminals.terminal").create({
  cmd = "lazygit",
  title = "git",
})
```

Toggle managed terminal windows:

```lua
require("terminals.terminal").toggle()
```

Open a terminal picker:

```lua
require("terminals.terminal").pick()
```

Use Telescope when available:

```lua
require("terminals.terminal").pick({
  backend = "telescope",
})
```

Use a different window policy in the current tabpage:

```lua
require("terminals").set_tab_policy({
  terminal_position = "left",
  terminal_width = 40,
})
```

Send the current line:

```lua
require("terminals.terminal").send_current_line()
```

Send the current visual selection:

```lua
require("terminals.terminal").send_visual_selection()
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
