#!/usr/bin/env lua
-- ============================================================
-- StarhubRejoiner v1.0 -- Single-file distribution
-- Do not edit directly. Edit source files and run build.ps1
-- ============================================================

-- Inline module system
local _MODULES = {}
local _LOADED = {}
local _real_require = require
require = function(name)
    if _LOADED[name] ~= nil then return _LOADED[name] end
    if _MODULES[name] then
        _LOADED[name] = _MODULES[name]() or true
        return _LOADED[name]
    end
    return _real_require(name)
end
-- ============================================================
-- MODULE: json
-- ============================================================
_MODULES["json"] = function()
-- StarhubRejoiner: Pure Lua JSON encoder/decoder
-- No external dependencies required

local json = {}

-- ============================================================
-- DECODE
-- ============================================================

local function decode_error(str, idx, msg)
    local line = 1
    local col = 1
    for i = 1, idx do
        if str:sub(i, i) == "\n" then
            line = line + 1
            col = 1
        else
            col = col + 1
        end
    end
    error(string.format("[json] decode error at line %d col %d: %s", line, col, msg))
end

local function skip_whitespace(str, idx)
    local _, next_idx = str:find("^[ \n\r\t]*", idx)
    return (next_idx or idx - 1) + 1
end

local function decode_string(str, idx)
    if str:sub(idx, idx) ~= '"' then
        decode_error(str, idx, "expected '\"'")
    end
    idx = idx + 1
    local parts = {}
    local start = idx
    while idx <= #str do
        local c = str:sub(idx, idx)
        if c == '"' then
            parts[#parts + 1] = str:sub(start, idx - 1)
            return table.concat(parts), idx + 1
        elseif c == "\\" then
            parts[#parts + 1] = str:sub(start, idx - 1)
            idx = idx + 1
            local esc = str:sub(idx, idx)
            local escape_map = {
                ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
                ['b'] = '\b', ['f'] = '\f', ['n'] = '\n',
                ['r'] = '\r', ['t'] = '\t',
            }
            if esc == 'u' then
                local hex = str:sub(idx + 1, idx + 4)
                if not hex:match("^%x%x%x%x$") then
                    decode_error(str, idx, "invalid unicode escape")
                end
                local codepoint = tonumber(hex, 16)
                if codepoint < 128 then
                    parts[#parts + 1] = string.char(codepoint)
                elseif codepoint < 2048 then
                    parts[#parts + 1] = string.char(
                        192 + math.floor(codepoint / 64),
                        128 + (codepoint % 64)
                    )
                else
                    parts[#parts + 1] = string.char(
                        224 + math.floor(codepoint / 4096),
                        128 + math.floor((codepoint % 4096) / 64),
                        128 + (codepoint % 64)
                    )
                end
                idx = idx + 5
            elseif escape_map[esc] then
                parts[#parts + 1] = escape_map[esc]
                idx = idx + 1
            else
                decode_error(str, idx, "invalid escape '\\" .. esc .. "'")
            end
            start = idx
        else
            idx = idx + 1
        end
    end
    decode_error(str, start, "unterminated string")
end

local decode_value -- forward declaration

local function decode_array(str, idx)
    idx = idx + 1 -- skip '['
    local result = {}
    idx = skip_whitespace(str, idx)
    if str:sub(idx, idx) == ']' then
        return result, idx + 1
    end
    while true do
        local value
        value, idx = decode_value(str, idx)
        result[#result + 1] = value
        idx = skip_whitespace(str, idx)
        local c = str:sub(idx, idx)
        if c == ']' then
            return result, idx + 1
        elseif c == ',' then
            idx = skip_whitespace(str, idx + 1)
        else
            decode_error(str, idx, "expected ']' or ','")
        end
    end
end

local function decode_object(str, idx)
    idx = idx + 1 -- skip '{'
    local result = {}
    idx = skip_whitespace(str, idx)
    if str:sub(idx, idx) == '}' then
        return result, idx + 1
    end
    while true do
        if str:sub(idx, idx) ~= '"' then
            decode_error(str, idx, "expected string key")
        end
        local key
        key, idx = decode_string(str, idx)
        idx = skip_whitespace(str, idx)
        if str:sub(idx, idx) ~= ':' then
            decode_error(str, idx, "expected ':'")
        end
        idx = skip_whitespace(str, idx + 1)
        local value
        value, idx = decode_value(str, idx)
        result[key] = value
        idx = skip_whitespace(str, idx)
        local c = str:sub(idx, idx)
        if c == '}' then
            return result, idx + 1
        elseif c == ',' then
            idx = skip_whitespace(str, idx + 1)
        else
            decode_error(str, idx, "expected '}' or ','")
        end
    end
end

decode_value = function(str, idx)
    idx = skip_whitespace(str, idx)
    local c = str:sub(idx, idx)
    if c == '"' then
        return decode_string(str, idx)
    elseif c == '{' then
        return decode_object(str, idx)
    elseif c == '[' then
        return decode_array(str, idx)
    elseif c == 't' then
        if str:sub(idx, idx + 3) == "true" then
            return true, idx + 4
        end
        decode_error(str, idx, "invalid value")
    elseif c == 'f' then
        if str:sub(idx, idx + 4) == "false" then
            return false, idx + 5
        end
        decode_error(str, idx, "invalid value")
    elseif c == 'n' then
        if str:sub(idx, idx + 3) == "null" then
            return nil, idx + 4
        end
        decode_error(str, idx, "invalid value")
    elseif c == '-' or (c >= '0' and c <= '9') then
        local num_str = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", idx)
        if not num_str then
            decode_error(str, idx, "invalid number")
        end
        local num = tonumber(num_str)
        if not num then
            decode_error(str, idx, "invalid number: " .. num_str)
        end
        return num, idx + #num_str
    else
        decode_error(str, idx, "unexpected character '" .. c .. "'")
    end
end

--- Decode a JSON string into a Lua value
---@param str string JSON string
---@return any Decoded Lua value
function json.decode(str)
    if type(str) ~= "string" then
        error("[json] decode expects a string, got " .. type(str))
    end
    str = str:gsub("^\239\187\191", "") -- strip BOM
    local value, idx = decode_value(str, 1)
    idx = skip_whitespace(str, idx)
    if idx <= #str then
        decode_error(str, idx, "trailing content after value")
    end
    return value
end

-- ============================================================
-- ENCODE
-- ============================================================

local encode_value -- forward declaration

local function encode_string(val)
    val = tostring(val)
    local escape_map = {
        ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b',
        ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
    }
    val = val:gsub('["\\\b\f\n\r\t]', escape_map)
    -- escape control characters
    val = val:gsub("[\x00-\x1f]", function(c)
        return string.format("\\u%04x", string.byte(c))
    end)
    return '"' .. val .. '"'
end

local function is_array(t)
    if type(t) ~= "table" then return false end
    local max_idx = 0
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false
        end
        if k > max_idx then max_idx = k end
        count = count + 1
    end
    return max_idx == count
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

encode_value = function(val, indent, current_indent)
    local val_type = type(val)
    if val == nil then
        return "null"
    elseif val_type == "boolean" then
        return val and "true" or "false"
    elseif val_type == "number" then
        if val ~= val then return "null" end -- NaN
        if val == math.huge or val == -math.huge then return "null" end
        if val == math.floor(val) and math.abs(val) < 1e15 then
            return string.format("%d", val)
        end
        return tostring(val)
    elseif val_type == "string" then
        return encode_string(val)
    elseif val_type == "table" then
        local next_indent = indent and (current_indent .. indent) or nil
        local separator = indent and ",\n" or ","
        local open_newline = indent and "\n" or ""
        local close_indent = indent and current_indent or ""

        if is_array(val) then
            if #val == 0 then return "[]" end
            local parts = {}
            for i = 1, #val do
                local prefix = next_indent and next_indent or ""
                parts[#parts + 1] = prefix .. encode_value(val[i], indent, next_indent or "")
            end
            return "[" .. open_newline .. table.concat(parts, separator) .. open_newline .. close_indent .. "]"
        else
            local keys = sorted_keys(val)
            if #keys == 0 then return "{}" end
            local parts = {}
            for _, k in ipairs(keys) do
                local prefix = next_indent and next_indent or ""
                local key_str = encode_string(tostring(k))
                local val_str = encode_value(val[k], indent, next_indent or "")
                local kv_sep = indent and ": " or ":"
                parts[#parts + 1] = prefix .. key_str .. kv_sep .. val_str
            end
            return "{" .. open_newline .. table.concat(parts, separator) .. open_newline .. close_indent .. "}"
        end
    else
        error("[json] cannot encode type: " .. val_type)
    end
end

--- Encode a Lua value into a JSON string
---@param val any Lua value to encode
---@param pretty boolean|nil If true, output is pretty-printed with 2-space indent
---@return string JSON string
function json.encode(val, pretty)
    local indent = pretty and "  " or nil
    return encode_value(val, indent, "")
end

--- Read and decode a JSON file
---@param path string File path
---@return any|nil Decoded value, or nil on error
---@return string|nil Error message
function json.read_file(path)
    local f, err = io.open(path, "r")
    if not f then
        return nil, "cannot open file: " .. tostring(err)
    end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then
        return nil, "file is empty"
    end
    local ok, result = pcall(json.decode, content)
    if not ok then
        return nil, tostring(result)
    end
    return result, nil
end

--- Encode and write a value to a JSON file
---@param path string File path
---@param val any Value to encode
---@param pretty boolean|nil Pretty-print
---@return boolean Success
---@return string|nil Error message
function json.write_file(path, val, pretty)
    local ok, encoded = pcall(json.encode, val, pretty)
    if not ok then
        return false, tostring(encoded)
    end
    local f, err = io.open(path, "w")
    if not f then
        return false, "cannot write file: " .. tostring(err)
    end
    f:write(encoded)
    f:write("\n")
    f:close()
    return true, nil
end

return json

end

-- ============================================================
-- MODULE: shell
-- ============================================================
_MODULES["shell"] = function()
-- StarhubRejoiner: Shell command execution layer
-- Provides safe shell execution, root commands, and Android-specific helpers

local shell = {}

--- Quote a value for safe shell usage
---@param value any Value to quote
---@return string Shell-safe quoted string
function shell.quote(value)
    value = tostring(value or "")
    return "'" .. value:gsub("'", "'\"'\"'") .. "'"
end

--- Trim whitespace from string
---@param s string
---@return string
function shell.trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Run a shell command and capture output + exit code
---@param command string Command to execute
---@return number exit_code
---@return string output (trimmed)
function shell.run(command)
    local marker = "__STARHUB_EXIT__:"
    local wrapped = command .. "; printf '\\n" .. marker .. "%s' \"$?\""
    local handle = io.popen(wrapped .. " 2>&1")
    if not handle then
        return 1, "failed to spawn command"
    end
    local output = handle:read("*a") or ""
    handle:close()
    local code = tonumber(output:match(marker .. "(%d+)%s*$")) or 1
    output = output:gsub("\n?" .. marker .. "%d+%s*$", "")
    return code, shell.trim(output)
end

--- Run a command via sh -c with stdin detached
---@param command string
---@return number exit_code
---@return string output
function shell.exec(command)
    return shell.run("sh -c " .. shell.quote(command) .. " </dev/null")
end

--- Run a command as root via su
---@param command string
---@return number exit_code
---@return string output
function shell.su(command)
    return shell.run("su -c " .. shell.quote(command) .. " </dev/null")
end

--- Check if root access is available
---@return boolean has_root
---@return string info (uid info or error)
function shell.check_root()
    local code, output = shell.su("id")
    if code == 0 and output:find("uid=0") then
        return true, output
    end
    return false, output
end

--- Sleep for N seconds
---@param seconds number
function shell.sleep(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return end
    shell.exec("sleep " .. shell.quote(tostring(seconds)))
end

--- Get terminal width
---@return number columns
function shell.term_cols()
    local _, output = shell.exec("command -v tput >/dev/null 2>&1 && tput cols || echo 80")
    return tonumber(shell.trim(output)) or 80
end

--- Clear the terminal screen
function shell.clear()
    os.execute("clear 2>/dev/null || cls 2>/dev/null")
end

-- ============================================================
-- Android-specific commands
-- ============================================================

--- Launch an app via Android Activity Manager
---@param package_name string Package name (e.g. "com.roblox.client")
---@param uri string|nil URI to open (deep link or URL)
---@return number exit_code
---@return string output
function shell.am_start(package_name, uri)
    if uri then
        return shell.su(
            "am start -a android.intent.action.VIEW" ..
            " -d " .. shell.quote(uri) ..
            " -p " .. shell.quote(package_name)
        )
    else
        return shell.su(
            "monkey -p " .. shell.quote(package_name) .. " 1 2>/dev/null"
        )
    end
end

--- Force stop an app
---@param package_name string
---@return number exit_code
---@return string output
function shell.am_force_stop(package_name)
    return shell.su("am force-stop " .. shell.quote(package_name))
end

--- Clear app cache
---@param package_name string
---@return number exit_code
---@return string output
function shell.clear_cache(package_name)
    return shell.su("rm -rf /data/data/" .. shell.quote(package_name) .. "/cache/* 2>/dev/null; echo ok")
end

--- Get PID of a running package
---@param package_name string
---@return number|nil pid
function shell.get_pid(package_name)
    local code, output = shell.su("pidof " .. shell.quote(package_name))
    if code == 0 and output ~= "" then
        -- pidof can return multiple PIDs, take the first
        local pid = output:match("(%d+)")
        return tonumber(pid)
    end
    return nil
end

--- Check if a package is currently running
---@param package_name string
---@return boolean is_running
function shell.is_running(package_name)
    return shell.get_pid(package_name) ~= nil
end

--- Get recent logcat lines for a package
---@param package_name string
---@param lines number Number of lines
---@return string logcat_output
function shell.logcat(package_name, lines)
    lines = lines or 200
    local pid = shell.get_pid(package_name)
    if not pid then
        return ""
    end
    local _, output = shell.su(
        "logcat -d -t " .. tostring(lines) ..
        " --pid=" .. tostring(pid) .. " 2>/dev/null"
    )
    return output or ""
end

--- Clear logcat buffer
---@return number exit_code
function shell.logcat_clear()
    local code = shell.su("logcat -c 2>/dev/null")
    return code
end

--- List installed packages matching a pattern
---@param pattern string Grep pattern
---@return table List of package names
function shell.list_packages(pattern)
    pattern = pattern or "roblox"
    local _, output = shell.su("pm list packages 2>/dev/null | grep -i " .. shell.quote(pattern))
    local packages = {}
    for line in (output or ""):gmatch("[^\n]+") do
        local pkg = line:match("^package:(.+)$")
        if pkg then
            packages[#packages + 1] = shell.trim(pkg)
        end
    end
    return packages
end

--- Get device CPU usage percentage by measuring delta
---@return string cpu_info
function shell.get_cpu_usage()
    local function read_stat()
        local _, out = shell.exec("cat /proc/stat 2>/dev/null | head -1")
        local fields = {}
        for v in (out or ""):gmatch("%d+") do
            fields[#fields + 1] = tonumber(v)
        end
        if #fields >= 4 then
            local total = 0
            for _, v in ipairs(fields) do total = total + v end
            return total, fields[4] -- total, idle
        end
        return nil, nil
    end

    local t1, i1 = read_stat()
    if not t1 then return "N/A" end

    shell.sleep(0.3) -- wait a bit to get a delta

    local t2, i2 = read_stat()
    if not t2 or t2 == t1 then return "N/A" end

    local total_diff = t2 - t1
    local idle_diff = i2 - i1
    
    local usage = (1 - (idle_diff / total_diff)) * 100
    if usage < 0 then usage = 0 end
    if usage > 100 then usage = 100 end

    return string.format("%.1f%%", usage)
end

--- Get device memory info
---@return string used_gb
---@return string total_gb
---@return string percent
function shell.get_memory_info()
    local _, output = shell.exec("cat /proc/meminfo 2>/dev/null")
    local total_kb = tonumber((output or ""):match("MemTotal:%s+(%d+)")) or 0
    local avail_kb = tonumber((output or ""):match("MemAvailable:%s+(%d+)"))
    if not avail_kb then
        local free_kb = tonumber((output or ""):match("MemFree:%s+(%d+)")) or 0
        local buffers_kb = tonumber((output or ""):match("Buffers:%s+(%d+)")) or 0
        local cached_kb = tonumber((output or ""):match("Cached:%s+(%d+)")) or 0
        avail_kb = free_kb + buffers_kb + cached_kb
    end
    local used_kb = total_kb - avail_kb
    local total_gb = total_kb / 1048576
    local used_gb = used_kb / 1048576
    local percent = total_kb > 0 and (used_kb / total_kb * 100) or 0
    return string.format("%.1f GB", used_gb),
           string.format("%.1f GB", total_gb),
           string.format("%.1f%%", percent)
end

--- Get SELinux status
---@return string status ("Enforcing", "Permissive", or "Unknown")
function shell.get_selinux()
    local _, output = shell.su("getenforce 2>/dev/null")
    output = shell.trim(output)
    if output == "Enforcing" or output == "Permissive" or output == "Disabled" then
        return output
    end
    return "Unknown"
end

--- Set SELinux to Permissive
---@return boolean success
function shell.set_selinux_permissive()
    local code = shell.su("setenforce 0 2>/dev/null")
    return code == 0
end

--- Get Android SDK version
---@return number|nil sdk_version
function shell.get_android_version()
    local _, output = shell.su("getprop ro.build.version.sdk 2>/dev/null")
    return tonumber(shell.trim(output))
end

--- Get device model
---@return string model
function shell.get_device_model()
    local _, output = shell.su("getprop ro.product.model 2>/dev/null")
    local model = shell.trim(output)
    if model == "" then
        _, output = shell.su("getprop ro.product.name 2>/dev/null")
        model = shell.trim(output)
    end
    return model ~= "" and model or "Unknown"
end

--- Execute SQLite command on a database
---@param db_path string Path to SQLite database
---@param sql string SQL command
---@return number exit_code
---@return string output
function shell.sqlite(db_path, sql)
    -- Find sqlite3 absolute path in the non-su environment (Termux usually has it in a non-standard path)
    local _, sqlite_path = shell.exec("command -v sqlite3 2>/dev/null")
    sqlite_path = shell.trim(sqlite_path or "")
    if sqlite_path == "" then
        sqlite_path = "sqlite3" -- Fallback
    end

    return shell.su(
        sqlite_path .. " " .. shell.quote(db_path) .. " " .. shell.quote(sql) .. " 2>&1"
    )
end

--- Fetch game name from Roblox API using place ID
---@param place_id string|number
---@return string|nil game_name
function shell.fetch_game_name(place_id)
    if not place_id or tostring(place_id) == "" then return nil end
    local url = "https://economy.roblox.com/v2/assets/" .. tostring(place_id) .. "/details"
    local _, out = shell.exec("curl -s " .. shell.quote(url) .. " 2>/dev/null")
    if out and out ~= "" then
        local name = out:match('"Name"%s*:%s*"([^"]+)"')
        if name then
            return name
        end
    end
    return nil
end
--- Verify a Roblox cookie via API
---@param cookie_string string
---@return boolean is_valid
---@return string username_or_error
function shell.verify_cookie(cookie_string)
    if not cookie_string or cookie_string == "" then return false, "No cookie provided" end
    
    local url = "https://users.roblox.com/v1/users/authenticated"
    local header = 'Cookie: .ROBLOSECURITY=' .. cookie_string
    local cmd = string.format("curl -s -H %s %s 2>/dev/null", shell.quote(header), shell.quote(url))
    
    local _, out = shell.exec(cmd)
    if out and out:find('"name"') then
        local name = out:match('"name"%s*:%s*"([^"]+)"')
        if name then
            return true, name
        end
    end
    
    return false, "Invalid or expired cookie"
end

return shell

end

-- ============================================================
-- MODULE: ui
-- ============================================================
_MODULES["ui"] = function()
-- StarhubRejoiner: Terminal UI components
-- Beautiful TUI rendering for Termux — colors, tables, menus, banners

local ui = {}

-- ============================================================
-- ANSI Color Codes
-- ============================================================

ui.color = {
    -- Reset
    reset     = "\27[0m",
    bold      = "\27[1m",
    dim       = "\27[2m",
    underline = "\27[4m",

    -- Foreground
    black     = "\27[30m",
    red       = "\27[91m",
    green     = "\27[92m",
    yellow    = "\27[93m",
    blue      = "\27[94m",
    magenta   = "\27[95m",
    cyan      = "\27[96m",
    white     = "\27[97m",
    gray      = "\27[90m",

    -- Background
    bg_black  = "\27[40m",
    bg_red    = "\27[41m",
    bg_green  = "\27[42m",
    bg_yellow = "\27[43m",
    bg_blue   = "\27[44m",
    bg_cyan   = "\27[46m",
    bg_white  = "\27[47m",
}

local C = ui.color

--- Apply color to text
---@param text string
---@param color string ANSI color code
---@return string
function ui.c(text, color)
    return color .. tostring(text) .. C.reset
end

--- Bold text
function ui.bold(text)
    return C.bold .. tostring(text) .. C.reset
end

--- Dim text
function ui.dim(text)
    return C.dim .. tostring(text) .. C.reset
end

-- ============================================================
-- BRAND BANNER
-- ============================================================

local BANNER = {
    C.cyan .. "╔══════════════════════════════════════════════╗" .. C.reset,
    C.cyan .. "║" .. C.reset .. C.bold .. C.cyan .. "          ★ StarhubRejoiner v1.0 ★           " .. C.reset .. C.cyan .. "║" .. C.reset,
    C.cyan .. "╚══════════════════════════════════════════════╝" .. C.reset,
}

--- Print the application banner
function ui.banner()
    for _, line in ipairs(BANNER) do
        print(line)
    end
end

--- Print a section header
---@param title string
function ui.header(title)
    local bar = C.cyan .. string.rep("─", 46) .. C.reset
    print("")
    print(bar)
    print(C.bold .. C.white .. "  " .. title .. C.reset)
    print(bar)
end

--- Print a sub-header
---@param title string
function ui.subheader(title)
    print("")
    print(C.yellow .. C.bold .. "  " .. title .. C.reset)
    print(C.gray .. "  " .. string.rep("·", 40) .. C.reset)
end

-- ============================================================
-- STATUS INDICATORS
-- ============================================================

ui.status = {
    ok      = C.green  .. "●" .. C.reset,
    error   = C.red    .. "●" .. C.reset,
    warning = C.yellow .. "●" .. C.reset,
    info    = C.cyan   .. "●" .. C.reset,
    off     = C.gray   .. "●" .. C.reset,
}

--- Get colored status text
---@param state string "ingame"|"stopped"|"crashed"|"disconnected"|"launching"|"unknown"
---@return string
function ui.state_badge(state)
    local badges = {
        running      = C.green  .. "● running"      .. C.reset,
        background   = C.yellow .. "● background"   .. C.reset,
        stopped      = C.red    .. "● stopped"      .. C.reset,
        crashed      = C.red    .. "● crashed"      .. C.reset,
        disconnected = C.yellow .. "● disconnected" .. C.reset,
        launching    = C.cyan   .. "● launching"    .. C.reset,
        rejoining    = C.cyan   .. "● rejoining"    .. C.reset,
        unknown      = C.gray   .. "● unknown"      .. C.reset,
    }
    return badges[state] or badges.unknown
end

-- ============================================================
-- TABLE RENDERER
-- ============================================================

--- Calculate visible string length (ignoring ANSI escape codes)
---@param s string
---@return number
function ui.visible_len(s)
    -- strip ANSI escape sequences
    local stripped = tostring(s):gsub("\27%[[%d;]*[A-Za-z]", "")
    return #stripped
end

--- Pad string to target width (accounting for ANSI codes)
---@param s string
---@param width number
---@param align string "left"|"right"|"center"
---@return string
function ui.pad(s, width, align)
    s = tostring(s)
    local visible = ui.visible_len(s)
    local needed = width - visible
    if needed <= 0 then return s end

    align = align or "left"
    if align == "right" then
        return string.rep(" ", needed) .. s
    elseif align == "center" then
        local left = math.floor(needed / 2)
        local right = needed - left
        return string.rep(" ", left) .. s .. string.rep(" ", right)
    else
        return s .. string.rep(" ", needed)
    end
end

--- Truncate text to max visible width
---@param text string
---@param max_width number
---@return string
function ui.truncate(text, max_width)
    text = tostring(text)
    if ui.visible_len(text) <= max_width then
        return text
    end
    if max_width <= 3 then
        return text:sub(1, max_width)
    end
    -- For colored strings, just truncate the raw text part
    local stripped = text:gsub("\27%[[%d;]*[A-Za-z]", "")
    return stripped:sub(1, max_width - 2) .. ".."
end

--- Render a bordered table
---@param headers table Array of column header strings
---@param rows table Array of row arrays
---@param options table|nil { col_widths: table, border_color: string }
function ui.table(headers, rows, options)
    options = options or {}
    local border_color = options.border_color or C.cyan
    local bc = border_color

    -- Calculate column widths
    local col_widths = options.col_widths or {}
    for i, h in ipairs(headers) do
        col_widths[i] = col_widths[i] or ui.visible_len(h)
    end
    for _, row in ipairs(rows) do
        for i, cell in ipairs(row) do
            local len = ui.visible_len(cell)
            if len > (col_widths[i] or 0) then
                col_widths[i] = len
            end
        end
    end

    -- Add padding
    for i = 1, #col_widths do
        col_widths[i] = col_widths[i] + 2 -- 1 space padding each side
    end

    -- Build border lines
    local function make_line(left, mid, right, fill)
        local parts = { bc .. left }
        for i, w in ipairs(col_widths) do
            parts[#parts + 1] = string.rep(fill, w)
            if i < #col_widths then
                parts[#parts + 1] = mid
            end
        end
        parts[#parts + 1] = right .. C.reset
        return table.concat(parts)
    end

    local top_line = make_line("┌", "┬", "┐", "─")
    local mid_line = make_line("├", "┼", "┤", "─")
    local bot_line = make_line("└", "┴", "┘", "─")

    local function make_row(cells, is_header)
        local parts = { bc .. "│" .. C.reset }
        for i, cell in ipairs(cells) do
            local text = ui.pad(" " .. ui.truncate(tostring(cell), col_widths[i] - 2) .. " ", col_widths[i])
            if is_header then
                text = C.bold .. C.white .. text .. C.reset
            end
            parts[#parts + 1] = text
            parts[#parts + 1] = bc .. "│" .. C.reset
        end
        return table.concat(parts)
    end

    -- Print table
    print(top_line)
    print(make_row(headers, true))
    print(mid_line)
    if #rows == 0 then
        local empty_width = 0
        for _, w in ipairs(col_widths) do empty_width = empty_width + w end
        empty_width = empty_width + #col_widths - 1 -- separators
        local msg = C.gray .. " (empty)" .. C.reset
        print(bc .. "│" .. C.reset .. ui.pad(msg, empty_width) .. bc .. "│" .. C.reset)
    else
        for _, row in ipairs(rows) do
            print(make_row(row))
        end
    end
    print(bot_line)
end

-- ============================================================
-- MENU SYSTEM
-- ============================================================

--- Print a menu and get user selection
---@param items table Array of { key: string, label: string, color: string|nil }
---@param prompt string|nil Custom prompt text
---@return string|nil Selected key
function ui.menu(items, prompt)
    print("")
    local max_key_len = 0
    for _, item in ipairs(items) do
        if #tostring(item.key) > max_key_len then
            max_key_len = #tostring(item.key)
        end
    end

    for _, item in ipairs(items) do
        local key_str = ui.pad(tostring(item.key), max_key_len, "right")
        local color = item.color or C.white
        local label = item.label or ""
        local prefix = "  "
        if item.separator then
            print("")
        else
            print(prefix .. C.cyan .. "[" .. C.yellow .. key_str .. C.cyan .. "]" .. C.reset .. " " .. color .. label .. C.reset)
        end
    end

    print("")
    local separator = C.cyan .. string.rep("═", 46) .. C.reset
    print(separator)
    io.write(C.cyan .. "? " .. C.white .. (prompt or "Select an option") .. " : " .. C.reset)
    io.flush()
    local input = io.read("*l")
    return input and input:match("^%s*(.-)%s*$") or nil
end

--- Simple yes/no prompt
---@param question string
---@param default boolean|nil Default value (true=yes, false=no)
---@return boolean
function ui.confirm(question, default)
    local hint = default == true and "(Y/n)" or
                 default == false and "(y/N)" or "(y/n)"
    io.write(C.cyan .. "? " .. C.white .. question .. " " .. C.gray .. hint .. " " .. C.reset)
    io.flush()
    local input = (io.read("*l") or ""):lower():match("^%s*(.-)%s*$")
    if input == "" and default ~= nil then
        return default
    end
    return input == "y" or input == "yes"
end

--- Text input prompt
---@param label string
---@param default string|nil Default value
---@return string
function ui.input(label, default)
    local hint = default and (" [" .. tostring(default) .. "]") or ""
    io.write(C.cyan .. "? " .. C.white .. label .. C.gray .. hint .. " : " .. C.reset)
    io.flush()
    local input = (io.read("*l") or ""):match("^%s*(.-)%s*$")
    if input == "" and default then
        return default
    end
    return input
end

--- Number input prompt
---@param label string
---@param default number|nil
---@param min_val number|nil
---@param max_val number|nil
---@return number|nil
function ui.input_number(label, default, min_val, max_val)
    local hint = default and (" [" .. tostring(default) .. "]") or ""
    io.write(C.cyan .. "? " .. C.white .. label .. C.gray .. hint .. " : " .. C.reset)
    io.flush()
    local input = (io.read("*l") or ""):match("^%s*(.-)%s*$")
    if input == "" and default then
        return default
    end
    local num = tonumber(input)
    if not num then return default end
    if min_val and num < min_val then num = min_val end
    if max_val and num > max_val then num = max_val end
    return num
end

-- ============================================================
-- LOG / MESSAGE OUTPUT
-- ============================================================

--- Print an info message
function ui.info(msg)
    print(C.cyan .. "[*]" .. C.reset .. " " .. tostring(msg))
end

--- Print a success message
function ui.success(msg)
    print(C.green .. "[✓]" .. C.reset .. " " .. tostring(msg))
end

--- Print a warning message
function ui.warn(msg)
    print(C.yellow .. "[!]" .. C.reset .. " " .. tostring(msg))
end

--- Print an error message
function ui.error(msg)
    print(C.red .. "[✗]" .. C.reset .. " " .. tostring(msg))
end

--- Print a timestamped log message
---@param msg string
---@param color string|nil
function ui.log(msg, color)
    local time = os.date("%H:%M:%S")
    color = color or C.white
    print(C.gray .. "[" .. time .. "]" .. C.reset .. " " .. color .. tostring(msg) .. C.reset)
end

--- Print a divider line
---@param char string|nil Character to repeat
---@param width number|nil Line width
function ui.divider(char, width)
    char = char or "─"
    width = width or 46
    print(C.cyan .. string.rep(char, width) .. C.reset)
end

--- Print key=value info line
---@param key string
---@param value any
function ui.kv(key, value)
    print("  " .. C.gray .. tostring(key) .. ": " .. C.reset .. C.white .. tostring(value) .. C.reset)
end

--- Spinner/progress animation (call in a loop)
---@param frame number Current frame number
---@return string Spinner character
function ui.spinner(frame)
    local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    return C.cyan .. frames[(frame % #frames) + 1] .. C.reset
end

--- Print a box around text
---@param text string
---@param color string|nil Border color
function ui.box(text, color)
    color = color or C.cyan
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    local max_len = 0
    for _, line in ipairs(lines) do
        local len = ui.visible_len(line)
        if len > max_len then max_len = len end
    end
    max_len = max_len + 2 -- padding

    print(color .. "┌" .. string.rep("─", max_len) .. "┐" .. C.reset)
    for _, line in ipairs(lines) do
        print(color .. "│" .. C.reset .. " " .. ui.pad(line, max_len - 2) .. " " .. color .. "│" .. C.reset)
    end
    print(color .. "└" .. string.rep("─", max_len) .. "┘" .. C.reset)
end

--- Clear current line (for live updates)
function ui.clear_line()
    io.write("\r\27[2K")
    io.flush()
end

--- Write text without newline (for live updates)
function ui.write(text)
    io.write(text)
    io.flush()
end

return ui

end

-- ============================================================
-- MODULE: config
-- ============================================================
_MODULES["config"] = function()
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
        launch_stagger_seconds = 60, -- delay between launching multiple packages
        periodic_rejoin_minutes = 20,-- automatic restart interval
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

end

-- ============================================================
-- MODULE: device
-- ============================================================
_MODULES["device"] = function()
-- StarhubRejoiner: Device & package management
-- Root check, package scanning, process status, system info

local shell = require("shell")
local ui = require("ui")

local device = {}

-- Cache device info so we don't re-check every time
local _cache = {
    has_root = nil,
    android_version = nil,
    device_model = nil,
    packages = nil,
}

-- ============================================================
-- ROOT & DEVICE INFO
-- ============================================================

--- Check if root access is available (cached)
---@return boolean
function device.has_root()
    if _cache.has_root == nil then
        _cache.has_root = shell.check_root()
    end
    return _cache.has_root
end

--- Get Android SDK version (cached)
---@return number|nil
function device.android_version()
    if _cache.android_version == nil then
        _cache.android_version = shell.get_android_version() or 0
    end
    return _cache.android_version > 0 and _cache.android_version or nil
end

--- Get device model (cached)
---@return string
function device.model()
    if not _cache.device_model then
        _cache.device_model = shell.get_device_model()
    end
    return _cache.device_model
end

--- Run full device check and print status
---@return boolean all_ok
function device.preflight_check()
    ui.subheader("Device Check")

    -- Root
    local has_root, root_info = shell.check_root()
    _cache.has_root = has_root
    if has_root then
        ui.success("Root access: " .. ui.c("OK", ui.color.green))
    else
        ui.error("Root access: " .. ui.c("FAILED", ui.color.red))
        ui.error("Root is required. Output: " .. tostring(root_info))
        return false
    end

    -- Android version
    local sdk = shell.get_android_version()
    _cache.android_version = sdk or 0
    if sdk then
        ui.success("Android SDK: " .. tostring(sdk))
    else
        ui.warn("Could not detect Android version")
    end

    -- Device model
    local model = shell.get_device_model()
    _cache.device_model = model
    ui.info("Device: " .. model)

    -- SELinux
    local selinux = shell.get_selinux()
    if selinux == "Enforcing" then
        ui.warn("SELinux: Enforcing (setting to Permissive...)")
        if shell.set_selinux_permissive() then
            ui.success("SELinux: Set to Permissive")
        else
            ui.warn("Could not change SELinux mode")
        end
    else
        ui.success("SELinux: " .. selinux)
    end

    -- sqlite3
    local sqlite_code = shell.exec("command -v sqlite3 >/dev/null 2>&1")
    if sqlite_code == 0 then
        ui.success("sqlite3: installed")
    else
        ui.warn("sqlite3: not found (needed for cookie injection)")
    end

    return true
end

-- ============================================================
-- PACKAGE SCANNING
-- ============================================================

--- Scan device for installed Roblox packages
---@param prefix string|nil Package prefix to search (default: "roblox")
---@return table List of package names
function device.scan_packages(prefix)
    prefix = prefix or "roblox"
    local packages = shell.list_packages(prefix)

    -- Also try specific known patterns
    local known_patterns = {
        "com.roblox.client",
        "com.roblox.clientv",
        "com.roblox.clientx",
        "com.roblox.clientz",
    }

    -- Merge: add known packages that were found but not in the list
    local found_set = {}
    for _, p in ipairs(packages) do
        found_set[p] = true
    end

    -- Additional scan for cloned packages with different prefixes
    local _, all_output = shell.su("pm list packages 2>/dev/null | grep -iE 'roblox|rbx' | head -20")
    for line in (all_output or ""):gmatch("[^\n]+") do
        local pkg = line:match("^package:(.+)$")
        if pkg and not found_set[pkg] then
            packages[#packages + 1] = shell.trim(pkg)
            found_set[pkg] = true
        end
    end

    table.sort(packages)
    _cache.packages = packages
    return packages
end

--- Get cached packages or scan if not cached
---@param prefix string|nil
---@return table
function device.get_packages(prefix)
    if _cache.packages then
        return _cache.packages
    end
    return device.scan_packages(prefix)
end

--- Clear the package cache (force re-scan on next call)
function device.clear_package_cache()
    _cache.packages = nil
end

-- ============================================================
-- PACKAGE STATUS
-- ============================================================

--- Package status info
---@class PackageStatus
---@field package string Package name
---@field running boolean Is the app running
---@field pid number|nil Process ID
---@field state string Status string ("ingame", "stopped", "running", "unknown")
---@field username string|nil Detected username

--- Get the status of a single package
---@param package_name string
---@return PackageStatus
function device.get_package_status(package_name)
    local status = {
        package = package_name,
        running = false,
        pid = nil,
        state = "stopped",
        username = nil,
        user_id = nil,
    }

    -- Check if running
    local pid = shell.get_pid(package_name)
    if pid then
        status.running = true
        status.pid = pid
        status.state = "background"

        -- Try to detect if actually ingame by checking activity
        local _, activity_output = shell.su(
            "dumpsys activity activities 2>/dev/null | grep -A2 " ..
            shell.quote(package_name) .. " | head -5"
        )
        if activity_output and activity_output:find("RobloxActivity") then
            status.state = "running"
        end
    end

    -- Try to detect username from logcat/prefs
    local username = device.detect_username(package_name)
    if username then
        status.username = username
    end

    -- Try to detect user ID from logcat/prefs
    local user_id = device.detect_user_id(package_name)
    if user_id then
        status.user_id = user_id
    end

    return status
end

--- Get status for all packages
---@param packages table List of package names
---@return table Array of PackageStatus
function device.get_all_status(packages)
    local statuses = {}
    for _, pkg in ipairs(packages) do
        statuses[#statuses + 1] = device.get_package_status(pkg)
    end
    return statuses
end

-- ============================================================
-- USERNAME / USER ID DETECTION
-- ============================================================

--- Try to detect the logged-in username from logcat/app data
---@param package_name string
---@return string|nil username
function device.detect_username(package_name)
    -- Method 1: Check logcat for username patterns
    local pid = shell.get_pid(package_name)
    if pid then
        local _, logcat = shell.su(
            "logcat -d -t 500 --pid=" .. tostring(pid) .. " 2>/dev/null | " ..
            "grep -iE 'username|displayname|user.?name' | tail -3"
        )

        if logcat and logcat ~= "" then
            -- Try various patterns
            local name = logcat:match('[Uu]sername[=:"%s]+([%w_]+)')
                or logcat:match('[Dd]isplay[Nn]ame[=:"%s]+([%w_]+)')
            if name and name ~= "" and name ~= "null" and name ~= "unknown" then
                return name
            end
        end
    end

    -- Method 2: Check shared preferences
    local _, prefs = shell.su(
        "cat /data/data/" .. shell.quote(package_name) ..
        '/shared_prefs/*.xml 2>/dev/null | grep -iE "username|displayname" | head -3'
    )
    if prefs and prefs ~= "" then
        local name = prefs:match('>([%w_]+)</')
        if name and name ~= "" then
            return name
        end
    end

    return nil
end

--- Try to detect the user ID from logcat/app data
---@param package_name string
---@return string|nil user_id
function device.detect_user_id(package_name)
    local pid = shell.get_pid(package_name)
    if pid then
        local _, logcat = shell.su(
            "logcat -d -t 500 --pid=" .. tostring(pid) .. " 2>/dev/null | " ..
            "grep -iE 'userid|user.?id' | tail -3"
        )

        if logcat and logcat ~= "" then
            local uid = logcat:match('[Uu]ser[_]?[Ii]d[=:"%s]+(%d+)')
            if uid and uid ~= "" and uid ~= "0" then
                return uid
            end
        end
    end
    
    -- Method 2: Check shared preferences
    local _, prefs = shell.su(
        "cat /data/data/" .. shell.quote(package_name) ..
        '/shared_prefs/*.xml 2>/dev/null | grep -iE "userid|user_id" | head -3'
    )
    if prefs and prefs ~= "" then
        local uid = prefs:match('>([%d]+)</')
        if uid and uid ~= "" and uid ~= "0" then
            return uid
        end
    end

    return nil
end

-- ============================================================
-- DISCONNECT DETECTION
-- ============================================================

--- Disconnect detection patterns
device.DISCONNECT_PATTERNS = {
    -- Roblox disconnect codes
    "Sending disconnect with reason: %d+",
    "Disconnection Notification%. Reason: %d+",
    "Lost connection with reason",
    "Connection lost",
    "ID_CONNECTION_LOST",
    "AckTimeout",
    "Session Transition FSM: Error Occurred",
    "SignalRCoreError.*Disconnected",
    "net::ERR_CONNECTION",
    "Kicked from game",
    "You have been kicked",
    "Teleport failed",
}

--- Check logcat for disconnect patterns
---@param package_name string
---@return boolean disconnected
---@return string|nil reason
function device.check_disconnect(package_name)
    local pid = shell.get_pid(package_name)
    if not pid then
        -- Process not running = probably crashed
        return true, "process not running"
    end

    local _, logcat = shell.su(
        "logcat -d -t 100 --pid=" .. tostring(pid) .. " 2>/dev/null"
    )

    if not logcat or logcat == "" then
        return false, nil
    end

    for _, pattern in ipairs(device.DISCONNECT_PATTERNS) do
        local match = logcat:match(pattern)
        if match then
            return true, match
        end
    end

    return false, nil
end

-- ============================================================
-- SYSTEM INFO DISPLAY
-- ============================================================

--- Print system resource usage table
function device.print_system_info()
    local cpu = shell.get_cpu_usage()
    local mem_used, mem_total, mem_percent = shell.get_memory_info()

    ui.table(
        { "Resource", "Usage" },
        {
            { "CPU", cpu .. " used" },
            { "Memory", mem_used .. " / " .. mem_total .. " (" .. mem_percent .. " used)" },
        }
    )
end

--- Print package status table
---@param statuses table Array of PackageStatus
---@param mask_usernames boolean|nil
function device.print_status_table(statuses, mask_usernames)
    local rows = {}
    for _, s in ipairs(statuses) do
        local pkg_short = s.package
        -- Shorten long package names
        if #pkg_short > 22 then
            pkg_short = "..." .. pkg_short:sub(-19)
        end

        local username = s.username or "-"
        if mask_usernames and s.username then
            username = s.username:sub(1, 3) .. string.rep("*", math.max(0, #s.username - 3))
        end

        local user_id = s.user_id or "-"

        rows[#rows + 1] = {
            pkg_short,
            user_id,
            username,
            ui.state_badge(s.state),
        }
    end

    ui.table(
        { "Package", "UserId", "Username", "State" },
        rows,
        { col_widths = { 22, 12, 14, 14 } }
    )
end

return device

end

-- ============================================================
-- MODULE: cookie
-- ============================================================
_MODULES["cookie"] = function()
-- StarhubRejoiner: Cookie injection & management
-- Manual cookie input, injection to Roblox app data, validation

local shell = require("shell")
local ui = require("ui")
local config = require("config")

local cookie = {}

-- ============================================================
-- COOKIE STORAGE PATHS
-- ============================================================

--- Known cookie storage locations in Roblox app data
local COOKIE_PATHS = {
    -- WebView cookie database (Chromium-based)
    { path = "/data/data/%s/app_webview/Default/Cookies", type = "sqlite" },
    { path = "/data/data/%s/app_webview/Cookies", type = "sqlite" },
    -- Legacy WebView
    { path = "/data/data/%s/app_webview/Cookies", type = "sqlite" },
    -- Shared preferences
    { path = "/data/data/%s/shared_prefs/", type = "prefs_dir" },
}

--- Cookie database column info
local COOKIE_DB_INFO = {
    table_name = "cookies",
    domain = ".roblox.com",
    name = ".ROBLOSECURITY",
    path = "/",
    secure = 1,
    httponly = 1,
}

-- ============================================================
-- COOKIE VALIDATION
-- ============================================================

--- Validate a cookie string format
---@param cookie_value string
---@return boolean valid
---@return string|nil error
function cookie.validate_format(cookie_value)
    if not cookie_value or cookie_value == "" then
        return false, "Cookie is empty"
    end
    -- .ROBLOSECURITY cookies typically start with _|WARNING:
    -- But some are just the raw token
    if #cookie_value < 50 then
        return false, "Cookie is too short (expected 100+ characters)"
    end
    -- Check for common issues
    if cookie_value:find("%s") then
        return false, "Cookie contains whitespace"
    end
    return true, nil
end

--- Strip the _|WARNING: prefix if present
---@param cookie_value string
---@return string cleaned_cookie
function cookie.clean(cookie_value)
    -- Remove common prefix
    cookie_value = cookie_value:gsub("^_|WARNING:%-DO%-NOT%-SHARE%-THIS%.%-%-Sharing%-this%-will%-allow%-someone%-to%-log%-in%-as%-you%-and%-to%-steal%-your%-ROBUX%-and%-items%.%-%-", "")
    -- Remove whitespace
    cookie_value = cookie_value:gsub("%s+", "")
    return cookie_value
end

--- Mask a cookie for display
---@param cookie_value string
---@param show_chars number|nil How many chars to show at start/end
---@return string masked
function cookie.mask(cookie_value, show_chars)
    show_chars = show_chars or 8
    if not cookie_value or #cookie_value < show_chars * 2 + 4 then
        return string.rep("*", math.max(8, #(cookie_value or "")))
    end
    return cookie_value:sub(1, show_chars) ..
           string.rep("*", 16) ..
           cookie_value:sub(-show_chars)
end

-- ============================================================
-- COOKIE INJECTION
-- ============================================================

--- Find the cookie database path for a package
---@param package_name string
---@return string|nil db_path
---@return string type ("sqlite" or "prefs_dir")
function cookie.find_db(package_name)
    for _, info in ipairs(COOKIE_PATHS) do
        local path = string.format(info.path, package_name)
        local code = shell.su("test -e " .. shell.quote(path) .. " && echo exists")
        if code == 0 then
            return path, info.type
        end
    end
    return nil, "none"
end

--- Extract cookie directly from Roblox WebView SQLite database
---@param package_name string
---@return string|nil cookie_value
function cookie.extract(package_name)
    local db_path, db_type = cookie.find_db(package_name)
    if db_type == "sqlite" and db_path then
        local sql = string.format("SELECT value FROM %s WHERE name='%s' LIMIT 1;", COOKIE_DB_INFO.table_name, COOKIE_DB_INFO.name)
        local code, output = shell.sqlite(db_path, sql)
        if code == 0 and output and output ~= "" then
            return shell.trim(output)
        end
    end
    return nil
end

--- Inject a cookie into a Roblox package's data
---@param package_name string
---@param cookie_value string The .ROBLOSECURITY value
---@param username string|nil The username of the account, used to bypass Native UI
---@return boolean success
---@return string|nil error_message
function cookie.inject(package_name, cookie_value, username)
    -- Validate
    local valid, err = cookie.validate_format(cookie_value)
    if not valid then
        return false, err
    end

    -- Clean the cookie
    cookie_value = cookie.clean(cookie_value)

    -- Step 1: Force stop the app
    ui.info("Force stopping " .. package_name .. "...")
    shell.am_force_stop(package_name)
    shell.sleep(2)

    local target_pkg_dir = "/data/data/" .. package_name

    -- Step 2: Create Webview Directory Structure
    local webview_dir = target_pkg_dir .. "/app_webview/Default"
    local db_path = webview_dir .. "/Cookies"
    
    local check_db = shell.su("test -e " .. shell.quote(db_path) .. " && echo ok")
    if shell.trim(check_db) ~= "ok" then
        ui.info("Creating fresh cookie database structure...")
        shell.su("mkdir -p " .. shell.quote(webview_dir))
        
        -- Create the schema directly using SQLite
        local create_sql = [[
            CREATE TABLE IF NOT EXISTS cookies (
                creation_utc INTEGER NOT NULL,
                top_frame_site_key TEXT NOT NULL,
                host_key TEXT NOT NULL,
                name TEXT NOT NULL,
                value TEXT NOT NULL,
                encrypted_value BLOB DEFAULT '',
                path TEXT NOT NULL DEFAULT '/',
                expires_utc INTEGER NOT NULL DEFAULT 0,
                is_secure INTEGER NOT NULL DEFAULT 0,
                is_httponly INTEGER NOT NULL DEFAULT 0,
                last_access_utc INTEGER NOT NULL DEFAULT 0,
                has_expires INTEGER NOT NULL DEFAULT 1,
                is_persistent INTEGER NOT NULL DEFAULT 1,
                priority INTEGER NOT NULL DEFAULT 1,
                samesite INTEGER NOT NULL DEFAULT -1,
                source_scheme INTEGER NOT NULL DEFAULT 0,
                source_port INTEGER NOT NULL DEFAULT -1,
                is_same_party INTEGER NOT NULL DEFAULT 0,
                UNIQUE (top_frame_site_key, host_key, name, path)
            );
        ]]
        local code, out = shell.sqlite(db_path, create_sql)
        if code ~= 0 then
            return false, "Failed to create DB schema: " .. tostring(out)
        end
    end

    -- Step 3: Write prefs.xml to update the CLI status table username
    if username then
        ui.info("Writing prefs.xml for " .. username .. "...")
        shell.su("mkdir -p " .. shell.quote(target_pkg_dir .. "/shared_prefs"))
        
        local prefs_content = string.format([[
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="username">%s</string>
    <string name="displayName">%s</string>
</map>
]], username, username)
        
        local temp_xml = "/data/local/tmp/prefs_" .. package_name .. ".xml"
        local code_echo = shell.su("echo " .. shell.quote(prefs_content) .. " > " .. temp_xml)
        if code_echo == 0 then
            shell.su("mv " .. temp_xml .. " " .. shell.quote(target_pkg_dir .. "/shared_prefs/prefs.xml"))
        end
    end

    -- Step 4: Inject SQLite database with the NEW cookie (uses WebKit timestamps)
    ui.info("Injecting cookie into database...")
    local result, err_msg = cookie.inject_sqlite(package_name, db_path, cookie_value)
    
    -- Step 5: Fix permissions
    cookie.fix_permissions(package_name, target_pkg_dir .. "/shared_prefs")
    cookie.fix_permissions(package_name, target_pkg_dir .. "/app_webview")
    
    if result then
        ui.success("Cookie injected successfully!")
        return true, nil
    else
        return false, err_msg
    end
end

--- Inject cookie via SQLite database
---@param package_name string
---@param db_path string
---@param cookie_value string
---@return boolean success
---@return string|nil error
function cookie.inject_sqlite(package_name, db_path, cookie_value)
    ui.info("Injecting via SQLite: " .. db_path)

    local temp_db = "/data/local/tmp/Cookies_" .. package_name .. ".db"
    shell.su("cat " .. shell.quote(db_path) .. " > " .. shell.quote(temp_db))

    -- Try UPDATE first (Schema agnostic)
    local update_sql = "UPDATE cookies SET value=" .. shell.quote(cookie_value) .. " WHERE name='.ROBLOSECURITY';"
    shell.sqlite(temp_db, update_sql)
    
    -- Check if it was updated
    local _, check_out = shell.sqlite(temp_db, "SELECT value FROM cookies WHERE name='.ROBLOSECURITY';")
    if not check_out or shell.trim(check_out) == "" then
        -- We must INSERT.
        local info = COOKIE_DB_INFO
        
        -- WebKit epoch is 1601-01-01, Unix is 1970-01-01. Difference is 11644473600 seconds.
        -- WebKit stores timestamps in MICROSECONDS.
        local current_unix = os.time()
        local expires_unix = current_unix + (365 * 24 * 3600)
        local creation_webkit = string.format("%.0f", (current_unix + 11644473600) * 1000000)
        local expires_webkit = string.format("%.0f", (expires_unix + 11644473600) * 1000000)
        
        -- Try Chromium schema with WebKit timestamps
        local insert_sql = string.format(
            "INSERT INTO cookies (creation_utc, top_frame_site_key, host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party) VALUES (%s, '', '%s', '%s', '%s', '', '%s', %s, 1, 1, %s, 1, 1, 1, -1, 1, -1, 0);",
            creation_webkit, info.domain, info.name, cookie_value, info.path, expires_webkit, creation_webkit
        )
        local c2, out2 = shell.sqlite(temp_db, insert_sql)
        if c2 ~= 0 then
            -- Fallback to slightly older Chromium schema
            insert_sql = string.format(
                "INSERT INTO cookies (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent) VALUES (%s, '%s', '%s', '%s', '%s', %s, 1, 1, %s, 1, 1);",
                creation_webkit, info.domain, info.name, cookie_value, info.path, expires_webkit, creation_webkit
            )
            local c3, out3 = shell.sqlite(temp_db, insert_sql)
            if c3 ~= 0 then
                -- Fallback to very old Chromium schema
                insert_sql = string.format(
                    "INSERT INTO cookies (creation_utc, host_key, name, value, path, expires_utc, secure, httponly, last_access_utc, has_expires, persistent) VALUES (%s, '%s', '%s', '%s', '%s', %s, 1, 1, %s, 1, 1);",
                    creation_webkit, info.domain, info.name, cookie_value, info.path, expires_webkit, creation_webkit
                )
                shell.sqlite(temp_db, insert_sql)
            end
        end
    end

    -- Move temp_db back to db_path using cat to preserve SELinux/Permissions
    shell.su("cat " .. shell.quote(temp_db) .. " > " .. shell.quote(db_path))
    shell.su("rm -f " .. shell.quote(temp_db))

    -- Fix permissions just in case
    cookie.fix_permissions(package_name, db_path)
    ui.success("Cookie injected successfully!")
    return true, nil
end

--- Fix file permissions after injection
---@param package_name string
---@param db_path string
function cookie.fix_permissions(package_name, db_path)
    -- Get the app's UID
    local _, uid_output = shell.su(
        "stat -c '%u' /data/data/" .. shell.quote(package_name) .. " 2>/dev/null"
    )
    local uid = shell.trim(uid_output)

    if uid ~= "" and uid ~= "0" then
        shell.su("chown " .. uid .. ":" .. uid .. " " .. shell.quote(db_path) .. " 2>/dev/null")
        shell.su("chown -R " .. uid .. ":" .. uid .. " " ..
                 shell.quote(db_path:match("(.+)/[^/]+$") or db_path) .. " 2>/dev/null")
    end
    shell.su("chmod 660 " .. shell.quote(db_path) .. " 2>/dev/null")
end

-- ============================================================
-- COOKIE MANAGEMENT UI
-- ============================================================

--- Interactive cookie injection menu
---@param cfg_data table Config data
---@param packages table Available packages
---@return table cfg_data (modified)
function cookie.injection_menu(cfg_data, packages)
    while true do
        ui.header("Cookie Injection")

        if #packages == 0 then
            ui.error("No Roblox packages found on device!")
            ui.info("Press Enter to go back...")
            io.read("*l")
            return cfg_data
        end

        -- Show available packages
        ui.info("Available packages:")
        local masked_display = config.get(cfg_data, "cookie.masked_display", true)
        local menu_items = {}
        for i, pkg in ipairs(packages) do
            local existing = config.get_cookie(cfg_data, pkg)
            if not existing then
                existing = cookie.extract(pkg)
                if existing then
                    config.set_cookie(cfg_data, pkg, existing)
                    config.save(cfg_data)
                end
            end
            local status
            if existing then
                local disp = masked_display and cookie.mask(existing) or existing
                status = ui.c(disp, ui.color.green)
            else
                status = ui.c("no cookie", ui.color.gray)
            end
            menu_items[#menu_items + 1] = {
                key = tostring(i),
                label = pkg .. "  " .. status,
            }
        end
        menu_items[#menu_items + 1] = { separator = true }
        menu_items[#menu_items + 1] = { key = "0", label = "Back", color = ui.color.gray }

        local choice = ui.menu(menu_items, "Select package")
        local idx = tonumber(choice)

        if not idx or idx == 0 or idx > #packages then
            return cfg_data
        end

        local target_pkg = packages[idx]

        while true do
            local existing = config.get_cookie(cfg_data, target_pkg)
            if not existing then
                existing = cookie.extract(target_pkg)
                if existing then
                    -- Save extracted cookie to config
                    config.set_cookie(cfg_data, target_pkg, existing)
                    config.save(cfg_data)
                end
            end
            
            print("")
            ui.info("Target: " .. ui.c(target_pkg, ui.color.cyan))
            if existing then
                local disp = masked_display and cookie.mask(existing) or existing
                ui.kv("Current Cookie", disp)
            else
                ui.kv("Current Cookie", ui.c("No cookie stored", ui.color.gray))
            end
            print("")

            -- Ask for action
            local action = ui.menu({
                { key = "1", label = existing and "Replace current cookie" or "Inject new cookie" },
                { key = "2", label = "Verify a cookie manually (Roblox API)" },
                { key = "3", label = "Remove cookie", color = ui.color.red },
                { key = "0", label = "Back", color = ui.color.gray },
            }, "Select action")

            if not action or action == "0" then
                break -- Go back to package list
            end

            if action == "1" then
                -- Inject new cookie
                print("")
                ui.info("Paste your .ROBLOSECURITY cookie below:")
                ui.dim("(The cookie starting with _|WARNING: or just the token)")
                print("")
                io.write(ui.color.cyan .. "> " .. ui.color.reset)
                io.flush()
                local cookie_input = io.read("*l")

                if not cookie_input or cookie_input == "" then
                    ui.warn("No cookie provided")
                else
                    ui.info("Verifying cookie before injection...")
                    local valid, name_or_err = shell.verify_cookie(cookie.clean(cookie_input))
                    if valid then
                        ui.success("Cookie is valid! Account: " .. ui.c(name_or_err, ui.color.green))
                    else
                        ui.warn("Cookie verification failed: " .. name_or_err)
                        if not ui.confirm("Do you still want to inject this cookie?", false) then
                            -- Skip injection
                            goto continue_action
                        end
                    end
                    
                    local ok, inject_err = cookie.inject(target_pkg, cookie_input, valid and name_or_err or nil)
                    if ok then
                        config.set_cookie(cfg_data, target_pkg, cookie.clean(cookie_input))
                        config.save(cfg_data)
                        ui.success("Cookie saved to config and injected!")
                    else
                        ui.error("Injection failed: " .. tostring(inject_err))
                        if ui.confirm("Save cookie to config anyway?", true) then
                            config.set_cookie(cfg_data, target_pkg, cookie.clean(cookie_input))
                            config.save(cfg_data)
                            ui.info("Cookie saved to config")
                        end
                    end
                end

            elseif action == "2" then
                print("")
                ui.info("Paste the cookie you want to verify:")
                io.write(ui.color.cyan .. "> " .. ui.color.reset)
                io.flush()
                local test_cookie = io.read("*l")
                
                if test_cookie and test_cookie ~= "" then
                    ui.info("Verifying cookie with Roblox API...")
                    local valid, name_or_err = shell.verify_cookie(cookie.clean(test_cookie))
                    if valid then
                        ui.success("Cookie is VALID!")
                        ui.kv("Account Name", ui.c(name_or_err, ui.color.green))
                    else
                        ui.error("Cookie is INVALID or EXPIRED: " .. name_or_err)
                    end
                else
                    ui.warn("No cookie provided")
                end

            elseif action == "3" then
                if existing and ui.confirm("Remove cookie for " .. target_pkg .. "?", false) then
                    config.set_cookie(cfg_data, target_pkg, nil)
                    config.save(cfg_data)
                    -- Also wipe it from the app data
                    ui.info("Wiping cookie from app data...")
                    shell.am_force_stop(target_pkg)
                    shell.su("rm -f /data/data/" .. shell.quote(target_pkg) .. "/app_webview/Default/Cookies")
                    shell.su("rm -f /data/data/" .. shell.quote(target_pkg) .. "/app_webview/Cookies")
                    shell.su("rm -f /data/data/" .. shell.quote(target_pkg) .. "/shared_prefs/prefs.xml")
                    ui.success("Cookie removed completely!")
                end
            end

            ::continue_action::
            print("")
            ui.info("Press Enter to continue...")
            io.read("*l")
        end
    end
end

return cookie

end

-- ============================================================
-- MODULE: grid
-- ============================================================
_MODULES["grid"] = function()
-- StarhubRejoiner: Auto Grid Module
-- Handles resizing and organizing Roblox packages in a grid

local shell = require("shell")
local ui = require("ui")
local config = require("config")

local grid = {}

--- Parse 'wm size' output
---@return number|nil width
---@return number|nil height
function grid.get_screen_size()
    local _, out = shell.su("wm size 2>/dev/null")
    if out then
        local w, h = out:match("(%d+)x(%d+)")
        if w and h then
            return tonumber(w), tonumber(h)
        end
    end
    
    -- Fallback
    local _, d_out = shell.su("dumpsys window displays 2>/dev/null")
    if d_out then
        local w, h = d_out:match("cur=(%d+)x(%d+)")
        if w and h then
            return tonumber(w), tonumber(h)
        end
    end
    
    return nil, nil
end

--- Apply grid layout to a list of packages
---@param cfg_data table
---@param packages table List of package names
---@param rows number
---@param cols number
function grid.apply(cfg_data, packages, rows, cols)
    if #packages == 0 then
        ui.error("No packages to arrange")
        return
    end

    -- Enable freeform support for Android 10+
    shell.su("settings put global enable_freeform_support 1")
    shell.su("settings put global force_resizable_activities 1")

    local w, h = grid.get_screen_size()
    if not w or not h then
        ui.error("Could not determine screen resolution")
        return
    end

    local cell_w = math.floor(w / cols)
    local cell_h = math.floor(h / rows)

    ui.info(string.format("Screen: %dx%d | Cell: %dx%d", w, h, cell_w, cell_h))

    -- Force stop all target packages first
    ui.info("Stopping selected packages before arranging...")
    for _, pkg in ipairs(packages) do
        shell.am_force_stop(pkg)
    end
    shell.sleep(1)

    local stagger = tonumber(config.get(cfg_data, "monitor.launch_stagger_seconds", 60))

    for i, pkg in ipairs(packages) do
        local uri = config.get_launch_uri(cfg_data, pkg)
        if not uri then
            ui.warn("No Server Target / URI configured for " .. pkg)
        else
            -- 0-indexed for math
            local idx = i - 1 
            local r = math.floor(idx / cols)
            local c = idx % cols

            if r >= rows then
                ui.warn(pkg .. " exceeds grid size, skipping...")
            else
                local left = c * cell_w
                local top = r * cell_h
                local right = left + cell_w
                local bottom = top + cell_h

                -- Launch activity in freeform mode with bounds
                ui.log(string.format("Launching %s at [%d,%d,%d,%d]...", pkg, left, top, right, bottom))
                local cmd = string.format("am start -n %s -a android.intent.action.VIEW --windowingMode 5 --bounds %d,%d,%d,%d -d %s",
                                          shell.quote(pkg .. "/com.roblox.client.Activity"), 
                                          left, top, right, bottom, shell.quote(uri))
                shell.su(cmd)
                
                if i < #packages and stagger > 0 then
                    ui.info("Waiting " .. stagger .. "s before next launch...")
                    shell.sleep(stagger)
                end
            end
        end
    end
    ui.success("Grid applied successfully!")
end

--- Interactive menu for Auto Grid
---@param cfg_data table
---@param packages table
function grid.menu(cfg_data, packages)
    ui.header("Auto Grid Layout")
    
    if #packages == 0 then
        ui.error("No Roblox packages found on device!")
        shell.sleep(2)
        return
    end

    local target_choice = ui.menu({
        { key = "1", label = "All Monitored Packages (" .. #packages .. ")" },
        { key = "2", label = "Select Specific Package" },
        { key = "0", label = "Cancel", color = ui.color.gray },
    }, "Target Package for Grid")
    
    local target_packages = {}
    if target_choice == "1" then
        target_packages = packages
    elseif target_choice == "2" then
        local options = {}
        for i, p in ipairs(packages) do
            table.insert(options, { key = tostring(i), label = p })
        end
        table.insert(options, { key = "0", label = "Cancel", color = ui.color.gray })
        local sel = ui.menu(options, "Select Package")
        local sel_num = tonumber(sel)
        if sel_num and sel_num > 0 and sel_num <= #packages then
            target_packages = { packages[sel_num] }
        else
            return
        end
    else
        return
    end

    local rows = ui.input_number("Enter number of rows", 2, 1, 10)
    local cols = ui.input_number("Enter number of columns", 2, 1, 10)

    if rows and cols then
        grid.apply(cfg_data, target_packages, rows, cols)
        shell.sleep(2)
    end
end

return grid

end

-- ============================================================
-- MODULE: monitor
-- ============================================================
_MODULES["monitor"] = function()
-- StarhubRejoiner: Auto Rejoin & Process Monitoring Engine
-- Core monitoring loop with disconnect detection, auto rejoin, and live status display

local shell = require("shell")
local ui = require("ui")
local config = require("config")
local device = require("device")

local monitor = {}

-- ============================================================
-- MONITOR STATE
-- ============================================================

---@class MonitorState
---@field running boolean Is monitor actively running
---@field paused boolean Is auto-rejoin paused
---@field packages table Package states
---@field start_time number Monitor start timestamp
---@field total_rejoins number Total rejoin count
---@field hotkeys_enabled boolean Are hotkeys active
---@field stty_state string|nil Original terminal state

local function new_state()
    return {
        running = false,
        paused = false,
        packages = {},          -- { [pkg] = { state, last_check, rejoin_count, grace_until, ... } }
        start_time = 0,
        total_rejoins = 0,
        hotkeys_enabled = false,
        stty_state = nil,
    }
end

-- ============================================================
-- HOTKEY CONTROL
-- ============================================================

--- Setup terminal for non-blocking key reading
---@return string|nil stty_state Original terminal state for restoration
local function setup_hotkeys()
    local code, stty = shell.exec("stty -g < /dev/tty 2>/dev/null")
    if code ~= 0 or shell.trim(stty) == "" then
        return nil
    end
    shell.exec("stty -icanon -echo min 0 time 0 susp undef < /dev/tty 2>/dev/null || true")
    return shell.trim(stty)
end

--- Restore terminal to original state
---@param stty_state string
local function restore_hotkeys(stty_state)
    if stty_state and stty_state ~= "" then
        shell.exec("stty " .. shell.quote(stty_state) .. " < /dev/tty 2>/dev/null || true")
    end
end

--- Poll for a control key press
---@return string|nil command "quit"|"stop"|"pause"|nil
local function poll_key()
    local ok, key = pcall(function()
        return io.stdin:read(1)
    end)
    if not ok then return nil end
    key = tostring(key or "")
    if key == "" then return nil end
    local lower = key:lower()
    if lower == "q" then return "quit" end
    if lower == "s" or key == string.char(26) then return "stop" end
    if lower == "p" then return "pause" end
    return nil
end

--- Sleep with hotkey polling
---@param seconds number
---@return string|nil command if a key was pressed
local function sleep_with_control(seconds)
    local total = math.max(0, tonumber(seconds) or 0)
    if total <= 0 then return poll_key() end
    local step = 0.3
    local elapsed = 0
    while elapsed < total do
        local cmd = poll_key()
        if cmd then return cmd end
        local wait = math.min(step, total - elapsed)
        shell.sleep(wait)
        elapsed = elapsed + wait
    end
    return poll_key()
end

-- ============================================================
-- REJOIN LOGIC
-- ============================================================

--- Perform a rejoin for a specific package
---@param pkg_name string
---@param cfg_data table Config data
---@param state MonitorState
---@return boolean success
---@return string|nil error
local function perform_rejoin(pkg_name, cfg_data, state)
    local pkg_state = state.packages[pkg_name]
    if not pkg_state then return false, "unknown package" end

    local mon_cfg = cfg_data.monitor or {}
    local max_attempts = mon_cfg.max_rejoin_attempts or 5

    -- Check rejoin attempt limit
    if pkg_state.rejoin_count >= max_attempts then
        ui.log(ui.c("MAX REJOIN ATTEMPTS reached for ", ui.color.red) .. pkg_name, ui.color.red)
        pkg_state.state = "stopped"
        return false, "max rejoin attempts reached"
    end

    pkg_state.state = "rejoining"
    pkg_state.rejoin_count = (pkg_state.rejoin_count or 0) + 1
    state.total_rejoins = state.total_rejoins + 1

    ui.log("Rejoining " .. ui.c(pkg_name, ui.color.cyan) ..
           " (attempt " .. pkg_state.rejoin_count .. "/" .. max_attempts .. ")", ui.color.yellow)

    -- Step 1: Force stop
    ui.log("  Force stopping...", ui.color.gray)
    shell.am_force_stop(pkg_name)
    shell.sleep(1)

    -- Step 2: Clear cache (optional)
    if mon_cfg.clear_cache_on_rejoin ~= false then
        ui.log("  Clearing cache...", ui.color.gray)
        shell.clear_cache(pkg_name)
    end

    -- Step 3: Clear logcat
    shell.logcat_clear()
    shell.sleep(1)

    -- Step 4: Launch with server URI
    local uri, uri_err = config.get_launch_uri(cfg_data, pkg_name)
    if not uri then
        ui.log("  " .. ui.c("Cannot rejoin: " .. tostring(uri_err), ui.color.red))
        pkg_state.state = "stopped"
        return false, uri_err
    end

    ui.log("  Launching...", ui.color.gray)
    -- Apply launch stagger here
    local stagger = tonumber(cfg_data.monitor and cfg_data.monitor.launch_stagger_seconds or 8)
    if stagger > 0 then shell.sleep(stagger) end

    local code, output = shell.am_start(pkg_name, uri)
    if code ~= 0 then
        ui.log("  " .. ui.c("Launch failed: " .. tostring(output), ui.color.red))
        pkg_state.state = "stopped"
        return false, "launch failed: " .. tostring(output)
    end

    -- Step 5: Set grace period
    local grace = mon_cfg.startup_grace_seconds or 45
    pkg_state.grace_until = os.time() + grace
    pkg_state.state = "launching"
    pkg_state.last_launch = os.time()
    
    return true, nil
end

-- ============================================================
-- LIVE STATUS DISPLAY
-- ============================================================

--- Print the live monitoring dashboard
---@param state MonitorState
---@param cfg_data table
---@param packages table
local function print_dashboard(state, cfg_data, packages)
    shell.clear()
    ui.banner()

    -- System info
    if config.get(cfg_data, "display.show_system_info", true) then
        device.print_system_info()
    end

    -- Package status table
    local statuses = {}
    for _, pkg in ipairs(packages) do
        local pkg_state = state.packages[pkg] or {}
        statuses[#statuses + 1] = {
            package = pkg,
            running = pkg_state.state == "ingame" or pkg_state.state == "running" or pkg_state.state == "launching",
            pid = pkg_state.pid,
            state = pkg_state.state or "unknown",
            username = pkg_state.username,
            user_id = pkg_state.user_id,
        }
    end

    local mask = config.get(cfg_data, "display.mask_usernames", false)
    device.print_status_table(statuses, mask)

    -- Monitor stats
    local uptime = os.time() - state.start_time
    local hours = math.floor(uptime / 3600)
    local mins = math.floor((uptime % 3600) / 60)
    local secs = uptime % 60

    print("")
    ui.kv("Uptime", string.format("%02d:%02d:%02d", hours, mins, secs))
    ui.kv("Total Rejoins", tostring(state.total_rejoins))
    if state.paused then
        ui.kv("Status", ui.c("PAUSED", ui.color.yellow))
    else
        ui.kv("Status", ui.c("MONITORING", ui.color.green))
    end

    print("")
    ui.dim("  Hotkeys: [q]uit  [s]top  [p]ause/resume")
    ui.divider("═")
end

-- ============================================================
-- MAIN MONITOR LOOP
-- ============================================================

--- Start the monitoring loop
---@param cfg_data table Config data
---@param packages table Packages to monitor
---@return string exit_reason "quit"|"stop"|"error"
function monitor.start(cfg_data, packages)
    if #packages == 0 then
        ui.error("No packages to monitor!")
        return "error"
    end

    local mon_cfg = cfg_data.monitor or {}
    local check_interval = mon_cfg.check_interval or 10

    -- Initialize state
    local state = new_state()
    state.running = true
    state.start_time = os.time()

    -- Initialize package states
    for _, pkg in ipairs(packages) do
        state.packages[pkg] = {
            state = "unknown",
            pid = nil,
            username = nil,
            user_id = nil,
            rejoin_count = 0,
            grace_until = 0,
            last_check = 0,
            last_rejoin = 0,
        }
    end

    -- Setup hotkeys
    state.stty_state = setup_hotkeys()
    state.hotkeys_enabled = state.stty_state ~= nil

    ui.info("Monitor starting...")
    ui.info("Monitoring " .. #packages .. " package(s)")
    ui.info("Check interval: " .. check_interval .. "s")
    print("")

    -- Auto-launch non-running packages on start
    if mon_cfg.auto_launch_on_start ~= false then
        ui.info("Checking for packages to launch...")
        local stagger = mon_cfg.launch_stagger_seconds or 8
        local launched = 0

        for _, pkg in ipairs(packages) do
            if not shell.is_running(pkg) then
                local uri = config.get_launch_uri(cfg_data, pkg)
                if uri then
                    if launched > 0 then
                        ui.info("Waiting " .. stagger .. "s before next launch...")
                        local cmd = sleep_with_control(stagger)
                        if cmd == "quit" then
                            restore_hotkeys(state.stty_state)
                            return "quit"
                        end
                    end
                    ui.log("Launching " .. ui.c(pkg, ui.color.cyan) .. "...")
                    shell.am_start(pkg, uri)
                    state.packages[pkg].state = "launching"
                    state.packages[pkg].grace_until = os.time() + (mon_cfg.startup_grace_seconds or 45)
                    state.packages[pkg].last_launch = os.time()
                    launched = launched + 1
                end
            else
                state.packages[pkg].state = "running"
                state.packages[pkg].pid = shell.get_pid(pkg)
                if not state.packages[pkg].last_launch then
                    state.packages[pkg].last_launch = os.time()
                end
            end
        end

        if launched > 0 then
            ui.success("Launched " .. launched .. " package(s)")
            ui.info("Waiting for grace period...")
        end
    end

    -- Main monitoring loop
    local cycle = 0
    while state.running do
        cycle = cycle + 1

        -- Update status for each package
        for _, pkg in ipairs(packages) do
            local pkg_state = state.packages[pkg]
            local now = os.time()

            -- Check if in grace period
            if pkg_state.grace_until > 0 and now < pkg_state.grace_until then
                pkg_state.state = "launching"
            else
                if pkg_state.grace_until > 0 and now >= pkg_state.grace_until then
                    pkg_state.grace_until = 0
                end

                -- Check if process is running
                local pid = shell.get_pid(pkg)
                pkg_state.pid = pid

                if not pid then
                    -- Process not running
                    if pkg_state.state ~= "stopped" and pkg_state.state ~= "rejoining" then
                        ui.log(ui.c(pkg, ui.color.cyan) .. " " ..
                               ui.c("process died!", ui.color.red))

                        if not state.paused then
                            perform_rejoin(pkg, cfg_data, state)
                        else
                            pkg_state.state = "stopped"
                        end
                    end
                else
                    -- Process is running
                    pkg_state.state = "background"

                    -- Check activity to determine if ingame
                    local _, activity = shell.su(
                        "dumpsys activity activities 2>/dev/null | grep " ..
                        shell.quote(pkg) .. " | head -3"
                    )
                    if activity and (activity:find("RobloxActivity") or activity:find("visible=true")) then
                        pkg_state.state = "running"
                        -- Reset rejoin counter when successfully ingame
                        pkg_state.rejoin_count = 0
                    end

                    -- Check for disconnect patterns
                    local disconnected, reason = device.check_disconnect(pkg)
                    if disconnected then
                        ui.log(ui.c(pkg, ui.color.cyan) .. " " ..
                               ui.c("disconnected: " .. tostring(reason), ui.color.yellow))

                        if not state.paused then
                            perform_rejoin(pkg, cfg_data, state)
                        else
                            pkg_state.state = "disconnected"
                        end
                    end

                    -- Check for periodic rejoin
                    local periodic_mins = tonumber(cfg_data.monitor and cfg_data.monitor.periodic_rejoin_minutes or 0)
                    if periodic_mins > 0 and pkg_state.state == "running" and pkg_state.last_launch then
                        local elapsed_mins = (now - pkg_state.last_launch) / 60
                        if elapsed_mins >= periodic_mins then
                            ui.log(ui.c(pkg, ui.color.cyan) .. " " ..
                                   ui.c(string.format("periodic rejoin (%d min elapsed)", periodic_mins), ui.color.yellow))
                            
                            if not state.paused then
                                perform_rejoin(pkg, cfg_data, state)
                            end
                        end
                    end

                    -- Update username/userid periodically
                    if cycle % 5 == 0 or not pkg_state.username then
                        local username = device.detect_username(pkg)
                        if username then pkg_state.username = username end
                        local user_id = device.detect_user_id(pkg)
                        if user_id then pkg_state.user_id = user_id end
                    end
                end
            end

            pkg_state.last_check = os.time()
        end

        -- Display dashboard
        local display_mode = config.get(cfg_data, "display.ui_mode", "live")
        if display_mode == "live" then
            print_dashboard(state, cfg_data, packages)
        else
            -- Compact mode: just log changes
            local time_str = os.date("%H:%M:%S")
            ui.clear_line()
            local status_parts = {}
            for _, pkg in ipairs(packages) do
                local ps = state.packages[pkg]
                local short = pkg:match("([^%.]+)$") or pkg
                status_parts[#status_parts + 1] = short .. ":" .. (ps.state or "?")
            end
            ui.write(ui.color.gray .. "[" .. time_str .. "] " .. ui.color.reset ..
                     table.concat(status_parts, " | "))
        end

        -- Sleep with hotkey polling
        local command = sleep_with_control(check_interval)
        if command then
            if command == "quit" then
                state.running = false
                ui.log("Quitting monitor...", ui.color.yellow)
                break
            elseif command == "stop" then
                state.running = false
                ui.log("Stopping monitor (returning to menu)...", ui.color.yellow)
                restore_hotkeys(state.stty_state)
                return "stop"
            elseif command == "pause" then
                state.paused = not state.paused
                if state.paused then
                    ui.log(ui.c("Auto-rejoin PAUSED", ui.color.yellow))
                else
                    ui.log(ui.c("Auto-rejoin RESUMED", ui.color.green))
                end
            end
        end
    end

    -- Cleanup
    restore_hotkeys(state.stty_state)
    return "quit"
end

-- ============================================================
-- QUICK STATUS (non-interactive)
-- ============================================================

--- Print status of all packages and exit
---@param cfg_data table
---@param packages table
function monitor.print_status(cfg_data, packages)
    ui.banner()
    print("")

    if config.get(cfg_data, "display.show_system_info", true) then
        device.print_system_info()
    end

    local statuses = device.get_all_status(packages)
    local mask = config.get(cfg_data, "display.mask_usernames", false)
    device.print_status_table(statuses, mask)
end

-- ============================================================
-- AUTO REJOIN MENU (interactive)
-- ============================================================

--- Interactive auto-rejoin setup and start menu
---@param cfg_data table
---@param packages table
---@return table cfg_data
function monitor.menu(cfg_data, packages)
    ui.header("Auto Rejoin")

    if #packages == 0 then
        ui.error("No Roblox packages found!")
        ui.info("Press Enter to go back...")
        io.read("*l")
        return cfg_data
    end

    -- Check server config
    local server = cfg_data.server or {}
    local has_server = false
    if server.type == "ps_link" and server.ps_link and server.ps_link ~= "" then
        has_server = true
    elseif server.type == "place_id" and server.place_id and server.place_id ~= "" then
        has_server = true
    elseif server.type == "job_id" and server.job_id and server.job_id ~= "" and
           server.place_id and server.place_id ~= "" then
        has_server = true
    end

    -- Show current config
    ui.subheader("Current Configuration")
    ui.kv("Server Type", server.type or "not set")
    if server.game_name and server.game_name ~= "" then
        ui.kv("Game Name", ui.c(server.game_name, ui.color.green))
    end
    if server.type == "ps_link" then
        ui.kv("PS Link", server.ps_link ~= "" and server.ps_link or ui.c("NOT SET", ui.color.red))
    elseif server.type == "place_id" then
        ui.kv("Place ID", server.place_id ~= "" and server.place_id or ui.c("NOT SET", ui.color.red))
    elseif server.type == "job_id" then
        ui.kv("Place ID", server.place_id or ui.c("NOT SET", ui.color.red))
        ui.kv("Job ID", server.job_id ~= "" and server.job_id or ui.c("NOT SET", ui.color.red))
    end
    ui.kv("Check Interval", tostring(cfg_data.monitor and cfg_data.monitor.check_interval or 10) .. "s")
    ui.kv("Packages", tostring(#packages))

    if not has_server then
        print("")
        ui.warn("Server target not configured! Set it up first.")
    end

    local choice = ui.menu({
        { key = "1", label = "Start Monitor" .. (has_server and "" or " (configure server first!)"),
          color = has_server and ui.color.green or ui.color.gray },
        { key = "2", label = "Configure Server Target" },
        { key = "3", label = "Configure Monitor Settings" },
        { key = "0", label = "Back", color = ui.color.gray },
    })

    if choice == "1" then
        if not has_server then
            ui.error("Please configure server target first!")
            shell.sleep(2)
            return cfg_data
        end
        
        -- Package Target Selection
        local target_choice = ui.menu({
            { key = "1", label = "All Monitored Packages (" .. #packages .. ")" },
            { key = "2", label = "Select Specific Package" },
            { key = "0", label = "Cancel", color = ui.color.gray },
        }, "Target Package")
        
        local target_packages = {}
        if target_choice == "1" then
            target_packages = packages
        elseif target_choice == "2" then
            local options = {}
            for i, p in ipairs(packages) do
                table.insert(options, { key = tostring(i), label = p })
            end
            table.insert(options, { key = "0", label = "Cancel", color = ui.color.gray })
            local sel = ui.menu(options, "Select Package")
            local sel_num = tonumber(sel)
            if sel_num and sel_num > 0 and sel_num <= #packages then
                target_packages = { packages[sel_num] }
            else
                return cfg_data
            end
        else
            return cfg_data
        end

        -- Start monitoring
        print("")
        ui.info("Starting monitor for " .. #target_packages .. " package(s)...")
        shell.sleep(1)
        monitor.start(cfg_data, target_packages)

    elseif choice == "2" then
        cfg_data = monitor.configure_server(cfg_data)

    elseif choice == "3" then
        cfg_data = monitor.configure_monitor(cfg_data)
    end

    return cfg_data
end

--- Configure server target
---@param cfg_data table
---@return table cfg_data
function monitor.configure_server(cfg_data)
    ui.header("Configure Server Target")

    local choice = ui.menu({
        { key = "1", label = "Private Server Link (PS Link)" },
        { key = "2", label = "Place ID" },
        { key = "3", label = "Place ID + Job ID" },
        { key = "0", label = "Back", color = ui.color.gray },
    }, "Select server type")

    local function detect_and_save_name(place_id)
        if place_id and place_id ~= "" then
            ui.info("Detecting game name...")
            local name = shell.fetch_game_name(place_id)
            if name then
                config.set(cfg_data, "server.game_name", name)
                ui.success("Detected Game: " .. name)
            else
                config.set(cfg_data, "server.game_name", "")
            end
        end
    end

    if choice == "1" then
        config.set(cfg_data, "server.type", "ps_link")
        local link = ui.input("Enter PS Link URL")
        if link and link ~= "" then
            config.set(cfg_data, "server.ps_link", link)
            local place_id = link:match("games/(%d+)/")
            detect_and_save_name(place_id)
            config.save(cfg_data)
            ui.success("PS Link saved!")
        end

    elseif choice == "2" then
        config.set(cfg_data, "server.type", "place_id")
        local pid = ui.input("Enter Place ID")
        if pid and pid ~= "" then
            config.set(cfg_data, "server.place_id", pid)
            detect_and_save_name(pid)
            config.save(cfg_data)
            ui.success("Place ID saved!")
        end

    elseif choice == "3" then
        config.set(cfg_data, "server.type", "job_id")
        local pid = ui.input("Enter Place ID")
        local jid = ui.input("Enter Job ID (Game Instance ID)")
        if pid and pid ~= "" then
            config.set(cfg_data, "server.place_id", pid)
            detect_and_save_name(pid)
        end
        if jid and jid ~= "" then
            config.set(cfg_data, "server.job_id", jid)
        end
        config.save(cfg_data)
        ui.success("Place ID + Job ID saved!")
    end

    return cfg_data
end

--- Configure monitor settings
---@param cfg_data table
---@return table cfg_data
function monitor.configure_monitor(cfg_data)
    ui.header("Monitor Settings")

    local mon = cfg_data.monitor or {}

    local interval = ui.input_number("Check interval (seconds)", mon.check_interval or 10, 3, 120)
    config.set(cfg_data, "monitor.check_interval", interval)

    local periodic = ui.input_number("Periodic Rejoin Interval (minutes, 0 to disable)", mon.periodic_rejoin_minutes or 0, 0, 1440)
    config.set(cfg_data, "monitor.periodic_rejoin_minutes", periodic)

    local stagger = ui.input_number("Package Join Delay (seconds)", mon.launch_stagger_seconds or 8, 0, 60)
    config.set(cfg_data, "monitor.launch_stagger_seconds", stagger)

    local max_rejoin = ui.input_number("Max rejoin attempts", mon.max_rejoin_attempts or 5, 1, 50)
    config.set(cfg_data, "monitor.max_rejoin_attempts", max_rejoin)

    local clear_cache = ui.confirm("Clear cache on rejoin?", mon.clear_cache_on_rejoin ~= false)
    config.set(cfg_data, "monitor.clear_cache_on_rejoin", clear_cache)

    local auto_launch = ui.confirm("Auto-launch on monitor start?", mon.auto_launch_on_start ~= false)
    config.set(cfg_data, "monitor.auto_launch_on_start", auto_launch)

    config.save(cfg_data)
    ui.success("Monitor settings saved!")
    shell.sleep(1)

    return cfg_data
end

return monitor

end

-- ============================================================
-- MODULE: api
-- ============================================================
_MODULES["api"] = function()
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

end

-- ============================================================
-- MODULE: optimizer
-- ============================================================
_MODULES["optimizer"] = function()
-- StarhubRejoiner: Roblox Optimizer
-- Manipulate ClientAppSettings.json for Potato Mode and FPS Unlock

local shell = require("shell")
local ui = require("ui")

local optimizer = {}

-- known fast settings for potato mode (15 FPS, lowest graphics)
local POTATO_JSON = [[
{
  "DFIntTaskSchedulerTargetFps": "15",
  "FFlagDisablePostFx": "True",
  "FFlagDebugGraphicsDisableCSGv2": "True",
  "FFlagDebugGraphicsPreferD3D11": "False",
  "FIntRenderShadowIntensity": "0",
  "FFlagDebugGraphicsPreferOpenGL": "True",
  "DFIntMaxFrameBufferSize": "4",
  "FFlagFastAnimBypassTimeCheck": "True",
  "FFlagGameBasicSettingsFramerateCap": "True"
}
]]

-- 60 fps unlock
local SMOOTH_JSON = [[
{
  "DFIntTaskSchedulerTargetFps": "60",
  "FFlagGameBasicSettingsFramerateCap": "True"
}
]]

--- Inject ClientAppSettings.json to a package
---@param package_name string
---@param json_content string
---@return boolean success
---@return string|nil err
function optimizer.apply(package_name, json_content)
    local target_dir = "/data/data/" .. package_name .. "/files/ClientSettings"
    local target_file = target_dir .. "/ClientAppSettings.json"
    
    -- create dir safely
    local code, out = shell.su("mkdir -p " .. shell.quote(target_dir))
    if code ~= 0 then
        return false, "Failed to create directory: " .. tostring(out)
    end
    
    -- write file via temp to avoid selinux issues with echo directly to /data/data
    local temp_file = "/data/local/tmp/ClientAppSettings_" .. package_name .. ".json"
    local echo_cmd = string.format("cat << 'EOF' > %s\n%s\nEOF", shell.quote(temp_file), json_content)
    code, out = shell.su(echo_cmd)
    if code ~= 0 then
        return false, "Failed to write temp file: " .. tostring(out)
    end
    
    -- move and chown
    shell.su("cp " .. shell.quote(temp_file) .. " " .. shell.quote(target_file))
    shell.su("rm -f " .. shell.quote(temp_file))
    
    -- chown to app uid
    local _, uid_output = shell.su("stat -c '%u' /data/data/" .. shell.quote(package_name) .. " 2>/dev/null")
    local uid = shell.trim(uid_output)
    if uid ~= "" and uid ~= "0" then
        shell.su("chown " .. uid .. ":" .. uid .. " " .. shell.quote(target_dir))
        shell.su("chown " .. uid .. ":" .. uid .. " " .. shell.quote(target_file))
    end
    shell.su("chmod 777 " .. shell.quote(target_dir))
    shell.su("chmod 666 " .. shell.quote(target_file))
    
    return true, nil
end

--- Remove ClientAppSettings.json from a package
---@param package_name string
function optimizer.remove(package_name)
    local target_file = "/data/data/" .. package_name .. "/files/ClientSettings/ClientAppSettings.json"
    shell.su("rm -f " .. shell.quote(target_file))
    return true
end

--- Interactive menu for Optimization
---@param packages table List of installed roblox packages
function optimizer.menu(packages)
    while true do
        ui.header("Optimization (FPS & Graphics)")
        
        if #packages == 0 then
            ui.error("No packages found!")
            ui.info("Press Enter to continue...")
            io.read("*l")
            return
        end
        
        local action = ui.menu({
            { key = "1", label = "Potato Mode (15 FPS, Rata Kiri)" },
            { key = "2", label = "Smooth Mode (60 FPS Unlock)" },
            { key = "3", label = "Remove Optimization (Default)" },
            { separator = true },
            { key = "0", label = "Back", color = ui.color.gray },
        }, "Select optimization profile")
        
        if not action or action == "0" then
            break
        end
        
        -- Target selection
        ui.info("Select target package:")
        local p_menu = {}
        for i, pkg in ipairs(packages) do
            p_menu[#p_menu + 1] = { key = tostring(i), label = pkg }
        end
        p_menu[#p_menu + 1] = { key = "a", label = "All Packages", color = ui.color.cyan }
        p_menu[#p_menu + 1] = { key = "0", label = "Cancel", color = ui.color.gray }
        
        local choice = ui.menu(p_menu, "Target")
        
        local targets = {}
        if choice == "a" then
            targets = packages
        else
            local idx = tonumber(choice)
            if idx and idx > 0 and idx <= #packages then
                targets = { packages[idx] }
            else
                goto continue_loop
            end
        end
        
        for _, pkg in ipairs(targets) do
            ui.info("Applying to " .. pkg .. "...")
            -- Stop app first
            shell.am_force_stop(pkg)
            
            if action == "1" then
                local ok, err = optimizer.apply(pkg, POTATO_JSON)
                if ok then ui.success("Potato mode applied to " .. pkg) else ui.error(tostring(err)) end
            elseif action == "2" then
                local ok, err = optimizer.apply(pkg, SMOOTH_JSON)
                if ok then ui.success("Smooth mode applied to " .. pkg) else ui.error(tostring(err)) end
            elseif action == "3" then
                optimizer.remove(pkg)
                ui.success("Optimization removed for " .. pkg)
            end
        end
        
        ::continue_loop::
        print("")
        ui.info("Press Enter to continue...")
        io.read("*l")
    end
end

return optimizer

end

-- ============================================================
-- MODULE: autoexec
-- ============================================================
_MODULES["autoexec"] = function()
-- StarhubRejoiner: Autoexecute Manager
-- Manage scripts in Delta/Autoexecute

local shell = require("shell")
local ui = require("ui")

local autoexec = {}

local DELTA_AUTOEXEC_DIR = "/sdcard/Delta/Autoexecute"

--- Ensure the directory exists
function autoexec.init()
    shell.su("mkdir -p " .. shell.quote(DELTA_AUTOEXEC_DIR))
end

--- Get a list of scripts in the autoexecute directory
---@return table list of filenames
function autoexec.list_scripts()
    local code, output = shell.su("ls -1 " .. shell.quote(DELTA_AUTOEXEC_DIR) .. " 2>/dev/null")
    local scripts = {}
    if code == 0 and output then
        for line in output:gmatch("[^\n]+") do
            if line ~= "" then
                scripts[#scripts + 1] = shell.trim(line)
            end
        end
    end
    return scripts
end

--- Download a script from URL and save it to the autoexec directory
---@param url string
---@param filename string
---@return boolean success
---@return string|nil err
function autoexec.add_from_url(url, filename)
    local target_path = DELTA_AUTOEXEC_DIR .. "/" .. filename
    
    -- Using curl to download directly
    local code, out = shell.su("curl -k -sL " .. shell.quote(url) .. " -o " .. shell.quote(target_path) .. " 2>&1")
    if code ~= 0 then
        return false, "Failed to download: " .. tostring(out)
    end
    return true, nil
end

--- Write a script manually to the autoexec directory
---@param filename string
---@param content string
---@return boolean success
---@return string|nil err
function autoexec.add_manual(filename, content)
    local target_path = DELTA_AUTOEXEC_DIR .. "/" .. filename
    local temp_path = "/data/local/tmp/" .. filename
    
    local echo_cmd = string.format("cat << 'EOF' > %s\n%s\nEOF", shell.quote(temp_path), content)
    local code, out = shell.su(echo_cmd)
    if code ~= 0 then
        return false, "Failed to write temp file: " .. tostring(out)
    end
    
    shell.su("cp " .. shell.quote(temp_path) .. " " .. shell.quote(target_path))
    shell.su("rm -f " .. shell.quote(temp_path))
    return true, nil
end

--- Delete a script
---@param filename string
function autoexec.delete(filename)
    local target_path = DELTA_AUTOEXEC_DIR .. "/" .. filename
    shell.su("rm -f " .. shell.quote(target_path))
end

--- Main menu for Autoexecute Manager
function autoexec.menu()
    autoexec.init()
    
    while true do
        ui.header("Delta Autoexecute Manager")
        ui.info("Directory: " .. ui.c(DELTA_AUTOEXEC_DIR, ui.color.cyan))
        
        local scripts = autoexec.list_scripts()
        if #scripts == 0 then
            ui.info("Status: " .. ui.c("No scripts found", ui.color.gray))
        else
            ui.info("Current Scripts:")
            for i, script in ipairs(scripts) do
                print("  [" .. i .. "] " .. script)
            end
        end
        print("")
        
        local action = ui.menu({
            { key = "1", label = "Add script from URL (Pastebin/Github)" },
            { key = "2", label = "Add script manually (Paste text)" },
            { key = "3", label = "Delete a script", color = ui.color.red },
            { separator = true },
            { key = "0", label = "Back", color = ui.color.gray },
        }, "Select action")
        
        if not action or action == "0" then
            break
        end
        
        if action == "1" then
            local url = ui.input("Enter RAW URL (e.g., https://pastebin.com/raw/...)")
            if url and url ~= "" then
                local filename = ui.input("Enter filename to save as (e.g., myscript.lua)", "script.lua")
                if filename and filename ~= "" then
                    ui.info("Downloading...")
                    local ok, err = autoexec.add_from_url(url, filename)
                    if ok then
                        ui.success("Script saved as " .. filename)
                    else
                        ui.error(err)
                    end
                end
            end
            ui.info("Press Enter to continue...")
            io.read("*l")
            
        elseif action == "2" then
            local filename = ui.input("Enter filename (e.g., myscript.lua)", "script.lua")
            if filename and filename ~= "" then
                print("")
                ui.info("Paste your script content below (Press Enter twice on an empty line to finish):")
                local lines = {}
                while true do
                    io.write(ui.color.cyan .. "> " .. ui.color.reset)
                    local line = io.read("*l")
                    if not line or line == "" then
                        break
                    end
                    lines[#lines + 1] = line
                end
                
                if #lines > 0 then
                    local content = table.concat(lines, "\n")
                    local ok, err = autoexec.add_manual(filename, content)
                    if ok then
                        ui.success("Script saved as " .. filename)
                    else
                        ui.error(err)
                    end
                else
                    ui.warn("No content provided.")
                end
            end
            ui.info("Press Enter to continue...")
            io.read("*l")
            
        elseif action == "3" then
            if #scripts == 0 then
                ui.error("No scripts to delete!")
            else
                local items = {}
                for i, script in ipairs(scripts) do
                    items[#items + 1] = { key = tostring(i), label = script }
                end
                items[#items + 1] = { key = "0", label = "Cancel", color = ui.color.gray }
                
                local choice = ui.menu(items, "Select script to delete")
                local idx = tonumber(choice)
                if idx and idx > 0 and idx <= #scripts then
                    local target = scripts[idx]
                    if ui.confirm("Delete " .. target .. "?", false) then
                        autoexec.delete(target)
                        ui.success("Deleted " .. target)
                    end
                end
            end
            ui.info("Press Enter to continue...")
            io.read("*l")
        end
    end
end

return autoexec

end

-- ============================================================
-- MAIN ENTRY POINT
-- ============================================================
-- ============================================================
-- StarhubRejoiner v1.0
-- CLI tool for managing Roblox instances on cloud phones
-- Runs in Termux with root access
-- ============================================================

local VERSION = "1.0.0"

-- Setup module path

-- Load modules
local json    = require("json")
local shell   = require("shell")
local ui      = require("ui")
local config  = require("config")
local device  = require("device")
local monitor = require("monitor")
local cookie  = require("cookie")
local grid    = require("grid")
local api     = require("api")

-- ============================================================
-- CLI ARGUMENT PARSER
-- ============================================================

local function parse_args()
    local args = {
        mode = nil,     -- "monitor", "status", "inject", "api", "setup"
        lang = nil,     -- "id" or "en"
        api_mode = false,
    }

    local i = 1
    while i <= #arg do
        local a = arg[i]
        if a == "--mode" and arg[i + 1] then
            args.mode = arg[i + 1]
            i = i + 2
        elseif a == "--lang" and arg[i + 1] then
            args.lang = arg[i + 1]
            i = i + 2
        elseif a == "--api" then
            args.api_mode = true
            i = i + 1
        elseif a == "--help" or a == "-h" then
            args.mode = "help"
            i = i + 1
        elseif a == "--version" or a == "-v" then
            args.mode = "version"
            i = i + 1
        else
            i = i + 1
        end
    end

    return args
end

-- ============================================================
-- HELP & VERSION
-- ============================================================

local function print_help()
    ui.banner()
    print("")
    print(ui.c("Usage:", ui.color.bold) .. " lua main.lua [options]")
    print("")
    print(ui.c("Options:", ui.color.bold))
    print("  --mode <mode>    Run in specific mode:")
    print("                     monitor  - Start monitoring directly")
    print("                     status   - Print status table and exit")
    print("                     setup    - Run first-time setup")
    print("  --api            Start API server (stdin/stdout mode)")
    print("  --lang <id|en>   Set language")
    print("  --help, -h       Show this help")
    print("  --version, -v    Show version")
    print("")
    print(ui.c("Examples:", ui.color.bold))
    print("  lua main.lua                    # Interactive menu")
    print("  lua main.lua --mode monitor     # Start monitoring")
    print("  lua main.lua --mode status      # Show status")
    print("  lua main.lua --api              # API mode")
    print("")
end

-- ============================================================
-- CONFIGURATION MENU
-- ============================================================

local function config_menu(cfg_data)
    while true do
        ui.header("Configuration")

        -- Show current config summary
        ui.subheader("Current Settings")
        ui.kv("Package Prefix", config.get(cfg_data, "packages.prefix", "com.roblox"))
        ui.kv("Server Type", config.get(cfg_data, "server.type", "ps_link"))

        local server_type = config.get(cfg_data, "server.type", "ps_link")
        local game_name = config.get(cfg_data, "server.game_name", "")
        if game_name ~= "" then
            ui.kv("Game Name", ui.c(game_name, ui.color.green))
        end

        if server_type == "ps_link" then
            local link = config.get(cfg_data, "server.ps_link", "")
            ui.kv("PS Link", link ~= "" and link or ui.c("NOT SET", ui.color.red))
        elseif server_type == "place_id" then
            ui.kv("Place ID", config.get(cfg_data, "server.place_id", "") or ui.c("NOT SET", ui.color.red))
        elseif server_type == "job_id" then
            ui.kv("Place ID", config.get(cfg_data, "server.place_id", "") or ui.c("NOT SET", ui.color.red))
            ui.kv("Job ID", config.get(cfg_data, "server.job_id", "") or ui.c("NOT SET", ui.color.red))
        end

        ui.kv("Check Interval", tostring(config.get(cfg_data, "monitor.check_interval", 10)) .. "s")
        ui.kv("Periodic Rejoin", tostring(config.get(cfg_data, "monitor.periodic_rejoin_minutes", 0)) .. " min")
        ui.kv("Join Delay", tostring(config.get(cfg_data, "monitor.launch_stagger_seconds", 8)) .. "s")

        local choice = ui.menu({
            { key = "1", label = "Server Target (PS Link / Place ID / Job ID)" },
            { key = "2", label = "Monitor Settings" },
            { key = "3", label = "Package Settings" },
            { key = "4", label = "Auto Grid Layout" },
            { key = "5", label = "Optimization (FPS & Graphics)" },
            { key = "6", label = "Autoexecute Manager (Delta)" },
            { key = "7", label = "View Raw Config" },
            { key = "8", label = "Reset to Defaults", color = ui.color.red },
            { separator = true },
            { key = "0", label = "Back", color = ui.color.gray },
        })

        if choice == "1" then
            cfg_data = monitor.configure_server(cfg_data)

        elseif choice == "2" then
            cfg_data = monitor.configure_monitor(cfg_data)

        elseif choice == "3" then
            ui.header("Package Settings")
            local mode = ui.menu({
                { key = "1", label = "Auto-scan (recommended)" },
                { key = "2", label = "Manual package list" },
            }, "Package detection mode")

            if mode == "1" then
                config.set(cfg_data, "packages.mode", "auto")
                local prefix = ui.input("Package prefix for scanning", config.get(cfg_data, "packages.prefix", "com.roblox"))
                config.set(cfg_data, "packages.prefix", prefix)
            elseif mode == "2" then
                config.set(cfg_data, "packages.mode", "manual")
                ui.info("Enter package names, one per line. Empty line to finish:")
                local packages = {}
                while true do
                    io.write(ui.color.cyan .. "> " .. ui.color.reset)
                    io.flush()
                    local line = io.read("*l")
                    if not line or line:match("^%s*$") then break end
                    packages[#packages + 1] = shell.trim(line)
                end
                config.set(cfg_data, "packages.manual_list", packages)
            end
            config.save(cfg_data)
            ui.success("Package settings saved!")
            shell.sleep(1)

        elseif choice == "4" then
            local packages = device.get_packages(config.get(cfg_data, "packages.prefix", "com.roblox"))
            grid.menu(cfg_data, packages)

        elseif choice == "5" then
            local packages = device.get_packages(config.get(cfg_data, "packages.prefix", "com.roblox"))
            local optimizer = require("optimizer")
            optimizer.menu(packages)

        elseif choice == "6" then
            local autoexec = require("autoexec")
            autoexec.menu()

        elseif choice == "7" then
            ui.header("Raw Configuration")
            local raw = json.encode(cfg_data)
            print(raw)
            ui.info("Press Enter to continue...")
            io.read("*l")

        elseif choice == "8" then
            if ui.confirm("Reset ALL settings to defaults? This cannot be undone!", false) then
                cfg_data = config.DEFAULT
                config.save(cfg_data)
                ui.success("Settings reset to defaults!")
            end
            shell.sleep(1)

        elseif choice == "99" then
            local packages = device.scan_packages(config.get(cfg_data, "packages.prefix", "roblox"))
            shell.clear()
            ui.header("Pebletz Spy Scanner")
            print("Pilih paket yang baru saja di-inject oleh Pebletz:\n")
            for i, pkg in ipairs(packages) do
                print(string.format("  %d. %s", i, pkg))
            end
            io.write("\n? Nomor paket: ")
            local num = tonumber(io.read() or "")
            if num and packages[num] then
                local pkg = packages[num]
                print("\n[*] Men-scan file yang berubah dalam 15 menit terakhir di " .. pkg .. "...")
                local _, out = shell.su("find /data/data/" .. pkg .. " -mmin -15 -type f -exec ls -la {} \\;")
                print("\n--- HASIL SCAN ---")
                print(out or "Tidak ada file yang berubah.")
                
                print("\n[*] Mengecek file shared_prefs...")
                local _, out2 = shell.su("ls -la /data/data/" .. pkg .. "/shared_prefs/")
                print("\n--- ISI SHARED PREFS ---")
                print(out2 or "Kosong")

                print("\n[*] Mengecek isi webview...")
                local _, out3 = shell.su("ls -la /data/data/" .. pkg .. "/app_webview/")
                print("\n--- ISI APP_WEBVIEW ---")
                print(out3 or "Kosong")
            else
                ui.warn("Pilihan tidak valid")
            end
            ui.info("\nPress Enter to continue...")
            io.read("*l")

        elseif choice == "0" or choice == nil then
            break
        end
    end

    return cfg_data
end

-- ============================================================
-- PACKAGE MANAGER MENU
-- ============================================================

local function package_menu(cfg_data, packages)
    while true do
        ui.header("Package Manager")

        -- Show packages
        ui.info("Found " .. #packages .. " Roblox package(s):")
        print("")
        for i, pkg in ipairs(packages) do
            local running = shell.is_running(pkg)
            local status = running and ui.c("running", ui.color.green) or ui.c("stopped", ui.color.gray)
            print("  " .. ui.c(tostring(i), ui.color.yellow) .. ". " .. pkg .. "  " .. status)
        end

        local choice = ui.menu({
            { key = "1", label = "Refresh Package List" },
            { key = "2", label = "Launch Package" },
            { key = "3", label = "Force Stop Package" },
            { key = "4", label = "Force Stop All" },
            { key = "5", label = "Clear Cache (package)" },
            { key = "6", label = "Set Package Prefix" },
            { separator = true },
            { key = "0", label = "Back", color = ui.color.gray },
        })

        if choice == "1" then
            device.clear_package_cache()
            packages = device.scan_packages(config.get(cfg_data, "packages.prefix", "roblox"))
            ui.success("Found " .. #packages .. " package(s)")
            shell.sleep(1)

        elseif choice == "2" then
            local idx = ui.input_number("Package number to launch", nil, 1, #packages)
            if idx and packages[idx] then
                local uri = config.get_launch_uri(cfg_data, packages[idx])
                if uri then
                    ui.info("Launching " .. packages[idx] .. "...")
                    shell.am_start(packages[idx], uri)
                    ui.success("Launched!")
                else
                    ui.info("Launching " .. packages[idx] .. " (no server configured)...")
                    shell.am_start(packages[idx])
                    ui.success("Launched!")
                end
                shell.sleep(1)
            end

        elseif choice == "3" then
            local idx = ui.input_number("Package number to stop", nil, 1, #packages)
            if idx and packages[idx] then
                shell.am_force_stop(packages[idx])
                ui.success("Stopped " .. packages[idx])
                shell.sleep(1)
            end

        elseif choice == "4" then
            if ui.confirm("Force stop ALL packages?", false) then
                for _, pkg in ipairs(packages) do
                    shell.am_force_stop(pkg)
                    ui.info("Stopped " .. pkg)
                end
                ui.success("All packages stopped")
                shell.sleep(1)
            end

        elseif choice == "5" then
            local idx = ui.input_number("Package number to clear cache", nil, 1, #packages)
            if idx and packages[idx] then
                shell.clear_cache(packages[idx])
                ui.success("Cache cleared for " .. packages[idx])
                shell.sleep(1)
            end

        elseif choice == "6" then
            local prefix = ui.input("Package prefix", config.get(cfg_data, "packages.prefix", "com.roblox"))
            config.set(cfg_data, "packages.prefix", prefix)
            config.save(cfg_data)
            device.clear_package_cache()
            packages = device.scan_packages(prefix)
            ui.success("Prefix set, found " .. #packages .. " package(s)")
            shell.sleep(1)

        elseif choice == "0" or choice == nil then
            break
        end
    end

    return cfg_data, packages
end

-- ============================================================
-- MAIN MENU
-- ============================================================

local function main_menu()
    -- Load config
    local cfg_data, is_new = config.load()
    if is_new then
        ui.info("First run detected — creating default config...")
        config.save(cfg_data)
    end

    -- Device preflight
    shell.clear()
    ui.banner()
    print("")

    if not device.preflight_check() then
        ui.error("Device check failed! Some features may not work.")
        ui.info("Press Enter to continue anyway...")
        io.read("*l")
    end

    -- Scan packages
    local prefix = config.get(cfg_data, "packages.prefix", "roblox")
    local packages = device.scan_packages(prefix)
    ui.success("Found " .. #packages .. " Roblox package(s)")
    shell.sleep(1)

    -- Main loop
    while true do
        shell.clear()
        ui.banner()

        -- Show system info
        if config.get(cfg_data, "display.show_system_info", true) then
            device.print_system_info()
        end

        -- Show quick package status
        local statuses = device.get_all_status(packages)
        local mask = config.get(cfg_data, "display.mask_usernames", false)
        device.print_status_table(statuses, mask)

        -- Main menu
        local choice = ui.menu({
            { key = "1", label = "Cookie Injection",     color = ui.color.white },
            { key = "2", label = "Auto Rejoin",          color = ui.color.white },
            { key = "3", label = "Status Monitor",       color = ui.color.white },
            { key = "4", label = "Package Manager",      color = ui.color.white },
            { key = "5", label = "Configuration",        color = ui.color.white },
            { key = "6", label = "Set Package Prefix (current: " ..
                          config.get(cfg_data, "packages.prefix", "com.roblox") .. ")" },
            { key = "7", label = "Toggle Masking (status table)" },
            { key = "8", label = "Refresh Status" },
            { separator = true },
            { key = "0", label = "Exit", color = ui.color.red },
        }, "Select an option")

        if choice == "1" then
            cfg_data = cookie.injection_menu(cfg_data, packages)

        elseif choice == "2" then
            cfg_data = monitor.menu(cfg_data, packages)

        elseif choice == "3" then
            -- Quick status view
            shell.clear()
            monitor.print_status(cfg_data, packages)
            print("")
            ui.info("Press Enter to go back...")
            io.read("*l")

        elseif choice == "4" then
            cfg_data, packages = package_menu(cfg_data, packages)

        elseif choice == "5" then
            cfg_data = config_menu(cfg_data)

        elseif choice == "6" then
            local new_prefix = ui.input("Package prefix", config.get(cfg_data, "packages.prefix", "com.roblox"))
            config.set(cfg_data, "packages.prefix", new_prefix)
            config.save(cfg_data)
            device.clear_package_cache()
            packages = device.scan_packages(new_prefix)
            ui.success("Prefix set to: " .. new_prefix .. " (found " .. #packages .. " packages)")
            shell.sleep(1)

        elseif choice == "7" then
            local current = config.get(cfg_data, "display.mask_usernames", false)
            config.set(cfg_data, "display.mask_usernames", not current)
            config.save(cfg_data)
            ui.success("Username masking " .. (not current and "enabled" or "disabled"))
            shell.sleep(1)

        elseif choice == "8" then
            device.clear_package_cache()
            packages = device.scan_packages(config.get(cfg_data, "packages.prefix", "roblox"))
            ui.success("Status refreshed, found " .. #packages .. " package(s)")
            shell.sleep(1)

        elseif choice == "99" then
            shell.clear()
            ui.header("Pebletz Diagnostic Dump")
            local c_pkg = ui.input("Enter package to dump (e.g. com.roblox.clienx)", "com.roblox.clienx")
            print("")
            ui.info("Dumping schema for " .. c_pkg .. "...")
            local path = "/data/data/" .. c_pkg .. "/app_webview/Default/Cookies"
            local code, out = shell.sqlite(path, ".schema cookies")
            print(out)
            print("")
            ui.info("Dumping row data (excluding encrypted values)...")
            local code2, out2 = shell.sqlite(path, "SELECT creation_utc, host_key, name, path, expires_utc, has_expires FROM cookies;")
            print(out2)
            print("")
            ui.info("Press Enter to continue...")
            io.read("*l")

        elseif choice == "0" or choice == nil then
            print("")
            ui.info("Goodbye! 👋")
            os.exit(0)
        end
    end
end

-- ============================================================
-- ENTRY POINT
-- ============================================================

local function main()
    local args = parse_args()

    -- Handle non-interactive modes
    if args.mode == "help" then
        print_help()
        os.exit(0)
    end

    if args.mode == "version" then
        print("StarhubRejoiner v" .. VERSION)
        os.exit(0)
    end

    if args.api_mode then
        local cfg_data = config.load()
        api.stdin_loop(cfg_data)
        os.exit(0)
    end

    if args.mode == "status" then
        local cfg_data = config.load()
        local packages = device.scan_packages(config.get(cfg_data, "packages.prefix", "roblox"))
        monitor.print_status(cfg_data, packages)
        os.exit(0)
    end

    if args.mode == "monitor" then
        local cfg_data = config.load()
        local packages = device.scan_packages(config.get(cfg_data, "packages.prefix", "roblox"))
        local target = config.get_target_packages(cfg_data, packages)
        if #target == 0 then
            ui.error("No packages to monitor!")
            os.exit(1)
        end
        monitor.start(cfg_data, target)
        os.exit(0)
    end

    -- Default: interactive menu
    main_menu()
end

-- Run
local ok, err = pcall(main)
if not ok then
    io.write("\n")
    ui.error("Fatal error: " .. tostring(err))
    ui.error("Please report this issue.")
    os.exit(1)
end
