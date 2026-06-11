local loader = require("wrench.loader")
local utils = require("wrench.utils")

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

	local create_plugin_folder = function(path, url)
		local plugin_path = utils.get_plugin_path(path, url)
		vim.fn.mkdir(plugin_path, "p")
		return plugin_path
	end

	local write_file = function(path, content)
		vim.fn.writefile(vim.split(content, "\n"), path)
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
			local url = "https://github.com/user/test-plugin"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)

			local specs = {
				[url] = {
					url = url,
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
			local url = "https://github.com/user/config-plugin"
			create_plugin_folder(ctx.install_dir, url)

			local config_called = false
			local specs = {
				[url] = {
					url = url,
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
			local dep_url = "https://github.com/user/dep-plugin"
			local main_url = "https://github.com/user/main-plugin"
			create_plugin_folder(ctx.install_dir, dep_url)
			create_plugin_folder(ctx.install_dir, main_url)

			local load_order = {}
			local specs = {
				[main_url] = {
					url = main_url,
					dependencies = {
						{ url = dep_url },
					},
					config = function()
						table.insert(load_order, "main")
					end,
				},
				[dep_url] = {
					url = dep_url,
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

		it("loads dependency-only specs only when a dependent plugin loads", function()
			-- arrange
			local ctx = new_test_context()
			local dep_url = "https://github.com/user/dep-only-plugin"
			local main_url = "https://github.com/user/lazy-main-plugin"
			local dep_path = create_plugin_folder(ctx.install_dir, dep_url)
			local main_path = create_plugin_folder(ctx.install_dir, main_url)

			local load_order = {}
			local key_pressed = false
			local specs = {
				[main_url] = {
					url = main_url,
					dependencies = {
						{ url = dep_url },
					},
					keys = {
						{
							lhs = "<leader>d",
							rhs = function()
								key_pressed = true
							end,
							mode = { "n" },
						},
					},
					config = function()
						table.insert(load_order, "main")
					end,
				},
				[dep_url] = {
					url = dep_url,
					__wrench_dependency_only = true,
					config = function()
						table.insert(load_order, "dep")
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- assert - neither the lazy plugin nor its dependency should load during setup
			assert.is_false(assert_in_rtp(dep_path), "Dependency should not be in rtp before dependent loads")
			assert.is_false(assert_in_rtp(main_path), "Main plugin should not be in rtp before lazy trigger")
			assert.are.equal(0, #load_order)

			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>d", true, false, true), "x", false)

			assert.is_true(assert_in_rtp(dep_path), "Dependency should be in rtp after dependent loads")
			assert.is_true(assert_in_rtp(main_path), "Main plugin should be in rtp after lazy trigger")
			assert.are.same({ "dep", "main" }, load_order)
			assert.is_true(key_pressed, "Key handler should be executed")

			ctx.cleanup()
		end)

		it("lazy loads plugin on filetype", function()
			-- arrange
			local ctx = new_test_context()
			local url = "https://github.com/user/ft-plugin"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)

			local config_called = false
			local specs = {
				[url] = {
					url = url,
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
			local url = "https://github.com/user/ft-plugin"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)

			local config_called = false
			local specs = {
				[url] = {
					url = url,
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
			local url = "https://github.com/user/event-plugin"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)

			local config_called = false
			local specs = {
				[url] = {
					url = url,
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
			local url = "https://github.com/user/event-plugin"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)

			local config_called = false
			local specs = {
				[url] = {
					url = url,
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
			local url = "https://github.com/user/keys-plugin"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)

			local config_called = false
			local key_pressed = false
			local specs = {
				[url] = {
					url = url,
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
			local url = "https://github.com/user/keys-plugin"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)

			local config_called = false
			local specs = {
				[url] = {
					url = url,
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

		it("lazy loads plugin on command", function()
			-- arrange
			local ctx = new_test_context()
			local url = "https://github.com/user/cmd-plugin"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)

			local config_called = false
			local specs = {
				[url] = {
					url = url,
					cmd = { "TestCmd" },
					config = function()
						config_called = true
						-- After loading, register the real command
						vim.api.nvim_create_user_command("TestCmd", function()
							-- Real command implementation
						end, {})
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- assert - plugin should NOT be loaded yet
			assert.is_false(assert_in_rtp(plugin_path), "Plugin should not be in rtp yet")
			assert.is_false(config_called, "Config should not be called yet")

			-- Execute the command
			vim.cmd("TestCmd")

			-- assert - plugin should now be loaded
			assert.is_true(assert_in_rtp(plugin_path), "Plugin should be in rtp after command")
			assert.is_true(config_called, "Config should be called after command")

			-- cleanup command
			vim.api.nvim_del_user_command("TestCmd")
			ctx.cleanup()
		end)

		it("removes sibling command stubs before loading plugin", function()
			local ctx = new_test_context()
			local url = "https://github.com/user/cmd-plugin-siblings"
			create_plugin_folder(ctx.install_dir, url)

			local command_calls = {}
			local specs = {
				[url] = {
					url = url,
					cmd = { "FirstCmd", "SecondCmd" },
					config = function()
						vim.api.nvim_create_user_command("FirstCmd", function()
							table.insert(command_calls, "first")
						end, {})
						vim.api.nvim_create_user_command("SecondCmd", function()
							table.insert(command_calls, "second")
						end, {})
					end,
				},
			}

			loader.setup_loading(specs, ctx.install_dir)

			vim.cmd("FirstCmd")
			vim.cmd("SecondCmd")

			assert.are.same({ "first", "second" }, command_calls)

			vim.api.nvim_del_user_command("FirstCmd")
			vim.api.nvim_del_user_command("SecondCmd")
			ctx.cleanup()
		end)

		it("replays lazy command with bang and modifiers", function()
			local ctx = new_test_context()
			local url = "https://github.com/user/cmd-plugin-replay"
			create_plugin_folder(ctx.install_dir, url)

			local observed
			local specs = {
				[url] = {
					url = url,
					cmd = { "ReplayCmd" },
					config = function()
						vim.api.nvim_create_user_command("ReplayCmd", function(opts)
							observed = {
								args = opts.args,
								bang = opts.bang,
								mods = opts.mods,
							}
						end, { nargs = "*", bang = true })
					end,
				},
			}

			loader.setup_loading(specs, ctx.install_dir)

			vim.cmd("silent ReplayCmd! foo bar")

			assert.are.same({ args = "foo bar", bang = true, mods = "silent" }, observed)

			vim.api.nvim_del_user_command("ReplayCmd")
			ctx.cleanup()
		end)

		it("does NOT load plugin on wrong command", function()
			-- arrange
			local ctx = new_test_context()
			local url = "https://github.com/user/cmd-plugin-wrong"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)

			local config_called = false
			local specs = {
				[url] = {
					url = url,
					cmd = { "TestCmdWrong" }, -- Plugin should load on :TestCmdWrong
					config = function()
						config_called = true
					end,
				},
			}

			-- act
			loader.setup_loading(specs, ctx.install_dir)

			-- Execute a DIFFERENT command (use built-in)
			vim.cmd("echo 'hello'")

			-- assert - plugin should NOT be loaded
			assert.is_false(assert_in_rtp(plugin_path), "Plugin should not be in rtp after wrong command")
			assert.is_false(config_called, "Config should not be called after wrong command")

			-- cleanup stub command (still exists since plugin wasn't loaded)
			vim.api.nvim_del_user_command("TestCmdWrong")
			ctx.cleanup()
		end)

		it("sources vim plugin files with escaped filenames", function()
			local ctx = new_test_context()
			local url = "https://github.com/user/space-plugin"
			local plugin_path = create_plugin_folder(ctx.install_dir, url)
			vim.fn.mkdir(plugin_path .. "/plugin", "p")
			write_file(plugin_path .. "/plugin/pipe|file.vim", "let g:wrench_space_file_loaded = 1")

			vim.g.wrench_space_file_loaded = nil
			local specs = {
				[url] = {
					url = url,
				},
			}

			loader.setup_loading(specs, ctx.install_dir)

			assert.are.equal(1, vim.g.wrench_space_file_loaded)

			vim.g.wrench_space_file_loaded = nil
			ctx.cleanup()
		end)
	end)
end)
