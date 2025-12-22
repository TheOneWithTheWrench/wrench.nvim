local lockfile = require("wrench.lockfile")

describe("lockfile", function()
	-- Test helpers
	local new_test_dir = function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		return dir
	end
	local cleanup = function(dir) vim.fn.delete(dir, "rf") end
	local write_file = function(path, lines) vim.fn.writefile(lines, path) end
	local read_file = function(path) return vim.fn.readfile(path) end

	describe("read", function()
		it("returns empty table when file does not exist", function()
			-- arrange
			local dir = new_test_dir()
			local path = dir .. "/nonexistent.json"

			-- act
			local data, err = lockfile.read(path)

			-- assert
			assert.are.same({}, data)
			assert.is_nil(err)

			cleanup(dir)
		end)

		it("parses valid JSON lockfile", function()
			-- arrange
			local dir = new_test_dir()
			local path = dir .. "/lock.json"
			write_file(path, {
				"{",
				'  "https://github.com/owner/repo": "abc123"',
				"}",
			})

			-- act
			local data, err = lockfile.read(path)

			-- assert
			assert.is_nil(err)
			assert.are.equal("abc123", data["https://github.com/owner/repo"])

			cleanup(dir)
		end)

		it("returns error for invalid JSON", function()
			-- arrange
			local dir = new_test_dir()
			local path = dir .. "/invalid.json"
			write_file(path, { "not valid json" })

			-- act
			local data, err = lockfile.read(path)

			-- assert
			assert.are.same({}, data)
			assert.is_not_nil(err)
			assert.is_truthy(err:match("Failed to parse"))

			cleanup(dir)
		end)
	end)

	describe("write", function()
		it("writes empty lockfile", function()
			-- arrange
			local dir = new_test_dir()
			local path = dir .. "/lock.json"

			-- act
			local success, err = lockfile.write(path, {})

			-- assert
			assert.is_true(success)
			assert.is_nil(err)
			local content = table.concat(read_file(path), "\n")
			assert.are.equal("{\n}", content)

			cleanup(dir)
		end)

		it("writes lockfile with sorted keys", function()
			-- arrange
			local dir = new_test_dir()
			local path = dir .. "/lock.json"
			local data = {
				["https://github.com/z/repo"] = "zzz",
				["https://github.com/a/repo"] = "aaa",
			}

			-- act
			local success, err = lockfile.write(path, data)

			-- assert
			assert.is_true(success)
			assert.is_nil(err)
			local lines = read_file(path)
			assert.are.equal("{", lines[1])
			assert.is_truthy(lines[2]:match("a/repo"))
			assert.is_truthy(lines[3]:match("z/repo"))
			assert.are.equal("}", lines[4])

			cleanup(dir)
		end)

		it("round-trips data through write and read", function()
			-- arrange
			local dir = new_test_dir()
			local path = dir .. "/lock.json"
			local original = {
				["https://github.com/owner/plugin1"] = "abc123",
				["https://github.com/owner/plugin2"] = "def456",
			}

			-- act
			lockfile.write(path, original)
			local restored, err = lockfile.read(path)

			-- assert
			assert.is_nil(err)
			assert.are.equal("abc123", restored["https://github.com/owner/plugin1"])
			assert.are.equal("def456", restored["https://github.com/owner/plugin2"])

			cleanup(dir)
		end)
	end)
end)
