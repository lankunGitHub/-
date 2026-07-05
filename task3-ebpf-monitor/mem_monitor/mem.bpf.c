/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Memory Monitor - eBPF Kernel Program
 * Monitors: page faults, kmalloc, OOM kills, swap events
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

/* Page fault counter [0=major_reserved, 1=minor] */
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 4);
    __type(key, unsigned int);
    __type(value, unsigned long long);
} page_fault_count SEC(".maps");

/* Memory allocation tracking [0=alloc_count, 1=alloc_bytes] */
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 2);
    __type(key, unsigned int);
    __type(value, unsigned long long);
} alloc_stats SEC(".maps");

/* OOM event counter */
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 1);
    __type(key, unsigned int);
    __type(value, unsigned long long);
} oom_count SEC(".maps");

/* Ring buffer */
struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 256 * 1024);
} mem_events SEC(".maps");

struct mem_event {
    unsigned int  metric_type;    /* 0=pgfault, 1=alloc, 2=oom */
    unsigned long long timestamp;
    char          comm[16];
    unsigned int  pid;
    unsigned long long value1;
    unsigned long long value2;
    unsigned long long value3;
};

/* ===== Tracepoint: page_fault_user ===== */
SEC("tracepoint/exceptions/page_fault_user")
int trace_page_fault(void *ctx)
{
    unsigned int key = 1;  /* minor fault */
    unsigned long long *count;

    count = bpf_map_lookup_elem(&page_fault_count, &key);
    if (count) {
        __sync_fetch_and_add(count, 1);
    }

    /* Sample every 1000 faults */
    if (count && (*count % 1000 == 0)) {
        struct mem_event *e;
        e = bpf_ringbuf_reserve(&mem_events, sizeof(*e), 0);
        if (e) {
            e->metric_type = 0;
            e->timestamp = bpf_ktime_get_ns();
            e->pid = bpf_get_current_pid_tgid() >> 32;
            bpf_get_current_comm(&e->comm, sizeof(e->comm));
            e->value1 = *count;
            e->value2 = key;
            e->value3 = 0;
            bpf_ringbuf_submit(e, 0);
        }
    }
    return 0;
}

/*
 * Tracepoint: kmem/kmalloc
 * Format: call_site, ptr, bytes_req, bytes_alloc, gfp_flags
 */
struct kmalloc_args {
    unsigned long long __do_not_use__;
    unsigned long long call_site;
    unsigned long long ptr;
    unsigned long long bytes_req;
    unsigned long long bytes_alloc;
    unsigned long long gfp_flags;
};

SEC("tracepoint/kmem/kmalloc")
int trace_kmalloc(struct kmalloc_args *ctx)
{
    unsigned long long bytes = ctx->bytes_req;
    unsigned int key_count = 0;
    unsigned int key_bytes = 1;
    unsigned long long *total_count, *total_bytes;

    total_count = bpf_map_lookup_elem(&alloc_stats, &key_count);
    if (total_count) __sync_fetch_and_add(total_count, 1);

    total_bytes = bpf_map_lookup_elem(&alloc_stats, &key_bytes);
    if (total_bytes) __sync_fetch_and_add(total_bytes, bytes);

    return 0;
}

/* ===== Tracepoint: oom/mark_victim =====
 * Fires when the OOM killer selects a process to kill.
 * Fields: pid, comm (victim), total_vm, anon_rss, etc.
 */
SEC("tracepoint/oom/mark_victim")
int trace_oom_kill(struct trace_event_raw_mark_victim *ctx)
{
    unsigned int key = 0;
    unsigned long long *count;

    count = bpf_map_lookup_elem(&oom_count, &key);
    if (count) {
        __sync_fetch_and_add(count, 1);
    }

    /* Always report OOM events */
    struct mem_event *e;
    e = bpf_ringbuf_reserve(&mem_events, sizeof(*e), 0);
    if (e) {
        e->metric_type = 2;
        e->timestamp = bpf_ktime_get_ns();
        e->pid = ctx->pid;          /* victim PID from tracepoint */
        bpf_get_current_comm(&e->comm, sizeof(e->comm));
        e->value1 = *count;         /* total OOM count */
        e->value2 = ctx->total_vm;  /* victim's total VM */
        e->value3 = ctx->anon_rss;  /* victim's anonymous RSS */
        bpf_ringbuf_submit(e, 0);
    }
    return 0;
}
