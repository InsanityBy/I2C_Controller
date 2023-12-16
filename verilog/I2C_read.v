/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: I2C_read.v
 * create date: 2023.12.11
 * last modified date: 2023.12.17
 *
 * design name: I2C_controller
 * module name: I2C_read
 * description:
 *     module for reading 1-bit or 1-byte data, supports both master and slave
 * dependencies:
 *     (none)
 *
 * revision:
 * V1.0 - 2023.12.14
 *     initial version
 * V1.1 - 2023.12.17
 *     fix: timing issues of signals
 * V1.2 - 2023.12.17
 *     feature: support both master and slave
 */

module I2C_read (
    // clock and reset
    input clk,
    input rst_n,
    // control
    input rd_en,  // expected to be enabled after scl falling edge
    input is_byte,  // 1 for reading 1-byte, 0 for 1-bit
    output reg rd_ld,  // drive external data shift register
    // data
    output reg data_o,  // data read from sda
    // status
    output reg get_start,  // start condition detected
    output reg get_stop,  // stop condition detected
    output reg bus_err,  // 1 for start or stop condition at wrong bit
    output reg rd_finish,  // finish reading data
    // I2C
    input scl_i,  // must be synchronized external
    input sda_i  // must be synchronized external
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
        scl_fall = rd_en && scl_last && (~scl_i);
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
        get_start = rd_en && scl_i && sda_last && (~sda_i);
        get_stop  = rd_en && scl_i && (~sda_last) && sda_i;
    end

    // counter for reading data bit by bit, sequential circuit
    reg [2:0] bit_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 3'b000;
        end
        else if (!rd_en) begin  // reset when disabled
            bit_cnt <= 3'b000;
        end
        else if (scl_fall) begin  // add when enabled and scl falls
            if (!is_byte) begin  // read 1-bit data
                bit_cnt <= 3'b000;
            end
            else begin  // read 1-byte data
                if (bit_cnt == 3'b111) begin
                    bit_cnt <= 3'b000;
                end
                else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end
        end
        else begin
            bit_cnt <= bit_cnt;
        end
    end

    // read data, sequential circuit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_o <= 1'b0;
        end
        else if (rd_en && scl_i) begin
            data_o <= sda_i;
        end
        else begin
            data_o <= data_o;
        end
    end

    // load
    always @(*) begin
        rd_ld = rd_en && scl_fall;
    end

    // bus error, start or stop conditions at wrong bit
    always @(*) begin
        if (!rd_en) begin  // reset when disabled
            bus_err = 1'b0;
        end
        else if (get_start || get_stop) begin
            // start or stop conditions at first bit of byte is correct
            if (is_byte && (bit_cnt == 3'b000)) begin
                bus_err = 1'b0;
            end
            else begin
                bus_err = 1'b1;
            end
        end
        else begin
            bus_err = 1'b0;
        end
    end

    // finish, sequential circuit to avoid glitch
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_finish <= 1'b0;
        end
        if (!rd_en) begin  // reset when disabled
            rd_finish <= 1'b0;
        end
        else if (!is_byte) begin
            if ((bit_cnt == 3'b000) && scl_fall) begin
                rd_finish <= 1'b1;
            end
            else begin
                rd_finish <= rd_finish;
            end
        end
        else begin
            if ((bit_cnt == 3'b111) && scl_fall) begin
                rd_finish <= 1'b1;
            end
            else begin
                rd_finish <= rd_finish;
            end
        end
    end

endmodule
