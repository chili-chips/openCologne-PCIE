// SPDX-FileCopyrightText: 2026 Chili.CHIPS
//
// SPDX-License-Identifier: BSD-3-Clause

//==========================================================================
// ep-link-test: a lab test of our EP from the Linux host (a Raspberry Pi
// CM5, a PC), run as root. Two phases:
//   idle     one 1-DW read of BAR0 a second: the link stays up
//   traffic  every 5 s a burst of posted 1-DW writes to BAR0, timed (MB/s)
//            and checked by reading back the last ones; then a write of a
//            known value and single 1-DW reads of it, spaced, each timed
//            (read latency) and checked
// Every second, in both: the root port's AER status (read, then cleared:
// RW1C) and its Link Status (speed, width, a retrain or a drop). The EP has
// no AER (no ECRC), so the root port's view is the one the host has.
// BAR0 is the firmware's PIO memory (4 KB, ../../../3.sw/EP/main.c): any DWORD.
//
// Build on the host: gcc -O2 -o ep-link-test ep-link-test.c
// Usage: sudo ./ep-link-test [-d BDF] [-i IDLE_S] [-t TRAFFIC_S] [-n BURST]
//                            [-m READS] [-g READ_GAP_US]
//   -d  the EP (default: the first device CC00:CC00)
//   -i  idle phase, s (default 600)      -t  traffic phase, s (default 600)
//   -n  writes in a burst (default 20000) -m reads after a burst (default 500)
//   -g  gap between those reads, us (default 20)
// Exit 0 when the link held and every read came back right.
//==========================================================================

#include <dirent.h>
#include <fcntl.h>
#include <libgen.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static const uint16_t EP_VENDOR = 0xCC00, EP_DEVICE = 0xCC00;   // 2.rtl/5.tlp/tl_pkg.sv
static const size_t   BAR0_SIZE = 4096;

static char ep_bdf[NAME_MAX + 1], rp_bdf[NAME_MAX + 1];
static int  rp_cfg = -1;
static int  rp_pcie_cap, rp_aer_cap;

static double now_s(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

static uint32_t cfg_rd(int fd, int off, int n)
{
    uint32_t v = 0;
    if (pread(fd, &v, n, off) != n) {
        return 0xFFFFFFFF;
    }
    return v;
}

// a sysfs file of a device: its first line
static int sys_read(const char *bdf, const char *name, char *buf, size_t len)
{
    char  p[PATH_MAX];
    FILE *f;
    snprintf(p, sizeof p, "/sys/bus/pci/devices/%s/%s", bdf, name);
    if (!(f = fopen(p, "r")) || !fgets(buf, (int)len, f)) {
        if (f) fclose(f);
        return -1;
    }
    fclose(f);
    return 0;
}

static int find_ep(void)
{
    DIR           *d = opendir("/sys/bus/pci/devices");
    struct dirent *e;
    char           v[32], dv[32];
    if (!d) return -1;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        if (sys_read(e->d_name, "vendor", v, sizeof v) || sys_read(e->d_name, "device", dv, sizeof dv)) continue;
        if (strtoul(v, 0, 16) == EP_VENDOR && strtoul(dv, 0, 16) == EP_DEVICE) {
            snprintf(ep_bdf, sizeof ep_bdf, "%s", e->d_name);
            closedir(d);
            return 0;
        }
    }
    closedir(d);
    return -1;
}

// the root port: the EP's parent in sysfs; its PCIe and AER capabilities
static int find_rp(void)
{
    char p[PATH_MAX], r[PATH_MAX];
    snprintf(p, sizeof p, "/sys/bus/pci/devices/%s", ep_bdf);
    if (!realpath(p, r)) return -1;
    snprintf(rp_bdf, sizeof rp_bdf, "%s", basename(dirname(r)));
    snprintf(p, sizeof p, "/sys/bus/pci/devices/%s/config", rp_bdf);
    if ((rp_cfg = open(p, O_RDWR)) < 0) return -1;
    for (int c = cfg_rd(rp_cfg, 0x34, 1) & 0xFC, n = 0; c >= 0x40 && n < 48; n++) {
        uint32_t h = cfg_rd(rp_cfg, c, 2);
        if ((h & 0xFF) == 0x10) rp_pcie_cap = c;
        c = (h >> 8) & 0xFC;
    }
    for (int c = 0x100, n = 0; c && n < 64; n++) {
        uint32_t h = cfg_rd(rp_cfg, c, 4);
        if (h == 0 || h == 0xFFFFFFFF) break;
        if ((h & 0xFFFF) == 0x0001) rp_aer_cap = c;
        c = (h >> 20) & 0xFFC;
    }
    return 0;
}

// AER Correctable Status bits, as counted (seconds with each set)
static const struct { int bit; const char *name; } COR[] = {
    {0, "receiver error"}, {6, "bad TLP"}, {7, "bad DLLP"}, {8, "replay rollover"}, {12, "replay timeout"},
};
enum { N_COR = sizeof COR / sizeof COR[0] };

struct phase {
    const char *name;
    int         secs, cor[N_COR], uncor, retrains, drops;
    int         bursts, mismatches, reads;
    double      mbs_min, mbs_max, mbs_sum, lat_min, lat_max, lat_sum;
};

static uint16_t link_status(void)
{
    return rp_pcie_cap ? (uint16_t)cfg_rd(rp_cfg, rp_pcie_cap + 0x12, 2) : 0;
}

