# eBPF Linux Performance Monitor - Build System
# ============================================
# Compiles all 5 monitoring modules using local LLVM/clang toolchain.
#
# Usage:
#   make all      - Build all modules
#   make cpu      - Build CPU monitor only
#   make mem      - Build memory monitor only
#   make disk     - Build disk monitor only
#   make file     - Build file monitor only
#   make net      - Build network monitor only
#   make clean    - Remove all build artifacts
#   make run-ui   - Launch interactive UI
#   make test     - Run stress test

# ===== Toolchain Configuration =====
LLVM_DIR  := $(CURDIR)/local_llvm/usr/lib/llvm-20
CLANG     := $(LLVM_DIR)/bin/clang
LLC       := $(LLVM_DIR)/bin/llc
LD        := $(LLVM_DIR)/bin/ld.lld
BPFTOOL   := bpftool

# Fallback to system tools if local not found
ifeq ($(wildcard $(CLANG)),)
    CLANG   := clang
endif
ifeq ($(wildcard $(LLC)),)
    LLC     := llc
endif

# ===== Include Paths =====
LOCAL_INC := $(CURDIR)/local_llvm/usr/include
INCLUDES  := -I$(CURDIR)/common -I$(LOCAL_INC) -I/usr/include

# ===== Compiler Flags =====
# BPF kernel program flags
BPF_CFLAGS := -target bpf \
              -D__TARGET_ARCH_x86 \
              -g -O2 -Wall \
              -I$(CURDIR)/common \
              -I$(LOCAL_INC) \
              -I/usr/include/x86_64-linux-gnu

# GCC include path (for stddef.h, stdarg.h, etc.)
GCC_INC   := /usr/lib/gcc/x86_64-linux-gnu/15/include

# User-space program flags
USER_CFLAGS := -g -O2 -Wall \
               -I$(CURDIR)/common \
               -I$(LOCAL_INC) \
               -I/usr/include \
               -I/usr/include/x86_64-linux-gnu \
               -I$(GCC_INC) \
               -D_GNU_SOURCE

# Linker flags
LDFLAGS := -L/usr/lib/x86_64-linux-gnu \
           -L$(CURDIR)/local_llvm/usr/lib/x86_64-linux-gnu \
           -lbpf -lelf -lz -lpthread

# ===== Modules =====
MODULES := cpu mem disk file net

# ===== Targets =====
.PHONY: all clean run-ui test help $(MODULES)

all: $(MODULES)
	@echo ""
	@echo "╔══════════════════════════════════════════════════════╗"
	@echo "║  All modules built successfully!                    ║"
	@echo "║  Run './ui/monitor_ui.py' to start the interactive  ║"
	@echo "║  monitoring interface.                              ║"
	@echo "╚══════════════════════════════════════════════════════╝"

help:
	@echo "eBPF Linux Performance Monitor - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build all monitoring modules"
	@echo "  cpu      - Build CPU monitor"
	@echo "  mem      - Build Memory monitor"
	@echo "  disk     - Build Disk I/O monitor"
	@echo "  file     - Build File I/O monitor"
	@echo "  net      - Build Network monitor"
	@echo "  clean    - Remove build artifacts"
	@echo "  run-ui   - Start interactive UI"
	@echo "  test     - Run stress tests"
	@echo "  help     - Show this help"

# ===== Module Build Rules =====

cpu: cpu_monitor/cpu_monitor

cpu_monitor/cpu_monitor: cpu_monitor/cpu.bpf.o cpu_monitor/cpu.c common/common.c
	@echo "[BUILD] CPU Monitor..."
	$(BPFTOOL) gen skeleton cpu_monitor/cpu.bpf.o > cpu_monitor/cpu.skel.h
	$(CLANG) $(USER_CFLAGS) -o $@ cpu_monitor/cpu.c common/common.c $(LDFLAGS)
	@echo "[OK] CPU Monitor built: $@"

cpu_monitor/cpu.bpf.o: cpu_monitor/cpu.bpf.c common/vmlinux.h
	@echo "[BPF]  Compiling CPU BPF program..."
	$(CLANG) $(BPF_CFLAGS) -c cpu_monitor/cpu.bpf.c -o $@

