# Five-Stage Pipelined RISC-V CPU on Basys 3

A Verilog implementation of a five-stage, 32-bit RISC-V processor, simulated with a self-checking instruction test and demonstrated on a Digilent Basys 3 Artix-7 FPGA.

The project focuses on the parts of a pipelined CPU to build and verify: data forwarding, load-use hazard handling, branch and jump redirection, and pipeline flushing. On the board, the eight user LEDs display the low eight word-address bits of the program counter, making CPU progress visible without external debug hardware.

## Highlights

- Five pipeline stages: **IF, ID, EX, MEM, WB**
- RV32I instruction groups exercised by the test program: integer register and immediate ALU operations, `LUI`, `AUIPC`, byte/halfword/word loads and stores, all six conditional branch conditions, `JAL`, and `JALR`
- EX-stage forwarding from later pipeline stages
- Load-use hazard detection with a one-cycle bubble
- Taken-branch and jump redirection with flushing of younger instructions
- Separate instruction and data memories so instruction fetch can overlap data-memory access
- Self-checking, 77-instruction simulation testbench
- Basys 3 clock-enable pacing: CPU state advances once every 5,000,000 cycles of the 100 MHz input clock (about 20 CPU steps per second)
- Basys 3 LEDs display `debug_pc[9:2]`; the center pushbutton is reset

## Target hardware and tools

- **Board:** Digilent Basys 3, Artix-7 `xc7a35tcpg236-1`
- **Clock:** 100 MHz onboard oscillator
- **HDL:** Verilog
- **Tool flow:** AMD Vivado (project developed with Vivado 2025.2)

## Architecture

The processor uses conventional IF/ID, ID/EX, EX/MEM, and MEM/WB pipeline registers. The register file contains 32 32-bit registers and hardwires `x0` to zero. The instruction memory holds 1,024 32-bit words and is initialized from `test.mem`. The data memory is 256 bytes and supports little-endian byte, halfword, and word accesses.

| Stage | Main work |
| --- | --- |
| IF | Fetch instruction and update the program counter |
| ID | Decode instruction, read registers, and detect load-use hazards |
| EX | ALU operation, forwarding, branch comparison, and redirect calculation |
| MEM | Data-memory loads and stores |
| WB | Write results, load data, or jump link values to the register file |

### Hazard and control-flow handling

- Forward the newest available ALU or link result to dependent instructions in EX.
- Insert a bubble when an instruction depends on a value being loaded by the instruction immediately ahead of it.
- Redirect the PC for taken branches, `JAL`, and `JALR`; flush younger instructions that followed the redirecting instruction.

## Verification

The self-checking testbench runs a 77-instruction program and checks architectural register and memory results, load/store byte ordering, jump link addresses, flushed instructions, and hazard behavior. It exercises:

- Register-register and immediate ALU operations, shifts, comparisons, `LUI`, and `AUIPC`
- `LB`, `LBU`, `LH`, `LHU`, and `LW`; plus `SB`, `SH`, and `SW`
- Forwarding, including load-to-store forwarding
- Two load-use stalls
- All six branch conditions: `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, and `BGEU`
- `JAL` and `JALR` link values and pipeline flushes

The testbench reports a `PASS` message only after its register, memory, stall, and redirect checks succeed. The project’s recorded simulation result passed this test.

## FPGA implementation and timing

The Basys 3 top module keeps all CPU state on the board’s 100 MHz clock and uses a clock enable to pace execution. It does not create a separate, divided CPU clock. This makes the program-counter display slow enough to observe while keeping a single clock domain.

The recorded Vivado implementation completed with:

- Setup WNS: **+2.117 ns**
- Hold WHS: **+0.050 ns**
- Setup and hold failing endpoints: **0**
- Routed failed nets: **0**

These timing results are for the constraints specified in `basys3.xdc`, including its multicycle exceptions for CPU state paths. They describe the reported implementation and constraint set; they are not a claim that every possible RV32I program or external I/O timing scenario has been formally verified.

## Repository layout

```text
riscv_cpu.xpr
riscv_cpu.srcs/
├── constrs_1/new/basys3.xdc       # Basys 3 clock, pin, I/O, and timing constraints
├── sim_1/new/cpu_tb.v             # Self-checking testbench
├── sim_1/new/test.mem             # Test program image
└── sources_1/new/
    ├── alu.v
    ├── cpu.v                      # Five-stage pipelined CPU
    ├── cpu_top.v                  # Basys 3 clock-enable and LED top level
    ├── dmem.v
    ├── regfile.v
    └── test.mem                   # Instruction memory initialization image
```

## Run the simulation

1. Open `riscv_cpu.xpr` in Vivado.
2. In **Simulation**, select **Run Simulation → Run Behavioral Simulation**.
3. Check the Tcl Console or simulation log for the testbench `PASS` message.

The simulation source set includes `cpu_tb.v` and `test.mem`. If running simulation from a different tool or working directory, ensure the `test.mem` initialization file is available in the simulator’s working directory because the CPU loads it with `$readmemh("test.mem", imem)`.

## Basys 3 pin mapping

| Signal | Basys 3 connection | FPGA package pin | I/O standard |
| --- | --- | --- | --- |
| `clk_in` | 100 MHz oscillator | W5 | LVCMOS33 |
| `reset` | Center pushbutton | U18 | LVCMOS33 |
| `led[0]` | LD0 | U16 | LVCMOS33 |
| `led[1]` | LD1 | E19 | LVCMOS33 |
| `led[2]` | LD2 | U19 | LVCMOS33 |
| `led[3]` | LD3 | V19 | LVCMOS33 |
| `led[4]` | LD4 | W18 | LVCMOS33 |
| `led[5]` | LD5 | U15 | LVCMOS33 |
| `led[6]` | LD6 | U14 | LVCMOS33 |
| `led[7]` | LD7 | V14 | LVCMOS33 |

## Loading a different program

The FPGA design initializes instruction memory from `test.mem`. To try another program, replace the memory image with 32-bit instruction words in the format expected by `$readmemh`, then rerun synthesis, implementation, and bitstream generation. The current design has a 1,024-word instruction memory and a 256-byte data memory.
