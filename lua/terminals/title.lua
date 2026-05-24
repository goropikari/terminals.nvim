local state = require('terminals.state')

local M = {}

local pending_bufs = {}
local pending_sync = false
local title_sync_timer = nil
local uv = vim.uv or vim.loop

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
function M.for_command(cmd, tabpage)
  if cmd and cmd ~= '' then
    return vim.fn.fnamemodify(cmd, ':t')
  end
  local cfg = config(tabpage)
  local shell = cfg.shell or vim.o.shell
  return vim.fn.fnamemodify(shell, ':t')
end

---@param title? string
---@return string?
local function normalize(title)
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
---@return string?
local function parse_osc(sequence)
  if type(sequence) ~= 'string' then
    return nil
  end

  if not sequence:match('^\27%][02];') then
    return nil
  end

  local title = sequence:gsub('^\27%][02];', '')
  title = title:gsub('\7$', '')
  title = title:gsub('\27\\$', '')

  if title:match('^[^%s|]+%s+|%s+') then
    title = title:gsub('^[^%s|]+%s+|%s+', '')
  end

  return normalize(title)
end

---@param bufnr integer
---@param title string
---@return boolean
local function apply(bufnr, title)
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
local function sync_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local terminal = state.find_terminal_by_bufnr(bufnr)
  if not terminal then
    return false
  end

  local ok, raw_title = pcall(vim.api.nvim_buf_get_var, bufnr, 'term_title')
  local title = ok and normalize(raw_title) or nil
  if not title then
    return false
  end

  return apply(bufnr, title)
end

local function sync_all()
  local changed = false
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    for _, terminal in ipairs(state.list(tabpage)) do
      changed = sync_buffer(terminal.bufnr) or changed
    end
  end
  return changed
end

function M.stop_timer()
  if title_sync_timer then
    title_sync_timer:stop()
    title_sync_timer:close()
    title_sync_timer = nil
  end
end

function M.ensure_timer()
  if not config().osc_title then
    M.stop_timer()
    return
  end
  if not has_managed_terminals() then
    M.stop_timer()
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
        M.stop_timer()
        return
      end
      sync_all()
    end)
  )
end

local function flush_pending()
  pending_sync = false
  local pending = pending_bufs
  pending_bufs = {}

  for bufnr, attempts in pairs(pending) do
    if not sync_buffer(bufnr) and vim.api.nvim_buf_is_valid(bufnr) and attempts < 5 then
      pending_bufs[bufnr] = attempts + 1
    end
  end

  if next(pending_bufs) then
    pending_sync = true
    vim.defer_fn(flush_pending, 20)
  end
end

---@param bufnr integer
---@param sequence? string
---@return boolean
function M.handle_term_request(bufnr, sequence)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local title = parse_osc(sequence)
  if title then
    vim.b[bufnr].term_title = title
    apply(bufnr, title)
  end

  pending_bufs[bufnr] = 1
  if pending_sync then
    return true
  end

  pending_sync = true
  vim.defer_fn(flush_pending, 20)
  return true
end

return M
