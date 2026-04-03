local state = require('terminals.state')

---@class TerminalsConfig
---@field auto_close_on_exit boolean
---@field focus_terminal_on_open boolean
---@field keymaps table<string, table|false>
---@field osc_title boolean
---@field shell? string
---@field start_in_insert boolean
---@field terminal_position string
---@field terminal_height integer
---@field terminal_width integer
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

---@class TerminalsPickOpts
---@field backend? '"ui_select"'|'"telescope"'|string
---@field prompt? string
---@field preview_max_lines? integer
---@field tabpage? integer

local M = {}
local pending_title_bufs = {}
local pending_title_sync = false
local uv = vim.uv or vim.loop
local title_sync_timer = nil

---@param tabpage? integer
---@return TerminalsConfig
local function config(tabpage)
  return vim.tbl_deep_extend('force', {}, require('terminals').config, state.tab_policy(tabpage))
end

local wheel_passthrough = false

local function is_quitting()
  return require('terminals')._is_quitting == true
end

---@return integer
local function current_window()
  return vim.api.nvim_get_current_win()
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

  vim.keymap.set('n', '<LeftDrag>', function()
    require('terminals.ui.drag').update()
  end, opts)

  vim.keymap.set('n', '<LeftRelease>', function()
    require('terminals.ui.drag').finish()
  end, opts)

  vim.keymap.set('t', '<LeftDrag>', function()
    require('terminals.ui.drag').update()
  end, opts)

  vim.keymap.set('t', '<LeftRelease>', function()
    require('terminals.ui.drag').finish()
  end, opts)

  vim.keymap.set({ 'n', 't' }, '<ScrollWheelUp>', function()
    return require('terminals.terminal').handle_scroll_wheel('up')
  end, wheel_opts)

  vim.keymap.set({ 'n', 't' }, '<ScrollWheelDown>', function()
    return require('terminals.terminal').handle_scroll_wheel('down')
  end, wheel_opts)
end

---@param tabpage? integer
---@return integer?
local function terminal_window(tabpage)
  return state.terminal_window(tabpage or state.current_tabpage())
end

---@param winid? integer
---@param tabpage? integer
---@return boolean
function M.is_terminal_window(winid, tabpage)
  winid = winid or current_window()
  tabpage = tabpage or vim.api.nvim_win_get_tabpage(winid)
  return state.is_terminal_window(winid, tabpage)
end

---@param winid? integer
local function setup_terminal_window_options(winid)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    return
  end
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = 'no'
  vim.wo[winid].foldcolumn = '0'
  vim.wo[winid].winfixbuf = true
end

---@param winid? integer
---@param locked boolean
local function set_terminal_window_locked(winid, locked)
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].winfixbuf = locked
    if locked then
      setup_terminal_window_options(winid)
    end
  end
end

---@return integer
local function create_placeholder_buffer()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = 'wipe'
  return bufnr
end

---@generic T
---@param winid? integer
---@param fn fun(): T
---@return T
local function with_terminal_window_unlocked(winid, fn)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    return fn()
  end

  local previous = vim.wo[winid].winfixbuf
  vim.wo[winid].winfixbuf = false
  local ok, result = pcall(fn)
  if vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].winfixbuf = previous
  end
  if not ok then
    error(result)
  end
  return result
end

---@param tabpage? integer
---@return TerminalsWindowLayout?
local function saved_window_layout(tabpage)
  local layout = state.window_layout(tabpage)
  local position = config(tabpage).terminal_position
  if layout and layout.position == position then
    return layout
  end
  return nil
end

---@param winid? integer
---@param tabpage? integer
---@return TerminalsWindowLayout?
local function snapshot_window_layout(winid, tabpage)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    return nil
  end

  tabpage = tabpage or vim.api.nvim_win_get_tabpage(winid)
  local cfg = config(tabpage)
  local layout = {
    position = cfg.terminal_position,
    width = vim.api.nvim_win_get_width(winid),
    height = vim.api.nvim_win_get_height(winid),
  }

  if cfg.terminal_position == 'float' then
    local win_config = vim.api.nvim_win_get_config(winid)
    layout.row = win_config.row
    layout.col = win_config.col
  end

  state.set_window_layout(layout, tabpage)
  return layout
