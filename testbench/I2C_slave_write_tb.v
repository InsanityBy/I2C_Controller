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
    parameter test_round = 8;
    parameter scl_div = 8;
    parameter clk_period = 20;
    parameter scl_period = clk_period * scl_div;

    // signals
    reg clk, rst_n;
    reg wr_en, is_byte, data_i;
    wire wr_ld, data_o, wr_finish, wr_err, get_start, get_stop, bus_err;
    reg scl_i, sda_i, sda_ctrl;
    wire sda_o;

    // instantiate the module under test
    I2C_slave_write test_module (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (wr_en),
        .is_byte  (is_byte),
        .wr_ld    (wr_ld),
        .data_i   (data_i),
        .data_o   (data_o),
        .wr_finish(wr_finish),
        .wr_err   (wr_err),
        .get_start(get_start),
        .get_stop (get_stop),
        .bus_err  (bus_err),
        .scl_i    (scl_i),
        .sda_i    (sda_i),
        .sda_o    (sda_o)
    );
    // sda_ctrl to simulate another transmitter
    always @(*) begin
        sda_i = sda_o && sda_ctrl;
    end

    // generate clock and reset
    initial begin
        clk   = 1'b0;
        rst_n = 1'b1;
        #clk_period rst_n = 1'b0;
        #clk_period rst_n = 1'b1;
        forever #(clk_period / 2) clk = ~clk;
    end

    // data shift register
    reg [7:0] shifter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shifter <= 8'b0;
        end
        else if (wr_ld) begin
            shifter <= {shifter[6:0], 1'b0};
        end
    end
    always @(*) begin
        data_i = shifter[7];
    end

    // task: read 1-bit data
    task read_bit;
        input data_i;
        output data_o;
        input insert_bus_err;
        input insert_wr_err;
        integer i;
        begin
            i = 0;
            repeat (scl_div)
            @(posedge clk) begin
                if (i == 0) begin  // scl falls
                    #1 scl_i = 1'b0;
                end
                if (i == 1) begin
                    #1 wr_en = 1'b1;  // enable module 1 clock after scl falls
                    // simulate another transmitter write 0
                    // writing 1 won't cause error due to wired and
                    if (insert_wr_err) begin
                        #1 sda_ctrl = 1'b0;
                    end
                    else begin
                        sda_ctrl = data_i;
                    end
                end
                if (i == scl_div / 2) begin  // scl rises
                    #1 scl_i = 1'b1;
                end
                if (i == scl_div / 2 + 1) begin
                    data_o = sda_i;  // read data on sda
                    // insert bus error
                    if (insert_bus_err) begin
                        #1 sda_ctrl = ~sda_ctrl;
                    end
                end
                i = i + 1;
            end
        end
    endtask

    // task: read 1-bit data from module
    task read_bit_test;
        input data_i;
        output data_o;
        input insert_bus_err;
        input insert_wr_err;
        begin
            // initial
            scl_i = 1'b1;
            sda_ctrl = 1'b1;
            wr_en = 1'b0;
            is_byte = 1'b0;
            shifter[7] = data_i;
            #scl_period;
            // read
            read_bit(data_i, data_o, insert_bus_err, insert_wr_err);
            @(posedge clk) #1 scl_i = 1'b0;  // scl falls
            // wait finish
            wait (wr_finish);
            #(clk_period + 1) wr_en = 1'b0;
        end
    endtask

    // task: read 1-byte data from module
    task read_byte_test;
        input [7:0] data_i;
        output [7:0] data_o;
        input insert_bus_err;
        input insert_wr_err;
        input [2:0] err_pos;
        integer i;
        begin
            // initial
            scl_i = 1'b1;
            sda_ctrl = 1'b1;
            wr_en = 1'b0;
            is_byte = 1'b1;
            shifter = data_i;
            #scl_period;
            // generate scl and read data from module
            for (i = 0; i < 8; i = i + 1) begin
                if (i == err_pos) begin
                    read_bit(data_i[7-i], data_o[7-i], insert_bus_err, insert_wr_err);
                end
                else begin
                    read_bit(data_i[7-i], data_o[7-i], 1'b0, 1'b0);
                end
            end
            @(posedge clk) #1 scl_i = 1'b0;  // scl falls
            // wait finish
            wait (wr_finish);
            #(clk_period + 1) wr_en = 1'b0;
        end
    endtask

    // test module
    integer       test_cnt;
    integer       err_cnt;
    reg     [7:0] data;
    reg     [7:0] data_get;
    initial begin
        test_cnt = 0;
        err_cnt  = 0;
        data_get = 8'b0;
        $display("\n******************** module test started *******************\n");
        for (test_cnt = 1; test_cnt <= test_round; test_cnt = test_cnt + 1) begin
            $display("round %02d/%02d", test_cnt, test_round);
            // random data to write
            data = $random % 256;
            // test read bit
            $display("write bit: %b", data[7]);
            read_bit_test(data[7], data_get[7], 1'b0, 1'b0);
            if (data_get[7] != data[7]) begin
                $display("write bit error\n");
                err_cnt = err_cnt + 1;
            end
            // test read bit insert bus error
            read_bit_test(data[7], data_get[7], 1'b1, 1'b0);
            // insert write error
            read_bit_test(data[7], data_get[7], 1'b0, 1'b1);
            // both error
            read_bit_test(data[7], data_get[7], 1'b1, 1'b1);

            // test read byte
            $display("write byte: %b", data);
            read_byte_test(data, data_get, 1'b0, 1'b0, 3'b000);
            if (data_get != data) begin
                $display("read byte error\n");
                err_cnt = err_cnt + 1;
            end
            // test read byte insert error at different position
            for (integer i = 0; i < 8; i = i + 1) begin
                // bus error
                read_byte_test(data, data_get, 1'b1, 1'b0, i);
                // write error
                read_byte_test(data, data_get, 1'b0, 1'b1, i);
                // both error
                read_byte_test(data, data_get, 1'b1, 1'b1, i);
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
