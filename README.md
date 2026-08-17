# ★ StarhubRejoiner v1.0

CLI tool untuk manage instance Roblox di cloud phone / rooted Android via Termux.

## ✨ Features

- ✅ **Direct Cookie Injection** — Inject cookie ke Roblox kosong (tanpa perlu manual login). Bebas dari "Signed out" berkat Telemetry Purging!
- ✅ **Auto Rejoin** — Monitor proses Roblox, otomatis rejoin kalau crash/disconnect/kick
- ✅ **Status Monitor** — Dashboard real-time yang nunjukin semua package Roblox + status
- ✅ **Auto Grid Layout** — Susun jendela Roblox (Cloudphone) otomatis biar rapi tanpa numpuk
- ✅ **Optimization (FPS & Graphics)** — Ubah limit FPS dan matikan grafis berat buat menghemat RAM/CPU
- ✅ **Autoexecute Manager** — Atur script autoexecute (Delta Executor) langsung dari Termux
- ✅ **Multi-Package** — Support multiple Roblox clone (auto-scan dari device)
- ✅ **Server Targets** — Support PS Link, Place ID, dan Job ID

## 📋 Requirements

1. **Rooted Android Device** (Magisk/KernelSU)
   - Cloud phone (Redfinger, NOX Cloud, dll)
   - Emulator (LDPlayer, NoxPlayer, dll)
   - Physical device
2. **Termux** (F-Droid version recommended)
3. **Roblox** app installed
4. Dependencies: `lua54`, `curl`, `sqlite` (auto-installed by `start.sh`)

## 🚀 Quick Start (One-Liner)

### Step 1 — Install dependencies (sekali aja)

```bash
termux-setup-storage && pkg update && pkg upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" && pkg install lua54 curl sqlite -y
```

### Step 2 — Download & Run

```bash
curl -sL "https://raw.githubusercontent.com/SleepyStar01/starhub-rejoiner/refs/heads/main/starhub-rejoiner.lua?t=$(date +%s)" -o /sdcard/Download/starhub-rejoiner.lua && lua /sdcard/Download/starhub-rejoiner.lua
```

### Daily Run (setelah download)

```bash
lua /sdcard/Download/starhub-rejoiner.lua
```

### Update ke versi terbaru (Bypass Cache)

```bash
curl -sL "https://raw.githubusercontent.com/SleepyStar01/starhub-rejoiner/refs/heads/main/starhub-rejoiner.lua?t=$(date +%s)" -o /sdcard/Download/starhub-rejoiner.lua
```

---

### Alternative: Multi-file install (untuk development)

```bash
# Clone repo
git clone https://github.com/USERNAME/REPO.git /sdcard/Download/starhub-rejoiner
cd /sdcard/Download/starhub-rejoiner

# Run via bootstrap
chmod +x start.sh
./start.sh

# Atau langsung
lua main.lua
```

## 📊 Main Menu

```
╔══════════════════════════════════════════════╗
║          ★ StarhubRejoiner v1.0 ★           ║
╚══════════════════════════════════════════════╝

┌──────────┬──────────────────────────────────┐
│ Resource │ Usage                            │
├──────────┼──────────────────────────────────┤
│ CPU      │ 12.5% used                       │
│ Memory   │ 2.9 GB / 8.8 GB (33.0% used)    │
└──────────┴──────────────────────────────────┘

┌────────────────────────┬────────────┬──────────┬──────────────┐
│ Package                │ UserId     │ Username │ State        │
├────────────────────────┼────────────┼──────────┼──────────────┤
│ com.roblox.client      │ 9324256032 │ jamal..  │ ● ingame     │
│ com.roblox.clientv     │ -          │ -        │ ● stopped    │
└────────────────────────┴────────────┴──────────┴──────────────┘

  [1] - Cookie Injection
  [2] - Auto Rejoin
  [3] - Status Monitor
  [4] - Package Manager
  [5] - Configuration
  [6] - Set Package Prefix (current: com.roblox)
  [7] - Toggle Masking (status table)
  [8] - Refresh Status

  [0] - Exit

══════════════════════════════════════════════
? Select an option :
```

