module I2C_master_read_byte (input clock,
                             input reset_n,
                             input go,          // enable signal for module
                             output data,       // data read from I2C bus
                             output reg load,   // drive shifter to save data bit by bit
                             output reg finish, // indicates completion of writing
                             output reg error,  // indicates an error during reading
                             output reg scl,
                             input sda);
    
    // instantiate submodule to read 1-bit
    // reg and wire connect to submodule
    reg read_bit_go;
    wire read_bit_finish, read_bit_error;
    wire scl_w;
    
    // connect outputs of the submodule to this module's
    always @(*) begin
        scl   = scl_w;
        error = read_bit_error;
    end
    
    // instantiate submodule
    I2C_master_read_bit read_bit(
    .clock(clock),
    .reset_n(reset_n),
    .go(read_bit_go),
    .data(data),
    .finish(read_bit_finish),
    .error(read_bit_error),
    .scl(scl_w),
    .sda(sda)
    );
    
    // 3-bit counter for driving the FSM, only increase 1 after reading 1 bit
    reg [2:0] counter;  // current counter value
    wire counter_en;    // enable signal for counter
    wire counter_hold;  // hold counter value
    // generate enable and hold signal for counter
    assign counter_en   = go && (~finish) && (~read_bit_error);
    assign counter_hold = ~read_bit_finish;
    // counter
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 3'b000;
        end
        else if (counter_en) begin
            if (counter_hold) begin
                counter <= counter;
            end
            else begin
                if (counter == 3'b111)
                    counter <= 3'b000;
                else
                    counter <= counter + 1'b1;
            end
        end
        else begin
            counter <= 3'b000;
        end
    end
    
    // output
    // generate load signal to drive data shifter after reading each bit
    always @(*) begin
        load = read_bit_finish; // drive shifter to load each bit data
    end
    
    // output, combinational circuit
    always @(*) begin
        if (!reset_n) begin
            read_bit_go = 1'b0;
            finish      = 1'b0;
        end
        else if (go) begin
            read_bit_go = 1'b1;
            if (read_bit_finish && (counter == 3'b111)) begin
                finish = 1'b1;
            end
            else begin
                finish = 1'b0;
            end
        end
        else begin
            read_bit_go = 1'b0;
            finish      = 1'b0;
        end
    end
    
endmodule
