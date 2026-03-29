local state = require('terminals.state')
local winbar = require('terminals.ui.winbar')

local M = {}

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
  state.start_drag(source_id)
  winbar.refresh_all()
end

function M.update()
  local drag = state.drag()
  if not drag then
    return
  end

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

  local _, tabpage, target_index = mouse_target()
  if target_index then
    state.update_drag(target_index, tabpage)
  end

  state.finish_drag(tabpage)
  winbar.refresh_all()
end

function M.cancel()
  state.clear_drag()
  winbar.refresh_all()
end

return M
