local git = require("wrench.git")

describe("git", function()
	-- Test helpers
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

	describe("clone", function()
		it("clones a repository", function()
			-- arrange
			local dir = new_test_dir()
			local source = dir .. "/source"
			local dest = dir .. "/dest"
			init_repo(source, with_commit("initial"))

			-- act
			local success, err = git.clone(source, dest)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)
			assert.are.equal(1, vim.fn.isdirectory(dest .. "/.git"))

			cleanup(dir)
		end)

		it("returns error when source does not exist", function()
			-- arrange
			local dir = new_test_dir()
			local source = dir .. "/nonexistent"
			local dest = dir .. "/dest"

			-- act
			local success, err = git.clone(source, dest)

			-- assert
			assert.is_false(success)
			assert.is_not_nil(err)
			assert.is_truthy(err:match("clone"))

			cleanup(dir)
		end)
	end)

	describe("get_head", function()
		it("returns the current HEAD commit", function()
			-- arrange
			local dir = new_test_dir()
			local repo = dir .. "/repo"
			init_repo(repo, with_commit("initial"))

			-- act
			local sha, err = git.get_head(repo)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(sha)
			assert.are.equal(40, #sha)
			assert.is_truthy(sha:match("^%x+$")) -- hex characters only

			cleanup(dir)
		end)

		it("returns error when path is not a git repository", function()
			-- arrange
			local dir = new_test_dir()
			local not_repo = dir .. "/notrepo"
			vim.fn.mkdir(not_repo, "p")

			-- act
			local sha, err = git.get_head(not_repo)

			-- assert
			assert.is_nil(sha)
			assert.is_not_nil(err)
			assert.is_truthy(err:match("HEAD") or err:match("Not a git"))

			cleanup(dir)
		end)

		it("returns commit SHA for relative revisions", function()
			-- arrange
			local dir = new_test_dir()
			local repo = dir .. "/repo"
			init_repo(repo, with_commit("initial"))
			local first_sha = git.get_head(repo)
			-- Create second commit
			vim.system({ "git", "commit", "--allow-empty", "-m", "second" }, { cwd = repo }):wait()
			local second_sha = git.get_head(repo)

			-- act
			local head_0 = git.get_head(repo, "HEAD~0")
			local head_1 = git.get_head(repo, "HEAD~1")

			-- assert
			assert.are.equal(second_sha, head_0)
			assert.are.equal(first_sha, head_1)

			cleanup(dir)
		end)
	end)

	describe("checkout", function()
		it("checks out a specific commit", function()
			-- arrange
			local dir = new_test_dir()
			local repo = dir .. "/repo"
			init_repo(repo, with_commit("initial"))
			local first_sha = git.get_head(repo)
			-- Create a second commit
			vim.system({ "git", "commit", "--allow-empty", "-m", "second" }, { cwd = repo }):wait()
			local second_sha = git.get_head(repo)

			-- act
			local success, err = git.checkout(repo, first_sha)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)
			local current_sha = git.get_head(repo)
			assert.are.equal(first_sha, current_sha)
			assert.are_not.equal(second_sha, current_sha)

			cleanup(dir)
		end)

		it("returns error when ref does not exist", function()
			-- arrange
			local dir = new_test_dir()
			local repo = dir .. "/repo"
			init_repo(repo, with_commit("initial"))
			local invalid_sha = "0000000000000000000000000000000000000000"

			-- act
			local success, err = git.checkout(repo, invalid_sha)

			-- assert
			assert.is_false(success)
			assert.is_not_nil(err)
			assert.is_truthy(err:match("checkout"))

			cleanup(dir)
		end)
	end)

	describe("fetch", function()
		it("fetches from remote", function()
			-- arrange
			local dir = new_test_dir()
			local source = dir .. "/source"
			local clone = dir .. "/clone"
			init_repo(source, with_commit("initial"))

			-- Clone the repo
			git.clone(source, clone)

			-- Create a new commit in source
			vim.system({ "git", "commit", "--allow-empty", "-m", "new commit" }, { cwd = source }):wait()

			-- act
			local success, err = git.fetch(clone)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)

			cleanup(dir)
		end)

		it("returns error when path is not a git repository", function()
			-- arrange
			local dir = new_test_dir()
			local not_repo = dir .. "/notrepo"
			vim.fn.mkdir(not_repo, "p")

			-- act
			local success, err = git.fetch(not_repo)

			-- assert
			assert.is_false(success)
			assert.is_not_nil(err)
			assert.is_truthy(err:match("fetch") or err:match("Not a git"))

			cleanup(dir)
		end)
	end)

	describe("get_tags", function()
		it("returns tags when repo has tags", function()
			-- arrange
			local dir = new_test_dir()
			local repo = dir .. "/repo"
			init_repo(repo,
				with_commit("initial"),
				with_tag("v1.0.0"),
				with_commit("second"),
				with_tag("v1.1.0"),
				with_tag("v2.0.0")
			)

			-- act
			local tags, err = git.get_tags(repo)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(tags)
			assert.are.equal(3, #tags)
			assert.is_true(vim.tbl_contains(tags, "v1.0.0"))
			assert.is_true(vim.tbl_contains(tags, "v1.1.0"))
			assert.is_true(vim.tbl_contains(tags, "v2.0.0"))

			cleanup(dir)
		end)

		it("returns empty array when repo has no tags", function()
			-- arrange
			local dir = new_test_dir()
			local repo = dir .. "/repo"
			init_repo(repo, with_commit("initial"))

			-- act
			local tags, err = git.get_tags(repo)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(tags)
			assert.are.equal(0, #tags)

			cleanup(dir)
		end)

		it("returns error when path is not a git repository", function()
			-- arrange
			local dir = new_test_dir()
			local not_repo = dir .. "/notrepo"
			vim.fn.mkdir(not_repo, "p")

			-- act
			local tags, err = git.get_tags(not_repo)

			-- assert
			assert.is_nil(tags)
			assert.is_not_nil(err)
			assert.is_truthy(err:match("tag") or err:match("Not a git"))

			cleanup(dir)
		end)
	end)

	describe("get_remote_head", function()
		it("returns SHA for valid branch", function()
			-- arrange
			local dir = new_test_dir()
			local source = dir .. "/source"
			local clone = dir .. "/clone"
			init_repo(source, with_commit("initial"))
			local source_sha = git.get_head(source)

			-- Clone the repo
			git.clone(source, clone)

			-- act
			local sha, err = git.get_remote_head(clone, "master")

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(sha)
			assert.are.equal(40, #sha)
			assert.is_truthy(sha:match("^%x+$"))
			assert.are.equal(source_sha, sha)

			cleanup(dir)
		end)

		it("returns error for invalid branch", function()
			-- arrange
			local dir = new_test_dir()
			local source = dir .. "/source"
			local clone = dir .. "/clone"
			init_repo(source, with_commit("initial"))
			git.clone(source, clone)

			-- act
			local sha, err = git.get_remote_head(clone, "nonexistent")

			-- assert
			assert.is_nil(sha)
			assert.is_not_nil(err)
			assert.is_truthy(err:match("nonexistent") or err:match("unknown"))

			cleanup(dir)
		end)

		it("returns error when path is not a git repository", function()
			-- arrange
			local dir = new_test_dir()
			local not_repo = dir .. "/notrepo"
			vim.fn.mkdir(not_repo, "p")

			-- act
			local sha, err = git.get_remote_head(not_repo, "master")

			-- assert
			assert.is_nil(sha)
			assert.is_not_nil(err)
			assert.is_truthy(err:match("remote head") or err:match("not a git"))

			cleanup(dir)
		end)
	end)
end)
