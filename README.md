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

### Alternative: inline specs

You can also define plugins directly with `add()`:

```lua
require("wrench").add({
    { url = "https://github.com/folke/tokyonight.nvim", branch = "main" },
})
```

## Plugin spec

```lua
{
    url = "https://github.com/owner/repo",  -- required
    branch = "main",                         -- optional
    tag = "v1.0.0",                          -- optional
    commit = "abc123...",                    -- optional, pins to exact commit
    config = function() ... end,             -- optional, runs after load
    dependencies = { ... },                  -- optional, other plugin specs
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:WrenchUpdate` | Fetch latest, review changes, update |
| `:WrenchSync` | Sync plugins to config |
| `:WrenchRestore` | Restore plugins to lockfile |
| `:WrenchGetRegistered` | Show registered plugins |

## Plugins with build steps

Some plugins require a build step (e.g., compiling a native library). Wrench leaves this to the user.
One naive approach could be via an idempotency check as shown below.
In the future, Wrench might tackle this complexity. But until I have thought of a good solution, it's up to you.

```lua
{
    url = "https://github.com/nvim-telescope/telescope-fzf-native.nvim",
    branch = "main",
    config = function()
        local install_path = vim.fn.stdpath("data") .. "/wrench/plugins/telescope-fzf-native.nvim"
        local lib = install_path .. "/build/libfzf.so"

        if vim.uv.fs_stat(lib) == nil then
            vim.fn.system({ "make", "-C", install_path })
        end
    end,
}
```

## License

MIT
