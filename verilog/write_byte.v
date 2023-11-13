module I2C_write_byte (
    // signal to control module
    input [2:0] command,
    input       clock,
    input       reset_n,
    input       go,
    input       data,
    output reg  finish,
    // signal to control I2C
    output reg  scl,
                sda
);

// module to write 1-bit
// state and command
parameter START_BIT = 3'b010;
parameter STOP_BIT = 3'b011;
parameter DATA_0 = 3'b100;
parameter DATA_1 = 3'b101;
parameter ACK_BIT = 3'b110;
parameter NACK_BIT = 3'b111;

reg [2:0] write_command;
reg       write_bit_go;
wire      write_bit_finish;
wire      scl_o, sda_o;

assign scl = (write_bit_go)?scl_o:1'bz;
assign sda = (write_bit_go)?sda_o:1'bz;

I2C_write_bit write_bit(
    .command(write_command).
    .clock(clock),
    .reset_n(reset_n),
    .go(write_bit_go),
    .finish(write_bit_finish),
    .scl(scl_o),
    .sda(sda_o)
)

// 4-bit counter: when leave IDLE start counting
reg [3:0] counter;
always @(posedge clock ) begin
    if((go == 1'b1) && (finish == 1'b0)) begin
        if((command == DATA) && write_bit_finish) begin
            if(counter == 4'b1111)
                counter <= 4'b0000;
            else
                counter <= counter + 1'b1;
        end
    end
    else
        counter <= 4'b0000;
end

// state and command
parameter IDLE = 3'b000;
parameter START = 3'b001;
parameter DATA = 3'b011;
parameter ACK = 3'b111;
parameter NACK = 3'b101;
parameter STOP = 3'b100;

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
                        START: state_next = START;
                        DATA: state_next = DATA;
                        ACK: state_next = ACK;
                        NACK: state_next = NACK;
                        STOP: state_next = STOP;
                        default: state_next = IDLE;
                    endcase
            end
        START, STOP, ACK, NACK:
            begin
                if(write_bit_finish)
                    state_next = IDLE;
                else
                    state_next = state_current;
            end
        DATA:
            begin
                if(write_bit_finish && (counter == 4'b1000))
                    state_next = IDLE;
                else
                    state_next = DATA;
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
        case(state_current)
            IDLE:
                begin
                    write_bit_go = 1'b0;
                    write_command = IDLE;
                    finish = 1'b0;
                end
            START:
                begin
                    write_bit_go = 1'b1;
                    write_command = START_BIT;
                    if(write_bit_finish)
                        finish = 1'b1;
                    else
                        finish = 1'b0;
                end
            STOP:
                begin
                    write_bit_go = 1'b1;
                    write_command = STOP_BIT;
                    if(write_bit_finish)
                        finish = 1'b1;
                    else
                        finish = 1'b0;
                end
            ACK:
                begin
                    write_bit_go = 1'b1;
                    write_command = ACK_BIT;
                    if(write_bit_finish)
                        finish = 1'b1;
                    else
                        finish = 1'b0;
                end
            NACK:
                begin
                    write_bit_go = 1'b1;
                    write_command = NACK_BIT;
                    if(write_bit_finish)
                        finish = 1'b1;
                    else
                        finish = 1'b0;
                end
            DATA:
                begin
                    if(write_bit_finish && (counter == 4'b1000))
                        finish = 1'b1;
                    else begin
                        if(data)
                            write_command = DATA_1;
                        else
                            write_command = DATA_0;
                        write_bit_go = 1'b1'
                        finish = 1'b0;
                    end
                end
        endcase
    end
end
endmodule
