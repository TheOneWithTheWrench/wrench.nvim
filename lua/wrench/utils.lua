local M = {}

---Extracts the plugin name from a URL.
---@param url string The full URL (e.g., "https://github.com/owner/plugin").
---@return string name The plugin name (e.g., "plugin").
function M.get_name(url)
	local name = url:match(".*/(.+)$") or url
	return name:gsub("%.git$", "")
end

---Returns a collision-safe install directory name for a plugin.
---@param url string
---@return string
function M.get_plugin_dir_name(url)
	return string.format("%s-%s", M.get_name(url), vim.fn.sha256(url):sub(1, 8))
end

---Returns the canonical plugin install path.
---@param install_dir string
---@param url string
---@return string
function M.get_plugin_path(install_dir, url)
	return install_dir .. "/" .. M.get_plugin_dir_name(url)
end

---Resolves the plugin path, migrating legacy basename-only installs when found.
---@param install_dir string
---@param url string
---@return string? plugin_path
---@return string? error
function M.resolve_plugin_path(install_dir, url)
	local plugin_path = M.get_plugin_path(install_dir, url)
	if vim.fn.isdirectory(plugin_path) == 1 then
		return plugin_path, nil
	end

	local legacy_path = install_dir .. "/" .. M.get_name(url)
	if vim.fn.isdirectory(legacy_path) == 1 then
		local rename_result = vim.fn.rename(legacy_path, plugin_path)
		if rename_result ~= 0 then
			return nil, "Failed to migrate plugin path for " .. url
		end
	end

	return plugin_path, nil
end

---Parses a semver tag into components.
---@param tag string The tag to parse (e.g., "v1.2.3", "1.2.3").
---@return table? version Table with {major, minor, patch} or nil if invalid/pre-release.
function M.parse_semver(tag)
	-- Skip pre-release versions (contain - or +)
	if tag:match("[-+]") then
		return nil
	end

	-- Try to match v1.2.3 or 1.2.3 format
	local major, minor, patch = tag:match("^v?(%d+)%.(%d+)%.(%d+)$")

	if not major then
		return nil
	end

	return {
		major = tonumber(major),
		minor = tonumber(minor),
		patch = tonumber(patch),
	}
end

---Gets the latest semver tag from a list of tags.
---@param tags string[] Array of tag names.
---@return string? tag The latest semver tag, or nil if none found.
function M.get_latest_semver_tag(tags)
	local latest_tag = nil
	local latest_version = nil

	for _, tag in ipairs(tags) do
		local version = M.parse_semver(tag)
		if version then
			if not latest_version then
				latest_tag = tag
				latest_version = version
			else
				-- Compare versions: major > minor > patch
				local is_newer = false
				if version.major > latest_version.major then
					is_newer = true
				elseif version.major == latest_version.major then
					if version.minor > latest_version.minor then
						is_newer = true
					elseif version.minor == latest_version.minor then
						if version.patch > latest_version.patch then
							is_newer = true
						end
					end
				end

				if is_newer then
					latest_tag = tag
					latest_version = version
				end
			end
		end
	end

	return latest_tag
end

---Resolves the target ref for a plugin spec.
---@param plugin_path string The plugin repository path.
---@param spec PluginSpec
---@param locked_sha? string Locked SHA to use when the spec is otherwise unpinned.
---@return string? sha The commit SHA to checkout, or nil if failed.
---@return string? error Error message if resolution failed.
function M.resolve_ref(plugin_path, spec, locked_sha)
	local pinned_ref = spec.commit or spec.tag
	if pinned_ref then
		return pinned_ref, nil
	end

	if locked_sha and not spec.branch then
		return locked_sha, nil
	end

	local git = require("wrench.git")

	local fetch_success, fetch_err = git.fetch(plugin_path)
	if not fetch_success then
		return nil, fetch_err
	end

	if spec.branch then
		local sha, err = git.get_remote_head(plugin_path, spec.branch)
		if err then
			return nil, err
		end

		return sha, nil
	end

	-- Get all tags
	local tags, tags_err = git.get_tags(plugin_path)
	if tags_err then
		return nil, tags_err
	end

	-- Try to find latest semver tag
	local latest_tag = M.get_latest_semver_tag(tags)
	if latest_tag then
		-- Get commit SHA for the tag
		local sha, sha_err = git.get_head(plugin_path, latest_tag)
		if sha_err then
			return nil, sha_err
		end
		return sha, nil
	end

	local sha, err = git.get_remote_default_head(plugin_path)
	if err then
		return nil, err
	end

	return sha, nil
end

return M
