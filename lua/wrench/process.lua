local M = {}
local log = require("wrench.log")
local git = require("wrench.git")
local utils = require("wrench.utils")

--- Tracks which plugins have been installed (deduplication within a session).
---@type table<string, boolean>
local installed = {}

--- Tracks which plugins have had loading set up (deduplication within a session).
---@type table<string, boolean>
local loading_setup = {}

--- Tracks which plugins have actually been loaded at runtime.
---@type table<string, boolean>
local loaded = {}

--- Tracks which plugins have been synced (deduplication within a session).
---@type table<string, boolean>
local synced = {}

---Checks if a plugin install is valid (has more than just .git).
---@param path string The plugin install path.
---@return boolean is_valid True if install is valid.
local function is_valid_install(path)
    if vim.fn.isdirectory(path) == 0 then
        return false
    end
    local entries = vim.fn.readdir(path)
    for _, entry in ipairs(entries) do
        if entry ~= ".git" then
            return true
        end
    end
    return false
end

---Ensures a plugin and its dependencies are installed.
---@param url string The plugin URL to install.
---@param spec_map PluginMap The map of all specs.
---@param lock_data LockData The lockfile data to update.
---@return boolean lock_changed True if lockfile was updated.
function M.ensure_installed(url, spec_map, lock_data)
    if installed[url] then
        return false
    end
    installed[url] = true

    local spec = spec_map[url]
    if not spec then
        log.error("No spec found for " .. url)
        return false
    end

    local lock_changed = false

    if spec.dependencies then
        for _, dep in ipairs(spec.dependencies) do
            local dep_url = dep.url
            if M.ensure_installed(dep_url, spec_map, lock_data) then
                lock_changed = true
            end
        end
    end

    local install_path = utils.get_install_path(url)

    if not is_valid_install(install_path) then
        if vim.fn.isdirectory(install_path) == 1 then
            log.warn("Removing corrupted install: " .. utils.get_name(url))
            vim.fn.delete(install_path, "rf")
        end
        log.info("Installing " .. utils.get_name(url) .. "...")
        local opts = {
            branch = spec.branch,
            tag = spec.tag,
            commit = spec.commit,
        }
        local ok, err = git.clone(url, install_path, opts)
        if not ok then
            log.error("Failed to clone " .. url .. ": " .. (err or "unknown error"))
            return lock_changed
        end

        log.info("Installed " .. url)
    end

    if not lock_data[url] then
        local commit = git.get_head(install_path)
        if commit then
            lock_data[url] = commit
            lock_changed = true
        end
    end

    return lock_changed
end

---Loads a plugin immediately (adds to rtp, runs config).
---Used internally when dependencies need to be loaded.
---@param url string The plugin URL.
---@param spec_map PluginMap The map of all specs.
local function load_plugin_now(url, spec_map)
    if loaded[url] then
        return
    end
    loaded[url] = true

    local spec = spec_map[url]
    if not spec then
        return
    end

    if spec.dependencies then
        for _, dep in ipairs(spec.dependencies) do
            local dep_url = dep.url
            load_plugin_now(dep_url, spec_map)
        end
    end

    local install_path = utils.get_install_path(url)
    vim.opt.rtp:prepend(install_path)

    local plugin_dir = install_path .. "/plugin"
    if vim.fn.isdirectory(plugin_dir) == 1 then
        for _, file in ipairs(vim.fn.readdir(plugin_dir)) do
            if file:match("%.vim$") then
                vim.cmd("source " .. plugin_dir .. "/" .. file)
            elseif file:match("%.lua$") then
                dofile(plugin_dir .. "/" .. file)
            end
        end
    end

    if spec.config and type(spec.config) == "function" then
        spec.config()
    end
end

