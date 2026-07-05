#!/usr/bin/env python3
"""
eBPF Linux Performance Monitor - Interactive UI
================================================
Main entry point - provides interactive menu-driven interface
to launch and monitor all 5 eBPF performance tools.

Features:
- Real-time display of CPU, Memory, Disk, File, Network metrics
- Interactive menu navigation
- File-based data storage with optimization
- JSON/CSV export
- Prometheus metrics endpoint (bonus)
- SQLite database storage (bonus)
"""

import os
import sys
import time
import signal
import subprocess
import threading
import json
import sqlite3
import csv
from datetime import datetime
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler

# ===== Configuration =====
BASE_DIR = Path(__file__).resolve().parent.parent
LOG_DIR = BASE_DIR / "log"
DB_PATH = BASE_DIR / "storage" / "ebpf_monitor.db"
PROMETHEUS_PORT = 9091

# Module definitions
MODULES = {
    "1": {
        "name": "CPU Monitor",
        "binary": BASE_DIR / "cpu_monitor" / "cpu_monitor",
        "desc": "CPU utilization, run queue, context switches, frequency",
        "indicators": [
            ("CPU利用率", "Per-core user/system/idle/iowait %"),
            ("运行队列长度", "Scheduler run queue depth"),
            ("上下文切换率", "Context switches per second"),
            ("CPU频率", "Current CPU frequency (MHz)"),
            ("空闲状态", "CPU idle state time distribution"),
        ]
    },
    "2": {
        "name": "Memory Monitor",
        "binary": BASE_DIR / "mem_monitor" / "mem_monitor",
        "desc": "Memory usage, page faults, swap, OOM, allocation rate",
        "indicators": [
            ("内存使用率", "Total/Used/Free/Cached/Buffer memory"),
            ("页面错误率", "Major and minor page faults per second"),
            ("Swap使用", "Swap in/out activity"),
            ("OOM事件", "Out of memory kill events"),
            ("内存分配率", "kmalloc allocation rate by process"),
        ]
    },
    "3": {
        "name": "Disk I/O Monitor",
        "binary": BASE_DIR / "disk_monitor" / "disk_monitor",
        "desc": "Disk read/write bytes, IOPS, latency, utilization",
        "indicators": [
            ("磁盘读写字节", "Read/write bytes per second per disk"),
            ("IOPS", "I/O operations per second"),
            ("I/O延迟", "Average I/O latency (microseconds)"),
            ("磁盘利用率", "Disk busy/utilization percentage"),
            ("队列深度", "I/O request queue depth"),
        ]
    },
    "4": {
        "name": "File I/O Monitor",
        "binary": BASE_DIR / "file_monitor" / "file_monitor",
        "desc": "File open/close, VFS read/write, cache performance",
        "indicators": [
            ("文件打开/关闭", "Open and close operation counts"),
            ("VFS读写", "Virtual filesystem read/write operations"),
            ("目录缓存", "Dentry cache hits/misses"),
            ("Inode缓存", "Inode cache hits/misses"),
            ("Fsync操作", "File synchronization operations"),
        ]
    },
    "5": {
        "name": "Network Monitor",
        "binary": BASE_DIR / "net_monitor" / "net_monitor",
        "desc": "Network bytes/packets, TCP states, errors, retransmissions",
        "indicators": [
            ("网络收发字节", "Bytes sent/received per interface"),
            ("网络数据包", "Packets sent/received per interface"),
            ("TCP连接状态", "TCP connections by state (ESTAB, LISTEN, etc.)"),
            ("网络错误/丢包", "TX/RX errors and dropped packets"),
            ("TCP重传率", "TCP segment retransmission rate"),
        ]
    },
}

running_processes = {}

