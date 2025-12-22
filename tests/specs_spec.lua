local specs = require("wrench.specs")

describe("specs", function()
	-- Test helpers
	local new_test_context = function()
		local ctx = {}
		ctx.dir = vim.fn.tempname()
		ctx.lua_dir = ctx.dir .. "/lua"
		ctx.plugins_dir = ctx.lua_dir .. "/plugins"
		vim.fn.mkdir(ctx.plugins_dir, "p")

		-- Add to package.path so we can require modules
		ctx.old_path = package.path
		package.path = ctx.lua_dir .. "/?.lua;" .. package.path

		ctx.cleanup = function()
			package.path = ctx.old_path
			vim.fn.delete(ctx.dir, "rf")
		end

		return ctx
	end

	local write_spec_file = function(path, content)
		vim.fn.writefile(vim.split(content, "\n"), path)
	end

	describe("scan", function()
		it("scans single plugin spec file", function()
			-- arrange
			local ctx = new_test_context()
			local spec_file = ctx.plugins_dir .. "/example.lua"
			local spec_content = [[
return {
	url = "https://github.com/user/example.nvim"
}
]]
			write_spec_file(spec_file, spec_content)

			-- act
			local result, err = specs.scan("plugins", ctx.lua_dir)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(result)
			assert.are.equal("https://github.com/user/example.nvim", result["https://github.com/user/example.nvim"].url)

			ctx.cleanup()
		end)

		it("scans list of specs in one file", function()
			-- arrange
			local ctx = new_test_context()
			local spec_file = ctx.plugins_dir .. "/list.lua"
			local spec_content = [[
return {
	{ url = "https://github.com/user/plugin1" },
	{ url = "https://github.com/user/plugin2" },
}
]]
			write_spec_file(spec_file, spec_content)

			-- act
			local result, err = specs.scan("plugins", ctx.lua_dir)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(result["https://github.com/user/plugin1"])
			assert.is_not_nil(result["https://github.com/user/plugin2"])

			ctx.cleanup()
		end)

		it("scans multiple files and merges", function()
			-- arrange
			local ctx = new_test_context()
			local file1 = ctx.plugins_dir .. "/plugin1.lua"
			local file2 = ctx.plugins_dir .. "/plugin2.lua"
			write_spec_file(file1, 'return { url = "https://github.com/user/plugin1" }')
			write_spec_file(file2, 'return { url = "https://github.com/user/plugin2" }')

			-- act
			local result, err = specs.scan("plugins", ctx.lua_dir)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(result["https://github.com/user/plugin1"])
			assert.is_not_nil(result["https://github.com/user/plugin2"])

			ctx.cleanup()
		end)

		it("returns empty table when directory does not exist", function()
			-- arrange
			local ctx = new_test_context()

			-- act
			local result, err = specs.scan("nonexistent", ctx.lua_dir)

			-- assert
			assert.is_nil(err)
			assert.are.same({}, result)

			ctx.cleanup()
		end)

		it("collects dependencies as bare specs", function()
			-- arrange
			local ctx = new_test_context()
			local spec_file = ctx.plugins_dir .. "/plugin.lua"
			local spec_content = [[
return {
	url = "https://github.com/user/plugin",
	dependencies = {
		{ url = "https://github.com/user/dep1" },
		{ url = "https://github.com/user/dep2" },
	}
}
]]
			write_spec_file(spec_file, spec_content)

			-- act
			local result, err = specs.scan("plugins", ctx.lua_dir)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(result["https://github.com/user/plugin"])
			assert.is_not_nil(result["https://github.com/user/dep1"])
			assert.is_not_nil(result["https://github.com/user/dep2"])

			ctx.cleanup()
		end)

		it("dependency with own config file keeps full spec", function()
			-- arrange
			local ctx = new_test_context()

			-- Plugin A depends on Plugin B (bare dependency)
			local plugin_a = ctx.plugins_dir .. "/plugin_a.lua"
			local spec_a = [[
return {
	url = "https://github.com/user/plugin_a",
	dependencies = {
		{ url = "https://github.com/user/plugin_b" }
	},
	config = function() print("A config") end
}
]]
			write_spec_file(plugin_a, spec_a)

			-- Plugin B has its own file with config
			local plugin_b = ctx.plugins_dir .. "/plugin_b.lua"
			local spec_b = [[
return {
	url = "https://github.com/user/plugin_b",
	config = function() print("B config") end
}
]]
			write_spec_file(plugin_b, spec_b)

			-- act
			local result, err = specs.scan("plugins", ctx.lua_dir)

			-- assert
			assert.is_nil(err)
			assert.is_not_nil(result["https://github.com/user/plugin_a"])
			assert.is_not_nil(result["https://github.com/user/plugin_b"])

			-- Plugin B should have full spec (config function), not just bare url
			assert.is_not_nil(result["https://github.com/user/plugin_b"].config)
			assert.are.equal("function", type(result["https://github.com/user/plugin_b"].config))

			ctx.cleanup()
		end)
	end)
end)
