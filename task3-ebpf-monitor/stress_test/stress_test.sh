#!/bin/bash
#
# eBPF Monitor - Stress Testing Script
# =====================================
# Uses stress-ng and other tools to generate load for testing
# each monitoring module, then analyzes results.
#
# Scenarios:
# 1. CPU stress - high CPU utilization
# 2. Memory stress - memory allocation pressure
# 3. Disk I/O stress - heavy read/write
# 4. File I/O stress - many small file operations
# 5. Network stress - TCP connections and traffic

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
RESULTS_DIR="$PROJECT_DIR/storage/stress_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

mkdir -p "$RESULTS_DIR"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     eBPF Monitor - Stress Testing & Validation              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check for stress tools
check_tool() {
    if command -v "$1" &>/dev/null; then
        echo -e "  ${GREEN}[✓]${NC} $1 found"
        return 0
    else
        echo -e "  ${YELLOW}[!]${NC} $1 not found - install with: sudo apt install $2"
        return 1
    fi
}

echo "--- Checking Stress Tools ---"
check_tool stress-ng "stress-ng"
check_tool dd "coreutils"
check_tool curl "curl"
check_tool iperf3 "iperf3"
echo ""

# ===== Test 1: CPU Stress =====
test_cpu() {
    echo "══════════════════════════════════════════════════════════════"
    echo "  TEST 1: CPU Stress (High CPU Utilization)"
    echo "══════════════════════════════════════════════════════════════"

    echo "[*] Starting CPU monitor in background..."
    sudo "$PROJECT_DIR/cpu_monitor/cpu_monitor" &
    CPU_PID=$!
    sleep 2

    echo "[*] Running CPU stress (4 workers, 30 seconds)..."
    stress-ng --cpu 4 --timeout 30s --metrics-brief 2>&1 | tee "$RESULTS_DIR/cpu_stress_$TIMESTAMP.log"

    echo "[*] Checking eBPF CPU monitor data..."
    sleep 3
    sudo kill $CPU_PID 2>/dev/null || true

    if [ -f "$PROJECT_DIR/log/cpu_monitor_current.csv" ]; then
        LINES=$(wc -l < "$PROJECT_DIR/log/cpu_monitor_current.csv")
        echo -e "  ${GREEN}[✓]${NC} CPU monitor collected $LINES data points"
    else
        echo -e "  ${RED}[✗]${NC} No CPU monitor data found"
    fi
    echo ""
}

# ===== Test 2: Memory Stress =====
test_memory() {
    echo "══════════════════════════════════════════════════════════════"
    echo "  TEST 2: Memory Stress (Memory Allocation Pressure)"
    echo "══════════════════════════════════════════════════════════════"

    echo "[*] Starting memory monitor in background..."
    sudo "$PROJECT_DIR/mem_monitor/mem_monitor" &
    MEM_PID=$!
    sleep 2

    echo "[*] Running memory stress (2GB, 30 seconds)..."
    stress-ng --vm 2 --vm-bytes 1G --timeout 30s --metrics-brief 2>&1 | tee "$RESULTS_DIR/mem_stress_$TIMESTAMP.log"

    sleep 3
    sudo kill $MEM_PID 2>/dev/null || true

    if [ -f "$PROJECT_DIR/log/mem_monitor_current.csv" ]; then
        LINES=$(wc -l < "$PROJECT_DIR/log/mem_monitor_current.csv")
        echo -e "  ${GREEN}[✓]${NC} Memory monitor collected $LINES data points"
    fi
    echo ""
}

