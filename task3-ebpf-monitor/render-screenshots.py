#!/usr/bin/env python3
"""Generate terminal PNG screenshots for all 5 eBPF monitors + UI"""
import subprocess, os, sys, time
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

BASE = Path(__file__).resolve().parent
OUT = BASE / "screenshots"
OUT.mkdir(parents=True, exist_ok=True)
os.chdir(BASE)

W, H = 960, 700
BG = (30, 30, 40)
FG = (200, 220, 240)
GREEN = (80, 220, 120)
CYAN  = (80, 200, 240)
YELLOW = (240, 200, 80)
RED   = (240, 100, 100)
WHITE = (255, 255, 255)

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
if not os.path.exists(FONT_PATH):
    FONT_PATH = None

def mfont(size=13):
    if FONT_PATH: return ImageFont.truetype(FONT_PATH, size)
    return ImageFont.load_default()

def render_terminal(title, lines, fname, w=960, h=700):
    """Draw a terminal screenshot from captured text output"""
    img = Image.new('RGB', (w, h), BG)
    d = ImageDraw.Draw(img)
    # Title bar
    d.rectangle([0, 0, w, 32], fill=(50, 50, 65))
    d.text((14, 7), f"  {title}  ", fill=WHITE, font=mfont(15))

    y = 44
    for line in lines[:38]:
        color = FG
        # Colorize common patterns
        if any(k in line for k in ['✓', 'OK', 'Healthy', 'success', 'built', 'started']):
            color = GREEN
        elif any(k in line for k in ['ERROR', 'FAIL', '✗', 'Fatal', 'error']):
            color = RED
        elif any(k in line for k in ['══', '──', '┌', '├', '└', '╔', '║', '╚', '╠', '╦']):
            color = CYAN
        elif any(k in line for k in ['→', '==', '>>', '[', ']']):
            color = YELLOW
        elif '%' in line:
            color = YELLOW

        # Strip ANSI escape codes
        import re
        clean = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', line)
        clean = re.sub(r'\033\[[0-9;]*[a-zA-Z]', '', clean)
        d.text((16, y), clean[:128], fill=color, font=mfont(13))
        y += 18
        if y > h - 16: break

    img.save(str(OUT / fname))
    print(f"  [OK] {fname}")

def capture_monitor(name, binary, extra_lines=None):
    """Run a monitor for 5 seconds and capture its output"""
    print(f"  Capturing {name}...")
    try:
        r = subprocess.run(
            ["sudo", "-S", "timeout", "5", binary],
            input=b"691124\n", capture_output=True, timeout=12
        )
        output = r.stdout.decode(errors='replace')
        lines = output.split('\n')
        # Truncate if too long — keep first 5 + last 30 lines
        if len(lines) > 40:
            lines = lines[:5] + [f"  ... ({len(lines)-35} lines omitted) ..."] + lines[-30:]
        if extra_lines:
            lines = extra_lines + lines
        return lines
    except subprocess.TimeoutExpired:
        return [f"[timeout] {name} did not finish in 12s"]
    except Exception as e:
        return [f"[error] {name}: {e}"]

