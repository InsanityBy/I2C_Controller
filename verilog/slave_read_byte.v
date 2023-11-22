module I2C_slave_read_byte (
           input clock,
           input reset_n,
           input go,              // enable signal for module
           output reg data,       // data read from I2C bus
           output reg load,       // drive shifter to save data bit by bit
           output reg finish,     // indicates completion of reading
           output reg error,      // indicates an error during reading
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

// 3-bit counter for driving the FSM, only increase 1 after reading 1 bit
reg [2: 0] counter;  // current counter value
wire counter_en;    // enable signal for counter
wire counter_hold;  // hold counter value
// generate enable and hold signal for counter
assign counter_en = go && (~finish);
assign counter_hold = ~finish;
// counter
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        counter <= 3'b000;
        finish <= 1'b0;
        data <= 1'b0;
        load <= 1'b0;
    end
    else if (counter_en) begin
        if (scl_rising && scl) begin
            if(counter == 3'b111) begin
                counter <= 3'b000;
                finish <= 1'b1;
            end
            else begin
                counter <= counter + 1;
                finish <= 1'b0;
            end
            data <= sda;
            load <= 1'b1;
        end
        else begin
            counter <= counter;
            finish <= 1'b0;
            data <= data;
            load <= 1'b0;
        end
    end
    else begin
        counter <= 3'b000;
        finish <= 1'b0;
        data <= 1'b0;
        load <= 1'b0;
    end
end

endmodule