# ===== Test 3: Disk I/O Stress =====
test_disk() {
    echo "══════════════════════════════════════════════════════════════"
    echo "  TEST 3: Disk I/O Stress (Heavy Read/Write)"
    echo "══════════════════════════════════════════════════════════════"

    echo "[*] Starting disk monitor in background..."
    sudo "$PROJECT_DIR/disk_monitor/disk_monitor" &
    DISK_PID=$!
    sleep 2

    echo "[*] Running disk stress (4 workers, 30 seconds, 64MB files)..."
    stress-ng --hdd 4 --hdd-bytes 64M --timeout 30s --metrics-brief 2>&1 | tee "$RESULTS_DIR/disk_stress_$TIMESTAMP.log"

    sleep 3
    sudo kill $DISK_PID 2>/dev/null || true

    if [ -f "$PROJECT_DIR/log/disk_monitor_current.csv" ]; then
        LINES=$(wc -l < "$PROJECT_DIR/log/disk_monitor_current.csv")
        echo -e "  ${GREEN}[✓]${NC} Disk monitor collected $LINES data points"
    fi
    echo ""
}

# ===== Test 4: File I/O Stress =====
test_fileio() {
    echo "══════════════════════════════════════════════════════════════"
    echo "  TEST 4: File I/O Stress (Many Small Files)"
    echo "══════════════════════════════════════════════════════════════"

    echo "[*] Starting file monitor in background..."
    sudo "$PROJECT_DIR/file_monitor/file_monitor" &
    FILE_PID=$!
    sleep 2

    echo "[*] Generating file I/O stress (creating/deleting 10000 files)..."
    TEST_DIR=$(mktemp -d)
    for i in $(seq 1 1000); do
        dd if=/dev/zero of="$TEST_DIR/test_$i.dat" bs=4K count=1 2>/dev/null
        cat "$TEST_DIR/test_$i.dat" > /dev/null 2>/dev/null
    done
    rm -rf "$TEST_DIR"

    echo "[*] Running file stress with stress-ng..."
    stress-ng --dir 4 --timeout 15s 2>&1 | tee -a "$RESULTS_DIR/file_stress_$TIMESTAMP.log"

    sleep 3
    sudo kill $FILE_PID 2>/dev/null || true

    if [ -f "$PROJECT_DIR/log/file_monitor_current.csv" ]; then
        LINES=$(wc -l < "$PROJECT_DIR/log/file_monitor_current.csv")
        echo -e "  ${GREEN}[✓]${NC} File monitor collected $LINES data points"
    fi
    echo ""
}

# ===== Test 5: Network Stress =====
test_network() {
    echo "══════════════════════════════════════════════════════════════"
    echo "  TEST 5: Network Stress (TCP Connections & Traffic)"
    echo "══════════════════════════════════════════════════════════════"

    echo "[*] Starting network monitor in background..."
    sudo "$PROJECT_DIR/net_monitor/net_monitor" &
    NET_PID=$!
    sleep 2

    echo "[*] Generating network traffic (HTTP requests to localhost)..."
    # Start a temporary HTTP server
    python3 -m http.server 9999 --directory /tmp &
    HTTP_PID=$!
    sleep 1

    for i in $(seq 1 100); do
        curl -s http://localhost:9999/ > /dev/null 2>&1 || true
    done

    kill $HTTP_PID 2>/dev/null || true

    echo "[*] Running network stress with stress-ng..."
    stress-ng --netdev 2 --timeout 15s 2>&1 | tee -a "$RESULTS_DIR/net_stress_$TIMESTAMP.log"

    sleep 3
    sudo kill $NET_PID 2>/dev/null || true

    if [ -f "$PROJECT_DIR/log/net_monitor_current.csv" ]; then
        LINES=$(wc -l < "$PROJECT_DIR/log/net_monitor_current.csv")
        echo -e "  ${GREEN}[✓]${NC} Network monitor collected $LINES data points"
    fi
    echo ""
}

