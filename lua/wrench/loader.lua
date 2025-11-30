local M = {}
local log = require("wrench.log")

---Recursively scans a directory for .lua files.
---@param path string The directory path to scan.
---@return string[] files List of absolute file paths.
local function scan_directory(path)
	local files = {}

	if vim.fn.isdirectory(path) == 0 then
		return files
	end

	local entries = vim.fn.readdir(path)
	for _, entry in ipairs(entries) do
		local full_path = path .. "/" .. entry

		if vim.fn.isdirectory(full_path) == 1 then
			local nested = scan_directory(full_path)
			for _, file in ipairs(nested) do
				table.insert(files, file)
			end
		elseif entry:match("%.lua$") then
			table.insert(files, full_path)
		end
	end

	return files
end

---Converts a file path to a require-able module name.
---@param file_path string Absolute path to lua file.
---@param base_path string Base lua directory path.
---@return string module_name The module name for require().
local function path_to_module(file_path, base_path)
	local relative = file_path:sub(#base_path + 2)
	local module = relative:gsub("%.lua$", ""):gsub("/", ".")
	return module
end

---Checks if a table is a single PluginConfig (has url field or first element is a string).
---@param tbl table The table to check.
---@return boolean is_single True if it's a single PluginConfig.
local function is_single_config(tbl)
	return tbl.url ~= nil or type(tbl[1]) == "string"
end

---Loads all plugin specs from a directory.
---@param import_path string The import path relative to lua/ (e.g., "plugins").
---@return PluginList plugins All collected plugin configs.
function M.load_all(import_path)
	local base_path = vim.fn.stdpath("config") .. "/lua"
	local full_path = base_path .. "/" .. import_path

	if vim.fn.isdirectory(full_path) == 0 then
		log.warn("Plugin directory not found: " .. full_path)
		return {}
	end

	local files = scan_directory(full_path)
	local all_plugins = {}

	for _, file in ipairs(files) do
		local module_name = path_to_module(file, base_path)
		local relative_path = file:sub(#base_path + 2)

		local ok, result = pcall(require, module_name)
		if not ok then
			log.error("Failed to load " .. relative_path .. ": " .. result)
		elseif result ~= nil then
			if type(result) ~= "table" then
				log.error("Failed to load " .. relative_path .. ": expected PluginConfig or PluginList, got " .. type(result))
			elseif is_single_config(result) then
				table.insert(all_plugins, result)
			else
				for _, plugin in ipairs(result) do
					table.insert(all_plugins, plugin)
				end
			end
		end
	end

	return all_plugins
end

return M
