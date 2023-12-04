`timescale 1ns / 10ps

module testbench ();
    reg clk, rst_n, bit_write_en;
    wire bit_write_i, bit_write_finish;
    reg  scl_i;
    wire sda_o;

    // test parameters and variables
    parameter data_test_value = 32'h13_57_9b_df;
    parameter test_number = 32;  // no more than length of data_test_value
    parameter clk_divisor = 4;  // period_of_SCL = clk_divisor * period_of_clk
    reg     test_start;
    integer test_cnt;
    integer error_cnt;

    // instantiate the submodule
    I2C_slave_write_bit test_module (
        .clk             (clk),
        .rst_n           (rst_n),
        .bit_write_en    (bit_write_en),
        .bit_write_i     (bit_write_i),
        .bit_write_finish(bit_write_finish),
        .scl_i           (scl_i),
        .sda_o           (sda_o)
    );

    // use fsdb/vcd or vcd to save wave
`ifdef fsdbdump
    initial begin
        $display("\n**************** fsdb file dump is turned on ***************");
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0);
        #100000 $fsdbDumpoff;
    end
`endif
`ifdef vcddump
    initial begin
        $display("\n**************** vcd file dump is turned on ****************");
        $dumpfile("wave.vcd");
        $dumpvars(0);
        #100000 $dumpoff;
    end
`endif

    // generate clock and reset
    initial begin
        clk   = 0;
        rst_n = 1;
        #10 rst_n = 0;
        #10 rst_n = 1;
        forever #10 clk = ~clk;
    end

    // counter for clock division
    reg [31:0] counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 32'b0;
        end
        else if (test_start) begin
            if (counter == (clk_divisor - 1)) begin
                counter <= 32'b0;
            end
            else begin
                counter <= counter + 1;
            end
        end
        else begin
            counter <= counter;
        end
    end

    // generate scl_i
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_i <= 1'b1;
        end
        else begin
            if (counter < (clk_divisor / 2)) begin
                scl_i <= 1'b1;
            end
            else begin
                scl_i <= 1'b0;
            end
        end
    end

    // detect scl rising and falling edge
    reg scl_last;
    wire scl_rise, scl_fall;
    // save scl last state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_last <= 1'b1;
        end
        else begin
            scl_last <= scl_i;
        end
    end
    assign scl_rise = (~scl_last) && scl_i;
    assign scl_fall = scl_last && (~scl_i);

    // test module to write 1 bit
    reg bit_written;
    assign bit_write_i = data_test_value[test_number-test_cnt-1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_write_en <= 1'b0;
            bit_written  <= 1'b0;
        end
        else if (test_start && scl_fall) begin
            bit_write_en <= 1'b1;
        end
        else if (scl_rise) begin
            bit_written <= sda_o;
        end
        else if (bit_write_finish) begin
            bit_write_en <= 1'b0;
        end
    end

    // start test and generate prompt and log
    initial begin
        test_start = 1'b0;
        error_cnt  = 0;

        // test and check
        $display("\n*********** 'slave_write_bit' module test started **********\n");
        for (test_cnt = 0; test_cnt < test_number; test_cnt = test_cnt + 1) begin
            #200 test_start = 1'b1;
            wait (bit_write_finish);
            test_start = 1'b0;
            wait (~bit_write_finish);
            // check read and written data
            if (bit_written != data_test_value[test_number-test_cnt-1]) begin
                error_cnt <= error_cnt + 1;
                $display("++%02d++FAIL++ write/read: %b/%b", test_cnt,
                         data_test_value[test_number-test_cnt-1], bit_written);
            end
            else begin
                $display("--%02d--PASS-- write/read: %b/%b", test_cnt,
                         data_test_value[test_number-test_cnt-1], bit_written);
                error_cnt <= error_cnt;
            end
        end
        $display("------------------------------------------------------------");

        // result
        if (error_cnt == 0) begin
            $display("result: passed with 0 errors in %02d tests", test_number);
        end
        else begin
            $display("result: failed with %02d errors in %02d tests", error_cnt,
                     test_number);
        end
        $display("\n********** 'slave_write_bit' module test finished **********\n");
        $finish;
    end

endmodule
