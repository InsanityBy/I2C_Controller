`timescale 1ns/10ps

module testbench();
reg clk, rst_n, enable_test;
wire data_test, load_test, finish_test, error_test;
reg scl_test, sda_test;

// test parameters
parameter test_data_value = 32'h13_57_9b_df;
parameter test_number = 4;       // test_number * 8 <= length of test_data_value
parameter clk_divider_ratio = 8; // period_of_SCL = clk_divider_ratio * period_of_clk
reg test_start;
reg [31:0] current_test_count;
reg [4:0] error_count;

// instantiate the submodule
I2C_slave_read_byte test_module(
                        .clock(clk),
                        .reset_n(rst_n),
                        .enable(enable_test),
                        .data(data_test),
                        .load(load_test),
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
    else if (test_start) begin
        if (counter == (clk_divider_ratio - 1)) begin
            counter <= 32'b0;
        end
        else begin
            counter <= counter + 1;
        end
    end
    else begin
        counter <= 32'b0;
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

// 3-bit counter for reading/writing 1-byte data bit by bit
reg [2: 0] bit_counter;
always @(posedge clk or negedge rst_n ) begin
    if (!rst_n) begin
        bit_counter <= 3'b000;
    end
    else if(test_start && scl_test_rising_edge) begin
        if(bit_counter == 3'b111) begin
            bit_counter <= 3'b000;
        end
        else begin
            bit_counter <= bit_counter + 1;
        end
    end
    else begin
        bit_counter <= bit_counter;
    end
end

// enable_test
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        enable_test <= 1'b0;
    end
    else if (test_start && (bit_counter == 3'b0) && scl_test_rising_edge) begin
        enable_test <= 1'b1;
    end
    else begin
        enable_test <= 1'b0;
    end
end

// load data to data shifter
reg [(test_number * 8 - 1) : 0] data_to_write;
reg [7:0] byte_write;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        byte_write <= 8'b0;
        data_to_write <= test_data_value;
    end
    else if(test_start && (bit_counter == 3'b0) && scl_test_falling_edge) begin
        byte_write <= data_to_write[(test_number * 8 - 1) : (test_number * 8 - 8)];
        data_to_write <= {data_to_write[(test_number * 8 - 9) : 0], 8'b0};
    end
    else begin
        byte_write <= byte_write;
        data_to_write <= data_to_write;
    end
end

// write data to test module
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sda_test <= 1'b1;
    end
    else if(test_start && (~scl_test)) begin
        sda_test <= byte_write[7 - bit_counter];
    end
    else begin
        sda_test <= sda_test;
    end
end

// save 1-byte data
reg [7:0] byte_read;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        byte_read <= 8'h00;
    end
    else if(load_test) begin
        byte_read <= {byte_read[6:0], data_test};
    end
    else begin
        byte_read <= byte_read;
    end
end

// start test and check sda_test
reg [7:0] byte_write_sync;
reg finish_test_sync;
always @(posedge clk or negedge rst_n) begin
    finish_test_sync <= finish_test;
    byte_write_sync <= byte_write;
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_test_count <= 32'b0;
        error_count <= 1'b0;
    end
    else if(finish_test_sync) begin
        current_test_count <= current_test_count + 1;
        if(byte_read != byte_write_sync) begin
            error_count <= error_count + 1;
            $display("--%02d--FAIL-- write/read: %h/%h",
                     current_test_count,
                     byte_write_sync,
                     byte_read);
        end
        else begin
            error_count <= error_count;
            $display("--%02d--PASS-- write/read: %h/%h",
                     current_test_count,
                     byte_write_sync,
                     byte_read);
        end
    end
    else begin
        current_test_count <= current_test_count;
        error_count <= error_count;
    end
end

// generate prompt and log
initial begin
    test_start = 1'b0;
    #20 test_start = 1'b1;
    $display("******** 'slave_read_byte' module test started ********");
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
    $display("******** 'slave_read_byte' module test finished ********");
    $finish;
end

endmodule
