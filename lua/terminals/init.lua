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

---@param opts? table
---@return table
function M.setup(opts)
  if M._did_setup then
    return M
  end

  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  setup_highlights()
  require('terminals.commands').setup(M.config.commands)
  require('terminals.autocmds').setup(setup_highlights)
  require('terminals.commands').setup_keymaps(M.config.keymaps)

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
