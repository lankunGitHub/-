/* SPDX-License-Identifier: GPL-2.0 */
/*
 * CPU Monitor - eBPF Kernel Program
 * Monitors: CPU utilization, run queue, context switches, CPU frequency, idle time
 *
 * Uses:
 *  - tracepoint/sched/sched_switch      → context switch counter
 *  - tracepoint/sched/sched_wakeup      → wakeup counter (run queue depth)
 *  - tp_btf/cpu_frequency               → CPU frequency via raw tracepoint (BTF-based)
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

#define MAX_CPUS 128

/* ===== BPF Maps ===== */
struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, MAX_CPUS);
	__type(key, unsigned int);
	__type(value, unsigned long long);
} ctx_switch_count SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, MAX_CPUS);
	__type(key, unsigned int);
	__type(value, unsigned int);
} cpu_freq_map SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, MAX_CPUS);
	__type(key, unsigned int);
	__type(value, unsigned long long);
} wakeup_count SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 256 * 1024);
} cpu_events SEC(".maps");

/* ===== Event structure ===== */
struct cpu_event {
	unsigned int  cpu_id;
	unsigned int  metric_type;   /* 2=ctx_switch, 3=frequency */
	unsigned long long timestamp;
	char          comm[16];
	unsigned int  pid;
	unsigned long long value1;
	unsigned long long value2;
	unsigned long long value3;
};

/* ===== Tracepoint: sched/sched_switch ===== */
SEC("tracepoint/sched/sched_switch")
int trace_sched_switch(void *ctx)
{
	unsigned int cpu = bpf_get_smp_processor_id();
	unsigned long long *count;

	count = bpf_map_lookup_elem(&ctx_switch_count, &cpu);
	if (count) {
		__sync_fetch_and_add(count, 1);
	}

	/* Report every 100 switches to avoid ring buffer overflow */
	if (count && (*count % 100 == 0)) {
		struct cpu_event *e;
		e = bpf_ringbuf_reserve(&cpu_events, sizeof(*e), 0);
		if (e) {
			e->cpu_id = cpu;
			e->metric_type = 2;
			e->timestamp = bpf_ktime_get_ns();
			e->pid = bpf_get_current_pid_tgid() >> 32;
			bpf_get_current_comm(&e->comm, sizeof(e->comm));
			e->value1 = *count;
			e->value2 = 0;
			e->value3 = 0;
			bpf_ringbuf_submit(e, 0);
		}
	}
	return 0;
}

/* ===== Tracepoint: sched/sched_wakeup ===== */
SEC("tracepoint/sched/sched_wakeup")
int trace_sched_wakeup(void *ctx)
{
	unsigned int cpu = bpf_get_smp_processor_id();
	unsigned long long *wakeups;

	wakeups = bpf_map_lookup_elem(&wakeup_count, &cpu);
	if (wakeups) {
		__sync_fetch_and_add(wakeups, 1);
	}
	return 0;
}

/*
 * Tracepoint: power/cpu_frequency
 * Format (verified on kernel 6.17.0):
 *   common fields: 8 bytes (common_type, common_flags, common_preempt_count, common_pid)
 *   field:u32 state;   offset:8   (CPU frequency in KHz)
 *   field:u32 cpu_id;  offset:12  (CPU number)
 */
struct cpu_frequency_args {
	unsigned long long __pad;   /* common tracepoint fields (8 bytes) */
	unsigned int      state;    /* frequency in KHz */
	unsigned int      cpu_id;   /* CPU core id */
};

SEC("tracepoint/power/cpu_frequency")
int trace_cpu_frequency(struct cpu_frequency_args *ctx)
{
	unsigned int state  = ctx->state;
	unsigned int cpu_id = ctx->cpu_id;

	if (cpu_id >= MAX_CPUS)
		return 0;

	unsigned int *freq = bpf_map_lookup_elem(&cpu_freq_map, &cpu_id);
	if (freq) {
		*freq = state;
	}

	struct cpu_event *e;
	e = bpf_ringbuf_reserve(&cpu_events, sizeof(*e), 0);
	if (e) {
		e->cpu_id = cpu_id;
		e->metric_type = 3;
		e->timestamp = bpf_ktime_get_ns();
		e->pid = 0;
		__builtin_memset(e->comm, 0, sizeof(e->comm));
		e->value1 = state;   /* frequency in KHz */
		e->value2 = 0;
		e->value3 = 0;
		bpf_ringbuf_submit(e, 0);
	}
	return 0;
}
