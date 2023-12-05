`timescale 1ns / 10ps

module testbench ();
    reg clk, rst_n;
    reg        slave_en;
    reg  [7:0] byte_write_i;
    wire [7:0] byte_read_o;
    wire read_write_flag, byte_finish, transmit_busy, transmit_err;
    reg scl_i, sda_i;
    wire scl_o, sda_o;

    // test parameters and variables
    parameter slave_addr = 7'b101_1101;  // without read/write bit
    parameter wrong_addr = 7'b110_0100;  // wrong address, without read/write bit
    parameter data_test_value = 32'h13_57_9b_df;
    parameter transmit_num = 4;  // transmit_num * 8 <= length of data_test_value
    parameter clk_divisor = 4;  // period_of_SCL = clk_divisor * period_of_clk

    integer test_ctrl;
    parameter WRONG_ADDR = 0;
    parameter SLAVE_READ = 1;
    parameter SLAVE_WRITE = 2;
    parameter SLAVE_COMBINED1 = 3;
    parameter SLAVE_COMBINED2 = 4;
    parameter SLAVE_COMBINED3 = 5;
    integer ctrl_cnt;
    parameter START = 0;
    parameter ADDR = 1;
    parameter TRANSMIT = ADDR + transmit_num;
    parameter PRE_STOP = ADDR + transmit_num + 1;
    parameter STOP = ADDR + transmit_num + 2;
    reg           test_start;
    reg     [3:0] bit_cnt;
    integer       error_cnt;

    // instantiate the submodule
    I2C_slave test_module (
        .clk            (clk),
        .rst_n          (rst_n),
        .slave_en       (slave_en),
        .slave_addr     (slave_addr),
        .byte_write_i   (byte_write_i),
        .byte_read_o    (byte_read_o),
        .read_write_flag(read_write_flag),
        .byte_finish    (byte_finish),
        .transmit_busy  (transmit_busy),
        .transmit_err   (transmit_err),
        .scl_i          (scl_i),
        .scl_o          (scl_o),
        .sda_i          (sda_i),
        .sda_o          (sda_o)
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

    // counter for clock division
    reg [31:0] counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 32'b0;
        end
        else if (test_start) begin
            if (counter == (clk_divisor - 1)) begin
                counter <= 32'b0;
            end
            else begin
                counter <= counter + 1;
            end
        end
        else begin
            counter <= counter;
        end
    end

    // generate scl_i
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_i <= 1'b1;
        end
        else begin
            if (counter < (clk_divisor / 2)) begin
                scl_i <= 1'b1;
            end
            else begin
                scl_i <= 1'b0;
            end
        end
    end

    // detect scl rising and falling edge
    reg scl_last;
    wire scl_rise, scl_fall;
    // save scl last state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_last <= 1'b1;
        end
        else begin
            scl_last <= scl_i;
        end
    end
    assign scl_rise = (~scl_last) && scl_i;
    assign scl_fall = scl_last && (~scl_i);

    // task to simulate master writing 1-byte data to slave and check ack
    task write_to_slave;
        input [7:0] byte_to_slave;
        begin
            if ((bit_cnt == 4'b1000) && scl_rise) begin  // check ACK
                if (sda_o) begin  // NACK: stop transmitting
                    ctrl_cnt <= PRE_STOP;
                end
                else begin  // ACK: continue transmitting
                    ctrl_cnt <= ctrl_cnt + 1;
                end
                bit_cnt <= 4'b0000;
            end
            else if (bit_cnt < 4'b1000) begin  // write 1-byte data
                if (scl_fall) begin
                    sda_i <= byte_to_slave[7-bit_cnt];
                end
                else if (scl_rise) begin
                    bit_cnt <= bit_cnt + 1;
                end
            end
        end
    endtask

    // task to simulating master reading 1-byte data from slave and check ack
    task read_from_slave;
        input ack;
        output [7:0] byte_from_slave;
        begin
            if (bit_cnt == 4'b1000) begin
                if (scl_fall) begin  // write ACK/NACK
                    if (ack) begin
                        sda_i <= 1'b0;
                    end
                    else begin
                        sda_i <= 1'b1;
                    end
                end
                else if (scl_rise) begin
                    bit_cnt  <= 4'b0000;
                    ctrl_cnt <= ctrl_cnt + 1;
                end
            end
            else if (bit_cnt < 4'b1000) begin  // read 1-byte data
                if (scl_rise) begin
                    byte_from_slave <= {byte_from_slave[6:0], sda_o};
                    bit_cnt <= bit_cnt + 1;
                end
            end
        end
    endtask

    // task to simulating master reading, writing or combined transmit with slave
    reg [7:0] byte_read_from_slave, byte_write_to_slave;
    always @(*) begin
        if ((ctrl_cnt > ADDR) && (ctrl_cnt <= TRANSMIT)) begin
            byte_write_to_slave <=
                data_test_value[((transmit_num-(ctrl_cnt-ADDR)+1)*8-1)-:8];
        end
        else begin
            byte_write_to_slave <= 8'b0;
        end
    end
    task transmit_test;
        input [6:0] addr;
        input read_write, combined_mode;
        begin
            if (ctrl_cnt == START) begin  // write start
                if (scl_i) begin
                    sda_i <= 1'b0;
                    ctrl_cnt <= ctrl_cnt + 1;
                end
            end
            else if (ctrl_cnt == ADDR) begin  // write address and read/write flag
                write_to_slave({addr, read_write});
            end
            else if (ctrl_cnt <= TRANSMIT) begin  // read/write transmit_num times
                if (read_write) begin  // master write. slave read
                    write_to_slave(byte_write_to_slave);
                end
                else begin  // master read, slave write
                    if (ctrl_cnt == TRANSMIT) begin  // NACK to stop
                        read_from_slave(1'b0, byte_read_from_slave);
                    end
                    else begin  // ACK to continue
                        read_from_slave(1'b1, byte_read_from_slave);
                    end
                end
            end
            else if (ctrl_cnt == PRE_STOP) begin
                if (scl_fall) begin
                    if (combined_mode) begin
                        sda_i <= 1'b1;
                        ctrl_cnt <= ctrl_cnt + 2;  // skip stop
                    end
                    else begin
                        sda_i <= 1'b0;
                        ctrl_cnt <= ctrl_cnt + 1;
                    end
                end
            end
            else if (ctrl_cnt == STOP) begin  // write stop
                if (scl_i) begin
                    sda_i <= 1'b1;
                    ctrl_cnt <= ctrl_cnt + 1;
                end
            end
        end
    endtask

    // simulating master transmit with slave
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_i <= 1'b1;
            byte_read_from_slave <= 8'b0;
            bit_cnt <= 4'b0;
        end
        else if (test_start) begin
            case (test_ctrl)
                WRONG_ADDR: begin
                    transmit_test(wrong_addr, 1'b1, 1'b0);
                end
                SLAVE_READ: begin
                    transmit_test(slave_addr, 1'b1, 1'b0);
                end
                SLAVE_WRITE: begin
                    transmit_test(slave_addr, 1'b0, 1'b0);
                end
                SLAVE_COMBINED1: begin
                    transmit_test(slave_addr, 1'b1, 1'b1);
                end
                SLAVE_COMBINED2: begin
                    transmit_test(slave_addr, 1'b0, 1'b1);
                end
                SLAVE_COMBINED3: begin
                    transmit_test(slave_addr, 1'b1, 1'b0);
                end
            endcase
        end
    end

    // test and check slave
    reg [7:0] byte_to_check;
    always @(*) begin
        if ((ctrl_cnt > ADDR) && (ctrl_cnt <= TRANSMIT)) begin
            byte_write_i <= data_test_value[((transmit_num-(ctrl_cnt-ADDR)+1)*8-1)-:8];
        end
        else begin
            byte_write_i <= 8'b0;
        end
    end
    always @(*) begin
        if ((ctrl_cnt > (ADDR + 1)) && (ctrl_cnt <= (TRANSMIT + 1))) begin
            byte_to_check <= data_test_value[((transmit_num-ctrl_cnt+3)*8-1)-:8];
        end
        else begin
            byte_to_check <= 8'b0;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end
        else if (byte_finish) begin
            if (read_write_flag) begin
                if (byte_read_o != byte_to_check) begin
                    error_cnt <= error_cnt + 1;
                    $display("     ++%02d++FAIL++ write/read: %b/%b",
                             ctrl_cnt - ADDR - 1, byte_to_check, byte_read_o);
                end
                else begin
                    error_cnt <= error_cnt;
                    $display("     --%02d--PASS-- write/read: %b/%b",
                             ctrl_cnt - ADDR - 1, byte_to_check, byte_read_o);
                end
            end
            else begin
                if (byte_read_from_slave != byte_to_check) begin
                    error_cnt <= error_cnt + 1;
                    $display("     ++%02d++FAIL++ write/read: %b/%b",
                             ctrl_cnt - ADDR - 1, byte_to_check, byte_read_from_slave);
                end
                else begin
                    error_cnt <= error_cnt;
                    $display("     --%02d--PASS-- write/read: %b/%b",
                             ctrl_cnt - ADDR - 1, byte_to_check, byte_read_from_slave);
                end
            end
        end
    end

    // start test and generate prompt and log
    initial begin
        error_cnt = 0;

        // test and check
        $display("\n**************** 'slave' module test started ***************\n");
        slave_en   = 1'b1;
        ctrl_cnt   = 0;
        test_start = 1'b0;
        test_ctrl  = WRONG_ADDR;
        #200 test_start = 1'b1;
        $display("--1-- wrong address test -----------------------------------");
        wait (ctrl_cnt == (STOP + 1));
        ctrl_cnt   = 0;
        test_start = 1'b0;
        test_ctrl  = SLAVE_READ;
        #200 test_start = 1'b1;
        $display("--2-- slave read data test ---------------------------------");
        wait (ctrl_cnt == (STOP + 1));
        ctrl_cnt   = 0;
        test_start = 1'b0;
        test_ctrl  = SLAVE_WRITE;
        #200 test_start = 1'b1;
        $display("--3-- slave write data test --------------------------------");
        wait (ctrl_cnt == (STOP + 1));
        ctrl_cnt   = 0;
        test_start = 1'b0;
        test_ctrl  = SLAVE_COMBINED1;
        #200 test_start = 1'b1;
        $display("--4-- combined mode test -----------------------------------");
        $display("-4-1- slave read -------------------------------------------");
        wait (ctrl_cnt == (STOP + 1));
        ctrl_cnt   = 0;
        test_ctrl  = SLAVE_COMBINED2;
        test_start = 1'b1;
        $display("-4-2- slave write ------------------------------------------");
        wait (ctrl_cnt == (STOP + 1));
        ctrl_cnt   = 0;
        test_ctrl  = SLAVE_COMBINED3;
        test_start = 1'b1;
        $display("-4-3- slave read -------------------------------------------");
        wait (ctrl_cnt == (STOP + 1));
        ctrl_cnt   = 0;
        test_start = 1'b0;
        slave_en   = 1'b0;
        $display("------------------------------------------------------------");

        // result
        if (error_cnt == 0) begin
            $display("result: passed with 0 errors in tests");
        end
        else begin
            $display("result: failed with %02d errors in tests", error_cnt);
        end
        $display("\n*************** 'slave' module test finished ***************\n");
        $finish;
    end

endmodule
