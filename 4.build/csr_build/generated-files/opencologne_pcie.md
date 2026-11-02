<!--
SPDX-FileCopyrightText: 2026 Chili.CHIPS

SPDX-License-Identifier: BSD-3-Clause
-->

<!---
Markdown description for SystemRDL register map.

Don't override. Generated from: opencologne_pcie
  - csr_build/csr.rdl
-->

## opencologne_pcie address map

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x30000300

|  Offset  |Identifier|Name|
|----------|----------|----|
|0x00000000|   imem   |imem|
|0x30000000|    csr   | csr|

## imem memory

- Absolute Address: 0x0
- Base Offset: 0x0
- Size: 0x2000

<p>CPU Program/Data Memory</p>

No supported members.


## csr address map

- Absolute Address: 0x30000000
- Base Offset: 0x30000000
- Size: 0x300

<p>openCologne-PCIE EndPoint CSR</p>

|Offset|Identifier|     Name     |
|------|----------|--------------|
| 0x000|    tx    |    csr.tx    |
| 0x010|    rx    |    csr.rx    |
| 0x024|  status  |  csr.status  |
| 0x100|rx_payload|csr.rx_payload|
| 0x200|tx_payload|csr.tx_payload|

## tx register file

- Absolute Address: 0x30000000
- Base Offset: 0x0
- Size: 0x10

<p>TLP Transmit CSR (CPU --&gt; PCIe link)</p>

|Offset|Identifier|     Name     |
|------|----------|--------------|
|  0x0 |  header0 |csr.tx.header0|
|  0x4 |  header1 |csr.tx.header1|
|  0x8 |  header2 |csr.tx.header2|
|  0xC |   data   |  csr.tx.data |

### header0 register

- Absolute Address: 0x30000000
- Base Offset: 0x0
- Size: 0x4

<p>TLP Header DW0 -- Fmt/Type, TC, attributes and Length</p>

|Bits|Identifier|Access|Reset|          Name          |
|----|----------|------|-----|------------------------|
|31:0|    hdr   |  rw  | 0x0 |csr.tx.header0.hdr[31:0]|

#### hdr field

<p>1st header DWORD of the outgoing TLP</p>

### header1 register

- Absolute Address: 0x30000004
- Base Offset: 0x4
- Size: 0x4

<p>TLP Header DW1 -- for a Completion: Completer ID, status and Byte Count</p>

|Bits|Identifier|Access|Reset|          Name          |
|----|----------|------|-----|------------------------|
|31:0|    hdr   |  rw  | 0x0 |csr.tx.header1.hdr[31:0]|

#### hdr field

<p>2nd header DWORD of the outgoing TLP</p>

### header2 register

- Absolute Address: 0x30000008
- Base Offset: 0x8
- Size: 0x4

<p>TLP Header DW2 -- for a Completion: Requester ID, Tag and Lower Address</p>

|Bits|Identifier|Access|Reset|          Name          |
|----|----------|------|-----|------------------------|
|31:0|    hdr   |  rw  | 0x0 |csr.tx.header2.hdr[31:0]|

#### hdr field

<p>3rd header DWORD of the outgoing TLP</p>

### data register

- Absolute Address: 0x3000000C
- Base Offset: 0xC
- Size: 0x4

<p>TLP Payload DWORD -- writing this register STARTS the transfer</p>

|Bits|Identifier|Access|Reset|           Name          |
|----|----------|------|-----|-------------------------|
|31:0|  payload |  rw  | 0x0 |csr.tx.data.payload[31:0]|

#### payload field

<p>4th DWORD of the outgoing TLP: the 1st payload DWORD of a
3-DW TLP, or DW3 of a 4-DW header. Further DWORDs come from
tx_payload. A software write to this register is what
launches the Tx FSM, so it must be written LAST, after the
three header registers and tx_payload. The write strobe is
exported to logic as the 'swmod' output of this field.</p>

## rx register file

- Absolute Address: 0x30000010
- Base Offset: 0x10
- Size: 0x14

<p>TLP Receive CSR (PCIe link --&gt; CPU). An incoming TLP is captured
as it is: the 3 header DWORDs here, DW3 in rx.data and, from DW3
on, every DWORD in rx_payload. The firmware decodes them, then
clears rx.valid to take the next TLP.</p>

|Offset|Identifier|     Name     |
|------|----------|--------------|
| 0x00 |  header0 |csr.rx.header0|
| 0x04 |  header1 |csr.rx.header1|
| 0x08 |  header2 |csr.rx.header2|
| 0x0C |   data   |  csr.rx.data |
| 0x10 |   valid  | csr.rx.valid |

### header0 register

- Absolute Address: 0x30000010
- Base Offset: 0x0
- Size: 0x4

<p>TLP Header DW0 -- Fmt/Type, TC, attributes and Length</p>

|Bits|Identifier|Access|Reset|          Name          |
|----|----------|------|-----|------------------------|
|31:0|    hdr   |   r  | 0x0 |csr.rx.header0.hdr[31:0]|

#### hdr field

<p>1st header DWORD of the received TLP</p>

### header1 register

- Absolute Address: 0x30000014
- Base Offset: 0x4
- Size: 0x4

<p>TLP Header DW1 -- for a request: Requester ID, Tag and byte enables</p>

|Bits|Identifier|Access|Reset|          Name          |
|----|----------|------|-----|------------------------|
|31:0|    hdr   |   r  | 0x0 |csr.rx.header1.hdr[31:0]|

