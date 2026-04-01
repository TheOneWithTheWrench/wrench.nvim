-- Minimal init for running tests
-- Find project root relative to this file
local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(require("wrench.utils").get_plugin_path(
	vim.fn.stdpath("data") .. "/wrench/plugins",
	"https://github.com/nvim-lua/plenary.nvim"
))
