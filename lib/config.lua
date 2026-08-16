-- StarhubRejoiner: Config management
-- Load/save/validate JSON config with smart defaults and merging

local json = require("json")

local config = {}

-- ============================================================
-- DEFAULT CONFIG
-- ============================================================

config.DEFAULT = {
    -- General
    language = "id",
    version = "1.0.0",

    -- Package management
    packages = {
        mode = "auto",              -- "auto" (scan device) or "manual"
        manual_list = {},           -- manual package list when mode="manual"
        selected = {},              -- packages to actively monitor (empty = all)
        prefix = "com.roblox",      -- package prefix for scanning
    },

    -- Server / rejoin target
    server = {
        mode = "all",               -- "all" (same for all packages) or "per_package"
        type = "ps_link",           -- "ps_link", "place_id", or "job_id"
        ps_link = "",               -- PS link URL
        place_id = "",              -- Place ID
        job_id = "",                -- Job/Game Instance ID
        per_package = {},           -- per-package server config: { ["pkg"] = { type, value } }
    },

    -- Monitor settings
    monitor = {
        check_interval = 10,        -- seconds between status checks
        startup_grace_seconds = 45, -- grace period after launch
        clear_cache_on_rejoin = true,
        max_rejoin_attempts = 5,    -- max consecutive rejoin attempts
        rejoin_cooldown = 30,       -- seconds between rejoin attempts
        auto_launch_on_start = true,-- launch non-running packages when monitor starts
        launch_stagger_seconds = 8, -- delay between launching multiple packages
    },

    -- Cookie settings
    cookie = {
        cookies = {},               -- { ["package_name"] = "cookie_value" }
        masked_display = true,      -- mask cookies in status display
    },

    -- Notifications
    notifications = {
        discord_webhook = "",
        notify_on_rejoin = true,
        notify_on_error = true,
    },

    -- API (future)
    api = {
        enabled = false,
        port = 8080,
    },

    -- Display
    display = {
        ui_mode = "live",           -- "live" (detailed) or "compact"
        show_system_info = true,
        mask_usernames = false,
    },
}

-- Path to config file (stored outside repo directory for safety)
config.CONFIG_PATH = "../config.json"

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

--- Deep copy a table
---@param t table
---@return table
local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deep_copy(v)
    end
    return copy
end

--- Deep merge: fills missing keys in `target` from `defaults`
--- Does NOT overwrite existing values
---@param target table
---@param defaults table
---@return table target (modified in place)
local function deep_merge(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = deep_copy(v)
        elseif type(v) == "table" and type(target[k]) == "table" then
            -- Only merge if both are non-array tables
            local is_array = #v > 0 or #target[k] > 0
            if not is_array then
                deep_merge(target[k], v)
            end
        end
    end
    return target
end

-- ============================================================
-- LOAD / SAVE
-- ============================================================

--- Load config from file, merging with defaults
---@param path string|nil Custom config path
---@return table config_data
---@return boolean is_new (true if config was created fresh)
function config.load(path)
    path = path or config.CONFIG_PATH
    local data, err = json.read_file(path)
    if data then
        -- Merge with defaults (fill missing keys)
        deep_merge(data, config.DEFAULT)
        return data, false
    end
    -- Config doesn't exist or is invalid — use defaults
    local fresh = deep_copy(config.DEFAULT)
    return fresh, true
end

--- Save config to file
---@param data table Config data
---@param path string|nil Custom config path
---@return boolean success
---@return string|nil error
function config.save(data, path)
    path = path or config.CONFIG_PATH
    return json.write_file(path, data, true)
end

-- ============================================================
-- GETTERS (safe nested access)
-- ============================================================

--- Get a nested config value safely
---@param data table Config data
---@param key_path string Dot-separated path (e.g. "server.ps_link")
---@param default any Default if not found
---@return any
function config.get(data, key_path, default)
    local current = data
    for key in key_path:gmatch("[^%.]+") do
        if type(current) ~= "table" then
            return default
        end
        current = current[key]
    end
    if current == nil then
        return default
    end
    return current
end

--- Set a nested config value safely
---@param data table Config data
---@param key_path string Dot-separated path
---@param value any Value to set
function config.set(data, key_path, value)
    local keys = {}
    for key in key_path:gmatch("[^%.]+") do
        keys[#keys + 1] = key
    end
    local current = data
    for i = 1, #keys - 1 do
        local k = keys[i]
        if type(current[k]) ~= "table" then
            current[k] = {}
        end
        current = current[k]
    end
    current[keys[#keys]] = value
end

-- ============================================================
-- SERVER HELPERS
-- ============================================================

--- Build the launch URI for a package based on config
---@param data table Config data
---@param package_name string
---@return string|nil uri
---@return string|nil error
function config.get_launch_uri(data, package_name)
    local server = data.server or {}
    local stype, value

    if server.mode == "per_package" and server.per_package then
        local pkg_cfg = server.per_package[package_name]
        if pkg_cfg then
            stype = pkg_cfg.type or server.type
            value = pkg_cfg.value or ""
        end
    end

    -- Fallback to global
    if not stype then
        stype = server.type or "ps_link"
    end

    if stype == "ps_link" then
        value = value or server.ps_link or ""
        if value == "" then
            return nil, "PS link not configured"
        end
        -- PS links are opened directly
        return value, nil
    elseif stype == "place_id" then
        local place_id = value or server.place_id or ""
        if place_id == "" then
            return nil, "Place ID not configured"
        end
        return "roblox://experiences/start?placeId=" .. tostring(place_id), nil
    elseif stype == "job_id" then
        local place_id = server.place_id or ""
        local job_id = value or server.job_id or ""
        if place_id == "" then
            return nil, "Place ID not configured (required for Job ID)"
        end
        if job_id == "" then
            return nil, "Job ID not configured"
        end
        return "roblox://experiences/start?placeId=" .. tostring(place_id) ..
               "&gameInstanceId=" .. tostring(job_id), nil
    else
        return nil, "Unknown server type: " .. tostring(stype)
    end
end

--- Get the list of packages to monitor based on config
---@param data table Config data
---@param available_packages table List of packages found on device
---@return table packages_to_monitor
function config.get_target_packages(data, available_packages)
    local pkg_cfg = data.packages or {}

    -- Determine the full list
    local full_list
    if pkg_cfg.mode == "manual" and pkg_cfg.manual_list and #pkg_cfg.manual_list > 0 then
        full_list = pkg_cfg.manual_list
    else
        full_list = available_packages
    end

    -- Filter by selected (if any)
    if pkg_cfg.selected and #pkg_cfg.selected > 0 then
        local selected_set = {}
        for _, p in ipairs(pkg_cfg.selected) do
            selected_set[p] = true
        end
        local filtered = {}
        for _, p in ipairs(full_list) do
            if selected_set[p] then
                filtered[#filtered + 1] = p
            end
        end
        return filtered
    end

    return full_list
end

--- Get cookie for a specific package
---@param data table Config data
---@param package_name string
---@return string|nil cookie
function config.get_cookie(data, package_name)
    local cookies = config.get(data, "cookie.cookies", {})
    return cookies[package_name]
end

--- Set cookie for a specific package
---@param data table Config data
---@param package_name string
---@param cookie_value string
function config.set_cookie(data, package_name, cookie_value)
    if not data.cookie then data.cookie = {} end
    if not data.cookie.cookies then data.cookie.cookies = {} end
    data.cookie.cookies[package_name] = cookie_value
end

return config
