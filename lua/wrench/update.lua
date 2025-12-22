local M = {}
local git = require("wrench.git")
local lockfile = require("wrench.lockfile")
local utils = require("wrench.utils")

---@class UpdateInfo
---@field url string Plugin URL
---@field old_sha string Current commit SHA
---@field new_sha string New commit SHA
---@field old_tag string? Old semver tag (if any)
---@field new_tag string? New semver tag (if any)
---@field commits string[] Commit messages between old and new
---@field is_major_bump boolean True if major version changed

---Collects available updates for unpinned plugins.
---@param specs table<string, PluginSpec> Map of plugin URL to spec
---@param lockfile_path string Path to lockfile
---@param install_dir string Directory where plugins are installed
---@return table<string, UpdateInfo>? updates Map of URL to UpdateInfo, or nil if error
---@return string? error Error message if failed
function M.collect_updates(specs, lockfile_path, install_dir)
	local lock_data, read_err = lockfile.read(lockfile_path)
	if read_err then
		return nil, read_err
	end

	local updates = {}

	for url, spec in pairs(specs) do
		-- Skip pinned plugins
		if spec.commit or spec.tag or spec.branch then
			goto continue
		end

		local name = utils.get_name(url)
		local plugin_path = install_dir .. "/" .. name

		-- Skip if plugin doesn't exist
		if vim.fn.isdirectory(plugin_path) == 0 then
			goto continue
		end

		-- Get current locked commit
		local old_sha = lock_data[url]
		if not old_sha then
			goto continue
		end

		-- Resolve new target (latest semver or remote head)
		print("Checking " .. name .. " for updates...")
		local new_sha, resolve_err = utils.resolve_target_ref(plugin_path)
		if resolve_err then
			return nil, "Failed to resolve update for " .. name .. ": " .. resolve_err
		end

		-- Skip if no update available
		if old_sha == new_sha then
			goto continue
		end

		-- Get commit log between old and new
		local log_result = vim.system(
			{ "git", "log", "--oneline", old_sha .. ".." .. new_sha },
			{ cwd = plugin_path }
		):wait()

		if log_result.code ~= 0 then
			return nil, "Failed to get commit log for " .. name
		end

		local commits = {}
		if vim.trim(log_result.stdout) ~= "" then
			commits = vim.split(vim.trim(log_result.stdout), "\n")
		end

		-- Skip if no commits between old and new (same commit or tag was moved)
		if #commits == 0 then
			goto continue
		end

		-- Try to get tags for old and new commits
		local old_tag = M.get_tag_for_commit(plugin_path, old_sha)
		local new_tag = M.get_tag_for_commit(plugin_path, new_sha)

		-- Detect major version bump
		local is_major_bump = false
		if old_tag and new_tag then
			local old_version = utils.parse_semver(old_tag)
			local new_version = utils.parse_semver(new_tag)
			if old_version and new_version then
				is_major_bump = new_version.major > old_version.major
			end
		end

		updates[url] = {
			url = url,
			old_sha = old_sha,
			new_sha = new_sha,
			old_tag = old_tag,
			new_tag = new_tag,
			commits = commits,
			is_major_bump = is_major_bump,
		}

		::continue::
	end

	return updates, nil
end

---Gets the semver tag for a commit (if any).
---@param plugin_path string Plugin repository path
---@param commit_sha string Commit SHA
---@return string? tag The semver tag, or nil if none
function M.get_tag_for_commit(plugin_path, commit_sha)
	-- Get all tags pointing to this commit
	local result = vim.system(
		{ "git", "tag", "--points-at", commit_sha },
		{ cwd = plugin_path }
	):wait()

	if result.code ~= 0 or vim.trim(result.stdout) == "" then
		return nil
	end

	local tags = vim.split(vim.trim(result.stdout), "\n")

	-- Find the first valid semver tag
	for _, tag in ipairs(tags) do
		if utils.parse_semver(tag) then
			return tag
		end
	end

	return nil
end

---Formats an update for display.
---@param info UpdateInfo The update information
---@return string[] lines Array of lines to display
function M.format_update(info)
	local lines = {}
	local name = utils.get_name(info.url)

	-- Build header: plugin-name (X commits)
	local header = name .. " (" .. #info.commits .. " commits)"

	-- Add version info if available
	if info.old_tag and info.new_tag then
		header = header .. " [" .. info.old_tag .. " → " .. info.new_tag .. "]"
	end

	-- Add warning for major bumps
	if info.is_major_bump then
		header = header .. " ⚠️  BREAKING"
	end

	table.insert(lines, header)

	-- Add commit messages (indented)
	for _, commit in ipairs(info.commits) do
		table.insert(lines, "  " .. commit)
	end

	return lines
end

---Applies updates by updating lockfile and checking out new commits.
---@param updates table<string, UpdateInfo> Map of URL to UpdateInfo
---@param lockfile_path string Path to lockfile
---@param install_dir string Directory where plugins are installed
---@return boolean success True if all updates applied successfully
---@return string? error Error message if failed
function M.apply_updates(updates, lockfile_path, install_dir)
	local lock_data, read_err = lockfile.read(lockfile_path)
	if read_err then
		return false, read_err
	end

	-- Update lockfile
	for url, info in pairs(updates) do
		lock_data[url] = info.new_sha
	end

	local write_success, write_err = lockfile.write(lockfile_path, lock_data)
	if not write_success then
		return false, write_err
	end

	-- Checkout new commits
	for url, info in pairs(updates) do
		local name = utils.get_name(url)
		local plugin_path = install_dir .. "/" .. name

		print("Updating " .. name .. "...")
		local checkout_success, checkout_err = git.checkout(plugin_path, info.new_sha)
		if not checkout_success then
			return false, "Failed to checkout " .. name .. ": " .. (checkout_err or "unknown error")
		end
	end

	return true, nil
end

return M
