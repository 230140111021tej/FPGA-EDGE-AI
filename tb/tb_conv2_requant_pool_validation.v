`timescale 1ns/1ps
module tb_conv2_requant_pool_validation;
 reg clk=0, rst=1, start=0;
 wire busy, done, acc_valid;
 wire [12:0] acc_addr;
 wire [4:0] acc_filter;
 wire signed [19:0] acc_data;
 wire act_valid;
 wire [7:0] act_data;

 integer acc_count=0, act_count=0, cycles=0;
 integer acc_fd, act_fd, pool_fd;
 integer f,y,x,base,idx;
 integer a,b,c,d,mx;
 reg done_seen=0;
 integer addr_errors=0;
 reg [7:0] activations [0:6271];

 always #5 clk=~clk;

 conv2_full_layer dut(
  .clk(clk), .rst(rst), .start(start),
  .busy(busy), .done(done),
  .out_addr(acc_addr), .out_filter(acc_filter),
  .out_acc(acc_data), .out_valid(acc_valid)
 );

 conv2_requantize rq(
  .clk(clk), .rst(rst), .in_valid(acc_valid), .in_acc(acc_data),
  .out_valid(act_valid), .out_data(act_data)
 );

 initial begin
  acc_fd=$fopen("conv2_rtl_accumulators.txt","w");
  act_fd=$fopen("conv2_rtl_activations.txt","w");
  if (acc_fd==0 || act_fd==0) begin
   $display("ERROR: unable to open output files");
   $fatal(1);
  end
 end

 always @(posedge clk) begin
  if (rst) begin
   acc_count <= 0;
   act_count <= 0;
   done_seen <= 0;
   addr_errors <= 0;
  end else begin
   if (acc_valid) begin
    $fwrite(acc_fd,"%0d %0d %0d\n",acc_addr,acc_filter,$signed(acc_data));
    if (acc_addr !== acc_count) begin
     $display("ERROR: accumulator address expected %0d, got %0d",acc_count,acc_addr);
     addr_errors <= addr_errors + 1;
    end
    acc_count <= acc_count + 1;
   end
   if (act_valid) begin
    activations[act_count] <= act_data;
    $fwrite(act_fd,"%0d %0d\n",act_count,act_data);
    act_count <= act_count + 1;
   end
   if (done) done_seen <= 1;
  end
 end

 initial begin
  repeat(4) @(posedge clk);
  rst <= 0;
  @(posedge clk); start <= 1;
  @(posedge clk); start <= 0;

  while ((!done_seen || acc_count < 6272 || act_count < 6272) && cycles < 1000000) begin
   @(posedge clk);
   cycles = cycles + 1;
  end
  #2;
  $fclose(acc_fd);
  $fclose(act_fd);

  if (!done_seen || acc_count != 6272 || act_count != 6272 || addr_errors != 0) begin
   $display("FAIL: done=%0d acc_count=%0d act_count=%0d addr_errors=%0d cycles=%0d",
            done_seen,acc_count,act_count,addr_errors,cycles);
   $fatal(1);
  end

  // Pool the RTL-generated activation stream in filter-major order.
  // This checks the pooling result from hardware requantization outputs.
  pool_fd=$fopen("conv2_rtl_pool2.txt","w");
  if (pool_fd==0) begin $display("ERROR: cannot open pool output file"); $fatal(1); end
  for (f=0; f<32; f=f+1) begin
   for (y=0; y<7; y=y+1) begin
    for (x=0; x<7; x=x+1) begin
     base=f*196+(2*y)*14+(2*x);
     a=activations[base];
     b=activations[base+1];
     c=activations[base+14];
     d=activations[base+15];
     mx=a;
     if (b>mx) mx=b;
     if (c>mx) mx=c;
     if (d>mx) mx=d;
     $fwrite(pool_fd,"%0d\n",mx);
    end
   end
  end
  $fclose(pool_fd);
  $display("PASS: generated %0d Conv2 accumulators and %0d activations.",acc_count,act_count);
  $display("Generated 1,568 Pool2 values from the RTL activation outputs.");
  $display("Simulation cycles: %0d",cycles);
  $finish;
 end
endmodule
