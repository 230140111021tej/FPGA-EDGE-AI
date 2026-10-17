`timescale 1ns/1ps
module tb_fc1_validation;
 reg clk=0,rst=1,start=0;
 wire busy,done,acc_valid;
 wire [5:0] acc_addr;
 wire signed [31:0] acc_data;
 wire act_valid;
 wire [7:0] act_data;
 integer acc_count=0,act_count=0,cycles=0,acc_fd,act_fd;
 integer addr_errors=0;
 reg done_seen=0;
 reg [7:0] acts [0:63];
 always #5 clk=~clk;
 fc1_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(acc_addr),.out_acc(acc_data),.out_valid(acc_valid));
 fc1_requantize rq(.clk(clk),.rst(rst),.in_valid(acc_valid),.in_acc(acc_data),
  .out_valid(act_valid),.out_data(act_data));
 initial begin
  acc_fd=$fopen("fc1_rtl_accumulators.txt","w");
  act_fd=$fopen("fc1_rtl_activations.txt","w");
  if(acc_fd==0 || act_fd==0) begin $display("ERROR opening FC1 outputs"); $fatal(1); end
 end
 always @(posedge clk) begin
  if(rst) begin acc_count<=0; act_count<=0; done_seen<=0; addr_errors<=0; end
  else begin
   if(acc_valid) begin
    $fwrite(acc_fd,"%0d %0d\n",acc_addr,$signed(acc_data));
    if(acc_addr!==acc_count) begin
     $display("ERROR address expected=%0d got=%0d",acc_count,acc_addr);
     addr_errors<=addr_errors+1;
    end
    acc_count<=acc_count+1;
   end
   if(act_valid) begin
    acts[act_count]<=act_data;
    $fwrite(act_fd,"%0d %0d\n",act_count,act_data);
    act_count<=act_count+1;
   end
   if(done) done_seen<=1;
  end
 end
 initial begin
  repeat(4) @(posedge clk); rst<=0;
  @(posedge clk); start<=1;
  @(posedge clk); start<=0;
  while((!done_seen || acc_count<64 || act_count<64) && cycles<200000) begin
   @(posedge clk); cycles=cycles+1;
  end
  #2; $fclose(acc_fd); $fclose(act_fd);
  if(!done_seen || acc_count!=64 || act_count!=64 || addr_errors!=0) begin
   $display("FAIL done=%0d accumulators=%0d activations=%0d address_errors=%0d cycles=%0d",
    done_seen,acc_count,act_count,addr_errors,cycles);
   $fatal(1);
  end
  $display("PASS: generated 64 FC1 accumulators and activations in %0d cycles.",cycles);
  $finish;
 end
endmodule
