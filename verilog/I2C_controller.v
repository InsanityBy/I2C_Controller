/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: I2C_controller.v
 * create date: 2023.12.12
 * last modified date: 2023.12.18
 *
 * design name: I2C_controller
 * module name: I2C_controller
 * description:
 *     top level module of I2C controller
 * dependencies:
 *     I2C_slave.v
 *     I2C_master.v
 *     reset_generator.v
 *     clock_divisor.v
 *
 * revision:
 * V1.0 - 2023.12.18
 *     initial version
 */
module I2C_controller (
    input clk,
    input rst_n,
    // control
    input enable,
    input [3:0] set_clk_div,  // 0~15, can ONLY be set when module disabled
    output [3:0] clk_div,  // current value of clk_div
    input [7:0] set_scl_div,  // 1~255, can ONLY be set when module disabled
    output [7:0] scl_div,  // current value of scl_div
    input start_trans,  // restart after current transmission(master)
    input stop_trans,  // stop after current transmission(master)
    input rd_clr,  // data in output register has been read
    input wr_rdy,  // data has been written to input register
    output reg rd_reg_full,  // output register is full to read
    output reg wr_reg_empty,  // input register is empty to write
    // address and data
    input [6:0] set_local_addr,
    output reg [6:0] local_addr,
    input [7:0] byte_wr_i,  // 1-byte data write to I2C bus
    output reg [7:0] byte_rd_o,  // 1-byte data read from I2C bus
    // status
    output reg bus_busy,  // bus status, 1 for busy, 0 for free
    output reg is_master,  // controller mode, 1 for master, 0 for slave
    output trans_start,  // write start condition, start transmit(master)
    output reg addr_match,  // address received matches(slave), address matches slave(master)
    output reg trans_dir,  // transmit direction, 1 for reading, 0 for writing
    output reg get_nack,  // 1 for NACK, 0 for ACK
    output reg bus_err,  // receive start or stop condition at wrong place
    output reg byte_wait,  // 1 for data wait to be read or written to continue
    output arbit_fail,  // arbitration fail(master)
    output reg trans_stop,  // receive stop condition, stop transmit
    //I2C
    input scl_i,
    output reg scl_o,
    input sda_i,
    output reg sda_o
);

    // instantiate submodule to generate async reset and sync release
    wire rst_sync_n;
    reset_generator U_reset (
        .clk       (clk),
        .rst_n     (rst_n),
        .rst_sync_n(rst_sync_n)
    );

    // instantiate submodule to  divide the high-speed system clock for other parts of the module
    wire clk_sys;
    clock_divisor U_clock (
        .clk_i      (clk),
        .rst_n      (rst_sync_n),
        .clk_en     (enable),
        .set_clk_div(set_clk_div),
        .clk_div    (clk_div),
        .clk_o      (clk_sys)
    );

    // instantiate slave module
    reg        slave_en;
    wire [7:0] s_byte_rd_o;
    wire s_rd_reg_full, s_wr_reg_empty;
    wire s_addr_match, s_trans_dir, s_get_nack, s_trans_stop, s_bus_err, s_byte_wait;
    wire s_scl_o, s_sda_o;
    I2C_slave U_slave (
        .clk         (clk_sys),
        .rst_n       (rst_sync_n),
        // control
        .slave_en    (slave_en),
        .rd_clr      (rd_clr),
        .wr_rdy      (wr_rdy),
        .rd_reg_full (s_rd_reg_full),
        .wr_reg_empty(s_wr_reg_empty),
        // address and data
        .local_addr  (local_addr),
        .byte_wr_i   (byte_wr_i),
        .byte_rd_o   (s_byte_rd_o),
        // status
        .addr_match  (s_addr_match),
        .trans_dir   (s_trans_dir),
        .get_nack    (s_get_nack),
        .trans_stop  (s_trans_stop),
        .bus_err     (s_bus_err),
        .byte_wait   (s_byte_wait),
        // I2C
        .scl_i       (scl_i),
        .scl_o       (s_scl_o),
        .sda_i       (sda_i),
        .sda_o       (s_sda_o)
    );

    // instantiate master module
    reg        master_en;
    wire [7:0] m_byte_rd_o;
    wire m_rd_reg_full, m_wr_reg_empty;
    wire m_addr_match, m_trans_dir, m_get_nack, m_trans_stop, m_bus_err, m_byte_wait;
    wire m_scl_o, m_sda_o;
    I2C_master u_master (
        .clk         (clk_sys),
        .rst_n       (rst_sync_n),
        // control
        .master_en   (master_en),
        .start_trans (start_trans),
        .stop_trans  (stop_trans),
        .rd_clr      (rd_clr),
        .wr_rdy      (wr_rdy),
        .rd_reg_full (m_rd_reg_full),
        .wr_reg_empty(m_wr_reg_empty),
        // address and data
        .byte_wr_i   (byte_wr_i),
        .byte_rd_o   (m_byte_rd_o),
        // status
        .trans_start (trans_start),
        .addr_match  (m_addr_match),
        .trans_dir   (m_trans_dir),
        .get_nack    (m_get_nack),
        .trans_stop  (m_trans_stop),
        .bus_err     (m_bus_err),
        .byte_wait   (m_byte_wait),
        .arbit_fail  (arbit_fail),
        // I2C
        .set_scl_div (set_scl_div),
        .scl_div     (scl_div),
        .scl_i       (scl_i),
        .scl_o       (m_scl_o),
        .sda_i       (sda_i),
        .sda_o       (m_sda_o)
    );

    // connect
    always @(*) begin
        if (is_master) begin
            byte_rd_o = m_byte_rd_o;
            rd_reg_full = m_rd_reg_full;
            wr_reg_empty = m_wr_reg_empty;
            addr_match = m_addr_match;
            trans_dir = m_trans_dir;
            get_nack = m_get_nack;
            bus_err = m_bus_err;
            byte_wait = m_byte_wait;
            trans_stop = m_trans_stop;
            scl_o = m_scl_o;
            sda_o = m_sda_o;
        end
        else begin
            byte_rd_o = s_byte_rd_o;
            rd_reg_full = s_rd_reg_full;
            wr_reg_empty = s_wr_reg_empty;
            addr_match = s_addr_match;
            trans_dir = s_trans_dir;
            get_nack = s_get_nack;
            bus_err = s_bus_err;
            byte_wait = s_byte_wait;
            trans_stop = s_trans_stop;
            scl_o = s_scl_o;
            sda_o = s_sda_o;
        end
    end

    // detect start and stop condition (sda changes during scl high)
    reg sda_last, get_start, get_stop;
    // save sda last value, sequential circuit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_last <= 1'b1;
        end
        else begin
            sda_last <= sda_i;
        end
    end
    // detect start and stop condition when enabled, combinational circuit
    always @(*) begin
        get_start = scl_i && sda_last && (~sda_i);
        get_stop  = scl_i && (~sda_last) && sda_i;
    end

    // set local address
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            local_addr <= 7'b100_1001;
        end
        else if (!enable) begin  // local_addr can ONLY be set when module disabled
            local_addr <= set_local_addr;
        end
        else begin
            local_addr <= local_addr;
        end
    end

    // finite state machine
    // state encode
    parameter IDLE = 2'b00;
    parameter SLAVE = 2'b01;
    parameter MASTER = 2'b10;

    // state variable
    reg [1:0] state_next;
    reg [1:0] state_current;

    // state transfer, sequential circuit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_current <= IDLE;
        end
        else begin
            state_current <= state_next;
        end
    end

    // state switch, combinational circuit
    always @(*) begin
        case (state_current)
            IDLE: begin
                if (!enable) begin
                    state_next = IDLE;
                end
                else begin
                    state_next = SLAVE;
                end
            end
            SLAVE: begin
                if (!enable) begin
                    state_next = IDLE;
                end
                else if ((~bus_busy) && start_trans) begin
                    state_next = MASTER;
                end
                else begin
                    state_next = SLAVE;
                end
            end
            MASTER: begin
                if (!enable) begin
                    state_next = IDLE;
                end
                else if (arbit_fail || trans_stop) begin
                    state_next = SLAVE;
                end
                else begin
                    state_next = MASTER;
                end
            end
            default: begin
                state_next = IDLE;
            end
        endcase
    end

    // control
    // submodules enable
    always @(*) begin
        case (state_current)
            IDLE: begin
                {master_en, slave_en} = 2'b00;
            end
            SLAVE: begin
                {master_en, slave_en} = 2'b01;
            end
            MASTER: begin
                {master_en, slave_en} = 2'b10;
            end
            default: begin
                {master_en, slave_en} = 2'b00;
            end
        endcase
    end

    // status
    // bus busy
    always @(posedge clk_sys or negedge rst_sync_n) begin
        if (!rst_sync_n) begin
            bus_busy <= 1'b0;
        end
        else if (get_start) begin
            bus_busy <= 1'b1;
        end
        else if (get_stop) begin
            bus_busy <= 1'b0;
        end
        else begin
            bus_busy <= bus_busy;
        end
    end

    // controller mode
    always @(*) begin
        if (state_current == MASTER) begin
            is_master = 1'b1;
        end
        else begin
            is_master = 1'b0;
        end
    end

endmodule
