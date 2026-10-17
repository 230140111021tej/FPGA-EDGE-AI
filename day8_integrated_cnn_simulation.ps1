$ErrorActionPreference = "Stop"
$root = "D:\FPGA_EdgeAI\cnn_baseline"
$vivado = "D:\vivado\2025.1\Vivado\bin"
Set-Location $root

Write-Host "`n=== Day 8: Data-connected CNN RTL integration simulation ===" -ForegroundColor Cyan

# Generate references and ensure all input/parameter ROMs exist.
python scripts\generate_conv2_reference.py
if ($LASTEXITCODE -ne 0) { throw "Conv2 reference generation failed." }
python scripts\prepare_fc1_reference.py
if ($LASTEXITCODE -ne 0) { throw "FC1 reference generation failed." }
python scripts\prepare_fc2_reference.py
if ($LASTEXITCODE -ne 0) { throw "FC2 reference generation failed." }

$top = @'
`timescale 1ns/1ps
module cnn_integrated_sim_top(
 input wire clk,input wire rst,input wire start,
 output reg busy,output reg done,
 output reg [3:0] predicted_class,
 output reg scores_valid,
 output reg signed [31:0] score0,score1,score2,score3,score4,
 output reg signed [31:0] score5,score6,score7,score8,score9
);
 localparam C1_COUNT=12544;
 localparam C2_COUNT=6272;
 reg [7:0] c1_acts [0:12543];
 reg [7:0] c2_acts [0:6271];
 reg [7:0] pool1 [0:3135];
 reg [7:0] pool2 [0:1567];
 reg [7:0] fc1_acts [0:63];

 reg c1_start,c2_start,f1_start,f2_start;
 wire c1_busy,c1_done,c1_valid;
 wire [13:0] c1_addr;
 wire [3:0] c1_filter;
 wire signed [19:0] c1_acc;
 wire c1_act_valid;
 wire [7:0] c1_act;
 wire c2_busy,c2_done,c2_valid;
 wire [12:0] c2_addr;
 wire [4:0] c2_filter;
 wire signed [19:0] c2_acc;
 wire c2_act_valid;
 wire [7:0] c2_act;
 wire f1_busy,f1_done,f1_valid;
 wire [5:0] f1_addr;
 wire signed [31:0] f1_acc;
 wire f1_act_valid;
 wire [7:0] f1_act;
 wire f2_busy,f2_done,f2_valid;
 wire [3:0] f2_addr;
 wire signed [31:0] f2_score;

 reg [13:0] c1_addr_d;
 reg [12:0] c2_addr_d;
 reg [5:0] f1_addr_d;
 reg [3:0] f2_addr_d;
 integer phase,wait_count;
 integer f,y,x,base,mx;
 integer i;
 reg signed [31:0] scores [0:9];
 integer best_class;
 reg signed [31:0] best_score;

 conv1_full_layer c1(
  .clk(clk),.rst(rst),.start(c1_start),.busy(c1_busy),.done(c1_done),
  .out_addr(c1_addr),.out_filter(c1_filter),.out_acc(c1_acc),.out_valid(c1_valid)
 );
 conv1_requantize c1rq(.clk(clk),.rst(rst),.in_valid(c1_valid),.in_acc(c1_acc),
  .out_valid(c1_act_valid),.out_activation(c1_act));

 conv2_full_layer c2(
  .clk(clk),.rst(rst),.start(c2_start),.busy(c2_busy),.done(c2_done),
  .out_addr(c2_addr),.out_filter(c2_filter),.out_acc(c2_acc),.out_valid(c2_valid)
 );
 conv2_requantize c2rq(.clk(clk),.rst(rst),.in_valid(c2_valid),.in_acc(c2_acc),
  .out_valid(c2_act_valid),.out_data(c2_act));

 fc1_full_layer f1(.clk(clk),.rst(rst),.start(f1_start),.busy(f1_busy),.done(f1_done),
  .out_addr(f1_addr),.out_acc(f1_acc),.out_valid(f1_valid));
 fc1_requantize f1rq(.clk(clk),.rst(rst),.in_valid(f1_valid),.in_acc(f1_acc),
  .out_valid(f1_act_valid),.out_data(f1_act));

 fc2_full_layer f2(.clk(clk),.rst(rst),.start(f2_start),.busy(f2_busy),.done(f2_done),
  .out_addr(f2_addr),.out_score(f2_score),.out_valid(f2_valid));

 always @(posedge clk) begin
  if(rst) begin c1_addr_d<=0;c2_addr_d<=0;f1_addr_d<=0;f2_addr_d<=0;end
  else begin
   if(c1_valid) c1_addr_d<=c1_addr;
   if(c2_valid) c2_addr_d<=c2_addr;
   if(f1_valid) f1_addr_d<=f1_addr;
   if(f2_valid) f2_addr_d<=f2_addr;
   if(c1_act_valid) c1_acts[c1_addr_d]<=c1_act;
   if(c2_act_valid) c2_acts[c2_addr_d]<=c2_act;
   if(f1_act_valid) fc1_acts[f1_addr_d]<=f1_act;
   if(f2_valid) scores[f2_addr]<=f2_score;
  end
 end

 // This controller performs actual activation writeback between layer instances.
 // The existing layer modules expose ROM arrays internally; these writes update
 // their input memories before each subsequent layer is started.
 always @(posedge clk) begin
  if(rst) begin
   busy<=0;done<=0;predicted_class<=0;scores_valid<=0;
   score0<=0;score1<=0;score2<=0;score3<=0;score4<=0;
   score5<=0;score6<=0;score7<=0;score8<=0;score9<=0;
   c1_start<=0;c2_start<=0;f1_start<=0;f2_start<=0;
   phase<=0;wait_count<=0;best_class<=0;best_score<=-2147483647;
  end else begin
   done<=0;scores_valid<=0;
   c1_start<=0;c2_start<=0;f1_start<=0;f2_start<=0;
   if(start && !busy) begin busy<=1;phase<=1;c1_start<=1;end
   else begin
    case(phase)
     1: if(c1_done) begin phase<=2;wait_count<=3;end
     2: if(wait_count>0) wait_count<=wait_count-1;
        else begin
         for(f=0;f<16;f=f+1) begin
          for(y=0;y<14;y=y+1) begin
           for(x=0;x<14;x=x+1) begin
            base=f*784+(2*y)*28+(2*x);
            mx=c1_acts[base];
            if(c1_acts[base+1]>mx) mx=c1_acts[base+1];
            if(c1_acts[base+28]>mx) mx=c1_acts[base+28];
            if(c1_acts[base+29]>mx) mx=c1_acts[base+29];
            pool1[f*196+y*14+x]=mx[7:0];
            c2.input_map[f*196+y*14+x]=mx[7:0];
           end
          end
         end
         phase<=3;c2_start<=1;
        end
     3: if(c2_done) begin phase<=4;wait_count<=3;end
     4: if(wait_count>0) wait_count<=wait_count-1;
        else begin
         for(f=0;f<32;f=f+1) begin
          for(y=0;y<7;y=y+1) begin
           for(x=0;x<7;x=x+1) begin
            base=f*196+(2*y)*14+(2*x);
            mx=c2_acts[base];
            if(c2_acts[base+1]>mx) mx=c2_acts[base+1];
            if(c2_acts[base+14]>mx) mx=c2_acts[base+14];
            if(c2_acts[base+15]>mx) mx=c2_acts[base+15];
            pool2[f*49+y*7+x]=mx[7:0];
            f1.input_map[f*49+y*7+x]=mx[7:0];
           end
          end
         end
         phase<=5;f1_start<=1;
        end
     5: if(f1_done) begin phase<=6;wait_count<=3;end
     6: if(wait_count>0) wait_count<=wait_count-1;
        else begin
         for(i=0;i<64;i=i+1) f2.input_map[i]=fc1_acts[i];
         phase<=7;f2_start<=1;
        end
     7: if(f2_done) begin phase<=8;wait_count<=3;end
     8: if(wait_count>0) wait_count<=wait_count-1;
        else begin
         score0<=scores[0];score1<=scores[1];score2<=scores[2];score3<=scores[3];score4<=scores[4];
         score5<=scores[5];score6<=scores[6];score7<=scores[7];score8<=scores[8];score9<=scores[9];
         best_class=0;best_score=scores[0];
         for(i=1;i<10;i=i+1) if(scores[i]>best_score) begin best_score=scores[i];best_class=i;end
         predicted_class<=best_class[3:0];
         scores_valid<=1;done<=1;busy<=0;phase<=0;
        end
     default: begin end
    endcase
   end
  end
 end
endmodule
'@
Set-Content "rtl\cnn_integrated_sim_top.v" $top -Encoding ascii

$tb = @'
`timescale 1ns/1ps
module tb_cnn_integrated_validation;
 reg clk=0,rst=1,start=0;
 wire busy,done;
 wire [3:0] predicted_class;
 wire scores_valid;
 wire signed [31:0] s0,s1,s2,s3,s4,s5,s6,s7,s8,s9;
 integer cycles=0,fd;
 always #5 clk=~clk;
 cnn_integrated_sim_top dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .predicted_class(predicted_class),.scores_valid(scores_valid),
  .score0(s0),.score1(s1),.score2(s2),.score3(s3),.score4(s4),
  .score5(s5),.score6(s6),.score7(s7),.score8(s8),.score9(s9));
 initial begin
  fd=$fopen("cnn_rtl_final_scores.txt","w");
  if(fd==0) begin $display("ERROR opening final score file");$fatal(1);end
  repeat(4) @(posedge clk);rst<=0;
  @(posedge clk);start<=1;
  @(posedge clk);start<=0;
  while(!done && cycles<2000000) begin @(posedge clk);cycles=cycles+1;end
  #2;
  if(!done) begin $display("FAIL: integrated CNN timed out at %0d cycles",cycles);$fatal(1);end
  $fwrite(fd,"0 %0d\n",$signed(s0));$fwrite(fd,"1 %0d\n",$signed(s1));
  $fwrite(fd,"2 %0d\n",$signed(s2));$fwrite(fd,"3 %0d\n",$signed(s3));
  $fwrite(fd,"4 %0d\n",$signed(s4));$fwrite(fd,"5 %0d\n",$signed(s5));
  $fwrite(fd,"6 %0d\n",$signed(s6));$fwrite(fd,"7 %0d\n",$signed(s7));
  $fwrite(fd,"8 %0d\n",$signed(s8));$fwrite(fd,"9 %0d\n",$signed(s9));
  $fclose(fd);
  $display("Integrated CNN predicted class: %0d",predicted_class);
  $display("Integrated CNN simulation cycles: %0d",cycles);
  $finish;
 end
