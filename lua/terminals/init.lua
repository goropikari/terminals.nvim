local M = {}

---@type TerminalsConfig
M.config = {
  auto_close_on_exit = true,
  focus_terminal_on_open = true,
  keymaps = {
    close = { lhs = '<A-w>', modes = { 'n', 't' } },
    move_left = { lhs = '<C-A-h>', modes = { 'n', 't' } },
    move_right = { lhs = '<C-A-l>', modes = { 'n', 't' } },
    new = { lhs = '<C-n>', modes = { 'n', 't' } },
    next = { lhs = '<A-l>', modes = { 'n', 't' } },
    prev = { lhs = '<A-h>', modes = { 'n', 't' } },
    toggle = { lhs = '<C-t>', modes = { 'n', 't' } },
  },
  commands = {},
  osc_title = true,
  shell = nil,
  start_in_insert = true,
  terminal_position = 'bottom',
  terminal_height = 0.3,
  terminal_width = 0.5,
  float = {
    border = 'rounded',
    height = 0.3,
    width = 0.9,
  },
}

local function setup_highlights()
  vim.api.nvim_set_hl(0, 'TerminalsWinbarFill', { link = 'WinBar' })
  vim.api.nvim_set_hl(0, 'TerminalsWinbarActive', { bold = true, fg = '#111111', bg = '#e5c07b' })
  vim.api.nvim_set_hl(0, 'TerminalsWinbarInactive', { fg = '#abb2bf', bg = '#30343f' })
  vim.api.nvim_set_hl(0, 'TerminalsWinbarDrag', { bold = true, fg = '#111111', bg = '#98c379' })
  vim.api.nvim_set_hl(0, 'TerminalsWinbarButton', { bold = true, fg = '#111111', bg = '#61afef' })
end

---@param button string
---@return boolean
local function is_wheel_up(button)
  return button == 'u' or button == 'wu' or button == 'wheelup' or button == 'up'
end

---@param button string
---@return boolean
local function is_wheel_down(button)
  return button == 'd' or button == 'wd' or button == 'wheeldown' or button == 'down'
end

-- Command handler implementations (shared with keymaps)
local function cmd_handlers()
  return {
    close = function()
      local terminal = require('terminals.terminal').current_or_active()
      if terminal then
        require('terminals.terminal').close(terminal.id, {
          winid = vim.api.nvim_get_current_win(),
        })
      end
    end,
    move_left = function()
      local terminal = require('terminals.terminal').current_or_active()
      if terminal then
        require('terminals.state').move_left(terminal.id)
        require('terminals.ui.winbar').refresh_all()
      end
    end,
    move_right = function()
      local terminal = require('terminals.terminal').current_or_active()
      if terminal then
        require('terminals.state').move_right(terminal.id)
        require('terminals.ui.winbar').refresh_all()
      end
    end,
    new = function()
      require('terminals.terminal').create()
    end,
    next = function()
      require('terminals.terminal').cycle(1)
    end,
    prev = function()
      require('terminals.terminal').cycle(-1)
    end,
    toggle = function()
      require('terminals.terminal').toggle()
    end,
  }
end

