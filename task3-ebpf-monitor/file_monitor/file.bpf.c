/* SPDX-License-Identifier: GPL-2.0 */
/*
 * File I/O Monitor - eBPF Kernel Program
 * Monitors: open/close/read/write/fsync via syscall tracepoints
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

#define TASK_COMM_LEN 16

/* Counters: 0=open, 1=close, 2=read, 3=write, 4=fsync */
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 8);
    __type(key, unsigned int);
    __type(value, unsigned long long);
} file_op_count SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 256 * 1024);
} file_events SEC(".maps");

struct file_event {
    unsigned int  metric_type;
    unsigned long long timestamp;
    char          comm[TASK_COMM_LEN];
    unsigned int  pid;
    unsigned long long value1;
    unsigned long long value2;
    unsigned long long value3;
};

/* Helper: increment counter and optionally send event */
static __always_inline void inc_counter(unsigned int key, unsigned int metric_type)
{
    unsigned long long *count;
    unsigned int pid = bpf_get_current_pid_tgid() >> 32;

    count = bpf_map_lookup_elem(&file_op_count, &key);
    if (count) {
        __sync_fetch_and_add(count, 1);
    }

    /* Sample: report every 10000 operations */
    if (count && (*count % 10000 == 0)) {
        struct file_event *e;
        e = bpf_ringbuf_reserve(&file_events, sizeof(*e), 0);
        if (e) {
            e->metric_type = metric_type;
            e->timestamp = bpf_ktime_get_ns();
            e->pid = pid;
            bpf_get_current_comm(&e->comm, sizeof(e->comm));
            e->value1 = *count;
            e->value2 = 0;
            e->value3 = 0;
            bpf_ringbuf_submit(e, 0);
        }
    }
}

SEC("tracepoint/syscalls/sys_enter_openat")
int trace_sys_enter_openat(void *ctx)
{
    inc_counter(0, 0);  /* open */
    return 0;
}

SEC("tracepoint/syscalls/sys_enter_close")
int trace_sys_enter_close(void *ctx)
{
    inc_counter(1, 1);  /* close */
    return 0;
}

SEC("tracepoint/syscalls/sys_enter_read")
int trace_sys_enter_read(void *ctx)
{
    inc_counter(2, 2);  /* read */
    return 0;
}

SEC("tracepoint/syscalls/sys_enter_write")
int trace_sys_enter_write(void *ctx)
{
    inc_counter(3, 3);  /* write */
    return 0;
}

SEC("tracepoint/syscalls/sys_enter_fsync")
int trace_sys_enter_fsync(void *ctx)
{
    inc_counter(4, 4);  /* fsync */
    return 0;
}
