local state = require('terminals.state')
local picker = require('terminals.picker')
local send = require('terminals.send')
local title = require('terminals.title')
local window = require('terminals.window')

---@class TerminalsConfig
---@field auto_close_on_exit boolean
---@field focus_terminal_on_open boolean
---@field keymaps table<string, table|false>
---@field commands string[]
---@field osc_title boolean
---@field shell? string
---@field start_in_insert boolean
---@field terminal_position string
---@field terminal_height number
---@field terminal_width number
---@field float { border?: string, height?: number, width?: number, row?: number, col?: number }

---@class TerminalsCreateOpts
---@field tabpage? integer
---@field cwd? string
---@field cmd? string
---@field title? string
---@field winid? integer

---@class TerminalsShowOpts
---@field tabpage? integer
---@field winid? integer

---@class TerminalsSendOpts
---@field id? integer
---@field tabpage? integer
---@field newline? boolean
---@field submit_delay_ms? integer

---@class TerminalsPickOpts
---@field backend? '"ui_select"'|'"telescope"'|string
---@field prompt? string
---@field preview_max_lines? integer
---@field tabpage? integer

local M = {}

---@param tabpage? integer
---@return TerminalsConfig
local function config(tabpage)
  tabpage = tabpage or state.current_tabpage()
  return vim.tbl_deep_extend('force', {}, require('terminals').config, state.tab_policy(tabpage))
end

---@return boolean
local function is_quitting()
  return require('terminals')._is_quitting == true
end

---@param cmd? string
---@param tabpage? integer
---@return string
local function shell_for_command(cmd, tabpage)
  if cmd and cmd ~= '' then
    return cmd
  end

  local cfg = config(tabpage)
  return cfg.shell or vim.o.shell
end

---@return boolean
local function mouse_over_terminal_winbar()
  local pos = vim.fn.getmousepos()
  local winid = pos.winid
  if not winid or winid == 0 or not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  local tabpage = vim.api.nvim_win_get_tabpage(winid)
  if not state.is_terminal_window(winid, tabpage) or vim.wo[winid].winbar == '' then
    return false
  end

  local topline = vim.api.nvim_win_call(winid, function()
    return vim.fn.line('w0')
  end)
  local first_text = vim.fn.screenpos(winid, topline, 1)
  return first_text.row > 0 and pos.screenrow == first_text.row - 1
end

---@param bufnr integer
local function attach_mouse_mappings(bufnr)
  local opts = { buffer = bufnr, silent = true }
  local wheel_opts = { buffer = bufnr, expr = true, remap = true, silent = true }

  vim.keymap.set({ 'n', 't' }, '<LeftDrag>', function()
    require('terminals.ui.drag').update()
  end, opts)

  vim.keymap.set({ 'n', 't' }, '<LeftRelease>', function()
    require('terminals.ui.drag').finish()
  end, opts)

  vim.keymap.set({ 'n', 't' }, '<ScrollWheelUp>', function()
    return require('terminals.terminal').handle_scroll_wheel('up')
  end, wheel_opts)

  vim.keymap.set({ 'n', 't' }, '<ScrollWheelDown>', function()
    return require('terminals.terminal').handle_scroll_wheel('down')
  end, wheel_opts)
end