// once a second: the root port's AER status (then cleared) and Link Status
static void tick(struct phase *p, uint16_t *ls_last)
{
    p->secs++;
    if (rp_aer_cap) {
        uint32_t u = cfg_rd(rp_cfg, rp_aer_cap + 0x04, 4), c = cfg_rd(rp_cfg, rp_aer_cap + 0x10, 4);
        for (int i = 0; i < N_COR; i++) p->cor[i] += (c >> COR[i].bit) & 1;
        p->uncor += u != 0;
        if (pwrite(rp_cfg, &c, 4, rp_aer_cap + 0x10) != 4 || pwrite(rp_cfg, &u, 4, rp_aer_cap + 0x04) != 4) {
            perror("AER clear");
        }
    }
    uint16_t ls = link_status();
    if ((ls & 0x0800) || (ls & 0x0F) != (*ls_last & 0x0F) || (ls & 0x03F0) != (*ls_last & 0x03F0)) p->retrains++;
    if (!(ls & 0x03F0)) p->drops++;   // width 0: no link
    *ls_last = ls;
}

static void burst_and_reads(volatile uint32_t *bar, struct phase *p, int n, int m, int gap_us)
{
    int    words = BAR0_SIZE / 4;
    double t0    = now_s();
    for (int i = 0; i < n; i++) bar[i % words] = 0x9E3779B9u * (uint32_t)i;
    (void)bar[0];                                       // a read: the writes are out (posted, ordered)
    double mbs = 4.0 * n / (now_s() - t0) / 1e6;
    for (int i = (n > words ? n - words : 0); i < n; i++) {
        p->mismatches += bar[i % words] != 0x9E3779B9u * (uint32_t)i;
    }
    p->mbs_min = p->bursts ? (mbs < p->mbs_min ? mbs : p->mbs_min) : mbs;
    p->mbs_max = mbs > p->mbs_max ? mbs : p->mbs_max;
    p->mbs_sum += mbs;
    p->bursts++;

    uint32_t v = 0x5A5A0000u | (uint32_t)p->bursts;
    bar[1] = v;
    for (int i = 0; i < m; i++) {
        double   t = now_s();
        uint32_t r = bar[1];
        double   l = (now_s() - t) * 1e6;                // us
        p->mismatches += r != v;
        p->lat_min = p->reads ? (l < p->lat_min ? l : p->lat_min) : l;
        p->lat_max = l > p->lat_max ? l : p->lat_max;
        p->lat_sum += l;
        p->reads++;
        usleep(gap_us);
    }
}

static void report(const struct phase *p)
{
    printf("%-8s %d s:", p->name, p->secs);
    for (int i = 0; i < N_COR; i++) printf(" %s %d,", COR[i].name, p->cor[i]);
    printf(" uncorrectable %d (seconds with it set); retrains %d, link down %d s\n", p->uncor, p->retrains, p->drops);
    if (p->bursts) {
        printf("         %d bursts: %.2f / %.2f / %.2f MB/s (min / mean / max); %d reads: %.2f / %.2f / %.2f us; "
               "%d mismatches\n", p->bursts, p->mbs_min, p->mbs_sum / p->bursts, p->mbs_max, p->reads, p->lat_min,
               p->lat_sum / p->reads, p->lat_max, p->mismatches);
    }
}

int main(int argc, char **argv)
{
    int idle_s = 600, traffic_s = 600, n = 20000, m = 500, gap_us = 20, o;
    while ((o = getopt(argc, argv, "d:i:t:n:m:g:")) != -1) {
        switch (o) {
            case 'd': snprintf(ep_bdf, sizeof ep_bdf, "%s", optarg); break;
            case 'i': idle_s = atoi(optarg); break;
            case 't': traffic_s = atoi(optarg); break;
            case 'n': n = atoi(optarg); break;
            case 'm': m = atoi(optarg); break;
            case 'g': gap_us = atoi(optarg); break;
            default: fprintf(stderr, "usage: %s [-d BDF] [-i S] [-t S] [-n N] [-m N] [-g US]\n", argv[0]); return 2;
        }
    }
    if (!ep_bdf[0] && find_ep()) {
        fprintf(stderr, "no device %04X:%04X: rescan the bus (echo 1 > /sys/bus/pci/rescan)\n", EP_VENDOR, EP_DEVICE);
        return 2;
    }
    if (find_rp()) {
        perror("root port config (run as root)");
        return 2;
    }

    char p[PATH_MAX];
    snprintf(p, sizeof p, "/sys/bus/pci/devices/%s/enable", ep_bdf);
    int fe = open(p, O_WRONLY);
    if (fe >= 0) { if (write(fe, "1", 1) != 1) perror("enable"); close(fe); }
    snprintf(p, sizeof p, "/sys/bus/pci/devices/%s/resource0", ep_bdf);
    int fd = open(p, O_RDWR | O_SYNC);
    volatile uint32_t *bar = fd < 0 ? MAP_FAILED : mmap(0, BAR0_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (bar == MAP_FAILED) {
        perror("BAR0");
        return 2;
    }
    printf("EP %s, root port %s (AER %s), BAR0 word 0: 0x%08X\n", ep_bdf, rp_bdf, rp_aer_cap ? "yes" : "none", bar[0]);

    uint16_t     ls   = link_status();
    struct phase idle = {.name = "idle"}, traffic = {.name = "traffic"};
    tick(&idle, &ls);                                     // clear what came before
    idle = (struct phase){.name = "idle"};
    for (int s = 0; s < idle_s; s++) {
        (void)bar[0];
        sleep(1);
        tick(&idle, &ls);
    }
    for (double t_end = now_s() + traffic_s, next = now_s(); now_s() < t_end;) {
        if (now_s() >= next) {
            burst_and_reads(bar, &traffic, n, m, gap_us);
            next += 5.0;
        }
        sleep(1);
        tick(&traffic, &ls);
    }
    report(&idle);
    report(&traffic);
    return (idle.drops || traffic.drops || traffic.mismatches) ? 1 : 0;
}
