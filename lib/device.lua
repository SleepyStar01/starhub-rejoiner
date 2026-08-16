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

        -- Try to detect username from logcat
        local username = device.detect_username(package_name)
        if username then
            status.username = username
        end

        -- Try to detect user ID from logcat
        local user_id = device.detect_user_id(package_name)
        if user_id then
            status.user_id = user_id
        end
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
    if not pid then return nil end

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
    if not pid then return nil end

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
