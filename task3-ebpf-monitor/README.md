# 基于 eBPF 技术的 Linux 系统性能监测工具

## 项目概述

本项目是《服务器运维与性能优化》课程大作业第三题（40分），基于 **eBPF** 技术实现了一套完整的 Linux
系统性能监测工具，覆盖 **CPU、内存、磁盘 I/O、文件 I/O、网络** 五大模块，共 **25 个关键性能指标**。

### 技术栈

| 层次 | 技术 |
|------|------|
| 内核态数据采集 | eBPF CO-RE + libbpf（tracepoint / raw tracepoint） |
| 用户态加载器 | C 语言 + libbpf API |
| 交互界面 | Python 3 终端 UI（菜单式 / 多面板摘要） |
| 数据存储 | CSV（6 种优化策略）+ SQLite |
| 可视化 | Prometheus + Grafana |
| 编译工具链 | LLVM/Clang 20 + bpftool |
| 测试工具 | stress-ng + 自定义压力测试脚本 |

---

## 项目结构

```
task3-ebpf-monitor/
├── common/                    # 公共基础设施
│   ├── vmlinux.h              # BTF 生成的完整内核类型定义 (162K 行)
│   ├── common.h               # 共享数据结构、宏、文件写入器接口
│   ├── common.c               # 文件存储、信号处理、格式化工具
│   └── events.h               # 内核-用户态共享事件结构体
├── cpu_monitor/               # CPU 监测模块
│   ├── cpu.bpf.c              # eBPF 内核程序 (sched_switch, sched_wakeup, cpu_frequency)
│   └── cpu.c                  # 用户态加载器 (读取 /proc/stat + sysfs)
├── mem_monitor/               # 内存监测模块
│   ├── mem.bpf.c              # eBPF 内核程序 (page_fault, kmalloc, OOM mark_victim)
│   └── mem.c                  # 用户态加载器 (读取 /proc/meminfo)
├── disk_monitor/              # 磁盘 I/O 监测模块
│   ├── disk.bpf.c             # eBPF 内核程序 (block_rq_issue + block_rq_complete)
│   └── disk.c                 # 用户态加载器 (读取 /proc/diskstats)
├── file_monitor/              # 文件 I/O 监测模块
│   ├── file.bpf.c             # eBPF 内核程序 (openat, close, read, write, fsync)
│   └── file.c                 # 用户态加载器 (读取 /proc/sys/fs/*)
├── net_monitor/               # 网络监测模块
│   ├── net.bpf.c              # eBPF 内核程序 (net_dev_queue, netif_receive_skb, tcp_retransmit)
│   └── net.c                  # 用户态加载器 (读取 /proc/net/dev, /proc/net/tcp)
├── ui/
│   └── monitor_ui.py          # Python 交互式终端 UI (含 CSV→SQLite→Prometheus 数据链路)
├── grafana/
│   ├── prometheus.yml         # Prometheus 采集配置
│   └── ebpf_dashboard.json    # Grafana 仪表盘 JSON
├── stress_test/
│   └── stress_test.sh         # 压力测试与验证脚本 (6 种场景)
├── storage/                   # SQLite 数据库和导出存储
├── log/                       # CSV 日志文件（运行时生成）
├── local_llvm/                # 本地 LLVM/Clang 编译工具链
├── Makefile                   # 构建系统
├── setup.sh                   # 一键环境配置脚本
└── README.md                  # 本文件
```

---

## 数据链路架构

