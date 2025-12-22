local M = {}

---Syncs all plugins (install/checkout to latest versions or lockfile).
function M.sync()
	local wrench = require("wrench")
	local specs_module = require("wrench.specs")

	-- Check if import path is configured
	if not wrench.config.import then
		print("Error: No import path configured. Set { import = 'plugins' } in setup()")
		return
	end

	-- Scan specs
	print("Scanning plugins from '" .. wrench.config.import .. "'...")
	local specs, scan_err = specs_module.scan(wrench.config.import)
	if scan_err then
		print("Error scanning plugins: " .. scan_err)
		return
	end

	-- Sync
	print("Syncing " .. vim.tbl_count(specs) .. " plugins...")
	local success, err = wrench.sync(specs, wrench.config.lockfile_path, wrench.config.install_dir)
	if not success then
		print("Error syncing plugins: " .. err)
		return
	end

	print("✓ Sync complete!")
end

---Restores plugins to lockfile state (removes unlocked plugins).
function M.restore()
	local wrench = require("wrench")

	print("Restoring plugins from lockfile...")
	local success, err = wrench.restore(wrench.config.lockfile_path, wrench.config.install_dir)
	if not success then
		print("Error restoring plugins: " .. err)
		return
	end

	print("✓ Restore complete!")
end

---Interactive update flow - shows available updates and prompts for approval.
function M.update()
	local wrench = require("wrench")
	local specs_module = require("wrench.specs")
	local update = require("wrench.update")

	-- Check if import path is configured
	if not wrench.config.import then
		print("Error: No import path configured")
		return
	end

	-- Scan specs
	print("Checking for updates...")
	local specs, scan_err = specs_module.scan(wrench.config.import)
	if scan_err then
		print("Error scanning plugins: " .. scan_err)
		return
	end

	-- Collect updates
	local updates, collect_err = update.collect_updates(
		specs,
		wrench.config.lockfile_path,
		wrench.config.install_dir
	)
	if collect_err then
		print("Error collecting updates: " .. collect_err)
		return
	end

	local update_count = vim.tbl_count(updates)
	if update_count == 0 then
		print("No updates available")
		return
	end

	print("Found " .. update_count .. " update(s)\n")

	-- Interactive approval
	local approved = {}
	local index = 0

	for url, info in pairs(updates) do
		index = index + 1

		-- Show formatted update
		local lines = update.format_update(info)
		for _, line in ipairs(lines) do
			print(line)
		end
		print("")

		-- Prompt for approval
		local prompt = string.format("[%d/%d] Update? (y/n/q): ", index, update_count)
		local response = vim.fn.input(prompt)
		print("") -- newline after input

		if response:lower() == "q" then
			print("Update cancelled")
			return
		elseif response:lower() == "y" then
			approved[url] = info
		end

		print("") -- blank line between updates
	end

	-- Apply approved updates
	if vim.tbl_count(approved) == 0 then
		print("No updates applied")
		return
	end

	print("Applying " .. vim.tbl_count(approved) .. " update(s)...")
	local success, err = update.apply_updates(approved, wrench.config.lockfile_path, wrench.config.install_dir)
	if not success then
		print("Error applying updates: " .. err)
		return
	end

	print("✓ Updated " .. vim.tbl_count(approved) .. " plugin(s)!")
end

---Shows all registered plugins (for debugging).
function M.get_registered()
	local wrench = require("wrench")
	print(vim.inspect(wrench.get_registered()))
end

-- Create user commands
vim.api.nvim_create_user_command("WrenchSync", M.sync, {})
vim.api.nvim_create_user_command("WrenchRestore", M.restore, {})
vim.api.nvim_create_user_command("WrenchUpdate", M.update, {})
vim.api.nvim_create_user_command("WrenchGetRegistered", M.get_registered, {})

return M
