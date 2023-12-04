`timescale 1ns / 10ps

module testbench ();
    reg clk, rst_n, bit_read_en;
    wire bit_read_o, bit_read_err, bit_read_finish;
    reg scl_i, sda_i;

    // test parameters
    parameter data_test_value = 32'h13_57_9b_df;
    parameter test_number = 32;  // no more than length of data_test_value
    parameter clk_divisor = 8;  // period_of_SCL = clk_divisor * period_of_clk
    reg     test_start;
    integer test_cnt;
    integer error_cnt;

    // instantiate the submodule
    I2C_slave_read_bit test_module (
        .clk            (clk),
        .rst_n          (rst_n),
        .bit_read_en    (bit_read_en),
        .bit_read_o     (bit_read_o),
        .bit_read_err   (bit_read_err),
        .bit_read_finish(bit_read_finish),
        .scl_i          (scl_i),
        .sda_i          (sda_i)
    );

    // use fsdb/vcd or vcd to save wave
`ifdef fsdbdump
    initial begin
        $display("**************** fsdb file dump is turned on ***************");
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0);
        #100000 $fsdbDumpoff;
    end
`endif
`ifdef vcddump
    initial begin
        $display("**************** vcd file dump is turned on ****************");
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
        else begin
            if (counter == (clk_divisor - 1)) begin
                counter <= 32'b0;
            end
            else begin
                counter <= counter + 1;
            end
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

    // enable test module
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_read_en <= 1'b0;
        end
        else begin
            bit_read_en <= scl_rise && test_start;
        end
    end

    // write data to test module
    reg [test_number-1:0] data_to_write;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_i         <= 1'b1;
            data_to_write <= data_test_value;
        end
        else if (scl_fall) begin
            sda_i <= data_to_write[test_number-1];
            data_to_write <= {
                data_to_write[(test_number-2):0], data_to_write[test_number-1]
            };
        end
        else begin
            sda_i         <= sda_i;
            data_to_write <= data_to_write;
        end
    end

    // check bit_read_o
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            test_cnt  <= 0;
            error_cnt <= 0;
        end
        else if (bit_read_finish) begin
            test_cnt <= test_cnt + 1;
            if (bit_read_o != data_test_value[test_number-test_cnt-1]) begin
                error_cnt <= error_cnt + 1;
                $display("++%02d++FAIL++ write/read: %b/%b", test_cnt,
                         data_test_value[test_number-test_cnt-1], bit_read_o);
            end
            else begin
                $display("--%02d--PASS-- write/read: %b/%b", test_cnt,
                         data_test_value[test_number-test_cnt-1], bit_read_o);
                error_cnt <= error_cnt;
            end
        end
        else begin
            test_cnt  <= test_cnt;
            error_cnt <= error_cnt;
        end
    end

    // start test and generate prompt and log
    initial begin
        test_start = 1'b0;
        #20 test_start = 1'b1;
        $display("*********** 'slave_read_bit' module test started ***********");
        // wait till finished
        wait (test_cnt == test_number);
        test_start = 1'b0;
        #500 $display("------------------------------------------------------------");
        if (error_cnt == 0) begin
            $display("result: passed with 0 errors in %02d tests", test_number);
        end
        else begin
            $display("result: failed with %02d errors in %02d tests", error_cnt,
                     test_number);
        end
        $display("*********** 'slave_read_bit' module test finished **********");
        $finish;
    end

endmodule
