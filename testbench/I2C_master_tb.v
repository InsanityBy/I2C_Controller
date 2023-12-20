`timescale 1ns / 10ps

module testbench ();
    // use fsdb/vcd or vcd to save wave
`ifdef fsdbdump
    initial begin
        $display("\n**************** fsdb file dump is turned on ***************");
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0);
        #1000000 $fsdbDumpoff;
    end
`endif
`ifdef vcddump
    initial begin
        $display("\n**************** vcd file dump is turned on ****************");
        $dumpfile("wave.vcd");
        $dumpvars(0);
        #1000000 $dumpoff;
    end
`endif

    // test parameters
    parameter test_round = 32;
    parameter scl_div = 16;
    parameter clk_period = 20;
    parameter scl_period = clk_period * scl_div;

    // signals
    reg clk, rst_n;

    reg master_en, start_trans, stop_trans, rd_clr, wr_rdy;
    wire rd_reg_full, wr_reg_empty;
    reg  [7:0] byte_wr_i;
    wire [7:0] byte_rd_o;
    wire trans_start, addr_match, trans_dir, get_nack, trans_stop, bus_err, byte_wait, arbit_fail;
    wire m_scl_div;
    reg scl, sda;
    reg m_scl, m_sda, s_sda;
    wire scl_o, sda_o;

    // instantiate the module under test
    I2C_master test_module (
        .clk         (clk),
        .rst_n       (rst_n),
        // control
        .master_en   (master_en),
        .start_trans (start_trans),
        .stop_trans  (stop_trans),
        .rd_clr      (rd_clr),
        .wr_rdy      (wr_rdy),
        .rd_reg_full (rd_reg_full),
        .wr_reg_empty(wr_reg_empty),
        // address and data
        .byte_wr_i   (byte_wr_i),
        .byte_rd_o   (byte_rd_o),
        // status
        .trans_start (trans_start),
        .addr_match  (addr_match),
        .trans_dir   (trans_dir),
        .get_nack    (get_nack),
        .trans_stop  (trans_stop),
        .bus_err     (bus_err),
        .byte_wait   (byte_wait),
        .arbit_fail  (arbit_fail),
        // I2C
        .set_scl_div (8'd16),
        .scl_div     (m_scl_div),
        .scl_i       (scl),
        .scl_o       (scl_o),
        .sda_i       (sda),
        .sda_o       (sda_o)
    );

    // sda and scl
    always @(*) begin
        scl = scl_o && m_scl;
        sda = sda_o && m_sda && s_sda;
    end

    // generate clock and reset
    initial begin
        clk   = 1'b0;
        rst_n = 1'b1;
        #clk_period rst_n = 1'b0;
        #clk_period rst_n = 1'b1;
        forever #(clk_period / 2) clk = ~clk;
    end

    // generate m_scl to test clock synchronization
    reg     scl_en;
    integer scl_cnt;
    initial begin
        scl_en = 1'b0;
    end
    always @(posedge clk) begin
        if (!scl_en) begin
            m_scl   <= 1'b1;
            scl_cnt <= 0;
        end
        else if (m_scl != scl) begin
            m_scl   <= m_scl;
            scl_cnt <= scl_cnt;
        end
        else if (scl_cnt == (scl_div / 2 - 1)) begin
            m_scl   <= 1'b0;
            scl_cnt <= scl_cnt + 1;
        end
        else if (scl_cnt == (scl_div - 1)) begin
            m_scl   <= 1'b1;
            scl_cnt <= 0;
        end
        else begin
            m_scl   <= m_scl;
            scl_cnt <= scl_cnt + 1;
        end
    end

    // task: simulate another master write start
    task write_start;
        integer i;
        begin
            m_sda = 1'b1;
            wait (scl);
            #(scl_period / 4 + 1) m_sda = 1'b0;
            scl_en = 1'b1;
        end
    endtask

    // task: simulate another master write stop
    task write_stop;
        begin
            wait (~scl);
            #(scl_period / 4 + 1) m_sda = 1'b0;
            wait (scl);
            #(scl_period / 4 + 1) m_sda = 1'b1;
            scl_en = 1'b0;
        end
    endtask

    // simulate slave
    // task: simulate slave detect start and stop
    reg sda_reg, get_start, get_stop;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_reg <= 1'b1;
        end
        else begin
            sda_reg <= sda;
        end
    end
    always @(*) begin
        get_start = scl && sda_reg && (~sda);
        get_stop  = scl && (~sda_reg) && sda;
    end
    task slave_get_start;
        begin
            wait (get_start);
            wait (~get_start);
        end
    endtask
    task slave_get_stop;
        begin
            wait (get_stop);
            wait (~get_stop);
            disable slave_correct_addr;
            disable slave_wrong_addr;
        end
    endtask

    // task: simulate slave write data and check ack
    task slave_write_data;
        input [7:0] data;
        output ack;
        integer i;
        begin
            i = 0;
            // write data
            repeat (8)
            @(negedge scl) begin
                #1 s_sda = data[7-i];
                i = i + 1;
            end
            // get ack
            @(negedge scl) #1 s_sda = 1'b1;  //release sda
            @(posedge scl) #1 ack = sda;
        end
    endtask

    // task: simulate slave read data and write ack/nack
    task slave_read_data;
        input ack;
        output [7:0] data_o;
        reg     [7:0] data;
        integer       i;
        begin
            i = 0;
            repeat (8)
            @(posedge scl) begin
                #1 data[7-i] = sda;
                i = i + 1;
            end
            // write ack
            data_o = data;
            @(negedge scl) #1 s_sda = ack;
        end
    endtask

    // simulate slave
    task slave_wrong_addr;
        reg [7:0] data;
        begin
            s_sda = 1'b1;
            // start
            slave_get_start;
            //address
            slave_read_data(1'b1, data);
        end
    endtask

    task slave_correct_addr;
        reg [7:0] data_read, data_write;
        reg ack;
        begin
            s_sda = 1'b1;
            // start
            slave_get_start;
            //address
            slave_read_data(1'b0, data_read);
            // data
            if (data_read[0]) begin  // write to master
                while (1) begin
                    data_write = $random % 256;
                    slave_write_data(data_write, ack);
                    if (ack) begin
                        s_sda = 1'b1;
                        disable slave_correct_addr;
                    end
                end
            end
            else begin  // get from master
                while (1) begin
                    @(negedge scl) #1 s_sda = 1'b1;  // release sda
                    slave_read_data(1'b0, data_read);
                end
            end
        end
    endtask

    // control test module
    // task: write n-byte to slave
    reg [7:0] data_written;
    task write_to_slave;
        input [6:0] addr;
        input [31:0] n_byte;
        reg     ack;
        integer i;
        begin
            // initial
            master_en = 1'b0;
            start_trans = 1'b0;
            stop_trans = 1'b0;
            rd_clr = 1'b0;
            wr_rdy = 1'b0;
            byte_wr_i = 8'b0;
            i = 0;
            // enable
            @(posedge clk) #1 master_en = 1'b1;
            // start
            @(posedge clk) #1 start_trans = 1'b1;
            wait (trans_start);
            @(posedge clk) #1 start_trans = 1'b0;
            // address
            wait (wr_reg_empty);
            @(posedge clk) #1 byte_wr_i = {addr, 1'b0};
            wr_rdy = 1'b1;
            @(posedge clk) #1 wr_rdy = 1'b0;
            // data
            wait (get_nack || addr_match);
            if (get_nack) begin
                @(posedge clk) #1 stop_trans = 1'b1;
                wait (trans_stop);
                @(posedge clk) #1 stop_trans = 1'b0;
                master_en = 1'b0;
            end
            else if (addr_match) begin
                for (i = 0; i < n_byte; i = i + 1) begin
                    data_written = $random % 256;
                    wait (wr_reg_empty);
                    @(posedge clk) #1 byte_wr_i = data_written;
                    wr_rdy = 1'b1;
                    @(posedge clk) #1 wr_rdy = 1'b0;
                end
                // stop
                wait (byte_wait);
                @(posedge clk) #1 stop_trans = 1'b1;
                wait (trans_stop);
                @(posedge clk) #1 stop_trans = 1'b0;
                master_en = 1'b0;
            end
        end
    endtask

    // task: read n-byte from slave
    reg [7:0] data_read;
    task read_from_slave;
        input [6:0] addr;
        input [31:0] n_byte;
        reg     ack;
        integer i;
        begin
            // initial
            master_en = 1'b0;
            start_trans = 1'b0;
            stop_trans = 1'b0;
            rd_clr = 1'b0;
            wr_rdy = 1'b0;
            byte_wr_i = 8'b0;
            i = 0;
            // enable
            @(posedge clk) #1 master_en = 1'b1;
            // start
            @(posedge clk) #1 start_trans = 1'b1;
            wait (trans_start);
            @(posedge clk) #1 start_trans = 1'b0;
            // address
            wait (wr_reg_empty);
            @(posedge clk) #1 byte_wr_i = {addr, 1'b1};
            wr_rdy = 1'b1;
            @(posedge clk) #1 wr_rdy = 1'b0;
            // data
            wait (get_nack || addr_match);
            if (get_nack) begin
                @(posedge clk) #1 stop_trans = 1'b1;
                wait (trans_stop);
                @(posedge clk) #1 stop_trans = 1'b0;
                master_en = 1'b0;
            end
            else if (addr_match) begin
                for (i = 0; i < n_byte; i = i + 1) begin
                    wait (rd_reg_full);
                    @(posedge clk) #1 data_read = byte_rd_o;
                    rd_clr = 1'b1;
                    @(posedge clk) #1 rd_clr = 1'b0;
                    if (i == (n_byte - 1)) begin
                        @(posedge clk) #1 stop_trans = 1'b1;
                    end
                end
                // stop
                wait (trans_stop);
                #1 stop_trans = 1'b0;
                master_en = 1'b0;
            end
        end
    endtask

    // task: insert write error
    task insert_wr_err;
        input [2:0] byte_pos;
        input [2:0] bit_pos;
        integer i;
        begin
            i = 0;
            m_sda = 1'b1;
            repeat (72)
            @(negedge scl) begin
                if (i == (byte_pos * 9 + bit_pos)) begin
                    #1 m_sda = 1'b0;
                end
                else begin
                    #1 m_sda = 1'b1;
                end
                i = i + 1;
            end
        end
    endtask

    // test module
    integer test_cnt;
    integer err_cnt;
    initial begin
        test_cnt  = 0;
        err_cnt   = 0;
        master_en = 0;
        #clk_period master_en = 1;

        $display("\n******************** module test started *******************\n");
        m_sda = 1'b1;
        // wrong address
        fork
            write_to_slave(7'b010_0101, 1);
            slave_wrong_addr;
            slave_get_stop;
        join
        #(clk_period * 1000);
        // write to slave
        fork
            write_to_slave(7'b010_0101, 4);
            slave_correct_addr;
            slave_get_stop;
        join
        #(clk_period * 1000);
        // read from slave
        fork
            read_from_slave(7'b010_0101, 4);
            slave_correct_addr;
            slave_get_stop;
        join
        #(clk_period * 1000);
        // write to slave, lost arbitration when addressing
        fork
            write_to_slave(7'b010_0101, 4);
            // insert_wr_err(3'd0, 3'd4);
            slave_correct_addr;
            slave_get_stop;
        join
        #(clk_period * 1000);
        // write to slave, lost arbitration after addressing
        fork
            write_to_slave(7'b010_0101, 4);
            insert_wr_err(3'd1, 3'd4);
            slave_correct_addr;
            slave_get_stop;
        join

        #10000 $display("------------------------------------------------------------");
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
