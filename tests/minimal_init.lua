-- Minimal init for running tests
-- Find project root relative to this file
local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")
