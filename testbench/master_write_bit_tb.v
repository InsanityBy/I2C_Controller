`timescale 1ns/10ps

module testbench();
    reg clk, rst_n, go_test;
    reg [2:0] command_test;
    wire finish_test, scl_test, sda_test;
    
    // command for different write operation
    parameter IDLE      = 3'b000;
    parameter START_BIT = 3'b010;
    parameter STOP_BIT  = 3'b011;
    parameter DATA_0    = 3'b100;
    parameter DATA_1    = 3'b101;
    parameter ACK_BIT   = 3'b110;
    parameter NACK_BIT  = 3'b111;
    
    // test value for command, test all commands
    parameter command_test_value = {IDLE, START_BIT, STOP_BIT, DATA_0, DATA_1, ACK_BIT, NACK_BIT};
    // test numver
    parameter test_number = 7;
    reg [3:0] current_test_number;
    
    // instantiate the detector
    I2C_master_write_bit test_module(
    .clock(clk),
    .reset_n(rst_n),
    .go(go_test),
    .command(command_test),
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
    
    // test module
    reg [20:0] command_send;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            go_test             <= 1'b0;
            command_test        <= 3'b000;
            command_send        <= command_test_value;
            current_test_number <= 4'b0000;
        end
        else if (finish_test) begin
            go_test      <= 1'b0;
            command_test <= command_send[20:18];
            command_send <= {command_send[17:0], command_send[20:18]};
            $display("--%02d-- command: %3b", current_test_number, command_test);
            current_test_number <= current_test_number + 1;
        end
        else begin
            go_test      <= 1'b1;
            command_test <= command_test;
            command_send <= command_send;
        end
    end
    
    // prompt and log
    initial begin
        $display("******** 'master_write_bit' module test started ********");
        wait(current_test_number == test_number);
        #10
        $display("-------------------------------------------------");
        $display("******** 'master_write_bit' module test finished ********");
        $finish;
    end
    
endmodule
