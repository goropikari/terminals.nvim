local command_names = {
  'TerminalNew',
  'TerminalOpen',
  'TerminalToggle',
  'TerminalCloseWindow',
  'TerminalSplit',
  'TerminalVSplit',
  'TerminalSetPosition',
  'TerminalNext',
  'TerminalPrev',
  'TerminalClose',
  'TerminalPicker',
  'TerminalRename',
  'TerminalMoveLeft',
  'TerminalMoveRight',
  'TerminalSendLine',
  'TerminalSendSelection',
}

local stub = require('luassert.stub')
local visualmode_stub = nil
local ui_select_stub = nil
local getmousepos_stub = nil
local screenpos_stub = nil
local getcmdtype_stub = nil
local getcmdline_stub = nil
local line_stub = nil
local executable_stub = nil
local notify_stub = nil
local telescope_modules = {}

local function clear_modules()
  for name in pairs(package.loaded) do
    if name:match('^terminals') then
      package.loaded[name] = nil
    end
  end
  for name in pairs(telescope_modules) do
    package.loaded[name] = nil
  end
  telescope_modules = {}
end

local function clear_commands()
  for _, name in ipairs(command_names) do
    pcall(vim.api.nvim_del_user_command, name)
  end
end

local function reset_editor()
  vim.cmd('silent! stopinsert')
  pcall(vim.api.nvim_del_augroup_by_name, 'TerminalsNvim')
  clear_commands()
  clear_modules()
  _G.TerminalsWinbarClick = nil
  _G.TerminalsWinbarAdd = nil

  while #vim.api.nvim_list_tabpages() > 1 do
    vim.cmd('silent! tabclose!')
  end

  pcall(vim.cmd, 'silent! only!')

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted == false then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end

  local listed = vim.fn.getbufinfo({ buflisted = 1 })
  for _, item in ipairs(listed) do
    if vim.api.nvim_buf_is_valid(item.bufnr) and item.bufnr ~= vim.api.nvim_get_current_buf() then
      pcall(vim.api.nvim_buf_delete, item.bufnr, { force = true })
    end
  end

  pcall(vim.cmd, 'new')
end

local all_commands = {
  'TerminalNew',
  'TerminalOpen',
  'TerminalToggle',
  'TerminalCloseWindow',
  'TerminalSplit',
  'TerminalVSplit',
  'TerminalSetPosition',
  'TerminalNext',
  'TerminalPrev',
  'TerminalClose',
  'TerminalPicker',
  'TerminalRename',
  'TerminalMoveLeft',
  'TerminalMoveRight',
  'TerminalSendLine',
  'TerminalSendSelection',
  'TerminalSave',
  'TerminalRestore',
  'TerminalClean',
  'TerminalCleanAll',
}

local function setup(opts)
  reset_editor()
  require('terminals').setup(vim.tbl_deep_extend('force', {
    auto_close_on_exit = false,
    focus_terminal_on_open = true,
    start_in_insert = false,
    terminal_position = 'bottom',
    commands = all_commands,
  }, opts or {}))
end

