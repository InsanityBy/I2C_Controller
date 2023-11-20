`timescale 1ns/10ps

module testbench();
parameter length = 8;

reg clk, rst_n, go_test;
reg [2:0] command_test;
wire finish_test, scl_test, sda_test;

// instantiate the detector
I2C_master_bit test_module(
    .clock(clk),
    .reset_n(rst_n),
    .go(go_test),
    .command(command_test),
    .finish(finish_test),
    .scl(scl_test),
    .sda(sda_test)
);

// use fsdb to save wave
initial begin
`ifdef fsdbdump
  $display("\n*** fsdb file dump is turned on ***\n");
  $fsdbDumpfile("wave.fsdb");
  $fsdbDumpvars(0);
  #100000
  $fsdbDumpoff;
`endif
end

// initialize inputs and create clock
initial begin
    clk = 0;
    rst_n = 1;
    go_test = 0;
    command_test = 3'b000;
    forever 
        #10 clk = ~clk;
end

initial begin
    #10 rst_n = 0;
    #10 rst_n = 1;

    // start bit
    #10 go_test = 1;
        command_test = 3'b010;
    wait(finish_test);
    go_test = 0;

    // stop bit
    #10 go_test = 1;
        command_test = 3'b011;
    wait(finish_test);
    go_test = 0;

    // data 0
    #10 go_test = 1;
        command_test = 3'b100;
    wait(finish_test);
    go_test = 0;

    // data 1
    #10 go_test = 1;
        command_test = 3'b101;
    wait(finish_test);
    go_test = 0;

    // ACK
    #10 go_test = 1;
        command_test = 3'b110;
    wait(finish_test);
    go_test = 0;

    // NACK
    #10 go_test = 1;
        command_test = 3'b111;
    wait(finish_test);
    go_test = 0;
    
    $finish;
end

endmodule
