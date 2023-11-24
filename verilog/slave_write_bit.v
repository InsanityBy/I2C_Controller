module I2C_slave_write_bit (
           input clock,
           input reset_n,
           input go,            // enable signal for module
           input data,          // data write to I2C bus
           output reg finish,   // indicates completion of writing
           input scl,
           output reg sda);

// detect scl falling edge
reg [1: 0] scl_state;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        scl_state <= 2'b00;
    end
    else begin
        scl_state <= {scl_state[0], scl};
    end
end
reg scl_falling; // indicates falling edge of scl
always @(*) begin
    if(scl_state == 2'b10)
        scl_falling = 1'b1;
    else
        scl_falling = 1'b0;
end

// output
always @(*) begin
    if (!reset_n) begin
        sda = 1'b1;
        finish = 1'b0;
    end
    if (go && scl_falling &&(~scl)) begin
        sda = data;
        finish = 1'b1;
    end
    else begin
        sda = sda;
        finish = 1'b0;
    end
end

endmodule
