-- Minimal init for running tests with mini.test
local root = vim.fn.fnamemodify('.', ':p')

-- Add plugin to runtime path
vim.opt.rtp:prepend(root)

-- Clone mini.nvim if not present
local mini_path = root .. 'deps/mini.nvim'
if not vim.uv.fs_stat(mini_path) then
  vim.fn.system({ 'git', 'clone', '--depth=1', 'https://github.com/echasnovski/mini.nvim', mini_path })
end
vim.opt.rtp:prepend(mini_path)

-- Setup mini.test
require('mini.test').setup()