---@param winid integer
---@param bufnr integer
local function move_window_to_terminal_end(winid, bufnr)
  if not (vim.api.nvim_win_is_valid(winid) and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count > 0 then
    local target_line = line_count
    local target_text = ''
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for index = #lines, 1, -1 do
      if lines[index] ~= '' then
        target_line = index
        target_text = lines[index]
        break
      end
    end
    pcall(vim.api.nvim_win_set_cursor, winid, { target_line, #target_text })
    pcall(vim.api.nvim_win_call, winid, function()
      vim.cmd('normal! zb')
    end)
  end
end

---@param winid? integer
---@param tabpage? integer
---@return boolean
function M.is_terminal_window(winid, tabpage)
  return window.is_terminal_window(winid, tabpage)
end

---@param opts? TerminalsCreateOpts
---@return TerminalsTerminal
function M.create(opts)
  opts = opts or {}
  local tabpage = opts.tabpage or state.current_tabpage()
  local cwd = opts.cwd or vim.loop.cwd()
  local cmd = opts.cmd
  local winid = opts.winid
  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    winid = window.ensure(tabpage)
  else
    state.add_terminal_window(winid, tabpage)
  end

  local bufnr = window.unlocked(winid, function()
    vim.api.nvim_set_current_win(winid)
    vim.cmd('enew')
    return vim.api.nvim_get_current_buf()
  end)
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].filetype = 'terminal'
  attach_mouse_mappings(bufnr)

  local terminal_id = state.next_id()
  local job_id = vim.fn.termopen(shell_for_command(cmd, tabpage), {
    cwd = cwd,
  })

  local terminal = {
    id = terminal_id,
    bufnr = bufnr,
    job_id = job_id,
    title = opts.title or title.for_command(cmd, tabpage),
    cwd = cwd,
    alive = true,
  }

  state.add_terminal(terminal, tabpage)
  state.set_window_terminal(winid, terminal.id, tabpage)
  window.unlocked(winid, function()
    vim.api.nvim_win_set_buf(winid, bufnr)
  end)
  move_window_to_terminal_end(winid, bufnr)
  window.set_locked(winid, true)
  require('terminals.ui.winbar').refresh_all()
  title.ensure_timer()

  if config(tabpage).start_in_insert then
    vim.cmd('startinsert')
  end

  return terminal
end

local wheel_passthrough = false

---@param direction '"up"'|'"down"'|string
---@return string
function M.handle_scroll_wheel(direction)
  local key = direction == 'up' and '<ScrollWheelUp>' or '<ScrollWheelDown>'

  if wheel_passthrough then
    wheel_passthrough = false
    return key
  end

  if mouse_over_terminal_winbar() then
    vim.schedule(function()
      M.cycle(direction == 'up' and -1 or 1)
    end)
    return '<Ignore>'
  end

  wheel_passthrough = true
  return key
end

---@param id integer
---@param opts? TerminalsShowOpts
---@return TerminalsTerminal?
function M.show(id, opts)
  opts = opts or {}
  local tabpage = opts.tabpage or state.current_tabpage()
  local terminal = state.set_active(id, tabpage)
  if not terminal then
    return nil
  end

  if not vim.api.nvim_buf_is_valid(terminal.bufnr) then
    state.remove_terminal(id, tabpage)
    require('terminals.ui.winbar').refresh_all()
    return nil
  end

  local winid = opts.winid or window.ensure(tabpage)
  state.add_terminal_window(winid, tabpage)
  state.set_window_terminal(winid, terminal.id, tabpage)
  window.unlocked(winid, function()
    vim.api.nvim_win_set_buf(winid, terminal.bufnr)
  end)
  move_window_to_terminal_end(winid, terminal.bufnr)
  window.set_locked(winid, true)
  if config(tabpage).focus_terminal_on_open and vim.api.nvim_get_current_win() ~= winid then
    vim.api.nvim_set_current_win(winid)
  end
  require('terminals.ui.winbar').refresh_all()

  if config(tabpage).start_in_insert and vim.bo[terminal.bufnr].buftype == 'terminal' then
    vim.cmd('startinsert')
  end

  return terminal
end

function M.hide(...)
  return window.hide(...)
end

function M.close_window(...)
  return window.close_window(...)
end

---@return boolean
function M.toggle()
  local tabpage = state.current_tabpage()
  if window.terminal_window(tabpage) then
    return M.hide(tabpage)
  end

  local active = state.active(tabpage)
  if active then
    return M.show(active.id, { tabpage = tabpage }) ~= nil
  end

  return M.create() ~= nil
end

---@param tabpage? integer
---@return integer?
function M.active_id(tabpage)
  local terminal = state.active(tabpage)
  return terminal and terminal.id or nil
end

---@param tabpage? integer
---@return TerminalsTerminal?
function M.current_or_active(tabpage)
  tabpage = tabpage or state.current_tabpage()
  local winid = window.current()
  local terminal = state.is_terminal_window(winid, tabpage) and state.window_terminal(winid, tabpage) or nil
  if terminal then
    return terminal
  end

  local bufnr = vim.api.nvim_get_current_buf()
  terminal = state.find_terminal_by_bufnr(bufnr, tabpage)
  if terminal then
    return terminal
  end
  return state.active(tabpage)
end

M.send = send.send
M.send_current_line = send.send_current_line
M.send_current_line_as_bracketed_paste = send.send_current_line_as_bracketed_paste
M.send_range = send.send_range
M.send_visual_selection = send.send_visual_selection
M.send_visual_selection_as_bracketed_paste = send.send_visual_selection_as_bracketed_paste

---@param step integer
function M.cycle(step)
  local tabpage = state.current_tabpage()
  local terminals = state.list(tabpage)
  if #terminals == 0 then
    return
  end

  local current_win = window.current()
  local winid = state.is_terminal_window(current_win, tabpage) and current_win or window.terminal_window(tabpage)
  local current = winid and state.window_terminal(winid, tabpage) or state.active(tabpage)
  local current_index = 1
  if current then
    for index, terminal in ipairs(terminals) do
      if terminal.id == current.id then
        current_index = index
        break
      end
    end
  end

  local next_index = ((current_index - 1 + step) % #terminals) + 1
  M.show(terminals[next_index].id, { tabpage = tabpage, winid = winid })
end

M.pick = picker.pick

---@param id integer
---@param title_text string
---@return boolean
function M.rename(id, title_text)
  local terminal = state.find_terminal(id)
  if not terminal then
    return false
  end
  terminal.title = title_text
  require('terminals.ui.winbar').refresh_all()
  return true
end

M.handle_term_request = title.handle_term_request

---@param id integer
---@param opts? { tabpage?: integer, winid?: integer }
---@return boolean
function M.close(id, opts)
  opts = opts or {}
  local tabpage = opts.tabpage or state.current_tabpage()
  local terminal = state.find_terminal(id, tabpage)
  if not terminal then
    return false
  end

  local winid = opts.winid or window.terminal_window(tabpage)
  local shown_window_ids = {}
  for _, terminal_winid in ipairs(state.terminal_windows(tabpage)) do
    local shown = state.window_terminal(terminal_winid, tabpage)
    if shown and shown.id == id then
      shown_window_ids[#shown_window_ids + 1] = terminal_winid
    end
  end
  state.remove_terminal(id, tabpage)

  local active = state.active(tabpage)
  if is_quitting() then
    active = nil
  end

  if active then
    for _, terminal_winid in ipairs(shown_window_ids) do
      if vim.api.nvim_win_is_valid(terminal_winid) then
        M.show(active.id, { tabpage = tabpage, winid = terminal_winid })
      end
    end
  elseif (not is_quitting()) and winid and vim.api.nvim_win_is_valid(winid) then
    active = M.create({
      cwd = terminal.cwd,
      tabpage = tabpage,
      winid = winid,
    })
    for _, terminal_winid in ipairs(shown_window_ids) do
      if terminal_winid ~= winid and vim.api.nvim_win_is_valid(terminal_winid) then
        M.show(active.id, { tabpage = tabpage, winid = terminal_winid })
      end
    end
  end

  if vim.api.nvim_buf_is_valid(terminal.bufnr) then
    pcall(vim.api.nvim_buf_delete, terminal.bufnr, { force = true })
  end

  title.ensure_timer()
  require('terminals.ui.winbar').refresh_all()
  return true
end

function M.cleanup_for_quit()
  title.stop_timer()
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local terminals = {}
    for _, terminal in ipairs(state.list(tabpage)) do
      terminals[#terminals + 1] = terminal
    end
    for _, terminal in ipairs(terminals) do
      if terminal.job_id and terminal.job_id > 0 then
        pcall(vim.fn.jobstop, terminal.job_id)
      end
    end
  end
end

M.sync_current_buffer = window.sync_current_buffer
M.register_or_reject_terminal_window = window.register_or_reject_terminal_window
M.register_cloned_terminal_window = window.register_cloned_terminal_window
M.prune_invalid_buffers = window.prune_invalid_buffers
M.open_split = window.open_split

return M
