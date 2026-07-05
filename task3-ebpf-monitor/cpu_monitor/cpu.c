/* SPDX-License-Identifier: GPL-2.0 */
/* CPU Monitor - User-space Loader */
#include "../common/common.h"
#include "../common/events.h"
#include "cpu.skel.h"
#include <sys/sysinfo.h>

static struct file_writer fw;

static void display_header(void)
{
    printf("\033[2J\033[H");
    printf("╔══════════════════════════════════════════════════════════════════╗\n");
    printf("║              eBPF CPU Performance Monitor                       ║\n");
    printf("╠════════════╦═════════╦═════════╦═════════╦═════════╦════════════╣\n");
    printf("║    Core    ║ User%%   ║ Sys%%    ║ Idle%%   ║ IOWait%% ║ Freq (MHz)     ║\n");
    printf("╠════════════╬═════════╬═════════╬═════════╬═════════╬════════════╣\n");
}

static int handle_event(void *ctx, void *data, size_t data_sz)
{
    struct cpu_event *e = data;
    char time_buf[32], buf[512];

    switch (e->metric_type) {
    case 2: /* ctx switch */
        printf("  Context switches: total=%llu on CPU%u\n", e->value1, e->cpu_id);
        format_timestamp(e->timestamp, time_buf, sizeof(time_buf));
        snprintf(buf, sizeof(buf), "%s,CPU,ctx_switch,%u,%u,%s,%llu,0,0,\n",
                 time_buf, e->cpu_id, e->pid, e->comm, e->value1);
        file_writer_write(&fw, "%s", buf);
        break;
    case 3: /* frequency — value1 is in KHz from cpufreq */
        printf("  CPU %u frequency: %llu KHz (%.1f MHz)\n",
               e->cpu_id, e->value1, (double)e->value1 / 1000.0);
        format_timestamp(e->timestamp, time_buf, sizeof(time_buf));
        snprintf(buf, sizeof(buf), "%s,CPU,freq,%u,0,,%llu,0,0,\n",
                 time_buf, e->cpu_id, e->value1);
        file_writer_write(&fw, "%s", buf);
        break;
    }
    return 0;
}

int main(int argc, char **argv)
{
    struct cpu_bpf *skel = NULL;
    struct ring_buffer *rb = NULL;
    int err;

    setup_signal_handler();
    err = bump_memlock_rlimit();
    if (err) return err;

    file_writer_init(&fw, "./log", "cpu_monitor", 100);

    skel = cpu_bpf__open();
    if (!skel) { PRINT_ERR("Failed to open CPU BPF skeleton"); return 1; }

    err = cpu_bpf__load(skel);
    if (err) { PRINT_ERR("Failed to load CPU BPF: %s", strerror(-err)); goto cleanup; }

    err = cpu_bpf__attach(skel);
    if (err) { PRINT_ERR("Failed to attach CPU BPF: %s", strerror(-err)); goto cleanup; }

    rb = ring_buffer__new(bpf_map__fd(skel->maps.cpu_events), handle_event, NULL, NULL);
    if (!rb) { PRINT_ERR("Failed to create ring buffer"); err = -1; goto cleanup; }

    display_header();
    PRINT_INFO("CPU Monitor started. Press Ctrl+C to stop.");

    /* Static arrays for /proc/stat tracking */
    static unsigned long long prev_total[128], prev_idle[128];
    static int initialized = 0;

    while (!exiting) {
        ring_buffer__poll(rb, 100);

        FILE *fp = fopen("/proc/stat", "r");
        if (fp) {
            char line[256];
            while (fgets(line, sizeof(line), fp)) {
                char label[16];
                unsigned long long user, nice, system, idle, iowait,
                                 irq, softirq, steal;
                if (sscanf(line, "%s %llu %llu %llu %llu %llu %llu %llu %llu",
                           label, &user, &nice, &system, &idle,
                           &iowait, &irq, &softirq, &steal) < 8) continue;
                if (label[0] != 'c' || label[1] != 'p' || label[2] != 'u') continue;
                int cpu = atoi(label + 3);

                unsigned long long total = user + nice + system + idle + iowait + irq + softirq + steal;
                unsigned long long total_idle = idle + iowait;

                if (initialized && total > prev_total[cpu]) {
                    unsigned long long td = total - prev_total[cpu];
                    unsigned long long id = total_idle - prev_idle[cpu];
                    double util = 100.0 * (td - id) / td;
                    double upct = 100.0 * user / td;
                    double spct = 100.0 * (system + irq + softirq) / td;
                    double ipct = 100.0 * id / td;
                    double wpct = 100.0 * iowait / td;

                    /* Read CPU frequency from BPF map (in KHz), fallback to sysfs */
                    unsigned int freq_khz = 0;
                    bpf_map_lookup_elem(bpf_map__fd(skel->maps.cpu_freq_map),
                                       &cpu, &freq_khz);
                    /* sysfs fallback: /sys/devices/system/cpu/cpuN/cpufreq/scaling_cur_freq */
                    if (freq_khz == 0) {
                        char freq_path[64];
                        snprintf(freq_path, sizeof(freq_path),
                                 "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq", cpu);
                        FILE *ff = fopen(freq_path, "r");
                        if (ff) {
                            if (fscanf(ff, "%u", &freq_khz) != 1)
                                freq_khz = 0;
                            fclose(ff);
                        }
                    }
                    char freq_str[16];
                    if (freq_khz > 0)
                        snprintf(freq_str, sizeof(freq_str), "%.0f MHz",
                                 (double)freq_khz / 1000.0);
                    else
                        snprintf(freq_str, sizeof(freq_str), "N/A");

                    printf("║ CPU%-7d ║ %6.1f ║ %6.1f ║ %6.1f ║ %6.1f ║ %12s ║\n",
                           cpu, upct, spct, ipct, wpct, freq_str);

                    char tbuf[32], buf[512];
                    time_t now_t = time(NULL);
                    strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", localtime(&now_t));
                    snprintf(buf, sizeof(buf),
                             "%s,CPU,util,%d,0,,%.1f,%.1f,%.1f,user=%.1f sys=%.1f idle=%.1f\n",
                             tbuf, cpu, util, upct, spct, upct, spct, ipct);
                    file_writer_write(&fw, "%s", buf);
                }
                prev_total[cpu] = total;
                prev_idle[cpu] = total_idle;
            }
            fclose(fp);
            initialized = 1;
        }

        printf("\033[%d;0H", get_nprocs() + 6);
        fflush(stdout);
        sleep(1);
    }

    printf("\nCPU Monitor stopped.\n");
cleanup:
    ring_buffer__free(rb);
    cpu_bpf__destroy(skel);
    file_writer_close(&fw);
    return err < 0 ? -err : 0;
}
