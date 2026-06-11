local M = {}

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

---Checks if a table is a single PluginSpec (has url field).
---@param tbl table The table to check.
---@return boolean is_single True if it's a single PluginSpec.
local function is_single_spec(tbl)
	return tbl.url ~= nil
end

---Validates spec.dependencies.
---@param spec table The plugin spec to validate.
---@param context string The file/spec context used in error messages.
---@return string? error Error message if invalid.
local function validate_dependencies(spec, context)
	if spec.dependencies == nil then
		return nil
	end

	if type(spec.dependencies) ~= "table" then
		return "Invalid dependencies in " .. context .. ": expected table, got " .. type(spec.dependencies)
	end

	if spec.dependencies.url ~= nil then
		return "Invalid dependencies in " .. context .. ': expected list of dependency refs, got single ref. Use { { url = "..." } }'
	end

	if next(spec.dependencies) ~= nil and #spec.dependencies == 0 then
		return "Invalid dependencies in " .. context .. ": expected list of dependency refs"
	end

	for index, dep in ipairs(spec.dependencies) do
		if type(dep) ~= "table" then
			return "Invalid dependency in " .. context .. " dependency #" .. index .. ": expected table with url field, got " .. type(dep)
		end

		if type(dep.url) ~= "string" or dep.url == "" then
			return "Invalid dependency in " .. context .. " dependency #" .. index .. ": expected non-empty url string"
		end
	end

	return nil
end

---Collects dependency URLs from a spec into the spec map (as bare refs).
---@param spec_map table<string, table> The map to collect into.
---@param spec table The spec whose dependencies to collect.
local function collect_dependencies(spec_map, spec)
	if not spec.dependencies then
		return
	end

	for _, dep in ipairs(spec.dependencies) do
		local url = dep.url
		if not spec_map[url] then
			-- Add as bare spec (just url, no config)
			spec_map[url] = { url = url }
		end
	end
end

---Scans a directory for plugin specs and returns a merged map.
---@param import_path string The import path relative to lua/ (e.g., "plugins").
---@param base_path? string Base lua directory path (defaults to stdpath config).
---@return table? spec_map Map of URL to canonical spec, or nil on error.
---@return string? error Error message if scanning failed.
function M.scan(import_path, base_path)
	base_path = base_path or (vim.fn.stdpath("config") .. "/lua")
	local full_path = base_path .. "/" .. import_path

	if vim.fn.isdirectory(full_path) == 0 then
		return {}, nil -- Empty if directory doesn't exist
	end

	local files = scan_directory(full_path)

	-- Phase 1: Require and collect all specs
	---@type table[]
	local all_specs = {}

	for _, file in ipairs(files) do
		local chunk, load_err = loadfile(file)
		if not chunk then
			return nil, "Failed to load " .. file .. ": " .. load_err
		end

		local ok, result = pcall(chunk)
		if not ok then
			return nil, "Failed to execute " .. file .. ": " .. result
		end

		if result ~= nil then
			if type(result) ~= "table" then
				return nil, "Invalid spec in " .. file .. ": expected table, got " .. type(result)
			end

			if is_single_spec(result) then
				local dep_err = validate_dependencies(result, file)
				if dep_err then
					return nil, dep_err
				end

				table.insert(all_specs, result)
			else
				-- List of specs
				for index, spec in ipairs(result) do
					local dep_err = validate_dependencies(spec, file .. " spec #" .. index)
					if dep_err then
						return nil, dep_err
					end

					table.insert(all_specs, spec)
				end
			end
		end
	end

	-- Phase 2: Merge specs by URL
	---@type table<string, table>
	local spec_map = {}

	for _, spec in ipairs(all_specs) do
		spec_map[spec.url] = spec
	end

	-- Phase 3: Collect bare dependency refs
	for _, spec in ipairs(all_specs) do
		collect_dependencies(spec_map, spec)
	end

	return spec_map, nil
end

return M
