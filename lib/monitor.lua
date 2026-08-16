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
    pkg_state.last_rejoin = os.time()

    ui.log("  " .. ui.c("Launched! Grace period: " .. grace .. "s", ui.color.green))

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
                    launched = launched + 1
                end
            else
                state.packages[pkg].state = "running"
                state.packages[pkg].pid = shell.get_pid(pkg)
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
        -- Start monitoring
        local target_packages = config.get_target_packages(cfg_data, packages)
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

    if choice == "1" then
        config.set(cfg_data, "server.type", "ps_link")
        local link = ui.input("Enter PS Link URL")
        if link and link ~= "" then
            config.set(cfg_data, "server.ps_link", link)
            config.save(cfg_data)
            ui.success("PS Link saved!")
        end

    elseif choice == "2" then
        config.set(cfg_data, "server.type", "place_id")
        local pid = ui.input("Enter Place ID")
        if pid and pid ~= "" then
            config.set(cfg_data, "server.place_id", pid)
            config.save(cfg_data)
            ui.success("Place ID saved!")
        end

    elseif choice == "3" then
        config.set(cfg_data, "server.type", "job_id")
        local pid = ui.input("Enter Place ID")
        local jid = ui.input("Enter Job ID (Game Instance ID)")
        if pid and pid ~= "" then
            config.set(cfg_data, "server.place_id", pid)
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

    local grace = ui.input_number("Startup grace period (seconds)", mon.startup_grace_seconds or 45, 10, 120)
    config.set(cfg_data, "monitor.startup_grace_seconds", grace)

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