endmodule
'@
Set-Content "tb\tb_cnn_integrated_validation.v" $tb -Encoding ascii

$compare = @'
from pathlib import Path
import numpy as np
root=Path(r"D:\FPGA_EdgeAI\cnn_baseline")
ref=[int(x.strip()) for x in (root/"fc2_reference_scores.txt").read_text().splitlines() if x.strip()]
rtl=[]
for line in (root/"cnn_rtl_final_scores.txt").read_text().splitlines():
 p=line.split()
 if len(p)==2: rtl.append(tuple(map(int,p)))
if len(ref)!=10 or len(rtl)!=10:
 raise SystemExit(f"Final score count mismatch: reference={len(ref)}, RTL={len(rtl)}")
errors=[(i,ref[i],rtl[i]) for i in range(10) if rtl[i]!=(i,ref[i])]
print("Final class scores:",len(rtl),"mismatches:",len(errors))
if errors: print("Mismatches (class, expected, RTL row):",errors)
ref_pred=int(np.argmax(ref))
rtl_pred=max(range(10),key=lambda i:rtl[i][1])
print("Python predicted class:",ref_pred)
print("RTL predicted class:",rtl_pred)
if errors: raise SystemExit("Final score equivalence failed.")
if ref_pred!=rtl_pred: raise SystemExit("Final predicted class mismatch.")
print("PASS: final CNN scores and prediction match Python for this image.")
'@
Set-Content "scripts\compare_cnn_final.py" $compare -Encoding ascii

