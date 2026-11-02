# DLL simulation

| testbench | what it exercises | run |
|---|---|---|
| `tb_dll_wavecrux.v` | a fork of gatemate-pipe's `tb_dll_logic.v` with real TLP headers, makes the WaveCrux pictures | see [../README.md](../README.md#viewing-the-dll-in-wavecrux) |
| `tb_dll_phy.sv` | the DLL over a real PHY: two link partners over a serial link | `bash run-dll-phy.sh` |

## DLL over the PHY: `run-dll-phy.sh`

Two complete stacks, an Endpoint and a Root Complex, connected by a bit-level serial link in both directions:

```
       EP                                                    RC
  TL stimulus           tb_dll_phy.sv                   TL stimulus
       |                                                     |
  dll_logic             2.rtl/2.pipe/pipe_src           dll_logic
       |                                                     |
  ccfpga_LTSSM_logic    2.rtl/2.pipe/pipe_src           ccfpga_LTSSM_logic
       |                                                     |
  phy_model             2.rtl/4.dll/sim                 phy_model
  (ccfpga_pipe_logic + ccfpga_serdes model)
       |                                                     |
       +--------------- serial link, 2.5 Gb/s ---------------+
```

`pcie_stack.sv` is one side: the DLL, the MAC and the test-bench PHY [`phy_model.sv`](phy_model.sv), which is the PIPE logic, the SerDes model and a small SerDes bring-up FSM, so the layers above see a plain PIPE interface. The synthesizable `phy_top` will be the same with the `CC_SERDES` primitive in place of the SerDes model.

```sh
git submodule update --init                   # DLL, MAC and PIPE sources: the gatemate-pipe submodule
bash 2.rtl/4.dll/sim/run-dll-phy.sh           # ~15 s
bash 2.rtl/4.dll/sim/run-dll-phy.sh --dump    # with a waveform
bash 2.rtl/4.dll/sim/run-dll-phy.sh --inject=end   # #24: in place of steps 4 to 7, a TLP with its END (or stp: STP) hit
```

Build products and the waveform go to `$SERDES_BUILD_DIR/dll` (default `~/.cache/opencologne-pcie`). Tested with Icarus Verilog 13.

The test first trains both LTSSMs from Detect.Quiet to L0, every state change is printed. Then:

1. both DLLs go through InitFC1/InitFC2 to DL_Active
2. three TLPs EP to RC, every word is checked
3. two TLPs RC to EP, every word is checked
4. a TLP EP to RC three times, one byte corrupted at the RC's DLL input each time: its sequence number, a TLP byte, its LCRC; the RC Naks it and the EP replays it
5. an UpdateFC-P DLLP EP to RC with a byte of its CRC corrupted: the RC drops it; then a clean one
6. TLPs of 3, 5 and 7 DW in both directions, the last word marked with `tl_tx_tlp_last_half`: each is sent once, with 12, 20 or 28 TLP bytes on the line
7. step 4 with a 5 DW TLP, its last TLP byte corrupted

**Known gap:** [#24](https://github.com/chili-chips-ba/openCologne-PCIE/issues/24) (upstream [gatemate-pipe#15](https://github.com/colognechip/gatemate-pipe/issues/15)): the DLL has no REPLAY_TIMER, so a TLP whose STP or END is hit is never Naked or replayed, and the EP stops sending TLPs. `--inject=stp` and `--inject=end` show it: both fail until #24 is fixed (the regression lists them as known).

Every TLP the two DLLs send has its LCRC checked on the way out against a CRC-32 the testbench computes over the sequence number and TLP bytes; in step 6 also its length.

```
[   80256.0 ns] LINK : both MACs in L0, LinkUp
=== Step 1: DLL initialisation, InitFC1/InitFC2 across the link ===
[   83164.0 ns]   both DLLs DL_Active
  ...
=== Step 4: TLP with one field corrupted at the RC's receiver, expect NAK and replay ===
[  100740.0 ns]   RC received 6 DW, checked
[  103268.0 ns]   sequence number corrupted: EP sent the TLP 2 times, NAK and replay worked
  ...
=== Step 5: UpdateFC-P DLLPs, EP -> RC: its CRC corrupted, dropped; then clean ===
[  131172.0 ns]   RC dropped the UpdateFC with a bad CRC
[  132516.0 ns]   RC received UpdateFC hdr=10 data=200
  ...
[  164772.0 ns] LINE : 19 TLPs, LCRC checked, 0 wrong
  SUMMARY: 0 errors
  TEST PASSED
```

### The Root Complex side

The MAC implements the upstream port. The Root Complex is a second instance of it, set to the downstream port role with `force`:

* in Configuration it transmits link number 0, and from Config.Linkwidth.Accept on lane number 0 (`expected_Link`, `expected_Lane`)
* in Config.Linkwidth.Accept and Config.Lanenum.Accept it accepts both TS1 and TS2 (`TS1_pattern_en`, `TS2_pattern_en`)

### Settings

* scrambling is disabled in both MACs, as with `DISABLE_SCRAMBLING` in the MAC's pcievhost test
* the SerDes is set up and clocked as in `phy_top`: `PLL_FCNTRL = 6'h3A`, the PLL clock at the word rate, used as PCLK and as the SerDes TX and RX core clock, all 31.25 MHz
* the PIPE reset is released 256 `clk_aon` cycles after the global reset, the MAC and DLL reset once the SerDes reports ready, synchronised to PCLK
* the DLL gets `phy_linkup` when the MAC reports link up and the LTSSM is in L0; unlike `pcie_core` ([#35](https://github.com/chili-chips-ba/openCologne-PCIE/issues/35)), `pcie_stack.sv` does not hold it through Recovery
* the errors in steps 4, 5 and 7 are forced on the RC's DLL input (`phy_rx_data`, `phy_rx_data_k`) for one PCLK, at a fixed byte from the frame's STP or SDP: a K symbol becomes a data byte, a data byte gets bit 0 flipped. The same field is hit every run, whatever the timing

--------------------
#### End of Document
