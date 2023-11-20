module I2C_master_read_bit (
    // signal to control module
    input       clock,
    input       reset_n,
    input       go,
    output reg  finish,
    output reg  data,
    // signal to control I2C
    input       sda,
    output reg  scl
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

// state
parameter IDLE = 1'b0;
parameter READ_BIT = 1'b1;

// state varibele
reg       state_next;
reg       state_current;

// state transfer, sequential
always @(posedge clock or negedge reset_n) begin
    // reset, transfer to IDLE state
    if(!reset_n)
        state_current <= IDLE;
    else
        state_current <= state_next;
end

/ state switch, combination
always @(*) begin
    case(state_current)
        IDLE:
            begin
                if((go == 1'b1) && (finish == 1'b0))
                    state_next = READ_BIT;
                else
                    state_next = IDLE;
            end
        READ_BIT:
            begin
                if(counter == 4'b100)
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
        data = 1'b0;
        data_state = 2'b00;
        finish = 1'b0;
    end
    else begin
        case(state_current)
            IDLE:
                begin
                    finish = 1'b0;
                end
            READ_BIT:
                case(counter)
                    4'b0000, 4'b0001: begin
                        scl = 1'b0;
                        finish = 1'b0;
                    end
                    4'b0010: begin
                        scl = 1'b1;
                        finish = 1'b0;
                    end
                    4'b0011: begin
                        scl = 1'b1;
                        data = sda;
                        finish = 1'b0;
                    end
                    4'b0100: begin
                        scl = 1'b1;
                        finish = 1'b1;
                    end
                endcase
        endcase
    end
end
endmodule
