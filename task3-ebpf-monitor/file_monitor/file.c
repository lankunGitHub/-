/* File I/O Monitor - User-space Loader */
#include "../common/common.h"
#include "../common/events.h"
#include "file.skel.h"

static struct file_writer fw;

static const char *op_names[] = {"open", "close", "read", "write", "fsync"};

static int handle_event(void *ctx, void *data, size_t data_sz)
{
    struct file_event *e = data;
    char time_buf[32], buf[512];
    time_t now_t = time(NULL);
    strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M:%S", localtime(&now_t));
    const char *op = (e->metric_type < 5) ? op_names[e->metric_type] : "unknown";

    printf("  [FILE %s] PID=%u (%s) count=%llu\n", op, e->pid, e->comm, e->value1);
    snprintf(buf, sizeof(buf), "%s,File,%s,0,%u,%s,%llu,%llu,%llu,\n",
             time_buf, op, e->pid, e->comm, e->value1, e->value2, e->value3);
    file_writer_write(&fw, "%s", buf);
    return 0;
}

int main(int argc, char **argv)
{
    struct file_bpf *skel = NULL;
    struct ring_buffer *rb = NULL;
    int err;

    setup_signal_handler();
    err = bump_memlock_rlimit();
    if (err) return err;
    file_writer_init(&fw, "./log", "file_monitor", 100);

    skel = file_bpf__open();
    if (!skel) { PRINT_ERR("Failed to open File BPF skeleton"); return 1; }
    err = file_bpf__load(skel);
    if (err) { PRINT_ERR("Failed to load File BPF: %s", strerror(-err)); goto cleanup; }
    err = file_bpf__attach(skel);
    if (err) { PRINT_ERR("Failed to attach File BPF: %s", strerror(-err)); goto cleanup; }

    rb = ring_buffer__new(bpf_map__fd(skel->maps.file_events), handle_event, NULL, NULL);
    if (!rb) { PRINT_ERR("Failed to create ring buffer"); err = -1; goto cleanup; }

    printf("\033[2J\033[H");
    printf("╔════════════════════════════════════════════════════════════╗\n");
    printf("║        eBPF File I/O Performance Monitor                  ║\n");
    printf("╠════════════════════════════════════════════════════════════╣\n");
    PRINT_INFO("File I/O Monitor started. Press Ctrl+C to stop.");

    while (!exiting) {
        ring_buffer__poll(rb, 500);

        unsigned int keys[] = {0, 1, 2, 3, 4};
        unsigned long long open_cnt = 0, close_cnt = 0, read_cnt = 0,
                          write_cnt = 0, fsync_cnt = 0;

        bpf_map_lookup_elem(bpf_map__fd(skel->maps.file_op_count), &keys[0], &open_cnt);
        bpf_map_lookup_elem(bpf_map__fd(skel->maps.file_op_count), &keys[1], &close_cnt);
        bpf_map_lookup_elem(bpf_map__fd(skel->maps.file_op_count), &keys[2], &read_cnt);
        bpf_map_lookup_elem(bpf_map__fd(skel->maps.file_op_count), &keys[3], &write_cnt);
        bpf_map_lookup_elem(bpf_map__fd(skel->maps.file_op_count), &keys[4], &fsync_cnt);

        printf("\033[4;0H");
        printf("║  Open: %10llu | Close: %10llu                         ║\n", open_cnt, close_cnt);
        printf("║  Read: %10llu | Write: %10llu                         ║\n", read_cnt, write_cnt);
        printf("║  Fsync: %9llu                                        ║\n", fsync_cnt);

        /* Dentry cache stats */
        FILE *fp = fopen("/proc/sys/fs/dentry-state", "r");
        if (fp) {
            int dentries = 0, unused = 0;
            fscanf(fp, "%d %d", &dentries, &unused);
            printf("║  Dentry cache: %d entries (unused: %d)              ║\n", dentries, unused);
            fclose(fp);
        }
        fp = fopen("/proc/sys/fs/inode-nr", "r");
        if (fp) {
            long long inodes = 0, free_inodes = 0;
            fscanf(fp, "%lld %lld", &inodes, &free_inodes);
            printf("║  Inode cache: %lld allocated (free: %lld)            ║\n", inodes, free_inodes);
            fclose(fp);
        }

        char tbuf[32], buf[512];
        time_t now_t = time(NULL);
        strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", localtime(&now_t));
        snprintf(buf, sizeof(buf),
                 "%s,File,stats,0,0,,%llu,%llu,%llu,open=%llu close=%llu read=%llu write=%llu\n",
                 tbuf, read_cnt, write_cnt, open_cnt, open_cnt, close_cnt, read_cnt, write_cnt);
        file_writer_write(&fw, "%s", buf);

        fflush(stdout);
        sleep(1);
    }

    printf("\nFile I/O Monitor stopped.\n");
cleanup:
    ring_buffer__free(rb);
    file_bpf__destroy(skel);
    file_writer_close(&fw);
    return err < 0 ? -err : 0;
}
