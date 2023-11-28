module I2C_slave_read_byte (
           input clock,
           input reset_n,
           input enable,     // enable signal, expected to be a pulse at scl rising edge
           output [7:0] data,// data read from I2C bus
           output reg error, // error signal
           output reg finish,// finish signal
           input scl,
           input sda);

// instantiate I2C_slave_read_bit
wire read_bit_enable, read_bit_data, read_bit_finish, read_bit_error;
I2C_slave_read_bit read_bit(
                       .clock(clock),
                       .reset_n(reset_n),
                       .enable(read_bit_enable),
                       .data(read_bit_data),
                       .error(read_bit_error),
                       .finish(read_bit_finish),
                       .scl(scl),
                       .sda(sda)
                   );

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

// 3-bit counter for reading 1-byte data bit by bit
reg [2: 0] counter;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        counter <= 3'b000;
    end
    else if(read_bit_finish) begin
        if(counter == 3'b111) begin
            counter <= 3'b000;
        end
        else begin
            counter <= counter + 1;
        end
    end
    else begin
        counter <= counter;
    end
end

// save data to shift register
reg [7:0] shift_register;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        shift_register <= 8'b0000_0000;
    end
    else if (read_bit_finish) begin
        shift_register <= {shift_register[6:0], read_bit_data};
    end
    else begin
        shift_register <= shift_register;
    end
end

// track whether module has been enabled to prevent unexpected read_bit_enable
reg enabled;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        enabled <= 1'b0;
    end
    else if (enable && scl) begin
        enabled <= 1'b1;
    end
    else if((counter == 3'b111) && read_bit_finish) begin
        enabled <= 1'b0;
    end
    else begin
        enabled <= enabled;
    end
end

// generate error
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        error <= 1'b0;
    end
    else if(enabled && read_bit_error) begin
        error <= 1'b1;
    end
    else begin
        error <= error;
    end
end

// generate read_bit_enable
// first bit is enabled by enable signal, others are enabled by scl rising edge
assign read_bit_enable = enable || (scl_rising_edge && enabled);

// generate data
assign data = shift_register;

// generate finish
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        finish <= 1'b0;
    end
    else if(read_bit_finish && (counter == 3'b111)) begin
        finish <= 1'b1;
    end
    else begin
        finish <= 1'b0;
    end
end

endmodule
