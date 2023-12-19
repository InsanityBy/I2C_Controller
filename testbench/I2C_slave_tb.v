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
    parameter scl_div = 16;
    parameter clk_period = 20;
    parameter scl_period = clk_period * scl_div;

    // signals
    reg clk, rst_n;

    reg slave_en, rd_clr, wr_rdy;
    wire rd_reg_full, wr_reg_empty;
    reg  [6:0] local_addr;
    reg  [7:0] byte_wr_i;
    wire [7:0] byte_rd_o;
    wire addr_match, trans_dir, get_nack, trans_stop, bus_err, byte_wait;
    reg scl, sda;
    reg m_scl, m_sda;
    wire scl_o, sda_o;

    // instantiate the module under test
    I2C_slave test_module (
        .clk         (clk),
        .rst_n       (rst_n),
        // control
        .slave_en    (slave_en),
        .rd_clr      (rd_clr),
        .wr_rdy      (wr_rdy),
        .rd_reg_full (rd_reg_full),
        .wr_reg_empty(wr_reg_empty),
        // address and data
        .local_addr  (local_addr),
        .byte_wr_i   (byte_wr_i),
        .byte_rd_o   (byte_rd_o),
        // status
        .addr_match  (addr_match),
        .trans_dir   (trans_dir),
        .get_nack    (get_nack),
        .trans_stop  (trans_stop),
        .bus_err     (bus_err),
        .byte_wait   (byte_wait),
        // I2C
        .scl_i       (scl),
        .scl_o       (scl_o),
        .sda_i       (sda),
        .sda_o       (sda_o)
    );

    // sda and scl
    always @(*) begin
        scl = scl_o && m_scl;
        sda = sda_o && m_sda;
    end

    // generate clock and reset
    initial begin
        clk   = 1'b0;
        rst_n = 1'b1;
        #clk_period rst_n = 1'b0;
        #clk_period rst_n = 1'b1;
        forever #(clk_period / 2) clk = ~clk;
    end

    // generate m_scl
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

    // task: write start
    task write_start;
        integer i;
        begin
            m_sda = 1'b1;
            #(scl_period / 2 + 1) m_sda = 1'b0;
            scl_en = 1'b1;
        end
    endtask

    // task: write stop
    task write_stop;
        begin
            wait (~scl);
            #(scl_period / 4 + 1) m_sda = 1'b0;
            wait (scl);
            #(scl_period / 4 + 1) m_sda = 1'b1;
            scl_en = 1'b0;
        end
    endtask

    // task: write data
    task write_data;
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
    task read_data;
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
    task write_to_slave;
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
            write_start;
            // address
            write_data(1'b1, {addr, 1'b0});
            // check ack
            @(negedge scl) m_sda = 1'b1;  // release sda
            read_data(1'b0, ack);
            if (ack) begin
                write_stop;
            end
            else begin
                // write data
                for (i = 0; i < n_byte; i = i + 1) begin
                    data_written = $random % 256;
                    write_data(1'b1, data_written);
                    // check ack
                    @(negedge scl) m_sda = 1'b1;  // release sda
                    read_data(1'b0, ack);
                    if (ack) begin
                        write_stop;
                        disable write_to_slave;
                    end
                end
                // stop
                write_stop;
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
            m_scl = 1'b1;
            m_sda = 1'b1;
            i = 0;
            #clk_period;
            // start
            write_start;
            // address
            write_data(1'b1, {addr, 1'b1});
            // check ack
            @(negedge scl) m_sda = 1'b1;  // release sda
            read_data(1'b0, ack);
            if (ack) begin
                write_stop;
            end
            else begin
                // read data
                for (i = 0; i < n_byte; i = i + 1) begin
                    read_data(1'b1, data_read);
                    // write ack
                    if (i == (n_byte - 1)) begin
                        write_data(1'b0, 8'h01);
                    end
                    else begin
                        write_data(1'b0, 8'h00);
                    end
                    @(negedge scl) #1 m_sda = 1;  // release sda
                end
                // stop
                write_stop;
            end
        end
    endtask

    // control test module
    reg [7:0] slave_read, slave_write;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_clr <= 1'b0;
            slave_read <= 8'b0;
        end
        else if ((~trans_dir) && rd_reg_full) begin
            rd_clr <= 1'b1;
            slave_read <= byte_rd_o;
        end
        else begin
            rd_clr <= 1'b0;
            slave_read <= slave_read;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_rdy <= 1'b0;
            slave_write <= ($random % 256);
            byte_wr_i <= 8'b0;
        end
        else if (trans_dir && wr_reg_empty && (~wr_rdy)) begin
            wr_rdy <= 1'b1;
            slave_write <= ($random % 256);
            byte_wr_i <= slave_write;
        end
        else begin
            wr_rdy <= 1'b0;
            slave_write <= slave_write;
            byte_wr_i <= byte_wr_i;
        end
    end

    // test module
    integer test_cnt;
    integer err_cnt;
    initial begin
        test_cnt = 0;
        err_cnt = 0;
        slave_en = 0;
        local_addr = 7'b010_0101;
        #clk_period slave_en = 1;

        $display("\n******************** module test started *******************\n");
        // wrong address
        write_to_slave((~local_addr), 1);
        #scl_period;

        // write
        write_to_slave(local_addr, 1);
        #scl_period;

        write_to_slave(local_addr, 2);
        #scl_period;

        write_to_slave(local_addr, 3);
        #scl_period;

        // read
        read_from_slave(local_addr, 1);
        #scl_period;

        read_from_slave(local_addr, 2);
        #scl_period;

        read_from_slave(local_addr, 3);
        #scl_period;

        $display("------------------------------------------------------------");
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