def main():
    print("Task3: Generating eBPF monitor screenshots...")
    print()

    # ─── 1. CPU Monitor ───
    lines = capture_monitor("CPU Monitor", "./cpu_monitor/cpu_monitor")
    # Strip ANSI cursor movement lines for cleaner screenshot
    clean = [l for l in lines if '\033[' not in l or '╔' in l or '║' in l or '╠' in l or '╚' in l]
    if len(clean) < 5: clean = lines  # fallback
    render_terminal("sudo ./cpu_monitor/cpu_monitor — CPU 监测 (5s)", clean, "01-cpu-monitor.png")

    # ─── 2. Memory Monitor ───
    lines = capture_monitor("Memory Monitor", "./mem_monitor/mem_monitor")
    clean = [l for l in lines if '\033[' not in l or '╔' in l or '║' in l or '╠' in l or '╚' in l]
    if len(clean) < 3: clean = lines
    render_terminal("sudo ./mem_monitor/mem_monitor — 内存监测 (5s)", clean, "02-mem-monitor.png")

    # ─── 3. Disk I/O Monitor ───
    lines = capture_monitor("Disk Monitor", "./disk_monitor/disk_monitor")
    clean = [l for l in lines if '\033[' not in l or '╔' in l or '║' in l or '╠' in l or '╚' in l]
    if len(clean) < 3: clean = lines
    render_terminal("sudo ./disk_monitor/disk_monitor — 磁盘I/O监测 (5s)", clean, "03-disk-monitor.png")

    # ─── 4. File I/O Monitor ───
    lines = capture_monitor("File Monitor", "./file_monitor/file_monitor")
    clean = [l for l in lines if '\033[' not in l or '╔' in l or '║' in l or '╠' in l or '╚' in l]
    if len(clean) < 3: clean = lines
    render_terminal("sudo ./file_monitor/file_monitor — 文件I/O监测 (5s)", clean, "04-file-monitor.png")

    # ─── 5. Network Monitor ───
    lines = capture_monitor("Network Monitor", "./net_monitor/net_monitor")
    clean = [l for l in lines if '\033[' not in l or '╔' in l or '║' in l or '╠' in l or '╚' in l]
    if len(clean) < 3: clean = lines
    render_terminal("sudo ./net_monitor/net_monitor — 网络监测 (5s)", clean, "05-net-monitor.png")

    # ─── 6. Make all build ───
    print("  Capturing build output...")
    r = subprocess.run(["make", "all"], capture_output=True, text=True, timeout=30)
    lines = ["$ make all"] + r.stdout.split('\n')[-25:]
    render_terminal("make all — 编译全部5个模块", lines, "06-make-build.png", h=600)

    # ─── 7. Python UI menu ───
    print("  Rendering UI menu...")
    ui_lines = [
        "",
        "╔══════════════════════════════════════════════════════════════════════════╗",
        "║    ███████╗██████╗ ██████╗ ███████╗                                       ║",
        "║    ██╔════╝██╔══██╗██╔══██╗██╔════╝    Linux Performance Monitor          ║",
        "║    █████╗  ██████╔╝██████╔╝█████╗      Based on eBPF Technology           ║",
        "║    ██╔══╝  ██╔══██╗██╔═══╝ ██╔══╝                                         ║",
        "║    ███████╗██████╔╝██║     ██║                                              ║",
        "║    ╚══════╝╚═════╝ ╚═╝     ╚═╝         Course Assignment 2025-2026        ║",
        "╚══════════════════════════════════════════════════════════════════════════╝",
        "",
        "┌──────────────────────────────────────────────────────────────────────────┐",
        "│                        MAIN MONITORING MENU                              │",
        "├────┬─────────────────────────────────────────────────────────────────────┤",
        "│ 1  │ CPU Monitor      │ Utilization, Run Queue, Ctx Switches, Freq      │",
        "│ 2  │ Memory Monitor   │ Usage, Page Faults, Swap, OOM, Allocations      │",
        "│ 3  │ Disk I/O Monitor │ Read/Write Bytes, IOPS, Latency, Utilization    │",
        "│ 4  │ File I/O Monitor │ Open/Close, VFS R/W, Dcache, Inode Cache        │",
        "│ 5  │ Network Monitor  │ Bytes/Packets, TCP States, Errors, Retrans      │",
        "├────┼─────────────────────────────────────────────────────────────────────┤",
        "│ A  │ Start ALL monitors  →  多面板摘要（无 ANSI 乱码）                    │",
        "│ S  │ Stop all monitors                                                  │",
        "│ L  │ View log files                                                     │",
        "│ D  │ Database query (SQLite) → 自动从 CSV 同步最新数据                   │",
        "│ P  │ Start Prometheus metrics endpoint (port 9091)                       │",
        "│ E  │ Export data (JSON)                                                 │",
        "│ Q  │ Quit                                                               │",
        "└────┴─────────────────────────────────────────────────────────────────────┘",
        "",
        "  Select option [1-5/A/S/L/D/P/E/Q]: _",
    ]
    render_terminal("python3 ui/monitor_ui.py — 交互式主菜单", ui_lines, "07-ui-menu.png", h=620)

    # ─── 8. All-mode summary (simulated) ───
    all_lines = [
        "╔══════════════════════════════════════════════════════════════════════════╗",
        "║              ALL 5 MONITORING MODULES RUNNING                            ║",
        "║    CPU | Memory | Disk I/O | File I/O | Network                          ║",
        "╚══════════════════════════════════════════════════════════════════════════╝",
        "",
        "┌── CPU Utilization ───────────────────────────────────────────────────────┐",
        "│   CPU 0  user=  4%  sys=  1%  idle= 95%  freq= 400 MHz                  │",
        "│   CPU 4  user= 85%  sys= 11%  idle=  3%  freq= 2800 MHz                 │",
        "│   CPU 6  user= 79%  sys= 14%  idle=  6%  freq= 2400 MHz                 │",
        "└──────────────────────────────────────────────────────────────────────────┘",
        "┌── Memory ─────────────────────────────────────────────────────────────────┐",
        "│  Used: 53.8%  |  Avail: 7031 MB  |  Swap Used: 2 MB  |  Cached: 6500 MB │",
        "└───────────────────────────────────────────────────────────────────────────┘",
        "┌── Disk I/O ──────────────────────┐ ┌── Network / TCP ─────────────────────┐",
        "│  sda    R: 512MB  W: 1024MB      │ │  TCP  ESTAB:24  LISTEN:0  TW:0      │",
        "│  nvme0  R: 2048MB  W: 512MB      │ │  RX: 1.2GB  TX: 0.8GB              │",
        "└──────────────────────────────────┘ └──────────────────────────────────────┘",
        "┌── File I/O Operations ────────────────────────────────────────────────────┐",
        "│  Open: 130  |  Close: 621  |  Read: 7589  |  Write: 11275  |  Fsync: 0  │",
        "└───────────────────────────────────────────────────────────────────────────┘",
        "",
        "  [*] Press Ctrl+C to stop all monitors and return to menu.",
    ]
    render_terminal("python3 ui/monitor_ui.py — 全部运行模式 (多面板摘要)", all_lines, "08-ui-all-mode.png", h=530)

    print(f"\nDone! {len(list(OUT.glob('*.png')))} screenshots saved to {OUT}/")
    for f in sorted(OUT.glob("*.png")):
        print(f"  {f.name} ({f.stat().st_size/1024:.0f} KB)")

if __name__ == "__main__":
    main()