local function setup_commands()
  local commands = M.config.commands
  if not commands or type(commands) ~= 'table' or #commands == 0 then
    return
  end

  local h = cmd_handlers()

  local command_registry = {
    TerminalNew = function()
      vim.api.nvim_create_user_command('TerminalNew', function(opts)
        require('terminals.terminal').create({ cmd = opts.args ~= '' and opts.args or nil })
      end, { nargs = '*' })
    end,
    TerminalOpen = function()
      vim.api.nvim_create_user_command('TerminalOpen', function()
        local active = require('terminals.terminal').active_id()
        if active then
          require('terminals.terminal').show(active)
        else
          require('terminals.terminal').create()
        end
      end, {})
    end,
    TerminalToggle = function()
      vim.api.nvim_create_user_command('TerminalToggle', h.toggle, {})
    end,
    TerminalCloseWindow = function()
      vim.api.nvim_create_user_command('TerminalCloseWindow', function()
        require('terminals.terminal').close_window()
      end, {})
    end,
    TerminalSplit = function()
      vim.api.nvim_create_user_command('TerminalSplit', function()
        require('terminals.terminal').open_split()
      end, {})
    end,
    TerminalVSplit = function()
      vim.api.nvim_create_user_command('TerminalVSplit', function()
        require('terminals.terminal').open_split({ vertical = true })
      end, {})
    end,
    TerminalSetPosition = function()
      vim.api.nvim_create_user_command('TerminalSetPosition', function(opts)
        require('terminals').set_tab_policy({
          terminal_position = opts.args,
        })
      end, {
        nargs = 1,
        complete = function()
          return { 'bottom', 'top', 'left', 'right', 'float' }
        end,
      })
    end,
    TerminalNext = function()
      vim.api.nvim_create_user_command('TerminalNext', h.next, {})
    end,
    TerminalPrev = function()
      vim.api.nvim_create_user_command('TerminalPrev', h.prev, {})
    end,
    TerminalClose = function()
      vim.api.nvim_create_user_command('TerminalClose', h.close, {})
    end,
    TerminalPicker = function()
      vim.api.nvim_create_user_command('TerminalPicker', function(opts)
        local backend = opts.args ~= '' and opts.args or nil
        require('terminals.terminal').pick({ backend = backend })
      end, {
        nargs = '?',
        complete = function()
          return { 'ui_select', 'snacks', 'telescope' }
        end,
      })
    end,
    TerminalRename = function()
      vim.api.nvim_create_user_command('TerminalRename', function(opts)
        local active = require('terminals.terminal').active_id()
        if active and opts.args ~= '' then
          require('terminals.terminal').rename(active, opts.args)
        end
      end, { nargs = 1 })
    end,
    TerminalMoveLeft = function()
      vim.api.nvim_create_user_command('TerminalMoveLeft', h.move_left, {})
    end,
    TerminalMoveRight = function()
      vim.api.nvim_create_user_command('TerminalMoveRight', h.move_right, {})
    end,
    TerminalSendLine = function()
      vim.api.nvim_create_user_command('TerminalSendLine', function()
        require('terminals.terminal').send_current_line()
      end, {})
    end,
    TerminalSendSelection = function()
      vim.api.nvim_create_user_command('TerminalSendSelection', function(opts)
        local terminal = require('terminals.terminal')
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")
        local start_row = start_pos[2]
        local end_row = end_pos[2]

        if start_row > 0 and end_row > 0 and start_row == opts.line1 and end_row == opts.line2 then
          terminal.send_visual_selection()
          return
        end

        terminal.send_range(opts.line1, opts.line2)
      end, { range = true })
    end,
  }

  for _, command_name in ipairs(commands) do
    if command_registry[command_name] then
      command_registry[command_name]()
    end
  end
end

-- Autocommands

---@param tabpage integer
local function reopen_tab_terminal_window(tabpage)
  local terminal = require('terminals.terminal')
  local state = require('terminals.state')
  local winid = state.terminal_window(tabpage)
  local active = state.active(tabpage)

  if winid then
    terminal.hide(tabpage, { snapshot = false })
  end

  if active then
    terminal.show(active.id, { tabpage = tabpage })
  end
end

local function setup_keymaps()
  local handlers = cmd_handlers()

  for name, spec in pairs(M.config.keymaps or {}) do
    if spec and spec.lhs and handlers[name] then
      vim.keymap.set(spec.modes or 'n', spec.lhs, handlers[name], {
        desc = 'terminals.nvim ' .. name,
        silent = true,
      })
    end
  end
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup('TerminalsNvim', { clear = true })

  vim.api.nvim_create_autocmd({ 'TabEnter', 'WinEnter', 'BufEnter', 'DirChanged' }, {
    group = group,
    callback = function()
      local state = require('terminals.state')
      local terminal = require('terminals.terminal')
      local tabpage = state.current_tabpage()
      local winid = vim.api.nvim_get_current_win()
      local bufnr = vim.api.nvim_get_current_buf()
      if vim.wo[winid].winbar == '' then
        return
      end
      if state.find_terminal_by_bufnr(bufnr, tabpage) and state.is_terminal_window(winid, tabpage) then
        state.add_terminal_window(winid, tabpage)
      elseif #state.terminal_windows(tabpage) == 0 then
        state.set_terminal_window(nil, tabpage)
      end
      terminal.sync_current_buffer()
      require('terminals.ui.winbar').refresh_all()
    end,
  })

  vim.api.nvim_create_autocmd({ 'TermClose', 'BufDelete' }, {
    group = group,
    callback = function(args)
      local terminals = require('terminals')
      local terminal_api = require('terminals.terminal')
      local state = require('terminals.state')
      local terminal, _, tabpage = state.find_terminal_by_bufnr(args.buf)
      if terminal then
        if terminals._is_quitting then
          state.remove_terminal(terminal.id, tabpage)
          return
        end

        if args.event == 'TermClose' and terminals.config.auto_close_on_exit then
          vim.schedule(function()
            local existing = state.find_terminal(terminal.id, tabpage)
            if existing then
              terminal_api.close(terminal.id, {
                tabpage = tabpage,
                winid = state.terminal_window(tabpage),
              })
            end
          end)
          return
        end

        state.remove_terminal(terminal.id, tabpage)
        require('terminals.ui.winbar').refresh_all()
      end
    end,
  })

  vim.api.nvim_create_autocmd('TermRequest', {
    group = group,
    callback = function(args)
      local terminals = require('terminals')
      if not terminals.config.osc_title then
        return
      end
      local bufnr = args.buf
      local sequence = args.data and args.data.sequence or nil
      require('terminals.terminal').handle_term_request(bufnr, sequence)
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      local closed = tonumber(args.match)
      if not closed then
        return
      end
      local state = require('terminals.state')
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        if state.is_terminal_window(closed, tabpage) then
          state.remove_terminal_window(closed, tabpage)
        end
      end
      require('terminals.ui.winbar').refresh_all()
    end,
  })

  vim.api.nvim_create_autocmd('WinResized', {
    group = group,
    callback = function()
      require('terminals.ui.winbar').refresh_all()
    end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = setup_highlights,
  })

  vim.api.nvim_create_autocmd({ 'QuitPre', 'VimLeavePre' }, {
    group = group,
    callback = function()
      local terminals = require('terminals')
      if terminals._is_quitting then
        return
      end
      terminals._is_quitting = true
      require('terminals.terminal').cleanup_for_quit()
    end,
  })
