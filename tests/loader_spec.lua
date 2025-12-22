local loader = require("wrench.loader")

describe("loader", function()
	-- Test helpers
	local new_test_context = function()
		local ctx = {}
		ctx.dir = vim.fn.tempname()
		ctx.install_dir = ctx.dir .. "/plugins"
		vim.fn.mkdir(ctx.install_dir, "p")

		ctx.cleanup = function()
			vim.fn.delete(ctx.dir, "rf")
		end

		return ctx
	end

	local create_folder = function(path, name)
		local plugin_path = path .. "/" .. name
		vim.fn.mkdir(plugin_path, "p")
		return plugin_path
	end

	local assert_in_rtp = function(plugin_path)
		local rtp = vim.opt.rtp:get()
		for _, path in ipairs(rtp) do
			if path == plugin_path then
				return true
			end
		end
		return false
	end

	describe("setup_loading", function()
		it("loads plugin eagerly when no lazy triggers", function()
			-- arrange
			local ctx = new_test_context()
			local plugin_path = create_folder(ctx.install_dir, "test-plugin")

			local specs = {
				["https://github.com/user/test-plugin"] = {
					url = "https://github.com/user/test-plugin",
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- assert
			assert.is_true(assert_in_rtp(plugin_path), "Plugin should be in rtp")

			ctx.cleanup()
		end)

		it("runs config function when loading plugin", function()
			-- arrange
			local ctx = new_test_context()
			create_folder(ctx.install_dir, "config-plugin")

			local config_called = false
			local specs = {
				["https://github.com/user/config-plugin"] = {
					url = "https://github.com/user/config-plugin",
					config = function()
						config_called = true
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- assert
			assert.is_true(config_called, "Config function should be called")

			ctx.cleanup()
		end)

		it("loads dependencies before main plugin", function()
			-- arrange
			local ctx = new_test_context()
			create_folder(ctx.install_dir, "dep-plugin")
			create_folder(ctx.install_dir, "main-plugin")

			local load_order = {}
			local specs = {
				["https://github.com/user/main-plugin"] = {
					url = "https://github.com/user/main-plugin",
					dependencies = {
						{ url = "https://github.com/user/dep-plugin" },
					},
					config = function()
						table.insert(load_order, "main")
					end,
				},
				["https://github.com/user/dep-plugin"] = {
					url = "https://github.com/user/dep-plugin",
					config = function()
						table.insert(load_order, "dep")
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- assert
			assert.are.equal(2, #load_order)
			assert.are.equal("dep", load_order[1], "Dependency should load first")
			assert.are.equal("main", load_order[2], "Main plugin should load second")

			ctx.cleanup()
		end)

		it("lazy loads plugin on filetype", function()
			-- arrange
			local ctx = new_test_context()
			local plugin_path = create_folder(ctx.install_dir, "ft-plugin")

			local config_called = false
			local specs = {
				["https://github.com/user/ft-plugin"] = {
					url = "https://github.com/user/ft-plugin",
					ft = { "testft" }, -- Use fake filetype to avoid built-in ftplugin noise
					config = function()
						config_called = true
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- assert - plugin should NOT be loaded yet
			assert.is_false(assert_in_rtp(plugin_path), "Plugin should not be in rtp yet")
			assert.is_false(config_called, "Config should not be called yet")

			-- Trigger FileType event
			vim.api.nvim_exec_autocmds("FileType", { pattern = "testft" })

			-- assert - plugin should now be loaded
			assert.is_true(assert_in_rtp(plugin_path), "Plugin should be in rtp after FileType")
			assert.is_true(config_called, "Config should be called after FileType")

			ctx.cleanup()
		end)

		it("does NOT load plugin on wrong filetype", function()
			-- arrange
			local ctx = new_test_context()
			local plugin_path = create_folder(ctx.install_dir, "ft-plugin")

			local config_called = false
			local specs = {
				["https://github.com/user/ft-plugin"] = {
					url = "https://github.com/user/ft-plugin",
					ft = { "testft" }, -- Plugin should load on testft
					config = function()
						config_called = true
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- Trigger WRONG FileType event
			vim.api.nvim_exec_autocmds("FileType", { pattern = "wrongft" })

			-- assert - plugin should NOT be loaded
			assert.is_false(assert_in_rtp(plugin_path), "Plugin should not be in rtp after wrong filetype")
			assert.is_false(config_called, "Config should not be called after wrong filetype")

			ctx.cleanup()
		end)

		it("lazy loads plugin on event", function()
			-- arrange
			local ctx = new_test_context()
			local plugin_path = create_folder(ctx.install_dir, "event-plugin")

			local config_called = false
			local specs = {
				["https://github.com/user/event-plugin"] = {
					url = "https://github.com/user/event-plugin",
					event = { "BufRead" },
					config = function()
						config_called = true
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- assert - plugin should NOT be loaded yet
			assert.is_false(assert_in_rtp(plugin_path), "Plugin should not be in rtp yet")
			assert.is_false(config_called, "Config should not be called yet")

			-- Trigger BufRead event
			vim.api.nvim_exec_autocmds("BufRead", {})

			-- assert - plugin should now be loaded
			assert.is_true(assert_in_rtp(plugin_path), "Plugin should be in rtp after BufRead")
			assert.is_true(config_called, "Config should be called after BufRead")

			ctx.cleanup()
		end)

		it("does NOT load plugin on wrong event", function()
			-- arrange
			local ctx = new_test_context()
			local plugin_path = create_folder(ctx.install_dir, "event-plugin")

			local config_called = false
			local specs = {
				["https://github.com/user/event-plugin"] = {
					url = "https://github.com/user/event-plugin",
					event = { "BufRead" }, -- Plugin should load on BufRead
					config = function()
						config_called = true
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- Trigger WRONG event
			vim.api.nvim_exec_autocmds("BufWrite", {})

			-- assert - plugin should NOT be loaded
			assert.is_false(assert_in_rtp(plugin_path), "Plugin should not be in rtp after wrong event")
			assert.is_false(config_called, "Config should not be called after wrong event")

			ctx.cleanup()
		end)

		it("lazy loads plugin on key press", function()
			-- arrange
			local ctx = new_test_context()
			local plugin_path = create_folder(ctx.install_dir, "keys-plugin")

			local config_called = false
			local key_pressed = false
			local specs = {
				["https://github.com/user/keys-plugin"] = {
					url = "https://github.com/user/keys-plugin",
					keys = {
						{
							lhs = "<leader>t",
							rhs = function()
								key_pressed = true
							end,
							mode = { "n" },
						},
					},
					config = function()
						config_called = true
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- assert - plugin should NOT be loaded yet
			assert.is_false(assert_in_rtp(plugin_path), "Plugin should not be in rtp yet")
			assert.is_false(config_called, "Config should not be called yet")

			-- Press the key
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>t", true, false, true), "x", false)

			-- assert - plugin should now be loaded
			assert.is_true(assert_in_rtp(plugin_path), "Plugin should be in rtp after key press")
			assert.is_true(config_called, "Config should be called after key press")
			assert.is_true(key_pressed, "Key handler should be executed")

			ctx.cleanup()
		end)

		it("does NOT load plugin on wrong key press", function()
			-- arrange
			local ctx = new_test_context()
			local plugin_path = create_folder(ctx.install_dir, "keys-plugin")

			local config_called = false
			local specs = {
				["https://github.com/user/keys-plugin"] = {
					url = "https://github.com/user/keys-plugin",
					keys = {
						{
							lhs = "<leader>t", -- Plugin should load on <leader>t
							rhs = function()
								-- This should not be called
							end,
							mode = { "n" },
						},
					},
					config = function()
						config_called = true
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- Press WRONG key
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>x", true, false, true), "x", false)

			-- assert - plugin should NOT be loaded
			assert.is_false(assert_in_rtp(plugin_path), "Plugin should not be in rtp after wrong key")
			assert.is_false(config_called, "Config should not be called after wrong key")

			ctx.cleanup()
		end)
	end)
end)