#### hdr field

<p>2nd header DWORD of the received TLP</p>

### header2 register

- Absolute Address: 0x30000018
- Base Offset: 0x8
- Size: 0x4

<p>TLP Header DW2 -- for a Memory request: the address</p>

|Bits|Identifier|Access|Reset|          Name          |
|----|----------|------|-----|------------------------|
|31:0|    hdr   |   r  | 0x0 |csr.rx.header2.hdr[31:0]|

#### hdr field

<p>3rd header DWORD of the received TLP</p>

### data register

- Absolute Address: 0x3000001C
- Base Offset: 0xC
- Size: 0x4

<p>TLP Payload DWORD, or DW3 of a 4-DW header</p>

|Bits|Identifier|Access|Reset|           Name          |
|----|----------|------|-----|-------------------------|
|31:0|  payload |   r  | 0x0 |csr.rx.data.payload[31:0]|

#### payload field

<p>4th DWORD of the received TLP: the 1st payload DWORD of a
3-DW MemWr, or the low address of a 4-DW request. The same
DWORD is entry 0 of rx_payload.</p>

### valid register

- Absolute Address: 0x30000020
- Base Offset: 0x10
- Size: 0x4

<p>Receive Status Register</p>

|Bits|Identifier|  Access |Reset|       Name       |
|----|----------|---------|-----|------------------|
|  0 |   valid  |rw, woclr| 0x0 |csr.rx.valid.valid|

#### valid field

<p>Set by hardware when a TLP has been captured. While it is
set, the link is held off (m_axis_rx.tready low). Software
writes 1 to clear it once it has read the TLP.</p>

## status register file

- Absolute Address: 0x30000024
- Base Offset: 0x24
- Size: 0x10

<p>PCIe Link Status CSR</p>

|Offset|Identifier|       Name      |
|------|----------|-----------------|
|  0x0 |    err   |  csr.status.err |
|  0x4 |    phy   |  csr.status.phy |
|  0x8 |  result  |csr.status.result|
|  0xC |  cfg_id  |csr.status.cfg_id|

### err register

- Absolute Address: 0x30000024
- Base Offset: 0x0
- Size: 0x4

<p>PCIe Error Status Register</p>

|Bits|  Identifier |Access|Reset|            Name            |
|----|-------------|------|-----|----------------------------|
| 16 |msg_err_fatal|   r  | 0x0 |csr.status.err.msg_err_fatal|

#### msg_err_fatal field

<p>A fatal-error Message TLP has been received</p>

### phy register

- Absolute Address: 0x30000028
- Base Offset: 0x4
- Size: 0x4

<p>PCIe PHY / Tx FSM Status Register</p>

|Bits| Identifier |Access|Reset|              Name              |
|----|------------|------|-----|--------------------------------|
| 5:0|tx_buf_avail|   r  | 0x0 |csr.status.phy.tx_buf_avail[5:0]|
| 7:6|  tx_state  |   r  | 0x0 |  csr.status.phy.tx_state[1:0]  |

#### tx_buf_avail field

<p>Number of free transmit buffers in the PCIe core
(tx_buf_avail). Software waits for a non-zero value.</p>

#### tx_state field

<p>State of the Tx FSM: 0 = IDLE, 1 = SEND_CYCLE_1,
2 = SEND_CYCLE_2, 3 = SEND_REST (beats out of tx_payload).
Software polls for 0 before it starts loading the next
TLP.</p>

### result register

- Absolute Address: 0x3000002C
- Base Offset: 0x8
- Size: 0x4

<p>Firmware Result Register</p>

|Bits|Identifier|Access|Reset|             Name             |
|----|----------|------|-----|------------------------------|
|31:0|  marker  |  rw  | 0x0 |csr.status.result.marker[31:0]|

#### marker field

<p>Result marker the firmware writes when it stops, e.g.
0x0000FACE for PASS. Unlike tx.data, writing it launches
no TLP: the value goes to logic only, to the PASS LED.</p>

### cfg_id register

- Absolute Address: 0x30000030
- Base Offset: 0xC
- Size: 0x4

<p>Core ID: the EP's own Bus/Device/Function number</p>

|Bits|Identifier|Access|Reset|           Name           |
|----|----------|------|-----|--------------------------|
|15:0|    id    |   r  | 0x0 |csr.status.cfg_id.id[15:0]|

#### id field

<p>Bus[15:8], Device[7:3] and Function[2:0] of this EP, as
the TL captured them from the last Type 0 Configuration
Write (UG477 cfg_bus_number, cfg_device_number,
cfg_function_number). The firmware puts this value in the
Completer ID of every Completion it sends. It is 0 until
the host has configured the EP, and its bus number depends
on the topology: behind a switch it is not the same as on
a direct link.</p>

## rx_payload memory

- Absolute Address: 0x30000100
- Base Offset: 0x100
- Size: 0x100

<p>DWORDs of the received TLP from DW3 on, captured with rx.valid:
entry i is DW 3+i, so entry 0 is rx.data. DWORDs past the last
entry are dropped.</p>

No supported members.


## tx_payload memory

- Absolute Address: 0x30000200
- Base Offset: 0x200
- Size: 0x100

<p>DWORDs of the outgoing TLP from DW4 on: entry i is DW 3+i. DW3
is tx.data, written last to launch the transfer, so entry 0 is
not sent. The TLP's Fmt and Length say how many entries go out.</p>

No supported members.

