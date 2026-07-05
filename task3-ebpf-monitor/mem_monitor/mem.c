/* Memory Monitor - User-space Loader */
#include "../common/common.h"
#include "../common/events.h"
#include "mem.skel.h"

static struct file_writer fw;

static int handle_event(void *ctx, void *data, size_t data_sz)
{
    struct mem_event *e = data;
    char time_buf[32], buf[512];
    time_t now_t = time(NULL);
    strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M:%S", localtime(&now_t));

    switch (e->metric_type) {
    case 0:
        printf("  [PAGE FAULT] PID=%u (%s) total=%llu type=%s\n",
               e->pid, e->comm, e->value1, e->value2 == 1 ? "MINOR" : "MAJOR");
        snprintf(buf, sizeof(buf), "%s,Memory,page_fault,0,%u,%s,%llu,%llu,0,%s\n",
                 time_buf, e->pid, e->comm, e->value1, e->value2,
                 e->value2 == 1 ? "minor" : "major");
        break;
    case 2:
        printf("  [OOM KILL] PID=%u (%s) count=%llu\n", e->pid, e->comm, e->value1);
        snprintf(buf, sizeof(buf), "%s,Memory,OOM,0,%u,%s,%llu,0,0,OOM\n",
                 time_buf, e->pid, e->comm, e->value1);
        break;
    default:
        return 0;
    }
    file_writer_write(&fw, "%s", buf);
    return 0;
}

int main(int argc, char **argv)
{
    struct mem_bpf *skel = NULL;
    struct ring_buffer *rb = NULL;
    int err;

    setup_signal_handler();
    err = bump_memlock_rlimit();
    if (err) return err;
    file_writer_init(&fw, "./log", "mem_monitor", 100);

    skel = mem_bpf__open();
    if (!skel) { PRINT_ERR("Failed to open MEM BPF skeleton"); return 1; }
    err = mem_bpf__load(skel);
    if (err) { PRINT_ERR("Failed to load MEM BPF: %s", strerror(-err)); goto cleanup; }
    err = mem_bpf__attach(skel);
    if (err) { PRINT_ERR("Failed to attach MEM BPF: %s", strerror(-err)); goto cleanup; }

    rb = ring_buffer__new(bpf_map__fd(skel->maps.mem_events), handle_event, NULL, NULL);
    if (!rb) { PRINT_ERR("Failed to create ring buffer"); err = -1; goto cleanup; }

    printf("\033[2J\033[H");
    printf("╔════════════════════════════════════════════════════════════╗\n");
    printf("║        eBPF Memory Performance Monitor                    ║\n");
    printf("╠════════════════════════════════════════════════════════════╣\n");
    PRINT_INFO("Memory Monitor started. Press Ctrl+C to stop.");

    while (!exiting) {
        ring_buffer__poll(rb, 500);

        FILE *fp = fopen("/proc/meminfo", "r");
        if (fp) {
            char line[128];
            unsigned long long mem_total = 0, mem_free = 0, mem_avail = 0,
                              swap_total = 0, swap_free = 0, cached = 0, buffers = 0;
            while (fgets(line, sizeof(line), fp)) {
                unsigned long long val;
                if (sscanf(line, "MemTotal: %llu kB", &val)) mem_total = val;
                else if (sscanf(line, "MemFree: %llu kB", &val)) mem_free = val;
                else if (sscanf(line, "MemAvailable: %llu kB", &val)) mem_avail = val;
                else if (sscanf(line, "Cached: %llu kB", &val)) cached = val;
                else if (sscanf(line, "Buffers: %llu kB", &val)) buffers = val;
                else if (sscanf(line, "SwapTotal: %llu kB", &val)) swap_total = val;
                else if (sscanf(line, "SwapFree: %llu kB", &val)) swap_free = val;
            }
            fclose(fp);

            double used_pct = mem_total > 0 ? 100.0 * (mem_total - mem_avail) / mem_total : 0;
            double swap_used = swap_total - swap_free;

            printf("\033[4;0H");
            printf("║ MemTotal: %8llu MB | Used: %.1f%% | Avail: %8llu MB  ║\n",
                   mem_total / 1024, used_pct, mem_avail / 1024);
            printf("║ Cached:   %8llu MB | Buffers: %8llu MB                 ║\n",
                   cached / 1024, buffers / 1024);
            printf("║ Swap:     %8llu MB | Used:  %8llu MB                   ║\n",
                   swap_total / 1024, (unsigned long long)swap_used / 1024);

            char tbuf[32], buf[512];
            time_t now_t = time(NULL);
            strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", localtime(&now_t));
            snprintf(buf, sizeof(buf),
                     "%s,Memory,usage,0,0,,%.1f,%llu,%llu,used_pct=%.1f%%\n",
                     tbuf, used_pct, mem_avail / 1024,
                     (unsigned long long)swap_used / 1024, used_pct);
            file_writer_write(&fw, "%s", buf);
        }
        fflush(stdout);
        sleep(1);
    }

    printf("\nMemory Monitor stopped.\n");
cleanup:
    ring_buffer__free(rb);
    mem_bpf__destroy(skel);
    file_writer_close(&fw);
    return err < 0 ? -err : 0;
}
