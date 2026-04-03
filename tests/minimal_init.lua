local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root .. '/deps/plenary.nvim')
vim.opt.runtimepath:prepend(root)
vim.opt.shadafile = 'NONE'
vim.opt.swapfile = false
vim.opt.hidden = true
vim.opt.mouse = 'a'
