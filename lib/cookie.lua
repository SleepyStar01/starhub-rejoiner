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
                host_key TEXT NOT NULL,
                name TEXT NOT NULL,
                value TEXT NOT NULL,
                path TEXT NOT NULL DEFAULT '/',
                expires_utc INTEGER NOT NULL DEFAULT 0,
                is_secure INTEGER NOT NULL DEFAULT 0,
                is_httponly INTEGER NOT NULL DEFAULT 0,
                last_access_utc INTEGER NOT NULL DEFAULT 0,
                has_expires INTEGER NOT NULL DEFAULT 1,
                is_persistent INTEGER NOT NULL DEFAULT 1,
                priority INTEGER NOT NULL DEFAULT 1,
                samesite INTEGER NOT NULL DEFAULT -1,
                source_scheme INTEGER NOT NULL DEFAULT 0
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
            "INSERT INTO cookies (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent) VALUES (%s, '%s', '%s', '%s', '%s', %s, 1, 1, %s, 1, 1);",
            creation_webkit, info.domain, info.name, cookie_value, info.path, expires_webkit, creation_webkit
        )
        local c2, out2 = shell.sqlite(temp_db, insert_sql)
        if c2 ~= 0 then
            -- Fallback to older Chromium schema
            insert_sql = string.format(
                "INSERT INTO cookies (creation_utc, host_key, name, value, path, expires_utc, secure, httponly, last_access_utc, has_expires, persistent) VALUES (%s, '%s', '%s', '%s', '%s', %s, 1, 1, %s, 1, 1);",
                creation_webkit, info.domain, info.name, cookie_value, info.path, expires_webkit, creation_webkit
            )
            shell.sqlite(temp_db, insert_sql)
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
