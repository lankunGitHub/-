/* SPDX-License-Identifier: GPL-2.0 */
/*
 * eBPF Linux Performance Monitor - Common Definitions
 *
 * Shared data structures and macros for all monitoring modules:
 * CPU, Memory, Disk, File I/O, Network
 */

#ifndef __COMMON_H__
#define __COMMON_H__

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <sys/resource.h>
#include <bpf/libbpf.h>
#include <bpf/bpf.h>

/* ===== Module Identifiers ===== */
#define MODULE_CPU     0
#define MODULE_MEMORY  1
#define MODULE_DISK    2
#define MODULE_FILE    3
#define MODULE_NETWORK 4

#define MODULE_COUNT   5

static const char *module_names[] = {
    "CPU",
    "Memory",
    "Disk",
    "File",
    "Network"
};

/* ===== Collection Duration (seconds), 0 = infinite ===== */
#define DEFAULT_DURATION  0

/* ===== Output Modes ===== */
#define OUTPUT_TERMINAL  0
#define OUTPUT_JSON      1
#define OUTPUT_CSV       2
#define OUTPUT_PROMETHEUS 3

/* ===== Common Data Structures ===== */

/* Timestamp in nanoseconds */
typedef unsigned long long timestamp_t;

/* Generic metric entry for ring buffer transfer */
struct metric_event {
    unsigned int  module;        /* MODULE_CPU, etc. */
    unsigned int  metric_id;     /* metric identifier within module */
    timestamp_t   timestamp;     /* event timestamp (ns) */
    unsigned int  cpu_id;        /* CPU core that generated this */
    char          comm[16];      /* process command name */
    unsigned int  pid;           /* process ID */
    unsigned long long value1;   /* primary metric value */
    unsigned long long value2;   /* secondary metric value */
    unsigned long long value3;   /* tertiary metric value */
    char          label[64];     /* human-readable label */
};

/* CPU-specific metrics */
#define CPU_METRIC_UTILIZATION   0
#define CPU_METRIC_RUNQUEUE      1
#define CPU_METRIC_CTX_SWITCH    2
#define CPU_METRIC_FREQUENCY     3
#define CPU_METRIC_IDLE_TIME     4

struct cpu_metric {
    unsigned long long user_time;
    unsigned long long nice_time;
    unsigned long long system_time;
    unsigned long long idle_time;
    unsigned long long iowait_time;
    unsigned long long irq_time;
    unsigned long long softirq_time;
    unsigned long long steal_time;
    unsigned long long nr_running;
    unsigned long long ctx_switches;
    unsigned int        cpu_freq_mhz;
};

/* Memory-specific metrics */
#define MEM_METRIC_USAGE         0
#define MEM_METRIC_PAGE_FAULT    1
#define MEM_METRIC_SWAP          2
#define MEM_METRIC_OOM           3
#define MEM_METRIC_ALLOC_RATE    4

struct mem_metric {
    unsigned long long total_mb;
    unsigned long long free_mb;
    unsigned long long used_mb;
    unsigned long long cached_mb;
    unsigned long long buffer_mb;
    unsigned long long swap_total_mb;
    unsigned long long swap_used_mb;
    unsigned long long pgfault_major;
    unsigned long long pgfault_minor;
    unsigned long long oom_kills;
    unsigned long long alloc_bytes_per_sec;
};

/* Disk I/O metrics */
#define DISK_METRIC_READ_BYTES   0
#define DISK_METRIC_WRITE_BYTES  1
#define DISK_METRIC_IOPS         2
#define DISK_METRIC_LATENCY      3
#define DISK_METRIC_UTILIZATION  4

struct disk_metric {
    unsigned long long read_bytes;
    unsigned long long write_bytes;
    unsigned long long read_iops;
    unsigned long long write_iops;
    unsigned long long avg_latency_us;
    unsigned long long queue_depth;
    unsigned int        utilization_pct;
    char                disk_name[32];
};

/* File I/O metrics */
#define FILE_METRIC_OPEN_COUNT   0
#define FILE_METRIC_READ_COUNT   1
#define FILE_METRIC_WRITE_COUNT  2
#define FILE_METRIC_DCACHE_HITS  3
#define FILE_METRIC_ICACHE_HITS  4

struct file_metric {
    unsigned long long open_count;
    unsigned long long close_count;
    unsigned long long read_count;
    unsigned long long write_count;
    unsigned long long fsync_count;
    unsigned long long dcache_hits;
    unsigned long long dcache_misses;
    unsigned long long icache_hits;
    unsigned long long icache_misses;
};

/* Network metrics */
#define NET_METRIC_BYTES_IN      0
#define NET_METRIC_BYTES_OUT     1
#define NET_METRIC_PACKETS_IN    2
#define NET_METRIC_PACKETS_OUT   3
#define NET_METRIC_TCP_STATES    4
#define NET_METRIC_ERRORS        5

struct net_metric {
    unsigned long long bytes_in;
    unsigned long long bytes_out;
    unsigned long long packets_in;
    unsigned long long packets_out;
    unsigned long long tcp_established;
    unsigned long long tcp_listen;
    unsigned long long tcp_close_wait;
    unsigned long long tcp_time_wait;
    unsigned long long rx_errors;
    unsigned long long tx_errors;
    unsigned long long rx_dropped;
    unsigned long long tx_dropped;
    unsigned long long tcp_retransmits;
    char                if_name[16];
};

/* ===== Helper Macros ===== */

#define PRINT_ERR(fmt, ...)  fprintf(stderr, "[ERROR] " fmt "\n", ##__VA_ARGS__)
#define PRINT_INFO(fmt, ...) fprintf(stdout, "[INFO] " fmt "\n", ##__VA_ARGS__)

#ifndef __always_inline
#define __always_inline __attribute__((__always_inline__))
#endif

#ifndef __weak
#define __weak __attribute__((__weak__))
#endif

/* ===== File Writer Interface ===== */

struct file_writer {
    FILE        *fp;
    char        filename[256];
    char        dir[128];
    size_t      max_size;         /* max file size before rotation (bytes) */
    size_t      current_size;
    int         rotation_count;
    int         compress_old;     /* 1 = gzip old files */
    int         async_mode;       /* 1 = use async buffer */
    time_t      last_rotation;
};

int file_writer_init(struct file_writer *fw, const char *dir,
                     const char *prefix, size_t max_size_mb);
int file_writer_write(struct file_writer *fw, const char *fmt, ...);
int file_writer_rotate(struct file_writer *fw);
int file_writer_cleanup(struct file_writer *fw, int keep_days);
void file_writer_close(struct file_writer *fw);

/* ===== Signal Handling ===== */
extern volatile int exiting;

void setup_signal_handler(void);

/* ===== BPF Helpers ===== */
int bump_memlock_rlimit(void);

/* ===== Utility Functions ===== */
unsigned long long get_timestamp_ns(void);
double calc_rate(unsigned long long current, unsigned long long previous, double interval_sec);
const char *format_bytes(unsigned long long bytes, char *buf, size_t len);
const char *format_timestamp(unsigned long long ts_ns, char *buf, size_t len);

#endif /* __COMMON_H__ */
