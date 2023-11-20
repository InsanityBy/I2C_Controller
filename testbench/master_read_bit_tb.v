`timescale 1ns/10ps

module testbench();
reg clk, rst_n, go_test;
reg [2:0] command_test;
reg       sda_test;
wire finish_test, scl_test, data_test;

// instantiate the detector
I2C_master_read_bit test_module(
    .clock(clk),
    .reset_n(rst_n),
    .go(go_test),
    .finish(finish_test),
    .data(data_test),
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
    sda_test = 1;
    forever 
        #10 clk = ~clk;
end

reg [1:0] scl_state;
reg detect;

assign detect = scl_state[1] && (~scl_state[0]);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        scl_state <= 2'b00; 
    else
        scl_state <= {scl_state[0], scl_test}; 
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        sda_test <= 1'b1;
    else if(detect)
        sda_test <= ~sda_test; 
end


initial begin
    #10 rst_n = 0;
    #10 rst_n = 1;

    // read 1st
    go_test = 1;
    while(!finish_test) begin
        #5 $display("%b", data_test);
    end
    $display("get: %b",data_test);
    go_test = 0;

    // read 2nd
    wait(!finish_test);
    go_test = 1;
    while(!finish_test) begin
        #5 $display("%b", data_test);
    end
    $display("get: %b",data_test);
    go_test = 0;

    #100 $finish;
end

endmodule
