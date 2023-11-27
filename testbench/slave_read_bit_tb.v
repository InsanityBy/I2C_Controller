`timescale 1ns/10ps

module testbench();
reg clk, rst_n, enable_test;
wire data_test, error_test, finish_test;
reg scl_test, sda_test;

// test parameters
parameter test_data_value = 32'h13_57_9b_df;
parameter test_number = 32;
parameter clk_divider_ratio = 8; // period_of_SCL = clk_divider_ratio * period_of_clk
reg test_start;
reg [31:0] current_test_count;
reg [4:0] error_count;

// instantiate the submodule
I2C_slave_read_bit test_module(
                       .clock(clk),
                       .reset_n(rst_n),
                       .enable(enable_test),
                       .data(data_test),
                       .error(error_test),
                       .finish(finish_test),
                       .scl(scl_test),
                       .sda(sda_test)
                   );

// use fsdb/vcd or vcd to save wave
initial begin
`ifdef fsdbdump
    $display("\n******** fsdb file dump is turned on ******** \n");
    $fsdbDumpfile("wave.fsdb");
    $fsdbDumpvars(0);
    #100000
     $fsdbDumpoff;
`endif
`ifdef vcddump

    $display("******** vcd file dump is turned on******** ");
    $dumpfile("wave.vcd");
    $dumpvars(0);
    #100000
     $dumpoff;
`endif
end

// generate clock and reset
initial begin
    clk       = 0;
    rst_n     = 1;
    #10 rst_n = 0;
    #10 rst_n = 1;
    forever
        #10 clk = ~clk;
end

// scl_test
// counter to generate scl_test
reg [31:0] counter;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter <= 32'b0;
    end
    else begin
        if (counter == (clk_divider_ratio - 1)) begin
            counter <= 32'b0;
        end
        else begin
            counter <= counter + 1;
        end
    end
end
// generate scl_test
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl_test <= 1'b1;
    end
    else begin
        if (counter < (clk_divider_ratio / 2)) begin
            scl_test <= 1'b1;
        end
        else begin
            scl_test <= 1'b0;
        end
    end
end

// detect scl rising and falling edge
reg scl_test_last_state;
wire scl_test_rising_edge, scl_test_falling_edge;
// save scl last state
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl_test_last_state <= 1'b1;
    end
    else begin
        scl_test_last_state <= scl_test;
    end
end
assign scl_test_rising_edge = (~scl_test_last_state) && scl_test;
assign scl_test_falling_edge = scl_test_last_state && (~scl_test);

// enable_test
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        enable_test <= 1'b0;
    end
    else begin
        enable_test <= scl_test_rising_edge && test_start;
    end
end

// write data to test module
reg [test_number - 1 : 0] data_to_write;
// write data
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sda_test <= 1'b1;
        data_to_write <= test_data_value;
    end
    else if(scl_test_falling_edge) begin
        sda_test <= data_to_write[test_number - 1];
        data_to_write <= {data_to_write[test_number - 2:0], data_to_write[test_number - 1]};
    end
    else begin
        sda_test <= sda_test;
        data_to_write <= data_to_write;
    end
end

// check data_test
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_test_count <= 32'b0;
        error_count <= 1'b0;
    end
    else if(finish_test) begin
        current_test_count <= current_test_count + 1;
        if(data_test != test_data_value[test_number - current_test_count - 1]) begin
            error_count <= error_count + 1;
            $display("--%02d--FAIL-- write/read: %h",
                     current_test_count,
                     test_data_value[test_number - current_test_count - 1],
                     data_test);
        end
        else begin
            $display("--%02d--PASS-- write/read: %h",
                     current_test_count,
                     test_data_value[test_number - current_test_count - 1],
                     data_test);
            error_count <= error_count;
        end
    end
    else begin
        current_test_count <= current_test_count;
        error_count <= error_count;
    end
end

// start test and generate prompt and log
initial begin
    test_start = 1'b0;
    #20 test_start = 1'b1;
    $display("******** 'slave_read_bit' module test started ********");
    // wait till finished
    wait(current_test_count == test_number);
    test_start = 1'b0;
    #500
     $display("-------------------------------------------------");
    if (error_count == 0) begin
        $display("result: passed with %02d errors in %02d tests", error_count, test_number);
    end
    else begin
        $display("result: failed with %02d errors in %02d tests", error_count, test_number);
    end
    $display("******** 'slave_read_bit' module test finished ********");
    $finish;
end

endmodule
