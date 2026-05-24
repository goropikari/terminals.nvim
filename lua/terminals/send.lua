local state = require('terminals.state')

local M = {}

---@param opts? TerminalsSendOpts
---@return TerminalsTerminal?
local function target_terminal(opts)
  opts = opts or {}
  if opts.id then
    return state.find_terminal(opts.id, opts.tabpage)
  end
  return require('terminals.terminal').current_or_active(opts.tabpage)
end

---@param text string|string[]
---@param opts? TerminalsSendOpts
---@return boolean
function M.send(text, opts)
  opts = opts or {}
  local terminal = target_terminal(opts)
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
  return M.send(vim.api.nvim_get_current_line(), opts)
end

---@param payload string
---@param opts? TerminalsSendOpts
---@return boolean
local function send_as_bracketed_paste(payload, opts)
  opts = opts or {}
  if payload == '' then
    return false
  end

  local terminal = target_terminal(opts)
  if not terminal or not terminal.job_id or terminal.job_id <= 0 then
    return false
  end

  local job_id = terminal.job_id
  vim.fn.chansend(job_id, '\27[200~' .. payload .. '\27[201~')
  vim.defer_fn(function()
    pcall(vim.fn.chansend, job_id, '\r')
  end, opts.submit_delay_ms or 20)
  return true
end

---@param opts? TerminalsSendOpts
---@return boolean
function M.send_current_line_as_bracketed_paste(opts)
  return send_as_bracketed_paste(vim.api.nvim_get_current_line(), opts)
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

---@param bufnr integer
---@param row integer
---@param col integer
---@return integer
local function clamp_buf_col(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''
  return math.max(0, math.min(col, #line))
end

---@return string[]?
local function visual_selection_lines()
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.fn.visualmode()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_row, start_col = start_pos[2], start_pos[3]
  local end_row, end_col = end_pos[2], end_pos[3]

  if start_row == 0 or end_row == 0 then
    return nil
  end
  if start_row > end_row or (start_row == end_row and start_col > end_col) then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  local lines
  if mode == 'V' then
    lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)
  elseif mode == '\22' then
    local start_col0 = math.min(start_col, end_col) - 1
    local end_col0 = math.max(start_col, end_col)
    lines = {}
    for row = start_row, end_row do
      lines[#lines + 1] = vim.api.nvim_buf_get_text(bufnr, row - 1, clamp_buf_col(bufnr, row, start_col0), row - 1, clamp_buf_col(bufnr, row, end_col0), {})[1]
        or ''
    end
  else
    lines =
      vim.api.nvim_buf_get_text(bufnr, start_row - 1, clamp_buf_col(bufnr, start_row, start_col - 1), end_row - 1, clamp_buf_col(bufnr, end_row, end_col), {})
  end

  if #lines == 0 then
    return nil
  end
  return lines
end

---@param opts? TerminalsSendOpts
---@return boolean
function M.send_visual_selection(opts)
  local lines = visual_selection_lines()
  if not lines then
    return false
  end

  return M.send(lines, opts)
end

---@param opts? TerminalsSendOpts
---@return boolean
function M.send_visual_selection_as_bracketed_paste(opts)
  opts = opts or {}
  local lines = visual_selection_lines()
  if not lines then
    return false
  end

  local payload = table.concat(lines, '\n')
  if payload == '' then
    return false
  end

  return send_as_bracketed_paste(payload, opts)
end

return M
