module I2C_master_write_bit (input clock,
                             input reset_n,
                             input go,
                             input [2:0] command,
                             output reg finish,
                             output reg scl,
                             output reg sda);
    
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
    
    // command for different write operation
    parameter IDLE      = 3'b000;
    parameter START_BIT = 3'b010;
    parameter STOP_BIT  = 3'b011;
    parameter DATA_0    = 3'b100;
    parameter DATA_1    = 3'b101;
    parameter ACK_BIT   = 3'b110;
    parameter NACK_BIT  = 3'b111;
    
    
    // output, sequential circuit to handle race and hazard
    // according to protocol divide each kind bit into 8 parts
    // +-----------+-----+---+---+---+---+---+---+---+---+
    // | START_BIT | scl | 1   1   1   1 | 1   1   1   1 |
    // |           | sda | 1   1   1   1 | 1   1   0   0 |
    // +-----------+-----+---+---+---+---+---+---+---+---+
    // | STOP_BIT  | scl | 0   0   0   0 | 1   1   1   1 |
    // |           | sda | x   0   0   0 | 0   0   1   1 |
    // +-----------+-----+---+---+---+---+---+---+---+---+
    // | DATA_0    | scl | 0   0   0   0 | 1   1   1   1 |
    // |           | sda | x   0   0   0 | 0   0   0   0 |
    // +-----------+-----+---+---+---+---+---+---+---+---+
    // | DATA_1    | scl | 0   0   0   0 | 1   1   1   1 |
    // |           | sda | x   1   1   1 | 1   1   1   1 |
    // +-----------+-----+---+---+---+---+---+---+---+---+
    // | ACK_BIT   | scl | 0   0   0   0 | 1   1   1   1 |
    // |           | sda | x   0   0   0 | 0   0   0   0 |
    // +-----------+-----+---+---+---+---+---+---+---+---+
    // | NACK_BIT  | scl | 0   0   0   0 | 1   1   1   1 |
    // |           | sda | x   1   1   1 | 1   1   1   1 |
    // +-----------+-----+---+---+---+---+---+---+---+---+
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            {scl, sda} <= 2'b11;
            finish     <= 1'b0;
        end
        else begin
            case(counter)
                3'b000: begin
                    finish <= 1'b0;
                    case(command)
                        START_BIT: begin
                            {scl, sda} <= 2'b11;
                        end
                        STOP_BIT, DATA_0, DATA_1, ACK_BIT, NACK_BIT: begin
                            scl <= 1'b0;
                            sda <= sda;
                        end
                        default: begin
                            {scl, sda} <= {scl, sda};
                        end
                    endcase
                end
                3'b001, 3'b010, 3'b011: begin
                    finish <= 1'b0;
                    case(command)
                        START_BIT: begin
                            {scl, sda} <= 2'b11;
                        end
                        STOP_BIT, DATA_0, ACK_BIT: begin
                            {scl, sda} <= 2'b00;
                        end
                        DATA_1, NACK_BIT: begin
                            {scl, sda} <= 2'b01;
                        end
                        default: begin
                            {scl, sda} <= {scl, sda};
                        end
                    endcase
                end
                3'b100, 3'b101: begin
                    finish = 1'b0;
                    case(command)
                        START_BIT, DATA_1, NACK_BIT: begin
                            {scl, sda} <= 2'b11;
                        end
                        STOP_BIT, DATA_0, ACK_BIT: begin
                            {scl, sda} <= 2'b10;
                        end
                        default: begin
                            {scl, sda} <= {scl, sda};
                        end
                    endcase
                end
                3'b110: begin
                    finish <= 1'b0;
                    case(command)
                        START_BIT, DATA_0, ACK_BIT: begin
                            {scl, sda} <= 2'b10;
                        end
                        STOP_BIT, DATA_1, NACK_BIT: begin
                            {scl, sda} <= 2'b11;
                        end
                        default: begin
                            {scl, sda} <= {scl, sda};
                        end
                    endcase
                end
                3'b111: begin
                    finish <= 1'b1;
                    case(command)
                        START_BIT, DATA_0, ACK_BIT: begin
                            {scl, sda} <= 2'b10;
                        end
                        STOP_BIT, DATA_1, NACK_BIT: begin
                            {scl, sda} <= 2'b11;
                        end
                        default: begin
                            {scl, sda} <= {scl, sda};
                        end
                    endcase
                end
            endcase
        end
    end
endmodule
