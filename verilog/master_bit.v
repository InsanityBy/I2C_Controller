module I2C_master_bit (
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

// 2-bit counter: when leave IDLE start counting
reg [1:0] counter;
always @(posedge clock ) begin
    if((go == 1'b1) && (finish == 1'b0)) begin

        if(counter == 2'b11)
            counter <= 2'b00;
        else
            counter <= counter + 1'b1;
    end
    else
        counter <= 2'b00;
end

// state and command
parameter IDLE = 3'b000
parameter START_BIT = 3'b010;
parameter STOP_BIT = 3'b011;
parameter DATA_0 = 3'b100;
parameter DATA_1 = 3'b101;
parameter ACK = 3'b110;
parameter NACK = 3'b111;

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
                        ACK: state_next = ACK;
                        NACK: state_next = NACK;
                        default: state_next = IDLE;
                    endcase
                else
                    state_next = IDLE;
            end
        START_BIT, STOP_BIT, DATA_0, DATA_1, ACK, NACK:
            begin
                if(counter == 2'b11)
                    state_next = IDLE;
                else
                    state_next = state_current;
            end
        default: state_next = IDLE;
    endcase
end

always @(*) begin
    if(!reset_n) begin
        scl = 1'b1;
        sda = 1'b1;
        finish = 1'b0;
    end
    else begin
        case(state_current): 
            IDLE:
                begin
                    {scl, sda} = 2'b11;
                    finish = 1'b0;
                end
            START_BIT:
                case(counter)
                    2'b00, 2'b01, 2'b10:
                        {scl, sda} = 2'b11;
                    2'b11:
                        {scl, sda} = 2'b10;
                endcase
            STOP_BIT:
                case(counter)
                    2'b00:
                        scl = 1'b0; 
                    2'b01:
                        {scl, sda} = 2'b00;
                    2'b10:
                        {scl, sda} = 2'b10;
                    2'b11:
                        {scl, sda} = 2'b11;
                endcase
            DATA_0:
                case(counter)
                    2'b00:
                        scl = 1'b0; 
                    2'b01:
                        {scl, sda} = 2'b00;
                    2'b10, 2'b11:
                        {scl, sda} = 2'b10;
                endcase
            DATA_1:
                case(counter)
                    2'b00:
                        scl = 1'b0; 
                    2'b01:
                        {scl, sda} = 2'b01;
                    2'b10, 2'b11:
                        {scl, sda} = 2'b11;
                endcase
            ACK:
                case(counter)
                    2'b00:
                        scl = 1'b0; 
                    2'b01:
                        {scl, sda} = 2'b00;
                    2'b10, 2'b11:
                        {scl, sda} = 2'b10;
                endcase
            NACK:
                case(counter)
                    2'b00:
                        scl = 1'b0; 
                    2'b01:
                        {scl, sda} = 2'b01;
                    2'b10, 2'b11:
                        {scl, sda} = 2'b11;
                endcase
        endcase
    end
end
endmodule