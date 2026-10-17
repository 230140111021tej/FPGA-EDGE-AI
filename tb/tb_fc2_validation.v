`timescale 1ns/1ps
module tb_fc2_validation;
 reg clk=0,rst=1,start=0;
 wire busy,done,out_valid;
 wire [3:0] out_addr;
 wire signed [31:0] out_score;
 integer count=0,cycles=0,fd;
 integer addr_errors=0;
 reg done_seen=0;
 always #5 clk=~clk;
 fc2_full_layer dut(.clk(clk),.rst(rst),.start(start),.busy(busy),.done(done),
  .out_addr(out_addr),.out_score(out_score),.out_valid(out_valid));
 initial begin
  fd=$fopen("fc2_rtl_scores.txt","w");
  if(fd==0) begin $display("ERROR opening FC2 score file");$fatal(1);end
 end
 always @(posedge clk) begin
  if(rst) begin count<=0;done_seen<=0;addr_errors<=0;end
  else begin
   if(out_valid) begin
    $fwrite(fd,"%0d %0d\n",out_addr,$signed(out_score));
    if(out_addr!==count) begin
     $display("ERROR score address expected=%0d got=%0d",count,out_addr);
     addr_errors<=addr_errors+1;
    end
    count<=count+1;
   end
   if(done) done_seen<=1;
  end
 end
 initial begin
  repeat(4) @(posedge clk);rst<=0;
  @(posedge clk);start<=1;
  @(posedge clk);start<=0;
  while((!done_seen || count<10) && cycles<10000) begin @(posedge clk);cycles=cycles+1;end
  #2;$fclose(fd);
  if(!done_seen || count!=10 || addr_errors!=0) begin
   $display("FAIL done=%0d count=%0d address_errors=%0d cycles=%0d",done_seen,count,addr_errors,cycles);
   $fatal(1);
  end
  $display("PASS: generated 10 FC2 class scores in %0d cycles.",cycles);
  $finish;
 end
endmodule
