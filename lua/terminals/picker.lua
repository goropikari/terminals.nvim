local state = require('terminals.state')

local M = {}

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
      require('terminals.terminal').show(choice.id, { tabpage = opts.tabpage })
    end
  end)
  return true
end

---@param items table[]
---@param opts TerminalsPickOpts
---@return boolean
local function pick_with_snacks(items, opts)
  local snacks = rawget(_G, 'Snacks')
  if not (snacks and snacks.picker and snacks.picker.select) then
    local ok, module = pcall(require, 'snacks')
    if ok then
      snacks = module
    end
  end

  if not (snacks and snacks.picker and snacks.picker.select) then
    return false
  end

  snacks.picker.select(items, {
    prompt = opts.prompt or 'Select terminal',
    format_item = picker_label,
  }, function(choice)
    if choice then
      require('terminals.terminal').show(choice.id, { tabpage = opts.tabpage })
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
            require('terminals.terminal').show(selection.value.id, { tabpage = opts.tabpage })
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
  if backend == 'snacks' and pick_with_snacks(items, {
    prompt = opts.prompt,
    tabpage = tabpage,
  }) then
    return true
  end

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

return M