```
┌─────────────────────────────────────────────────────────────┐
│  Linux 内核                                                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌─────────┐ ┌──────┐│
│  │ sched_   │ │ page_    │ │ block_   │ │ syscall │ │ net_ ││
│  │ switch   │ │ fault    │ │ rq_issue │ │ openat  │ │ dev_ ││
│  │ wakeup   │ │ kmalloc  │ │ rq_compl │ │ read…   │ │ queue││
│  │ cpu_freq │ │ mark_    │ │          │ │ write…  │ │ rx_  ││
│  │          │ │ victim   │ │          │ │ fsync   │ │ skb  ││
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬────┘ └──┬───┘│
│       │            │            │            │         │     │
│  ┌────┴────────────┴────────────┴────────────┴─────────┴───┐ │
│  │                eBPF Programs (CO-RE + BTF)              │ │
│  │     Ring Buffer → user-space event handlers             │ │
│  └─────────────────────────┬───────────────────────────────┘ │
└────────────────────────────┼──────────────────────────────────┘
                             ↓
┌────────────────────────────┼──────────────────────────────────┐
│  用户态 C 程序               ↓                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  ring_buffer__poll()   +   /proc & /sys file parsing     │ │
│  │         ↓                                                │ │
│  │  CSV 文件写入 (log/*_current.csv)                         │ │
│  │  + 终端实时输出 (ANSI 表格)                                │ │
│  └─────────────────────────┬────────────────────────────────┘ │
└────────────────────────────┼──────────────────────────────────┘
                             ↓
┌────────────────────────────┼──────────────────────────────────┐
│  Python UI (monitor_ui.py) ↓                                   │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │             MetricsCollector (后台线程, 1 Hz)             │ │
│  │  增量读取 CSV 文件 →                                      │ │
│  │  ├── SQLite 数据库 (storage/ebpf_monitor.db)             │ │
│  │  └── Prometheus 内存指标 → HTTP :9091/metrics            │ │
│  └──────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  交互式菜单:                                              │ │
│  │  1-5  单个模块监控 (透传 C 程序输出)                       │ │
│  │  A    全部模块运行 (Python 多面板摘要, 无输出冲突)          │ │
│  │  S    停止所有监控                                        │ │
│  │  L    查看 CSV 日志文件                                   │ │
│  │  D    SQLite 数据库查询 (自动先同步 CSV)                   │ │
│  │  P    Prometheus /metrics 端点                            │ │
│  │  E    导出 JSON                                           │ │
│  │  Q    退出                                                │ │
│  └──────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

---

## 25 个关键性能指标

### CPU（5 个指标）

| # | 指标 | 数据源 | 说明 |
|---|------|--------|------|
| 1 | CPU 利用率 | `/proc/stat` | 每核 user / system / idle / iowait 百分比，每秒刷新 |
| 2 | 运行队列长度 | `tracepoint/sched/sched_wakeup` | 唤醒计数，反映调度压力 |
| 3 | 上下文切换率 | `tracepoint/sched/sched_switch` | 每核上下文切换累计数，每 100 次采样上报 |
| 4 | CPU 频率 | `tracepoint/power/cpu_frequency` + sysfs fallback | eBPF 捕获变频事件，回退读 `scaling_cur_freq` |
| 5 | CPU 空闲时间 | `/proc/stat` idle 字段 | 各空闲状态时间分布（含 iowait 细分） |

### 内存（5 个指标）

| # | 指标 | 数据源 | 说明 |
|---|------|--------|------|
| 1 | 内存使用率 | `/proc/meminfo` | Total / Used / Avail / Cached / Buffer，每秒刷新 |
| 2 | 页面错误率 | `tracepoint/exceptions/page_fault_user` | Minor page faults，每 1000 次采样上报 |
| 3 | Swap 使用 | `/proc/meminfo` | SwapTotal / SwapFree，检测换页活动 |
| 4 | OOM 事件 | `tracepoint/oom/mark_victim` | OOM Killer 选中 victim 时上报（PID、VM、RSS） |
| 5 | 内存分配率 | `tracepoint/kmem/kmalloc` | 内核 kmalloc 调用次数和字节数 |

### 磁盘 I/O（5 个指标）

| # | 指标 | 数据源 | 说明 |
|---|------|--------|------|
| 1 | 磁盘读取字节 | `tracepoint/block/block_rq_complete` + `/proc/diskstats` | 每秒读取字节数，区分读/写 |
| 2 | 磁盘写入字节 | `tracepoint/block/block_rq_complete` + `/proc/diskstats` | 每秒写入字节数 |
| 3 | IOPS | `tracepoint/block/block_rq_issue` | 每秒 I/O 操作次数（按 rwbs 区分 R/W） |
| 4 | I/O 延迟 | `block_rq_issue` → `block_rq_complete` 时间差 | 按 (dev, sector) 追踪请求延迟（微秒） |
| 5 | 磁盘利用率 | `/proc/diskstats` io_ticks | 磁盘繁忙时间百分比 |

### 文件 I/O（5 个指标）

| # | 指标 | 数据源 | 说明 |
|---|------|--------|------|
| 1 | 文件打开/关闭 | `tracepoint/syscalls/sys_enter_openat` / `close` | 文件操作次数，每 10000 次采样 |
| 2 | VFS 读取 | `tracepoint/syscalls/sys_enter_read` | 虚拟文件系统读取操作 |
| 3 | VFS 写入 | `tracepoint/syscalls/sys_enter_write` | 虚拟文件系统写入操作 |
| 4 | 目录缓存 | `/proc/sys/fs/dentry-state` | Dentry cache 总条目数 / 未使用数 |
| 5 | Inode 缓存 | `/proc/sys/fs/inode-nr` | Inode cache 已分配 / 空闲数 |

### 网络（5 个指标）

| # | 指标 | 数据源 | 说明 |
|---|------|--------|------|
| 1 | 网络收发字节 | `/proc/net/dev` | 每接口 RX/TX 字节数，自动发现接口名 |
| 2 | 网络数据包 | `tracepoint/net/net_dev_queue` + `netif_receive_skb` | TX/RX 包计数，每 1000 包采样 |
| 3 | TCP 连接状态 | `/proc/net/tcp` | ESTABLISHED / LISTEN / TIME_WAIT / CLOSE_WAIT 计数 |
| 4 | 网络错误/丢包 | `/proc/net/dev` | RX/TX errors, dropped 字段 |
| 5 | TCP 重传率 | `tracepoint/tcp/tcp_retransmit_skb` | TCP 段重传累计数，每 100 次采样 |

---

## 快速开始

### 环境要求

- Linux 内核 ≥ 5.4（推荐 5.8+，CO-RE 支持）
- BTF 支持：`/sys/kernel/btf/vmlinux` 存在
- Python ≥ 3.8
- root/sudo 权限（eBPF 程序加载需要 `CAP_BPF`）

### 一键构建与运行

```bash
# 1. 配置环境（下载 LLVM，生成 vmlinux.h，编译所有模块）
bash setup.sh