end

---@param opts? table
---@return table
function M.setup(opts)
  if M._did_setup then
    return M
  end

  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  setup_highlights()
  setup_commands()
  setup_autocmds()
  setup_keymaps()

  vim.cmd([[
    cnoreabbrev <expr> q      v:lua.require'terminals'.command_abbrev('q')
    cnoreabbrev <expr> q!     v:lua.require'terminals'.command_abbrev('q!')
    cnoreabbrev <expr> quit   v:lua.require'terminals'.command_abbrev('quit')
    cnoreabbrev <expr> quit!  v:lua.require'terminals'.command_abbrev('quit!')
    cnoreabbrev <expr> split  v:lua.require'terminals'.command_abbrev('split')
    cnoreabbrev <expr> sp     v:lua.require'terminals'.command_abbrev('sp')
    cnoreabbrev <expr> vsplit v:lua.require'terminals'.command_abbrev('vsplit')
    cnoreabbrev <expr> vs     v:lua.require'terminals'.command_abbrev('vs')
  ]])

  _G.TerminalsWinbarClick = function(minwid, _, button, _)
    local terminal = require('terminals.terminal')
    local pos = vim.fn.getmousepos()
    local winid = pos.winid ~= 0 and pos.winid or nil
    local tabpage = winid and vim.api.nvim_win_get_tabpage(winid) or nil

    if is_wheel_up(button) then
      terminal.cycle(-1)
      return
    end

    if is_wheel_down(button) then
      terminal.cycle(1)
      return
    end

    if button == 'l' then
      terminal.show(minwid, { winid = winid, tabpage = tabpage })
      require('terminals.ui.drag').begin(minwid)
      return
    end

    if button == 'm' then
      terminal.close(minwid, {
        winid = winid,
        tabpage = tabpage,
      })
      return
    end

    if button == 'r' then
      local current = require('terminals.state').find_terminal(minwid)
      if not current then
        return
      end
      terminal.show(minwid, { winid = winid, tabpage = tabpage })
      vim.schedule(function()
        vim.ui.input({
          prompt = 'Rename terminal: ',
          default = current.title,
        }, function(input)
          if input and input ~= '' then
            terminal.rename(minwid, input)
          end
        end)
      end)
    end
  end

  _G.TerminalsWinbarAdd = function(_, _, button, _)
    if button ~= 'l' then
      return
    end
    require('terminals.terminal').create()
  end

  M._did_setup = true
  return M
end

---@param command string
---@return string
function M.command_abbrev(command)
  if vim.fn.getcmdtype() ~= ':' then
    return command
  end

  local current = vim.fn.getcmdline()
  if current ~= command then
    return command
  end

  if not require('terminals.terminal').is_terminal_window() then
    return command
  end

  if command == 'q' or command == 'q!' or command == 'quit' or command == 'quit!' then
    return 'TerminalCloseWindow'
  end

  if command == 'split' or command == 'sp' then
    return 'TerminalSplit'
  end

  if command == 'vsplit' or command == 'vs' then
    return 'TerminalVSplit'
  end

  return command
end

---@param tabpage? integer
---@return table
function M.get_tab_policy(tabpage)
  return vim.deepcopy(require('terminals.state').tab_policy(tabpage))
end

---@param policy table
---@param tabpage? integer
function M.set_tab_policy(policy, tabpage)
  tabpage = tabpage or require('terminals.state').current_tabpage()
  require('terminals.state').set_tab_policy(policy, tabpage)
  reopen_tab_terminal_window(tabpage)
  require('terminals.ui.winbar').refresh_all()
end

---@param policy table
---@param tabpage? integer
function M.replace_tab_policy(policy, tabpage)
  tabpage = tabpage or require('terminals.state').current_tabpage()
  require('terminals.state').replace_tab_policy(policy, tabpage)
  reopen_tab_terminal_window(tabpage)
  require('terminals.ui.winbar').refresh_all()
end

---@param tabpage? integer
function M.clear_tab_policy(tabpage)
  tabpage = tabpage or require('terminals.state').current_tabpage()
  require('terminals.state').clear_tab_policy(tabpage)
  reopen_tab_terminal_window(tabpage)
  require('terminals.ui.winbar').refresh_all()
end

return M
