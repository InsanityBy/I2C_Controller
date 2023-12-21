/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: I2C_master.v
 * create date: 2023.11.23
 * last modified date: 2023.12.21
 *
 * design name: I2C_controller
 * module name: I2C_master
 * description:
 *     top level module of I2C master
 * dependencies:
 *     I2C_read.v
 *     I2C_write.v
 *     scl_generator.v
 *
 * revision:
 * V1.0 - 2023.11.23
 *     initial version
 * V2.0 - 2023.12.18
 *     refactor: change the logic of finite state machine to use new submodules
 *     feature: add more control and status signals
 *              add clock stretch
 *              add arbitration
 *              add registers to write next or read previous byte while current transmit
 * V2.1 - 2023.12.21
 *     fix: timing and logic issues
 * V2.2 - 2023.12.21
 *     refactor: move setting scl_div external
 */

module I2C_master (
    input clk,
    input rst_n,
    // control
    input master_en,
    input [7:0] scl_div,  // 1~255, f_{scl_o} = f_{clk}/(2*(scl_div+1))
    input start_trans,  // restart after current transmission
    input stop_trans,  // stop after current transmission
    input rd_clr,  // data in output register has been read
    input wr_rdy,  // data has been written to input register
    output reg rd_reg_full,  // output register is full to read
    output reg wr_reg_empty,  // input register is empty to write
    // address and data
    input [7:0] byte_wr_i,  // 1-byte data write to I2C bus
    output reg [7:0] byte_rd_o,  // 1-byte data read from I2C bus
    // status
    output reg trans_start,  // finish writing start condition, start transmit
    output reg addr_match,  // 1 for addressing slave successfully
    output reg trans_dir,  // transmit direction, 1 for reading, 0 for writing
    output reg get_nack,  // 1 for NACK, 0 for ACK
    output reg trans_stop,  // finish writing stop condition, stop transmit
    output reg bus_err,  // receive start or stop condition at wrong place
    output reg byte_wait,  // 1 for data wait to be read or written to continue
    output reg arbit_fail,  // arbitration fail
    // I2C
    input scl_i,  // must be synchronized external
    output scl_o,
    input sda_i,  // must be synchronized external
    output sda_o
);
    // instantiate submodule to generate scl
    reg scl_en, scl_wait;
    wire scl_stretched;
    scl_generator U_master_scl (
        .clk          (clk),
        .rst_n        (rst_n),
        .scl_en       (scl_en),
        .scl_wait     (scl_wait),
        .scl_div      (scl_div),
        .scl_stretched(scl_stretched),
        .scl_i        (scl_i),
        .scl_o        (scl_o)
    );

    // instantiate submodule to read
    reg rd_en, rd_is_byte;
    wire rd_ld, rd_data_o, rd_get_start, rd_get_stop, rd_bus_err, rd_finish;
    I2C_read U_master_read (
        .clk      (clk),
        .rst_n    (rst_n),
        .rd_en    (rd_en),
        .is_byte  (rd_is_byte),
        .rd_ld    (rd_ld),
        .data_o   (rd_data_o),
        .get_start(rd_get_start),
        .get_stop (rd_get_stop),
        .bus_err  (rd_bus_err),
        .rd_finish(rd_finish),
        .scl_i    (scl_i),
        .sda_i    (sda_i)
    );

    // instantiate submodule to write
    reg wr_en, wr_is_data, wr_is_byte, wr_data_i, wr_command_i;
    wire wr_ld, wr_data_o, wr_get_start, wr_get_stop, wr_bus_err, wr_err, wr_finish;
    I2C_write U_master_write (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (wr_en),
        .is_data  (wr_is_data),
        .is_byte  (wr_is_byte),
        .wr_ld    (wr_ld),
        .command_i(wr_command_i),
        .data_i   (wr_data_i),
        .data_o   (wr_data_o),
        .get_start(wr_get_start),
        .get_stop (wr_get_stop),
        .bus_err  (wr_bus_err),
        .wr_err   (wr_err),
        .wr_finish(wr_finish),
        .scl_i    (scl_i),
        .sda_i    (sda_i),
        .sda_o    (sda_o)
    );

    // data shift register
    reg [7:0] rd_shifter, wr_shifter;
    // copy data from shift register to output register
    reg rd_copy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_reg_full <= 1'b0;
            rd_shifter  <= 8'b0;
            byte_rd_o   <= 8'b0;
        end
        else if (!master_en) begin
            rd_reg_full <= 1'b0;
            rd_shifter  <= 8'b0;
            byte_rd_o   <= 8'b0;
        end
        else if (rd_copy) begin  // shifter -> reg
            rd_reg_full <= 1'b1;
            rd_shifter  <= rd_shifter;
            byte_rd_o   <= rd_shifter;
        end
        else if (rd_clr) begin  // reg -> output
            rd_reg_full <= 1'b0;
            rd_shifter  <= rd_shifter;
            byte_rd_o   <= byte_rd_o;
        end
        else if (rd_ld) begin
            rd_shifter <= {rd_shifter[6:0], rd_data_o};
        end
        else begin
            rd_reg_full <= rd_reg_full;
            rd_shifter  <= rd_shifter;
            byte_rd_o   <= byte_rd_o;
        end
    end
    // copy data from input register to shift register
    reg [7:0] byte_wr_reg;
    reg       wr_copy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_reg_empty <= 1'b1;
            wr_shifter   <= 8'b0;
            byte_wr_reg  <= 8'b0;
        end
        else if ((~master_en) || trans_start || trans_stop) begin
            wr_reg_empty <= 1'b1;
            wr_shifter   <= 8'b0;
            byte_wr_reg  <= 8'b0;
        end
        else if (wr_rdy) begin  // input -> reg
            wr_reg_empty <= 1'b0;
            wr_shifter   <= wr_shifter;
            byte_wr_reg  <= byte_wr_i;
        end
        else if (wr_copy) begin  // reg -> shifter
            wr_reg_empty <= 1'b1;
            wr_shifter   <= byte_wr_reg;
            byte_wr_reg  <= byte_wr_reg;
        end
        else if (wr_ld) begin
            wr_shifter <= {wr_shifter[6:0], 1'b0};
        end
        else begin
            wr_reg_empty <= wr_reg_empty;
            wr_shifter   <= wr_shifter;
            byte_wr_reg  <= byte_wr_reg;
        end
    end

    // connect to I2C_write module, combinational circuit
    reg wr_bit;
    always @(*) begin
        if (wr_is_byte) begin
            wr_data_i = wr_shifter[7];
        end
        else begin
            wr_data_i = wr_bit;
        end
    end

    // finite state machine
    // state encode
    parameter IDLE = 14'h0000;
    parameter START = 14'h0001;
    parameter WAIT_ADDRESS = 14'h0002;
    parameter LOAD_ADDRESS = 14'h0004;
    parameter ADDRESS = 14'h0008;
    parameter ADDRESS_ACK = 14'h0010;
    parameter READ_DATA = 14'h0020;
    parameter WRITE_ACK = 14'h0040;
    parameter WRITE_NACK = 14'h0080;
    parameter WAIT_READ = 14'h0100;
    parameter WAIT_WRITE = 14'h0200;
    parameter WRITE_DATA = 14'h0400;
    parameter CHECK_ACK = 14'h0800;
    parameter WAIT = 14'h1000;
    parameter STOP = 14'h2000;

    // state variable
    reg [13:0] state_next;
    reg [13:0] state_current;

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
                if (master_en) begin
                    state_next = START;
                end
                else begin
                    state_next = IDLE;
                end
            end
            START: begin
                if (!wr_finish) begin
                    state_next = START;
                end
                else begin
                    state_next = WAIT_ADDRESS;
                end
            end
            WAIT_ADDRESS: begin  // scl low
                if (!wr_reg_empty) begin
                    state_next = LOAD_ADDRESS;
                end
                else begin
                    state_next = WAIT_ADDRESS;
                end
            end
            LOAD_ADDRESS: begin
                state_next = ADDRESS;
            end
            ADDRESS: begin
                if (wr_bus_err || wr_err) begin  // lost arbitration
                    state_next = IDLE;
                end
                else if (!wr_finish) begin
                    state_next = ADDRESS;
                end
                else begin
                    state_next = ADDRESS_ACK;
                end
            end
            ADDRESS_ACK: begin
                if (rd_bus_err) begin
                    state_next = IDLE;
                end
                else if (!rd_finish) begin
                    state_next = ADDRESS_ACK;
                end
                else if (get_nack) begin
                    state_next = WAIT;
                end
                else if (trans_dir) begin
                    state_next = READ_DATA;
                end
                else begin
                    state_next = WAIT_WRITE;
                end
            end
            READ_DATA: begin
                if (rd_bus_err) begin
                    state_next = IDLE;
                end
                else if (!rd_finish) begin
                    state_next = READ_DATA;
                end
                else if (start_trans || stop_trans) begin
                    state_next = WRITE_NACK;
                end
                else begin
                    state_next = WRITE_ACK;
                end
            end
            WRITE_ACK: begin  // sda low, bus error won't happen
                if (!wr_finish) begin
                    state_next = WRITE_ACK;
                end
                else if (!rd_reg_full) begin
                    state_next = READ_DATA;
                end
                else begin
                    state_next = WAIT_READ;
                end
            end
            WRITE_NACK: begin
                if (!wr_finish) begin
                    state_next = WRITE_NACK;
                end
                else if (start_trans) begin
                    state_next = START;
                end
                else if (stop_trans) begin
                    state_next = STOP;
                end
                else begin
                    state_next = WAIT;
                end
            end
            WAIT_READ: begin  // scl low, bus error won't happen
                if (!rd_reg_full) begin
                    state_next = READ_DATA;
                end
                else begin
                    state_next = WAIT_READ;
                end
            end
            WAIT_WRITE: begin  // scl low, bus error won't happen
                if (start_trans) begin
                    state_next = START;
                end
                else if (stop_trans) begin
                    state_next = STOP;
                end
                else if (!wr_reg_empty) begin
                    state_next = WRITE_DATA;
                end
                else begin
                    state_next = WAIT_WRITE;
                end
            end
            WRITE_DATA: begin
                if (wr_bus_err || wr_err) begin  // lost arbitration
                    state_next = IDLE;
                end
                else if (!wr_finish) begin
                    state_next = WRITE_DATA;
                end
                else begin
                    state_next = CHECK_ACK;
                end
            end
            CHECK_ACK: begin
                if (rd_bus_err) begin
                    state_next = IDLE;
                end
                else if (!rd_finish) begin
                    state_next = CHECK_ACK;
                end
                else if (get_nack) begin
                    state_next = WAIT;
                end
                else if (!wr_reg_empty) begin
                    state_next = WRITE_DATA;
                end
                else begin
                    state_next = WAIT_WRITE;
                end
            end
            WAIT: begin
                if (start_trans) begin
                    state_next = START;
                end
                else if (stop_trans) begin
                    state_next = STOP;
                end
                else begin
                    state_next = WAIT;
                end
            end
            STOP: begin
                if (!wr_finish) begin
                    state_next = STOP;
                end
                else begin
                    state_next = IDLE;
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
            IDLE, WAIT_ADDRESS, LOAD_ADDRESS, WAIT_READ, WAIT_WRITE, WAIT: begin
                {rd_en, rd_is_byte, wr_en, wr_is_data, wr_is_byte} = 5'b00_000;
                wr_command_i = 1'b0;
                wr_bit = 1'b0;
            end
            START: begin
                {rd_en, rd_is_byte, wr_en, wr_is_data, wr_is_byte} = 5'b00_100;
                wr_command_i = 1'b1;
                wr_bit = 1'b0;
            end
            ADDRESS, WRITE_DATA: begin
                {rd_en, rd_is_byte, wr_en, wr_is_data, wr_is_byte} = 5'b00_111;
                wr_command_i = 1'b0;
                wr_bit = 1'b0;
            end
            ADDRESS_ACK, CHECK_ACK: begin
                {rd_en, rd_is_byte, wr_en, wr_is_data, wr_is_byte} = 5'b10_000;
                wr_command_i = 1'b0;
                wr_bit = 1'b0;
            end
            READ_DATA: begin
                {rd_en, rd_is_byte, wr_en, wr_is_data, wr_is_byte} = 5'b11_000;
                wr_command_i = 1'b0;
                wr_bit = 1'b0;
            end
            WRITE_ACK: begin
                {rd_en, rd_is_byte, wr_en, wr_is_data, wr_is_byte} = 5'b00_110;
                wr_command_i = 1'b0;
                wr_bit = 1'b0;
            end
            WRITE_NACK: begin
                {rd_en, rd_is_byte, wr_en, wr_is_data, wr_is_byte} = 5'b00_110;
                wr_command_i = 1'b0;
                wr_bit = 1'b1;
            end
            STOP: begin
                {rd_en, rd_is_byte, wr_en, wr_is_data, wr_is_byte} = 5'b00_100;
                wr_command_i = 1'b0;
                wr_bit = 1'b0;
            end
            default: begin
                {rd_en, rd_is_byte, wr_en, wr_is_data, wr_is_byte} = 5'b00_000;
                wr_command_i = 1'b0;
                wr_bit = 1'b0;
            end
        endcase
    end

    // copy from register
    always @(*) begin
        if (((state_current == WRITE_ACK) && wr_finish)
            || (state_current == WAIT_READ)) begin
            if (!rd_reg_full) begin
                rd_copy = 1'b1;
            end
            else begin
                rd_copy = 1'b0;
            end
        end
        else begin
            rd_copy = 1'b0;
        end
    end

    // copy to register
    always @(*) begin
        if (((state_current == CHECK_ACK) && rd_finish && (~get_nack))
            || (state_current == WAIT_WRITE)
            || (state_current == WAIT_ADDRESS)) begin
            if (!wr_reg_empty) begin
                wr_copy = 1'b1;
            end
            else begin
                wr_copy = 1'b0;
            end
        end
        else if (state_current == LOAD_ADDRESS) begin
            wr_copy = 1'b1;
        end
        else begin
            wr_copy = 1'b0;
        end
    end

    // status
    // transmit start
    always @(*) begin
        if ((state_current == START) && wr_finish) begin
            trans_start = 1'b1;
        end
        else begin
            trans_start = 1'b0;
        end
    end

    // address match
    always @(*) begin
        if ((state_current == ADDRESS_ACK) && rd_finish && (~get_nack)) begin
            addr_match = 1'b1;
        end
        else begin
            addr_match = 1'b0;
        end
    end

    // transmit direction, 1 for reading, 0 for writing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trans_dir <= 1'b0;
        end
        // reset when disabled/start/stop
        else if ((~master_en) || trans_start || trans_stop) begin
            trans_dir <= 1'b0;
        end
        else if (state_current == LOAD_ADDRESS) begin
            trans_dir <= wr_shifter[0];
        end
        else begin
            trans_dir <= trans_dir;
        end
    end

    // get NACK
    always @(*) begin
        if (((state_current == CHECK_ACK) || (state_current == ADDRESS_ACK))
            && rd_finish) begin
            if (rd_shifter[0]) begin
                get_nack = 1'b1;
            end
            else begin
                get_nack = 1'b0;
            end
        end
        else begin
            get_nack = 1'b0;
        end
    end

    // transmit stop
    always @(*) begin
        if ((state_current == STOP) && wr_finish) begin
            trans_stop = 1'b1;
        end
        else begin
            trans_stop = 1'b0;
        end
    end

    // bus error, start or stop condition at wrong place
    always @(*) begin
        bus_err = wr_bus_err || rd_bus_err;
    end

    // byte wait to be read or written
    always @(*) begin
        if ((state_current == WAIT_READ)
        || (state_current == WAIT_WRITE)
        || (state_current == WAIT_ADDRESS)) begin
            byte_wait = 1'b1;
        end
        else begin
            byte_wait = 1'b0;
        end
    end

    // arbitration fail
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arbit_fail <= 1'b0;
        end
        else if (!master_en) begin  // reset when disabled
            arbit_fail <= 1'b0;
        end
        else if (wr_err) begin
            arbit_fail <= 1'b1;
        end
        else begin
            arbit_fail <= arbit_fail;
        end
    end

    // scl enable
    always @(*) begin
        scl_en = master_en;
    end

    // stretch scl
    always @(*) begin
        if ((state_current == WAIT_READ)
        || (state_current == WAIT_WRITE)
        || (state_current == WAIT_ADDRESS)
        || (state_current == LOAD_ADDRESS)) begin
            scl_wait = 1'b1;
        end
        else begin
            scl_wait = 1'b0;
        end
    end

endmodule
