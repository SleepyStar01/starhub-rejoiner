#!/usr/bin/env lua
-- ============================================================
-- StarhubRejoiner v1.0
-- CLI tool for managing Roblox instances on cloud phones
-- Runs in Termux with root access
-- ============================================================

local VERSION = "1.0.0"

-- Setup module path
local script_dir = arg[0]:match("(.+)/[^/]+$") or "."
package.path = script_dir .. "/lib/?.lua;" .. package.path

-- Load modules
local json    = require("json")
local shell   = require("shell")
local ui      = require("ui")
local config  = require("config")
local device  = require("device")
local monitor = require("monitor")
local cookie  = require("cookie")
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
        ui.kv("Language", config.get(cfg_data, "language", "id"))
        ui.kv("Package Mode", config.get(cfg_data, "packages.mode", "auto"))
        ui.kv("Package Prefix", config.get(cfg_data, "packages.prefix", "com.roblox"))
        ui.kv("Server Type", config.get(cfg_data, "server.type", "ps_link"))

        local server_type = config.get(cfg_data, "server.type", "ps_link")
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
        ui.kv("Discord Webhook", config.get(cfg_data, "notifications.discord_webhook", "") ~= "" and "Set" or "Not set")
        ui.kv("UI Mode", config.get(cfg_data, "display.ui_mode", "live"))

        local choice = ui.menu({
            { key = "1", label = "Server Target (PS Link / Place ID / Job ID)" },
            { key = "2", label = "Monitor Settings" },
            { key = "3", label = "Package Settings" },
            { key = "4", label = "Display Settings" },
            { key = "5", label = "Discord Webhook" },
            { key = "6", label = "View Raw Config" },
            { key = "7", label = "Reset to Defaults", color = ui.color.red },
            { separator = true },
            { key = "0", label = "Back", color = ui.color.gray },
        })

        if choice == "1" then
            cfg_data = monitor.configure_server(cfg_data)

        elseif choice == "2" then
            cfg_data = monitor.configure_monitor(cfg_data)

        elseif choice == "3" then
            -- Package settings
            ui.header("Package Settings")
            local mode = ui.menu({
                { key = "1", label = "Auto-scan (recommended)" },
                { key = "2", label = "Manual package list" },
            }, "Package detection mode")

            if mode == "1" then
                config.set(cfg_data, "packages.mode", "auto")
                local prefix = ui.input("Package prefix for scanning", config.get(cfg_data, "packages.prefix", "roblox"))
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
            -- Display settings
            ui.header("Display Settings")
            local ui_mode = ui.menu({
                { key = "1", label = "Live (full dashboard, clears screen)" },
                { key = "2", label = "Compact (single-line status, no clear)" },
            }, "UI mode")
            if ui_mode == "1" then
                config.set(cfg_data, "display.ui_mode", "live")
            elseif ui_mode == "2" then
                config.set(cfg_data, "display.ui_mode", "compact")
            end

            local show_sys = ui.confirm("Show system info (CPU/RAM)?",
                config.get(cfg_data, "display.show_system_info", true))
            config.set(cfg_data, "display.show_system_info", show_sys)

            local mask = ui.confirm("Mask usernames in status?",
                config.get(cfg_data, "display.mask_usernames", false))
            config.set(cfg_data, "display.mask_usernames", mask)

            config.save(cfg_data)
            ui.success("Display settings saved!")
            shell.sleep(1)

        elseif choice == "5" then
            -- Discord webhook
            ui.header("Discord Webhook")
            local current = config.get(cfg_data, "notifications.discord_webhook", "")
            if current ~= "" then
                ui.info("Current webhook: " .. current:sub(1, 40) .. "...")
            end
            local webhook = ui.input("Discord Webhook URL (empty to clear)", current)
            config.set(cfg_data, "notifications.discord_webhook", webhook)
            config.save(cfg_data)
            ui.success("Webhook settings saved!")
            shell.sleep(1)

        elseif choice == "6" then
            -- View raw config
            ui.header("Raw Config")
            print(json.encode(cfg_data, true))
            print("")
            ui.info("Press Enter to continue...")
            io.read("*l")

        elseif choice == "7" then
            -- Reset to defaults
            if ui.confirm("Reset ALL settings to defaults? This cannot be undone!", false) then
                cfg_data = config.load() -- Will get defaults
                -- Actually overwrite with a fresh copy
                local fresh = {}
                for k, v in pairs(config.DEFAULT) do
                    if type(v) == "table" then
                        fresh[k] = json.decode(json.encode(v))
                    else
                        fresh[k] = v
                    end
                end
                cfg_data = fresh
                config.save(cfg_data)
                ui.success("Config reset to defaults!")
                shell.sleep(1)
            end

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
