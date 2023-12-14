/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: I2C_slave_read.v
 * create date: 2023.12.11
 * last modified date: 2023.12.14
 *
 * design name: I2C_controller
 * module name: I2C_slave_read
 * description:
 *     combine slave_read_bit and slave_read_byte, and add more control and status signals
 * dependencies:
 *     (none)
 *
 * revision:
 * V1.0 - 2023.12.14
 *     initial version
 */

module I2C_slave_read (
    // clock and reset
    input clk,
    input rst_n,
    // control
    input rd_en,  // enable, expected to be high 1 clock after scl falling edge
    input is_byte,  // 1 for reading 1-byte, 0 for 1-bit
    output reg rd_ld,  // drive external data shift register
    // data
    output reg data_o,
    // status
    output reg rd_finish,  // finish reading data
    output reg get_start,  // start condition detected
    output reg get_stop,  // stop condition detected
    output reg rd_err,  // 1 for sda changes during scl high (except first bit of byte)
    // I2C
    input scl_i,
    input sda_i
);

    // detect scl falling edge
    reg scl_last, scl_fall;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_last <= 1'b1;
            scl_fall <= 1'b0;
        end
        else if (!rd_en) begin  // stop detecting and reset when disabled
            scl_last <= scl_i;
            scl_fall <= 1'b0;
        end
        else begin
            scl_last <= scl_i;
            scl_fall <= scl_last && (~scl_i);
        end
    end

    // detect start and stop condition (sda changes during scl high)
    reg sda_last;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_last  <= 1'b1;
            get_start <= 1'b0;
            get_stop  <= 1'b0;
        end
        else if (!rd_en) begin  // stop detecting and reset when disabled
            sda_last  <= sda_i;
            get_start <= 1'b0;
            get_stop  <= 1'b0;
        end
        else if (scl_i) begin  // detect when scl high
            sda_last  <= sda_i;
            get_start <= scl_last && sda_last && (~sda_i);
            get_stop  <= scl_last && (~sda_last) && sda_i;
        end
        else begin
            sda_last  <= sda_i;
            get_start <= 1'b0;
            get_stop  <= 1'b0;
        end
    end

    // counter for reading data bit by bit
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

    // read data
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

    // finish
    always @(*) begin
        if (!rd_en) begin
            rd_finish = 1'b0;
        end
        else if (!is_byte) begin
            if ((bit_cnt == 3'b000) && scl_fall) begin
                rd_finish = 1'b1;
            end
            else begin
                rd_finish = 1'b0;
            end
        end
        else begin
            if ((bit_cnt == 3'b111) && scl_fall) begin
                rd_finish = 1'b1;
            end
            else begin
                rd_finish = 1'b0;
            end
        end
    end

    // error
    always @(*) begin
        if (!rd_en) begin  // reset when disabled
            rd_err = 1'b0;
        end
        else if (get_start || get_stop) begin
            // start or stop conditions at first bit of byte is correct
            if (is_byte && (bit_cnt == 3'b000)) begin
                rd_err = 1'b0;
            end
            else begin
                rd_err = 1'b1;
            end
        end
        else begin
            rd_err = 1'b0;
        end
    end

endmodule
