module I2C_master_write_byte (input clock,
                              input reset_n,
                              input go,            // enable signal for module
                              input data,          // 1 byte data to write
                              input [2:0] command, // command for different types of writing
                              output load,         // drive shifter to load data bit by bit
                              output reg finish,   // indicates completion of writing
                              output reg scl,
                              output reg sda);
    
    // instantiate submodule to write 1-bit
    // command for different write operation of submodule
    parameter START_BIT = 3'b010;
    parameter STOP_BIT  = 3'b011;
    parameter DATA_0    = 3'b100;
    parameter DATA_1    = 3'b101;
    parameter ACK_BIT   = 3'b110;
    parameter NACK_BIT  = 3'b111;
    
    // reg and wire connected to submodule
    reg [2:0] write_command;
    reg       write_bit_go;
    wire      write_bit_finish;
    wire      scl_w, sda_w;
    
    // connect outputs of the submodule to this module's
    always @(*) begin
        scl = scl_o;
        sda = sda_o;
    end
    
    // instantiate submodule
    I2C_master_write_bit write_bit(
    .command(write_command),
    .clock(clock),
    .reset_n(reset_n),
    .go(write_bit_go),
    .finish(write_bit_finish),
    .scl(scl_o),
    .sda(sda_o)
    );
    
    // finite state machine to write data and other condition
    // state encode, also write command
    parameter IDLE  = 3'b000;
    parameter START = 3'b001;
    parameter DATA  = 3'b011;
    parameter ACK   = 3'b111;
    parameter NACK  = 3'b101;
    parameter STOP  = 3'b100;
    
    // 3-bit counter for driving submodule to write 8 times when writing 1 byte data
    // only increase 1 after sending 1 bit
    reg [2:0] counter;  // current counter value
    wire counter_en;    // enable signal for counter
    wire counter_hold;  // hold counter value
    // generate enable and hold signal for counter
    assign counter_en   = go && (~finish) && (command == DATA);
    assign counter_hold = ~write_bit_finish;
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
    
    // state varibele
    reg [2:0] state_next;
    reg [2:0] state_current;
    
    // state transfer, sequential circuit
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n)
            state_current <= IDLE;
        else
            state_current <= state_next;
    end
    
    // state switch, combinational circuit
    always @(*) begin
        case(state_current)
            IDLE: begin
                if ((go == 1'b1) && (finish == 1'b0))
                    case(command)
                        START: state_next   = START;
                        DATA: state_next    = DATA;
                        ACK: state_next     = ACK;
                        NACK: state_next    = NACK;
                        STOP: state_next    = STOP;
                        default: state_next = IDLE;
                    endcase
                else
                    state_next = IDLE;
            end
            START, STOP, ACK, NACK: begin
                if (write_bit_finish)
                    state_next = IDLE;
                else
                    state_next = state_current;
            end
            DATA: begin
                if (write_bit_finish && (counter == 3'b111))
                    state_next = IDLE;
                else
                    state_next = DATA;
            end
            default: state_next = IDLE;
        endcase
    end
    
    // output
    // generate load signal to drive data shifter after sending each bit
    assign load = write_bit_finish && (command == DATA);
    // output, combinational circuit
    always @(*) begin
        if (!reset_n) begin
            write_bit_go  = 1'b0;
            write_command = IDLE;
            finish        = 1'b0;
        end
        else begin
            case(state_current)
                IDLE: begin
                    write_bit_go  = 1'b0;
                    write_command = IDLE;
                    finish        = 1'b0;
                end
                START: begin
                    write_bit_go  = 1'b1;
                    write_command = START_BIT;
                    if (write_bit_finish)
                        finish = 1'b1;
                    else
                        finish = 1'b0;
                end
                STOP: begin
                    write_bit_go  = 1'b1;
                    write_command = STOP_BIT;
                    if (write_bit_finish)
                        finish = 1'b1;
                    else
                        finish = 1'b0;
                end
                ACK: begin
                    write_bit_go  = 1'b1;
                    write_command = ACK_BIT;
                    if (write_bit_finish)
                        finish = 1'b1;
                    else
                        finish = 1'b0;
                end
                NACK: begin
                    write_bit_go  = 1'b1;
                    write_command = NACK_BIT;
                    if (write_bit_finish)
                        finish = 1'b1;
                    else
                        finish = 1'b0;
                end
                DATA: begin
                    if (write_bit_finish && (counter == 3'b111))
                        finish = 1'b1;
                    else begin
                        write_bit_go = 1'b1;
                        if (data) begin
                            write_command = DATA_1;
                        end
                        else begin
                            write_command = DATA_0;
                        end
                        finish = 1'b0;
                    end
                end
            endcase
        end
    end
endmodule
