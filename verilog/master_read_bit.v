module I2C_master_read_bit (input clock,
                            input reset_n,
                            input go,
                            output reg data,
                            output reg finish,
                            output reg error,
                            input sda,
                            output reg scl);
    
    // 3-bit counter: drive the finite state machine
    reg [2:0] counter;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n)
            counter <= 3'b000;
        else if ((go == 1'b1) && (finish == 1'b0)) begin
            if (counter == 3'b111)
                counter <= 3'b000;
            else
                counter <= counter + 1'b1;
        end
        else
            counter <= 3'b000;
    end
    
    // output, sequential circuit to handle race and hazard
    // each bit is divided 8 parts, x means no sample, s means sample
    // +--------------+-----+---+---+---+---+---+---+---+---+
    // | set value    | scl | 0   0   0   0 | 1   1   1   1 |
    // | sample value | sda | x   x   x   x | s   s   s   s |
    // +--------------+-----+---+---+---+---+---+---+---+---+
    reg [2:0] sample_value;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            data  <= 1'b0;
            error <= 1'b0;
        end
        else if (counter == 3'b111) begin
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
            end
            always @(posedge clock or negedge reset_n) begin
                if (!reset_n) begin
                    scl          <= 1'b1;
                    sample_value <= 4'b0000;
                    finish       <= 1'b0;
                end
                else begin
                    case(counter)
                        3'b000, 3'b001, 3'b010, 3'b011: begin
                            scl          <= 1'b0;
                            sample_value <= 4'b0000;
                            finish       <= 1'b0;
                        end
                        3'b100, 3'b101, 3'b110: begin
                            scl          <= 1'b1;
                            sample_value <= sample_value + sda;
                            finish       <= 1'b0;
                        end
                        3'b111: begin
                            scl          <= 1'b1;
                            sample_value <= sample_value + sda;
                            finish = 1'b1;
                        end
                    endcase
                end
            end
            endmodule
