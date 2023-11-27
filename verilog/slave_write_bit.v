module I2C_slave_write_bit (
           input clock,
           input reset_n,
           input enable,    // enable signal, expected to be a pulse at scl falling edge
           input data,      // data write to I2C bus
           output finish,   // finish signal
           input scl,
           output reg sda);

// detect scl falling edge
reg scl_last_state;
wire scl_falling_edge;
// save scl last state
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        scl_last_state <= 1'b1;
    end
    else begin
        scl_last_state <= scl;
    end
end
// scl falling edge: 1 -> 0
assign scl_falling_edge = scl_last_state && (~scl);

// generate sda output, write once at enable high and scl low
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        sda <= 1'b1;
    end
    else if (enable && (~scl)) begin
        sda <= data;
    end
    else begin
        sda <= sda;
    end
end

// track whether module has been enabled to prevent unexpected finish flag
reg enabled;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        enabled <= 1'b0;
    end
    else if (enable && (~scl)) begin
        enabled <= 1'b1;
    end
    else if(scl_falling_edge) begin
        enabled <= 1'b0;
    end
    else begin
        enabled <= enabled;
    end
end

// generate finish flag
assign finish = enabled && scl_falling_edge;

endmodule
