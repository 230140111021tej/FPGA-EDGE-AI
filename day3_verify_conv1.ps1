$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
Set-Location $root

# Replace the testbench with one that records every RTL output.
$tb = @'
`timescale 1ns/1ps
module tb_conv1_full_layer;
 reg clk=0, rst=1, start=0;
 wire busy, done, out_valid;
 wire [13:0] out_addr;
 wire [3:0] out_filter;
 wire signed [19:0] out_acc;
 integer count=0, cycles=0, fd;
 reg done_seen=0;
 integer errors=0;
 always #5 clk=~clk;

 conv1_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(out_addr),.out_filter(out_filter),.out_acc(out_acc),.out_valid(out_valid));

 initial begin
  fd = $fopen("conv1_rtl_outputs.txt","w");
  if(fd==0) begin $display("ERROR: cannot open output file"); $fatal(1); end
 end

 always @(posedge clk) begin
  if(rst) begin count<=0; done_seen<=0; errors<=0; end
  else begin
   if(out_valid) begin
    $fwrite(fd,"%0d %0d %0d\n",out_addr,out_filter,$signed(out_acc));
    if(out_addr !== count) begin
     $display("ERROR: expected address %0d got %0d",count,out_addr);
     errors<=errors+1;
    end
    count<=count+1;
   end
   if(done) done_seen<=1;
  end
 end

 initial begin
  repeat(4) @(posedge clk); rst<=0;
  @(posedge clk); start<=1;
  @(posedge clk); start<=0;
  while(!done_seen && cycles<150000) begin @(posedge clk); cycles=cycles+1; end
  #1;
  $fclose(fd);
  if(!done_seen || count!=10816 || errors!=0) begin
   $display("FAIL done=%0d outputs=%0d errors=%0d",done_seen,count,errors);
   $fatal(1);
  end
  $display("PASS: wrote %0d RTL outputs to conv1_rtl_outputs.txt",count);
  $finish;
 end
endmodule
'@
Set-Content "tb\tb_conv1_full_layer.v" $tb -Encoding ascii

# Independent integer reference using the same files, but independent Python arithmetic.
$py = @'
from pathlib import Path

root = Path(r"D:\FPGA_EdgeAI\cnn_baseline")
rom = root / "rom"

def load_hex(path, bits, signed=False):
    vals = []
    for line in path.read_text().splitlines():
        s = line.strip()
        if not s:
            continue
        v = int(s, 16)
        if signed and v & (1 << (bits - 1)):
            v -= 1 << bits
        vals.append(v)
    return vals

image = load_hex(rom / "conv1_image_u8_hex.mem", 8, False)
weights = load_hex(rom / "conv1_weights_int8_hex.mem", 8, True)
biases = load_hex(rom / "conv1_bias_int32_hex.mem", 32, True)
if len(image) != 784 or len(weights) != 144 or len(biases) != 16:
    raise SystemExit(f"Bad ROM lengths: image={len(image)} weights={len(weights)} biases={len(biases)}")

rtl_path = root / "conv1_rtl_outputs.txt"
if not rtl_path.exists():
    raise SystemExit(f"Missing RTL output file: {rtl_path}")
rtl = []
for line in rtl_path.read_text().splitlines():
    parts = line.split()
    if len(parts) == 3:
        rtl.append(tuple(map(int, parts)))
if len(rtl) != 10816:
    raise SystemExit(f"Expected 10816 RTL rows, found {len(rtl)}")

errors = 0
max_abs_diff = 0
first_errors = []
for filt in range(16):
    for pos in range(676):
        row, col = divmod(pos, 26)
        acc = biases[filt]
        for ky in range(3):
            for kx in range(3):
                pix = image[(row + ky) * 28 + col + kx]
                wt = weights[filt * 9 + ky * 3 + kx]
                acc += pix * wt
        # RTL accumulator is signed 20-bit and bias is truncated to 20 bits on load.
        acc20 = acc & ((1 << 20) - 1)
        if acc20 & (1 << 19):
            acc20 -= 1 << 20

        addr = filt * 676 + pos
        got_addr, got_filter, got_acc = rtl[addr]
        diff = abs(got_acc - acc20)
        max_abs_diff = max(max_abs_diff, diff)
        if got_addr != addr or got_filter != filt or got_acc != acc20:
            errors += 1
            if len(first_errors) < 10:
                first_errors.append((addr, filt, acc20, got_addr, got_filter, got_acc))

print(f"RTL rows: {len(rtl)}")
print(f"Compared outputs: 10816")
print(f"Mismatches: {errors}")
print(f"Maximum absolute difference: {max_abs_diff}")
if first_errors:
    print("First mismatches (expected_addr, expected_filter, expected_acc, rtl_addr, rtl_filter, rtl_acc):")
    for item in first_errors:
        print(item)
if errors:
    raise SystemExit(1)
print("PASS: all 10,816 accumulator values match the independent Python reference.")
'@
Set-Content "scripts\verify_conv1_reference.py" $py -Encoding ascii

$xvlog = Join-Path $vivado "xvlog.bat"
$xelab = Join-Path $vivado "xelab.bat"
$xsim = Join-Path $vivado "xsim.bat"
& $xvlog -work xil_defaultlib rtl\conv1_shared_mac.v rtl\conv1_full_layer.v tb\tb_conv1_full_layer.v
if ($LASTEXITCODE -ne 0) { throw "XSim compilation failed" }
& $xelab xil_defaultlib.tb_conv1_full_layer -s conv1_full_layer_sim
if ($LASTEXITCODE -ne 0) { throw "XSim elaboration failed" }
& $xsim conv1_full_layer_sim -runall
if ($LASTEXITCODE -ne 0) { throw "XSim simulation failed" }

python scripts\verify_conv1_reference.py
if ($LASTEXITCODE -ne 0) { throw "Numerical reference comparison failed; inspect mismatch report above." }