end

---@param value number
---@param total integer
---@return integer
local function resolve_float_size(value, total)
  if type(value) == 'number' and value > 0 and value <= 1 then
    return math.max(1, math.floor(total * value))
  end
  return math.max(1, math.floor(value))
end

---@param tabpage integer
---@return integer
local function create_split_window(tabpage)
  local cfg = config(tabpage)
  local layout = saved_window_layout(tabpage)
  local position = cfg.terminal_position
  local height = layout and layout.height or cfg.terminal_height
  local width = layout and layout.width or cfg.terminal_width

  if position == 'top' then
    vim.cmd(string.format('topleft %dsplit', height))
  elseif position == 'left' then
    vim.cmd('topleft vsplit')
    vim.cmd(string.format('vertical resize %d', width))
  elseif position == 'right' then
    vim.cmd('botright vsplit')
    vim.cmd(string.format('vertical resize %d', width))
  else
    vim.cmd(string.format('botright %dsplit', height))
  end

  return current_window()
end

---@param tabpage integer
---@return integer
local function create_float_window(tabpage)
  local cfg = config(tabpage)
  local float = cfg.float or {}
  local layout = saved_window_layout(tabpage)
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight
  local width = layout and layout.width or resolve_float_size(float.width or 0.9, editor_width)
  local height = layout and layout.height or resolve_float_size(float.height or 0.3, editor_height)
  local row = layout and layout.row or float.row
  local col = layout and layout.col or float.col

  if row == nil then
    row = math.floor((editor_height - height) / 2)
  end
  if col == nil then
    col = math.floor((editor_width - width) / 2)
  end

  local placeholder = vim.api.nvim_create_buf(false, true)
  vim.bo[placeholder].bufhidden = 'wipe'

  return vim.api.nvim_open_win(placeholder, cfg.focus_terminal_on_open, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = float.border or 'rounded',
  })
end

---@param tabpage? integer
---@return integer?
local function ensure_terminal_window(tabpage)
  tabpage = tabpage or state.current_tabpage()
  local winid = terminal_window(tabpage)
  if winid then
    return winid
  end

  local original_tab = state.current_tabpage()
  local original_win = current_window()
  if original_tab ~= tabpage then
    vim.api.nvim_set_current_tabpage(tabpage)
  end

  if config(tabpage).terminal_position == 'float' then
    winid = create_float_window(tabpage)
  else
    winid = create_split_window(tabpage)
  end
  state.set_terminal_window(winid, tabpage)
  set_terminal_window_locked(winid, true)

  if config(tabpage).focus_terminal_on_open then
    return winid
  end

  if vim.api.nvim_win_is_valid(original_win) and vim.api.nvim_win_get_tabpage(original_win) == original_tab then
    vim.api.nvim_set_current_win(original_win)
  end
  return winid
end

---@param cmd? string
---@param tabpage? integer
---@return string
local function shell_for_command(cmd, tabpage)
  if cmd and cmd ~= '' then
    return cmd
  end
  return config(tabpage).shell or vim.o.shell
end

---@param cmd? string
---@param cwd string
---@param tabpage? integer
---@return string
local function title_for_command(cmd, cwd, tabpage)
  if cmd and cmd ~= '' then
    return vim.fn.fnamemodify(cmd, ':t')
  end
  local cfg = config(tabpage)
  local shell = cfg.shell or vim.o.shell
  return vim.fn.fnamemodify(shell, ':t')
end

---@param title? string
---@return string?
local function normalize_term_title(title)
  if type(title) ~= 'string' then
    return nil
  end
  title = vim.trim(title)
  if title == '' or title:match('^term://') then
    return nil
  end
  return title
end

---@param sequence? string
local function parse_osc_title(sequence)
  if type(sequence) ~= 'string' then
    return nil
  end

  if not sequence:match('^\27%][02];') then
    return nil
  end

  local title = sequence:gsub('^\27%][02];', '')
  title = title:gsub('\7$', '')
  title = title:gsub('\27\\$', '')

  -- If using Zellij, the title often looks like "session_name | current_title"
  -- We want to strip the session name prefix.
  if title:match('^[^%s|]+%s+|%s+') then
    title = title:gsub('^[^%s|]+%s+|%s+', '')
  end

  return normalize_term_title(title)
