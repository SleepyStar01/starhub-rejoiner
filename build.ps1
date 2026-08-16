# StarhubRejoiner Build Script
# Combines all modules into a single distributable Lua file

$src = "c:\Users\Sleepy\Documents\StarhubUI\rejoiner"
$out = Join-Path $src "starhub-rejoiner.lua"
$modules = @("json", "shell", "ui", "config", "device", "cookie", "monitor", "api")

$sb = New-Object System.Text.StringBuilder

# Header
$header = @'
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

'@

[void]$sb.Append($header)

# Bundle each module
foreach ($mod in $modules) {
    $modPath = Join-Path $src "lib\$mod.lua"
    if (-not (Test-Path $modPath)) {
        Write-Error "Module not found: $modPath"
        exit 1
    }
    $content = [System.IO.File]::ReadAllText($modPath, [System.Text.Encoding]::UTF8)
    
    $modHeader = @"
-- ============================================================
-- MODULE: $mod
-- ============================================================
"@
    [void]$sb.AppendLine($modHeader)
    
    $modOpen = '_MODULES["' + $mod + '"] = function()'
    [void]$sb.AppendLine($modOpen)
    [void]$sb.AppendLine($content)
    [void]$sb.AppendLine("end")
    [void]$sb.AppendLine("")
}

# Bundle main.lua (strip shebang and package.path setup)
$mainPath = Join-Path $src "main.lua"
$mainLines = [System.IO.File]::ReadAllLines($mainPath, [System.Text.Encoding]::UTF8)

[void]$sb.AppendLine("-- ============================================================")
[void]$sb.AppendLine("-- MAIN ENTRY POINT")
[void]$sb.AppendLine("-- ============================================================")

foreach ($line in $mainLines) {
    # Skip lines that are only needed in multi-file mode
    if ($line -match "^#!/usr/bin/env lua") { continue }
    if ($line -match "^local script_dir") { continue }
    if ($line -match "^package\.path") { continue }
    [void]$sb.AppendLine($line)
}

# Write output (UTF-8 without BOM)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($out, $sb.ToString(), $utf8NoBom)

$fileInfo = Get-Item $out
$sizeKB = [math]::Round($fileInfo.Length / 1024, 1)
Write-Host ""
Write-Host "  Build complete!" -ForegroundColor Green
Write-Host ("  Output: " + $out) -ForegroundColor Cyan
Write-Host ("  Size:   " + $sizeKB + " KB") -ForegroundColor Cyan
Write-Host ""