# ===== Prometheus Metrics (Bonus) =====
class PrometheusMetrics:
    """Thread-safe prometheus metrics store"""
    def __init__(self):
        self._metrics = {}
        self._lock = threading.Lock()

    def set(self, name, value, labels=None):
        with self._lock:
            key = (name, json.dumps(labels or {}))
            self._metrics[key] = value

    def get_all(self):
        with self._lock:
            result = []
            for (name, label_json), value in self._metrics.items():
                labels = json.loads(label_json)
                label_str = ",".join(f'{k}="{v}"' for k, v in labels.items())
                if label_str:
                    result.append(f"{name}{{{label_str}}} {value}")
                else:
                    result.append(f"{name} {value}")
            return result

prom_metrics = PrometheusMetrics()

class PrometheusHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            metrics = prom_metrics.get_all()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write("\n".join(metrics).encode())
            self.wfile.write(b"\n")
        elif self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress logs

# ===== SQLite Database Storage (Bonus) =====
class DatabaseStorage:
    def __init__(self, db_path):
        os.makedirs(os.path.dirname(db_path), exist_ok=True)
        self.conn = sqlite3.connect(db_path, check_same_thread=False)
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("PRAGMA synchronous=NORMAL")
        self._create_tables()

    def _create_tables(self):
        self.conn.execute("""
            CREATE TABLE IF NOT EXISTS metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                module TEXT NOT NULL,
                metric_name TEXT NOT NULL,
                cpu_id INTEGER DEFAULT 0,
                pid INTEGER DEFAULT 0,
                comm TEXT DEFAULT '',
                value1 REAL DEFAULT 0,
                value2 REAL DEFAULT 0,
                value3 REAL DEFAULT 0,
                label TEXT DEFAULT '',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        self.conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_metrics_module
            ON metrics(module, timestamp)
        """)
        self.conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_metrics_timestamp
            ON metrics(timestamp)
        """)
        self.conn.commit()

    def insert(self, timestamp, module, metric_name, cpu_id=0,
               pid=0, comm="", value1=0, value2=0, value3=0, label=""):
        self.conn.execute("""
            INSERT INTO metrics (timestamp, module, metric_name, cpu_id, pid, comm,
                                value1, value2, value3, label)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (timestamp, module, metric_name, cpu_id, pid, comm,
              value1, value2, value3, label))
        self.conn.commit()

    def query(self, module=None, limit=100):
        if module:
            return self.conn.execute(
                "SELECT * FROM metrics WHERE module=? ORDER BY timestamp DESC LIMIT ?",
                (module, limit)).fetchall()
        return self.conn.execute(
            "SELECT * FROM metrics ORDER BY timestamp DESC LIMIT ?",
            (limit,)).fetchall()

    def close(self):
        self.conn.close()

db = None
collector = None