end

---@param bufnr integer
---@param title string
---@return boolean
local function apply_terminal_title(bufnr, title)
  local terminal, _, tabpage = state.find_terminal_by_bufnr(bufnr)
  if not terminal or title == terminal.title then
    return false
  end

  terminal.title = title
  require('terminals.ui.winbar').refresh_terminal_windows(terminal.id, tabpage)
  return true
end

---@return boolean
local function has_managed_terminals()
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    if #state.list(tabpage) > 0 then
      return true
    end
  end
  return false
end

---@param bufnr integer
---@return boolean
local function sync_buffer_title(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local terminal, _, tabpage = state.find_terminal_by_bufnr(bufnr)
  if not terminal then
    return false
  end

  local ok, raw_title = pcall(vim.api.nvim_buf_get_var, bufnr, 'term_title')
  local title = ok and normalize_term_title(raw_title) or nil
  if not title then
    return false
  end

  return apply_terminal_title(bufnr, title)
end

local function sync_all_titles()
  local changed = false
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    for _, terminal in ipairs(state.list(tabpage)) do
      changed = sync_buffer_title(terminal.bufnr) or changed
    end
  end
  return changed
end

local function stop_title_sync_timer()
  if title_sync_timer then
    title_sync_timer:stop()
    title_sync_timer:close()
    title_sync_timer = nil
  end
end

local function ensure_title_sync_timer()
  if not config().osc_title then
    stop_title_sync_timer()
    return
  end
  if not has_managed_terminals() then
    stop_title_sync_timer()
    return
  end
  if title_sync_timer then
    return
  end

  title_sync_timer = uv.new_timer()
  if not title_sync_timer then
    return
  end

  title_sync_timer:start(
    250,
    250,
    vim.schedule_wrap(function()
      if is_quitting() or not has_managed_terminals() then
        stop_title_sync_timer()
        return
      end
      sync_all_titles()
    end)
  )
end

local function flush_pending_title_sync()
  pending_title_sync = false
  local pending = pending_title_bufs
  pending_title_bufs = {}

  for bufnr, attempts in pairs(pending) do
    if not sync_buffer_title(bufnr) and vim.api.nvim_buf_is_valid(bufnr) and attempts < 5 then
      pending_title_bufs[bufnr] = attempts + 1
    end
  end

  if next(pending_title_bufs) then
    pending_title_sync = true
    vim.defer_fn(flush_pending_title_sync, 20)
  end
end

---@param cmd? string
---@param terminal_id? integer
---@param tabpage? integer
---@return string
local function shell_for_command(cmd, terminal_id, tabpage)
  if cmd and cmd ~= '' then
    return cmd
  end

  local cfg = config(tabpage)
  local backend = cfg.backend or 'none'

  if backend == 'zellij' and terminal_id then
    local backend_cfg = cfg.backends and cfg.backends.zellij or {}
    local hash = state.get_cwd_hash()
    -- Format: <hash>_<terminal_id> (e.g., 3bb414d0_1)
    local session_name = string.format('%s_%d', hash, terminal_id)
    local config_path = state.zellij_config_path(backend_cfg.config_path)
    return string.format('zellij --config %s attach -c %s', config_path, session_name)
  end

  if backend == 'tmux' and terminal_id then
    local backend_cfg = cfg.backends and cfg.backends.tmux or {}
    local hash = state.get_cwd_hash()
    local base_session = hash
    local client_session = string.format('%s_%d', hash, terminal_id)
    local window_name = tostring(terminal_id)
    local config_path = state.tmux_config_path(backend_cfg.config_path)

    -- Improved robust command for grouped sessions:
    -- 1. Create base session if missing
    -- 2. Create window in the group if missing
    -- 3. Create a unique client session in the same group if missing
    -- 4. Switch the client session to the specific window
    -- 5. Attach to the unique client session
    return string.format(
      'sh -c "tmux -f %s has-session -t %s 2>/dev/null || tmux -f %s new-session -d -s %s -n %s; '
        .. 'tmux -f %s new-window -t %s -n %s 2>/dev/null; '
        .. 'tmux -f %s has-session -t %s 2>/dev/null || tmux -f %s new-session -d -t %s -s %s; '
        .. 'tmux -f %s select-window -t %s:%s; '
        .. 'tmux -f %s attach-session -t %s"',
      config_path,
      base_session,
      config_path,
      base_session,
      window_name,
      config_path,
      base_session,
      window_name,
      config_path,
      client_session,
      config_path,
      base_session,
      client_session,
      config_path,
      client_session,
      window_name,
      config_path,
      client_session
    )
  end

  return cfg.shell or vim.o.shell
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
    winid = ensure_terminal_window(tabpage)
  else
    state.add_terminal_window(winid, tabpage)
  end

  local bufnr = with_terminal_window_unlocked(winid, function()
    vim.api.nvim_set_current_win(winid)
    vim.cmd('enew')
    return vim.api.nvim_get_current_buf()
  end)
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].bufhidden = 'hide'
  vim.bo[bufnr].filetype = 'terminal'
  attach_mouse_mappings(bufnr)

  local terminal_id = state.next_id()
  local term_opts = {
    cwd = cwd,
    env = {
      ZELLIJ_SKIP_CHECK_UPDATE = 'true',
    },
  }
  local job_id = vim.fn.termopen(shell_for_command(cmd, terminal_id, tabpage), term_opts)

  local terminal = {
    id = terminal_id,
    bufnr = bufnr,
    job_id = job_id,
    title = opts.title or title_for_command(cmd, cwd, tabpage),
    cwd = cwd,
    alive = true,
  }

  state.add_terminal(terminal, tabpage)
  state.set_window_terminal(winid, terminal.id, tabpage)
  with_terminal_window_unlocked(winid, function()
    vim.api.nvim_win_set_buf(winid, bufnr)
  end)
  set_terminal_window_locked(winid, true)
  require('terminals.ui.winbar').refresh_all()
  ensure_title_sync_timer()

  if config(tabpage).start_in_insert then
    vim.cmd('startinsert')
  end

  return terminal
