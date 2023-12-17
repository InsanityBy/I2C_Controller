`timescale 1ns/10ps

module testbench();
    reg clk, rst_n, go_test, data_test;
    reg [2:0] command_test;
    wire load_test, finish_test, scl_test, sda_test;
    
    // command for different write operation
    parameter IDLE  = 3'b000;
    parameter START = 3'b001;
    parameter DATA  = 3'b011;
    parameter ACK   = 3'b111;
    parameter NACK  = 3'b101;
    parameter STOP  = 3'b100;
    
    // test value for command, test all commands
    parameter command_test_value = {START, DATA, DATA, ACK, STOP, START, DATA, NACK, STOP, IDLE};
    // test data
    parameter data_test_value = 32'haa_57_9b_df;
    // test number
    parameter test_number = 10;
    reg [3:0] current_test_number;
    
    // instantiate the detector
    I2C_master_write_byte test_module(
    .clock(clk),
    .reset_n(rst_n),
    .go(go_test),
    .data(data_test),
    .command(command_test),
    .load(load_test),
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
    
    // shifter to load data
    reg [31:0] data_send;
    always @(*) begin
        data_test = data_send[31];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_send <= data_test_value;
        end
        else if (load_test) begin
            data_send <= {data_send[30:0], data_send[31]};
        end
        else begin
            data_send <= data_send;
        end
    end
    
    // test module
    reg [29:0] command_send;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            go_test             <= 1'b0;
            command_test        <= 3'b000;
            command_send        <= command_test_value;
            current_test_number <= 4'b0000;
        end
        else if (finish_test) begin
            go_test      <= 1'b1;
            command_test <= command_send[29:27];
            command_send <= {command_send[26:0], command_send[29:27]};
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
        $display("******** 'master_write_byte' module test started ********");
        #25
        command_test = START;
        // wait till finished
        wait(current_test_number == test_number);
        $display("-------------------------------------------------");
        $display("******** 'master_write_byte' module test finished ********");
        $finish;
    end
    
endmodule
