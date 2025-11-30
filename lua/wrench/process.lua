local M = {}
local log = require("wrench.log")
local git = require("wrench.git")
local utils = require("wrench.utils")

--- Tracks which plugins have been processed (deduplication).
--- NOTE: Future optimization - plugins at same dependency level could be cloned in parallel.
---@type table<string, boolean>
local processed = {}

--- Tracks which plugins have been synced (deduplication).
---@type table<string, boolean>
local synced = {}

--- Tracks which plugins have been updated (deduplication).
---@type table<string, boolean>
local updated = {}

---Resets the processed/synced sets. Call between separate sessions if needed.
function M.reset()
	processed = {}
	synced = {}
	updated = {}
end

---Processes a single plugin (and its dependencies).
---@param plugin PluginConfig The plugin to process.
---@param lock_data LockData The lockfile data to update.
---@return boolean lock_changed True if lockfile was updated.
function M.plugin(plugin, lock_data)
	local url = plugin[1] or plugin.url

	-- Skip if already processed (deduplication)
	if processed[url] then --- NOTE: Future problem: What if same plugin with different branch/commit?
		return false
	end
	processed[url] = true

	local lock_changed = false

	-- Process dependencies recursively first
	if plugin.dependencies then
		for _, dep in ipairs(plugin.dependencies) do
			if M.plugin(dep, lock_data) then
				lock_changed = true
			end
		end
	end

	local install_path = utils.get_install_path(url)

	-- Clone if not already installed
	if vim.fn.isdirectory(install_path) == 0 then
		log.info("Installing " .. utils.get_name(url) .. "...")
		local opts = {
			branch = plugin.branch,
			tag = plugin.tag,
			commit = plugin.commit,
		}
		local ok, err = git.clone(url, install_path, opts)
		if not ok then
			log.error("Failed to clone " .. url .. ": " .. (err or "unknown error"))
			return lock_changed
		end

		log.info("Installed " .. url)
	end

	-- Ensure lockfile entry exists
	if not lock_data[url] then
		local commit = git.get_head(install_path)
		local branch = plugin.branch or git.get_branch(install_path)
		if commit and branch then
			lock_data[url] = { branch = branch, commit = commit }
			lock_changed = true
		end
	end

	-- Load plugin (immediately or deferred)
	if plugin.ft then
		vim.api.nvim_create_autocmd("FileType", {
			pattern = plugin.ft,
			once = true,
			callback = function()
				vim.opt.rtp:prepend(install_path)
				if plugin.config and type(plugin.config) == "function" then
					plugin.config()
				end
			end,
		})
	else
		vim.opt.rtp:prepend(install_path)
		if plugin.config and type(plugin.config) == "function" then
			plugin.config()
		end
	end

	return lock_changed
end

---Syncs a single plugin (and its dependencies) to the specified commit/tag/branch.
---@param plugin PluginConfig The plugin to sync.
---@param lock_data LockData The lockfile data to update.
---@return boolean lock_changed True if lockfile was updated.
function M.sync(plugin, lock_data)
	local url = plugin[1] or plugin.url

	-- Skip if already synced (deduplication)
	if synced[url] then
		return false
	end
	synced[url] = true

	local lock_changed = false

	-- Sync dependencies first
	if plugin.dependencies then
		for _, dep in ipairs(plugin.dependencies) do
			if M.sync(dep, lock_data) then
				lock_changed = true
			end
		end
	end

	local install_path = utils.get_install_path(url)

	-- Skip if not installed
	if vim.fn.isdirectory(install_path) == 0 then
		return lock_changed
	end

	local ok, err
	local new_commit

	if plugin.commit then
		-- Specific commit requested — checkout if different
		local current_commit = git.get_head(install_path)
		if current_commit and current_commit ~= plugin.commit then
			ok, err = git.checkout(install_path, plugin.commit)
			if ok then
				new_commit = plugin.commit
				log.info("Synced " .. url .. " to " .. plugin.commit:sub(1, 7))
			end
		else
			-- Already at correct commit, but ensure lockfile is updated
			new_commit = plugin.commit
		end
	elseif plugin.tag then
		-- Tag requested — checkout tag
		ok, err = git.checkout(install_path, plugin.tag)
		if ok then
			new_commit = git.get_head(install_path)
			log.info("Synced " .. url .. " to tag " .. plugin.tag)
		end
	elseif plugin.branch then
		-- Branch only — checkout branch first (in case of detached HEAD), then pull
		ok, err = git.checkout(install_path, plugin.branch)
		if ok then
			ok, err = git.pull(install_path)
			if ok then
				new_commit = git.get_head(install_path)
				log.info("Synced " .. url .. " to latest on " .. plugin.branch)
			end
		end
	end

	if not ok and err then
		log.error("Failed to sync " .. url .. ": " .. err)
	end

	if new_commit and plugin.branch then
		lock_data[url] = { branch = plugin.branch, commit = new_commit }
		lock_changed = true
	end

	return lock_changed
