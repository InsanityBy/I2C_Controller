module I2C_master_read_byte (
    // signal to control module
    input       clock,
    input       reset_n,
    input       go,
    output reg  finish,
    output      data,
    output reg  load,
    // signal to control I2C
    input       sda,
    output reg  scl
);

// module to read 1-bit
reg       read_bit_go;
wire      read_bit_finish;
wire      scl_o;

assign scl = scl_o;
assign load = read_bit_finish;

I2C_master_read_bit read_bit(
    .clock(clock),
    .reset_n(reset_n),
    .go(read_bit_go),
    .finish(read_bit_finish),
    .data(data),
    .sda(sda),
    .scl(scl_o)
);

// 4-bit counter: when leave IDLE start counting
reg [3:0] counter;
always @(posedge clock ) begin
    if((go == 1'b1) && (finish == 1'b0)) begin
        if(read_bit_finish) begin
	      if(counter == 4'b1111)
	          counter <= 4'b0000;
	      else
	          counter <= counter + 1'b1;
        end
        else
            counter <= counter;
    end
    else
        counter <= 4'b0000;
end

// state
parameter IDLE = 1'b0;
parameter READ_BYTE = 1'b1;

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

// state switch, combination
always @(*) begin
    case(state_current)
        IDLE:
            begin
                if((go == 1'b1) && (finish == 1'b0))
                    state_next = READ_BYTE;
                else
                    state_next = IDLE;
            end
        READ_BYTE:
            begin
                if(read_bit_finish && (counter == 4'b0111))
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
        finish = 1'b0;
    end
    else begin
        case(state_current)
            IDLE:
                begin
                    read_bit_go = 1'b0;
                    finish = 1'b0;
                end
            READ_BYTE:
                begin
                    if(read_bit_finish && (counter == 4'b0111))
                        finish = 1'b1;
                    else begin
                        read_bit_go = 1'b1;
                        finish = 1'b0;
                    end
                end
        endcase
    end
end
endmodule
