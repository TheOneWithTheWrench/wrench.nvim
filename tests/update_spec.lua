local update = require("wrench.update")
local git = require("wrench.git")
local lockfile = require("wrench.lockfile")

describe("update", function()
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

		for _, opt in ipairs({ ... }) do
			opt(path)
		end
	end

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

	describe("collect_updates", function()
		it("returns update when newer semver tag available", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source,
				with_commit("initial"),
				with_tag("v1.0.0"),
				with_commit("second"),
				with_tag("v1.1.0")
			)

			-- Clone and lock to v1.0.0
			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/source")
			local v1_0_sha = git.get_head(ctx.source, "v1.0.0")
			git.checkout(ctx.install_dir .. "/source", v1_0_sha)
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = v1_0_sha,
			})

			local specs = {
				[ctx.source] = { url = ctx.source }, -- No pin
			}

			-- act
			local updates, err = update.collect_updates(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(updates)
			assert.are.equal(1, vim.tbl_count(updates))

			local info = updates[ctx.source]
			assert.is_not_nil(info)
			assert.are.equal(ctx.source, info.url)
			assert.are.equal(v1_0_sha, info.old_sha)
			assert.are.equal("v1.0.0", info.old_tag)
			assert.are.equal("v1.1.0", info.new_tag)
			assert.is_false(info.is_major_bump)

			ctx.cleanup()
		end)

		it("detects major version bump", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source,
				with_commit("initial"),
				with_tag("v1.5.0"),
				with_commit("second"),
				with_tag("v2.0.0")
			)

			-- Clone and lock to v1.5.0
			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/source")
			local v1_sha = git.get_head(ctx.source, "v1.5.0")
			git.checkout(ctx.install_dir .. "/source", v1_sha)
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = v1_sha,
			})

			local specs = {
				[ctx.source] = { url = ctx.source }, -- No pin
			}

			-- act
			local updates, err = update.collect_updates(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_nil(err)
			local info = updates[ctx.source]
			assert.is_not_nil(info)
			assert.are.equal("v1.5.0", info.old_tag)
			assert.are.equal("v2.0.0", info.new_tag)
			assert.is_true(info.is_major_bump)

			ctx.cleanup()
		end)

		it("skips plugins with commit pin", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source,
				with_commit("initial"),
				with_tag("v1.0.0"),
				with_commit("second"),
				with_tag("v2.0.0")
			)

			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/source")
			local v1_sha = git.get_head(ctx.source, "v1.0.0")
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = v1_sha,
			})

			local specs = {
				[ctx.source] = { url = ctx.source, commit = v1_sha }, -- Pinned!
			}

			-- act
			local updates, err = update.collect_updates(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_nil(err)
			assert.are.equal(0, vim.tbl_count(updates))

			ctx.cleanup()
		end)

		it("returns empty when no updates available", function()
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source,
				with_commit("initial"),
				with_tag("v1.0.0")
			)

			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/source")
			local v1_sha = git.get_head(ctx.source, "v1.0.0")
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = v1_sha,
			})

			local specs = {
				[ctx.source] = { url = ctx.source },
			}

			-- act
			local updates, err = update.collect_updates(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_nil(err)
			assert.are.equal(0, vim.tbl_count(updates))

			ctx.cleanup()
		end)

		it("skips updates with 0 commits even if SHAs differ", function()
			-- This test catches the bug where old_sha != new_sha but git log shows 0 commits
			-- arrange
			local ctx = new_test_context()
			init_repo(ctx.source,
				with_commit("initial"),
				with_tag("v1.0.0")
			)

			vim.fn.mkdir(ctx.install_dir, "p")
			git.clone(ctx.source, ctx.install_dir .. "/source")

			local v1_sha = git.get_head(ctx.source, "v1.0.0")

			-- Lockfile has the v1.0.0 commit
			lockfile.write(ctx.lockfile_path, {
				[ctx.source] = v1_sha,
			})

			local specs = {
				[ctx.source] = { url = ctx.source }, -- No pin
			}

			-- act
			local updates, err = update.collect_updates(specs, ctx.lockfile_path, ctx.install_dir)

			-- assert
			assert.is_nil(err)
			assert.are.equal(0, vim.tbl_count(updates), "Should have no updates when at same commit (0 commits)")

			ctx.cleanup()
		end)
	end)

	describe("format_update", function()
		it("formats update with version info", function()
			local info = {
				url = "https://github.com/user/plugin",
				old_sha = "abc1234",
				new_sha = "def5678",
				old_tag = "v1.0.0",
				new_tag = "v1.1.0",
				commits = {
					"abc1234 Add feature X",
					"def5678 Fix bug Y",
				},
				is_major_bump = false,
			}

			local lines = update.format_update(info)

			assert.is_not_nil(lines)
			assert.is_true(#lines > 0)
			-- Should contain plugin name and version transition
			local header = lines[1]
			assert.is_truthy(header:match("plugin"))
			assert.is_truthy(header:match("v1.0.0"))
			assert.is_truthy(header:match("v1.1.0"))
		end)

		it("shows warning for major version bump", function()
			local info = {
				url = "https://github.com/user/plugin",
				old_sha = "abc1234",
				new_sha = "def5678",
				old_tag = "v1.5.0",
				new_tag = "v2.0.0",
				commits = {
					"abc1234 Breaking change",
				},
				is_major_bump = true,
			}

			local lines = update.format_update(info)

			assert.is_not_nil(lines)
			local header = lines[1]
			-- Should contain BREAKING or similar warning
			assert.is_truthy(header:match("BREAKING") or header:match("WARNING") or header:match("MAJOR"))
		end)
	end)
end)
