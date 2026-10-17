`timescale 1ns/1ps
module tb_cnn_fc2_hw_top_compare;
 reg clk=0, rst=1, start=0;
 wire b_busy,b_done,b_scores_valid;
 wire [3:0] b_class;
 wire signed [31:0] b0,b1,b2,b3,b4,b5,b6,b7,b8,b9;
 wire h_busy,h_done,h_scores_valid;
 wire [3:0] h_class;
 wire signed [31:0] h0,h1,h2,h3,h4,h5,h6,h7,h8,h9;
 integer cycles, errors;
 always #5 clk=~clk;

 cnn_integrated_sim_top baseline(
  .clk(clk),.rst(rst),.start(start),.busy(b_busy),.done(b_done),
  .predicted_class(b_class),.scores_valid(b_scores_valid),
  .score0(b0),.score1(b1),.score2(b2),.score3(b3),.score4(b4),
  .score5(b5),.score6(b6),.score7(b7),.score8(b8),.score9(b9)
 );
 cnn_integrated_fc2_hw_top candidate(
  .clk(clk),.rst(rst),.start(start),.busy(h_busy),.done(h_done),
  .predicted_class(h_class),.scores_valid(h_scores_valid),
  .score0(h0),.score1(h1),.score2(h2),.score3(h3),.score4(h4),
  .score5(h5),.score6(h6),.score7(h7),.score8(h8),.score9(h9)
 );

 // Debug trace: sample controller progress independently of the main test.
 initial begin : controller_trace
  integer trace_cycle;
  trace_cycle=0;
  forever begin
   @(posedge clk); #1;
   trace_cycle=trace_cycle+1;
   if (trace_cycle <= 80 || (trace_cycle % 100000)==0) begin
    $display("TRACE cyc=%0d rst=%b start=%b | B phase=%0d busy=%b done=%b c1=%b/%b c2=%b/%b f1=%b/%b f2=%b/%b | H phase=%0d busy=%b done=%b c1=%b/%b c2=%b/%b f1=%b/%b f2=%b/%b",
     trace_cycle,rst,start,baseline.phase,b_busy,b_done,baseline.c1_busy,baseline.c1_done,baseline.c2_busy,baseline.c2_done,baseline.f1_busy,baseline.f1_done,baseline.f2_busy,baseline.f2_done,
     candidate.phase,h_busy,h_done,candidate.c1_busy,candidate.c1_done,candidate.c2_busy,candidate.c2_done,candidate.f1_busy,candidate.f1_done,candidate.f2_busy,candidate.f2_done);
   end
  end
 end
 initial begin
  errors=0;
  repeat(4) @(negedge clk);
  rst=0;
  @(negedge clk); start=1;
  @(negedge clk); start=0;
  cycles=0;
  while((b_done!==1'b1 || h_done!==1'b1) && cycles<2000000) begin
   @(posedge clk); #1; cycles=cycles+1;
  end
  if(b_done!==1'b1 || h_done!==1'b1) begin
   $display("DAY10_FC2_TOP_COMPARE_FAIL_TIMEOUT baseline_done=%b candidate_done=%b cycles=%0d",b_done,h_done,cycles);
   $display("BASELINE CTRL phase=%0d wait_count=%0d busy=%b done=%b start=%b c1_start=%b c1_busy=%b c1_done=%b c2_busy=%b c2_done=%b f1_busy=%b f1_done=%b f2_busy=%b f2_done=%b",
      baseline.phase,baseline.wait_count,b_busy,b_done,start,baseline.c1_start,baseline.c1_busy,baseline.c1_done,baseline.c2_busy,baseline.c2_done,baseline.f1_busy,baseline.f1_done,baseline.f2_busy,baseline.f2_done);
   $display("CANDIDATE CTRL phase=%0d wait_count=%0d busy=%b done=%b start=%b c1_start=%b c1_busy=%b c1_done=%b c2_busy=%b c2_done=%b f1_busy=%b f1_done=%b f2_busy=%b f2_done=%b f2_we=%b f2_addr=%0d transfer_index=%0d",
      candidate.phase,candidate.wait_count,h_busy,h_done,start,candidate.c1_start,candidate.c1_busy,candidate.c1_done,candidate.c2_busy,candidate.c2_done,candidate.f1_busy,candidate.f1_done,candidate.f2_busy,candidate.f2_done,candidate.f2_input_we,candidate.f2_input_addr,candidate.f2_transfer_index);
   $fatal(1,"CNN top comparison timed out; no PASS marker is valid");
  end
  if(b_class !== h_class) begin $display("MISMATCH predicted_class baseline=%0d candidate=%0d",b_class,h_class); errors=errors+1; end
  if(b0!==h0) begin $display("MISMATCH score0 baseline=%0d candidate=%0d",b0,h0); errors=errors+1; end
  if(b1!==h1) begin $display("MISMATCH score1 baseline=%0d candidate=%0d",b1,h1); errors=errors+1; end
  if(b2!==h2) begin $display("MISMATCH score2 baseline=%0d candidate=%0d",b2,h2); errors=errors+1; end
  if(b3!==h3) begin $display("MISMATCH score3 baseline=%0d candidate=%0d",b3,h3); errors=errors+1; end
  if(b4!==h4) begin $display("MISMATCH score4 baseline=%0d candidate=%0d",b4,h4); errors=errors+1; end
  if(b5!==h5) begin $display("MISMATCH score5 baseline=%0d candidate=%0d",b5,h5); errors=errors+1; end
  if(b6!==h6) begin $display("MISMATCH score6 baseline=%0d candidate=%0d",b6,h6); errors=errors+1; end
  if(b7!==h7) begin $display("MISMATCH score7 baseline=%0d candidate=%0d",b7,h7); errors=errors+1; end
  if(b8!==h8) begin $display("MISMATCH score8 baseline=%0d candidate=%0d",b8,h8); errors=errors+1; end
  if(b9!==h9) begin $display("MISMATCH score9 baseline=%0d candidate=%0d",b9,h9); errors=errors+1; end
  $display("Baseline class=%0d Candidate class=%0d",b_class,h_class);
  $display("Baseline scores: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",b0,b1,b2,b3,b4,b5,b6,b7,b8,b9);
  $display("Candidate scores: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",h0,h1,h2,h3,h4,h5,h6,h7,h8,h9);
  if(errors==0) begin $display("DAY10_FC2_TOP_COMPARE_PASS cycles=%0d",cycles); $finish; end
  else begin $display("DAY10_FC2_TOP_COMPARE_FAIL mismatches=%0d",errors); $fatal(1,"CNN top comparison mismatch"); end
 end
endmodule


