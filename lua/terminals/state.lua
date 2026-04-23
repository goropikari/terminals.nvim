---@class TerminalsWindowLayout
---@field position string
---@field width integer
---@field height integer
---@field row? number
---@field col? number

---@class TerminalsDragState
---@field source_id integer
---@field active boolean
---@field target_index? integer
---@field start_mouse? { row?: integer, col?: integer }

---@class TerminalsTerminal
---@field id integer
---@field bufnr integer
---@field job_id integer
---@field title string
---@field cwd string
---@field alive boolean

---@class TerminalsTabState
---@field terminals TerminalsTerminal[]
---@field active_id? integer
---@field drag? TerminalsDragState
---@field policy table
---@field primary_terminal_winid? integer
---@field terminal_winids integer[]
---@field window_terminal_ids table<integer, integer?>
---@field window_layout? TerminalsWindowLayout

---@class TerminalsStateStore
---@field projects table<string, TerminalsTabState>
---@field next_terminal_id integer

local M = {}

---@type TerminalsStateStore
local state = {
  projects = {},
  next_terminal_id = 1,
}

local project_root_cache = {}

---@param path string
---@return string
local function normalize_path(path)
  local uv = vim.uv or vim.loop
  local resolved = uv.fs_realpath(path)
  path = resolved or vim.fn.fnamemodify(path, ':p')
  return path:gsub('/+$', '')
end

---@param tabpage? integer
---@return string
function M.get_tab_cwd(tabpage)
  tabpage = tabpage or vim.api.nvim_get_current_tabpage()
  local tabnr = nil
  for index, candidate in ipairs(vim.api.nvim_list_tabpages()) do
    if candidate == tabpage then
      tabnr = index
      break
    end
  end

  -- Vim's getcwd() expects a tab number, not a Neovim tabpage handle.
  local ok, cwd = false, nil
  if tabnr then
    ok, cwd = pcall(vim.fn.getcwd, -1, tabnr)
  end
  if not ok then
    cwd = vim.fn.getcwd()
  end
  return normalize_path(cwd)
end

---@param cwd string
---@return string
function M.get_project_root(cwd)
  cwd = normalize_path(cwd)
  if project_root_cache[cwd] then
    return project_root_cache[cwd]
  end

  local root = cwd
  local ok, output = pcall(vim.fn.systemlist, { 'git', '-C', cwd, 'rev-parse', '--show-toplevel' })
  if ok and vim.v.shell_error == 0 and type(output) == 'table' and output[1] and output[1] ~= '' then
    root = normalize_path(output[1])
  end

  project_root_cache[cwd] = root
  return root
end

---@param tabpage? integer
---@return string
function M.get_tab_project(tabpage)
  return M.get_project_root(M.get_tab_cwd(tabpage))
end

function M.prune()
  -- No longer pruning based on tabpage validity as we are project-based
end

---@return integer
function M.current_tabpage()
  return vim.api.nvim_get_current_tabpage()
end

---@param tabpage? integer
---@return TerminalsTabState
function M.get_tab(tabpage)
  local project_key = M.get_tab_project(tabpage)
  local project = state.projects[project_key]
  if not project then
    project = {
      terminals = {},
      active_id = nil,
      drag = nil,
      policy = {},
      primary_terminal_winid = nil,
      terminal_winids = {},
      window_terminal_ids = {},
      window_layout = nil,
    }
    state.projects[project_key] = project
  end
  return project
end

---@param tabpage? integer
---@return TerminalsTerminal[]
function M.list(tabpage)
  return M.get_tab(tabpage).terminals
end

---@param tabpage? integer
---@return integer?
function M.terminal_window(tabpage)
  local tab = M.get_tab(tabpage)
  if tab.primary_terminal_winid and vim.api.nvim_win_is_valid(tab.primary_terminal_winid) then
    return tab.primary_terminal_winid
  end

  for _, winid in ipairs(tab.terminal_winids or {}) do
    if vim.api.nvim_win_is_valid(winid) then
      tab.primary_terminal_winid = winid
      return winid
    end
  end

  return nil
end

---@param winid? integer
---@param tabpage? integer
---@return integer?
function M.set_terminal_window(winid, tabpage)
  local tab = M.get_tab(tabpage)
  if winid and vim.api.nvim_win_is_valid(winid) then
    tab.primary_terminal_winid = winid
    tab.terminal_winids = { winid }
    tab.window_terminal_ids = {}
    if tab.active_id then
      tab.window_terminal_ids[winid] = tab.active_id
    end
    return winid
  end
  tab.primary_terminal_winid = nil
  tab.terminal_winids = {}
  tab.window_terminal_ids = {}
  return nil
end

