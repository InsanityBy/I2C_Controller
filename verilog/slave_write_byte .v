module I2C_slave_write_byte (
           input clock,
           input reset_n,
           input enable,    // enable signal, expected to be a pulse at scl falling edge
           input [7:0] data,// data write to I2C bus
           output finish,   // finish signal
           input scl,
           output sda);

// instantiate I2C_slave_write_bit
wire write_bit_enable, write_bit_data, write_bit_finish;
I2C_slave_write_bit write_bit(
                        .clock(clock),
                        .reset_n(reset_n),
                        .enable(write_bit_enable),
                        .data(write_bit_data),
                        .finish(write_bit_finish),
                        .scl(scl),
                        .sda(sda)
                    );

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

// 3-bit counter for writing 1-byte data bit by bit
reg [2: 0] counter;
always @(posedge clock or negedge reset_n ) begin
    if (!reset_n) begin
        counter <= 3'b000;
    end
    else if(write_bit_finish) begin
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

// load data to shift register
reg [7:0] shift_register;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        shift_register <= 8'b0000_0000;
    end
    else if ((~enabled) && scl_falling_edge) begin
        shift_register <= data;
    end
    else if (write_bit_finish) begin
        shift_register <= {shift_register[6:0], 1'b0};
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
    else if (enable && (~scl)) begin
        enabled <= 1'b1;
    end
    else if((counter == 3'b111) && write_bit_finish) begin
        enabled <= 1'b0;
    end
    else begin
        enabled <= enabled;
    end
end

// generate write_bit_enable
// first bit is enabled by enable signal, others are enabled by scl falling edge
assign write_bit_enable = enable || (scl_falling_edge && enabled);

// generate write_bit_data
assign write_bit_data = shift_register[7];

// generate finish
assign finish = write_bit_finish && (counter == 3'b111);

endmodule