# ===== Metrics Collector: CSV → SQLite + Prometheus (Background) =====
class MetricsCollector:
    """Background thread that syncs CSV log data to SQLite and Prometheus"""
    def __init__(self, database=None):
        self.running = False
        self.thread = None
        self._csv_positions = {}  # filename → last read byte offset
        self._db = database       # explicit DB reference

    def start(self):
        if self.running:
            return
        self.running = True
        self.thread = threading.Thread(target=self._collect_loop, daemon=True)
        self.thread.start()
        print("[+] Metrics collector started (CSV→SQLite, CSV→Prometheus)")

    def stop(self):
        self.running = False
        if self.thread:
            self.thread.join(timeout=2)
        print("[*] Metrics collector stopped")

    def _collect_loop(self):
        while self.running:
            try:
                self._sync_all_csvs()
            except Exception as e:
                pass  # silent — CSV files may be mid-write
            time.sleep(1)

    def _sync_all_csvs(self):
        if not LOG_DIR.exists():
            return
        for csv_file in sorted(LOG_DIR.glob("*_current.csv")):
            self._sync_one_csv(csv_file)
        self._cleanup_old_positions()

    def _sync_one_csv(self, csv_path):
        module_name = csv_path.name.replace("_current.csv", "").replace("_monitor", "")
        path_str = str(csv_path)
        last_pos = self._csv_positions.get(path_str, 0)
        try:
            size = csv_path.stat().st_size
            if size <= last_pos:
                return
            with open(csv_path, 'r') as f:
                f.seek(last_pos)
                # Skip header if reading from beginning
                if last_pos == 0:
                    header = f.readline()
                    last_pos = f.tell()
                reader = csv.reader(f)
                new_entries = []
                for row in reader:
                    if len(row) >= 8:
                        new_entries.append(row)
                        if len(new_entries) >= 100:  # batch insert
                            self._insert_batch(module_name, new_entries)
                            new_entries = []
                if new_entries:
                    self._insert_batch(module_name, new_entries)
                self._csv_positions[path_str] = f.tell()
        except Exception:
            pass  # file may be locked mid-write

    def _insert_batch(self, module_name, rows):
        if self._db is None:
            return
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        for row in rows:
            try:
                ts     = row[0] if len(row) > 0 else now
                metric = row[2] if len(row) > 2 else "unknown"
                cpu_id = int(row[3]) if len(row) > 3 and row[3].isdigit() else 0
                pid    = int(row[4]) if len(row) > 4 and row[4].isdigit() else 0
                comm   = row[5] if len(row) > 5 else ""
                v1     = float(row[6]) if len(row) > 6 and row[6].replace('.','',1).replace('-','',1).isdigit() else 0
                v2     = float(row[7]) if len(row) > 7 and row[7].replace('.','',1).replace('-','',1).isdigit() else 0
                v3     = float(row[8]) if len(row) > 8 and row[8].replace('.','',1).replace('-','',1).isdigit() else 0
                label  = row[9] if len(row) > 9 else ""
                self._db.insert(ts, module_name, metric, cpu_id, pid, comm, v1, v2, v3, label)

                # Also update Prometheus
                pname = f"{module_name.lower()}_{metric}".replace(' ', '_')
                prom_metrics.set(pname, v1)
                if v2 != 0:
                    prom_metrics.set(f"{pname}_value2", v2)
            except (ValueError, IndexError):
                continue

    def _cleanup_old_positions(self):
        existing = set(str(p) for p in LOG_DIR.glob("*_current.csv")) if LOG_DIR.exists() else set()
        for path in list(self._csv_positions.keys()):
            if path not in existing:
                del self._csv_positions[path]

    def sync_now(self):
        """Force immediate sync (called before DB query)"""
        try:
            self._sync_all_csvs()
        except Exception:
            pass

# ===== File Storage with Optimization =====
def init_storage():
    os.makedirs(LOG_DIR, exist_ok=True)
    os.makedirs(BASE_DIR / "storage", exist_ok=True)

def write_csv_log(module, data):
    """Write to CSV log with rotation"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_file = LOG_DIR / f"{module}_current.csv"

    # Check rotation (100MB limit)
    try:
        if log_file.exists() and log_file.stat().st_size > 100 * 1024 * 1024:
            import gzip
            new_name = LOG_DIR / f"{module}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
            log_file.rename(new_name)
            # Compress old file
            with open(new_name, 'rb') as f_in:
                with gzip.open(str(new_name) + '.gz', 'wb') as f_out:
                    f_out.write(f_in.read())
            new_name.unlink()
            print(f"[STORAGE] File rotated and compressed: {new_name}.gz")

            # Cleanup old files (>7 days)
            import subprocess
            subprocess.run(
                f"find '{LOG_DIR}' -name '*.gz' -mtime +7 -delete",
                shell=True, capture_output=True
            )
    except Exception as e:
        print(f"[STORAGE] Rotation error: {e}")

    with open(log_file, 'a', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([timestamp] + list(data))

# ===== UI Functions =====
def clear_screen():
    os.system('clear' if os.name == 'posix' else 'cls')

def print_banner():
    print("""
╔══════════════════════════════════════════════════════════════════════════╗
║                                                                          ║
║    ███████╗██████╗ ██████╗ ███████╗                                       ║
║    ██╔════╝██╔══██╗██╔══██╗██╔════╝    Linux Performance Monitor          ║
║    █████╗  ██████╔╝██████╔╝█████╗      Based on eBPF Technology           ║
║    ██╔══╝  ██╔══██╗██╔═══╝ ██╔══╝      Kernel Version: {kernel}      ║
║    ███████╗██████╔╝██║     ██║                                              ║
║    ╚══════╝╚═════╝ ╚═╝     ╚═╝         Course Assignment 2025-2026        ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
""".format(kernel=os.uname().release))

def print_main_menu():
    print("""