end

---Restores a plugin to the commit specified in lockfile.
---@param url string The plugin URL.
---@param lock_entry LockEntry The lockfile entry for this plugin.
---@return boolean success True if restore succeeded.
function M.restore(url, lock_entry)
	local install_path = utils.get_install_path(url)

	if vim.fn.isdirectory(install_path) == 0 then
		log.warn("Cannot restore " .. url .. ": not installed")
		return false
	end

	local current_commit = git.get_head(install_path)
	if current_commit == lock_entry.commit then
		return true -- Already at correct commit
	end

	local ok, err = git.checkout(install_path, lock_entry.commit)
	if ok then
		log.info("Restored " .. url .. " to " .. lock_entry.commit:sub(1, 7))
		return true
	else
		log.error("Failed to restore " .. url .. ": " .. (err or "unknown error"))
		return false
	end
end

---Updates lockfile with latest remote commits (no checkout).
---Skips plugins with pinned commits.
---@param plugin PluginConfig The plugin to update.
---@param lock_data LockData The lockfile data to update.
---@return boolean lock_changed True if lockfile was updated.
function M.update(plugin, lock_data)
	local url = plugin[1] or plugin.url

	-- Skip if already updated (deduplication)
	if updated[url] then
		return false
	end
	updated[url] = true

	local lock_changed = false

	-- Update dependencies first
	if plugin.dependencies then
		for _, dep in ipairs(plugin.dependencies) do
			if M.update(dep, lock_data) then
				lock_changed = true
			end
		end
	end

	local install_path = utils.get_install_path(url)

	-- Skip if not installed
	if vim.fn.isdirectory(install_path) == 0 then
		return lock_changed
	end

	-- Skip if pinned to specific commit
	if plugin.commit then
		log.info("Skipping " .. url .. " (pinned to commit)")
		return lock_changed
	end

	-- Fetch latest from remote
	local ok, err = git.fetch(install_path)
	if not ok then
		log.error("Failed to fetch " .. url .. ": " .. (err or "unknown error"))
		return lock_changed
	end

	local new_commit

	if plugin.tag then
		-- For tags, get the commit the tag points to after fetch
		-- (tags rarely change, but this handles it)
		ok, err = git.checkout(install_path, plugin.tag)
		if ok then
			new_commit = git.get_head(install_path)
		end
	elseif plugin.branch then
		-- Get the remote branch HEAD (without checking out)
		new_commit, err = git.get_remote_head(install_path, plugin.branch)
	end

	if not new_commit then
		log.error("Failed to get latest commit for " .. url .. ": " .. (err or "unknown error"))
		return lock_changed
	end

	-- Update lockfile if commit changed
	local current = lock_data[url]
	if not current or current.commit ~= new_commit then
		lock_data[url] = { branch = plugin.branch, commit = new_commit }
		log.info("Updated " .. url .. " → " .. new_commit:sub(1, 7))
		lock_changed = true
	end

	return lock_changed
end

---Removes a plugin directory.
---@param url string The plugin URL.
---@return boolean success True if removal succeeded.
function M.remove(url)
	local install_path = utils.get_install_path(url)

	if vim.fn.isdirectory(install_path) == 0 then
		return true -- Already gone
	end

	local ok = vim.fn.delete(install_path, "rf")
	if ok == 0 then
		log.info("Removed " .. url)
		return true
	else
		log.error("Failed to remove " .. url)
		return false
	end
end

return M
