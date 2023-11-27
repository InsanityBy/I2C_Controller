module I2C_slave_read_bit(
           input clock,
           input reset_n,
           input enable,    // enable signal, expected to be a pulse at scl rising edge
           output reg data, // data read from I2C bus
           output reg error,// error signal
           output finish,   // finish signal
           input scl,
           input sda);

// detect scl rising edge
reg scl_last_state;
wire scl_rising_edge;
// save scl last state
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        scl_last_state <= 1'b1;
    end
    else begin
        scl_last_state <= scl;
    end
end
// scl rising edge: 0 -> 1
assign scl_rising_edge = (~scl_last_state) && scl;

// generate data output, read once at enable high and scl high
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        data <= 1'b0;
    end
    else if (enable && scl) begin
        data <= sda;
    end
    else begin
        data <= data;
    end
end

// generate error output, check whether sda changed during scl high
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        error <= 1'b0;
    end
    else if (scl && (data != sda)) begin
        error <= 1'b1;
    end
    else begin
        error <= error;
    end
end

// track whether module has been enabled to prevent unexpected finish flag
reg enabled;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        enabled <= 1'b0;
    end
    else if (enable && scl) begin
        enabled <= 1'b1;
    end
    else if(scl_rising_edge) begin
        enabled <= 1'b0;
    end
    else begin
        enabled <= enabled;
    end
end

// generate finish flag
assign finish = enabled && scl_rising_edge;

endmodule