# 2. 构建所有模块
make all

# 3. 启动交互式 UI
python3 ui/monitor_ui.py
# 或
make run-ui

# 4. 单独运行某个监测器（需要 root）
sudo ./cpu_monitor/cpu_monitor
sudo ./mem_monitor/mem_monitor
sudo ./disk_monitor/disk_monitor
sudo ./file_monitor/file_monitor
sudo ./net_monitor/net_monitor

# 5. 运行压力测试
make test
# 或
sudo bash stress_test/stress_test.sh all
```

### Makefile 目标

| 目标 | 说明 |
|------|------|
| `make all` | 编译全部 5 个模块 |
| `make cpu` | 仅编译 CPU 监测器 |
| `make mem` | 仅编译内存监测器 |
| `make disk` | 仅编译磁盘 I/O 监测器 |
| `make file` | 仅编译文件 I/O 监测器 |
| `make net` | 仅编译网络监测器 |
| `make clean` | 清理所有构建产物 |
| `make run-ui` | 启动交互式 UI |
| `make test` | 运行压力测试 |

---

## 交互式 UI 使用说明

启动 UI：`python3 ui/monitor_ui.py` 或 `make run-ui`

### 菜单选项

```
┌──────────────────────────────────────────────────────────────┐
│ 1  CPU Monitor      │ Utilization, Run Queue, Ctx Switches   │
│ 2  Memory Monitor   │ Usage, Page Faults, Swap, OOM          │
│ 3  Disk I/O Monitor │ Read/Write Bytes, IOPS, Latency        │
│ 4  File I/O Monitor │ Open/Close, VFS R/W, Dcache, Inode     │
│ 5  Network Monitor  │ Bytes/Packets, TCP States, Errors      │
├──────────────────────────────────────────────────────────────┤
│ A  Start ALL monitors  →  多面板摘要显示（无 ANSI 乱码）      │
│ S  Stop all monitors                                        │
│ L  View log files                                            │
│ D  Database query (SQLite)  →  自动从 CSV 同步最新数据       │
│ P  Start Prometheus metrics endpoint (port 9091)             │
│ E  Export data (JSON)                                        │
│ Q  Quit                                                      │
└──────────────────────────────────────────────────────────────┘
```

### "全部运行" 模式 (A)

选择 `A` 后，5 个 C 监测器在后台运行（stdout 被抑制，仅写 CSV）。Python UI
渲染统一的多面板摘要，每秒刷新：

```
┌── CPU Utilization ──────────────────────────────────────────┐
│  18:46:50  CPU  0  user=  4%  sys=  1%  idle= 95%          │
│  18:46:50  CPU  4  user= 86%  sys= 10%  idle=  4%          │
└──────────────────────────────────────────────────────────────┘
┌── Memory ───────────────────────────────────────────────────┐
│  Used: 53.7%  |  Avail: 7037 MB  |  Swap Used:    2 MB     │
└──────────────────────────────────────────────────────────────┘
┌── Disk I/O ────────────────────┐ ┌── Network / TCP ─────────┐
│  sda    R:  512MB W: 1024MB    │ │  TCP  ESTAB: 24  TW:  0 │
└────────────────────────────────┘ └──────────────────────────┘
┌── File I/O Operations ──────────────────────────────────────┐
│  Open:      130  |  Close:      621  |  Read:     7589      │
└──────────────────────────────────────────────────────────────┘
```

### Prometheus + Grafana

```bash
# 1. 在 UI 中选择 'P' 启动 Prometheus 端点
#    或直接运行:
python3 ui/monitor_ui.py   # 然后按 P

