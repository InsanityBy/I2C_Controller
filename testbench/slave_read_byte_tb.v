`timescale 1ns/10ps

module testbench();
reg clk, rst_n, go_test;
wire data_test, load_test,  finish_test, error_test;
reg scl_test, sda_test;

// test data to write
parameter test_data_value = 32'h13_57_9b_df;
// test number
parameter test_number = 32;
reg [4:0] current_test_number;
reg [4:0] error_count;

// instantiate the submodule
I2C_slave_read_byte test_module(
                        .clock(clk),
                        .reset_n(rst_n),
                        .go(go_test),
                        .data(data_test),
                        .load(load_test),
                        .finish(finish_test),
                        .error(error_test),
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

// write data to test module
reg [31:0] data_to_write;
reg [7:0] data_write;
reg [4:0] counter;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        go_test <= 1'b0;
        counter <= 5'b00000;
        data_to_write <= test_data_value;
        data_write <= 8'h00;
        scl_test <= 1'b1;
        sda_test <= 1'b1;
    end
    else if (!finish_test) begin
        go_test <= 1'b1;
        if (counter == 5'b11111) begin
            counter <= 5'b00000;
        end
        else begin
            counter <= counter + 1;
        end
        case(counter[1:0])
            2'b00: begin
                {scl_test, sda_test} <= {1'b0, sda_test};
                data_to_write <= data_to_write;
                data_write <= data_write;
            end
            2'b01: begin
                {scl_test, sda_test} <= data_to_write[31];
                data_to_write <= data_to_write;
                data_write <= data_write;
            end
            2'b10: begin
                {scl_test, sda_test} <= {1'b1, sda_test};
                data_to_write <= data_to_write;
                data_write <= data_write;
            end
            2'b11: begin
                {scl_test, sda_test} <= {1'b1, sda_test};
                data_to_write <= {data_to_write[30:0], data_to_write[31]};
                data_write <= {data_write[6:0], data_to_write[31]};
            end
        endcase
    end
    else begin
        go_test <= 1'b0;
        counter <= 5'b00000;
        data_to_write <= data_to_write;
        data_write <= data_write;
        scl_test <= scl_test;
        sda_test <= sda_test;
    end
end

// save data and check
reg [7:0] data_get;
// save
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_get <= 8'h00;
    end
    else if(load_test) begin
        data_get <= {data_get[6:0], data_test};
    end
    else begin
        data_get <= data_get;
    end
end
// check
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_test_number <= 4'b0000;
        error_count         <= 4'b0000;
    end
    else if (!go_test) begin
        current_test_number <= current_test_number + 1;
        if(data_get == data_write) begin
            $display("--%02d--PASS-- write/read: %h/%h", current_test_number, data_write, data_get);
            error_count <= error_count;
        end
        else begin
            $display("--%02d--FAIL-- write/read: %h/%h", current_test_number, data_write, data_get);
            error_count <= error_count + 1;
        end
    end
    else begin
        error_count <= error_count;
        current_test_number <= current_test_number;
    end
end

// prompt and log
initial begin
    $display("******** 'slave_read_byte' module test started ********");
    // wait till finished
    wait(current_test_number == test_number - 1);
    #1000
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
