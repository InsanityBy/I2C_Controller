`timescale 1ns/10ps

module testbench();
reg clk, rst_n;
reg transfer_go, byte_go, read_write_test, combined_test;
reg [6: 0] target_address;
reg [7: 0] data_in;
wire [7: 0] data_out;
wire data_finish, transfer_finish, transfer_busy, bus_busy, error;
reg scl_in, sda_in;
wire scl_out, sda_out;

// test value, test all state transfer
parameter test_address = 7'b110_0110;
parameter data_to_write = 32'h13_57_9b_df;
reg test_stop;

// instantiate the submodule
I2C_master test_module(
               .clock(clk),
               .reset_n(rst_n),
               .transfer_control(transfer_go),
               .byte_control(byte_go),
               .read_write(read_write_test),
               .combined_enable(combined_test),
               .targret_address(test_address),
               .data_in(data_in),
               .data_out(data_out),
               .data_finish(data_finish),
               .transfer_busy(transfer_busy),
               .bus_busy(bus_busy),
               .error(error),
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

// test module
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        test_stop <= 1'b0;
        transfer_go <= 1'b0;
        byte_go <= 1'b0;
        read_write_test <= 1'b0;
        combined_test <= 1'b0;
    end
    else if (!transfer_busy) begin
        test_stop <= 1'b0;
        target_address <= test_address;
        transfer_go <= 1'b1;
        read_write_test <= 1'b0;
        combined_test <= 1'b0;
        byte_go <= 1'b1;
        data_in <= data_to_write[31:24];
    end
    else if(data_finish) begin
        test_stop <= 1'b1;
        transfer_go <= 1'b0;
        read_write_test <= 1'b0;
        combined_test <= 1'b0;
        byte_go <= 1'b0;
        $display("--write--: %b", data_in);
    end
    else begin
        test_stop <= 1'b0;
        target_address <= test_address;
        transfer_go <= 1'b1;
        read_write_test <= 1'b0;
        combined_test <= 1'b0;
        byte_go <= 1'b1;
        data_in <= data_in;
    end
end

// prompt and log
initial begin
    $display("******** 'master' module test started ********");
    wait(test_stop);
    $display("-------------------------------------------------");
    $display("******** 'master' module test finished ********");
    $finish;
end

endmodule
