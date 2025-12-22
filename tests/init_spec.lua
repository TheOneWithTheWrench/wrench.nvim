local wrench = require("wrench.init")
local lockfile = require("wrench.lockfile")
local git = require("wrench.git")

describe("wrench", function()
	-- Test helpers
	local new_test_context = function()
		local ctx = {}
		ctx.dir = vim.fn.tempname()
		vim.fn.mkdir(ctx.dir, "p")
		ctx.source = ctx.dir .. "/source"
		ctx.install_dir = ctx.dir .. "/plugins"
		ctx.lockfile_path = ctx.dir .. "/lock.json"
		ctx.cleanup = function()
			vim.fn.delete(ctx.dir, "rf")
		end
		return ctx
	end

	local init_repo = function(path, ...)
		vim.fn.mkdir(path, "p")
		vim.system({ "git", "init" }, { cwd = path }):wait()
		vim.system({ "git", "config", "--local", "user.email", "test@test.com" }, { cwd = path }):wait()
		vim.system({ "git", "config", "--local", "user.name", "Test" }, { cwd = path }):wait()
		vim.system({ "git", "config", "--local", "commit.gpgsign", "false" }, { cwd = path }):wait()

		-- Apply options
		for _, opt in ipairs({ ... }) do
			opt(path)
		end
	end

	-- Functional option pattern. I am a golang programmer after all
	local with_commit = function(message)
		return function(repo_path)
			vim.system({ "git", "commit", "--allow-empty", "-m", message }, { cwd = repo_path }):wait()
		end
	end

	local with_tag = function(tag_name)
		return function(repo_path)
			vim.system({ "git", "tag", tag_name }, { cwd = repo_path }):wait()
		end
	end


	describe("restore", function()
		it("restores plugin to locked commit when plugin exists", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"), with_commit("second"))
			local first_sha = git.get_head(ctx.source, "HEAD~1")
			local second_sha = git.get_head(ctx.source)

			-- Clone to install_dir (will be at second commit)
			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/source")

			-- Verify we're at second commit
			local before_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(second_sha, before_sha)

			-- Write lockfile pointing to first commit
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = first_sha,
			})

			-- act
			local success, err = wrench.restore(ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)
			local after_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(first_sha, after_sha)

			ctx.cleanup()
		end)

		it("clones and restores plugin when plugin does not exist", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"), with_commit("second"))
			local first_sha = git.get_head(ctx.source, "HEAD~1")

			-- Write lockfile pointing to first commit (plugin not installed yet)
			vim.fn.mkdir(ctx.install_dir, "p")
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = first_sha,
			})

			-- act
			local success, err = wrench.restore(ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)
			assert.are.equal(1, vim.fn.isdirectory(ctx.install_dir .. "/source/.git"))
			local after_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(first_sha, after_sha)

			ctx.cleanup()
		end)

		it("succeeds with empty lockfile", function()
			-- arrange
			local ctx = new_test_context()
			vim.fn.mkdir(ctx.install_dir, "p")
			lockfile.write(ctx.lockfile_path, {})

			-- act
			local success, err = wrench.restore(ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			ctx.cleanup()
		end)

		it("returns error when commit in lockfile is invalid", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"))

			-- Clone plugin
			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/source")

			-- Write lockfile with invalid SHA
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = "0000000000000000000000000000000000000000",
			})

			-- act
			local success, err = wrench.restore(ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_false(success)
			assert.is_not_nil(err)
			assert.is_truthy(err:match("checkout") or err:match("source"))

			ctx.cleanup()
		end)

		it("succeeds when lockfile does not exist", function()
			-- arrange
			local ctx = new_test_context()
			vim.fn.mkdir(ctx.install_dir, "p")

			-- act
			local success, err = wrench.restore(ctx.dir .. "/nonexistent.json", ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			ctx.cleanup()
		end)

		it("removes plugins not in lockfile", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"))
			local sha = git.get_head(ctx.source)

			-- Install two plugins
			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/plugin1")
			git.clone(ctx.source, ctx.install_dir .. "/plugin2")

			-- Lockfile only has plugin1
			lockfile.write(ctx.lockfile_path, {
				["https://github.com/user/plugin1"] = sha,
			})

			-- act
			local success, err = wrench.restore(ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			-- plugin1 should exist
			assert.are.equal(1, vim.fn.isdirectory(ctx.install_dir .. "/plugin1"))

			-- plugin2 should be removed
			assert.are.equal(0, vim.fn.isdirectory(ctx.install_dir .. "/plugin2"))

			ctx.cleanup()
		end)
	end)

	describe("sync", function()
		it("syncs new plugin without pin and locks it", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"))
			local specs = {
				[ctx.source] = {}, -- No pin
			}

			-- act
			local success, err = wrench.sync(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			-- Plugin should be cloned
			assert.are.equal(1, vim.fn.isdirectory(ctx.install_dir .. "/source/.git"))

			-- Lockfile should have current HEAD
			local lock_data = lockfile.read(ctx.lockfile_path)
			local current_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(current_sha, lock_data[ctx.source])

			ctx.cleanup()
		end)

		it("syncs new plugin with commit pin", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"), with_commit("second"))
			local first_sha = git.get_head(ctx.source, "HEAD~1")
			local second_sha = git.get_head(ctx.source)

			local specs = {
				[ctx.source] = { commit = first_sha }, -- Pin to first commit
			}

			-- act
			local success, err = wrench.sync(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			-- Plugin should be at pinned commit
			local current_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(first_sha, current_sha)
			assert.are_not_equal(second_sha, current_sha)

			-- Lockfile should have pinned commit
			local lock_data = lockfile.read(ctx.lockfile_path)
			assert.are.equal(first_sha, lock_data[ctx.source])

			ctx.cleanup()
		end)

		it("syncs existing plugin, spec pin overrides lockfile", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"), with_commit("second"))
			local first_sha = git.get_head(ctx.source, "HEAD~1")
			local second_sha = git.get_head(ctx.source)

			-- Clone plugin and write lockfile with second commit
			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/source")
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = second_sha,
			})

			-- Spec pins to first commit (overrides lockfile)
			local specs = {
				[ctx.source] = { commit = first_sha },
			}

			-- act
			local success, err = wrench.sync(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			-- Plugin should be at spec's pinned commit (not lockfile)
			local current_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(first_sha, current_sha)

			-- Lockfile should be updated to match spec
			local lock_data = lockfile.read(ctx.lockfile_path)
			assert.are.equal(first_sha, lock_data[ctx.source])

			ctx.cleanup()
		end)

		it("syncs existing plugin with no pin, uses lockfile", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"), with_commit("second"))
			local first_sha = git.get_head(ctx.source, "HEAD~1")

			-- Clone plugin at second commit
			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/source")

			-- Lockfile points to first commit
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = first_sha,
			})

			-- Spec has no pin
			local specs = {
				[ctx.source] = {},
			}

			-- act
			local success, err = wrench.sync(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			-- Plugin should be at lockfile commit
			local current_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(first_sha, current_sha)

			-- Lockfile should stay the same
			local lock_data = lockfile.read(ctx.lockfile_path)
			assert.are.equal(first_sha, lock_data[ctx.source])

			ctx.cleanup()
		end)

		it("syncs new plugin with no pin, resolves to latest semver tag", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source,
				with_commit("initial"),
				with_tag("v1.0.0"),
				with_commit("second"),
				with_tag("v2.0.0"),
				with_commit("third-untagged")  -- HEAD is AHEAD of latest tag
			)
			local v2_sha = git.get_head(ctx.source, "v2.0.0")
			local head_sha = git.get_head(ctx.source)  -- third-untagged commit

			-- Verify HEAD is different from v2.0.0
			assert.are_not.equal(v2_sha, head_sha)

			local specs = {
				[ctx.source] = {}, -- No pin
			}

			-- act
			local success, err = wrench.sync(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			-- Plugin should be at v2.0.0 (latest semver tag), NOT at HEAD
			local current_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(v2_sha, current_sha)
			assert.are_not.equal(head_sha, current_sha)

			-- Lockfile should have v2.0.0 commit
			local lock_data = lockfile.read(ctx.lockfile_path)
			assert.are.equal(v2_sha, lock_data[ctx.source])

			ctx.cleanup()
		end)

		it("syncs new plugin with no tags, uses remote head", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"))
			local head_sha = git.get_head(ctx.source)

			local specs = {
				[ctx.source] = {}, -- No pin
			}

			-- act
			local success, err = wrench.sync(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			-- Plugin should be at remote head
			local current_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(head_sha, current_sha)

			-- Lockfile should have head commit
			local lock_data = lockfile.read(ctx.lockfile_path)
			assert.are.equal(head_sha, lock_data[ctx.source])

			ctx.cleanup()
		end)
	end)

	describe("setup", function()
		it("scans, syncs, and loads plugins", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source, with_commit("initial"))

			-- Create lua/plugins directory structure
			local lua_dir = ctx.dir .. "/lua"
			local plugins_dir = lua_dir .. "/plugins"
			vim.fn.mkdir(plugins_dir, "p")

			-- Write a plugin spec file
			local spec_file = plugins_dir .. "/test.lua"
			local spec_content = string.format([[
return {
	url = "%s",
}
]], ctx.source)
			vim.fn.writefile(vim.split(spec_content, "\n"), spec_file)

			-- Add lua_dir to package.path
			local old_path = package.path
			package.path = lua_dir .. "/?.lua;" .. package.path

			local config_called = false

			-- act
			wrench.setup("plugins", {
				base_path = lua_dir,
				install_dir = ctx.install_dir,
				lockfile_path = ctx.lockfile_path,
			})

			-- assert
			-- Plugin should be installed
			assert.are.equal(1, vim.fn.isdirectory(ctx.install_dir .. "/source/.git"))

			-- Plugin should be in lockfile
			local lock_data = lockfile.read(ctx.lockfile_path)
			assert.is_not_nil(lock_data[ctx.source])

			-- Plugin should be in rtp
			local rtp = vim.opt.rtp:get()
			local found = false
			for _, path in ipairs(rtp) do
				if path == ctx.install_dir .. "/source" then
					found = true
					break
				end
			end
			assert.is_true(found, "Plugin should be in rtp")

			-- cleanup
			package.path = old_path
			ctx.cleanup()
		end)
	end)

	describe("ensure_installed", function()
		it("checks out to spec branch when cloning new plugin", function()
			-- arrange
			local ctx = new_test_context()

			-- Create repo with two branches
			init_repo(ctx.source, with_commit("initial on master"))

			-- Create main branch with different commit
			vim.system({ "git", "checkout", "-b", "main" }, { cwd = ctx.source }):wait()
			vim.system({ "git", "commit", "--allow-empty", "-m", "commit on main" }, { cwd = ctx.source }):wait()
			local main_sha = git.get_head(ctx.source, "main")

			-- Go back to master (so clone gets master by default)
			vim.system({ "git", "checkout", "master" }, { cwd = ctx.source }):wait()
			local master_sha = git.get_head(ctx.source, "master")

			-- Verify they're different
			assert.are_not.equal(main_sha, master_sha)

			local specs = {
				[ctx.source] = {
					url = ctx.source,
					branch = "main"  -- Spec says use main branch
				},
			}

			-- act
			wrench.ensure_installed(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			local installed_sha = git.get_head(ctx.install_dir .. "/source")
			assert.are.equal(main_sha, installed_sha, "Should checkout to main branch, not master")
			assert.are_not.equal(master_sha, installed_sha, "Should NOT be on master branch")

			ctx.cleanup()
		end)
	end)

	describe("commands", function()
		it("registers user commands when wrench is required", function()
			-- act
			require("wrench")

			-- assert
			local commands = vim.api.nvim_get_commands({})
			assert.is_not_nil(commands.WrenchSync, "WrenchSync command should be registered")
			assert.is_not_nil(commands.WrenchRestore, "WrenchRestore command should be registered")
			assert.is_not_nil(commands.WrenchUpdate, "WrenchUpdate command should be registered")
		end)
	end)
end)