end

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

  local winid = opts.winid or ensure_terminal_window(tabpage)
  state.add_terminal_window(winid, tabpage)
  state.set_window_terminal(winid, terminal.id, tabpage)
  with_terminal_window_unlocked(winid, function()
    vim.api.nvim_win_set_buf(winid, terminal.bufnr)
  end)
  set_terminal_window_locked(winid, true)
  if config(tabpage).focus_terminal_on_open and vim.api.nvim_get_current_win() ~= winid then
    vim.api.nvim_set_current_win(winid)
  end
  require('terminals.ui.winbar').refresh_all()

  if config(tabpage).start_in_insert and vim.bo[terminal.bufnr].buftype == 'terminal' then
    vim.cmd('startinsert')
  end

  return terminal
end

---@param tabpage? integer
---@param opts? { snapshot?: boolean }
---@return boolean
function M.hide(tabpage, opts)
  opts = opts or {}
  tabpage = tabpage or state.current_tabpage()
  local winids = state.terminal_windows(tabpage)
  if #winids == 0 then
    return false
  end

  state.set_terminal_window(nil, tabpage)
  local ok = true
  for index, winid in ipairs(winids) do
    if opts.snapshot ~= false and index == 1 then
      snapshot_window_layout(winid, tabpage)
    end
    if vim.api.nvim_win_is_valid(winid) then
      with_terminal_window_unlocked(winid, function()
        vim.api.nvim_win_set_buf(winid, create_placeholder_buffer())
      end)
    end
    ok = pcall(vim.api.nvim_win_close, winid, false) and ok
  end
  require('terminals.ui.winbar').refresh_all()
  return ok
end

