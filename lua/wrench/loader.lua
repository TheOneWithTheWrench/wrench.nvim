local M = {}
local utils = require("wrench.utils")

--- Tracks which plugins have actually been loaded at runtime.
---@type table<string, boolean>
local loaded = {}

--- Tracks which plugins have had loading set up (deduplication within a session).
---@type table<string, boolean>
local loading_setup = {}

---Loads a plugin immediately (adds to rtp, runs config).
---@param url string The plugin URL.
---@param spec table The plugin spec.
---@param specs table The map of all specs.
---@param install_dir string Directory where plugins are installed.
local function load_plugin_now(url, spec, specs, install_dir)
	if loaded[url] then
		return
	end
	loaded[url] = true

	-- Load dependencies first
	if spec.dependencies then
		for _, dep in ipairs(spec.dependencies) do
			local dep_url = dep.url
			local dep_spec = specs[dep_url]
			if dep_spec then
				load_plugin_now(dep_url, dep_spec, specs, install_dir)
			end
		end
	end

	local name = utils.get_name(url)
	local plugin_path = install_dir .. "/" .. name
	vim.opt.rtp:prepend(plugin_path)

	-- Source plugin/ files
	local plugin_dir = plugin_path .. "/plugin"
	if vim.fn.isdirectory(plugin_dir) == 1 then
		for _, file in ipairs(vim.fn.readdir(plugin_dir)) do
			if file:match("%.vim$") then
				vim.cmd("source " .. plugin_dir .. "/" .. file)
			elseif file:match("%.lua$") then
				dofile(plugin_dir .. "/" .. file)
			end
		end
	end

	-- Run config function
	if spec.config and type(spec.config) == "function" then
		spec.config()
	end
end

---Sets up loading behavior for all plugins.
---@param specs table Map of URL to PluginSpec.
---@param install_dir string Directory where plugins are installed.
function M.setup_loading(specs, install_dir)
	for url, spec in pairs(specs) do
		if loading_setup[url] then
			goto continue
		end
		loading_setup[url] = true

		local is_lazy = spec.ft or spec.event or spec.keys

		if not is_lazy then
			load_plugin_now(url, spec, specs, install_dir)
		else
			-- Set up lazy loading triggers
			local group_name = "WrenchLoad_" .. url:gsub("[^%w]", "_")
			local group = vim.api.nvim_create_augroup(group_name, { clear = true })

			local function trigger_load()
				if loaded[url] then
					return
				end
				vim.api.nvim_del_augroup_by_id(group)
				load_plugin_now(url, spec, specs, install_dir)
			end

			if spec.ft then
				vim.api.nvim_create_autocmd("FileType", {
					pattern = spec.ft,
					group = group,
					callback = trigger_load,
				})
			end

			if spec.event then
				vim.api.nvim_create_autocmd(spec.event, {
					pattern = "*",
					group = group,
					callback = trigger_load,
				})
			end

			if spec.keys then
				for _, key in ipairs(spec.keys) do
					local lhs = key.lhs
					local rhs = key.rhs
					local modes = key.mode or { "n" }

					local opts = {}
					for k, v in pairs(key) do
						if k ~= "lhs" and k ~= "rhs" and k ~= "mode" then
							opts[k] = v
						end
					end

					for _, mode in ipairs(modes) do
						vim.keymap.set(mode, lhs, function()
							vim.keymap.del(mode, lhs)
							load_plugin_now(url, spec, specs, install_dir)
							vim.keymap.set(mode, lhs, rhs, opts)
							local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
							vim.api.nvim_feedkeys(keys, "m", false)
						end, opts)
					end
				end
			end
		end

		::continue::
	end
end

return M
