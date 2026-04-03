local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
local plenary_path = root .. "/deps/plenary.nvim"

if vim.uv.fs_stat(plenary_path) == nil then
	error("Missing test dependency at " .. plenary_path .. ". Run `make test` first.")
end

vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(root)

vim.cmd("runtime plugin/plenary.vim")