---@param winid? integer
---@param opts? { tabpage?: integer, snapshot?: boolean }
---@return boolean
function M.close_window(winid, opts)
  opts = opts or {}
  winid = winid or current_window()
  if not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  local tabpage = opts.tabpage or vim.api.nvim_win_get_tabpage(winid)
  if not state.is_terminal_window(winid, tabpage) then
    return false
  end

  local managed = state.terminal_windows(tabpage)
  if #managed > 1 then
    state.remove_terminal_window(winid, tabpage)
    local ok = pcall(vim.api.nvim_win_close, winid, false)
    require('terminals.ui.winbar').refresh_all()
    return ok
  end

  local all_wins = vim.api.nvim_tabpage_list_wins(tabpage)
  if #all_wins > 1 then
    return M.hide(tabpage, opts)
  end

  state.set_terminal_window(nil, tabpage)
  set_terminal_window_locked(winid, false)
  vim.api.nvim_win_call(winid, function()
    vim.cmd('new')
  end)
  require('terminals.ui.winbar').refresh_all()
  return true
end

---@return boolean
function M.toggle()
  local tabpage = state.current_tabpage()
  if terminal_window(tabpage) then
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
  local winid = current_window()
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

---@param text string|string[]
---@param opts? TerminalsSendOpts
---@return boolean
function M.send(text, opts)
  opts = opts or {}
  local terminal = opts.id and state.find_terminal(opts.id, opts.tabpage) or M.current_or_active(opts.tabpage)
  if not terminal or not terminal.job_id or terminal.job_id <= 0 then
    return false
  end

  local payload = text
  if type(payload) == 'table' then
    payload = table.concat(payload, '\n')
  end
  if type(payload) ~= 'string' or payload == '' then
    return false
  end
  if opts.newline ~= false and not payload:match('\n$') then
    payload = payload .. '\n'
  end

  vim.fn.chansend(terminal.job_id, payload)
  return true
end

---@param opts? TerminalsSendOpts
---@return boolean
function M.send_current_line(opts)
  local line = vim.api.nvim_get_current_line()
  return M.send(line, opts)
end

---@param start_line? integer
---@param end_line? integer
---@param opts? TerminalsSendOpts
---@return boolean
function M.send_range(start_line, end_line, opts)
  if not start_line or not end_line then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  if #lines == 0 then
    return false
  end
  return M.send(lines, opts)
end

---@param opts? TerminalsSendOpts
---@return boolean
function M.send_visual_selection(opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.fn.visualmode()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row, start_col = start_pos[2], start_pos[3]
  local end_row, end_col = end_pos[2], end_pos[3]

  if start_row == 0 or end_row == 0 then
    return false
  end
  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)
  if #lines == 0 then
    return false
  end

  if mode == 'v' or mode == '\22' then
    lines[1] = string.sub(lines[1], start_col, #lines[1])
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  return M.send(lines, opts)
end

---@param step integer
function M.cycle(step)
  local tabpage = state.current_tabpage()
  local terminals = state.list(tabpage)
  if #terminals == 0 then
    return
  end

  local winid = state.is_terminal_window(current_window(), tabpage) and current_window() or terminal_window(tabpage)
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

---@param tabpage integer
---@return { id: integer, title: string, cwd: string, bufnr: integer, index: integer, active: boolean }[]
local function picker_items(tabpage)
  local active = state.active(tabpage)
  local items = {}

  for index, terminal in ipairs(state.list(tabpage)) do
    items[#items + 1] = {
      id = terminal.id,
      title = terminal.title,
      cwd = terminal.cwd,
      bufnr = terminal.bufnr,
      index = index,
      active = active and active.id == terminal.id or false,
    }
  end

  return items
end

---@param item { title: string, cwd: string, active: boolean }
---@return string
local function picker_label(item)
  local active = item.active and '* ' or '  '
  local cwd = item.cwd and vim.fn.fnamemodify(item.cwd, ':t') or ''
  if cwd == '' then
    return string.format('%s%s', active, item.title)
  end
  return string.format('%s%s [%s]', active, item.title, cwd)
end

---@param items table[]
---@param opts TerminalsPickOpts
---@return boolean
local function pick_with_ui_select(items, opts)
  vim.ui.select(items, {
    prompt = opts.prompt or 'Select terminal',
    format_item = picker_label,
  }, function(choice)
    if choice then
      M.show(choice.id, { tabpage = opts.tabpage })
    end
  end)
  return true
end

---@param bufnr? integer
---@param max_lines? integer
---@return string[]
local function preview_terminal_lines(bufnr, max_lines)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start_line = math.max(0, line_count - (max_lines or 200))
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, line_count, false)

  while #lines > 0 and lines[#lines] == '' do
    table.remove(lines)
  end

  return lines