# ===== Test 6: Combined Stress (All Modules) =====
test_combined() {
    echo "══════════════════════════════════════════════════════════════"
    echo "  TEST 6: Combined Stress Test (All Modules Simultaneously)"
    echo "══════════════════════════════════════════════════════════════"

    echo "[*] Starting all monitors..."
    sudo "$PROJECT_DIR/cpu_monitor/cpu_monitor" &
    P1=$!
    sudo "$PROJECT_DIR/mem_monitor/mem_monitor" &
    P2=$!
    sudo "$PROJECT_DIR/disk_monitor/disk_monitor" &
    P3=$!
    sudo "$PROJECT_DIR/net_monitor/net_monitor" &
    P4=$!
    sleep 2

    echo "[*] Running combined stress (CPU + Memory + Disk + Network, 30 seconds)..."
    stress-ng --cpu 4 --vm 2 --vm-bytes 512M --hdd 2 --netdev 2 \
        --timeout 30s --metrics-brief 2>&1 | tee "$RESULTS_DIR/combined_stress_$TIMESTAMP.log"

    echo "[*] Analyzing results..."
    sleep 3

    for pid in $P1 $P2 $P3 $P4; do
        sudo kill $pid 2>/dev/null || true
    done

    echo ""
    echo "--- Stress Test Results Summary ---"
    for module in cpu mem disk file net; do
        CSV="$PROJECT_DIR/log/${module}_monitor_current.csv"
        if [ -f "$CSV" ]; then
            LINES=$(wc -l < "$CSV")
            SIZE=$(du -h "$CSV" | cut -f1)
            echo -e "  ${GREEN}[✓]${NC} ${module}_monitor: $LINES records ($SIZE)"
        else
            echo -e "  ${RED}[✗]${NC} ${module}_monitor: no data"
        fi
    done
    echo ""
}

# ===== Analysis & Optimization Suggestions =====
analyze_results() {
    echo "══════════════════════════════════════════════════════════════"
    echo "  ANALYSIS & OPTIMIZATION SUGGESTIONS"
    echo "══════════════════════════════════════════════════════════════"

    cat << 'EOF'

Based on the stress test results, here are common observations and optimization suggestions:

1. CPU Stress Analysis:
   - High user% indicates compute-bound workload → Consider CPU scaling/optimization
   - High iowait% during CPU test → Storage may be bottleneck
   - Context switches spike → Consider CPU affinity/pinning

2. Memory Stress Analysis:
   - Page faults increase → May need more RAM or adjust swappiness
   - Swap usage spikes → System under memory pressure
   - OOM events → Configure OOM killer policies or add memory limits

3. Disk I/O Stress Analysis:
   - High I/O latency → Consider SSD upgrade or RAID configuration
   - Queue depth grows → Disk is saturated, consider I/O scheduler tuning
   - Low IOPS with high latency → Fragmentation or seek-bound workload

4. File I/O Stress Analysis:
   - Many open/close operations → Consider connection pooling or file caching
   - Low dentry cache hit rate → Increase vfs_cache_pressure
   - High fsync count → Consider write-back caching strategy

5. Network Stress Analysis:
   - TCP retransmissions → Network congestion or packet loss
   - High TIME_WAIT connections → Tune tcp_tw_reuse/recycle
   - RX/TX errors → Check NIC driver, cables, or network configuration

General Optimization Approach (USE Method):
  1. Identify the bottleneck (CPU/Memory/Disk/Network)
  2. Apply targeted optimization (kernel params, hardware upgrade, config tuning)
  3. Re-run stress test to validate improvement
  4. Iterate until performance target is met

EOF
}

# ===== Main =====
case "${1:-all}" in
    cpu)     test_cpu ;;
    mem)     test_memory ;;
    disk)    test_disk ;;
    file)    test_fileio ;;
    net)     test_network ;;
    combined) test_combined ;;
    all)
        test_cpu
        test_memory
        test_disk
        test_fileio
        test_network
        test_combined
        analyze_results
        ;;
    analyze) analyze_results ;;
    *)
        echo "Usage: $0 {cpu|mem|disk|file|net|combined|all|analyze}"
        echo ""
        echo "  cpu      - CPU stress test"
        echo "  mem      - Memory stress test"
        echo "  disk     - Disk I/O stress test"
        echo "  file     - File I/O stress test"
        echo "  net      - Network stress test"
        echo "  combined - All modules simultaneously"
        echo "  all      - Run all tests"
        echo "  analyze  - Show optimization suggestions"
        ;;
esac
