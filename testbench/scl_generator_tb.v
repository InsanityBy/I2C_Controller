`timescale 1ns / 10ps

module testbench ();
    reg clk, rst_n, scl_en, scl_wait;
    reg  [7:0] scl_div;
    wire [7:0] scl_div_cur;
    wire       scl_stretched;
    reg        scl_ctrl;
    wire scl, scl_o;

    // instantiate the submodule
    scl_generator test_module (
        .clk          (clk),
        .rst_n        (rst_n),
        .scl_en       (scl_en),
        .scl_wait     (scl_wait),
        .scl_div      (scl_div),
        .scl_div_cur  (scl_div_cur),
        .scl_stretched(scl_stretched),
        .scl_i        (scl),
        .scl_o        (scl_o)
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

    // connect scl
    assign scl = scl_o && scl_ctrl;

    // detect scl rising and falling edge
    reg  scl_last;
    wire scl_fall;
    // save scl last state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_last <= 1'b1;
        end
        else begin
            scl_last <= scl;
        end
    end
    assign scl_fall = scl_last && (~scl);

    // test clock divisor
    initial begin
        scl_ctrl = 1;
        scl_wait = 0;
        scl_div  = 0;
        scl_en   = 0;

        // enable module
        #20 scl_en = 1;

        // set scl_div when module enabled
        // scl_div should not be loaded
        #20 scl_div = 8'hff;

        // set scl_div when module disabled
        #200 scl_en = 0;
        #20 scl_div = 8'h01;
        #100 scl_en = 1;

        // simulate scl being stretched
        #100 wait (scl_fall);
        #20 scl_ctrl = 0;
        #100 scl_ctrl = 1;

        // simulate stretching scl to wait
        #100 wait (scl_fall);
        #20 scl_wait = 1;
        #100 scl_wait = 0;

        #100 scl_en = 0;
        $finish;
    end

endmodule
