`timescale 1ns/10ps

module testbench();
    reg clk, rst_n, go_test;
    reg [7:0] data_test;
    reg [2:0] command_test;
    wire finish_test, scl_test, sda_test, load_test;
    
    // instantiate the detector
    I2C_master_write_byte test_module(
    .clock(clk),
    .reset_n(rst_n),
    .go(go_test),
    .command(command_test),
    .data(data_test[7]),
    .load(load_test),
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
        #1000000
        $fsdbDumpoff;
        `endif
        `ifdef vcddump
        $display("\n*** vcd file dump is turned on ***\n");
        $dumpfile("wave.vcd");
        $dumpvars(0);
        #1000000
        $dumpoff;
        `endif
        $monitor($realtime, "finish = ", finish_test);
    end
    
    // initialize inputs and create clock
    initial begin
        clk          = 0;
        rst_n        = 1;
        go_test      = 0;
        command_test = 3'b000;
        data_test    = 8'b1010_1100;
        forever
            #10 clk = ~clk;
    end
    
    // shifter to write data
    always @(posedge clk) begin
        if (load_test)
            data_test <= {data_test[6:0], 1'b0};
        else
            data_test <= data_test;
    end
    
    initial begin
        #10 rst_n = 0;
        #10 rst_n = 1;
        
        // start bit
        go_test      = 1;
        command_test = 3'b001;
        wait(finish_test);
        go_test = 0;
        
        // ACK
        command_test = 3'b111;
        wait(!finish_test);
        go_test = 1;
        wait(finish_test);
        go_test = 0;
        
        // data
        command_test = 3'b011;
        wait(!finish_test);
        go_test = 1;
        wait(finish_test);
        go_test = 0;
        
        // stop bit
        command_test = 3'b100;
        wait(!finish_test);
        go_test = 1;
        wait(finish_test);
        go_test = 0;
        
        // NACK
        command_test = 3'b101;
        wait(!finish_test);
        go_test = 1;
        wait(finish_test);
        go_test = 0;
        
        $finish;
    end
    
endmodule
