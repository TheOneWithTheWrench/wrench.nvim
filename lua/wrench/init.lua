-- wrench/init.lua

local M = {}
local log = require("wrench.log")
local lockfile = require("wrench.lockfile")
local utils = require("wrench.utils")
local validate = require("wrench.validate")
local process = require("wrench.process")
local commands = require("wrench.commands")
local update_ui = require("wrench.update")
local loader = require("wrench.loader")

commands.setup()

--- All registered plugins across add() calls.
---@type PluginList
local registered_plugins = {}

---@class PluginConfig
---@field url string The full plugin URL. This must be the first element, e.g., { "https://github.com/owner/repo" }.
---@field dependencies? PluginConfig[] (Optional) A list of other plugins that will be loaded first.
---@field branch? string (Optional) Specify a git branch to clone.
---@field tag? string (Optional) Specify a git tag to checkout.
---@field commit? string (Optional) Pin to a specific commit hash.
---@field config? function (Optional) A function to run after the plugin is loaded.
---@field ft? string[] (Optional) Only load plugin when opening files of this type.

--- A list of plugins to be processed, each as a PluginConfig table.
---@alias PluginList PluginConfig[]

--- Adds and processes a list of plugins.
---@param plugins PluginList A list of PluginConfig tables.
function M.add(plugins)
	if not plugins or type(plugins) ~= "table" then
		log.error("add() requires a table of PluginConfigs.")
		return
	end

	local valid, err = validate.all(plugins)
	if not valid then
		log.error("Validation failed: " .. (err or "unknown error"))
		return
	end

	-- Register plugins for later use (e.g., sync)
	for _, plugin in ipairs(plugins) do
		table.insert(registered_plugins, plugin)
	end

	local lock_data = lockfile.read(utils.LOCKFILE_PATH)
	local lock_changed = false

	for _, plugin in ipairs(plugins) do
		if process.plugin(plugin, lock_data) then
			lock_changed = true
		end
	end

	if lock_changed then
		local ok, write_err = lockfile.write(utils.LOCKFILE_PATH, lock_data)
		if not ok then
			log.error("Failed to write lockfile: " .. (write_err or "unknown error"))
		end
	end
end

---Syncs plugins to the commits specified in config.
---Iterates over all registered plugins and checks out the specified commit if different from current.
function M.sync()
	log.info("Syncing plugins...")

	if #registered_plugins == 0 then
		log.warn("No plugins registered. Call add() first.")
		return
	end

	local lock_data = lockfile.read(utils.LOCKFILE_PATH)
	local lock_changed = false

	-- Build set of URLs in config
	local config_urls = {}
	for _, plugin in ipairs(registered_plugins) do
		local url = plugin[1] or plugin.url
		config_urls[url] = true
	end

	-- Remove lockfile entries not in config
	for url, _ in pairs(lock_data) do
		if not config_urls[url] then
			log.info("Removing " .. url .. " from lockfile")
			lock_data[url] = nil
			lock_changed = true
		end
	end

	for _, plugin in ipairs(registered_plugins) do
		if process.sync(plugin, lock_data) then
			lock_changed = true
		end
	end

	if lock_changed then
		local ok, write_err = lockfile.write(utils.LOCKFILE_PATH, lock_data)
		if not ok then
			log.error("Failed to write lockfile: " .. (write_err or "unknown error"))
		end
	end
end

---Updates all plugins to latest (ignores pinned commits).
---Fetches latest commits, shows changes, prompts for approval, then restores.
function M.update()
	log.info("Checking for updates...")

	if #registered_plugins == 0 then
		log.warn("No plugins registered. Call add() first.")
		return
	end

	local lock_data = lockfile.read(utils.LOCKFILE_PATH)

	-- Phase 1: Collect all available updates
	local updates = update_ui.collect_all(registered_plugins, lock_data)

	if #updates == 0 then
		log.info("All plugins up to date.")
		return
	end

	log.info("Found " .. #updates .. " plugin(s) with updates.")

	-- Phase 2: Interactive review
	local approved = update_ui.review(updates)

	if #approved == 0 then
		log.info("No updates selected.")
		return
	end

	-- Phase 3: Apply approved updates to lockfile
	for _, info in ipairs(approved) do
		lock_data[info.url] = { branch = lock_data[info.url].branch, commit = info.new_commit }
	end

	local ok, write_err = lockfile.write(utils.LOCKFILE_PATH, lock_data)
	if not ok then
		log.error("Failed to write lockfile: " .. (write_err or "unknown error"))
		return
	end

	-- Phase 4: Restore (checkout the new commits)
	log.info("Applying " .. #approved .. " update(s)...")
	M.restore()
end

---Restores all plugins to the state in the lockfile.
---Plugins not in lockfile will be removed.
function M.restore()
	log.info("Restoring plugins...")

	local lock_data = lockfile.read(utils.LOCKFILE_PATH)

	if vim.tbl_isempty(lock_data) then
		log.warn("Lockfile is empty. Nothing to restore.")
		return
	end

	-- Get list of installed plugins
	local install_dir = utils.INSTALL_PATH
	if vim.fn.isdirectory(install_dir) == 0 then
		log.warn("No plugins installed.")
		return
	end

	local installed = vim.fn.readdir(install_dir)

	-- Build set of plugin names from lockfile
	local locked_names = {}
	for url, _ in pairs(lock_data) do
		locked_names[utils.get_name(url)] = url
	end

	-- Restore or remove each installed plugin
	for _, name in ipairs(installed) do
		local url = locked_names[name]
		if url then
			-- Plugin is in lockfile — restore to locked commit
			process.restore(url, lock_data[url])
		else
			-- Plugin not in lockfile — remove it
			log.warn("Plugin " .. name .. " not in lockfile, removing...")
			process.remove(name)
		end
	end
end

---Returns all registered plugins (for debugging).
---@return PluginList
function M.get_registered()
	return registered_plugins
end

---Sets up wrench by loading plugins from a directory.
---@param import_path string The path relative to lua/ to scan for plugin specs (e.g., "plugins").
function M.setup(import_path)
	if not import_path or type(import_path) ~= "string" then
		log.error("setup() requires an import path (e.g., 'plugins')")
		return
	end

	local plugins = loader.load_all(import_path)

	if #plugins == 0 then
		log.info("No plugins found in " .. import_path)
		return
	end

	M.add(plugins)
end

return M

