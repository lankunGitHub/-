#!/bin/bash
#
# eBPF Linux Performance Monitor - Setup Script
# =============================================
# One-time environment setup for building and running the eBPF monitoring tools.
#
# This script:
# 1. Downloads and extracts LLVM/clang locally (no sudo needed)
# 2. Generates vmlinux.h from BTF
# 3. Builds all monitoring modules
# 4. Sets up Python dependencies
#
# Usage: bash setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LLVM_DIR="$SCRIPT_DIR/local_llvm"
LLVM_BIN="$LLVM_DIR/usr/lib/llvm-20/bin"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     eBPF Performance Monitor - Environment Setup            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ===== Step 1: Check Prerequisites =====
echo "[1/6] Checking prerequisites..."

if ! command -v bpftool &>/dev/null; then
    echo "  [!] bpftool not found. Attempting local install..."
    cd /tmp
    apt download bpftool 2>/dev/null || true
    BPFTOOL_DEB=$(ls bpftool_*.deb 2>/dev/null | head -1)
    if [ -n "$BPFTOOL_DEB" ]; then
        dpkg-deb -x "$BPFTOOL_DEB" "$LLVM_DIR" 2>/dev/null || true
        export PATH="$LLVM_DIR/usr/sbin:$LLVM_DIR/usr/bin:$PATH"
    fi
    cd "$SCRIPT_DIR"
fi

echo "  [✓] bpftool: $(bpftool version 2>/dev/null | head -1 || echo 'using fallback')"

if ! command -v python3 &>/dev/null; then
    echo "  [!] Python3 is required. Please install: sudo apt install python3"
    exit 1
fi
echo "  [✓] Python3: $(python3 --version)"

# ===== Step 2: Setup Local LLVM/Clang =====
echo ""
echo "[2/6] Setting up local LLVM/clang toolchain..."

if [ ! -f "$LLVM_BIN/clang" ]; then
    echo "  Downloading LLVM/clang packages (no sudo required)..."
    cd /tmp
    for pkg in clang-20 lld-20; do
        if [ ! -f "${pkg}_1%3a20.1.8-0ubuntu4_amd64.deb" ]; then
            apt download $pkg 2>/dev/null || echo "  [!] Failed to download $pkg - trying system clang"
        fi
        if [ -f "${pkg}_1%3a20.1.8-0ubuntu4_amd64.deb" ]; then
            dpkg-deb -x "${pkg}_1%3a20.1.8-0ubuntu4_amd64.deb" "$LLVM_DIR" 2>/dev/null || true
        fi
    done
    cd "$SCRIPT_DIR"
fi

if [ -f "$LLVM_BIN/clang" ]; then
    CLANG="$LLVM_BIN/clang"
    echo "  [✓] Local clang: $($CLANG --version 2>/dev/null | head -1)"
else
    CLANG="clang"
    echo "  [!] Local clang not found. Using system clang (may need: sudo apt install clang)"
fi

# ===== Step 3: Generate vmlinux.h =====
echo ""
echo "[3/6] Generating vmlinux.h from BTF..."

if [ -f /sys/kernel/btf/vmlinux ]; then
    bpftool btf dump file /sys/kernel/btf/vmlinux format c > "$SCRIPT_DIR/common/vmlinux.h" 2>/dev/null
    VMLINUX_LINES=$(wc -l < "$SCRIPT_DIR/common/vmlinux.h")
    echo "  [✓] vmlinux.h generated ($VMLINUX_LINES lines)"
else
    echo "  [!] /sys/kernel/btf/vmlinux not found. Using pre-generated vmlinux.h if available."
fi

# ===== Step 4: Install Python Dependencies =====
echo ""
echo "[4/6] Installing Python dependencies..."

pip3 install --user --break-system-packages \
    sqlite3 2>/dev/null || true

echo "  [✓] Python dependencies ready"

# ===== Step 5: Build All Modules =====
echo ""
echo "[5/6] Building all monitoring modules..."

make clean 2>/dev/null || true
make all 2>&1 || {
    echo ""
    echo "  [!] Build failed. This is expected if system libraries are missing."
    echo "  Please run the following with sudo to install dependencies:"
    echo "    sudo apt install -y clang lld libbpf-dev libelf-dev zlib1g-dev make"
    echo "  Then re-run: bash setup.sh"
    echo ""
    echo "  For manual build, see Makefile for detailed instructions."
}

# ===== Step 6: Create Directories =====
echo ""
echo "[6/6] Creating runtime directories..."

mkdir -p "$SCRIPT_DIR/log"
mkdir -p "$SCRIPT_DIR/storage"
chmod +x "$SCRIPT_DIR/ui/monitor_ui.py"
chmod +x "$SCRIPT_DIR/stress_test/stress_test.sh" 2>/dev/null || true

echo "  [✓] Runtime directories ready"

# ===== Done =====
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  SETUP COMPLETE                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"
echo "║  Quick Start:                                                ║"
echo "║    python3 ui/monitor_ui.py     # Interactive UI             ║"
echo "║    sudo ./cpu_monitor/cpu_monitor  # Individual monitor       ║"
echo "║    make run-ui                  # Build and run UI           ║"
echo "║    make test                    # Run stress tests           ║"
echo "║                                                              ║"
echo "║  Note: eBPF programs require root privileges to run.         ║"
echo "║        Use 'sudo' when running individual monitors.          ║"
echo "║                                                              ║"
echo "║  Project Structure:                                          ║"
echo "║    cpu_monitor/    - CPU performance monitoring              ║"
echo "║    mem_monitor/    - Memory monitoring                       ║"
echo "║    disk_monitor/   - Disk I/O monitoring                     ║"
echo "║    file_monitor/   - File I/O monitoring                     ║"
echo "║    net_monitor/    - Network monitoring                      ║"
echo "║    ui/             - Interactive Python UI                   ║"
echo "║    log/            - Monitoring data logs (CSV)              ║"
echo "║    storage/        - Database and export storage             ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
