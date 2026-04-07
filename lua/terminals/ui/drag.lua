local state = require('terminals.state')
local winbar = require('terminals.ui.winbar')

local M = {}
local DRAG_THRESHOLD_COLS = 2
local DRAG_THRESHOLD_ROWS = 0
local ghost = {
  bufnr = nil,
  winid = nil,
}

---@return { row?: integer, col?: integer }
local function mouse_position()
  local mouse = vim.fn.getmousepos()
  return {
    row = mouse.screenrow,
    col = mouse.screencol,
  }
end

---@param drag TerminalsDragState
---@return boolean
local function should_activate_drag(drag)
  local start_mouse = drag.start_mouse
  if not start_mouse then
    return true
  end

  local current = mouse_position()
  local dx = math.abs((current.col or 0) - (start_mouse.col or 0))
  local dy = math.abs((current.row or 0) - (start_mouse.row or 0))
  return dx > DRAG_THRESHOLD_COLS or dy > DRAG_THRESHOLD_ROWS
end

---@param terminal TerminalsTerminal?
---@return string
local function ghost_label(terminal)
  if not terminal then
    return ''
  end
  local title = terminal.title:gsub('[%c]', ' ')
  title = vim.trim(title)
  return string.format(' %s ', title)
end

local function cleanup_ghost()
  if ghost.winid and vim.api.nvim_win_is_valid(ghost.winid) then
    vim.api.nvim_win_close(ghost.winid, true)
  end
  ghost.winid = nil
end

local function create_ghost()
  local drag = state.drag()
  if not drag then
    return
  end

  local terminal = state.find_terminal(drag.source_id)
  local label = ghost_label(terminal)
  if label == '' then
    return
  end

  if not ghost.bufnr or not vim.api.nvim_buf_is_valid(ghost.bufnr) then
    ghost.bufnr = vim.api.nvim_create_buf(false, true)
  end
  vim.bo[ghost.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(ghost.bufnr, 0, -1, false, { label })
  vim.bo[ghost.bufnr].modifiable = false

  cleanup_ghost()
  ghost.winid = vim.api.nvim_open_win(ghost.bufnr, false, {
    relative = 'editor',
    row = math.max(0, (drag.start_mouse and drag.start_mouse.row or 1) - 1),
    col = math.max(0, (drag.start_mouse and drag.start_mouse.col or 1) - 1),
    width = vim.fn.strdisplaywidth(label),
    height = 1,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
    mouse = false,
    zindex = 250,
  })
  vim.api.nvim_set_option_value('winhl', 'Normal:TerminalsWinbarDrag,FloatBorder:TerminalsWinbarDrag', { win = ghost.winid })
end

local function update_ghost()
  local pos = mouse_position()
  if ghost.winid and vim.api.nvim_win_is_valid(ghost.winid) then
    vim.api.nvim_win_set_config(ghost.winid, {
      relative = 'editor',
      row = math.max(0, (pos.row or 1) - 1),
      col = math.max(0, (pos.col or 1) - 1),
    })
  end
end

---@return integer, integer, integer?
local function mouse_target()
  local mouse = vim.fn.getmousepos()
  local winid = mouse.winid ~= 0 and mouse.winid or vim.api.nvim_get_current_win()
  local tabpage = vim.api.nvim_win_get_tabpage(winid)
  local target_index = winbar.target_index_for_position(winid, mouse.wincol)
  return winid, tabpage, target_index
end

---@param source_id integer
function M.begin(source_id)
  state.start_drag(source_id, mouse_position())
end

function M.update()
  local drag = state.drag()
  if not drag then
    return
  end

  if not drag.active then
    if not should_activate_drag(drag) then
      return
    end
    state.activate_drag()
    create_ghost()
  end

  update_ghost()

  local _, tabpage, target_index = mouse_target()
  if not target_index then
    return
  end

  state.update_drag(target_index, tabpage)
  winbar.refresh_all()
end

function M.finish()
  local drag = state.drag()
  if not drag then
    return
  end

  if not drag.active then
    state.clear_drag()
    cleanup_ghost()
    return
  end

  local _, tabpage, target_index = mouse_target()
  if target_index then
    state.update_drag(target_index, tabpage)
  end

  state.finish_drag(tabpage)
  cleanup_ghost()
  winbar.refresh_all()
end

function M.cancel()
  state.clear_drag()
  cleanup_ghost()
  winbar.refresh_all()
end

---@return integer?
function M.ghost_window()
  if ghost.winid and vim.api.nvim_win_is_valid(ghost.winid) then
    return ghost.winid
  end
  return nil
end

return M
