local M = {}

---@param setup_highlights fun()
function M.setup(setup_highlights)
  local group = vim.api.nvim_create_augroup('TerminalsNvim', { clear = true })

  vim.api.nvim_create_autocmd({ 'TabEnter', 'WinEnter', 'BufEnter', 'DirChanged' }, {
    group = group,
    callback = function()
      local state = require('terminals.state')
      local terminal = require('terminals.terminal')
      local tabpage = state.current_tabpage()
      local winid = vim.api.nvim_get_current_win()
      local bufnr = vim.api.nvim_get_current_buf()
      local current = state.find_terminal_by_bufnr(bufnr, tabpage)
      if current and state.is_terminal_window(winid, tabpage) then
        state.add_terminal_window(winid, tabpage)
      elseif #state.terminal_windows(tabpage) == 0 then
        state.set_terminal_window(nil, tabpage)
      end
      terminal.sync_current_buffer()
      require('terminals.ui.winbar').refresh_all()
    end,
  })

  vim.api.nvim_create_autocmd('WinNew', {
    group = group,
    callback = function()
      vim.schedule(function()
        require('terminals.terminal').register_cloned_terminal_window()
      end)
    end,
  })

  vim.api.nvim_create_autocmd({ 'TermClose', 'BufDelete' }, {
    group = group,
    callback = function(args)
      local terminals = require('terminals')
      local terminal_api = require('terminals.terminal')
      local state = require('terminals.state')
      local terminal, _, tabpage = state.find_terminal_by_bufnr(args.buf)
      if terminal then
        if terminals._is_quitting then
          state.remove_terminal(terminal.id, tabpage)
          return
        end

        if args.event == 'TermClose' and terminals.config.auto_close_on_exit then
          vim.schedule(function()
            local existing = state.find_terminal(terminal.id, tabpage)
            if existing then
              terminal_api.close(terminal.id, {
                tabpage = tabpage,
                winid = state.terminal_window(tabpage),
              })
            end
          end)
          return
        end

        state.remove_terminal(terminal.id, tabpage)
        require('terminals.ui.winbar').refresh_all()
      end
    end,
  })

  vim.api.nvim_create_autocmd('TermRequest', {
    group = group,
    callback = function(args)
      local terminals = require('terminals')
      if not terminals.config.osc_title then
        return
      end
      local bufnr = args.buf
      local sequence = args.data and args.data.sequence or nil
      require('terminals.terminal').handle_term_request(bufnr, sequence)
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      local closed = tonumber(args.match)
      if not closed then
        return
      end
      local state = require('terminals.state')
      for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        if state.is_terminal_window(closed, tabpage) then
          state.remove_terminal_window(closed, tabpage)
        end
      end
      require('terminals.ui.winbar').refresh_all()
    end,
  })

  vim.api.nvim_create_autocmd('WinResized', {
    group = group,
    callback = function()
      require('terminals.ui.winbar').refresh_all()
    end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = setup_highlights,
  })

  vim.api.nvim_create_autocmd({ 'QuitPre', 'VimLeavePre' }, {
    group = group,
    callback = function()
      local terminals = require('terminals')
      if terminals._is_quitting then
        return
      end
      terminals._is_quitting = true
      require('terminals.terminal').cleanup_for_quit()
    end,
  })
end

return M