mem: mem_monitor/mem_monitor

mem_monitor/mem_monitor: mem_monitor/mem.bpf.o mem_monitor/mem.c common/common.c
	@echo "[BUILD] Memory Monitor..."
	$(BPFTOOL) gen skeleton mem_monitor/mem.bpf.o > mem_monitor/mem.skel.h
	$(CLANG) $(USER_CFLAGS) -o $@ mem_monitor/mem.c common/common.c $(LDFLAGS)
	@echo "[OK] Memory Monitor built: $@"

mem_monitor/mem.bpf.o: mem_monitor/mem.bpf.c common/vmlinux.h
	@echo "[BPF]  Compiling Memory BPF program..."
	$(CLANG) $(BPF_CFLAGS) -c mem_monitor/mem.bpf.c -o $@

disk: disk_monitor/disk_monitor

disk_monitor/disk_monitor: disk_monitor/disk.bpf.o disk_monitor/disk.c common/common.c
	@echo "[BUILD] Disk I/O Monitor..."
	$(BPFTOOL) gen skeleton disk_monitor/disk.bpf.o > disk_monitor/disk.skel.h
	$(CLANG) $(USER_CFLAGS) -o $@ disk_monitor/disk.c common/common.c $(LDFLAGS)
	@echo "[OK] Disk Monitor built: $@"

disk_monitor/disk.bpf.o: disk_monitor/disk.bpf.c common/vmlinux.h
	@echo "[BPF]  Compiling Disk I/O BPF program..."
	$(CLANG) $(BPF_CFLAGS) -c disk_monitor/disk.bpf.c -o $@

file: file_monitor/file_monitor

file_monitor/file_monitor: file_monitor/file.bpf.o file_monitor/file.c common/common.c
	@echo "[BUILD] File I/O Monitor..."
	$(BPFTOOL) gen skeleton file_monitor/file.bpf.o > file_monitor/file.skel.h
	$(CLANG) $(USER_CFLAGS) -o $@ file_monitor/file.c common/common.c $(LDFLAGS)
	@echo "[OK] File Monitor built: $@"

file_monitor/file.bpf.o: file_monitor/file.bpf.c common/vmlinux.h
	@echo "[BPF]  Compiling File I/O BPF program..."
	$(CLANG) $(BPF_CFLAGS) -c file_monitor/file.bpf.c -o $@

net: net_monitor/net_monitor

net_monitor/net_monitor: net_monitor/net.bpf.o net_monitor/net.c common/common.c
	@echo "[BUILD] Network Monitor..."
	$(BPFTOOL) gen skeleton net_monitor/net.bpf.o > net_monitor/net.skel.h
	$(CLANG) $(USER_CFLAGS) -o $@ net_monitor/net.c common/common.c $(LDFLAGS)
	@echo "[OK] Network Monitor built: $@"

net_monitor/net.bpf.o: net_monitor/net.bpf.c common/vmlinux.h
	@echo "[BPF]  Compiling Network BPF program..."
	$(CLANG) $(BPF_CFLAGS) -c net_monitor/net.bpf.c -o $@

# ===== Utilities =====

run-ui:
	@chmod +x ui/monitor_ui.py
	@echo "[*] Starting interactive monitoring UI..."
	@python3 ui/monitor_ui.py

test:
	@chmod +x stress_test/stress_test.sh
	@bash stress_test/stress_test.sh

# ===== Cleanup =====

clean:
	@echo "[CLEAN] Removing build artifacts..."
	rm -f cpu_monitor/cpu.bpf.o cpu_monitor/cpu.skel.h cpu_monitor/cpu_monitor
	rm -f mem_monitor/mem.bpf.o mem_monitor/mem.skel.h mem_monitor/mem_monitor
	rm -f disk_monitor/disk.bpf.o disk_monitor/disk.skel.h disk_monitor/disk_monitor
	rm -f file_monitor/file.bpf.o file_monitor/file.skel.h file_monitor/file_monitor
	rm -f net_monitor/net.bpf.o net_monitor/net.skel.h net_monitor/net_monitor
	rm -rf log/
	@echo "[OK] Clean complete."
