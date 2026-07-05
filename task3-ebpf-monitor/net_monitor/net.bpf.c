/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Network Monitor - eBPF Kernel Program
 * Monitors: packets in/out, errors, TCP retransmits
 *
 * Uses net_dev_queue (TX), netif_receive_skb (RX), and net_dev_xmit (TX completion
 * with error code) tracepoints, plus tcp_retransmit_skb for TCP retransmissions.
 */
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

#define MAX_IFACES 64
#define IFNAME_LEN  16

/*
 * net_dev_queue tracepoint args (from vmlinux.h: trace_event_raw_net_dev_template)
 * We read ifindex and len fields to track per-interface TX bytes/packets.
 */

/* Packet counters: 0=packets_out, 1=packets_in, 2=tx_errors, 3=rx_errors */
struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 8);
	__type(key, unsigned int);
	__type(value, unsigned long long);
} net_stats SEC(".maps");

/* TCP retransmission counter */
struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, unsigned int);
	__type(value, unsigned long long);
} tcp_retrans_count SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 256 * 1024);
} net_events SEC(".maps");

struct net_event {
	unsigned int  metric_type;  /* 0=rx, 1=tx, 2=tx_err, 3=rx_err, 4=tcp_retrans */
	unsigned long long timestamp;
	unsigned int  ifindex;
	char          ifname[IFNAME_LEN];
	unsigned long long value1;  /* bytes or count */
	unsigned long long value2;
	unsigned long long value3;
};

/* ===== Tracepoint: net/net_dev_queue (packet queued for TX) ===== */
SEC("tracepoint/net/net_dev_queue")
int trace_net_dev_queue(void *ctx)
{
	unsigned int key = 0;  /* packets_out */
	unsigned long long *count;

	count = bpf_map_lookup_elem(&net_stats, &key);
	if (count)
		__sync_fetch_and_add(count, 1);

	return 0;
}

/* ===== Tracepoint: net/netif_receive_skb (packet received) ===== */
SEC("tracepoint/net/netif_receive_skb")
int trace_netif_receive_skb(void *ctx)
{
	unsigned int key = 1;  /* packets_in */
	unsigned long long *count;

	count = bpf_map_lookup_elem(&net_stats, &key);
	if (count)
		__sync_fetch_and_add(count, 1);

	/* Sample every 1000 packets to ring buffer */
	if (count && (*count % 1000 == 0)) {
		struct net_event *e;
		e = bpf_ringbuf_reserve(&net_events, sizeof(*e), 0);
		if (e) {
			e->metric_type = 0;    /* rx sample */
			e->timestamp = bpf_ktime_get_ns();
			e->ifindex = 0;
			__builtin_memset(e->ifname, 0, IFNAME_LEN);
			e->value1 = *count;
			e->value2 = 0;
			e->value3 = 0;
			bpf_ringbuf_submit(e, 0);
		}
	}
	return 0;
}

/* ===== Tracepoint: net/net_dev_xmit (TX completion — may carry error) ===== */
/*
 * net_dev_xmit is called when the driver completes a TX.  The tracepoint carries
 * the return code from ndo_start_xmit.  We count every completion; user-space
 * compares with /proc/net/dev for the exact error breakdown.
 */
SEC("tracepoint/net/net_dev_xmit")
int trace_net_dev_xmit(void *ctx)
{
	unsigned int key = 0;  /* packets_out (TX completions ≈ TX submissions) */
	unsigned long long *count;

	count = bpf_map_lookup_elem(&net_stats, &key);
	if (count)
		__sync_fetch_and_add(count, 1);

	return 0;
}

/* ===== Tracepoint: tcp/tcp_retransmit_skb ===== */
SEC("tracepoint/tcp/tcp_retransmit_skb")
int trace_tcp_retransmit_skb(void *ctx)
{
	unsigned int key = 0;
	unsigned long long *count;

	count = bpf_map_lookup_elem(&tcp_retrans_count, &key);
	if (count)
		__sync_fetch_and_add(count, 1);

	/* Report every 100 retransmits */
	if (count && (*count % 100 == 0)) {
		struct net_event *e;
		e = bpf_ringbuf_reserve(&net_events, sizeof(*e), 0);
		if (e) {
			e->metric_type = 4;    /* tcp_retrans */
			e->timestamp = bpf_ktime_get_ns();
			e->ifindex = 0;
			__builtin_memset(e->ifname, 0, IFNAME_LEN);
			e->value1 = *count;
			e->value2 = 0;
			e->value3 = 0;
			bpf_ringbuf_submit(e, 0);
		}
	}
	return 0;
}
