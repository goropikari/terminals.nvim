vim.g.mapleader = ','

vim.opt.runtimepath:prepend('/home/ubuntu/workspace/github/terminals.nvim')

require('terminals').setup({
  keymaps = {
    next = { lhs = '<A-n>', modes = { 'n', 't' } },
    move_right = { lhs = '<C-A-n>', modes = { 'n', 't' } },
  },
})

local terminal = require('terminals.terminal')

vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], { silent = true })
vim.keymap.set('n', '<leader>tl', '<cmd>TerminalSendLine<cr>', { desc = 'Send line to terminal', silent = true })
vim.keymap.set('v', '<leader>ts', function()
  terminal.send_visual_selection()
end, { desc = 'Send selection to terminal', silent = true })
