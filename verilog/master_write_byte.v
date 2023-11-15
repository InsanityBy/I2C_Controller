module I2C_master_write_byte (input clock,
                              input reset_n,
                              input go,
                              input data,
                              input [2:0] command,
                              output reg load,
                              output reg finish,
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
    
    // reg and wire connect to submodule
    reg [2:0] write_command;
    reg       write_bit_go;
    wire      write_bit_finish;
    wire      scl_w, sda_w;
    
    // connect outputs of the submodule to this module's
    always @(*) begin
        scl = scl_o;
        sda = sda_o;
    end
    
    // generate load signal to drive data shifter after sending each bit
    always @(*) begin
        load = write_bit_finish && (command == DATA);
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
    
    // finite state machine to write data and other condition, like start and ACK
    // state encode
    parameter IDLE  = 3'b000;
    parameter START = 3'b001;
    parameter DATA  = 3'b011;
    parameter ACK   = 3'b111;
    parameter NACK  = 3'b101;
    parameter STOP  = 3'b100;
    
    // 3-bit counter: drive submodule to write 8 times when writing 1 byte data
    // only increase 1 after sending 1 bit
    reg [2:0] counter;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n)
            counter <= 3'b000;
        else if ((go == 1'b1) && (finish == 1'b0) && (command == DATA)) begin
            if (write_bit_finish) begin
                if (counter == 3'b111)
                    counter <= 3'b000;
                else
                    counter <= counter + 1'b1;
            end
            else
                counter <= counter;
        end
        else
            counter <= 3'b000;
    end
    
    // state varibele
    reg [2:0] state_next;
    reg [2:0] state_current;
    
    // state transfer, sequential circuit
    always @(posedge clock or negedge reset_n) begin
        // reset, transfer to IDLE state
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
    
    // output, sequential circuit to handle race and hazard
    
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            write_bit_go  <= 1'b0;
            write_command <= IDLE;
            finish        <= 1'b0;
        end
        else begin
            case(state_current)
                IDLE: begin
                    write_bit_go  <= 1'b0;
                    write_command <= IDLE;
                    finish        <= 1'b0;
                end
                START: begin
                    write_bit_go  <= 1'b1;
                    write_command <= START_BIT;
                    if (write_bit_finish)
                        finish <= 1'b1;
                    else
                        finish <= 1'b0;
                end
                STOP: begin
                    write_bit_go  <= 1'b1;
                    write_command <= STOP_BIT;
                    if (write_bit_finish)
                        finish <= 1'b1;
                    else
                        finish <= 1'b0;
                end
                ACK: begin
                    write_bit_go  <= 1'b1;
                    write_command <= ACK_BIT;
                    if (write_bit_finish)
                        finish <= 1'b1;
                    else
                        finish <= 1'b0;
                end
                NACK: begin
                    write_bit_go  <= 1'b1;
                    write_command <= NACK_BIT;
                    if (write_bit_finish)
                        finish <= 1'b1;
                    else
                        finish <= 1'b0;
                end
                DATA: begin
                    if (write_bit_finish && (counter == 3'b111))
                        finish <= 1'b1;
                    else begin
                        write_bit_go <= 1'b1;
                        if (data) begin
                            write_command <= DATA_1;
                        end
                        else begin
                            write_command <= DATA_0;
                        end
                        finish <= 1'b0;
                    end
                end
            endcase
        end
    end
endmodule
