`timescale 1ns/1ps

module tb_conv1_shared_mac;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;
    reg [71:0] pixel_bus = 0;
    reg [71:0] weight_bus = 0;
    reg signed [31:0] bias = 0;

    wire signed [17:0] acc;
    wire busy, done;
    wire [7:0] q;

    reg [7:0] image [0:783];
    reg signed [7:0] weights [0:143];
    reg signed [31:0] biases [0:15];
    integer expected_acc [0:12543];
    integer expected_q [0:12543];

    integer fi, fy, fx, ky, kx, idx, temp, fh;
    integer image_file, weight_file, bias_file;
    integer acc_file, q_file;
    integer got_acc, got_q;
    integer acc_errors, q_errors, timeout_count;

    conv1_shared_mac dut (
        .clk(clk), .rst(rst), .start(start),
        .pixels(pixel_bus), .weights(weight_bus), .bias(bias),
        .acc(acc), .busy(busy), .done(done)
    );

    conv1_single_pixel #(
        .ACC_WIDTH(18),
        .MULTIPLIER(5863783),
        .SHIFT(31)
    ) requant (
        .acc(acc),
        .q(q)
    );

    initial begin
        acc_errors = 0;
        q_errors = 0;

        image_file = $fopen("experiments/conv1_requant/image_pixels.txt", "r");
        weight_file = $fopen("outputs/rtl_params/conv1_weights_int8.txt", "r");
        bias_file = $fopen("outputs/rtl_params/conv1_bias_int32.txt", "r");
        acc_file = $fopen("experiments/conv1_requant/expected_acc.txt", "r");
        q_file = $fopen("experiments/conv1_requant/expected_q.txt", "r");

        if (!image_file || !weight_file || !bias_file ||
            !acc_file || !q_file)
            $fatal(1, "Could not open reference files");

        for (idx = 0; idx < 784; idx = idx + 1) begin
            fh = $fscanf(image_file, "%d", temp);
            if (fh != 1) $fatal(1, "Image read failed");
            image[idx] = temp;
        end

        for (idx = 0; idx < 144; idx = idx + 1) begin
            fh = $fscanf(weight_file, "%d", temp);
            if (fh != 1) $fatal(1, "Weight read failed");
            weights[idx] = temp;
        end

        for (idx = 0; idx < 16; idx = idx + 1) begin
            fh = $fscanf(bias_file, "%d", temp);
            if (fh != 1) $fatal(1, "Bias read failed");
            biases[idx] = temp;
        end

        for (idx = 0; idx < 12544; idx = idx + 1) begin
            fh = $fscanf(acc_file, "%d", temp);
            if (fh != 1) $fatal(1, "Accumulator reference read failed");
            expected_acc[idx] = temp;

            fh = $fscanf(q_file, "%d", temp);
            if (fh != 1) $fatal(1, "Output reference read failed");
            expected_q[idx] = temp;
        end

        $fclose(image_file);
        $fclose(weight_file);
        $fclose(bias_file);
        $fclose(acc_file);
        $fclose(q_file);

        repeat (2) @(negedge clk);
        rst = 0;
        idx = 0;

        for (fi = 0; fi < 16; fi = fi + 1) begin
            for (fy = 0; fy < 28; fy = fy + 1) begin
                for (fx = 0; fx < 28; fx = fx + 1) begin
                    pixel_bus = 0;
                    weight_bus = 0;

                    for (ky = 0; ky < 3; ky = ky + 1) begin
                        for (kx = 0; kx < 3; kx = kx + 1) begin
                            temp = (fy + ky - 1) * 28
                                 + (fx + kx - 1);

                            if ((fy + ky >= 1) && (fy + ky <= 28) &&
                                (fx + kx >= 1) && (fx + kx <= 28))
                                pixel_bus[((ky*3+kx)*8) +: 8] = image[temp];

                            weight_bus[((ky*3+kx)*8) +: 8] =
                                weights[fi*9 + ky*3 + kx];
                        end
                    end

                    bias = biases[fi];

                    @(negedge clk);
                    start = 1;
                    @(negedge clk);
                    start = 0;

                    timeout_count = 0;
                    while (done !== 1'b1 && timeout_count < 20) begin
                        @(negedge clk);
                        timeout_count = timeout_count + 1;
                    end

                    if (done !== 1'b1) begin
                        $display("TIMEOUT at index=%0d", idx);
                        $fatal(1, "Shared MAC did not assert done");
                    end

                    got_acc = $signed(acc);
                    got_q = q;

                    if (got_acc != expected_acc[idx]) begin
                        if (acc_errors < 10)
                            $display("ACC mismatch idx=%0d expected=%0d got=%0d",
                                idx, expected_acc[idx], got_acc);
                        acc_errors = acc_errors + 1;
                    end

                    if (got_q != expected_q[idx]) begin
                        if (q_errors < 10)
                            $display("Q mismatch idx=%0d expected=%0d got=%0d",
                                idx, expected_q[idx], got_q);
                        q_errors = q_errors + 1;
                    end

                    idx = idx + 1;
                end
            end
        end

        $display("Total positions: %0d", idx);
        $display("Accumulator mismatches: %0d", acc_errors);
        $display("Output mismatches: %0d", q_errors);

        if (acc_errors == 0 && q_errors == 0)
            $display("PASS: shared MAC and requantization");
        else
            $fatal(1, "FAIL: shared MAC verification");

        $finish;
    end
endmodule
