/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: I2C_slave.v
 * create date: 2023.12.02
 * last modified date: 2023.12.20
 *
 * design name: I2C_controller
 * module name: I2C_slave
 * description:
 *     top level module of I2C slave
 * dependencies:
 *     I2C_read.v
 *     I2C_write.v
 *
 * revision:
 * V1.0 - 2023.12.02
 *     initial version
 * V1.1 - 2023.12.02
 *     fix: read_enable is continuous high instead of a pulse when reading address
 * V2.0 - 2023.12.05
 *     refactor: change the logic of finite state machine
 * V2.1 - 2023.12.06
 *     fix: ack, sda_o, read_write_flag and byte_finish error
 * V3.0 - 2023.12.18
 *     refactor: change the logic of finite state machine to use new submodules
 *     feature: add more control and status signals
 *              add clock stretch
 *              add registers to write next or read previous byte while current transmit
 * V3.1 - 2023.12.20
 *     fix: timing and logic issues
 */

module I2C_slave (
    input clk,
    input rst_n,
    // control
    input slave_en,
    input rd_clr,  // data in output register has been read
    input wr_rdy,  // data has been written to input register
    output reg rd_reg_full,  // output register is full to read
    output reg wr_reg_empty,  // input register is empty to write
    // address and data
    input [6:0] local_addr,  // local address of device
    input [7:0] byte_wr_i,  // 1-byte data write to I2C bus
    output reg [7:0] byte_rd_o,  // 1-byte data read from I2C bus
    // status
    output reg addr_match,  // address received matches local address
    output reg trans_dir,  // transmit direction, 1 for reading, 0 for writing
    output reg get_nack,  // 1 for NACK, 0 for ACK
    output reg trans_stop,  // receive stop condition, stop transmit
    output reg bus_err,  // receive start or stop condition at wrong place
    output reg byte_wait,  // 1 for data wait to be read or written to continue
    // I2C
    input scl_i,  // must be synchronized external
    output reg scl_o,
    input sda_i,  // must be synchronized external
    output sda_o
);

    // instantiate submodule to read
    reg rd_en, rd_is_byte;
    wire rd_ld, rd_data_o, rd_get_start, rd_get_stop, rd_bus_err, rd_finish;
    I2C_read U_slave_read (
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
    reg wr_en, wr_is_byte, wr_data_i;
    wire wr_ld, wr_data_o, wr_get_start, wr_get_stop, wr_bus_err, wr_err, wr_finish;
    I2C_write U_slave_write (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (wr_en),
        .is_data  (1'b1),
        .is_byte  (wr_is_byte),
        .wr_ld    (wr_ld),
        .command_i(1'b0),
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

    // detect scl falling edge
    reg scl_last, scl_fall;
    // save scl last value, sequential circuit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_last <= 1'b1;
        end
        else begin
            scl_last <= scl_i;
        end
    end
    // detect scl falling edge when enabled, combinational circuit
    always @(*) begin
        scl_fall = slave_en && scl_last && (~scl_i);
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
        get_start = slave_en && scl_i && sda_last && (~sda_i);
        get_stop  = slave_en && scl_i && (~sda_last) && sda_i;
    end

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
        else if (!slave_en) begin
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
        else if ((~slave_en) || get_start || get_stop) begin
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
    always @(*) begin
        if (wr_is_byte) begin
            wr_data_i = wr_shifter[7];
        end
        else begin
            wr_data_i = 1'b0;  // 1-bit only used to write ACK
        end
    end

    // finite state machine
    // state encode
    parameter IDLE = 10'h000;
    parameter START = 10'h001;
    parameter ADDRESS = 10'h002;
    parameter ADDRESS_ACK = 10'h004;
    parameter READ_DATA = 10'h008;
    parameter WRITE_ACK = 10'h010;
    parameter WAIT_READ = 10'h020;
    parameter WAIT_WRITE = 10'h040;
    parameter WRITE_DATA = 10'h080;
    parameter CHECK_ACK = 10'h100;
    parameter WAIT_STOP = 10'h200;

    // state variable
    reg [9:0] state_next;
    reg [9:0] state_current;

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
                if (slave_en && get_start) begin
                    state_next = START;
                end
                else begin
                    state_next = IDLE;
                end
            end
            START: begin
                if (get_start) begin
                    state_next = START;
                end
                else if (get_stop) begin
                    state_next = IDLE;
                end
                else if (scl_fall) begin
                    state_next = ADDRESS;
                end
                else begin
                    state_next = START;
                end
            end
            ADDRESS: begin
                if (rd_get_start) begin
                    state_next = START;
                end
                else if (rd_get_stop) begin
                    state_next = IDLE;
                end
                else if (!rd_finish) begin
                    state_next = ADDRESS;
                end
                else if (addr_match) begin
                    state_next = ADDRESS_ACK;
                end
                else begin
                    state_next = WAIT_STOP;
                end
            end
            ADDRESS_ACK: begin
                if (!wr_finish) begin
                    state_next = ADDRESS_ACK;
                end
                else if (trans_dir) begin
                    state_next = WAIT_WRITE;
                end
                else begin
                    state_next = READ_DATA;
                end
            end
            READ_DATA: begin
                if (rd_get_start) begin
                    state_next = START;
                end
                else if (rd_get_stop) begin
                    state_next = IDLE;
                end
                else if (!rd_finish) begin
                    state_next = READ_DATA;
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
            WAIT_READ: begin  // scl low, bus error won't happen
                if (!rd_reg_full) begin
                    state_next = READ_DATA;
                end
                else begin
                    state_next = WAIT_READ;
                end
            end
            WAIT_WRITE: begin  // scl low, bus error won't happen
                if (!wr_reg_empty) begin
                    state_next = WRITE_DATA;
                end
                else begin
                    state_next = WAIT_WRITE;
                end
            end
            WRITE_DATA: begin  // slave ignore write failure
                if (wr_get_start) begin
                    state_next = START;
                end
                else if (wr_get_stop) begin
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
                if (rd_get_start) begin
                    state_next = START;
                end
                else if (rd_get_stop) begin
                    state_next = IDLE;
                end
                else if (!rd_finish) begin
                    state_next = CHECK_ACK;
                end
                else if (get_nack) begin
                    state_next = WAIT_STOP;
                end
                else if (!wr_reg_empty) begin
                    state_next = WRITE_DATA;
                end
                else begin
                    state_next = WAIT_WRITE;
                end
            end
            WAIT_STOP: begin
                if (get_stop) begin
                    state_next = IDLE;
                end
                else begin
                    state_next = WAIT_STOP;
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
            IDLE, START, WAIT_READ, WAIT_WRITE, WAIT_STOP: begin
                {rd_en, rd_is_byte, wr_en, wr_is_byte} = 4'b00_00;
            end
            ADDRESS, READ_DATA: begin
                {rd_en, rd_is_byte, wr_en, wr_is_byte} = 4'b11_00;
            end
            ADDRESS_ACK, WRITE_ACK: begin
                {rd_en, rd_is_byte, wr_en, wr_is_byte} = 4'b00_10;
            end
            WRITE_DATA: begin
                {rd_en, rd_is_byte, wr_en, wr_is_byte} = 4'b00_11;
            end
            CHECK_ACK: begin
                {rd_en, rd_is_byte, wr_en, wr_is_byte} = 4'b10_00;
            end
            default: begin
                {rd_en, rd_is_byte, wr_en, wr_is_byte} = 4'b00_00;
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
            || (state_current == WAIT_WRITE)) begin
            if (!wr_reg_empty) begin
                wr_copy = 1'b1;
            end
            else begin
                wr_copy = 1'b0;
            end
        end
        else begin
            wr_copy = 1'b0;
        end
    end

    // status
    // address match
    always @(*) begin
        if (state_current == ADDRESS) begin
            if (rd_shifter[7:1] == local_addr) begin
                addr_match = 1'b1;
            end
            else begin
                addr_match = 1'b0;
            end
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
        else if ((~slave_en) || get_start || get_stop) begin
            trans_dir <= 1'b0;
        end
        else if (addr_match) begin
            trans_dir <= rd_shifter[0];
        end
        else begin
            trans_dir <= trans_dir;
        end
    end

    // get NACK
    always @(*) begin
        if ((state_current == CHECK_ACK) && rd_finish) begin
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
        trans_stop = get_stop;
    end

    // bus error, start or stop condition at wrong place
    always @(*) begin
        bus_err = wr_bus_err && rd_bus_err;
    end

    // byte wait to be read or written
    always @(*) begin
        if ((state_current == WAIT_READ) || (state_current == WAIT_WRITE)) begin
            byte_wait = 1'b1;
        end
        else begin
            byte_wait = 1'b0;
        end
    end

    // stretch scl
    always @(*) begin
        if ((state_current == WAIT_READ) || (state_current == WAIT_WRITE)) begin
            scl_o = 1'b0;
        end
        else begin
            scl_o = 1'b1;
        end
    end

endmodule