┌──────────────────────────────────────────────────────────────────────────┐
│                        MAIN MONITORING MENU                              │
├────┬─────────────────────────────────────────────────────────────────────┤
│ 1  │ CPU Monitor      │ Utilization, Run Queue, Ctx Switches, Freq      │
│ 2  │ Memory Monitor   │ Usage, Page Faults, Swap, OOM, Allocations      │
│ 3  │ Disk I/O Monitor │ Read/Write Bytes, IOPS, Latency, Utilization    │
│ 4  │ File I/O Monitor │ Open/Close, VFS R/W, Dcache, Inode Cache        │
│ 5  │ Network Monitor  │ Bytes/Packets, TCP States, Errors, Retrans      │
├────┼─────────────────────────────────────────────────────────────────────┤
│ A  │ Start ALL monitors                                                 │
│ S  │ Stop all monitors                                                  │
│ L  │ View log files                                                     │
│ D  │ Database query (SQLite)                                            │
│ P  │ Start Prometheus metrics endpoint (port {port})                     │
│ E  │ Export data (JSON)                                                 │
│ Q  │ Quit                                                               │
└────┴─────────────────────────────────────────────────────────────────────┘
""".format(port=PROMETHEUS_PORT))

def print_module_info(module_key):
    mod = MODULES[module_key]
    print(f"""
┌─────────────────────────────────────────────────────────────────────┐
│ {mod['name']} - Key Performance Indicators                              │
├─────────────────────────────────────────────────────────────────────┤
""")
    for i, (name, desc) in enumerate(mod['indicators'], 1):
        print(f"│ {i}. {name:<25s} {desc:<42s} │")
    print("└─────────────────────────────────────────────────────────────────────┘")

def run_module(module_key):
    """Run a single monitoring module"""
    global collector
    mod = MODULES[module_key]
    binary = str(mod['binary'])

    if not os.path.exists(binary):
        print(f"[ERROR] Binary not found: {binary}")
        print("        Please run './setup.sh' first to build the project.")
        return

    # Auto-start metrics collector
    if collector is None:
        collector = MetricsCollector(db)
    collector.start()

    clear_screen()
    print_module_info(module_key)
    print(f"\n[*] Starting {mod['name']}...")
    print("[*] Press Ctrl+C to stop and return to menu.\n")
    print("-" * 70)

    try:
        proc = subprocess.Popen(
            [binary],
            cwd=str(BASE_DIR),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )
        running_processes[module_key] = proc
        for line in proc.stdout:
            print(line, end='')
    except KeyboardInterrupt:
        pass
    finally:
        if module_key in running_processes:
            running_processes[module_key].terminate()
            try:
                running_processes[module_key].wait(timeout=3)
            except subprocess.TimeoutExpired:
                running_processes[module_key].kill()
            del running_processes[module_key]
        time.sleep(0.5)

def run_all_modules():
    """Start all 5 monitoring modules, show clean Python summary screen"""
    global collector

    # Auto-start collector
    if collector is None:
        collector = MetricsCollector(db)
    collector.start()

    clear_screen()
    print("""
