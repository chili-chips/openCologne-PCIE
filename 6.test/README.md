# Lab Test

Tests of our EndPoint on a board, from the Linux host it is plugged into (a Raspberry Pi CM5, a PC). The simulation counterpart is [5.sim](../5.sim/README.md).

| File | What it does |
|---|---|
| [`1.sw/host/ep-link-test.c`](1.sw/host/ep-link-test.c) | the link and data-link test below |

## ep-link-test

A long run against the EP's BAR0, the firmware's 4 KB PIO memory ([3.sw](../3.sw/README.md)), in two phases:

| Phase | Default | What it does |
|---|---|---|
| Idle | 600 s | one 1-DW read of BAR0 a second: the link stays up with no traffic |
| Traffic | 600 s | every 5 s: a burst of 20,000 posted 1-DW writes to BAR0, timed (MB/s) and read back; then a write of a known value and 500 single reads of it, 20 µs apart, each timed (latency) and checked |

Every second, in both phases, it reads the root port's AER status (receiver error, bad TLP, bad DLLP, replay rollover, replay timeout, uncorrectable) and clears it (RW1C), and the root port's Link Status: a retrain or a link drop. Our EP has no AER, so the root port is where the host sees errors.

It ends with one report line per phase: the seconds with each AER flag set, retrains and link-down seconds; for traffic, the burst rate (min / mean / max), the read latency (min / mean / max) and the mismatches. It exits 0 when the link held and every read came back right.

### Build and run

On the host, as root:

```sh
gcc -O2 -o ep-link-test 1.sw/host/ep-link-test.c
echo 1 > /sys/bus/pci/rescan            # if the EP is not on the bus yet
sudo ./ep-link-test                     # the first device CC00:CC00, 10 + 10 min
sudo ./ep-link-test -d 0001:01:00.0 -i 60 -t 60
```

| Option | Default | Meaning |
|---|---|---|
| `-d BDF` | the first `CC00:CC00` | the EP; another ID needs it |
| `-i S`, `-t S` | 600, 600 | idle and traffic phase, seconds |
| `-n N` | 20000 | posted writes in a burst |
| `-m N`, `-g US` | 500, 20 | reads after a burst, and the gap between them |

### What to compare with

- **Write rate:** 1-DW writes at Gen1 x1 carry 4 bytes in 24 symbols, so the line limit is 41.7 MB/s. The RC model's tester measures the same in simulation (`5.sim`, `make BURST=2400`; the `===> Probe: posted burst` line). A rate far below the limit points at the EP's credits or its receive buffer ([#4](https://github.com/chili-chips/openCologne-PCIE/issues/4)).
- **Read latency:** the host's view, from the MRd to the CplD; the RC model prints its own (`===> Probe: read`).
- **AER:** any replay timeout or rollover means the EP's TLPs needed a replay; any bad TLP or DLLP means the line or our framing ([#27](https://github.com/chili-chips/openCologne-PCIE/issues/27) adds the EP's own counters).

--------------------
#### End of Document