$xvlog=Join-Path $vivado "xvlog.bat"
$xelab=Join-Path $vivado "xelab.bat"
$xsim=Join-Path $vivado "xsim.bat"
& $xvlog -work xil_defaultlib rtl\conv1_shared_mac.v rtl\conv1_full_layer.v rtl\conv1_requantize.v rtl\conv2_shared_mac.v rtl\conv2_full_layer.v rtl\conv2_requantize.v rtl\fc1_shared_mac.v rtl\fc1_full_layer.v rtl\fc1_requantize.v rtl\fc2_shared_mac.v rtl\fc2_full_layer.v rtl\cnn_integrated_sim_top.v tb\tb_cnn_integrated_validation.v
if ($LASTEXITCODE -ne 0) { throw "Integrated CNN XSim compilation failed." }
& $xelab xil_defaultlib.tb_cnn_integrated_validation -s cnn_integrated_validation_sim
if ($LASTEXITCODE -ne 0) { throw "Integrated CNN XSim elaboration failed." }
& $xsim cnn_integrated_validation_sim -runall
if ($LASTEXITCODE -ne 0) { throw "Integrated CNN XSim simulation failed." }
python scripts\compare_cnn_final.py
if ($LASTEXITCODE -ne 0) { throw "Integrated CNN final comparison failed." }
Write-Host "`nDAY 8 COMPLETE: data-connected single-image CNN simulation matched Python." -ForegroundColor Green