╔══════════════════════════════════════════════════════════════════════════╗
║              ALL 5 MONITORING MODULES RUNNING                            ║
║    CPU | Memory | Disk I/O | File I/O | Network                          ║
╚══════════════════════════════════════════════════════════════════════════╝
[*] Press Ctrl+C to stop all monitors and return to menu.
""")

    # Start all monitors with stdout/stderr suppressed (CSV logging only)
    for key in ["1", "2", "3", "4", "5"]:
        mod = MODULES[key]
        binary = str(mod['binary'])
        if not os.path.exists(binary):
            print(f"  [SKIP] {mod['name']}: binary not found")
            continue
        try:
            proc = subprocess.Popen(
                [binary],
                cwd=str(BASE_DIR),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            running_processes[key] = proc
            print(f"  [OK] {mod['name']} started (PID={proc.pid})")
        except Exception as e:
            print(f"  [FAIL] {mod['name']}: {e}")
    print()

    # Display clean summary from CSVs, refreshed every second
    try:
        while any(proc.poll() is None for proc in running_processes.values()):
            _display_summary_screen()
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        print("\n[*] Stopping all monitors...")
        for key, proc in list(running_processes.items()):
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
        running_processes.clear()
        print("[*] All monitors stopped.")


def _display_summary_screen():
    """Read latest CSV data and display a clean multi-module summary"""
    import re

    def read_csv_tail(path, n=1):
        """Read last n data lines from a CSV file"""
        if not path.exists():
            return []
        try:
            with open(path) as f:
                lines = f.readlines()
                # Return last n data lines (skip header)
                data = [l.strip() for l in lines if l.strip() and not l.startswith('timestamp,')]
                return data[-n:] if data else []
        except Exception:
            return []

    def extract_value(row, idx, default="?"):
        parts = row.split(',')
        return parts[idx] if idx < len(parts) else default

    # Move cursor to just below the banner
    print("\033[7;0H\033[J")  # clear from line 7 down

    # ── CPU ──
    cpu_data = read_csv_tail(LOG_DIR / "cpu_monitor_current.csv", 3)
    print("┌── CPU Utilization ───────────────────────────────────────────────────────┐")
    if cpu_data:
        for row in cpu_data:
            ts = extract_value(row, 0, "")[-8:]  # time only
            cpu = extract_value(row, 3, "?")
            label = extract_value(row, 9, "")
            # Parse label for percentages
            user_m = re.search(r'user=([\d.]+)', label)
            sys_m  = re.search(r'sys=([\d.]+)', label)
            idle_m = re.search(r'idle=([\d.]+)', label)
            user_s = f"{float(user_m.group(1)):.0f}%" if user_m else "?"
            sys_s  = f"{float(sys_m.group(1)):.0f}%" if sys_m else "?"
            idle_s = f"{float(idle_m.group(1)):.0f}%" if idle_m else "?"
            print(f"│  {ts}  CPU{cpu:>3}  user={user_s:>4}  sys={sys_s:>4}  idle={idle_s:>4}                              │")
    else:
        print("│  (waiting for data...)                                                    │")
    print("└───────────────────────────────────────────────────────────────────────────┘")

    # ── Memory ──
    mem_data = read_csv_tail(LOG_DIR / "mem_monitor_current.csv", 1)
    print("┌── Memory ─────────────────────────────────────────────────────────────────┐")
    if mem_data:
        row = mem_data[-1]
        label = extract_value(row, 9, "")
        used_m = re.search(r'used_pct=([\d.]+)', label)
        used_s = f"{float(used_m.group(1)):.1f}%" if used_m else "?"
        avail = extract_value(row, 7, "?")
        swap  = extract_value(row, 8, "?")
        print(f"│  Used: {used_s:>6}  |  Avail: {avail:>5} MB  |  Swap Used: {swap:>5} MB                         │")
    else:
        print("│  (waiting for data...)                                                    │")
    print("└───────────────────────────────────────────────────────────────────────────┘")

    # ── Disk + Network side by side ──
    disk_data = read_csv_tail(LOG_DIR / "disk_monitor_current.csv", 2)
    net_data  = read_csv_tail(LOG_DIR / "net_monitor_current.csv", 1)
    print("┌── Disk I/O ──────────────────────┐ ┌── Network / TCP ─────────────────────┐")
    if disk_data:
        row = disk_data[-1]
        dev  = extract_value(row, 5, "?")
        r_mb = extract_value(row, 6, "?")
        w_mb = extract_value(row, 7, "?")
        ios  = extract_value(row, 8, "?")
        print(f"│  {dev:<8} R:{r_mb:>5}MB W:{w_mb:>5}MB  │ │", end="")
    else:
        print("│  (waiting...)                     │ │", end="")
    if net_data:
        row = net_data[-1]
        label = extract_value(row, 9, "")
        est_m = re.search(r'ESTAB=(\d+)', label)
        lst_m = re.search(r'LISTEN=(\d+)', label)
        tw_m  = re.search(r'TW=(\d+)', label)
        est_s = est_m.group(1) if est_m else "?"
        lst_s = lst_m.group(1) if lst_m else "?"
        tw_s  = tw_m.group(1) if tw_m else "?"
        print(f" TCP  ESTAB:{est_s:>3}  LISTEN:{lst_s:>3}  TW:{tw_s:>3}    │")
    else:
        print(f" (waiting...)                         │")
    print("└───────────────────────────────────┘ └──────────────────────────────────────┘")

    # ── File I/O ──
    file_data = read_csv_tail(LOG_DIR / "file_monitor_current.csv", 1)
    print("┌── File I/O Operations ────────────────────────────────────────────────────┐")
    if file_data:
        row = file_data[-1]
        label = extract_value(row, 9, "")
        open_m  = re.search(r'open=(\d+)', label)
        close_m = re.search(r'close=(\d+)', label)
        read_m  = re.search(r'read=(\d+)', label)
        write_m = re.search(r'write=(\d+)', label)
        open_s  = open_m.group(1) if open_m else "?"
        close_s = close_m.group(1) if close_m else "?"
        read_s  = read_m.group(1) if read_m else "?"
        write_s = write_m.group(1) if write_m else "?"
        print(f"│  Open: {open_s:>8}  |  Close: {close_s:>8}  |  Read: {read_s:>8}  |  Write: {write_s:>8}   │")
    else:
        print("│  (waiting for data...)                                                    │")
    print("└───────────────────────────────────────────────────────────────────────────┘")
    sys.stdout.flush()

def view_logs():
    """View stored log files"""
    clear_screen()
    print("\n┌─────────────────────────────────────────────────────────────────────┐")
    print("│                        LOG FILES                                    │")
    print("├─────────────────────────────────────────────────────────────────────┤")

    log_files = sorted(LOG_DIR.glob("*_current.csv")) if LOG_DIR.exists() else []
    if not log_files:
        print("│  No log files found. Run monitors first.                           │")
    else:
        for lf in log_files:
            size_mb = lf.stat().st_size / (1024 * 1024) if lf.exists() else 0
            name = lf.name.replace("_current.csv", "")
            print(f"│  {name:<20s} {size_mb:>8.2f} MB                                │")
            # Show last 3 lines
            try:
                with open(lf) as f:
                    lines = f.readlines()
                    for line in lines[-3:]:
                        print(f"│    {line.strip()[:65]:<65s} │")
            except Exception:
                pass
    print("└─────────────────────────────────────────────────────────────────────┘")

def database_query():
    """Query SQLite database (sync from CSV first)"""
    global db, collector
    if db is None:
        print("[INFO] Database not initialized.")
        return

    # Force CSV→SQLite sync before querying
    if collector:
        collector.sync_now()
    elif LOG_DIR.exists():
        # One-shot sync if collector not running
        collector = MetricsCollector(db)
        collector.sync_now()

    clear_screen()
    print("\n┌──────────────────────────────────────────────────────────────────────────┐")
    print("│                   DATABASE QUERY (Recent 20 entries)                     │")
    print("├──────────────────────────────────────────────────────────────────────────┤")
    try:
        rows = db.query(limit=20)
        if not rows:
            print("│  No data in database.                                              │")
        else:
            for row in rows:
                try:
                    v1 = float(row[6]) if row[6] is not None else 0.0
                    v2 = float(row[7]) if row[7] is not None else 0.0
                except (ValueError, TypeError):
                    v1, v2 = 0.0, 0.0
                print(f"│  {str(row[1]):<20s} {str(row[2]):<12s} {str(row[3]):<15s} v1={v1:<10.1f} v2={v2:<10.1f} │")
    except Exception as e:
        print(f"│  Query error: {e}")
    print("└─────────────────────────────────────────────────────────────────────┘")

def export_json():
    """Export all log data to JSON"""
    import json
    clear_screen()
    print("\n[*] Exporting log data to JSON...")
    export_path = BASE_DIR / "storage" / f"export_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"

    all_data = {}
    for lf in LOG_DIR.glob("*_current.csv") if LOG_DIR.exists() else []:
        module_name = lf.name.replace("_current.csv", "")
        module_data = []
        try:
            with open(lf) as f:
                reader = csv.reader(f)
                header = next(reader, None)
                for row in reader:
                    module_data.append(dict(zip(header, row)) if header else list(row))
        except Exception as e:
            module_data = [{"error": str(e)}]
        all_data[module_name] = module_data

    with open(export_path, 'w') as f:
        json.dump(all_data, f, indent=2, ensure_ascii=False)

    size = os.path.getsize(export_path)
    print(f"[+] Data exported to: {export_path}")
    print(f"[+] Total size: {size / 1024:.1f} KB")

def start_prometheus():
    """Start Prometheus metrics HTTP endpoint"""
    global db
    clear_screen()
    print(f"""
