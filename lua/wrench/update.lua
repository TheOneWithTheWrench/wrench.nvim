local M = {}
local git = require("wrench.git")
local utils = require("wrench.utils")
local log = require("wrench.log")

---@class UpdateInfo
---@field url string Plugin URL
---@field name string Plugin name
---@field old_commit string Current commit SHA
---@field new_commit string New commit SHA from remote
---@field log_lines string[] Commit messages between old and new
---@field old_tag? string Tag at old commit
---@field new_tag? string Tag at new commit
---@field is_major_bump boolean Whether this is a major version bump

---Parses semver major version from a tag.
---@param tag string? Tag like "v2.1.0"
---@return number? major The major version number
local function parse_major(tag)
    if not tag then
        return nil
    end
    local major = tag:match("v?(%d+)%.")
    return tonumber(major)
end

---Fetches and collects update info for a single plugin.
---@param url string Plugin URL
---@param branch string Branch name
---@param current_commit string Current commit from lockfile
---@return UpdateInfo? info Update info, or nil if no updates
function M.collect_one(url, branch, current_commit)
    local install_path = utils.get_install_path(url)

    if vim.fn.isdirectory(install_path) == 0 then
        return nil
    end

    local ok, err = git.fetch(install_path)
    if not ok then
        log.error("Failed to fetch " .. url .. ": " .. (err or ""))
        return nil
    end

    local new_commit = git.get_remote_head(install_path, branch)
    if not new_commit then
        return nil
    end

    if new_commit == current_commit then
        return nil
    end

    local log_lines = git.log_range(install_path, current_commit, new_commit) or {}

    if #log_lines == 0 then
        return nil
    end
    local old_tag = git.describe_tag(install_path, current_commit)
    local new_tag = git.describe_tag(install_path, new_commit)

    local old_major = parse_major(old_tag)
    local new_major = parse_major(new_tag)
    local is_major_bump = old_major and new_major and new_major > old_major

    return {
        url = url,
        name = utils.get_name(url),
        old_commit = current_commit,
        new_commit = new_commit,
        log_lines = log_lines,
        old_tag = old_tag,
        new_tag = new_tag,
        is_major_bump = is_major_bump or false,
    }
end

---Collects updates for all registered plugins.
---@param spec_map PluginMap Map of URL to spec
---@param lock_data LockData Current lockfile data
---@return UpdateInfo[] updates List of available updates
function M.collect_all(spec_map, lock_data)
    local updates = {}

    for url, spec in pairs(spec_map) do
        -- Skip pinned commits or tags
        if spec.commit or spec.tag then
            goto continue
        end

        local current_commit = lock_data[url]
        if not current_commit then
            goto continue
        end

        -- Use spec branch, or detect from repo
        local branch = spec.branch
        if not branch then
            local install_path = utils.get_install_path(url)
            branch = git.get_branch(install_path)
            if not branch then
                goto continue
            end
        end

        log.info("Checking " .. utils.get_name(url) .. "...")
        local info = M.collect_one(url, branch, current_commit)
        if info then
            table.insert(updates, info)
        end

        ::continue::
    end

    return updates
end

---Formats update info for display.
---@param info UpdateInfo
---@return string formatted
function M.format_update(info)
    local lines = {}

    local header = info.name .. " (" .. #info.log_lines .. " commits)"
    if info.is_major_bump then
        header = header .. " ⚠️  MAJOR " .. (info.old_tag or "?") .. " → " .. (info.new_tag or "?")
    elseif info.new_tag and info.old_tag and info.new_tag ~= info.old_tag then
        header = header .. " " .. info.old_tag .. " → " .. info.new_tag
    end
    table.insert(lines, header)
    table.insert(lines, string.rep("-", #header))

    for _, log_line in ipairs(info.log_lines) do
        table.insert(lines, "  " .. log_line)
    end

    return table.concat(lines, "\n")
end

---Prompts user to review updates one by one.
---@param updates UpdateInfo[] List of updates
---@return UpdateInfo[] approved List of approved updates
function M.review(updates)
    local approved = {}

    for i, info in ipairs(updates) do
        local formatted = M.format_update(info)
        print("\n" .. formatted .. "\n")

        local prompt = string.format("[%d/%d] Update %s? (y)es / (n)o / (q)uit: ", i, #updates, info.name)
        local choice = vim.fn.input(prompt):lower()
        vim.api.nvim_out_write("\n")

        if choice == "y" or choice == "yes" then
            table.insert(approved, info)
        elseif choice == "q" or choice == "quit" then
            break
        end
    end

    return approved
end

return M
