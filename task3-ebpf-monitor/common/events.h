/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Shared event structures for user-space and kernel-space
 * These must match the definitions in the corresponding .bpf.c files.
 */
#ifndef __EVENTS_H__
#define __EVENTS_H__

struct cpu_event {
    unsigned int  cpu_id;
    unsigned int  metric_type;
    unsigned long long timestamp;
    char          comm[16];
    unsigned int  pid;
    unsigned long long value1;
    unsigned long long value2;
    unsigned long long value3;
};

struct mem_event {
    unsigned int  metric_type;
    unsigned long long timestamp;
    char          comm[16];
    unsigned int  pid;
    unsigned long long value1;
    unsigned long long value2;
    unsigned long long value3;
};

struct disk_event {
    unsigned int        metric_type;
    unsigned long long  timestamp;
    unsigned int        dev;
    char                disk_name[32];
    unsigned long long  value1;
    unsigned long long  value2;
    unsigned long long  value3;
};

struct file_event {
    unsigned int  metric_type;
    unsigned long long timestamp;
    char          comm[16];
    unsigned int  pid;
    unsigned long long value1;
    unsigned long long value2;
    unsigned long long value3;
};

struct net_event {
    unsigned int  metric_type;
    unsigned long long timestamp;
    unsigned int  ifindex;
    char          ifname[16];
    unsigned long long value1;
    unsigned long long value2;
    unsigned long long value3;
};

#endif /* __EVENTS_H__ */
