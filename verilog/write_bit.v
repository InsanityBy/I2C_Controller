module I2C_write_bit (
    // signal to control module
    input [2:0] command,
    input       clock,
    input       reset_n,
    input       go,
    output reg  finish,
    // signal to control I2C
    output reg  scl,
                sda
);

// 3-bit counter: when leave IDLE start counting
reg [2:0] counter;
always @(posedge clock ) begin
    if((go == 1'b1) && (finish == 1'b0)) begin
        if(counter == 3'b111)
            counter <= 3'b000;
        else
            counter <= counter + 1'b1;
    end
    else
        counter <= 3'b000;
end

// state and command
parameter IDLE = 3'b000;
parameter START_BIT = 3'b010;
parameter STOP_BIT = 3'b011;
parameter DATA_0 = 3'b100;
parameter DATA_1 = 3'b101;
parameter ACK_BIT = 3'b110;
parameter NACK_BIT = 3'b111;

// state varibele
reg [2:0] state_next;
reg [2:0] state_current;

// state transfer, sequential
always @(posedge clock or negedge reset_n) begin
    // reset, transfer to IDLE state
    if(!reset_n)
        state_current <= IDLE;
    else
        state_current <= state_next;
end

// state switch, combination
always @(*) begin
    case(state_current)
        IDLE:
            begin
                if((go == 1'b1) && (finish == 1'b0))
                    case(command)
                        START_BIT: state_next = START_BIT;
                        STOP_BIT: state_next = STOP_BIT;
                        DATA_0: state_next = DATA_0;
                        DATA_1: state_next = DATA_1;
                        ACK_BIT: state_next = ACK_BIT;
                        NACK_BIT: state_next = NACK_BIT;
                        default: state_next = IDLE;
                    endcase
                else
                    state_next = IDLE;
            end
        START_BIT, STOP_BIT, DATA_0, DATA_1, ACK_BIT, NACK_BIT:
            begin
                if(counter == 3'b100)
                    state_next = IDLE;
                else
                    state_next = state_current;
            end
        default: state_next = IDLE;
    endcase
end

// output
always @(*) begin
    if(!reset_n) begin
        scl = 1'b1;
        sda = 1'b1;
        finish = 1'b0;
    end
    else begin
        case(state_current)
            IDLE:
                begin
                    finish = 1'b0;
                end
            START_BIT:
                case(counter)
                    3'b001, 3'b010, 3'b011:
                        {scl, sda} = 2'b11;
                    3'b100: begin
                        {scl, sda} = 2'b10;
                        finish = 1'b1;
                    end
                endcase
            STOP_BIT:
                case(counter)
                    3'b001:
                        scl = 1'b0; 
                    3'b010:
                        {scl, sda} = 2'b00;
                    3'b011:
                        {scl, sda} = 2'b10;
                    3'b100: begin
                        {scl, sda} = 2'b11;
                        finish = 1'b1;
                    end
                endcase
            DATA_0:
                case(counter)
                    3'b001:
                        scl = 1'b0; 
                    3'b010:
                        {scl, sda} = 2'b00;
                    3'b011:
                        {scl, sda} = 2'b10;
                    3'b100: begin
                        {scl, sda} = 2'b10;
                        finish = 1'b1;
                    end
                endcase
            DATA_1:
                case(counter)
                    3'b001:
                        scl = 1'b0; 
                    3'b010:
                        {scl, sda} = 2'b01;
                    3'b011:
                        {scl, sda} = 2'b11;
                    3'b100: begin
                        {scl, sda} = 2'b11;
                        finish = 1'b1;
                    end
                endcase
            ACK_BIT:
                case(counter)
                    3'b001:
                        scl = 1'b0; 
                    3'b010:
                        {scl, sda} = 2'b00;
                    3'b011:
                        {scl, sda} = 2'b10;
                    3'b100: begin
                        {scl, sda} = 2'b10;
                        finish = 1'b1;
                    end
                endcase
            NACK_BIT:
                case(counter)
                    3'b001:
                        scl = 1'b0; 
                    3'b010:
                        {scl, sda} = 2'b01;
                    3'b011:
                        {scl, sda} = 2'b11;
                    3'b100: begin
                        {scl, sda} = 2'b11;
                        finish = 1'b1;
                    end
                endcase
        endcase
    end
end
endmodule
