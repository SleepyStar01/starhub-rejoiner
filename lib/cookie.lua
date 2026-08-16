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

--- Inject a cookie into a Roblox package's data
---@param package_name string
---@param cookie_value string The .ROBLOSECURITY value
---@return boolean success
---@return string|nil error_message
function cookie.inject(package_name, cookie_value)
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

    -- Step 2: Find cookie database
    local db_path, db_type = cookie.find_db(package_name)

    if db_type == "sqlite" and db_path then
        return cookie.inject_sqlite(package_name, db_path, cookie_value)
    end

    -- Fallback: try to create/inject via known path
    ui.warn("Cookie database not found, attempting direct creation...")
    return cookie.inject_direct(package_name, cookie_value)
end

--- Inject cookie via SQLite database
---@param package_name string
---@param db_path string
---@param cookie_value string
---@return boolean success
---@return string|nil error
function cookie.inject_sqlite(package_name, db_path, cookie_value)
    ui.info("Injecting via SQLite: " .. db_path)

    local info = COOKIE_DB_INFO
    -- Calculate expiration (1 year from now in microseconds since epoch)
    local expires = tostring(os.time() + 365 * 24 * 3600)

    -- Build SQL to insert/replace the cookie
    local sql = string.format(
        [[DELETE FROM %s WHERE host_key='%s' AND name='%s';]] ..
        [[INSERT INTO %s (host_key, name, value, path, secure, httponly, has_expires, expires_utc, is_persistent, creation_utc, last_access_utc) ]] ..
        [[VALUES ('%s', '%s', '%s', '%s', %d, %d, 1, %s, 1, %s, %s);]],
        info.table_name, info.domain, info.name,
        info.table_name,
        info.domain, info.name, cookie_value, info.path,
        info.secure, info.httponly,
        expires, expires, expires
    )

    local code, output = shell.sqlite(db_path, sql)
    if code ~= 0 then
        -- Table might not have all columns, try simpler insert
        sql = string.format(
            [[DELETE FROM %s WHERE host_key='%s' AND name='%s';]] ..
            [[INSERT INTO %s (host_key, name, value, path) ]] ..
            [[VALUES ('%s', '%s', '%s', '%s');]],
            info.table_name, info.domain, info.name,
            info.table_name,
            info.domain, info.name, cookie_value, info.path
        )
        code, output = shell.sqlite(db_path, sql)
    end

    if code == 0 then
        -- Fix permissions
        cookie.fix_permissions(package_name, db_path)
        ui.success("Cookie injected successfully!")
        return true, nil
    else
        return false, "SQLite error: " .. tostring(output)
    end
end

--- Direct cookie injection (create WebView cookie DB from scratch)
---@param package_name string
---@param cookie_value string
---@return boolean success
---@return string|nil error
function cookie.inject_direct(package_name, cookie_value)
    -- Create the WebView directory structure
    local webview_dir = "/data/data/" .. package_name .. "/app_webview/Default"
    local db_path = webview_dir .. "/Cookies"

    shell.su("mkdir -p " .. shell.quote(webview_dir))

    local info = COOKIE_DB_INFO
    local expires = tostring(os.time() + 365 * 24 * 3600)

    -- Create SQLite database with cookie table
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

    local code, output = shell.sqlite(db_path, create_sql)
    if code ~= 0 then
        return false, "Failed to create cookie database: " .. tostring(output)
    end

    -- Insert the cookie
    local insert_sql = string.format(
        [[INSERT INTO cookies (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent) ]] ..
        [[VALUES (%s, '%s', '%s', '%s', '%s', %s, 1, 1, %s, 1, 1);]],
        expires, info.domain, info.name, cookie_value, info.path, expires, expires
    )

    code, output = shell.sqlite(db_path, insert_sql)
    if code ~= 0 then
        return false, "Failed to insert cookie: " .. tostring(output)
    end

    -- Fix permissions
    cookie.fix_permissions(package_name, db_path)
    ui.success("Cookie injected (direct method)!")
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
    ui.header("Cookie Injection")

    if #packages == 0 then
        ui.error("No Roblox packages found on device!")
        ui.info("Press Enter to go back...")
        io.read("*l")
        return cfg_data
    end

    -- Show available packages
    ui.info("Available packages:")
    local menu_items = {}
    for i, pkg in ipairs(packages) do
        local existing = config.get_cookie(cfg_data, pkg)
        local status = existing and (ui.c("has cookie", ui.color.green)) or (ui.c("no cookie", ui.color.gray))
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
    print("")
    ui.info("Target: " .. ui.c(target_pkg, ui.color.cyan))

    -- Ask for action
    local action = ui.menu({
        { key = "1", label = "Inject new cookie" },
        { key = "2", label = "View current cookie" },
        { key = "3", label = "Remove cookie" },
        { key = "0", label = "Back", color = ui.color.gray },
    }, "Select action")

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
            local ok, inject_err = cookie.inject(target_pkg, cookie_input)
            if ok then
                -- Save to config
                config.set_cookie(cfg_data, target_pkg, cookie.clean(cookie_input))
                config.save(cfg_data)
                ui.success("Cookie saved to config and injected!")
            else
                ui.error("Injection failed: " .. tostring(inject_err))
                -- Still save to config for later use
                if ui.confirm("Save cookie to config anyway?", true) then
                    config.set_cookie(cfg_data, target_pkg, cookie.clean(cookie_input))
                    config.save(cfg_data)
                    ui.info("Cookie saved to config")
                end
            end
        end

    elseif action == "2" then
        -- View current cookie
        local existing = config.get_cookie(cfg_data, target_pkg)
        if existing then
            print("")
            ui.info("Cookie for " .. target_pkg .. ":")
            ui.kv("Masked", cookie.mask(existing))
            ui.kv("Length", tostring(#existing) .. " chars")
        else
            ui.warn("No cookie stored for " .. target_pkg)
        end

    elseif action == "3" then
        -- Remove cookie
        if ui.confirm("Remove cookie for " .. target_pkg .. "?", false) then
            config.set_cookie(cfg_data, target_pkg, nil)
            config.save(cfg_data)
            ui.success("Cookie removed")
        end
    end

    print("")
    ui.info("Press Enter to continue...")
    io.read("*l")
    return cfg_data
end

return cookie
