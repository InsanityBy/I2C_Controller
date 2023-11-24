module I2C_slave_read_bit(
           input clock,
           input reset_n,
           input go,              // enable signal for module
           output reg data,       // data read from I2C bus
           output reg finish,     // indicates completion of reading
           input scl,
           input sda);

// detect scl rising edge
reg [1: 0] scl_state;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        scl_state <= 2'b00;
    end
    else begin
        scl_state <= {scl_state[0], scl};
    end
end
reg scl_rising; // indicates rising edge of scl
always @(*) begin
    if(scl_state == 2'b01)
        scl_rising = 1'b1;
    else
        scl_rising = 1'b0;
end

// output
always @(*) begin
    if (go && scl_rising && scl) begin
        data <= sda;
        finish <= 1'b1;
    end
    else begin
        data <= 1'b0;
        finish <= 1'b0;
    end
end

endmodule
