module I2C_master_read_bit (input clock,
                            input reset_n,
                            input go,          // enable signal for module
                            output reg data,   // data read from I2C bus
                            output reg finish, // indicates completion of reading
                            output reg error,  // indicates an error during reading
                            output reg scl,
                            input sda);
    
    // 3-bit counter for driving the FSM
    reg [2:0] counter;  // current counter value
    wire counter_en;    // enable signal for counter
    // generate enable signal for counter
    assign counter_en = go && (~finish);
    // counter
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 3'b000;
        end
        else if (counter_en) begin
            if (counter == 3'b111)
                counter <= 3'b000;
            else
                counter <= counter + 1'b1;
        end
        else begin
            counter <= 3'b000;
        end
    end
    
    // output
    // master device controls scl during reading, combinational circuit
    always @(*) begin
        if (!reset_n)
            scl = 1'b1;
        else if (counter_en)
            case(counter)
                3'b000, 3'b001, 3'b010, 3'b011:
                scl = 1'b0;
                3'b100, 3'b101, 3'b110, 3'b111:
                scl = 1'b1;
            endcase
        else
            scl = 1'b1;
    end
    
    // sample sda, sequential circuit
    // each bit is divided 8 parts, x means no sample, s means sample
    // +--------------+-----+---+---+---+---+---+---+---+---+
    // | set value    | scl | 0   0   0   0 | 1   1   1   1 |
    // | sample value | sda | x   x   x   x | s   s   s   s |
    // +--------------+-----+---+---+---+---+---+---+---+---+
    reg [2:0] sample_value; // add up the 4 sample values
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n)
            sample_value <= 3'b000;
        else
            case(counter)
                3'b000, 3'b001, 3'b010, 3'b011:
                sample_value <= 3'b000;
                3'b100, 3'b101, 3'b110, 3'b111:
                sample_value <= sample_value + sda;
            endcase
    end
    
    // generate data, error and finish, sequential circuit
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            finish <= 1'b0;
            data   <= 1'b0;
            error  <= 1'b0;
        end
        else if (counter == 3'b111) begin
            finish <= 1'b1;
            case(sample_value)
                3'b000, 3'b001: begin
                    data  <= 1'b0;
                    error <= 1'b0;
                end
                3'b011, 3'b100: begin
                    data  <= 1'b1;
                    error <= 1'b0;
                end
                default: begin
                    data  <= 1'b0;
                    error <= 1'b1;
                end
            endcase
        end
        else begin
            finish <= 1'b0;
            data   <= 1'b0;
            error  <= 1'b0;
        end
    end
    
endmodule
