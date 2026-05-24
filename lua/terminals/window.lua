local state = require('terminals.state')

local M = {}

---@param tabpage? integer
---@return TerminalsConfig
local function config(tabpage)
  tabpage = tabpage or state.current_tabpage()
  return vim.tbl_deep_extend('force', {}, require('terminals').config, state.tab_policy(tabpage))
end

---@return integer
function M.current()
  return vim.api.nvim_get_current_win()
end

---@param tabpage? integer
---@return integer?
function M.terminal_window(tabpage)
  return state.terminal_window(tabpage or state.current_tabpage())
end

---@param winid? integer
---@param tabpage? integer
---@return boolean
function M.is_terminal_window(winid, tabpage)
  winid = winid or M.current()
  tabpage = tabpage or vim.api.nvim_win_get_tabpage(winid)
  return state.is_terminal_window(winid, tabpage)
end

---@param winid? integer
function M.setup_options(winid)
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
function M.set_locked(winid, locked)
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].winfixbuf = locked
    if locked then
      M.setup_options(winid)
    end
  end
end

---@return integer
function M.create_placeholder_buffer()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = 'wipe'
  return bufnr
end

---@generic T
---@param winid? integer
---@param fn fun(): T
---@return T
function M.unlocked(winid, fn)
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
local function saved_layout(tabpage)
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
function M.snapshot_layout(winid, tabpage)
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
local function resolve_dimension(value, total)
  if type(value) == 'number' and value > 0 and value <= 1 then
    return math.max(1, math.floor(total * value))
  end
  return math.max(1, math.floor(value))
end

---@param tabpage integer
---@return integer
local function create_split_window(tabpage)
  local cfg = config(tabpage)
  local layout = saved_layout(tabpage)
  local position = cfg.terminal_position
  local height = layout and layout.height or resolve_dimension(cfg.terminal_height, vim.o.lines - vim.o.cmdheight)
  local width = layout and layout.width or resolve_dimension(cfg.terminal_width, vim.o.columns)

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

  return M.current()
end

---@param tabpage integer
---@return integer
local function create_float_window(tabpage)
  local cfg = config(tabpage)
  local float = cfg.float or {}
  local layout = saved_layout(tabpage)
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight
  local width = layout and layout.width or resolve_dimension(float.width or 0.9, editor_width)
  local height = layout and layout.height or resolve_dimension(float.height or 0.3, editor_height)
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
function M.ensure(tabpage)
  tabpage = tabpage or state.current_tabpage()
  local winid = M.terminal_window(tabpage)
  if winid then
    return winid
  end

  local original_tab = state.current_tabpage()
  local original_win = M.current()
  if original_tab ~= tabpage then
    vim.api.nvim_set_current_tabpage(tabpage)
  end

  if config(tabpage).terminal_position == 'float' then
    winid = create_float_window(tabpage)
  else
    winid = create_split_window(tabpage)
  end
  state.set_terminal_window(winid, tabpage)
  M.set_locked(winid, true)

  if config(tabpage).focus_terminal_on_open then
    return winid
  end

  if vim.api.nvim_win_is_valid(original_win) and vim.api.nvim_win_get_tabpage(original_win) == original_tab then
    vim.api.nvim_set_current_win(original_win)
  end
  return winid
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
      M.snapshot_layout(winid, tabpage)
    end
    if vim.api.nvim_win_is_valid(winid) then
      M.unlocked(winid, function()
        vim.api.nvim_win_set_buf(winid, M.create_placeholder_buffer())
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
  winid = winid or M.current()
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
  M.set_locked(winid, false)
  vim.api.nvim_win_call(winid, function()
    vim.cmd('new')
  end)
  require('terminals.ui.winbar').refresh_all()
  return true
end

function M.sync_current_buffer()
  local tabpage = state.current_tabpage()
  local winid = M.current()
  local bufnr = vim.api.nvim_get_current_buf()
  local terminal = state.find_terminal_by_bufnr(bufnr, tabpage)
  if terminal then
    if state.is_terminal_window(winid, tabpage) then
      state.set_window_terminal(winid, terminal.id, tabpage)
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
  winid = winid or M.current()
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
    require('terminals.terminal').show(current.id, { tabpage = tabpage, winid = winid })
  end
  M.set_locked(winid, true)
  return true
end

---@param tabpage? integer
---@param winid? integer
---@param bufnr? integer
---@return boolean
function M.register_cloned_terminal_window(tabpage, winid, bufnr)
  tabpage = tabpage or state.current_tabpage()
  winid = winid or M.current()
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if state.is_terminal_window(winid, tabpage) then
    return false
  end

  local current = state.find_terminal_by_bufnr(bufnr, tabpage)
  if not current then
    return false
  end

  for _, candidate in ipairs(state.terminal_windows(tabpage)) do
    if candidate ~= winid and vim.api.nvim_win_is_valid(candidate) and vim.api.nvim_win_get_buf(candidate) == bufnr then
      state.add_terminal_window(winid, tabpage)
      state.set_window_terminal(winid, current.id, tabpage)
      M.set_locked(winid, true)
      require('terminals.ui.winbar').refresh_all()
      return true
    end
  end

  return false
end

function M.prune_invalid_buffers()
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    if not M.terminal_window(tabpage) then
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

---@param opts? { tabpage?: integer, vertical?: boolean }
---@return integer?
function M.open_split(opts)
  opts = opts or {}
  local terminal_api = require('terminals.terminal')
  local tabpage = opts.tabpage or state.current_tabpage()
  local active = state.active(tabpage)

  if not active then
    active = terminal_api.create({ tabpage = tabpage })
  end

  local current = M.current()
  local source = state.is_terminal_window(current, tabpage) and current or M.terminal_window(tabpage)
  if not source then
    terminal_api.show(active.id, { tabpage = tabpage })
    source = M.terminal_window(tabpage)
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
    terminal_api.show(source_terminal.id, { tabpage = tabpage, winid = created })
  end
  M.set_locked(created, true)
  pcall(vim.api.nvim_set_current_win, created)
  require('terminals.ui.winbar').refresh_all()
  return created
end

return M