end

---@param items table[]
---@param opts TerminalsPickOpts
---@return boolean
local function pick_with_telescope(items, opts)
  local ok_pickers, pickers = pcall(require, 'telescope.pickers')
  local ok_finders, finders = pcall(require, 'telescope.finders')
  local ok_config, telescope_config = pcall(require, 'telescope.config')
  local ok_actions, actions = pcall(require, 'telescope.actions')
  local ok_action_state, action_state = pcall(require, 'telescope.actions.state')
  local ok_previewers, previewers = pcall(require, 'telescope.previewers')
  local ok_preview_utils, preview_utils = pcall(require, 'telescope.previewers.utils')

  if not (ok_pickers and ok_finders and ok_config and ok_actions and ok_action_state and ok_previewers and ok_preview_utils) then
    return false
  end

  pickers
    .new(opts, {
      prompt_title = opts.prompt or 'Select terminal',
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return {
            value = item,
            display = picker_label(item),
            ordinal = string.format('%s %s %s %d', item.title, item.cwd or '', item.active and 'active' or '', item.index),
          }
        end,
      }),
      previewer = previewers.new_buffer_previewer({
        title = 'Terminal Output',
        define_preview = function(self, entry, status)
          local lines = preview_terminal_lines(entry.value.bufnr, opts.preview_max_lines)
          local preview_lines = #lines > 0 and lines or { '' }
          vim.bo[self.state.bufnr].filetype = 'bash'
          vim.bo[self.state.bufnr].modifiable = true
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines)
          vim.bo[self.state.bufnr].modifiable = false
          preview_utils.highlighter(self.state.bufnr, 'bash', opts)

          if status and status.preview_win and vim.api.nvim_win_is_valid(status.preview_win) then
            local preview_bufnr = vim.api.nvim_win_get_buf(status.preview_win)
            local line_count = vim.api.nvim_buf_line_count(preview_bufnr)
            if line_count > 0 then
              pcall(vim.api.nvim_win_set_cursor, status.preview_win, { line_count, 0 })
            end
            pcall(vim.api.nvim_win_call, status.preview_win, function()
              vim.cmd('normal! zb')
            end)
          end
        end,
      }),
      sorter = telescope_config.values.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection and selection.value then
            M.show(selection.value.id, { tabpage = opts.tabpage })
          end
        end)
        return true
      end,
    })
    :find()

  return true
end

---@param opts? TerminalsPickOpts
---@return boolean
function M.pick(opts)
  opts = opts or {}
  local tabpage = opts.tabpage or state.current_tabpage()
  local items = picker_items(tabpage)
  if #items == 0 then
    return false
  end

  local backend = opts.backend or 'ui_select'
  if
    backend == 'telescope'
    and pick_with_telescope(items, {
      prompt = opts.prompt,
      preview_max_lines = opts.preview_max_lines,
      tabpage = tabpage,
    })
  then
    return true
  end

  return pick_with_ui_select(items, {
    prompt = opts.prompt,
    tabpage = tabpage,
  })
end

---@param id integer
---@param title string
---@return boolean
function M.rename(id, title)
  local terminal = state.find_terminal(id)
  if not terminal then
    return false
  end
  terminal.title = title
  require('terminals.ui.winbar').refresh_all()
  return true
end

---@param bufnr integer
---@param sequence? string
---@return boolean
function M.handle_term_request(bufnr, sequence)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local title = parse_osc_title(sequence)
  if title then
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.b[bufnr].term_title = title
    end
    apply_terminal_title(bufnr, title)
  end

  pending_title_bufs[bufnr] = 1
  if pending_title_sync then
    return true
  end

  pending_title_sync = true
  vim.defer_fn(flush_pending_title_sync, 20)
  return true