---@param tabpage? integer
---@return integer[]
function M.terminal_windows(tabpage)
  local tab = M.get_tab(tabpage)
  local valid = {}
  local seen = {}

  for _, winid in ipairs(tab.terminal_winids or {}) do
    if vim.api.nvim_win_is_valid(winid) and not seen[winid] then
      valid[#valid + 1] = winid
      seen[winid] = true
    end
  end

  tab.terminal_winids = valid
  if tab.primary_terminal_winid and not seen[tab.primary_terminal_winid] then
    tab.primary_terminal_winid = valid[1]
  end

  return valid
end

---@param winid integer
---@param tabpage? integer
---@return boolean
function M.is_terminal_window(winid, tabpage)
  for _, candidate in ipairs(M.terminal_windows(tabpage)) do
    if candidate == winid then
      return true
    end
  end
  return false
end

---@param winid? integer
---@param tabpage? integer
---@return integer?
function M.add_terminal_window(winid, tabpage)
  local tab = M.get_tab(tabpage)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    return nil
  end
  if not M.is_terminal_window(winid, tabpage) then
    tab.terminal_winids[#tab.terminal_winids + 1] = winid
  end
  if not tab.primary_terminal_winid or not vim.api.nvim_win_is_valid(tab.primary_terminal_winid) then
    tab.primary_terminal_winid = winid
  end
  if tab.window_terminal_ids[winid] == nil and tab.active_id then
    tab.window_terminal_ids[winid] = tab.active_id
  end
  return winid
end

---@param winid integer
---@param tabpage? integer
function M.remove_terminal_window(winid, tabpage)
  local tab = M.get_tab(tabpage)
  local next_winids = {}
  for _, candidate in ipairs(M.terminal_windows(tabpage)) do
    if candidate ~= winid then
      next_winids[#next_winids + 1] = candidate
    end
  end
  tab.terminal_winids = next_winids
  tab.window_terminal_ids[winid] = nil
  if tab.primary_terminal_winid == winid then
    tab.primary_terminal_winid = next_winids[1]
  end
end

---@param winid? integer
---@param terminal_id? integer
---@param tabpage? integer
---@return integer?
function M.set_window_terminal(winid, terminal_id, tabpage)
  local tab = M.get_tab(tabpage)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    return nil
  end
  if terminal_id and M.find_terminal(terminal_id, tabpage) then
    tab.window_terminal_ids[winid] = terminal_id
    return terminal_id
  end
  tab.window_terminal_ids[winid] = nil
  return nil
end

---@param winid? integer
---@param tabpage? integer
---@return integer?
function M.window_terminal_id(winid, tabpage)
  local tab = M.get_tab(tabpage)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    return tab.active_id
  end

  local terminal_id = tab.window_terminal_ids[winid]
  if terminal_id and M.find_terminal(terminal_id, tabpage) then
    return terminal_id
  end

  tab.window_terminal_ids[winid] = tab.active_id
  return tab.active_id
end

---@param winid? integer
---@param tabpage? integer
---@return TerminalsTerminal?
function M.window_terminal(winid, tabpage)
  local terminal_id = M.window_terminal_id(winid, tabpage)
  if not terminal_id then
    return nil
  end
  return M.find_terminal(terminal_id, tabpage)
end

---@param tabpage? integer
---@return table
function M.tab_policy(tabpage)
  return M.get_tab(tabpage).policy or {}
end

---@param policy? table
---@param tabpage? integer
---@return table
function M.set_tab_policy(policy, tabpage)
  local tab = M.get_tab(tabpage)
  tab.policy = vim.tbl_deep_extend('force', {}, tab.policy or {}, policy or {})
  return tab.policy
end

---@param policy? table
---@param tabpage? integer
---@return table
function M.replace_tab_policy(policy, tabpage)
  local tab = M.get_tab(tabpage)
  tab.policy = vim.tbl_deep_extend('force', {}, policy or {})
  return tab.policy
end

---@param tabpage? integer
function M.clear_tab_policy(tabpage)
  local tab = M.get_tab(tabpage)
  tab.policy = {}
end

---@param tabpage? integer
---@return TerminalsWindowLayout?
function M.window_layout(tabpage)
  return M.get_tab(tabpage).window_layout
end

---@param layout? TerminalsWindowLayout
---@param tabpage? integer
---@return TerminalsWindowLayout?
function M.set_window_layout(layout, tabpage)
  local tab = M.get_tab(tabpage)
  tab.window_layout = layout and vim.deepcopy(layout) or nil
  return tab.window_layout
end

---@param id integer
function M.set_next_id(id)
  state.next_terminal_id = id
end

---@return integer
function M.next_id()
  local id = state.next_terminal_id
  state.next_terminal_id = id + 1
  return id
end

---@param terminal TerminalsTerminal
---@param tabpage? integer
function M.add_terminal(terminal, tabpage)
  local tab = M.get_tab(tabpage)
  tab.terminals[#tab.terminals + 1] = terminal
  tab.active_id = terminal.id
end

---@param id integer
---@param tabpage? integer
---@return TerminalsTerminal?, integer?
function M.find_terminal(id, tabpage)
  for index, terminal in ipairs(M.list(tabpage)) do
    if terminal.id == id then
      return terminal, index
    end
  end
end

---@param bufnr integer
---@param tabpage? integer
---@return TerminalsTerminal?, integer?, integer?
function M.find_terminal_by_bufnr(bufnr, tabpage)
  if tabpage == nil then
    for _, current_tabpage in ipairs(vim.api.nvim_list_tabpages()) do
      local terminal, index = M.find_terminal_by_bufnr(bufnr, current_tabpage)
      if terminal then
        return terminal, index, current_tabpage
      end
    end
    return nil
  end

  for index, terminal in ipairs(M.list(tabpage)) do
    if terminal.bufnr == bufnr then
      return terminal, index
    end
  end
end

---@param id integer
---@param tabpage? integer
---@return TerminalsTerminal?
function M.set_active(id, tabpage)
  local tab = M.get_tab(tabpage)
  local terminal = M.find_terminal(id, tabpage)
  if terminal then
    tab.active_id = id
  end
  return terminal
end

---@param tabpage? integer
---@return TerminalsTerminal?, integer?
function M.active(tabpage)
  local tab = M.get_tab(tabpage)
  if not tab.active_id then
    return nil
  end
  return M.find_terminal(tab.active_id, tabpage)
end

---@param id integer
---@param tabpage? integer
---@return TerminalsTerminal?
function M.remove_terminal(id, tabpage)
  local tab = M.get_tab(tabpage)
  local _, index = M.find_terminal(id, tabpage)
  if not index then
    return nil
  end

  local removed = table.remove(tab.terminals, index)
  if tab.active_id == id then
    local fallback = tab.terminals[index] or tab.terminals[index - 1]
    tab.active_id = fallback and fallback.id or nil
  end
  for winid, terminal_id in pairs(tab.window_terminal_ids) do
    if terminal_id == id then
      tab.window_terminal_ids[winid] = tab.active_id
    end
  end
  if tab.drag and tab.drag.source_id == id then
    tab.drag = nil
  end
  return removed
end

---@param source_id integer
---@param target_index integer
---@param tabpage? integer
---@return boolean
function M.move_terminal(source_id, target_index, tabpage)
  local tab = M.get_tab(tabpage)
  local terminal, source_index = M.find_terminal(source_id, tabpage)
  if not terminal or not source_index then
    return false
  end

  target_index = math.max(1, math.min(target_index, #tab.terminals + 1))
  table.remove(tab.terminals, source_index)
  if source_index < target_index then
    target_index = target_index - 1
  end
  target_index = math.max(1, math.min(target_index, #tab.terminals + 1))
  if source_index == target_index then
    table.insert(tab.terminals, source_index, terminal)
    return false
  end
  table.insert(tab.terminals, target_index, terminal)
  return true
end

---@param id integer
---@param tabpage? integer
---@return boolean
function M.move_left(id, tabpage)
  local _, index = M.find_terminal(id, tabpage)
  if not index then
    return false
  end
  return M.move_terminal(id, index - 1, tabpage)
end

---@param id integer
---@param tabpage? integer
---@return boolean
function M.move_right(id, tabpage)
  local tab = M.get_tab(tabpage)
  local _, index = M.find_terminal(id, tabpage)
  if not index then
    return false
  end
  return M.move_terminal(id, math.min(#tab.terminals + 1, index + 2), tabpage)
end

---@param source_id integer
---@param start_mouse? { row?: integer, col?: integer }
---@param tabpage? integer
function M.start_drag(source_id, start_mouse, tabpage)
  local tab = M.get_tab(tabpage)
  tab.drag = {
    source_id = source_id,
    active = false,
    target_index = nil,
    start_mouse = start_mouse and vim.deepcopy(start_mouse) or nil,
  }
end

---@param tabpage? integer
---@return boolean
function M.activate_drag(tabpage)
  local drag = M.drag(tabpage)
  if not drag or drag.active then
    return false
  end
  drag.active = true
  return true
end

---@param target_index integer
---@param tabpage? integer
function M.update_drag(target_index, tabpage)
  local tab = M.get_tab(tabpage)
  if not tab.drag or not tab.drag.active then
    return
  end
  tab.drag.target_index = target_index
end

---@param tabpage? integer
---@return TerminalsDragState?
function M.drag(tabpage)
  return M.get_tab(tabpage).drag
end

---@param tabpage? integer
---@return boolean
function M.finish_drag(tabpage)
  local tab = M.get_tab(tabpage)
  local drag = tab.drag
  tab.drag = nil
  if not drag or not drag.active or not drag.target_index then
    return false
  end
  return M.move_terminal(drag.source_id, drag.target_index, tabpage)
end

---@param tabpage? integer
function M.clear_drag(tabpage)
  M.get_tab(tabpage).drag = nil
end

return M
