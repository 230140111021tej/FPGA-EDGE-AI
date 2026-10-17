`timescale 1ns/1ps
module tb_conv2_validation;
 reg clk=0,rst=1,start=0;
 wire busy,done,out_valid;
 wire [12:0] out_addr;
 wire [4:0] out_filter;
 wire signed [19:0] out_acc;
 integer count=0,cycles=0,fd;
 reg done_seen=0;
 integer errors=0;
 always #5 clk=~clk;
 conv2_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(out_addr),.out_filter(out_filter),.out_acc(out_acc),.out_valid(out_valid));
 initial begin
  fd=$fopen("conv2_rtl_accumulators.txt","w");
  if(fd==0) begin $display("ERROR: cannot open accumulator output file"); $fatal(1); end
 end
 always @(posedge clk) begin
  if(rst) begin count<=0;done_seen<=0;errors<=0;end
  else begin
   if(out_valid) begin
    $fwrite(fd,"%0d %0d %0d\n",out_addr,out_filter,$signed(out_acc));
    if(out_addr!==count) begin
     $display("ERROR address expected=%0d got=%0d",count,out_addr);
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
  while((!done_seen || count<6272) && cycles<1000000) begin @(posedge clk); cycles=cycles+1; end
  #1; $fclose(fd);
  if(!done_seen || count!=6272 || errors!=0) begin
   $display("FAIL done=%0d count=%0d errors=%0d cycles=%0d",done_seen,count,errors,cycles);
   $fatal(1);
  end
  $display("PASS: Conv2 RTL generated %0d accumulators in %0d cycles",count,cycles);
  $finish;
 end
endmodule
