`timescale 1ns/10ps

module testbench();
reg clk, rst_n;
reg enable_test;
wire [7:0] data_write_test, data_read_test;
wire read_write_flag_test, data_finish_test, transfer_status_test, bus_status_test, error_test;
reg scl_in, sda_in;
wire scl_out, sda_out;
wire sda;
assign sda = sda_in && sda_out;

// test parameters
parameter module_address = 7'b101_1101;
parameter wrong_address = 8'b1100_1001; // include read/write bit
parameter test_data_value = 32'h13_57_9b_df;
parameter transfer_byte_number = 4; // ransfer_byte_number * 8 <= length of test_data_value
parameter clk_divider_ratio = 4;    // period_of_SCL = clk_divider_ratio * period_of_clk
parameter test_number = 4;
reg test_start;
reg [1:0] test_control;// 0-wrong address, 1-slave read, 2-slave write, 3-combined
reg [31:0] current_test_count;
reg [4:0] error_count;

// instantiate the submodule
I2C_slave test_module(
              .clock(clk),
              .reset_n(rst_n),
              .enable(enable_test),
              .address(module_address),
              .data_write(data_write_test),
              .data_read(data_read_test),
              .read_write_flag(read_write_flag_test),
              .data_finish(data_finish_test),
              .transfer_status(transfer_status_test),
              .bus_status(bus_status_test),
              .error(error_test),
              .scl_in(scl_in),
              .scl_out(scl_out),
              .sda_in(sda_in),
              .sda_out(sda_out)
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
    clk = 0;
    rst_n = 1;
    scl_in <= 1'b1;
    sda_in <= 1'b1;
    #10 rst_n = 0;
    #10 rst_n = 1;
    forever
        #10 clk = ~clk;
end

// scl_in
// counter to generate scl_in
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
// generate scl_in
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl_in <= 1'b1;
    end
    else begin
        if (counter < (clk_divider_ratio / 2)) begin
            scl_in <= 1'b1;
        end
        else begin
            scl_in <= 1'b0;
        end
    end
end

// detect scl rising and falling edge
reg scl_in_last_state;
wire scl_in_rising_edge, scl_in_falling_edge;
// save scl last state
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl_in_last_state <= 1'b1;
    end
    else begin
        scl_in_last_state <= scl_in;
    end
end
assign scl_in_rising_edge = (~scl_in_last_state) && scl_in;
assign scl_in_falling_edge = scl_in_last_state && (~scl_in);

reg [31:0] bit_counter;

// test wrong address
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sda_in <= 1'b1;
        bit_counter <= 32'b0;
    end
    else if(test_start && test_control == 2'b00) begin
        if (bit_counter == 32'b0) begin
            if (scl_in) begin    // write start to module
                sda_in <= 1'b0;
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter <= 32'd8) begin // write address and read/write flag to module
            if (scl_in_falling_edge) begin
                sda_in <= wrong_address[8 - bit_counter];
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd9) begin // module write ack
            if (scl_in_falling_edge) begin
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd10) begin    // check ack from module
            if (scl_in_rising_edge) begin
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd11) begin    // prepare to stop
            if (scl_in_falling_edge) begin
                sda_in <= 1'b0;
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd12) begin    // write stop to module
            if(scl_in) begin
                sda_in <= 1'b1;
                bit_counter <= 32'b0;
                test_start <= 1'b0;
            end
        end
    end
end

// test slave read data
reg [transfer_byte_number * 8 - 1 : 0] data_to_write;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        data_to_write <= test_data_value;
        sda_in <= 1'b1;
        bit_counter <= 32'b0;
    end
    else if(test_start && test_control == 2'b01) begin
        if (bit_counter == 32'b0) begin
            if (scl_in) begin    // write start to module
                sda_in <= 1'b0;
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter <= 32'd7) begin // write address to module
            if (scl_in_falling_edge) begin
                sda_in <= module_address[7 - bit_counter];
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd8) begin // write read/write flag to module
            if (scl_in_falling_edge) begin
                sda_in <= 1'b1;
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd9) begin // module write ack
            if (scl_in_falling_edge) begin
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd10) begin    // check ack from module
            if (scl_in_rising_edge) begin
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter <= transfer_byte_number * 10 + 10) begin    // write data to module
            if (((bit_counter % 10) >= 32'd1) && ((bit_counter % 10) <= 32'd8)) begin // 8 bits
                if (scl_in_falling_edge) begin
                    sda_in <= data_to_write[transfer_byte_number * 8 - (bit_counter % 10)];
                    bit_counter <= bit_counter + 1;
                end
            end
            else if ((bit_counter % 10)  == 32'd9) begin // module write ack
                if (scl_in_falling_edge) begin
                    bit_counter <= bit_counter + 1;
                end
            end
            else if ((bit_counter % 10)  == 32'd0) begin    // check ack from module
                if (scl_in_rising_edge) begin
                    if (sda_out) begin  // NACK, stop transfer
                        bit_counter <= transfer_byte_number * 10 + 11;
                    end
                    else begin  // prepare next byte data to write to module
                        data_to_write = {data_to_write[transfer_byte_number * 8 - 9 : 0], 8'b0};
                        bit_counter <= bit_counter + 1;
                    end
                end
            end
        end
        else if (bit_counter == transfer_byte_number * 10 + 11) begin    // prepare to stop
            if (scl_in_falling_edge) begin
                sda_in <= 1'b0;
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == transfer_byte_number * 10 + 12) begin    //write  stop to module
            if(scl_in) begin
                sda_in <= 1'b1;
                bit_counter <= 32'b0;
                test_start <= 1'b0;
            end
        end
    end
end

// test slave write data
reg [transfer_byte_number * 8 - 1 : 0] data_to_load;
reg [7:0] byte_read;
assign data_write_test = data_to_load[transfer_byte_number * 8 - 1 : transfer_byte_number * 8 - 8];
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        data_to_load <= test_data_value;
        byte_read <= 8'b0;
        sda_in <= 1'b1;
        bit_counter <= 32'b0;
    end
    else if(test_start && test_control == 2'b10) begin
        if (bit_counter == 32'b0) begin
            if (scl_in) begin    // write start to module
                sda_in <= 1'b0;
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter <= 32'd7) begin // write address to module
            if (scl_in_falling_edge) begin
                sda_in <= module_address[7 - bit_counter];
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd8) begin // write read/write flag to module
            if (scl_in_falling_edge) begin
                sda_in <= 1'b0;
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd9) begin // module write ack
            if (scl_in_falling_edge) begin
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == 32'd10) begin    // check ack from module
            if (scl_in_rising_edge) begin
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter <= transfer_byte_number * 10 + 10) begin    // module write data
            if (((bit_counter % 10) >= 32'd1) && ((bit_counter % 10) <= 32'd8)) begin  // read data from module
                if (scl_in_rising_edge) begin
                    byte_read <= {byte_read[6:0], sda_out};
                    bit_counter <= bit_counter + 1;
                end
            end
            else if ((bit_counter % 10)  == 32'd9) begin // write ack to module
                if (scl_in_falling_edge) begin
                    if (bit_counter == transfer_byte_number * 10 + 9) begin // write NACK
                        sda_in <= 1'b1;
                    end
                    else begin
                        sda_in <= 1'b0;
                    end
                    bit_counter <= bit_counter + 1;
                end
            end
            else if ((bit_counter % 10)  == 32'd0) begin    // wait module check ack and load next byte to module
                if (scl_in_rising_edge) begin
                    data_to_load <= {data_to_load[transfer_byte_number * 8 - 9 : 0], 8'b0};
                    bit_counter <= bit_counter + 1;
                end
            end
        end
        else if (bit_counter == transfer_byte_number * 10 + 11) begin    // prepare to stop
            if (scl_in_falling_edge) begin
                sda_in <= 1'b0;
                bit_counter <= bit_counter + 1;
            end
        end
        else if (bit_counter == transfer_byte_number * 10 + 12) begin    // stop
            if(scl_in) begin
                sda_in <= 1'b1;
                bit_counter <= 32'b0;
                test_start <= 1'b0;
            end
        end
    end
end

// enable submodule
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        enable_test <= 1'b0;
    end
    else begin
        enable_test <= 1'b1;
    end
end

// generate prompt and log
initial begin
    $display("******** 'slave' module test started ********");

    test_start = 1'b0;
    test_control = 2'b00;
    #20 test_start = 1'b1;
    $display("--1-- wrong address test");

    wait(!test_start);
    test_control = 2'b01;
    #500 test_start = 1'b1;
    $display("--2-- read data test");

    wait(!test_start);
    test_control = 2'b10;
    #500 test_start = 1'b1;
    $display("--3-- write data test");

    wait(!test_start);
    #500 $finish;
    test_control = 2'b11;
    #500 test_start = 1'b1;
    $display("--4-- combined mode test");

    wait(!test_start);
    #500 $display("-------------------------------------------------");
    if (error_count == 0) begin
        $display("result: passed with 0 errors");
    end
    else begin
        $display("result: failed with %02d errors", error_count);
    end
    $display("******** 'slave' module test finished ********");
    $finish;
end

endmodule
