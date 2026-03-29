local state = require('terminals.state')

---@class TerminalsWinbarLayoutEntry
---@field id integer
---@field index integer
---@field start_col integer
---@field end_col integer

local M = {
  layouts = {},
}

---@param title string
---@return string
local function sanitize_label_text(title)
  title = title:gsub('%%', '%%%%')
  title = title:gsub('[%c]', ' ')
  return vim.trim(title)
end

---@param terminal TerminalsTerminal
---@param active boolean
---@param dragging boolean?
---@return string
local function render_label(terminal, active, dragging)
  local hl = active and '%#TerminalsWinbarActive#' or '%#TerminalsWinbarInactive#'
  if dragging then
    hl = '%#TerminalsWinbarDrag#'
  end
  return string.format('%s %s ', hl, sanitize_label_text(terminal.title))
end

---@param tabpage integer
---@return TerminalsTerminal[]
local function tabs_for_current_tabpage(tabpage)
  return state.list(tabpage)
end

---@return string
local function add_button()
  return '%#TerminalsWinbarButton#%@v:lua.TerminalsWinbarAdd@ + %X'
end

---@return TerminalsWinbarLayoutEntry[]
local function current_layout()
  local winid = vim.api.nvim_get_current_win()
  local tabpage = vim.api.nvim_win_get_tabpage(winid)
  local entries = {}
  local col = 1
  local drag = state.drag(tabpage)

  for index, terminal in ipairs(tabs_for_current_tabpage(tabpage)) do
    local active = state.window_terminal(winid, tabpage) and state.window_terminal(winid, tabpage).id == terminal.id
    local dragging = drag and drag.source_id == terminal.id
    local label = render_label(terminal, active, dragging)
    local width = vim.fn.strdisplaywidth(label:gsub('%%#.-#', ''))
    entries[#entries + 1] = {
      id = terminal.id,
      index = index,
      start_col = col,
      end_col = col + width - 1,
    }
    col = col + width
  end

  M.layouts[winid] = entries
  return entries
end

---@return string
local function render_tabs()
  local chunks = {}
  local winid = vim.api.nvim_get_current_win()
  local tabpage = vim.api.nvim_win_get_tabpage(winid)
  local active = state.window_terminal(winid, tabpage)
  local drag = state.drag(tabpage)

  for _, terminal in ipairs(tabs_for_current_tabpage(tabpage)) do
    local label = render_label(terminal, active and active.id == terminal.id, drag and drag.source_id == terminal.id)
    chunks[#chunks + 1] = string.format('%%%d@v:lua.TerminalsWinbarClick@%s%%X', terminal.id, label)
  end

  return table.concat(chunks, '')
end

---@return string
function M.render()
  current_layout()
  local tabpage = vim.api.nvim_get_current_tabpage()
  if #tabs_for_current_tabpage(tabpage) == 0 then
    return ''
  end
  return table.concat({
    '%#TerminalsWinbarFill#',
    render_tabs(),
    '%#TerminalsWinbarFill#',
    '%=',
    add_button(),
  }, '')
end

---@param winid integer
---@return TerminalsWinbarLayoutEntry[]
function M.layout_for_win(winid)
  return M.layouts[winid] or {}
end

---@param winid integer
---@param col integer
---@return integer?
function M.target_index_for_position(winid, col)
  local layout = M.layout_for_win(winid)
  if #layout == 0 then
    return nil
  end

  for _, entry in ipairs(layout) do
    if col >= entry.start_col and col <= entry.end_col then
      local midpoint = math.floor((entry.start_col + entry.end_col) / 2)
      if col <= midpoint then
        return entry.index
      end
      return entry.index + 1
    end
  end

  local last = layout[#layout]
  if col > last.end_col then
    return #layout + 1
  end
  return 1
end

---@param winid integer
function M.refresh_window(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local tabpage = vim.api.nvim_win_get_tabpage(winid)
  local tab = state.get_tab(tabpage)
  if not state.is_terminal_window(winid, tabpage) or #tab.terminals == 0 then
    vim.wo[winid].winbar = ''
    return
  end

  vim.wo[winid].winbar = "%{%v:lua.require'terminals.ui.winbar'.render()%}"
end

---@param terminal_id integer
---@param tabpage? integer
function M.refresh_terminal_windows(terminal_id, tabpage)
  state.prune()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) then
      local current_tabpage = vim.api.nvim_win_get_tabpage(winid)
      if (not tabpage or current_tabpage == tabpage) and state.is_terminal_window(winid, current_tabpage) then
        local current = state.window_terminal(winid, current_tabpage)
        if current and current.id == terminal_id then
          M.refresh_window(winid)
        end
      end
    end
  end
  pcall(vim.cmd, 'redrawstatus')
end

function M.refresh_all()
  require('terminals.terminal').prune_invalid_buffers()
  state.prune()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    M.refresh_window(winid)
  end
  pcall(vim.cmd, 'redrawstatus')
end

return M
