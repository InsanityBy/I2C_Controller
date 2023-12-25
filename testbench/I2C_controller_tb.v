`timescale 1ns / 10ps

module testbench ();
    // use fsdb/vcd or vcd to save wave
`ifdef fsdbdump
    initial begin
        $display("\n**************** fsdb file dump is turned on ***************");
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0);
        #10000000 $fsdbDumpoff;
        $finish;
    end
`endif
`ifdef vcddump
    initial begin
        $display("\n**************** vcd file dump is turned on ****************");
        $dumpfile("wave.vcd");
        $dumpvars(0);
        #10000000 $dumpoff;
    end
`endif

    // test parameters
    parameter test_round = 32;
    parameter scl_div = 32;
    parameter clk_period = 40;
    parameter local_addr = 7'b110_1010;
    parameter scl_period = clk_period * scl_div;

    // signals
    reg clk, rst_n;

    reg enable, rd_clr, wr_rdy, start_trans, stop_trans;
    wire scl_div_cur, rd_reg_full, wr_reg_empty;
    wire [6:0] local_addr_cur;
    reg  [7:0] byte_wr_i;
    wire [7:0] byte_rd_o;
    wire bus_busy, is_master, trans_start, addr_match, trans_dir,
        get_nack, trans_stop, bus_err, byte_wait, arbit_fail;
    reg scl, sda;
    reg m_scl, m_sda, s_sda, e_sda;
    wire scl_o, sda_o;

    // instantiate the module under test
    I2C_controller test_module (
        .clk           (clk),
        .rst_n         (rst_n),
        // control
        .enable        (enable),
        .set_scl_div   (scl_div),
        .scl_div       (scl_div_cur),
        .start_trans   (start_trans),
        .stop_trans    (stop_trans),
        .rd_clr        (rd_clr),
        .wr_rdy        (wr_rdy),
        .rd_reg_full   (rd_reg_full),
        .wr_reg_empty  (wr_reg_empty),
        // address and data
        .set_local_addr(local_addr),
        .local_addr    (local_addr_cur),
        .byte_wr_i     (byte_wr_i),
        .byte_rd_o     (byte_rd_o),
        // status
        .bus_busy      (bus_busy),
        .is_master     (is_master),
        .trans_start   (trans_start),
        .addr_match    (addr_match),
        .trans_dir     (trans_dir),
        .get_nack      (get_nack),
        .bus_err       (bus_err),
        .byte_wait     (byte_wait),
        .arbit_fail    (arbit_fail),
        .trans_stop    (trans_stop),
        // I2C
        .scl_i         (scl),
        .scl_o         (scl_o),
        .sda_i         (sda),
        .sda_o         (sda_o)
    );

    // sda and scl
    always @(*) begin
        scl = scl_o && m_scl;
        sda = sda_o && m_sda && s_sda && e_sda;
    end

    // generate clock and reset
    initial begin
        clk   = 1'b0;
        forever #(clk_period / 2) clk = ~clk;
    end
    initial begin
        rst_n = 1'b1;
        #clk_period #1 rst_n = 1'b0;
        #clk_period #1 rst_n = 1'b1;
    end
    // generate m_scl
    reg     m_scl_en;
    integer scl_cnt;
    initial begin
        m_scl_en = 1'b0;
    end
    always @(posedge clk) begin
        if (!m_scl_en) begin
            m_scl   <= #1 1'b1;
            scl_cnt <= 0;
        end
        else if (m_scl != scl) begin
            m_scl   <= m_scl;
            scl_cnt <= scl_cnt;
        end
        else if (scl_cnt == (scl_div / 2 - 1)) begin
            m_scl   <= #1 1'b0;
            scl_cnt <= scl_cnt + 1;
        end
        else if (scl_cnt == (scl_div - 1)) begin
            m_scl   <= #1 1'b1;
            scl_cnt <= 0;
        end
        else begin
            m_scl   <= m_scl;
            scl_cnt <= scl_cnt + 1;
        end
    end

    // task: write start
    task m_write_start;
        integer i;
        begin
            m_sda = 1'b1;
            #(scl_period / 2 + 1) m_sda = 1'b0;
            m_scl_en = 1'b1;
        end
    endtask

    // task: write stop
    task m_write_stop;
        begin
            wait (~scl);
            #(scl_period / 4 + 1) m_sda = 1'b0;
            wait (scl);
            #(scl_period / 4 + 1) m_sda = 1'b1;
            m_scl_en = 1'b0;
        end
    endtask

    // task: write data
    task m_write_data;
        input is_byte;
        input [7:0] data;
        integer i;
        begin
            i = 0;
            if (is_byte) begin
                repeat (8)
                @(negedge scl) begin
                    #1 m_sda = data[7-i];
                    i = i + 1;
                end
            end
            else begin
                @(negedge scl) #1 m_sda = data[0];
            end
        end
    endtask

    // task: read data
    task m_read_data;
        input is_byte;
        output reg [7:0] data;
        integer i;
        begin
            i = 0;
            if (is_byte) begin
                repeat (8)
                @(posedge scl) begin
                    #1 data[7-i] = sda;
                    i = i + 1;
                end
            end
            else begin
                @(posedge scl) #1 data[0] = sda;
            end
        end
    endtask

    // task: write n-byte to slave
    reg [7:0] data_written;
    task m_write_to_slave;
        input [6:0] addr;
        input [31:0] n_byte;
        reg     ack;
        integer i;
        begin
            m_scl = 1'b1;
            m_sda = 1'b1;
            i = 0;
            #clk_period;
            // start
            m_write_start;
            // address
            m_write_data(1'b1, {addr, 1'b0});
            // check ack
            @(negedge scl) #1 m_sda = 1'b1;  // release sda
            m_read_data(1'b0, ack);
            if (ack) begin
                m_write_stop;
            end
            else begin
                // write data
                for (i = 0; i < n_byte; i = i + 1) begin
                    data_written = $random % 256;
                    m_write_data(1'b1, data_written);
                    // check ack
                    @(negedge scl) #1 m_sda = 1'b1;  // release sda
                    m_read_data(1'b0, ack);
                    if (ack) begin
                        m_write_stop;
                        disable m_write_to_slave;
                    end
                end
                // stop
                m_write_stop;
            end
        end
    endtask

    // task: read n-byte from slave
    reg [7:0] data_read;
    task m_read_from_slave;
        input [6:0] addr;
        input [31:0] n_byte;
        reg     ack;
        integer i;
        begin
            m_scl = 1'b1;
            m_sda = 1'b1;
            i = 0;
            #clk_period;
            // start
            m_write_start;
            // address
            m_write_data(1'b1, {addr, 1'b1});
            // check ack
            @(negedge scl) #1 m_sda = 1'b1;  // release sda
            m_read_data(1'b0, ack);
            if (ack) begin
                m_write_stop;
            end
            else begin
                // read data
                for (i = 0; i < n_byte; i = i + 1) begin
                    m_read_data(1'b1, data_read);
                    // write ack
                    if (i == (n_byte - 1)) begin
                        m_write_data(1'b0, 8'h01);
                    end
                    else begin
                        m_write_data(1'b0, 8'h00);
                    end
                    @(negedge scl) #1 m_sda = 1;  // release sda
                end
                // stop
                m_write_stop;
            end
        end
    endtask
    // simulate slave
    // task: simulate slave detect start and stop
    reg sda_reg, get_start, get_stop;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_reg <= #1 1'b1;
        end
        else begin
            sda_reg <= #1 sda;
        end
    end
    always @(*) begin
        get_start = scl && sda_reg && (~sda);
        get_stop  = scl && (~sda_reg) && sda;
    end
    task s_get_start;
        begin
            wait (get_start);
            wait (~get_start);
        end
    endtask
    task s_get_stop;
        begin
            wait (get_stop);
            wait (~get_stop);
            disable s_correct_addr;
            disable s_wrong_addr;
        end
    endtask

    // task: simulate slave write data and check ack
    task s_write_data;
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
    task s_read_data;
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
    task s_wrong_addr;
        reg [7:0] data;
        begin
            s_sda = 1'b1;
            // start
            s_get_start;
            //address
            s_read_data(1'b1, data);
        end
    endtask

    task s_correct_addr;
        reg [7:0] data_read, data_write;
        reg ack;
        begin
            s_sda = 1'b1;
            // start
            s_get_start;
            //address
            s_read_data(1'b0, data_read);
            // data
            if (data_read[0]) begin  // write to master
                while (1) begin
                    data_write = $random % 256;
                    s_write_data(data_write, ack);
                    if (ack) begin
                        #1 s_sda = 1'b1;
                        disable s_correct_addr;
                    end
                end
            end
            else begin  // get from master
                while (1) begin
                    @(negedge scl) #1 s_sda = 1'b1;  // release sda
                    s_read_data(1'b0, data_read);
                end
            end
        end
    endtask

    // control test module
    // task: write n-byte to slave
    task write_to_slave;
        input [6:0] addr;
        input [31:0] n_byte;
        reg     ack;
        integer i;
        begin
            // initial
            start_trans = 1'b0;
            stop_trans = 1'b0;
            rd_clr = 1'b0;
            wr_rdy = 1'b0;
            byte_wr_i = 8'b0;
            i = 0;
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
            end
            else if (addr_match) begin
                for (i = 0; i < n_byte; i = i + 1) begin
                    data_written = $random % 256;
                    wait (wr_reg_empty);
                    @(posedge clk) #1 byte_wr_i = data_written;
                    wr_rdy = 1'b1;
                    @(posedge clk) #5 wr_rdy = 1'b0;
                end
                // stop
                wait (byte_wait);
                @(posedge clk) #1 stop_trans = 1'b1;
                wait (trans_stop);
                @(posedge clk) #1 stop_trans = 1'b0;
            end
        end
    endtask

    // task: read n-byte from slave
    task read_from_slave;
        input [6:0] addr;
        input [31:0] n_byte;
        reg     ack;
        integer i;
        begin
            // initial
            start_trans = 1'b0;
            stop_trans = 1'b0;
            rd_clr = 1'b0;
            wr_rdy = 1'b0;
            byte_wr_i = 8'b0;
            i = 0;
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
            end
            else if (addr_match) begin
                for (i = 0; i < n_byte; i = i + 1) begin
                    wait (rd_reg_full);
                    @(posedge clk) #1 data_read = byte_rd_o;
                    rd_clr = 1'b1;
                    @(posedge clk) #5 rd_clr = 1'b0;
                    if (i == (n_byte - 2)) begin
                        @(posedge clk) #1 stop_trans = 1'b1;
                    end
                end
                // stop
                wait (trans_stop);
                #1 stop_trans = 1'b0;
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
            e_sda = 1'b1;
            repeat (72)
            @(negedge scl) begin
                if (i == (byte_pos * 9 + bit_pos)) begin
                    #1 e_sda = 1'b0;
                    disable insert_wr_err;
                end
                else begin
                    #1 e_sda = 1'b1;
                end
                i = i + 1;
            end
        end
    endtask

    // task: insert bus error
    task insert_bus_err_0;
        input [2:0] byte_pos;
        input [2:0] bit_pos;
        integer i;
        begin
            i = 0;
            e_sda = 1'b1;
            repeat (72)
            @(negedge scl) begin
                if (i == (byte_pos * 9 + bit_pos)) begin
                    #1 e_sda = 1'b0;
                    @(posedge scl) #(scl_period / 4 + 1) e_sda = 1'b1;
                    disable insert_bus_err_0;
                end
                else begin
                    #1 e_sda = 1'b1;
                end
                i = i + 1;
            end
        end
    endtask
    task insert_bus_err_1;
        input [2:0] byte_pos;
        input [2:0] bit_pos;
        integer i;
        begin
            i = 0;
            e_sda = 1'b1;
            repeat (72)
            @(negedge scl) begin
                if (i == (byte_pos * 9 + bit_pos)) begin
                    #1 e_sda = 1'b1;
                    @(posedge scl) #(scl_period / 4 + 1) e_sda = 1'b0;
                    disable insert_bus_err_1;
                end
                else begin
                    #1 e_sda = 1'b1;
                end
                i = i + 1;
            end
        end
    endtask

    // control test module
    reg [7:0] slave_read, slave_write;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_clr <= #1 1'b0;
            slave_read <= #1 8'b0;
        end
        else if (!is_master) begin
            if ((~trans_dir) && rd_reg_full) begin
                rd_clr <= #1 1'b1;
                slave_read <= #1 byte_rd_o;
            end
            else begin
                rd_clr <= #1 1'b0;
                slave_read <= #1 slave_read;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_rdy <= #1 1'b0;
            slave_write <= #1 ($random % 256);
            byte_wr_i <= #1 8'b0;
        end
        else if (!is_master) begin
            if (trans_dir && wr_reg_empty) begin
                wr_rdy <= #1 1'b1;
                slave_write <= #1 ($random % 256);
                byte_wr_i <= #1 slave_write;
            end
            else begin
                wr_rdy <= #1 1'b0;
                slave_write <= #1 slave_write;
                byte_wr_i <= #1 byte_wr_i;
            end
        end
    end

    // test module
    integer test_cnt;
    integer err_cnt;
    initial begin
        enable = 0;
        start_trans = 1'b0;
        stop_trans = 1'b0;
        s_sda = 1'b1;
        m_sda = 1'b1;
        e_sda = 1'b1;
        #(clk_period * 8 + 1) enable = 1;

        $display("\n******************** module test started *******************\n");
        // wrong address
        m_write_to_slave((~local_addr), 1);
        #(scl_period + 1);

        // write
        m_write_to_slave(local_addr, 1);
        #(scl_period + 1);
        m_write_to_slave(local_addr, 4);
        #(scl_period + 1);
        // // write with bus error
        // fork
        //     m_write_to_slave(local_addr, 4);
        //     insert_bus_err_0(1, 3);
        //     e_sda = 1'b1;
        // join
        // #(scl_period + 1);
        // fork
        //     m_write_to_slave(local_addr, 4);
        //     insert_bus_err_1(2, 3);
        //     e_sda = 1'b1;
        // join
        // #(scl_period + 1);

        // read
        m_read_from_slave(local_addr, 1);
        #(scl_period + 1);
        m_read_from_slave(local_addr, 4);
        #(scl_period + 1);
        // // read with bus error
        // fork
        //     m_read_from_slave(local_addr, 4);
        //     insert_bus_err_0(1, 4);
        //     e_sda = 1'b1;
        // join
        // #(scl_period + 1);
        // // read with bus error
        // fork
        //     m_read_from_slave(local_addr, 4);
        //     insert_bus_err_1(2, 3);
        //     e_sda = 1'b1;
        // join
        // #(scl_period + 1);

        // wrong address
        fork
            write_to_slave(7'b010_0101, 1);
            s_wrong_addr;
            s_get_stop;
        join
        #(scl_period + 1);
        // write to slave
        fork
            write_to_slave(7'b010_0101, 4);
            s_correct_addr;
            s_get_stop;
        join
        #(scl_period + 1);
        // // write with bus error
        // fork
        //     write_to_slave(7'b010_0101, 4);
        //     insert_bus_err_0(1, 4);
        //     e_sda = 1'b1;
        // join
        // #(clk_period * 1000);
        // fork
        //     write_to_slave(7'b010_0101, 4);
        //     insert_bus_err_1(2, 5);
        //     e_sda = 1'b1;
        // join
        // #(clk_period * 1000);
        // read from slave
        fork
            read_from_slave(7'b010_0101, 4);
            s_correct_addr;
            s_get_stop;
        join
        #(scl_period + 1);
        // // read with bus error
        // fork
        //     read_from_slave(7'b010_0101, 4);
        //     insert_bus_err_0(1, 4);
        //     e_sda = 1'b1;
        // join
        // #(clk_period * 1000);
        // fork
        //     read_from_slave(7'b010_0101, 4);
        //     insert_bus_err_1(2, 5);
        //     e_sda = 1'b1;
        // join
        // #(clk_period * 1000);
        // write to slave, lost arbitration when addressing
        fork
            write_to_slave(7'b010_0101, 4);
            insert_wr_err(3'd0, 3'd4);
            s_correct_addr;
            s_get_stop;
        join
        #(scl_period + 1);
        // write to slave, lost arbitration after addressing
        fork
            write_to_slave(7'b010_0101, 4);
            insert_wr_err(3'd1, 3'd4);
            s_correct_addr;
            s_get_stop;
        join
        #(scl_period + 1);
        $display("------------------------------------------------------------");
        // result
        $display("\n******************* module test finished *******************\n");
        $finish;
    end

endmodule
