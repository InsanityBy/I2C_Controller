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
    parameter test_round = 32;
    parameter scl_div = 8;
    parameter clk_period = 20;
    parameter scl_period = clk_period * scl_div;

    // signals
    reg clk, rst_n;
    reg rd_en, is_byte;
    wire rd_ld, data_o, rd_finish, get_start, get_stop, bus_err;
    reg scl_i, sda_i;

    // instantiate the module under test
    I2C_read test_module (
        .clk      (clk),
        .rst_n    (rst_n),
        .rd_en    (rd_en),
        .is_byte  (is_byte),
        .rd_ld    (rd_ld),
        .data_o   (data_o),
        .rd_finish(rd_finish),
        .get_start(get_start),
        .get_stop (get_stop),
        .bus_err  (bus_err),
        .scl_i    (scl_i),
        .sda_i    (sda_i)
    );

    // generate clock and reset
    initial begin
        clk   = 1'b0;
        rst_n = 1'b1;
        #clk_period rst_n = 1'b0;
        #clk_period rst_n = 1'b1;
        forever #(clk_period / 2) clk = ~clk;
    end

    // task: write 1-bit data
    task write_bit;
        input data;
        input insert_err;
        integer i;
        begin
            i = 0;
            repeat (scl_div)
            @(posedge clk) begin
                if (i == 0) begin  // scl falls
                    #1 scl_i = 1'b0;
                end
                if (i == 1) begin
                    #1 sda_i = data;  // write data 1 clock after scl falls
                    #1 rd_en = 1'b1;  // enable module 1 clock after scl falls
                end
                if (i == scl_div / 2) begin  // scl rises
                    #1 scl_i = 1'b1;
                end
                if (i == scl_div / 2 + 1) begin  // insert bus error
                    if (insert_err) begin
                        #1 sda_i = ~sda_i;
                    end
                end
                i = i + 1;
            end
        end
    endtask

    // task: write 1-bit data to test
    task write_bit_test;
        input data;
        input insert_err;
        integer i;
        begin
            // initial
            scl_i   = 1'b1;
            sda_i   = 1'b1;
            rd_en   = 1'b0;
            is_byte = 1'b0;
            #clk_period;
            // write
            write_bit(data, insert_err);
            @(posedge clk) #1 scl_i = 1'b0;  // scl falls
            // wait finish
            wait (rd_finish);
            #(clk_period + 1) rd_en = 1'b0;
        end
    endtask

    // task: write 1-byte data to test
    task write_byte_test;
        input [7:0] data;
        input insert_err;
        input [2:0] err_pos;
        integer i;
        begin
            // initial
            scl_i   = 1'b1;
            sda_i   = 1'b1;
            rd_en   = 1'b0;
            is_byte = 1'b1;
            #clk_period;
            //write
            for (i = 0; i < 8; i = i + 1) begin
                if (i == err_pos) begin
                    write_bit(data[7-i], insert_err);
                end
                else begin
                    write_bit(data[7-i], 1'b0);
                end
            end
            @(posedge clk) #1 scl_i = 1'b0;  // scl falls
            // wait finish
            wait (rd_finish);
            #(clk_period + 1) rd_en = 1'b0;
        end
    endtask

    // data shift register
    reg [7:0] shifter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shifter <= 8'b0;
        end
        else if (rd_ld) begin
            shifter <= {shifter[6:0], data_o};
        end
    end

    // test module
    integer       test_cnt;
    integer       err_cnt;
    reg     [7:0] data;
    initial begin
        test_cnt = 0;
        err_cnt  = 0;
        $display("\n******************** module test started *******************\n");
        for (test_cnt = 1; test_cnt <= test_round; test_cnt = test_cnt + 1) begin
            $display("round %02d/%02d", test_cnt, test_round);
            // random data to write
            data = $random % 256;
            // test read bit
            $display("write bit: %b", data[0]);
            write_bit_test(data[0], 1'b0);
            if (shifter[0] != data[0]) begin
                $display("read bit error\n");
                err_cnt = err_cnt + 1;
            end
            // test read bit insert error
            write_bit_test(data[0], 1'b1);

            // test read byte
            $display("write byte: %b", data);
            write_byte_test(data, 1'b0, 3'b000);
            if (shifter != data) begin
                $display("read byte error\n");
                err_cnt = err_cnt + 1;
            end
            // test read byte insert error at different position
            for (integer i = 0; i < 8; i = i + 1) begin
                write_byte_test(data, 1'b1, i);
            end
            $display("------------------------------------------------------------");
        end
        // result
        if (err_cnt == 0) begin
            $display("result: passed with 0 error");
        end
        else begin
            $display("result: failed with %02d errors in tests", err_cnt);
        end
        $display("\n******************* module test finished *******************\n");
        $finish;
    end

endmodule
