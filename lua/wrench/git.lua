local M = {}

---Clones a git repository.
---@param url string The repository URL or path to clone from.
---@param path string The destination path.
---@return boolean success True if clone succeeded.
---@return string? error Error message if clone failed.
function M.clone(url, path)
	local result = vim.system({ "git", "clone", url, path }):wait()

	if result.code ~= 0 then
		return false, "Failed to clone: " .. (result.stderr or "unknown error")
	end

	return true, nil
end

---Gets the commit SHA for a git revision.
---@param path string The repository path.
---@param rev? string The git revision (default: "HEAD"). Supports HEAD~1, HEAD~2, etc.
---@return string? sha The commit SHA, or nil if failed.
---@return string? error Error message if operation failed.
function M.get_head(path, rev)
	rev = rev or "HEAD"
	local result = vim.system({ "git", "rev-parse", rev }, { cwd = path }):wait()

	if result.code ~= 0 then
		return nil, "Failed to get HEAD: " .. (result.stderr or "unknown error")
	end

	local sha = vim.trim(result.stdout)
	return sha, nil
end

---Checks out a specific git reference (commit, branch, tag).
---@param path string The repository path.
---@param ref string The git reference to checkout.
---@return boolean success True if checkout succeeded.
---@return string? error Error message if checkout failed.
function M.checkout(path, ref)
	local result = vim.system({ "git", "checkout", ref }, { cwd = path }):wait()

	if result.code ~= 0 then
		return false, "Failed to checkout: " .. (result.stderr or "unknown error")
	end

	return true, nil
end

---Fetches from remote repository.
---@param path string The repository path.
---@return boolean success True if fetch succeeded.
---@return string? error Error message if fetch failed.
function M.fetch(path)
	local result = vim.system({ "git", "fetch", "--tags" }, { cwd = path }):wait()

	if result.code ~= 0 then
		return false, "Failed to fetch: " .. (result.stderr or "unknown error")
	end

	return true, nil
end

---Gets all tags in the repository.
---@param path string The repository path.
---@return string[]? tags Array of tag names, or nil if failed.
---@return string? error Error message if operation failed.
function M.get_tags(path)
	local result = vim.system({ "git", "tag", "-l" }, { cwd = path }):wait()

	if result.code ~= 0 then
		return nil, "Failed to get tags: " .. (result.stderr or "unknown error")
	end

	local stdout = vim.trim(result.stdout)
	if stdout == "" then
		return {}, nil
	end

	local tags = vim.split(stdout, "\n")
	return tags, nil
end

---Gets the commit SHA for a remote branch.
---@param path string The repository path.
---@param branch string The branch name (e.g., "master", "main").
---@return string? sha The commit SHA, or nil if failed.
---@return string? error Error message if operation failed.
function M.get_remote_head(path, branch)
	local ref = "origin/" .. branch
	local result = vim.system({ "git", "rev-parse", ref }, { cwd = path }):wait()

	if result.code ~= 0 then
		return nil, "Failed to get remote head: " .. (result.stderr or "unknown error")
	end

	local sha = vim.trim(result.stdout)
	return sha, nil
end

return M
