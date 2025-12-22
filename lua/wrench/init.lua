local M = {}

local lockfile = require("wrench.lockfile")
local git = require("wrench.git")
local utils = require("wrench.utils")

-- Load commands to register user commands
require("wrench.commands")

---@class DependencyRef
---@field url string The plugin URL. This is the ONLY allowed field for dependencies.

---@class KeySpec
---@field lhs string Required. The key sequence to bind.
---@field rhs function Required. The action to execute.
---@field mode? string[] (Optional) Mode(s) for the keymap. Defaults to {"n"}.
---@field [string] any Any other valid vim.keymap.set option (desc, silent, buffer, etc.)

---@class PluginSpec
---@field url string The full plugin URL.
---@field ft? string[] (Optional) Only load plugin when opening files of this type.
---@field event? string[] (Optional) Only load plugin when opening files of this type.
---@field keys? KeySpec[] (Optional) Lazy-load on keypress and set up keymaps.
---@field dependencies? DependencyRef[] (Optional) Plugins that must be loaded first (url only).
---@field branch? string (Optional) Specify a git branch to clone.
---@field tag? string (Optional) Specify a git tag to checkout.
---@field commit? string (Optional) Pin to a specific commit hash.
---@field config? function (Optional) A function to run after the plugin is loaded.

---A map of plugin URL to its canonical spec.
---@alias PluginMap table<string, PluginSpec>

-- Default configuration
M.config = {
	install_dir = vim.fn.stdpath("data") .. "/wrench/plugins",
	lockfile_path = vim.fn.stdpath("config") .. "/wrench-lock.json",
}

-- Store registered specs for debugging
local registered_specs = {}

---Setup wrench with user configuration.
---@param import string Path to scan for plugin specs (e.g., "plugins" scans lua/plugins/)
---@param opts? table Optional configuration overrides (install_dir, lockfile_path, base_path)
function M.setup(import, opts)
	if not import or type(import) ~= "string" then
		error("setup() requires an import path (e.g., 'plugins')")
		return
	end

	opts = opts or {}
	opts.import = import
	M.config = vim.tbl_extend("force", M.config, opts)

	local specs_module = require("wrench.specs")
	local loader_module = require("wrench.loader")

	-- Scan for plugin specs (base_path is optional, for testing)
	local specs, scan_err = specs_module.scan(import, opts.base_path)
	if scan_err then
		error("Failed to scan plugins: " .. scan_err)
	end

	-- Store specs for get_registered()
	registered_specs = specs

	-- Ensure all plugins are installed (clone missing only, skip checkout for existing)
	local install_ok, install_err = M.ensure_installed(specs, M.config.lockfile_path, M.config.install_dir)
	if not install_ok then
		error("Failed to install plugins: " .. install_err)
	end

	-- Setup loading for all plugins
	loader_module.setup_loading(specs, M.config.install_dir)
end

---Ensures all plugins are installed by cloning missing ones.
---Does NOT sync/checkout existing plugins (fast for startup).
---Updates lockfile with newly installed plugins.
---@param specs PluginMap Map of plugin URL to PluginSpec.
---@param lockfile_path string Path to the lockfile.
---@param install_dir string Directory where plugins are installed.
---@return boolean success True if all plugins installed successfully.
---@return string? error Error message if failed.
function M.ensure_installed(specs, lockfile_path, install_dir)
	local lock_data, read_err = lockfile.read(lockfile_path)
	if read_err then
		return false, read_err
	end

	local lock_changed = false

	for url, spec in pairs(specs) do
		local name = utils.get_name(url)
		local plugin_path = install_dir .. "/" .. name

		-- Clone if plugin doesn't exist
		if vim.fn.isdirectory(plugin_path) == 0 then
			print("Installing " .. name .. "...")
			local clone_success, clone_err = git.clone(url, plugin_path)
			if not clone_success then
				return false, "Failed to clone " .. name .. ": " .. (clone_err or "unknown error")
			end

			-- Checkout to spec pin if specified (branch/tag/commit)
			local target_ref = spec.commit or spec.tag or spec.branch
			if target_ref then
				local checkout_success, checkout_err = git.checkout(plugin_path, target_ref)
				if not checkout_success then
					return false, "Failed to checkout " .. name .. " to " .. target_ref .. ": " .. (checkout_err or "unknown error")
				end
			end
			-- Else: leave at whatever clone gave us (default branch HEAD)
			-- Note: We do NOT checkout to lockfile here - that's only for restore()

			-- Record the current commit in lockfile
			local current_sha, get_err = git.get_head(plugin_path)
			if get_err then
				return false, "Failed to get HEAD for " .. name .. ": " .. get_err
			end
			lock_data[url] = current_sha
			lock_changed = true
		end
	end

	-- Write lockfile if changed
	if lock_changed then
		local write_success, write_err = lockfile.write(lockfile_path, lock_data)
		if not write_success then
			return false, write_err
		end
	end

	return true, nil
end