---Sets up loading behavior for a plugin.
---@param url string The plugin URL.
---@param spec_map PluginMap The map of all specs.
function M.setup_loading(url, spec_map)
    if loading_setup[url] then
        return
    end
    loading_setup[url] = true

    local spec = spec_map[url]
    if not spec then
        return
    end

    if spec.dependencies then
        for _, dep in ipairs(spec.dependencies) do
            local dep_url = dep.url
            M.setup_loading(dep_url, spec_map)
        end
    end

    local is_lazy = spec.ft or spec.event or spec.keys

    if not is_lazy then
        load_plugin_now(url, spec_map)
        return
    end

    local group_name = "WrenchLoad_" .. url:gsub("[^%w]", "_")
    local group = vim.api.nvim_create_augroup(group_name, { clear = true })

    local function trigger_load()
        if loaded[url] then
            return
        end
        vim.api.nvim_del_augroup_by_id(group)
        load_plugin_now(url, spec_map)
    end

    if spec.ft then
        vim.api.nvim_create_autocmd("FileType", {
            pattern = spec.ft,
            group = group,
            callback = trigger_load,
        })
    end

    if spec.event then
        vim.api.nvim_create_autocmd(spec.event, {
            pattern = "*",
            group = group,
            callback = trigger_load,
        })
    end

    if spec.keys then
        for _, key in ipairs(spec.keys) do
            local lhs = key.lhs
            local rhs = key.rhs
            local modes = key.mode or { "n" }

            local opts = {}
            for k, v in pairs(key) do
                if k ~= "lhs" and k ~= "rhs" and k ~= "mode" then
                    opts[k] = v
                end
            end

            for _, mode in ipairs(modes) do
                vim.keymap.set(mode, lhs, function()
                    vim.keymap.del(mode, lhs)
                    load_plugin_now(url, spec_map)
                    vim.keymap.set(mode, lhs, rhs, opts)
                    local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
                    vim.api.nvim_feedkeys(keys, "m", false)
                end, opts)
            end
        end
    end
end

---Syncs a single plugin to the specified commit/tag/branch.
---@param url string The plugin URL.
---@param spec PluginSpec The plugin spec.
---@param lock_data LockData The lockfile data to update.
---@return boolean lock_changed True if lockfile was updated.
function M.sync(url, spec, lock_data)
    if synced[url] then
        return false
    end
    synced[url] = true

    local lock_changed = false
    local install_path = utils.get_install_path(url)

    if vim.fn.isdirectory(install_path) == 0 then
        return lock_changed
    end

    local ok, err
    local new_commit

    if spec.commit then
        local current_commit = git.get_head(install_path)
        if current_commit and current_commit ~= spec.commit then
            ok, err = git.checkout(install_path, spec.commit)
            if ok then
                new_commit = spec.commit
                log.info("Synced " .. url .. " to " .. spec.commit:sub(1, 7))
            end
        else
            new_commit = spec.commit
        end
    elseif spec.tag then
        ok, err = git.checkout(install_path, spec.tag)
        if ok then
            new_commit = git.get_head(install_path)
            log.info("Synced " .. url .. " to tag " .. spec.tag)
        end
    elseif spec.branch then
        ok, err = git.checkout(install_path, spec.branch)
        if ok then
            ok, err = git.pull(install_path)
            if ok then
                new_commit = git.get_head(install_path)
                log.info("Synced " .. url .. " to latest on " .. spec.branch)
            end
        end
    end

    if not ok and err then
        log.error("Failed to sync " .. url .. ": " .. err)
    end

    if new_commit then
        lock_data[url] = new_commit
        lock_changed = true
    end

    return lock_changed
end

---Restores a plugin to the commit specified in lockfile.
---@param url string The plugin URL.
---@param commit string The commit SHA to restore to.
---@return boolean success True if restore succeeded.
function M.restore(url, commit)
    local install_path = utils.get_install_path(url)

    if vim.fn.isdirectory(install_path) == 0 then
        log.warn("Cannot restore " .. url .. ": not installed")
        return false
    end

    local current_commit = git.get_head(install_path)
    if current_commit == commit then
        return true
    end

    local ok, err = git.checkout(install_path, commit)
    if ok then
        log.info("Restored " .. url .. " to " .. commit:sub(1, 7))
        return true
    else
        log.error("Failed to restore " .. url .. ": " .. (err or "unknown error"))
        return false
    end
end

---Removes a plugin directory.
---@param name string The plugin name (directory name).
---@return boolean success True if removal succeeded.
function M.remove(name)
    local install_path = utils.INSTALL_PATH .. "/" .. name

    if vim.fn.isdirectory(install_path) == 0 then
        return true
    end

    local ok = vim.fn.delete(install_path, "rf")
    if ok == 0 then
        log.info("Removed " .. name)
        return true
    else
        log.error("Failed to remove " .. name)
        return false
    end
end

return M
