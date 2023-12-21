`timescale 1ns / 10ps

module testbench ();
    // use fsdb/vcd or vcd to save wave
`ifdef fsdbdump
    initial begin
        $display("\n**************** fsdb file dump is turned on ***************");
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0);
        #100000 $fsdbDumpoff;
    end
`endif
`ifdef vcddump
    initial begin
        $display("\n**************** vcd file dump is turned on ****************");
        $dumpfile("wave.vcd");
        $dumpvars(0);
        #100000 $dumpoff;
    end
`endif

    // test parameters
    parameter clk_period = 20;
    parameter clk_div = 5;

    // signals
    reg clk, rst_n, clk_en;
    wire clk_o;

    // instantiate the module under test
    clock_divisor test_module (
        .clk_i  (clk),
        .rst_n  (rst_n),
        .clk_en (clk_en),
        .clk_div(clk_div),
        .clk_o  (clk_o)
    );

    // generate clock and reset
    initial begin
        clk   = 1'b0;
        rst_n = 1'b1;
        #clk_period rst_n = 1'b0;
        #clk_period rst_n = 1'b1;
        forever #(clk_period / 2) clk = ~clk;
    end

    // test clock divisor
    initial begin
        clk_en = 0;
        // enable module
        @(posedge clk) #1 clk_en = 1;
        #10000 $finish;
    end

endmodule