## ⚙️ CLI Modes

```bash
lua main.lua                      # Interactive menu
lua main.lua --mode monitor       # Start monitoring langsung
lua main.lua --mode status        # Print status table & exit
lua main.lua --api                # API mode (stdin/stdout)
lua main.lua --help               # Show help
```

## 🎮 Monitor Hotkeys

Ketika monitor jalan, bisa pake hotkey:
- `q` — Quit (keluar dari tool)
- `s` atau `Ctrl+Z` — Stop monitor, balik ke menu
- `p` — Pause/resume auto-rejoin

## ⚙️ Configuration (Sub-Menu)

Config disimpan di `../config.json` (di luar folder repo, aman dari git update).

### Server Target
- **PS Link**: `https://www.roblox.com/share?code=XXX&type=Server`
- **Place ID**: Numeric ID game
- **Job ID**: Game Instance ID (butuh Place ID juga)

### Auto Grid Layout
Mengatur letak dan ukuran window Roblox secara otomatis:
- **Columns**: Jumlah grid mendatar
- **Scaling**: Persentase ukuran resolusi per game (buat meringankan Cloudphone)

### Optimization (FPS & Graphics)
Bisa mengubah pengaturan grafik Roblox secara langsung dari file settingan Roblox-nya:
- **Unlock FPS**: Atur batas FPS (misal: 10, 15, 20) biar CPU nggak meledak.
- **Low Graphics**: Matikan bayangan, efek cuaca, pantulan air, dan turunkan kualitas gambar ke terendah secara otomatis.

### Autoexecute Manager (Delta)
Kelola script otomatis buat Delta Executor tanpa repot nge-copy manual:
- Taruh script `.lua` atau `.txt` ke folder `autoexec` dan aktifkan/matikan scriptnya lewat menu Termux.

### Monitor Settings
| Setting | Default | Keterangan |
|---------|---------|------------|
| check_interval | 10s | Interval check status |
| startup_grace_seconds | 45s | Grace period setelah launch |
| max_rejoin_attempts | 5 | Max rejoin retry |
| clear_cache_on_rejoin | true | Clear cache sebelum rejoin |
| auto_launch_on_start | true | Auto-launch ketika monitor start |

## 🔌 API Mode (Future Integration)

Tool bisa dijalankan dalam API mode untuk dikontrol dari web panel:

```bash
lua main.lua --api
```

Kirim JSON command via stdin:
```json
{"command": "get_status"}
{"command": "rejoin", "params": {"package": "com.roblox.client"}}
{"command": "inject_cookie", "params": {"package": "com.roblox.client", "cookie": "..."}}
{"command": "ping"}
```

Response dikirim sebagai JSON ke stdout.

## 📁 Project Structure

```
starhub-rejoiner/
├── starhub-rejoiner.lua  # ⭐ Single-file bundle (deploy this)
├── build.ps1             # Build script (regenerate bundle)
├── start.sh              # Bootstrap script (multi-file mode)
├── main.lua              # Entry point & main menu
├── lib/
│   ├── json.lua          # JSON encode/decode
│   ├── shell.lua         # Shell command helpers
│   ├── ui.lua            # TUI components
│   ├── config.lua        # Config management
│   ├── device.lua        # Device & package management
│   ├── monitor.lua       # Auto rejoin engine
│   ├── cookie.lua        # Cookie injection
│   └── api.lua           # API interface
├── config.json           # User config (auto-generated, outside repo)
└── README.md             # This file
```

## ⚠️ Security Notes

1. **JANGAN SHARE** file `config.json` — berisi cookie yang bisa dipakai login
2. Cookie `.ROBLOSECURITY` = password. Siapapun yang punya bisa login.
3. Ganti password Roblox secara berkala

## 🔄 Roadmap

- [ ] Web panel integration (kontrol dari browser/laptop)
- [ ] Agent system (cloud phone jadi agent, kontrol remote)
- [ ] Discord bot integration
- [ ] Auto cookie rotation
- [ ] Multi-device management

---

**Disclaimer**: Tool ini untuk keperluan personal. Gunakan dengan bijak.