---Restores all plugins to the commits specified in the lockfile.
---This makes the installed plugins match the lockfile.
---Clones plugins if they don't exist, then checks out to the locked commit.
---Does NOT consider plugin specs - only uses the lockfile.
---@param lockfile_path string Path to the lockfile.
---@param install_dir string Directory where plugins are installed.
---@return boolean success True if restore succeeded.
---@return string? error Error message if restore failed.
function M.restore(lockfile_path, install_dir)
	local lock_data, read_err = lockfile.read(lockfile_path)
	if read_err then
		return false, read_err
	end

	-- Build set of plugin names from lockfile
	local locked_names = {}
	for url, _ in pairs(lock_data) do
		locked_names[utils.get_name(url)] = url
	end

	-- Remove plugins not in lockfile
	if vim.fn.isdirectory(install_dir) == 1 then
		local installed = vim.fn.readdir(install_dir)
		for _, name in ipairs(installed) do
			if not locked_names[name] then
				vim.fn.delete(install_dir .. "/" .. name, "rf")
			end
		end
	end

	-- Restore plugins in lockfile
	for url, sha in pairs(lock_data) do
		local name = utils.get_name(url)
		local plugin_path = install_dir .. "/" .. name

		-- Clone if plugin doesn't exist
		if vim.fn.isdirectory(plugin_path) == 0 then
			local clone_success, clone_err = git.clone(url, plugin_path)
			if not clone_success then
				return false, "Failed to clone " .. name .. ": " .. (clone_err or "unknown error")
			end
		end

		-- Checkout to locked commit
		local checkout_success, checkout_err = git.checkout(plugin_path, sha)
		if not checkout_success then
			return false, "Failed to checkout " .. name .. ": " .. (checkout_err or "unknown error")
		end
	end

	return true, nil
end

---Syncs plugins to match the plugin specs, updating the lockfile.
---This makes the lockfile match the plugin specs.
---For each spec:
---  - Clones if plugin doesn't exist
---  - Checks out to spec.commit OR spec.tag OR spec.branch (if specified)
---  - Falls back to lockfile commit if spec has no pin
---  - Updates lockfile with current HEAD
---Spec pins (commit/tag/branch) override the lockfile.
---@param specs PluginMap Map of plugin URL to PluginSpec.
---@param lockfile_path string Path to the lockfile.
---@param install_dir string Directory where plugins are installed.
---@return boolean success True if sync succeeded.
---@return string? error Error message if sync failed.
function M.sync(specs, lockfile_path, install_dir)
	local lock_data, read_err = lockfile.read(lockfile_path)
	if read_err then
		return false, read_err
	end

	local lock_changed = false

	for url, spec in pairs(specs) do
		local name = utils.get_name(url)
		local plugin_path = install_dir .. "/" .. name

		-- Clone if plugin doesn't exist
		if vim.fn.isdirectory(plugin_path) == 0 then
			print("Installing " .. name .. "...")
			local clone_success, clone_err = git.clone(url, plugin_path)
			if not clone_success then
				return false, "Failed to clone " .. name .. ": " .. (clone_err or "unknown error")
			end
		end

		-- Determine target ref: spec.commit OR spec.tag OR spec.branch OR lockfile OR resolve
		local target_ref = spec.commit or spec.tag or spec.branch

		if target_ref then
			-- Spec has a pin - checkout to it
			local checkout_success, checkout_err = git.checkout(plugin_path, target_ref)
			if not checkout_success then
				return false, "Failed to checkout " .. name .. ": " .. (checkout_err or "unknown error")
			end
		elseif lock_data[url] then
			-- No pin in spec - use lockfile
			local checkout_success, checkout_err = git.checkout(plugin_path, lock_data[url])
			if not checkout_success then
				return false, "Failed to checkout " .. name .. ": " .. (checkout_err or "unknown error")
			end
		else
			-- No pin, no lockfile - resolve to latest semver tag or remote head
			local resolved_ref, resolve_err = utils.resolve_target_ref(plugin_path)
			if resolve_err then
				return false, "Failed to resolve version for " .. name .. ": " .. resolve_err
			end
			local checkout_success, checkout_err = git.checkout(plugin_path, resolved_ref)
			if not checkout_success then
				return false, "Failed to checkout " .. name .. ": " .. (checkout_err or "unknown error")
			end
		end

		-- Update lockfile with current HEAD
		local current_sha, get_err = git.get_head(plugin_path)
		if get_err then
			return false, "Failed to get HEAD for " .. name .. ": " .. get_err
		end

		if lock_data[url] ~= current_sha then
			lock_data[url] = current_sha
			lock_changed = true
		end
	end

	-- Write lockfile if changed
	if lock_changed then
		local write_success, write_err = lockfile.write(lockfile_path, lock_data)
		if not write_success then
			return false, write_err
		end
	end

	return true, nil
end

---Returns all registered plugin specs (for debugging).
---@return table spec_map Map of URL to PluginSpec.
function M.get_registered()
	return registered_specs
end

return M
