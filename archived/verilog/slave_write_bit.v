module I2C_slave_write_bit (
    input clk,
    input rst_n,
    input bit_write_en,  // enable, expected to be high at or after scl falling edge
    input bit_write_i,  // 1-bit data write to I2C bus
    output bit_write_finish,
    input scl_i,
    output reg sda_o
);

    // detect scl_i falling and rising edge
    reg scl_last;
    wire scl_rise, scl_fall;
    // save scl_i last state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_last <= 1'b1;
        end
        else begin
            scl_last <= scl_i;
        end
    end
    // scl_i falling edge: 1 -> 0
    assign scl_fall = scl_last && (~scl_i);
    // scl_i rising edge: 0 -> 1
    assign scl_rise = (~scl_last) && scl_i;

    // track whether module has been enabled to prevent unexpected finish flag
    reg enabled;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled <= 1'b0;
        end
        else if (bit_write_en) begin
            enabled <= 1'b1;
        end
        else if ((~bit_write_en) || scl_fall) begin
            enabled <= 1'b0;
        end
        else begin
            enabled <= enabled;
        end
    end

    // sda_o, write once at bit_write_en high and scl_i low
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_o <= 1'b1;
        end
        else if (bit_write_en && (~scl_i)) begin
            sda_o <= bit_write_i;
        end
        else begin
            sda_o <= sda_o;
        end
    end

    // bit_write_finish, the second falling edge of scl_i after module enabled
    assign bit_write_finish = enabled && scl_fall;

endmodule
