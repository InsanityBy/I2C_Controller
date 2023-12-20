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
    parameter scl_div1 = 4;
    parameter scl_div2 = 4;

    // signals
    reg clk, rst_n, scl_en, scl_wait;
    wire scl_stretched;
    reg  scl_ctrl;
    wire scl, scl_o;

    // instantiate the module under test
    scl_generator test_module (
        .clk          (clk),
        .rst_n        (rst_n),
        .scl_en       (scl_en),
        .scl_wait     (scl_wait),
        .scl_div      (scl_div1),
        .scl_stretched(scl_stretched),
        .scl_i        (scl),
        .scl_o        (scl_o)
    );

    // generate clock and reset
    initial begin
        clk   = 1'b0;
        rst_n = 1'b1;
        #clk_period rst_n = 1'b0;
        #clk_period rst_n = 1'b1;
        forever #(clk_period / 2) clk = ~clk;
    end

    // generate another scl
    integer scl_cnt;
    always @(posedge clk) begin
        if (!scl_en) begin
            scl_ctrl <= 1'b1;
            scl_cnt  <= 0;
        end
        else if (scl_ctrl != scl) begin
            scl_ctrl <= scl_ctrl;
            scl_cnt  <= scl_cnt;
        end
        else if (scl_cnt == (scl_div2 - 1)) begin
            scl_ctrl <= 1'b0;
            scl_cnt  <= scl_cnt + 1;
        end
        else if (scl_cnt == (scl_div2 * 2 - 1)) begin
            scl_ctrl <= 1'b1;
            scl_cnt  <= 0;
        end
        else begin
            scl_ctrl <= scl_ctrl;
            scl_cnt  <= scl_cnt + 1;
        end
    end

    // connect scl
    assign scl = scl_o && scl_ctrl;

    // test scl synchronization
    initial begin
        scl_ctrl = 1;
        scl_wait = 0;
        scl_en   = 0;
        // stat test
        @(posedge clk) #1 scl_en = 1;
        #1000;
        // test scl wait
        @(negedge scl_o) #1 scl_wait = 1;
        #1000 scl_wait = 0;
        // finish
        #10000 $finish;
    end

endmodule
