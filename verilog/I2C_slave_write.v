/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: I2C_slave_write.v
 * create date: 2023.12.12
 * last modified date: 2023.12.17
 *
 * design name: I2C_controller
 * module name: I2C_slave_write
 * description:
 *     combine slave_write_bit and slave_write_byte, and add more control and status signals
 * dependencies:
 *     (none)
 *
 * revision:
 * V1.0 - 2023.12.17
 *     initial version
 */

module I2C_slave_write (
    // clock and reset
    input clk,
    input rst_n,
    // control
    input wr_en,  // expected to be enabled after scl falling edge
    input is_byte,  // 1 for writing 1-byte, 0 for writing 1-bit
    output reg wr_ld,  // drive external data shift register
    // data
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
            if (!is_byte) begin  // write 1-bit data
                bit_cnt <= 3'b000;
            end
            else begin  // write 1-byte data
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

    // write data, sequential circuit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_o <= 1'b1;
        end
        else if (!wr_en) begin
            sda_o <= 1'b1;
        end
        else if (!scl_i) begin
            sda_o <= data_i;
        end
        else begin
            sda_o <= sda_o;
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
        else if (wr_en && scl_i) begin
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
        bus_err = wr_en && (get_start || get_stop);
    end

    // write error, check when last data finish
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_err <= 1'b0;
        end
        else if (!wr_en) begin  // reset when disabled
            wr_err <= 1'b0;
        end
        else if (scl_fall && (data_o != data_i_reg)) begin
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
        if (!wr_en) begin  // reset when disabled
            wr_finish <= 1'b0;
        end
        else if (!is_byte) begin
            if ((bit_cnt == 3'b000) && scl_fall) begin
                wr_finish <= 1'b1;
            end
            else begin
                wr_finish <= wr_finish;
            end
        end
        else begin
            if ((bit_cnt == 3'b111) && scl_fall) begin
                wr_finish <= 1'b1;
            end
            else begin
                wr_finish <= wr_finish;
            end
        end
    end

endmodule
