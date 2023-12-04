module I2C_slave_read_bit (
    input clk,
    input rst_n,
    input bit_read_en,  // enable, expected to be high at or after scl falling edge
    output reg bit_read_o,  // 1-bit data read from I2C bus
    output bit_read_err,
    output bit_read_finish,
    input scl_i,
    input sda_i
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

    // track whether module has been enabled to prevent unexpected finish and error flag
    reg enabled;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled <= 1'b0;
        end
        else if (bit_read_en) begin
            enabled <= 1'b1;
        end
        else if ((~bit_read_en) || scl_fall) begin
            enabled <= 1'b0;
        end
        else begin
            enabled <= enabled;
        end
    end

    // bit_read_o, read once at bit_read_en high and scl_i high
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_read_o <= 1'b0;
        end
        else if (enabled && scl_rise) begin
            bit_read_o <= sda_i;
        end
        else begin
            bit_read_o <= bit_read_o;
        end
    end

    // bit_read_err, check whether sda_i changed during scl_i high
    reg sda_last;
    // save sda_i last state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_last <= 1'b1;
        end
        else begin
            sda_last <= sda_i;
        end
    end
    assign bit_read_err = enabled && scl_i && (sda_last != sda_i);

    // bit_read_finish, the first falling edge of scl_i after module enabled
    assign bit_read_finish = enabled && scl_fall;

endmodule
