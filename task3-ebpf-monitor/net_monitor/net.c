/* Network Monitor - User-space Loader */
#include "../common/common.h"
#include "../common/events.h"
#include "net.skel.h"

static struct file_writer fw;

static int handle_event(void *ctx, void *data, size_t data_sz)
{
    struct net_event *e = data;
    char time_buf[32], buf[512];
    time_t now_t = time(NULL);
    strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M:%S", localtime(&now_t));

    switch (e->metric_type) {
    case 0:
        printf("  [NET IN]  %s packets=%llu\n", e->ifname, e->value1);
        break;
    case 4:
        printf("  [TCP RETRANS] total=%llu\n", e->value1);
        break;
    }
    snprintf(buf, sizeof(buf), "%s,Network,%u,%u,0,%s,%llu,%llu,%llu,\n",
             time_buf, e->metric_type, e->ifindex, e->ifname,
             e->value1, e->value2, e->value3);
    file_writer_write(&fw, "%s", buf);
    return 0;
}

int main(int argc, char **argv)
{
    struct net_bpf *skel = NULL;
    struct ring_buffer *rb = NULL;
    int err;

    setup_signal_handler();
    err = bump_memlock_rlimit();
    if (err) return err;
    file_writer_init(&fw, "./log", "net_monitor", 100);

    skel = net_bpf__open();
    if (!skel) { PRINT_ERR("Failed to open Net BPF skeleton"); return 1; }
    err = net_bpf__load(skel);
    if (err) { PRINT_ERR("Failed to load Net BPF: %s", strerror(-err)); goto cleanup; }
    err = net_bpf__attach(skel);
    if (err) { PRINT_ERR("Failed to attach Net BPF: %s", strerror(-err)); goto cleanup; }

    rb = ring_buffer__new(bpf_map__fd(skel->maps.net_events), handle_event, NULL, NULL);
    if (!rb) { PRINT_ERR("Failed to create ring buffer"); err = -1; goto cleanup; }

    printf("\033[2J\033[H");
    printf("╔════════════════════════════════════════════════════════════╗\n");
    printf("║        eBPF Network Performance Monitor                   ║\n");
    printf("╠════════════════════════════════════════════════════════════╣\n");
    PRINT_INFO("Network Monitor started. Press Ctrl+C to stop.");

    while (!exiting) {
        ring_buffer__poll(rb, 500);

        FILE *fp = fopen("/proc/net/dev", "r");
        if (fp) {
            char line[256];
            fgets(line, sizeof(line), fp); fgets(line, sizeof(line), fp); /* skip headers */
            printf("\033[4;0H");
            while (fgets(line, sizeof(line), fp)) {
                char ifname[32];
                unsigned long long rx_bytes, rx_packets, rx_errs, rx_drop,
                                  tx_bytes, tx_packets, tx_errs, tx_drop;
                if (sscanf(line, " %[^:]: %llu %llu %llu %llu %*u %*u %*u %*u %llu %llu %llu %llu",
                           ifname, &rx_bytes, &rx_packets, &rx_errs, &rx_drop,
                           &tx_bytes, &tx_packets, &tx_errs, &tx_drop) >= 11) {
                    if (rx_bytes > 0 || tx_bytes > 0) {
                        double rx_mb = rx_bytes / (1024.0 * 1024.0);
                        double tx_mb = tx_bytes / (1024.0 * 1024.0);
                        printf("║ %-8s RX: %8.1f MB (%llu pkts) | TX: %8.1f MB (%llu pkts) ║\n",
                               ifname, rx_mb, rx_packets, tx_mb, tx_packets);
                        if (rx_errs + tx_errs + rx_drop + tx_drop > 0)
                            printf("║   Err: RX=%llu TX=%llu Drop: RX=%llu TX=%llu  ║\n",
                                   rx_errs, tx_errs, rx_drop, tx_drop);
                    }
                }
            }
            fclose(fp);
        }

        fp = fopen("/proc/net/tcp", "r");
        if (fp) {
            int est = 0, listen = 0, time_wait = 0, close_wait = 0;
            char line[256];
            fgets(line, sizeof(line), fp);
            while (fgets(line, sizeof(line), fp)) {
                char *p = line;
                int field = 0;
                char st_str[8] = {0};
                while (*p) {
                    if (*p == ' ' || *p == '\t') { while (*p == ' ' || *p == '\t') p++; field++; if (field == 3) break; }
                    else p++;
                }
                if (field == 3) { sscanf(p, "%2s", st_str); int st = (int)strtol(st_str, NULL, 16);
                    if (st == 1) est++; else if (st == 10) listen++;
                    else if (st == 6) time_wait++; else if (st == 8) close_wait++; }
            }
            fclose(fp);
            printf("║  TCP ESTAB:%d LISTEN:%d TIME_WAIT:%d CLOSE_WAIT:%d  ║\n",
                   est, listen, time_wait, close_wait);

            char tbuf[32], buf[512];
            time_t now_t = time(NULL);
            strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", localtime(&now_t));
            snprintf(buf, sizeof(buf),
                     "%s,Network,tcp,0,0,,%d,%d,%d,ESTAB=%d LISTEN=%d TW=%d CW=%d\n",
                     tbuf, est, listen, time_wait, est, listen, time_wait, close_wait);
            file_writer_write(&fw, "%s", buf);
        }

        fflush(stdout);
        sleep(1);
    }

    printf("\nNetwork Monitor stopped.\n");
cleanup:
    ring_buffer__free(rb);
    net_bpf__destroy(skel);
    file_writer_close(&fw);
    return err < 0 ? -err : 0;
}
