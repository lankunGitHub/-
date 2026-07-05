/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Disk I/O Monitor - eBPF Kernel Program
 * Monitors: read/write bytes, IOPS, I/O latency via block tracepoints
 *
 * Uses trace_event_raw_block_rq (issue) and trace_event_raw_block_rq_completion
 * to count IOPS and bytes per device, distinguishing reads from writes.
 * Latency is estimated by tracking in-flight I/O start times keyed by
 * (dev, sector) — a reasonable approximation for non-overlapping I/O.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

#define MAX_DISKS 16
#define DISK_NAME_LEN 32

/* Per-device aggregated I/O statistics */
struct disk_io_stats {
	unsigned long long rd_bytes;
	unsigned long long wr_bytes;
	unsigned long long rd_ops;
	unsigned long long wr_ops;
	unsigned long long total_lat_us;
	unsigned long long io_cnt;
	unsigned long long io_in_flight;
};

/* Used as key: (dev << 32) | (sector & 0xffffffff) → approximate per-request tracking */
struct io_key {
	unsigned int  dev;
	unsigned long long sector;
};

struct io_start {
	unsigned long long start_time_ns;
	unsigned long long bytes;
	int is_read;
};

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 256);
	__type(key, unsigned int);         /* dev major */
	__type(value, struct disk_io_stats);
} disk_stats_map SEC(".maps");

/* Track in-flight I/O: key=(dev,sector), value=start info */
struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 10240);
	__type(key, struct io_key);
	__type(value, struct io_start);
} io_start_map SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 256 * 1024);
} disk_events SEC(".maps");

struct disk_event {
	unsigned int        metric_type;   /* 0=io_stats, 1=latency */
	unsigned long long  timestamp;
	unsigned int        dev;
	char                disk_name[DISK_NAME_LEN];
	unsigned long long  value1;        /* rd_bytes or rd_ops  */
	unsigned long long  value2;        /* wr_bytes or wr_ops  */
	unsigned long long  value3;        /* avg_lat_us or io_cnt */
};

static __always_inline int is_read_op(const char *rwbs)
{
	/* rwbs[0]: R=read, W=write, D=discard, F=flush, etc. */
	char op = rwbs[0];
	return (op == 'R' || op == 'r');
}

static __always_inline int is_write_op(const char *rwbs)
{
	char op = rwbs[0];
	return (op == 'W' || op == 'w' || op == 'D' || op == 'F');
}

/* ===== Tracepoint: block/block_rq_issue ===== */
SEC("tracepoint/block/block_rq_issue")
int trace_block_rq_issue(struct trace_event_raw_block_rq *ctx)
{
	unsigned int dev = (unsigned int)ctx->dev;
	unsigned long long now = bpf_ktime_get_ns();
	unsigned int nr_sector = ctx->nr_sector;
	unsigned long long bytes = (unsigned long long)nr_sector * 512;

	struct disk_io_stats *ds, new_ds = {};
	ds = bpf_map_lookup_elem(&disk_stats_map, &dev);
	if (!ds) {
		bpf_map_update_elem(&disk_stats_map, &dev, &new_ds, BPF_ANY);
		ds = bpf_map_lookup_elem(&disk_stats_map, &dev);
		if (!ds)
			return 0;
	}

	if (is_read_op(ctx->rwbs)) {
		__sync_fetch_and_add(&ds->rd_ops, 1);
	} else if (is_write_op(ctx->rwbs)) {
		__sync_fetch_and_add(&ds->wr_ops, 1);
	}
	__sync_fetch_and_add(&ds->io_in_flight, 1);

	/* Track start time for latency estimation */
	struct io_key key = { .dev = dev, .sector = (unsigned long long)ctx->sector };
	struct io_start start = {
		.start_time_ns = now,
		.bytes = bytes,
		.is_read = is_read_op(ctx->rwbs) ? 1 : 0
	};
	bpf_map_update_elem(&io_start_map, &key, &start, BPF_ANY);

	return 0;
}

/* ===== Tracepoint: block/block_rq_complete ===== */
SEC("tracepoint/block/block_rq_complete")
int trace_block_rq_complete(struct trace_event_raw_block_rq_completion *ctx)
{
	unsigned int dev = (unsigned int)ctx->dev;
	unsigned long long now = bpf_ktime_get_ns();
	unsigned int nr_sector = ctx->nr_sector;
	unsigned long long bytes = (unsigned long long)nr_sector * 512;

	struct disk_io_stats *ds;
	ds = bpf_map_lookup_elem(&disk_stats_map, &dev);
	if (!ds) {
		struct disk_io_stats new_ds = {};
		bpf_map_update_elem(&disk_stats_map, &dev, &new_ds, BPF_ANY);
		ds = bpf_map_lookup_elem(&disk_stats_map, &dev);
		if (!ds)
			return 0;
	}

	if (is_read_op(ctx->rwbs)) {
		__sync_fetch_and_add(&ds->rd_bytes, bytes);
	} else if (is_write_op(ctx->rwbs)) {
		__sync_fetch_and_add(&ds->wr_bytes, bytes);
	}
	__sync_fetch_and_add(&ds->io_cnt, 1);

	/* Calculate latency if we have a matching start record */
	struct io_key key = { .dev = dev, .sector = (unsigned long long)ctx->sector };
	struct io_start *start = bpf_map_lookup_elem(&io_start_map, &key);
	if (start) {
		unsigned long long lat_ns = now - start->start_time_ns;
		unsigned long long lat_us = lat_ns / 1000;
		__sync_fetch_and_add(&ds->total_lat_us, lat_us);
		bpf_map_delete_elem(&io_start_map, &key);
	}

	/* Report every 100 completions to avoid ring buffer overflow */
	if (ds->io_cnt % 100 == 0) {
		struct disk_event *e;
		e = bpf_ringbuf_reserve(&disk_events, sizeof(*e), 0);
		if (e) {
			e->metric_type = 0;
			e->timestamp = now;
			e->dev = dev;
			__builtin_memset(e->disk_name, 0, DISK_NAME_LEN);
			e->disk_name[0] = 'd';
			e->disk_name[1] = 'i';
			e->disk_name[2] = 's';
			e->disk_name[3] = 'k';
			e->disk_name[4] = '\0';
			e->value1 = ds->rd_bytes;
			e->value2 = ds->wr_bytes;
			e->value3 = ds->io_cnt > 0 ? ds->total_lat_us / ds->io_cnt : 0;
			bpf_ringbuf_submit(e, 0);
		}
	}
	return 0;
}
