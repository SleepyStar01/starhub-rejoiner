#!/data/data/com.termux/files/usr/bin/sh
# ============================================================
# StarhubRejoiner — Bootstrap & Launcher
# Install dependencies, update from git, and run main.lua
# ============================================================

VERSION="1.0.0"
REPO_URL=""  # Set this if you host on GitHub
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If we're running from inside the repo (has main.lua), use this dir
if [ -f "$SCRIPT_DIR/main.lua" ]; then
    REPO_DIR="$SCRIPT_DIR"
else
    REPO_DIR="$HOME/starhub-rejoiner"
fi

# ============================================================
# HELPERS
# ============================================================

say() {
    printf "%s\n" "$1"
}

say_color() {
    printf "\033[%sm%s\033[0m\n" "$1" "$2"
}

say_cyan() {
    say_color "96" "$1"
}

say_green() {
    say_color "92" "$1"
}

say_red() {
    say_color "91" "$1"
}

say_yellow() {
    say_color "93" "$1"
}

# ============================================================
# BANNER
# ============================================================

print_banner() {
    say_cyan "╔══════════════════════════════════════════════╗"
    say_cyan "║          ★ StarhubRejoiner v$VERSION ★           ║"
    say_cyan "╚══════════════════════════════════════════════╝"
    say ""
}

# ============================================================
# DEPENDENCY INSTALLER
# ============================================================

ensure_deps() {
    say_cyan "[*] Checking dependencies..."

    # Update package list (quiet)
    pkg update -y > /dev/null 2>&1 || true

    # Required packages
    local DEPS="lua54 curl sqlite"
    local MISSING=""

    for tool in $DEPS; do
        if ! command -v "$tool" > /dev/null 2>&1; then
            MISSING="$MISSING $tool"
        fi
    done

    # lua54 might be installed as 'lua'
    if ! command -v lua54 > /dev/null 2>&1 && ! command -v lua > /dev/null 2>&1; then
        MISSING="$MISSING lua54"
    fi

    if [ -n "$MISSING" ]; then
        say_yellow "[*] Installing missing dependencies:$MISSING"
        for pkg_name in $MISSING; do
            say_cyan "[*] Installing $pkg_name..."
            pkg install "$pkg_name" -y || {
                say_red "[!] Failed to install $pkg_name"
                return 1
            }
        done
        say_green "[✓] All dependencies installed!"
    else
        say_green "[✓] All dependencies present"
    fi

    return 0
}

# ============================================================
# GIT UPDATE (optional, only if REPO_URL is set)
# ============================================================

ensure_repo() {
    # Skip if no repo URL configured
    if [ -z "$REPO_URL" ]; then
        return 0
    fi

    if ! command -v git > /dev/null 2>&1; then
        say_cyan "[*] Installing git..."
        pkg install git -y || return 1
    fi

    if [ -d "$REPO_DIR/.git" ]; then
        # Running from inside repo — pull latest
        say_cyan "[*] Updating from git..."
        git -C "$REPO_DIR" fetch --quiet origin 2>/dev/null || true
        git -C "$REPO_DIR" reset --hard origin/main 2>/dev/null || true
    elif [ "$SCRIPT_DIR" != "$REPO_DIR" ]; then
        # Fresh clone needed
        say_cyan "[*] Cloning repository..."
        rm -rf "$REPO_DIR" 2>/dev/null || true
        git clone "$REPO_URL" "$REPO_DIR" || return 1
    fi

    return 0
}

# ============================================================
# TERMUX WAKE LOCK
# ============================================================

setup_wake_lock() {
    if command -v termux-wake-lock > /dev/null 2>&1; then
        termux-wake-lock 2>/dev/null || true
        say_green "[✓] Wake lock acquired"
    else
        say_yellow "[!] termux-wake-lock not available (install Termux:API)"
    fi
}

# ============================================================
# CLEANUP
# ============================================================

cleanup() {
    if command -v termux-wake-unlock > /dev/null 2>&1; then
        termux-wake-unlock > /dev/null 2>&1 || true
    fi
}

on_interrupt() {
    say ""
    say_yellow "[*] Interrupted, cleaning up..."
    cleanup
    exit 130
}

# ============================================================
# MAIN
# ============================================================

main() {
    clear
    print_banner

    # Install dependencies
    ensure_deps || {
        say_red "[!] Failed to install dependencies"
        exit 1
    }

    # Update from git (if configured)
    ensure_repo || {
        say_red "[!] Failed to update repository"
        # Continue anyway — local files might still work
    }

    # Setup
    setup_wake_lock

    # Traps
    trap on_interrupt INT TERM HUP QUIT
    trap cleanup EXIT

    # Change to repo directory
    cd "$REPO_DIR" || {
        say_red "[!] Cannot change to $REPO_DIR"
        exit 1
    }

    # Find lua binary
    LUA_BIN=""
    if command -v lua54 > /dev/null 2>&1; then
        LUA_BIN="lua54"
    elif command -v lua > /dev/null 2>&1; then
        LUA_BIN="lua"
    else
        say_red "[!] Lua not found! Install with: pkg install lua54"
        exit 1
    fi

    say_green "[✓] Starting StarhubRejoiner..."
    say ""

    # Run main script, passing all arguments through
    "$LUA_BIN" "$REPO_DIR/main.lua" "$@"
    EXIT_CODE=$?

    cleanup
    exit $EXIT_CODE
}

main "$@"
