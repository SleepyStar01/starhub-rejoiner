-- StarhubRejoiner: API-Ready Interface
-- JSON command interface for future StarhubUI web panel integration
-- Exposes all core functions with JSON request/response format

local json = require("json")
local config = require("config")
local device = require("device")
local shell = require("shell")

local api = {}

-- ============================================================
-- COMMAND HANDLERS
-- ============================================================

local handlers = {}

--- GET /status — Get status of all packages
handlers.get_status = function(params, cfg_data)
    local packages = device.get_packages(config.get(cfg_data, "packages.prefix", "roblox"))
    local target = config.get_target_packages(cfg_data, packages)
    local statuses = device.get_all_status(target)

    -- System info
    local cpu = shell.get_cpu_usage()
    local mem_used, mem_total, mem_percent = shell.get_memory_info()

    return {
        ok = true,
        system = {
            cpu = cpu,
            memory_used = mem_used,
            memory_total = mem_total,
            memory_percent = mem_percent,
            device_model = device.model(),
            android_version = device.android_version(),
        },
        packages = statuses,
    }
end

--- GET /packages — List all available packages
handlers.get_packages = function(params, cfg_data)
    local prefix = params and params.prefix or config.get(cfg_data, "packages.prefix", "roblox")
    local packages = device.scan_packages(prefix)
    return {
        ok = true,
        packages = packages,
        count = #packages,
    }
end

--- POST /rejoin — Rejoin a specific package
handlers.rejoin = function(params, cfg_data)
    if not params or not params.package then
        return { ok = false, error = "missing 'package' parameter" }
    end

    local pkg = params.package
    local uri, err = config.get_launch_uri(cfg_data, pkg)
    if not uri then
        return { ok = false, error = err }
    end

    -- Force stop
    shell.am_force_stop(pkg)
    shell.sleep(1)

    -- Clear cache
    if config.get(cfg_data, "monitor.clear_cache_on_rejoin", true) then
        shell.clear_cache(pkg)
    end

    -- Clear logcat
    shell.logcat_clear()
    shell.sleep(1)

    -- Launch
    local code, output = shell.am_start(pkg, uri)
    return {
        ok = code == 0,
        package = pkg,
        uri = uri,
        output = output,
    }
end

--- POST /force_stop — Force stop a package
handlers.force_stop = function(params, cfg_data)
    if not params or not params.package then
        return { ok = false, error = "missing 'package' parameter" }
    end
    local code, output = shell.am_force_stop(params.package)
    return { ok = code == 0, output = output }
end

--- POST /inject_cookie — Inject a cookie into a package
handlers.inject_cookie = function(params, cfg_data)
    if not params or not params.package or not params.cookie then
        return { ok = false, error = "missing 'package' or 'cookie' parameter" }
    end

    local cookie_mod = require("cookie")
    local ok, err = cookie_mod.inject(params.package, params.cookie)
    if ok then
        config.set_cookie(cfg_data, params.package, cookie_mod.clean(params.cookie))
        config.save(cfg_data)
    end
    return { ok = ok, error = err }
end

--- GET /config — Get current config
handlers.get_config = function(params, cfg_data)
    -- Strip sensitive data
    local safe_config = json.decode(json.encode(cfg_data))
    if safe_config.cookie and safe_config.cookie.cookies then
        for k, v in pairs(safe_config.cookie.cookies) do
            if type(v) == "string" and #v > 16 then
                safe_config.cookie.cookies[k] = v:sub(1, 8) .. "****"
            end
        end
    end
    return { ok = true, config = safe_config }
end

--- POST /set_config — Update config values
handlers.set_config = function(params, cfg_data)
    if not params or not params.key or params.value == nil then
        return { ok = false, error = "missing 'key' or 'value' parameter" }
    end
    config.set(cfg_data, params.key, params.value)
    local ok, err = config.save(cfg_data)
    return { ok = ok, error = err }
end

--- GET /ping — Health check
handlers.ping = function(params, cfg_data)
    return {
        ok = true,
        version = "1.0.0",
        timestamp = os.time(),
        uptime = os.clock(),
    }
end

-- ============================================================
-- COMMAND DISPATCHER
-- ============================================================

--- Execute an API command
---@param command string Command name
---@param params table|nil Command parameters
---@param cfg_data table Config data
---@return table Response object
function api.execute(command, params, cfg_data)
    local handler = handlers[command]
    if not handler then
        return { ok = false, error = "unknown command: " .. tostring(command) }
    end

    local ok, result = pcall(handler, params, cfg_data)
    if not ok then
        return { ok = false, error = "internal error: " .. tostring(result) }
    end

    return result
end

--- Process a JSON command string
---@param json_str string JSON string: { "command": "...", "params": { ... } }
---@param cfg_data table Config data
---@return string JSON response string
function api.process_json(json_str, cfg_data)
    local ok, request = pcall(json.decode, json_str)
    if not ok then
        return json.encode({ ok = false, error = "invalid JSON: " .. tostring(request) })
    end

    if type(request) ~= "table" or not request.command then
        return json.encode({ ok = false, error = "missing 'command' field" })
    end

    local result = api.execute(request.command, request.params, cfg_data)
    return json.encode(result)
end

--- Run API in stdin/stdout mode (pipe-based)
--- Reads JSON commands from stdin, writes JSON responses to stdout
---@param cfg_data table Config data
function api.stdin_loop(cfg_data)
    io.stderr:write("[api] StarhubRejoiner API ready (stdin/stdout mode)\n")
    io.stderr:write("[api] Send JSON commands, one per line\n")

    while true do
        local line = io.read("*l")
        if not line then break end -- EOF
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            local response = api.process_json(line, cfg_data)
            io.write(response .. "\n")
            io.flush()
        end
    end
end

--- List all available API commands
---@return table commands Array of { name, description }
function api.list_commands()
    return {
        { name = "ping",           description = "Health check" },
        { name = "get_status",     description = "Get status of all monitored packages" },
        { name = "get_packages",   description = "List installed Roblox packages" },
        { name = "rejoin",         description = "Rejoin a specific package (params: package)" },
        { name = "force_stop",     description = "Force stop a package (params: package)" },
        { name = "inject_cookie",  description = "Inject cookie (params: package, cookie)" },
        { name = "get_config",     description = "Get current configuration" },
        { name = "set_config",     description = "Update config value (params: key, value)" },
    }
end

return api