# 2. 启动 Prometheus
prometheus --config.file=grafana/prometheus.yml

# 3. 访问
#    Prometheus: http://localhost:9090
#    Grafana:    http://localhost:3000 (导入 grafana/ebpf_dashboard.json)
```

---

## 数据存储优化策略

系统实现了 6 种文件存储优化策略（`common/common.c`）：

| # | 策略 | 实现 | 参数 |
|---|------|------|------|
| 1 | 文件自动分割 | `file_writer_rotate()` — 超过阈值自动滚动 | 100 MB |
| 2 | 异步写入 | C 程序实时 `fflush`，Python 读取时容错 | — |
| 3 | 数据压缩 | 旧日志文件自动 gzip 压缩 | 滚动时触发 |
| 4 | 冗余剔除 | eBPF 端采样上报（每 N 次事件送 1 次 ring buffer） | 100～10000 |
| 5 | 自动清理 | 7 天前的 `.csv.gz` 自动删除 | 7 天 |
| 6 | CSV 格式 | 逗号分隔，比 JSON 节约约 30% | — |

---

## 压力测试

```bash
# 运行全部测试
sudo bash stress_test/stress_test.sh all

# 单独测试
sudo bash stress_test/stress_test.sh cpu
sudo bash stress_test/stress_test.sh mem
sudo bash stress_test/stress_test.sh disk
sudo bash stress_test/stress_test.sh file
sudo bash stress_test/stress_test.sh net
sudo bash stress_test/stress_test.sh combined
```

### 测试场景

| 场景 | 工具 | 预期观测 |
|------|------|----------|
| CPU 密集型 | `stress-ng --cpu 4` (30s) | CPU 利用率 100%，上下文切换骤增 |
| 内存压力 | `stress-ng --vm 2 --vm-bytes 1G` (30s) | 内存使用率上升，可能触发 swap |
| 磁盘 I/O | `stress-ng --hdd 4 --hdd-bytes 64M` (30s) | IOPS 飙升，I/O 延迟增加 |
| 文件操作 | 大量小文件创建/删除 + stress-ng --dir | open/close 计数骤增 |
| 网络流量 | HTTP 请求 + stress-ng --netdev | 网络吞吐量上升，TCP 连接增加 |
| 综合压力 | 以上全部同时运行 | 全系统瓶颈暴露，资源竞争 |

### 实测结果（16 核 + 16 GB RAM）

```
✅ cpu_monitor:    9,588 records  (646 KB)   — 上下文切换从 100 → 75,200
✅ mem_monitor:    4,064 records  (304 KB)   — 页错误 391 万次，swap 从 0 → 2 MB
✅ disk_monitor:   3,638 records  (279 KB)   — 累计读写 42 GB
✅ file_monitor:      26 records  (2.1 KB)   — 文件操作实时追踪
✅ net_monitor:       39 records  (2.8 KB)   — TCP ESTAB: 26
────────────────────────────────────────────────────────────────────
SQLite 总计:      17,355 rows
Prometheus 指标:  15 个实时指标
```

---

## 常见优化建议

| 瓶颈 | 优化方向 |
|------|----------|
| **CPU 瓶颈** | CPU 亲和性绑定、进程优先级调整（nice/renice）、考虑 CPU 扩容 |
| **内存瓶颈** | 调整 `vm.swappiness`、增加物理内存、优化应用内存使用 |
| **磁盘瓶颈** | 升级 SSD、RAID 优化、I/O 调度器调优（mq-deadline/kyber） |
| **文件瓶颈** | 调整 `vm.vfs_cache_pressure`、使用 tmpfs 内存文件系统 |
| **网络瓶颈** | TCP 参数调优（`tcp_tw_reuse`、`tcp_fastopen`）、增加带宽、负载均衡 |

---

## 故障排查

| 现象 | 原因 | 解决 |
|------|------|------|
| `Failed to load BPF: Permission denied` | 非 root 或无 CAP_BPF | 使用 `sudo` 运行 |
| `Failed to attach: No such file or directory` | tracepoint 不存在 | 内核版本差异，程序有 fallback |
| `[ERROR] Binary not found` | 未编译 | 运行 `make all` |
| CPU 频率显示 `N/A` | cpu_frequency tracepoint 未触发 | 等待变频事件或依赖 sysfs fallback |
| SQLite 查询为空 | 未先运行监测器 | 先运行监测器写 CSV，再查询 |
| 数据库记录重复 | 多次创建 MetricsCollector | 正常使用 UI 不会重复（单例模式） |

---

## 许可证

本项目为课程作业，仅供学习参考。