end

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

  local winid = opts.winid or terminal_window(tabpage)
  state.remove_terminal(id, tabpage)

  local active = state.active(tabpage)
  if is_quitting() then
    active = nil
  end

  if active then
    for _, terminal_winid in ipairs(state.terminal_windows(tabpage)) do
      local shown = state.window_terminal(terminal_winid, tabpage)
      if shown and shown.id == id then
        M.show(active.id, { tabpage = tabpage, winid = terminal_winid })
      end
    end
  elseif (not is_quitting()) and winid and vim.api.nvim_win_is_valid(winid) then
    active = M.create({
      cwd = terminal.cwd,
      tabpage = tabpage,
      winid = winid,
    })
    for _, terminal_winid in ipairs(state.terminal_windows(tabpage)) do
      if terminal_winid ~= winid then
        M.show(active.id, { tabpage = tabpage, winid = terminal_winid })
      end
    end
  end

  if vim.api.nvim_buf_is_valid(terminal.bufnr) then
    pcall(vim.api.nvim_buf_delete, terminal.bufnr, { force = true })
  end

  ensure_title_sync_timer()
  require('terminals.ui.winbar').refresh_all()
  return true
end

function M.cleanup_for_quit()
  stop_title_sync_timer()
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

function M.sync_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local terminal = state.find_terminal_by_bufnr(bufnr, state.current_tabpage())
  if terminal then
    if state.is_terminal_window(current_window(), state.current_tabpage()) then
      state.set_window_terminal(current_window(), terminal.id, state.current_tabpage())
    end
    state.set_active(terminal.id)
  end
end

---@param tabpage? integer
---@param winid? integer
---@param bufnr? integer
---@return boolean
function M.register_or_reject_terminal_window(tabpage, winid, bufnr)
  tabpage = tabpage or state.current_tabpage()
  winid = winid or current_window()
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if state.is_terminal_window(winid, tabpage) then
    return false
  end
  if not state.find_terminal_by_bufnr(bufnr, tabpage) then
    return false
  end

  state.add_terminal_window(winid, tabpage)
  local current = state.find_terminal_by_bufnr(bufnr, tabpage) or state.active(tabpage)
  if current then
    state.set_window_terminal(winid, current.id, tabpage)
    M.show(current.id, { tabpage = tabpage, winid = winid })
  end
  set_terminal_window_locked(winid, true)
  return true
end

