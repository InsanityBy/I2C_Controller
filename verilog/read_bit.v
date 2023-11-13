module I2C_read_bit (
    // signal to control module
    input [2:0] command,
    input       clock,
    input       reset_n,
    input       go,
    output reg  finish,
    // signal to control I2C
    input       scl,
                sda
);

// detect start bit
reg start_bit;
always @(negedge sda) begin
    if(scl)
        start_bit = 1'b1;
    else
        start_bit = 1'b0;
end
endmodule