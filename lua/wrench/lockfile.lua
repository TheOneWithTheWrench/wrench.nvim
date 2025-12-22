local M = {}

-- Forward declarations
local format_json

---Reads the lockfile from disk.
---@param path string Path to the lockfile.
---@return table data The parsed lockfile, or empty table if file doesn't exist.
---@return string? error Error message if parsing failed.
function M.read(path)
	if vim.fn.filereadable(path) == 0 then
		return {}, nil
	end

	local lines = vim.fn.readfile(path)
	local content = table.concat(lines, "\n")

	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		return {}, "Failed to parse lockfile: " .. data
	end

	return data, nil
end

---Writes lock data to disk as JSON.
---@param path string Path to the lockfile.
---@param data table The lock data to write.
---@return boolean success True if write succeeded.
---@return string? error Error message if write failed.
function M.write(path, data)
	local json = format_json(data)
	local lines = vim.split(json, "\n")
	local result = vim.fn.writefile(lines, path)

	if result ~= 0 then
		return false, "Failed to write lockfile"
	end

	return true, nil
end

---Formats lock data as pretty JSON.
---@param data table
---@return string
format_json = function(data)
	local lines = { "{" }
	local keys = vim.tbl_keys(data)
	table.sort(keys)

	for i, url in ipairs(keys) do
		local commit = data[url]
		local comma = i < #keys and "," or ""
		table.insert(lines, string.format('  "%s": "%s"%s', url, commit, comma))
	end

	table.insert(lines, "}")
	return table.concat(lines, "\n")
end

return M
