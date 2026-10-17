`timescale 1ns/1ps
module tb_conv1_requant_validation;
 reg clk=0, rst=1, start=0;
 wire busy, done, acc_valid;
 wire [13:0] out_addr;
 wire [3:0] out_filter;
 wire signed [19:0] out_acc;
 wire act_valid;
 wire [7:0] activation;
 integer count=0, act_count=0, cycles=0, fd_acc, fd_act;
 reg done_seen=0;
 integer errors=0;
 always #5 clk=~clk;

 conv1_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(out_addr),.out_filter(out_filter),.out_acc(out_acc),.out_valid(acc_valid));
 conv1_requantize rq(.clk(clk),.rst(rst),.in_valid(acc_valid),.in_acc(out_acc),
  .out_valid(act_valid),.out_activation(activation));

 initial begin
  fd_acc=$fopen("conv1_rtl_outputs.txt","w");
  fd_act=$fopen("conv1_rtl_activations.txt","w");
  if(fd_acc==0 || fd_act==0) begin $display("ERROR: cannot open output files"); $fatal(1); end
 end

 always @(posedge clk) begin
  if(rst) begin count<=0; act_count<=0; done_seen<=0; errors<=0; end
  else begin
   if(acc_valid) begin
    $fwrite(fd_acc,"%0d %0d %0d\n",out_addr,out_filter,$signed(out_acc));
    if(out_addr !== count) begin
     $display("ERROR: expected address %0d got %0d",count,out_addr);
     errors<=errors+1;
    end
    count<=count+1;
   end
   if(act_valid) begin
    $fwrite(fd_act,"%0d %0d\n",act_count,activation);
    act_count<=act_count+1;
   end
   if(done) done_seen<=1;
  end
 end

 initial begin
  repeat(4) @(posedge clk); rst<=0;
  @(posedge clk); start<=1;
  @(posedge clk); start<=0;
  while((!done_seen || act_count<12544) && cycles<180000) begin
   @(posedge clk); cycles=cycles+1;
  end
  #1;
  $fclose(fd_acc); $fclose(fd_act);
  if(!done_seen || count!=12544 || act_count!=12544 || errors!=0) begin
   $display("FAIL done=%0d accumulators=%0d activations=%0d errors=%0d",
    done_seen,count,act_count,errors);
   $fatal(1);
  end
  $display("PASS: SAME-PADDING Conv1 produced %0d accumulators and %0d activations",count,act_count);
  $finish;
 end
endmodule
