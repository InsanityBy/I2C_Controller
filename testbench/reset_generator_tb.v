`timescale 1ns / 10ps

module testbench ();
    reg clk, rst_n;
    wire rst_sync;

    // instantiate the submodule
    reset_generator test_module (
        .clk       (clk),
        .rst_n     (rst_n),
        .rst_sync_n(rst_sync)
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

    // generate clock
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // test sync release
    integer i = 0;
    initial begin
        rst_n = 1;
        for (i = 0; i <= 100; i = i + 5) begin
            #i rst_n = ~rst_n;
        end
        #100 $finish;
    end

endmodule
