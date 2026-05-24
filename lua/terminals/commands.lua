local M = {}

function M.handlers()
  local terminal = require('terminals.terminal')
  local state = require('terminals.state')
  local winbar = require('terminals.ui.winbar')

  return {
    close = function()
      local current = terminal.current_or_active()
      if current then
        terminal.close(current.id, {
          winid = vim.api.nvim_get_current_win(),
        })
      end
    end,
    move_left = function()
      local current = terminal.current_or_active()
      if current then
        state.move_left(current.id)
        winbar.refresh_all()
      end
    end,
    move_right = function()
      local current = terminal.current_or_active()
      if current then
        state.move_right(current.id)
        winbar.refresh_all()
      end
    end,
    new = function()
      terminal.create()
    end,
    next = function()
      terminal.cycle(1)
    end,
    prev = function()
      terminal.cycle(-1)
    end,
    toggle = function()
      terminal.toggle()
    end,
  }
end

---@param commands string[]
function M.setup(commands)
  if not commands or type(commands) ~= 'table' or #commands == 0 then
    return
  end

  local h = M.handlers()
  local terminal = require('terminals.terminal')
  local command_definitions = {
    TerminalNew = {
      callback = function(opts)
        terminal.create({ cmd = opts.args ~= '' and opts.args or nil })
      end,
      opts = { nargs = '*' },
    },
    TerminalOpen = {
      callback = function()
        local active = terminal.active_id()
        if active then
          terminal.show(active)
        else
          terminal.create()
        end
      end,
    },
    TerminalToggle = { callback = h.toggle },
    TerminalCloseWindow = {
      callback = function()
        terminal.close_window()
      end,
    },
    TerminalSplit = {
      callback = function()
        terminal.open_split()
      end,
    },
    TerminalVSplit = {
      callback = function()
        terminal.open_split({ vertical = true })
      end,
    },
    TerminalSetPosition = {
      callback = function(opts)
        require('terminals').set_tab_policy({
          terminal_position = opts.args,
        })
      end,
      opts = {
        nargs = 1,
        complete = function()
          return { 'bottom', 'top', 'left', 'right', 'float' }
        end,
      },
    },
    TerminalNext = { callback = h.next },
    TerminalPrev = { callback = h.prev },
    TerminalClose = { callback = h.close },
    TerminalPicker = {
      callback = function(opts)
        local backend = opts.args ~= '' and opts.args or nil
        terminal.pick({ backend = backend })
      end,
      opts = {
        nargs = '?',
        complete = function()
          return { 'ui_select', 'snacks', 'telescope' }
        end,
      },
    },
    TerminalRename = {
      callback = function(opts)
        local active = terminal.active_id()
        if active and opts.args ~= '' then
          terminal.rename(active, opts.args)
        end
      end,
      opts = { nargs = 1 },
    },
    TerminalMoveLeft = { callback = h.move_left },
    TerminalMoveRight = { callback = h.move_right },
    TerminalSendLine = {
      callback = function()
        terminal.send_current_line()
      end,
    },
    TerminalSendSelection = {
      callback = function(opts)
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")
        local start_row = start_pos[2]
        local end_row = end_pos[2]

        if start_row > 0 and end_row > 0 and start_row == opts.line1 and end_row == opts.line2 then
          terminal.send_visual_selection()
          return
        end

        terminal.send_range(opts.line1, opts.line2)
      end,
      opts = { range = true },
    },
  }

  for _, command_name in ipairs(commands) do
    local command = command_definitions[command_name]
    if command then
      vim.api.nvim_create_user_command(command_name, command.callback, command.opts or {})
    end
  end
end

---@param keymaps table<string, table|false>
function M.setup_keymaps(keymaps)
  local handlers = M.handlers()

  for name, spec in pairs(keymaps or {}) do
    if spec and spec.lhs and handlers[name] then
      vim.keymap.set(spec.modes or 'n', spec.lhs, handlers[name], {
        desc = 'terminals.nvim ' .. name,
        silent = true,
      })
    end
  end
end

return M
