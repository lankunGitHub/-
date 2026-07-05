/* Disk I/O Monitor - User-space Loader */
#include "../common/common.h"
#include "../common/events.h"
#include "disk.skel.h"

static struct file_writer fw;

/* Map dev numbers → names from /proc/diskstats */
static char disk_name_map[256][32];
static int  disk_name_loaded = 0;

static void load_disk_names(void)
{
	FILE *fp = fopen("/proc/diskstats", "r");
	if (!fp) return;
	char line[256];
	while (fgets(line, sizeof(line), fp)) {
		unsigned int major, minor;
		char name[32];
		if (sscanf(line, "%u %u %s", &major, &minor, name) == 3) {
			if (major < 256)
				snprintf(disk_name_map[major], sizeof(disk_name_map[major]), "%s", name);
		}
	}
	fclose(fp);
	disk_name_loaded = 1;
}

static const char *get_disk_name(unsigned int dev)
{
	if (!disk_name_loaded) load_disk_names();
	if (dev < 256 && disk_name_map[dev][0] != '\0')
		return disk_name_map[dev];
	return "disk";
}

static int handle_event(void *ctx, void *data, size_t data_sz)
{
	struct disk_event *e = data;
	char time_buf[32], buf[512], rbuf[32], wbuf[32];
	time_t now_t = time(NULL);
	strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M:%S", localtime(&now_t));
	format_bytes(e->value1, rbuf, sizeof(rbuf));
	format_bytes(e->value2, wbuf, sizeof(wbuf));
	const char *dname = get_disk_name(e->dev);

	printf("  [DISK %s] Read: %s | Write: %s | Avg Lat: %llu us | IOs: %llu\n",
	       dname, rbuf, wbuf, e->value3, e->value2 > 0 ? e->value2 : e->value1);
	snprintf(buf, sizeof(buf), "%s,Disk,io,%u,,%s,%llu,%llu,%llu,rd_wr_lat\n",
	         time_buf, e->dev, dname, e->value1, e->value2, e->value3);
	file_writer_write(&fw, "%s", buf);
	return 0;
}

int main(int argc, char **argv)
{
	struct disk_bpf *skel = NULL;
	struct ring_buffer *rb = NULL;
	int err;

	setup_signal_handler();
	err = bump_memlock_rlimit();
	if (err) return err;
	file_writer_init(&fw, "./log", "disk_monitor", 100);

	skel = disk_bpf__open();
	if (!skel) { PRINT_ERR("Failed to open Disk BPF skeleton"); return 1; }
	err = disk_bpf__load(skel);
	if (err) { PRINT_ERR("Failed to load Disk BPF: %s", strerror(-err)); goto cleanup; }
	err = disk_bpf__attach(skel);
	if (err) { PRINT_ERR("Failed to attach Disk BPF: %s", strerror(-err)); goto cleanup; }

	rb = ring_buffer__new(bpf_map__fd(skel->maps.disk_events), handle_event, NULL, NULL);
	if (!rb) { PRINT_ERR("Failed to create ring buffer"); err = -1; goto cleanup; }

	printf("\033[2J\033[H");
	printf("╔══════════════════════════════════════════════════════════════════════════╗\n");
	printf("║              eBPF Disk I/O Performance Monitor                         ║\n");
	printf("╠══════════════╦══════════════╦══════════════╦═══════════╦════════════════╣\n");
	printf("║    Device    ║  Read (MB)   ║  Write (MB)  ║   IOPS    ║  Latency (ms) ║\n");
	printf("╠══════════════╬══════════════╬══════════════╬═══════════╬════════════════╣\n");
	PRINT_INFO("Disk Monitor started. Press Ctrl+C to stop.");

	while (!exiting) {
		ring_buffer__poll(rb, 500);

		/* Display real-time /proc/diskstats for all block devices */
		FILE *fp = fopen("/proc/diskstats", "r");
		if (fp) {
			char line[256];
			printf("\033[5;0H");
			int row = 0;
			while (fgets(line, sizeof(line), fp) && row < 8) {
				unsigned int major, minor;
				char name[32];
				unsigned long long reads, read_sectors, writes, write_sectors,
				                  ios_in_progress, io_ms;
				unsigned long long dummy; /* discard merged/partial fields */

				if (sscanf(line, "%u %u %s %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu %llu",
				           &major, &minor, name,
				           &reads, &dummy, &read_sectors, &dummy,
				           &writes, &dummy, &write_sectors, &dummy,
				           &ios_in_progress, &io_ms, &dummy) >= 14) {

					/* Only show real block devices */
					if (name[0] != 's' && name[0] != 'n' && name[0] != 'v' &&
					    name[0] != 'x' && name[0] != 'l')
						continue;

					unsigned long long read_mb  = read_sectors * 512 / (1024 * 1024);
					unsigned long long write_mb = write_sectors * 512 / (1024 * 1024);
					unsigned long long total_ios = reads + writes;
					double avg_lat = total_ios > 0 ? (double)io_ms / total_ios : 0;

					printf("║ %-12s║ %10llu ║ %10llu ║ %8llu ║ %10.2f  ║\n",
					       name, read_mb, write_mb, total_ios, avg_lat);
					row++;

					/* Write to CSV */
					char tbuf[32], buf[512];
					time_t now_t = time(NULL);
					strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", localtime(&now_t));
					snprintf(buf, sizeof(buf), "%s,Disk,stats,%u,%u,%s,%llu,%llu,%llu,mb_rw_ios\n",
					         tbuf, major, minor, name, read_mb, write_mb, total_ios);
					file_writer_write(&fw, "%s", buf);
				}
			}
			fclose(fp);
		}
		fflush(stdout);
		sleep(1);
	}

	printf("\nDisk Monitor stopped.\n");
cleanup:
	ring_buffer__free(rb);
	disk_bpf__destroy(skel);
	file_writer_close(&fw);
	return err < 0 ? -err : 0;
}