local function create_titles(...)
  local terminal = require('terminals.terminal')
  local ids = {}
  for _, title in ipairs({ ... }) do
    ids[#ids + 1] = terminal.create({ title = title }).id
  end
  return ids
end

local function titles()
  local state = require('terminals.state')
  local result = {}
  for _, term in ipairs(state.list()) do
    result[#result + 1] = term.title
  end
  return result
end

local function wait_for(predicate, timeout)
  local ok = vim.wait(timeout or 1000, predicate, 20)
  assert.is_true(ok)
end

local function terminal_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

describe('terminals.nvim', function()
  before_each(function()
    setup()
  end)

  after_each(function()
    if visualmode_stub then
      visualmode_stub:revert()
      visualmode_stub = nil
    end
    if ui_select_stub then
      ui_select_stub:revert()
      ui_select_stub = nil
    end
    if getmousepos_stub then
      getmousepos_stub:revert()
      getmousepos_stub = nil
    end
    if getcmdtype_stub then
      getcmdtype_stub:revert()
      getcmdtype_stub = nil
    end
    if getcmdline_stub then
      getcmdline_stub:revert()
      getcmdline_stub = nil
    end
    if line_stub then
      line_stub:revert()
      line_stub = nil
    end
    if screenpos_stub then
      screenpos_stub:revert()
      screenpos_stub = nil
    end
    if executable_stub then
      executable_stub:revert()
      executable_stub = nil
    end
    if notify_stub then
      notify_stub:revert()
      notify_stub = nil
    end
  end)

  it('keeps terminal groups isolated per tabpage', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local first_tab = vim.api.nvim_get_current_tabpage()
    local dir1 = vim.fn.tempname()
    vim.fn.mkdir(dir1, 'p')
    vim.cmd('tcd ' .. dir1)
    terminal.create({ title = 'one' })

    vim.cmd('tabnew')
    local second_tab = vim.api.nvim_get_current_tabpage()
    local dir2 = vim.fn.tempname()
    vim.fn.mkdir(dir2, 'p')
    vim.cmd('tcd ' .. dir2)
    terminal.create({ title = 'two' })

    assert.are.same(1, #state.list(first_tab))
    assert.are.same(1, #state.list(second_tab))
    assert.are.same('one', state.list(first_tab)[1].title)
    assert.are.same('two', state.list(second_tab)[1].title)
  end)

  it('keeps tab-local terminal position policies isolated per tabpage', function()
    local terminals = require('terminals')
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local first_tab = vim.api.nvim_get_current_tabpage()
    local dir1 = vim.fn.tempname()
    vim.fn.mkdir(dir1, 'p')
    vim.cmd('tcd ' .. dir1)
    terminal.create({ title = 'one' })
    local first_win = state.terminal_window(first_tab)

    vim.cmd('tabnew')
    local second_tab = vim.api.nvim_get_current_tabpage()
    local dir2 = vim.fn.tempname()
    vim.fn.mkdir(dir2, 'p')
    vim.cmd('tcd ' .. dir2)
    terminals.set_tab_policy({
      terminal_position = 'float',
      float = {
        width = 30,
        height = 8,
      },
    }, second_tab)
    terminal.create({ title = 'two' })
    local second_win = state.terminal_window(second_tab)

    assert.are.same('', vim.api.nvim_win_get_config(first_win).relative)
    assert.are.same('editor', vim.api.nvim_win_get_config(second_win).relative)
    assert.are.same('bottom', terminals.get_tab_policy(first_tab).terminal_position or 'bottom')
    assert.are.same('float', terminals.get_tab_policy(second_tab).terminal_position)
  end)

  it('toggles the dedicated window without killing the terminal buffer', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    local active = state.active()
    local bufnr = active.bufnr

    terminal.toggle()
    assert.is_nil(state.terminal_window())
    assert.is_true(vim.api.nvim_buf_is_valid(bufnr))

    terminal.toggle()
    assert.is_not_nil(state.terminal_window())
    assert.are.same(bufnr, state.active().bufnr)
  end)

  it('reopens the current tab terminal window when the tab policy changes', function()
    local terminals = require('terminals')
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    local previous_win = state.terminal_window()

    terminals.set_tab_policy({
      terminal_position = 'left',
      terminal_width = 24,
    })

    local winid = state.terminal_window()
    assert.are_not.same(previous_win, winid)
    assert.are.same(24, vim.api.nvim_win_get_width(winid))
  end)

  it('keeps the resized terminal height after toggle', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    local winid = state.terminal_window()

    vim.api.nvim_set_current_win(winid)
    vim.cmd('resize 9')
    vim.cmd('doautocmd <nomodeline> WinResized')

    terminal.toggle()
    terminal.toggle()

    wait_for(function()
      return state.terminal_window() ~= nil
    end)
    assert.are.same(9, vim.api.nvim_win_get_height(state.terminal_window()))
  end)

  it('keeps the resized terminal width after toggle', function()
    local terminals = require('terminals')
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    terminals.set_tab_policy({
      terminal_position = 'left',
      terminal_width = 24,
    })

    local winid = state.terminal_window()
    vim.api.nvim_set_current_win(winid)
    vim.cmd('vertical resize 31')
    vim.cmd('doautocmd <nomodeline> WinResized')

    terminal.toggle()
    terminal.toggle()

    assert.are.same(31, vim.api.nvim_win_get_width(state.terminal_window()))
  end)

  it('marks the dedicated terminal window as winfixbuf', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })

    assert.is_true(vim.wo[state.terminal_window()].winfixbuf)
  end)

  it('keeps regular buffers out of the dedicated terminal window', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    local terminal_buf = state.active().bufnr
    local windows_before = #vim.api.nvim_tabpage_list_wins(0)

    vim.api.nvim_set_current_win(state.terminal_window())
    local ok = pcall(vim.cmd, 'new')

    assert.is_true(ok)
    assert.are.same(windows_before + 1, #vim.api.nvim_tabpage_list_wins(0))
    assert.are.same(terminal_buf, vim.api.nvim_win_get_buf(state.terminal_window()))
  end)

  it('creates a managed terminal split only through TerminalSplit', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    local winid = state.terminal_window()
    local windows_before = #vim.api.nvim_tabpage_list_wins(0)

    vim.cmd('TerminalSplit')

    assert.are.same(windows_before + 1, #vim.api.nvim_tabpage_list_wins(0))
    assert.are.same(winid, state.terminal_window())
    assert.are.same(2, #state.terminal_windows())
  end)

  it('splits from the current terminal window', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    local root = state.terminal_window()

    vim.api.nvim_set_current_win(root)
    vim.cmd('TerminalSplit')
    local first_split = vim.api.nvim_get_current_win()

    vim.api.nvim_set_current_win(first_split)
    vim.cmd('TerminalVSplit')
    local second_split = vim.api.nvim_get_current_win()

    local first_col = vim.fn.win_screenpos(first_split)[2]
    local second_col = vim.fn.win_screenpos(second_split)[2]

    assert.is_true(second_col > first_col)
    assert.are_not.same(root, second_split)
  end)

  it('supports independent terminals per managed split', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local ids = create_titles('one', 'two', 'three')
    terminal.show(ids[1], { winid = state.terminal_window() })
    vim.cmd('TerminalVSplit')
    local right = vim.api.nvim_get_current_win()
    local left = state.terminal_window()

    terminal.show(ids[2], { winid = left })
    terminal.show(ids[3], { winid = right })

    assert.are.same(ids[2], state.window_terminal(left).id)
    assert.are.same(ids[3], state.window_terminal(right).id)
    assert.are.same(state.find_terminal(ids[2]).bufnr, vim.api.nvim_win_get_buf(left))
    assert.are.same(state.find_terminal(ids[3]).bufnr, vim.api.nvim_win_get_buf(right))
  end)

  it('does not auto-register a regular window that shows a terminal buffer', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    local managed_before = vim.deepcopy(state.terminal_windows())
    local bufnr = state.active().bufnr

    vim.cmd('new')
    vim.cmd('buffer ' .. bufnr)

    assert.are.same(managed_before, state.terminal_windows())
    assert.is_false(state.is_terminal_window(vim.api.nvim_get_current_win()))
  end)

  it('cycles only the current managed split', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local ids = create_titles('one', 'two', 'three')
    terminal.show(ids[1], { winid = state.terminal_window() })
    vim.cmd('TerminalVSplit')
    local right = vim.api.nvim_get_current_win()
    local left = state.terminal_window()

    terminal.show(ids[1], { winid = left })
    terminal.show(ids[2], { winid = right })

    vim.api.nvim_set_current_win(right)
    terminal.cycle(1)

    assert.are.same(ids[1], state.window_terminal(left).id)
    assert.are.same(ids[3], state.window_terminal(right).id)
  end)

  it('creates a managed split from a terminal window via TerminalSplit', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    local windows_before = #vim.api.nvim_tabpage_list_wins(0)

    vim.api.nvim_set_current_win(state.terminal_window())
    vim.cmd('TerminalSplit')
    wait_for(function()
      return #vim.api.nvim_tabpage_list_wins(0) == windows_before + 1
    end)

    assert.are.same(2, #state.terminal_windows())
  end)

  it('closes only the current managed terminal window', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    local bufnr = state.active().bufnr
    vim.cmd('TerminalSplit')
    local windows_before = #vim.api.nvim_tabpage_list_wins(0)
    local managed = state.terminal_windows()

    vim.api.nvim_set_current_win(managed[#managed])
    terminal.close_window()

    assert.are.same(windows_before - 1, #vim.api.nvim_tabpage_list_wins(0))
    assert.are.same(1, #state.terminal_windows())
    assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
  end)

  it('rewrites terminal-window commands to managed window commands', function()
    local terminals = require('terminals')
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    vim.api.nvim_set_current_win(state.terminal_window())

    getcmdtype_stub = stub(vim.fn, 'getcmdtype')
    getcmdtype_stub.returns(':')
    getcmdline_stub = stub(vim.fn, 'getcmdline')
    getcmdline_stub.returns('split')

    assert.are.same('TerminalSplit', terminals.command_abbrev('split'))
    getcmdline_stub:revert()
    getcmdline_stub = stub(vim.fn, 'getcmdline')
    getcmdline_stub.returns('vsplit')
    assert.are.same('TerminalVSplit', terminals.command_abbrev('vsplit'))
    getcmdline_stub:revert()
    getcmdline_stub = stub(vim.fn, 'getcmdline')
    getcmdline_stub.returns('q')
    assert.are.same('TerminalCloseWindow', terminals.command_abbrev('q'))
  end)

  it('keeps split commands unchanged outside terminal windows', function()
    local terminals = require('terminals')

    vim.cmd('new')
    getcmdtype_stub = stub(vim.fn, 'getcmdtype')
    getcmdtype_stub.returns(':')
    getcmdline_stub = stub(vim.fn, 'getcmdline')
    getcmdline_stub.returns('split')

    assert.are.same('split', terminals.command_abbrev('split'))
  end)

  it('creates a fresh terminal when closing the last one', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'solo' })
    local previous = state.active()
    local winid = state.terminal_window()

    terminal.close(previous.id)

    assert.are.same(1, #state.list())
    assert.is_not_nil(state.active())
    assert.are_not.same(previous.bufnr, state.active().bufnr)
    assert.are.same(winid, state.terminal_window())
  end)

  it('keeps another terminal active when closing one with siblings', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    create_titles('one', 'two', 'three')
    local previous = state.active()

    terminal.close(previous.id)

    assert.are.same(2, #state.list())
    assert.is_not_nil(state.active())
    assert.are_not.same(previous.id, state.active().id)
  end)

  it('renders the plugin winbar only in the dedicated terminal window', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'one' })
    vim.cmd('vsplit')
    require('terminals.ui.winbar').refresh_all()

    local dedicated = state.terminal_window()
    local other = nil
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if winid ~= dedicated then
        other = winid
        break
      end
    end

    assert.is_not_nil(dedicated)
    assert.is_not_nil(other)
    assert.is_true(vim.wo[dedicated].winbar ~= '')
    assert.are.same('', vim.wo[other].winbar)
  end)

  it('moves the active terminal right', function()
    local terminal = require('terminals.terminal')

    local ids = create_titles('one', 'two', 'three')
    terminal.show(ids[2])
    vim.cmd('TerminalMoveRight')

    assert.are.same({ 'one', 'three', 'two' }, titles())
  end)

  it('moves the active terminal left', function()
    local terminal = require('terminals.terminal')

    local ids = create_titles('one', 'two', 'three')
    terminal.show(ids[2])
    vim.cmd('TerminalMoveLeft')

    assert.are.same({ 'two', 'one', 'three' }, titles())
  end)

  it('cycles to the next terminal', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local ids = create_titles('one', 'two', 'three')
    terminal.show(ids[1])
    terminal.cycle(1)

    assert.are.same('two', state.active().title)
  end)

  it('cycles terminals with mouse wheel on the winbar', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local ids = create_titles('one', 'two', 'three')
    terminal.show(ids[2])
    local winid = state.terminal_window()
    local text_row = vim.fn.screenpos(winid, 1, 1).row

    getmousepos_stub = stub(vim.fn, 'getmousepos')
    getmousepos_stub.returns({
      screenrow = text_row - 1,
      winid = winid,
    })
    screenpos_stub = stub(vim.fn, 'screenpos')
    screenpos_stub.returns({
      row = text_row,
    })

    assert.are.same('<Ignore>', terminal.handle_scroll_wheel('down'))
    wait_for(function()
      return state.active().title == 'three'
    end)
    assert.are.same('three', state.active().title)

    assert.are.same('<Ignore>', terminal.handle_scroll_wheel('up'))
    wait_for(function()
      return state.active().title == 'two'
    end)
    assert.are.same('two', state.active().title)
  end)

  it('keeps normal wheel scrolling when the mouse is not on the winbar', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local ids = create_titles('one', 'two')
    terminal.show(ids[1])
    local winid = state.terminal_window()
    local text_row = vim.fn.screenpos(winid, 1, 1).row

    getmousepos_stub = stub(vim.fn, 'getmousepos')
    getmousepos_stub.returns({
      screenrow = text_row,
      winid = winid,
    })
    screenpos_stub = stub(vim.fn, 'screenpos')
    screenpos_stub.returns({
      row = text_row,
    })

    assert.are.same('<ScrollWheelDown>', terminal.handle_scroll_wheel('down'))
    assert.are.same('one', state.active().title)
    assert.are.same('<ScrollWheelDown>', terminal.handle_scroll_wheel('down'))
    assert.are.same('one', state.active().title)
  end)

  it('still treats wheel input as winbar scrolling when the buffer is scrolled', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local ids = create_titles('one', 'two', 'three')
    terminal.show(ids[2])
    local winid = state.terminal_window()

    getmousepos_stub = stub(vim.fn, 'getmousepos')
    getmousepos_stub.returns({
      screenrow = 4,
      winid = winid,
    })
    line_stub = stub(vim.fn, 'line')
    line_stub.returns(42)
    screenpos_stub = stub(vim.fn, 'screenpos')
    screenpos_stub.invokes(function(_, lnum)
      if lnum == 1 then
        return { row = 0 }
      end
      return { row = 5 }
    end)

    assert.are.same('<Ignore>', terminal.handle_scroll_wheel('down'))
    wait_for(function()
      return state.active().title == 'three'
    end)
    assert.are.same('three', state.active().title)
  end)

  it('updates the terminal title from OSC title sequences', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'bash' })
    local active = state.active()

    vim.b[active.bufnr].term_title = 'server console'
    local ok = terminal.handle_term_request(active.bufnr)

    assert.is_true(ok)
    wait_for(function()
      return state.active().title == 'server console'
    end)
    assert.are.same('server console', vim.b[active.bufnr].term_title)
  end)

  it('escapes terminal titles before rendering them in the winbar', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')
    local winbar = require('terminals.ui.winbar')

    terminal.create({ title = 'safe' })
    local active = state.active()

    terminal.rename(active.id, '100% %{danger}\nnext')
    local rendered = winbar.render()

    assert.is_truthy(rendered:find('100%% %%{danger} next', 1, true))

    vim.b[active.bufnr].term_title = 'OSC % title'
    terminal.handle_term_request(active.bufnr)
    wait_for(function()
      return state.active().title == 'OSC % title'
    end)
    rendered = winbar.render()

    assert.is_truthy(rendered:find('OSC %% title', 1, true))
  end)

  it('opens a picker with vim.ui.select and switches to the selected terminal', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local ids = create_titles('one', 'two', 'three')
    terminal.show(ids[1])

    local captured = nil
    ui_select_stub = stub(vim.ui, 'select')
    ui_select_stub.invokes(function(items, opts, on_choice)
      captured = {
        items = items,
        prompt = opts.prompt,
        labels = vim.tbl_map(opts.format_item, items),
      }
      on_choice(items[2])
    end)

    vim.cmd('TerminalPicker')

    assert.is_not_nil(captured)
    assert.are.same('Select terminal', captured.prompt)
    assert.are.same(3, #captured.items)
    assert.are.same('* one [' .. vim.fn.fnamemodify(vim.loop.cwd(), ':t') .. ']', captured.labels[1])
    assert.are.same('two', state.active().title)
  end)

  it('shows terminal output in the telescope picker preview and scrolls to the end', function()
    local terminal = require('terminals.terminal')

    terminal.create({ cmd = 'cat', title = 'cat one' })
    terminal.create({ cmd = 'cat', title = 'cat two' })
    local target = require('terminals.state').active()
    terminal.send({ 'alpha', 'beta', 'gamma' }, { id = target.id })

    wait_for(function()
      return table.concat(terminal_lines(target.bufnr), '\n'):match('gamma') ~= nil
    end)

    local captured = {}
    telescope_modules['telescope.finders'] = true
    package.loaded['telescope.finders'] = {
      new_table = function(spec)
        captured.finder = spec
        return spec
      end,
    }

    telescope_modules['telescope.config'] = true
    package.loaded['telescope.config'] = {
      values = {
        generic_sorter = function()
          return 'sorter'
        end,
      },
    }

    telescope_modules['telescope.actions'] = true
    package.loaded['telescope.actions'] = {
      close = function() end,
      select_default = {
        replace = function(_, fn)
          captured.select_default = fn
        end,
      },
    }

    telescope_modules['telescope.actions.state'] = true
    package.loaded['telescope.actions.state'] = {
      get_selected_entry = function()
        return nil
      end,
    }

    telescope_modules['telescope.previewers'] = true
    package.loaded['telescope.previewers'] = {
      new_buffer_previewer = function(spec)
        captured.previewer = spec
        return spec
      end,
    }

    telescope_modules['telescope.previewers.utils'] = true
    package.loaded['telescope.previewers.utils'] = {
      highlighter = function(bufnr, ft)
        captured.highlighter = {
          bufnr = bufnr,
          ft = ft,
        }
      end,
    }

    telescope_modules['telescope.pickers'] = true
    package.loaded['telescope.pickers'] = {
      new = function(_, spec)
        captured.picker = spec
        return {
          find = function()
            local preview_buf = vim.api.nvim_create_buf(false, true)
            local preview_win = vim.api.nvim_open_win(preview_buf, false, {
              relative = 'editor',
              row = 0,
              col = 0,
              width = 20,
              height = 5,
              style = 'minimal',
            })
            spec.previewer.define_preview({ state = { bufnr = preview_buf } }, {
              value = spec.finder.results[2],
            }, {
              preview_win = preview_win,
            })
            captured.preview_buf = preview_buf
            captured.preview_cursor = vim.api.nvim_win_get_cursor(preview_win)
            vim.api.nvim_win_close(preview_win, true)
          end,
        }
      end,
    }

    local ok = terminal.pick({ backend = 'telescope' })

    assert.is_true(ok)
    assert.is_not_nil(captured.previewer)
    assert.are.same('Terminal Output', captured.previewer.title)
    assert.are.same({ 'alpha', 'beta', 'gamma' }, vim.api.nvim_buf_get_lines(captured.preview_buf, 0, -1, false))
    assert.are.same(3, captured.preview_cursor[1])
    assert.are.same('bash', vim.bo[captured.preview_buf].filetype)
    assert.are.same('bash', captured.highlighter.ft)
  end)

  it('sends the current line to the active terminal', function()
    local terminal = require('terminals.terminal')

    terminal.create({ cmd = 'cat', title = 'cat' })
    vim.cmd('new')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'echo hello' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    vim.cmd('TerminalSendLine')

    local target = require('terminals.state').active().bufnr
    wait_for(function()
      return table.concat(terminal_lines(target), '\n'):match('echo hello') ~= nil
    end)
  end)

  it('sends the visual selection to the active terminal', function()
    local terminal = require('terminals.terminal')

    terminal.create({ cmd = 'cat', title = 'cat' })
    vim.cmd('new')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'first line', 'second line' })

    vim.fn.setpos("'<", { 0, 1, 2, 0 })
    vim.fn.setpos("'>", { 0, 1, 6, 0 })
    visualmode_stub = stub(vim.fn, 'visualmode')
    visualmode_stub.returns('v')
    vim.cmd('1,1TerminalSendSelection')

    local target = require('terminals.state').active().bufnr
    wait_for(function()
      local content = table.concat(terminal_lines(target), '\n')
      return content:match('irst ') ~= nil
    end)
  end)

  it('falls back to backend = none when the configured backend is unavailable', function()
    reset_editor()
    executable_stub = stub(vim.fn, 'executable')
    executable_stub.invokes(function(cmd)
      return cmd == 'dtach' and 0 or 1
    end)
    notify_stub = stub(vim, 'notify')
    setup({ backend = 'dtach' })

    local created = require('terminals.terminal').create({ title = 'fallback' })

    wait_for(function()
      return #terminal_lines(created.bufnr) > 0
    end)

    assert.stub(notify_stub).was_called(1)
    assert.stub(notify_stub).was_called_with(
      'Terminals.nvim: backend "dtach" is not installed; falling back to backend = "none".',
      vim.log.levels.WARN
    )
  end)
end)

describe('terminals.nvim session persistence', function()
  before_each(function()
    setup({ auto_restore = false }) -- Disable auto_restore to manually trigger it
  end)

  it('serializes and deserializes terminal state correctly', function()
    local state = require('terminals.state')
    local terminal = require('terminals.terminal')

    terminal.create({ title = 'term1' })
    terminal.create({ title = 'term2' })
    local cwd = vim.fn.getcwd()

    local serialized = state.serialize()
    assert.is_not_nil(serialized.projects[cwd])
    assert.are.same(2, #serialized.projects[cwd].terminals)
    assert.are.same('term1', serialized.projects[cwd].terminals[1].title)
    assert.are.same('term2', serialized.projects[cwd].terminals[2].title)
    assert.are.same(2, serialized.projects[cwd].active_index)
  end)

  it('saves and loads session data from disk', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'disk-test' })
    state.save()

    -- Clear current state in memory
    package.loaded['terminals.state'] = nil
    state = require('terminals.state')

    local loaded = state.load()
    local cwd = vim.fn.getcwd()
    assert.is_not_nil(loaded)
    assert.is_not_nil(loaded.projects[cwd])
    assert.are.same('disk-test', loaded.projects[cwd].terminals[1].title)
  end)

  it('restores terminals from session data', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'restore-1' })
    terminal.create({ title = 'restore-2' })
    local data = state.serialize()

    -- Reset the editor to a clean state
    reset_editor()
    setup({ auto_restore = false })
    terminal = require('terminals.terminal')
    state = require('terminals.state')

    -- Restore
    terminal.restore(data, { show = true })

    local list = state.list()
    assert.are.same(2, #list)
    assert.are.same('restore-1', list[1].title)
    assert.are.same('restore-2', list[2].title)
    assert.are.same('restore-2', state.active().title)
    assert.is_not_nil(state.terminal_window())
  end)

  it('keeps multiple restored terminals when the window is reopened later', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'restore-hidden-1' })
    terminal.create({ title = 'restore-hidden-2' })
    local data = state.serialize()

    reset_editor()
    setup({ auto_restore = false })
    terminal = require('terminals.terminal')
    state = require('terminals.state')

    terminal.restore(data, { show = false })

    wait_for(function()
      return #state.list() == 2
    end)
    assert.are.same('restore-hidden-2', state.active().title)

    vim.cmd('TerminalOpen')

    assert.are.same(2, #state.list())
    assert.are.same({ 'restore-hidden-1', 'restore-hidden-2' }, titles())
    assert.is_not_nil(state.terminal_window())
  end)

  it('restores projects into the matching tabpages by tab-local cwd', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local dir1 = vim.fn.tempname()
    local dir2 = vim.fn.tempname()
    vim.fn.mkdir(dir1, 'p')
    vim.fn.mkdir(dir2, 'p')

    vim.cmd('tcd ' .. dir1)
    terminal.create({ title = 'dir1-a' })
    terminal.create({ title = 'dir1-b' })

    vim.cmd('tabnew')
    vim.cmd('tcd ' .. dir2)
    terminal.create({ title = 'dir2-a' })
    terminal.create({ title = 'dir2-b' })

    local data = state.serialize()

    reset_editor()
    setup({ auto_restore = false })
    terminal = require('terminals.terminal')
    state = require('terminals.state')

    vim.cmd('tcd ' .. dir1)
    vim.cmd('tabnew')
    vim.cmd('tcd ' .. dir2)
    vim.cmd('tabprevious')

    terminal.restore(data, { show = false })

    local tabs = vim.api.nvim_list_tabpages()
    assert.are.same(2, #tabs)

    local tab_by_cwd = {}
    for _, tab in ipairs(tabs) do
      tab_by_cwd[state.get_tab_cwd(tab)] = tab
    end

    assert.is_not_nil(tab_by_cwd[dir1])
    assert.is_not_nil(tab_by_cwd[dir2])
    assert.are.same({ 'dir1-a', 'dir1-b' }, (function()
      local result = {}
      for _, term in ipairs(state.list(tab_by_cwd[dir1])) do
        result[#result + 1] = term.title
      end
      return result
    end)())
    assert.are.same({ 'dir2-a', 'dir2-b' }, (function()
      local result = {}
      for _, term in ipairs(state.list(tab_by_cwd[dir2])) do
        result[#result + 1] = term.title
      end
      return result
    end)())
  end)

  it('restores projects across multiple existing tabpages even without cwd matches', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local dir1 = vim.fn.tempname()
    local dir2 = vim.fn.tempname()
    vim.fn.mkdir(dir1, 'p')
    vim.fn.mkdir(dir2, 'p')

    vim.cmd('tcd ' .. dir1)
    terminal.create({ title = 'fallback-tab-1' })

    vim.cmd('tabnew')
    vim.cmd('tcd ' .. dir2)
    terminal.create({ title = 'fallback-tab-2' })

    local data = state.serialize()

    reset_editor()
    setup({ auto_restore = false })
    terminal = require('terminals.terminal')
    state = require('terminals.state')

    vim.cmd('tabnew')

    terminal.restore(data, { show = false })

    local restored = {}
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      local names = {}
      for _, term in ipairs(state.list(tab)) do
        names[#names + 1] = term.title
      end
      if #names > 0 then
        restored[table.concat(names, ',')] = true
      end
    end

    assert.is_true(restored['fallback-tab-1'])
    assert.is_true(restored['fallback-tab-2'])
  end)

  it('toggles restored terminals open on later tabpages without creating a new one', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    local dir1 = vim.fn.tempname()
    local dir2 = vim.fn.tempname()
    vim.fn.mkdir(dir1, 'p')
    vim.fn.mkdir(dir2, 'p')

    vim.cmd('tcd ' .. dir1)
    terminal.create({ title = 'tab1-only' })

    vim.cmd('tabnew')
    vim.cmd('tcd ' .. dir2)
    terminal.create({ title = 'tab2-a' })
    terminal.create({ title = 'tab2-b' })

    local data = state.serialize()

    reset_editor()
    setup({ auto_restore = false })
    terminal = require('terminals.terminal')
    state = require('terminals.state')

    vim.cmd('tcd ' .. dir1)
    vim.cmd('tabnew')
    vim.cmd('tcd ' .. dir2)
    vim.cmd('tabprevious')

    terminal.restore(data, { show = false })

    local target_tab = nil
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if state.get_tab_cwd(tab) == dir2 then
        target_tab = tab
        break
      end
    end

    assert.is_not_nil(target_tab)
    assert.are.same(2, #state.list(target_tab))

    vim.api.nvim_set_current_tabpage(target_tab)
    vim.cmd('TerminalToggle')

    assert.are.same(2, #state.list(target_tab))
    local restored = {}
    for _, term in ipairs(state.list(target_tab)) do
      restored[#restored + 1] = term.title
    end
    assert.are.same({ 'tab2-a', 'tab2-b' }, restored)
    assert.is_not_nil(state.terminal_window(target_tab))
  end)

  it('preserves terminal window layout after restoration', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    terminal.create({ title = 'main' })
    -- Ensure the layout is captured
    state.set_window_layout({ position = 'bottom', height = 15 })

    local data = state.serialize()

    reset_editor()
    setup({ auto_restore = false })
    terminal = require('terminals.terminal')
    state = require('terminals.state')

    terminal.restore(data, { show = true })

    assert.are.same(15, vim.api.nvim_win_get_height(state.terminal_window()))
  end)

  it('clears all session data and reset memory state via TerminalClean', function()
    local terminal = require('terminals.terminal')
    local state = require('terminals.state')

    -- Create some session data
    terminal.create({ title = 'to-be-cleaned' })
    state.save()

    local loaded = state.load()
    assert.is_not_nil(loaded)

    -- Run the clean command
    vim.cmd('TerminalClean')

    -- Memory state should be reset
    assert.are.same(0, #state.list())
    assert.are.same(1, state.next_id())

    -- Disk state should be gone
    assert.is_nil(state.load())
  end)
end)
