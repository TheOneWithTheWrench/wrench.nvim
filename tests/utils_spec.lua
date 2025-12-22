local utils = require("wrench.utils")

describe("utils", function()
	describe("get_name", function()
		it("extracts plugin name from URL", function()
			local name = utils.get_name("https://github.com/user/plugin")
			assert.are.equal("plugin", name)
		end)

		it("removes .git suffix", function()
			local name = utils.get_name("https://github.com/user/plugin.git")
			assert.are.equal("plugin", name)
		end)
	end)

	describe("parse_semver", function()
		it("parses v1.2.3 format", function()
			local version = utils.parse_semver("v1.2.3")
			assert.is_not_nil(version)
			assert.are.equal(1, version.major)
			assert.are.equal(2, version.minor)
			assert.are.equal(3, version.patch)
		end)

		it("parses 1.2.3 format without v prefix", function()
			local version = utils.parse_semver("1.2.3")
			assert.is_not_nil(version)
			assert.are.equal(1, version.major)
			assert.are.equal(2, version.minor)
			assert.are.equal(3, version.patch)
		end)

		it("returns nil for pre-release versions", function()
			local version = utils.parse_semver("v1.0.0-beta.1")
			assert.is_nil(version)
		end)

		it("returns nil for invalid format", function()
			local version = utils.parse_semver("invalid")
			assert.is_nil(version)
		end)

		it("returns nil for partial versions", function()
			local version = utils.parse_semver("v1.2")
			assert.is_nil(version)
		end)
	end)

	describe("get_latest_semver_tag", function()
		it("returns latest semver tag from list", function()
			local tags = { "v1.0.0", "v1.2.0", "v1.1.0", "v2.0.0" }
			local latest = utils.get_latest_semver_tag(tags)
			assert.are.equal("v2.0.0", latest)
		end)

		it("skips non-semver tags", function()
			local tags = { "v1.0.0", "random-tag", "v2.0.0", "another" }
			local latest = utils.get_latest_semver_tag(tags)
			assert.are.equal("v2.0.0", latest)
		end)

		it("skips pre-release tags", function()
			local tags = { "v1.0.0", "v2.0.0-beta.1", "v1.5.0" }
			local latest = utils.get_latest_semver_tag(tags)
			assert.are.equal("v1.5.0", latest)
		end)

		it("returns nil when no valid semver tags", function()
			local tags = { "random", "another", "not-semver" }
			local latest = utils.get_latest_semver_tag(tags)
			assert.is_nil(latest)
		end)

		it("returns nil for empty tag list", function()
			local tags = {}
			local latest = utils.get_latest_semver_tag(tags)
			assert.is_nil(latest)
		end)
	end)

	describe("resolve_target_ref", function()
		local git = require("wrench.git")

		-- Test helpers (borrowed from git_spec.lua)
		local new_test_dir = function()
			local dir = vim.fn.tempname()
			vim.fn.mkdir(dir, "p")
			return dir
		end
		local cleanup = function(dir) vim.fn.delete(dir, "rf") end
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

		it("resolves to latest semver tag when tags exist", function()
			-- arrange
			local dir = new_test_dir()
			local source = dir .. "/source"
			local clone = dir .. "/clone"

			init_repo(source,
				with_commit("initial"),
				with_tag("v1.0.0"),
				with_commit("second"),
				with_tag("v2.0.0")
			)

			git.clone(source, clone)
			local v2_sha = git.get_head(source)

			-- act
			local sha, err = utils.resolve_target_ref(clone)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(sha)
			assert.are.equal(v2_sha, sha)

			cleanup(dir)
		end)

		it("resolves to remote head when no semver tags", function()
			-- arrange
			local dir = new_test_dir()
			local source = dir .. "/source"
			local clone = dir .. "/clone"

			init_repo(source,
				with_commit("initial"),
				with_tag("random-tag")
			)

			git.clone(source, clone)
			local head_sha = git.get_head(source)

			-- act
			local sha, err = utils.resolve_target_ref(clone)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(sha)
			assert.are.equal(head_sha, sha)

			cleanup(dir)
		end)

		it("skips pre-release tags and uses stable version", function()
			-- arrange
			local dir = new_test_dir()
			local source = dir .. "/source"
			local clone = dir .. "/clone"

			init_repo(source,
				with_commit("initial"),
				with_tag("v1.0.0"),
				with_commit("second"),
				with_tag("v2.0.0-beta.1")
			)

			git.clone(source, clone)
			local v1_sha = git.get_head(source, "v1.0.0")

			-- act
			local sha, err = utils.resolve_target_ref(clone)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(sha)
			assert.are.equal(v1_sha, sha)

			cleanup(dir)
		end)

		it("returns error when path is not a git repository", function()
			-- arrange
			local dir = new_test_dir()
			local not_repo = dir .. "/notrepo"
			vim.fn.mkdir(not_repo, "p")

			-- act
			local sha, err = utils.resolve_target_ref(not_repo)

			-- assert
			assert.is_nil(sha)
			assert.is_not_nil(err)

			cleanup(dir)
		end)
	end)
end)
