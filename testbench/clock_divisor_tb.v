`timescale 1ns / 10ps

module testbench ();
    reg clk, rst_n, clk_en;
    reg  [3:0] clk_div;
    wire [3:0] clk_div_cur;
    wire       clk_o;

    // instantiate the submodule
    clock_divisor test_module (
        .clk_i      (clk),
        .rst_n      (rst_n),
        .clk_en     (clk_en),
        .clk_div    (clk_div),
        .clk_div_cur(clk_div_cur),
        .clk_o      (clk_o)
    );

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

    // generate clock and reset
    initial begin
        clk   = 0;
        rst_n = 1;
        #10 rst_n = 0;
        #10 rst_n = 1;
        forever #10 clk = ~clk;
    end

    // test clock divisor
    integer i = 0;
    initial begin
        clk_div = 0;
        clk_en  = 0;

        // enable module
        #40 clk_en = 1;

        // set clk_div when module enabled
        clk_div = 4'hf;

        // test all clk_div value
        for (i = 0; i <= 4'hf; i = i + 1) begin
            #1000 clk_en = 0;
            #10 clk_div = i;
            #10 clk_en = 1;
        end
        $finish;
    end

endmodule
