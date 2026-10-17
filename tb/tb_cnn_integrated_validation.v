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
  while(done !== 1'b1 && cycles<2000000) begin @(posedge clk); #1; cycles=cycles+1; end
  #2;
  if(!done) begin
    integer status_fd;
    $display("FAIL: integrated CNN timed out at %0d cycles",cycles);
    status_fd=$fopen("cnn_rtl_run_status.txt","w");
    if(status_fd!=0) begin $fwrite(status_fd,"FAIL: timeout at %0d cycles\n",cycles);$fclose(status_fd);end
    $fclose(fd);
    $finish;
  end else begin
    integer status_fd;
    status_fd=$fopen("cnn_rtl_run_status.txt","w");
    if(status_fd!=0) begin $fwrite(status_fd,"PASS\n");$fclose(status_fd);end
  end
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


