# Wrench

> ⚠️ **Disclaimer**: This project was built as a learning exercise for Lua and Neovim plugin development. There's no good reason to use this over established plugin managers like [lazy.nvim](https://github.com/folke/lazy.nvim). Use at your own risk!

A minimal Neovim plugin manager.

## Install

Add to your `init.lua`:

```lua
local wrenchpath = vim.fn.stdpath("data") .. "/wrench"
if not vim.loop.fs_stat(wrenchpath) then
    vim.fn.system({
        "git",
        "clone",
        "https://github.com/TheOneWithTheWrench/wrench.nvim.git",
        wrenchpath,
    })
end
vim.opt.rtp:prepend(wrenchpath)

require("wrench").setup("plugins")

vim.cmd.colorscheme("tokyonight")
```

Then create plugin files in `~/.config/nvim/lua/plugins/`:

```lua
-- lua/plugins/colorscheme.lua
return {
    { url = "https://github.com/folke/tokyonight.nvim", branch = "main" },
}
```

```lua
-- lua/plugins/editor/which-key.lua
return {
    {
        url = "https://github.com/folke/which-key.nvim",
        branch = "main",
        config = function()
            require("which-key").setup()
        end,
    },
}
```

Nested directories are supported. Each file can return a single plugin or a list of plugins.

## Plugin spec

```lua
{
    url = "https://github.com/owner/repo",  -- required
    branch = "main",                         -- optional
    tag = "v1.0.0",                          -- optional
    commit = "abc123...",                    -- optional, pins to exact commit
    config = function() ... end,             -- optional, runs after load
    dependencies = { ... },                  -- optional, URL-only refs (see below)
    ft = { "lua", "python" },                -- optional, lazy load on filetype
    event = "BufReadPost",                   -- optional, lazy load on event
    keys = { ... },                          -- optional, lazy load on keypress (see below)
    cmd = { "Mason", "MasonInstall" },       -- optional, lazy load on command
}
```

## Dependencies

Dependencies are **URL-only** references — they ensure a plugin is installed before yours:

```lua
{
    url = "https://github.com/nvim-neotest/neotest",
    branch = "master",
    dependencies = {
        { url = "https://github.com/nvim-lua/plenary.nvim" },
        { url = "https://github.com/nvim-neotest/nvim-nio" },
    },
    config = function()
        require("neotest").setup()
    end,
}
```

If a dependency needs configuration (branch, tag, config function), create a dedicated spec file for it. This ensures each plugin has a single source of truth.

## Commands

| Command | Description |
|---------|-------------|
| `:WrenchUpdate` | Fetch latest, review changes, update |
| `:WrenchSync` | Sync plugins to config |
| `:WrenchRestore` | Restore plugins to lockfile |
| `:WrenchGetRegistered` | Show registered plugins |

## Lazy loading

Plugins with `ft`, `event`, `keys`, or `cmd` specified will only load when triggered:

```lua
-- Load on filetype
{
    url = "https://github.com/rust-lang/rust.vim",
    ft = { "rust" },
}

-- Load on event (any Neovim autocmd event)
{
    url = "https://github.com/folke/noice.nvim",
    event = "BufReadPost",
}

-- Load on keypress
{
    url = "https://github.com/nvim-telescope/telescope.nvim",
    keys = {
        { lhs = "<leader>ff", rhs = function() require("telescope.builtin").find_files() end, desc = "Find files" },
        { lhs = "<leader>fg", rhs = function() require("telescope.builtin").live_grep() end, mode = { "n", "v" } },
    },
}

-- Load on command
{
    url = "https://github.com/williamboman/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    config = function()
        require("mason").setup()
    end,
}
```

### Key spec

Each key in the `keys` table supports:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `lhs` | `string` | Yes | The key sequence to bind |
| `rhs` | `function` | Yes | The action to execute |
| `mode` | `string[]` | No | Mode(s) for the keymap (defaults to `{"n"}`) |
| `...` | `any` | No | Any other valid `vim.keymap.set` option (`desc`, `silent`, etc.) |

## Plugins with build steps

Some plugins require a build step (e.g., compiling a native library). Wrench leaves this to the user.
One naive approach could be via an idempotency check as shown below.
In the future, Wrench might tackle this complexity. But until I have thought of a good solution, it's up to you.

```lua
{
	url = "https://github.com/nvim-telescope/telescope-fzf-native.nvim",
	branch = "main",
	config = function()
		local install_path = require("wrench.utils").get_plugin_path(
			vim.fn.stdpath("data") .. "/wrench/plugins",
			"https://github.com/nvim-telescope/telescope-fzf-native.nvim"
		)
		local lib = install_path .. "/build/libfzf.so"

        if vim.uv.fs_stat(lib) == nil then
            vim.fn.system({ "make", "-C", install_path })
        end
    end,
}
```

## License

MIT