function M.prune_invalid_buffers()
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    if not terminal_window(tabpage) then
      state.set_terminal_window(nil, tabpage)
    end
    local terminal_ids = {}
    for _, terminal in ipairs(state.list(tabpage)) do
      terminal_ids[#terminal_ids + 1] = terminal.id
    end
    for _, terminal_id in ipairs(terminal_ids) do
      local terminal = state.find_terminal(terminal_id, tabpage)
      if terminal and not vim.api.nvim_buf_is_valid(terminal.bufnr) then
        state.remove_terminal(terminal.id, tabpage)
      end
    end
  end
end

---@param tabpage? integer
---@return TerminalsWindowLayout?
function M.snapshot_terminal_window(tabpage)
  tabpage = tabpage or state.current_tabpage()
  return snapshot_window_layout(terminal_window(tabpage), tabpage)
end

---@param data table
---@param data table
---@param opts? { show?: boolean }
function M.restore(data, opts)
  opts = opts or {}
  if not data or not data.projects then
    return
  end

  local original_tab = state.current_tabpage()
  local original_win = current_window()

  -- Restore the global next ID counter
  if data.next_terminal_id then
    state.set_next_id(data.next_terminal_id)
  end

  local current_tabpages = vim.api.nvim_list_tabpages()
  local tab_idx = 1

  -- Sort projects so they are restored in a deterministic order
  local cwds = {}
  for cwd in pairs(data.projects) do
    table.insert(cwds, cwd)
  end
  table.sort(cwds)

  for _, cwd in ipairs(cwds) do
    local project_data = data.projects[cwd]
    local tabpage = current_tabpages[tab_idx]
    tab_idx = tab_idx + 1

    if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
      -- If we have more projects than tabpages, we might skip them or
      -- just load them into the state for later access
      tabpage = original_tab
    end

    -- We need to ensure the tabpage actually switches to the project directory
    -- if it's supposed to be directory-based.
    pcall(vim.api.nvim_set_current_tabpage, tabpage)
    pcall(vim.cmd, 'tcd ' .. vim.fn.fnameescape(cwd))

    -- Initializing project state
    local project = state.get_tab(tabpage)
    project.terminals = {}
    project.active_id = nil
    project.window_layout = project_data.window_layout
    project.policy = project_data.policy or project.policy

    -- Re-create terminal buffers
    local active_id = nil
    for j, term_info in ipairs(project_data.terminals) do
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].buflisted = false
      vim.bo[bufnr].bufhidden = 'hide'
      vim.bo[bufnr].filetype = 'terminal'
      attach_mouse_mappings(bufnr)

      local terminal_id = term_info.id or state.next_id()
      local job_id = vim.api.nvim_buf_call(bufnr, function()
        return vim.fn.termopen(shell_for_command(nil, terminal_id, tabpage), {
          cwd = term_info.cwd,
          env = {
            ZELLIJ_SKIP_CHECK_UPDATE = 'true',
          },
        })
      end)

      local terminal = {
        id = terminal_id,
        bufnr = bufnr,
        job_id = job_id,
        title = term_info.title,
        cwd = term_info.cwd,
        alive = true,
      }

      state.add_terminal(terminal, tabpage)
      if j == project_data.active_index then
        active_id = terminal_id
      end
    end

    if active_id then
      state.set_active(active_id, tabpage)
    end

    -- Show if requested or if terminal window already exists
    local active = state.active(tabpage)
    if active then
      local target_win = nil
      for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if state.is_terminal_window(winid, tabpage) then
          target_win = winid
          break
        end
      end

      if not target_win and opts.show then
        target_win = ensure_terminal_window(tabpage)
      end

      if target_win then
        state.add_terminal_window(target_win, tabpage)
        state.set_window_terminal(target_win, active.id, tabpage)
        with_terminal_window_unlocked(target_win, function()
          vim.api.nvim_win_set_buf(target_win, active.bufnr)
        end)
        set_terminal_window_locked(target_win, true)
      end
    end
  end

  if vim.api.nvim_tabpage_is_valid(original_tab) then
    vim.api.nvim_set_current_tabpage(original_tab)
  end
  if vim.api.nvim_win_is_valid(original_win) then
    vim.api.nvim_set_current_win(original_win)
  end

  ensure_title_sync_timer()
  require('terminals.ui.winbar').refresh_all()
end

---@param opts? { tabpage?: integer, vertical?: boolean }
---@return integer?
function M.open_split(opts)
  opts = opts or {}
  local tabpage = opts.tabpage or state.current_tabpage()
  local active = state.active(tabpage)

  if not active then
    active = M.create({ tabpage = tabpage })
  end

  local current = current_window()
  local source = state.is_terminal_window(current, tabpage) and current or terminal_window(tabpage)
  if not source then
    M.show(active.id, { tabpage = tabpage })
    source = terminal_window(tabpage)
  end
  if not source then
    return nil
  end

  local created = nil
  local before = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    before[winid] = true
  end

  vim.api.nvim_win_call(source, function()
    vim.cmd(opts.vertical and 'belowright vsplit' or 'belowright split')
  end)

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if not before[winid] then
      created = winid
      break
    end
  end

  if not (created and vim.api.nvim_win_is_valid(created)) then
    return nil
  end

  state.add_terminal_window(created, tabpage)
  local source_terminal = state.window_terminal(source, tabpage) or active
  if source_terminal then
    state.set_window_terminal(created, source_terminal.id, tabpage)
    M.show(source_terminal.id, { tabpage = tabpage, winid = created })
  end
  set_terminal_window_locked(created, true)
  pcall(vim.api.nvim_set_current_win, created)
  require('terminals.ui.winbar').refresh_all()
  return created
end

return M