╔══════════════════════════════════════════════════════════════════════════╗
║                PROMETHEUS METRICS ENDPOINT                               ║
║                                                                          ║
║  Endpoint: http://localhost:{PROMETHEUS_PORT}/metrics                                ║
║  Health:   http://localhost:{PROMETHEUS_PORT}/health                                 ║
║                                                                          ║
║  Add this to your prometheus.yml:                                        ║
║    scrape_configs:                                                       ║
║      - job_name: 'ebpf_monitor'                                          ║
║        static_configs:                                                   ║
║          - targets: ['localhost:{PROMETHEUS_PORT}']                                  ║
║                                                                          ║
║  Press Ctrl+C to stop the metrics endpoint.                              ║
╚══════════════════════════════════════════════════════════════════════════╝
""".format(port=PROMETHEUS_PORT))

    server = HTTPServer(('0.0.0.0', PROMETHEUS_PORT), PrometheusHandler)
    print(f"[*] Prometheus metrics server started on port {PROMETHEUS_PORT}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        print("\n[*] Prometheus metrics server stopped.")

# ===== Main Entry Point =====
def main():
    global db, collector

    init_storage()

    # Initialize database (bonus)
    try:
        db = DatabaseStorage(DB_PATH)
        print(f"[+] SQLite database initialized: {DB_PATH}")
    except Exception as e:
        print(f"[!] Database initialization failed: {e}")

    # Initialize metrics collector
    collector = MetricsCollector(db)

    signal.signal(signal.SIGINT, signal.SIG_IGN)  # Let subprocesses handle it

    while True:
        clear_screen()
        print_banner()
        print_main_menu()

        choice = input("  Select option [1-5/A/S/L/D/P/E/Q]: ").strip().upper()

        if choice in MODULES:
            run_module(choice)
        elif choice == 'A':
            run_all_modules()
        elif choice == 'S':
            for key, proc in list(running_processes.items()):
                print(f"[*] Stopping {MODULES[key]['name']}...")
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
            running_processes.clear()
            print("[*] All monitors stopped.")
            time.sleep(1)
        elif choice == 'L':
            view_logs()
            input("\n  Press Enter to continue...")
        elif choice == 'D':
            database_query()
            input("\n  Press Enter to continue...")
        elif choice == 'P':
            start_prometheus()
        elif choice == 'E':
            export_json()
            input("\n  Press Enter to continue...")
        elif choice == 'Q':
            # Cleanup
            if collector:
                collector.stop()
            for proc in running_processes.values():
                proc.terminate()
            if db:
                db.close()
            print("\n[*] Goodbye!")
            break
        else:
            print(f"\n[!] Invalid option: {choice}")
            time.sleep(0.5)

if __name__ == "__main__":
    main()
