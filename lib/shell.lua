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

--- Get device CPU usage percentage
---@return string cpu_info
function shell.get_cpu_usage()
    local _, output = shell.exec(
        "top -bn1 2>/dev/null | head -5 | grep -i cpu || " ..
        "cat /proc/stat 2>/dev/null | head -1"
    )
    -- Try to parse percentage from top output
    local cpu = tonumber(output:match("(%d+%.?%d*)%%"))
    if cpu then
        if cpu > 100 then
            local cores = tonumber(shell.trim(shell.exec("nproc 2>/dev/null") or "1")) or 1
            if cores > 0 then cpu = cpu / cores end
            if cpu > 100 then cpu = 100 end
        end
        return string.format("%.1f%%", cpu)
    end
    -- Fallback: parse /proc/stat
    local fields = {}
    for v in (output or ""):gmatch("%d+") do
        fields[#fields + 1] = tonumber(v)
    end
    if #fields >= 4 then
        local total = 0
        for _, v in ipairs(fields) do total = total + v end
        local idle = fields[4]
        if total > 0 then
            return string.format("%.1f%%", (1 - idle / total) * 100)
        end
    end
    return "N/A"
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
    return shell.su(
        "sqlite3 " .. shell.quote(db_path) .. " " .. shell.quote(sql) .. " 2>/dev/null"
    )
end

return shell
