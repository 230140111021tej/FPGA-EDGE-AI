# FPGA-Based Edge AI: Quantized CNN Inference and DSP-Accelerated MAC

An FPGA-oriented Edge AI project exploring quantized Convolutional Neural Network (CNN) inference, Verilog RTL implementation, hardware verification, and DSP-based multiply-accumulate (MAC) acceleration on the Digilent Basys 3 FPGA board.

## Project Overview

This project investigates how neural network computation can be mapped to FPGA hardware using fixed-point arithmetic and dedicated DSP resources. It combines a software CNN baseline, quantized model parameters, RTL development, simulation-based verification, and FPGA implementation experiments.

The objective is to understand the hardware implications of neural network inference, particularly arithmetic resource utilization, timing, and the trade-offs between logic-based and DSP-based MAC implementations.

## Key Features

- CNN baseline implemented and evaluated using PyTorch.
- INT8 weight-only quantization experiments.
- Verilog RTL development for arithmetic and MAC datapaths.
- Simulation and functional verification using Icarus Verilog and Verilator.
- Synthesis and implementation experiments using Xilinx Vivado.
- DSP48E1-based MAC implementation on the Basys 3 FPGA.
- Comparison of resource utilization and timing between baseline and DSP-oriented implementations.
- Automated test scripts, reports, and reference outputs for reproducibility.

## Hardware and Software

| Component | Technology |
|---|---|
| FPGA board | Digilent Basys 3 |
| FPGA device | Xilinx Artix-7 XC7A35T |
| RTL language | Verilog |
| FPGA toolchain | Xilinx Vivado 2025.1 |
| Simulation | Icarus Verilog, Verilator |
| CNN framework | PyTorch |
| Programming language | Python |
| Version control | Git and GitHub |

## CNN Baseline and Quantization

A small CNN was trained and evaluated using PyTorch as the software reference implementation.

The recorded baseline experiment achieved **98.56% test accuracy**. A weight-only INT8 quantization experiment retained the same recorded test accuracy of **98.56%**.

The project also includes integer multiply-accumulate checks and accumulator-width validation to investigate the arithmetic requirements of quantized inference.

These results describe the software model experiments. They should not be interpreted as measured end-to-end FPGA inference accuracy or throughput.

## DSP-Accelerated MAC Implementation

A dedicated MAC demonstration was implemented using Verilog and mapped to the Artix-7 DSP48E1 resource.

The design accepts activation and signed-weight values through board switches and push buttons. It supports loading operands, accumulating products, and clearing the accumulator.

### Demonstration controls

| Basys 3 control | Function |
|---|---|
| BTNC | Clear accumulator |
| BTNU | Load activation from switches |
| BTNR | Load signed weight |
| BTND | Execute MAC operation |
| Switches | Provide operand values |
| LEDs | Display the accumulator result |

### Hardware demonstration

For an activation of 5 and a weight of 3, the first MAC operation produces 15. Repeating the operation with the same operands produces an accumulated result of 30.

This demonstrates the basic multiply-accumulate behavior on the physical FPGA board.

## FPGA Implementation Results

The following results are from the recorded MAC demonstration implementations, not the complete CNN accelerator.

| Metric | Baseline MAC demo | DSP MAC demo |
|---|---:|---:|
| LUTs | 47 | 4 |
| Flip-flops | 42 | 12 |
| DSP48E1 blocks | 0 | 1 |
| BRAM blocks | 0 | 0 |
| Clock constraint | 100 MHz | 100 MHz |
| WNS | +3.634 ns | +7.748 ns |
| WHS | +0.187 ns | +0.211 ns |
| TNS | 0 | 0 |
| THS | 0 | 0 |

The DSP-based implementation reduced the reported LUT and flip-flop usage for this small MAC demonstration by mapping multiplication and accumulation to a dedicated DSP resource.

**Timing limitation:** the reports contain missing external I/O delay constraints. Therefore, the reported timing values describe the constrained implementation paths and do not establish complete external-interface timing closure.

These figures are specific to the tested designs and tool configuration; they should not be generalized to the full CNN datapath.

## Verification Approach

Verification activities include:

- RTL simulation using testbenches.
- Checking MAC arithmetic and accumulator behavior.
- Comparing outputs against expected reference values.
- Testing operand loading and accumulator clearing.
- Reviewing synthesis utilization and implementation timing reports.
- Programming the Basys 3 board and checking the MAC demonstration using physical controls and LEDs.

Simulation results and FPGA demonstration results should be distinguished from complete end-to-end CNN hardware validation.

## Repository Structure

The repository contains the following major areas:

| Directory | Purpose |
|---|---|
| `experiments/` | MAC implementations and FPGA experiments |
| `rtl/` | RTL modules |
| `sim/` | Simulation sources and testbenches |
| `tb/` | Additional testbench files |
| `reports/` | Synthesis, verification, and implementation reports |
| `results/` | Recorded experiment results and comparisons |
| `scripts/` | Automation and utility scripts |
| `data/` | Dataset-related project data |
| `models/` | Model artifacts, if present |
| `outputs/` | Generated outputs, if present |

Some generated build artifacts and the local raw MNIST dataset are intentionally excluded from Git history. Refer to the actual files in the repository for the current directory layout.

## Running the MAC Simulation

Install Icarus Verilog and ensure that `iverilog` and `vvp` are available in the terminal.

From the repository root, inspect the relevant RTL and testbench files under `experiments/dsp_inference/rtl/` and the corresponding testbench directory.

Compile and run the simulation using the appropriate source filenames. For example:

```bash
iverilog -g2012 -o mac_unit_tb.vvp \
  experiments/dsp_inference/rtl/mac_unit.v \
  experiments/dsp_inference/tb/mac_unit_tb.v

vvp mac_unit_tb.vvp
```

The exact testbench path may differ in the current repository. Check the directory contents before running the example.

## Reproducing the FPGA Results

1. Install Xilinx Vivado with support for the Artix-7 device.
2. Open the appropriate project or recreate it using the checked-in RTL and constraints.
3. Run synthesis and implementation.
4. Review utilization and timing reports.
5. Generate the bitstream.
6. Program the Basys 3 board and verify the MAC controls and LED output.

The selected DSP MAC demonstration bitstream is located at:

`experiments/dsp_inference/bitstream/mac_demo_top_dsp.bit`

Use the matching RTL and constraints when reproducing the design. Reported results may vary with tool versions, implementation settings, and constraints.

## Current Scope and Limitations

- The recorded CNN accuracy is from software evaluation.
- The DSP MAC demonstration validates a hardware arithmetic building block, not full end-to-end CNN inference.
- Complete CNN accelerator throughput, latency, power, and resource utilization have not been established by the MAC demo results.
- External I/O timing constraints require completion before claiming full interface timing closure.

## Future Work

- Integrate quantized CNN layers into a complete FPGA inference datapath.
- Connect the MAC unit to activation, buffering, control, and accumulation logic.
- Validate RTL outputs against software reference vectors.
- Measure end-to-end inference latency and throughput on the FPGA.
- Evaluate resource utilization and timing for progressively larger CNN blocks.
- Investigate memory bandwidth, parallelism, and DSP utilization trade-offs.
- Improve automated verification and regression testing.

## Author

**Electronics and Communication Engineering**

Focus areas: Digital Design, Verilog RTL, FPGA Implementation, Quantized Neural Networks, and Edge AI Hardware.

## License

A license has not yet been specified. Add an appropriate license before inviting others to reuse or redistribute the project.
