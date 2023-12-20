/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: I2C_write.v
 * create date: 2023.12.12
 * last modified date: 2023.12.21
 *
 * design name: I2C_controller
 * module name: I2C_write
 * description:
 *     module for writing 1-bit or 1-byte data, supports both master and slave
 *     module for writing start or stop condition(master only)
 * dependencies:
 *     (none)
 *
 * revision:
 * V1.0 - 2023.12.17
 *     initial version
 * V1.1 - 2023.12.17
 *     feature: support both master and slave
 * V1.2 - 2023.12.21
 *     fix: timing issues
 */

module I2C_write (
    // clock and reset
    input clk,
    input rst_n,
    // control
    input wr_en,  // expected to be enabled after scl falling edge
    input is_data,  // 1 for writing data, 0 for writing command
    input is_byte,  // 1 for writing 1-byte, 0 for writing 1-bit
    output reg wr_ld,  // drive external data shift register
    // data and command
    input command_i,  // 1 for start, 0 for stop
    input data_i,  // data write to sda
    output reg data_o,  // actual data on I2C sda
    // status
    output reg get_start,  // start condition detected
    output reg get_stop,  // stop condition detected
    output reg bus_err,  // 1 for start or stop condition at wrong bit
    output reg wr_err,  // 1 for data on sda different from data written
    output reg wr_finish,  // finish writing data
    // I2C
    input scl_i,  // must be synchronized external
    input sda_i,  // must be synchronized external
    output reg sda_o
);

    // detect scl falling and rising edge
    reg scl_last, scl_fall, scl_rise;
    // save scl last value, sequential circuit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_last <= 1'b1;
        end
        else begin
            scl_last <= scl_i;
        end
    end
    // detect scl falling and rising edge when enabled, combinational circuit
    always @(*) begin
        scl_fall = wr_en && scl_last && (~scl_i);
        scl_rise = wr_en && (~scl_last) && scl_i;
    end

    // detect start and stop condition (sda changes during scl high)
    reg sda_last;
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
        get_start = wr_en && scl_i && sda_last && (~sda_i);
        get_stop  = wr_en && scl_i && (~sda_last) && sda_i;
    end

    // counter for writing 1-byte data bit by bit, sequential circuit
    reg [2:0] bit_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 3'b000;
        end
        else if (!wr_en) begin  // reset when disabled
            bit_cnt <= 3'b000;
        end
        else if (scl_fall) begin  // add when enabled and scl falls
            if (is_data && is_byte) begin  // write 1-byte data
                if (bit_cnt == 3'b111) begin
                    bit_cnt <= 3'b000;
                end
                else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end
            else begin  // write 1-bit data or command
                bit_cnt <= 3'b000;
            end
        end
        else begin
            bit_cnt <= bit_cnt;
        end
    end

    // write data or command, sequential circuit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_o <= 1'b1;
        end
        else if (!wr_en) begin
            sda_o <= 1'b1;
        end
        else if (!scl_i) begin
            if (is_data) begin  // write data
                sda_o <= data_i;
            end
            else begin  // write command
                if (command_i) begin  // start: prepare to fall when scl high
                    sda_o <= 1'b1;
                end
                else begin  // stop: prepare to rise when scl high
                    sda_o <= 1'b0;
                end
            end
        end
        else begin
            if (is_data) begin
                sda_o <= sda_o;
            end
            else begin
                if (command_i) begin  // start: sda falls when scl high
                    sda_o <= 1'b0;
                end
                else begin  // stop: sda rises when scl high
                    sda_o <= 1'b1;
                end
            end
        end
    end

    // save data_i to compare
    reg data_i_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_i_reg <= 1'b0;
        end
        else if (wr_ld) begin
            data_i_reg <= data_i;
        end
        else begin
            data_i_reg <= data_i_reg;
        end
    end

    // read actual data on sda
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_o <= 1'b0;
        end
        else if (wr_en && is_data && scl_i) begin
            data_o <= sda_i;
        end
        else begin
            data_o <= data_o;
        end
    end

    // load
    always @(*) begin
        wr_ld = wr_en && scl_rise;
    end

    // bus error
    always @(*) begin
        bus_err = wr_en && is_data && (get_start || get_stop);
    end

    // write error, check when last data finish
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_err <= 1'b0;
        end
        else if (!wr_en) begin  // reset when disabled
            wr_err <= 1'b0;
        end
        else if (is_data && scl_fall && (data_o != data_i_reg)) begin
            wr_err <= 1'b1;
        end
        else begin
            wr_err <= wr_err;
        end
    end

    // finish, sequential circuit to avoid glitch
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_finish <= 1'b0;
        end
        else if (!wr_en) begin  // reset when disabled
            wr_finish <= 1'b0;
        end
        else if (is_data && is_byte) begin
            if ((bit_cnt == 3'b111) && scl_fall) begin
                wr_finish <= 1'b1;
            end
            else begin
                wr_finish <= 1'b0;
            end
        end
        else begin
            if ((bit_cnt == 3'b000) && scl_fall) begin
                wr_finish <= 1'b1;
            end
            else begin
                wr_finish <= 1'b0;
            end
        end
    end

endmodule
