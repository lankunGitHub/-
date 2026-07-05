/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Common utilities: file writer, signal handling, formatting helpers
 */
#include "common.h"
#include <stdarg.h>
#include <sys/stat.h>
#include <sys/types.h>

volatile int exiting = 0;

static void sig_handler(int sig) { exiting = 1; }

void setup_signal_handler(void)
{
    struct sigaction sa = {};
    sa.sa_handler = sig_handler;
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
}

int bump_memlock_rlimit(void)
{
    struct rlimit rlim = { .rlim_cur = RLIM_INFINITY, .rlim_max = RLIM_INFINITY };
    if (setrlimit(RLIMIT_MEMLOCK, &rlim)) {
        PRINT_ERR("Failed to increase RLIMIT_MEMLOCK (need sudo?)");
        return -errno;
    }
    return 0;
}

int file_writer_init(struct file_writer *fw, const char *dir,
                     const char *prefix, size_t max_size_mb)
{
    char cmd[256];
    memset(fw, 0, sizeof(*fw));
    strncpy(fw->dir, dir, sizeof(fw->dir) - 1);
    fw->max_size = max_size_mb * 1024 * 1024;
    fw->compress_old = 1;

    snprintf(cmd, sizeof(cmd), "mkdir -p %s", dir);
    system(cmd);

    snprintf(fw->filename, sizeof(fw->filename), "%s/%s_current.csv", dir, prefix);
    fw->fp = fopen(fw->filename, "a");
    if (!fw->fp) {
        PRINT_ERR("Cannot open log file: %s", fw->filename);
        return -1;
    }

    fseek(fw->fp, 0, SEEK_END);
    fw->current_size = ftell(fw->fp);
    if (fw->current_size == 0) {
        fprintf(fw->fp, "timestamp,module,metric,cpu,pid,comm,value1,value2,value3,label\n");
        fflush(fw->fp);
        fw->current_size = ftell(fw->fp);
    }
    PRINT_INFO("File writer ready: %s", fw->filename);
    return 0;
}

int file_writer_write(struct file_writer *fw, const char *fmt, ...)
{
    if (!fw || !fw->fp) return -1;
    if (fw->current_size >= fw->max_size && fw->max_size > 0)
        file_writer_rotate(fw);

    va_list args;
    va_start(args, fmt);
    int len = vfprintf(fw->fp, fmt, args);
    va_end(args);

    if (len > 0) {
        fw->current_size += len;
        fflush(fw->fp);
    }
    return len;
}

int file_writer_rotate(struct file_writer *fw)
{
    char old_name[512], new_name[512], cmd[768];
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    char ts[64];
    strftime(ts, sizeof(ts), "%Y%m%d_%H%M%S", t);

    if (fw->fp) { fclose(fw->fp); fw->fp = NULL; }

    /* Build base name by stripping _current.csv */
    char base[256];
    strncpy(base, fw->filename, sizeof(base) - 1);
    base[sizeof(base) - 1] = '\0';
    char *p = strstr(base, "_current.csv");
    if (p) *p = '\0';

    snprintf(old_name, sizeof(old_name), "%s_current.csv", base);
    snprintf(new_name, sizeof(new_name), "%s_%s.csv", base, ts);
    rename(old_name, new_name);

    if (fw->compress_old) {
        snprintf(cmd, sizeof(cmd), "gzip -f '%s' &", new_name);
        system(cmd);
    }

    snprintf(old_name, sizeof(old_name), "%s_current.csv", base);
    fw->fp = fopen(old_name, "a");
    if (fw->fp) {
        fprintf(fw->fp, "timestamp,module,metric,cpu,pid,comm,value1,value2,value3,label\n");
        fw->current_size = ftell(fw->fp);
        fw->rotation_count++;
        PRINT_INFO("File rotated (#%d)", fw->rotation_count);
    }
    file_writer_cleanup(fw, 7);
    return 0;
}

int file_writer_cleanup(struct file_writer *fw, int keep_days)
{
    char cmd[512];
    snprintf(cmd, sizeof(cmd),
             "find '%s' -name '*.csv.gz' -mtime +%d -delete 2>/dev/null",
             fw->dir, keep_days);
    return system(cmd);
}

void file_writer_close(struct file_writer *fw)
{
    if (fw && fw->fp) {
        fflush(fw->fp);
        fclose(fw->fp);
        fw->fp = NULL;
        PRINT_INFO("File writer closed: %s", fw->filename);
    }
}

double calc_rate(unsigned long long current, unsigned long long prev, double interval)
{
    if (interval <= 0) return 0.0;
    if (current < prev) return 0.0;
    return (double)(current - prev) / interval;
}

const char *format_bytes(unsigned long long bytes, char *buf, size_t len)
{
    const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    int idx = 0;
    double val = (double)bytes;
    while (val >= 1024.0 && idx < 4) { val /= 1024.0; idx++; }
    snprintf(buf, len, "%.2f %s", val, units[idx]);
    return buf;
}

const char *format_timestamp(unsigned long long ts_ns, char *buf, size_t len)
{
    time_t sec = (time_t)(ts_ns / 1000000000ULL);
    int ms = (int)((ts_ns / 1000000ULL) % 1000);
    struct tm *t = localtime(&sec);
    size_t n = strftime(buf, len, "%Y-%m-%d %H:%M:%S", t);
    snprintf(buf + n, len - n, ".%03d", ms);
    return buf;
}

unsigned long long get_timestamp_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (unsigned long long)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}
