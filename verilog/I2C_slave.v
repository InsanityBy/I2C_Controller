module I2C_slave (
           input clock,
           input reset_n,
           input enable,                // enable signal
           input [6: 0] address,        // set module address
           input [7: 0] data_write,     // data write to I2C bus
           output [7: 0] data_read,     // data read from I2C bus
           output reg read_write_flag,  // 1 for read, 0 for write
           output reg data_finish,      // data reading/writing finished
           output reg transfer_status,  // transfer status, 1 for transfer in process
           output reg bus_status,       // I2C bus status, 1 for bus busy
           output reg error,            // error signal
           input scl_in,
           output scl_out,
           input sda_in,
           output sda_out);

// instantiate submodules
// submodule to write 1 byte
reg write_enable;
wire write_finish, write_sda;
I2C_slave_write_byte write_byte(
                         .clock(clock),
                         .reset_n(reset_n),
                         .enable(write_enable),
                         .data(data_write),
                         .finish(write_finish),
                         .scl(scl_in),
                         .sda(write_sda));

// submodule to write ACK/NACK
reg ack_enable, ack_data;
wire ack_finish, ack_sda;
I2C_slave_write_bit write_ack(
                        .clock(clock),
                        .reset_n(reset_n),
                        .enable(ack_enable),
                        .data(ack_data),
                        .finish(ack_finish),
                        .scl(scl_in),
                        .sda(ack_sda)
                    );

// sda_out
assign sda_out = write_enable ? write_sda : (ack_enable ? ack_sda : 1'b1);

// submodule to read 1 byte
reg read_enable;
wire read_finish, read_error;
I2C_slave_read_byte read_byte(
                        .clock(clock),
                        .reset_n(reset_n),
                        .enable(read_enable),
                        .data(data_read),
                        .error(read_error),
                        .finish(read_finish),
                        .scl(scl_in),
                        .sda(sda_in));

// submodule to check ACK/NACK
reg check_enable;
wire check_data, check_error, check_finish;
wire get_ack;
assign get_ack = check_finish && (~check_data) && (~check_error);
I2C_slave_read_bit check_ACK(
                       .clock(clock),
                       .reset_n(reset_n),
                       .enable(check_enable),
                       .data(check_data),
                       .error(check_error),
                       .finish(check_finish),
                       .scl(scl_in),
                       .sda(sda_in));

// detect sda falling and rising edge
reg sda_last_state;
wire sda_rising_edge, sda_falling_edge;
// save sda last state
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        sda_last_state <= 1'b1;
    end
    else begin
        sda_last_state <= sda_in;
    end
end
// sda falling edge: 1 -> 0
assign sda_falling_edge = sda_last_state && (~sda_in);
// sda rising edge: 0 -> 1
assign sda_rising_edge = (~sda_last_state) && sda_in;

// check start and stop conditons
wire start, stop;
// start: scl high, sda 1 -> 0
assign start = scl_in && sda_falling_edge;
// stop: scl high, sda 0 -> 1
assign stop = scl_in && sda_rising_edge;

// detect scl falling and rising edge
reg scl_last_state;
wire scl_rising_edge, scl_falling_edge;
// save scl last state
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        scl_last_state <= 1'b1;
    end
    else begin
        scl_last_state <= scl_in;
    end
end
// scl falling edge: 1 -> 0
assign scl_falling_edge = scl_last_state && (~scl_in);
// scl rising edge: 0 -> 1
assign scl_rising_edge = (~scl_last_state) && scl_in;

// finite state machine
// state encode
parameter IDLE = 10'h000;
parameter GET_START = 10'h001;

parameter READ_ADDRESS = 10'h002;
parameter WRITE_ADDRESS_ACK = 10'h004;

parameter WAIT_TO_READ = 10'h008;
parameter READ_DATA = 10'h010;
parameter WRITE_DATA_ACK = 10'h020;

parameter WRITE_DATA = 10'h040;
parameter WAIT_TO_CHECK = 10'h080;
parameter CHECK_DATA_ACK = 10'h100;

parameter WAIT = 10'h200;

// state varibele
reg [9: 0] state_next;
reg [9: 0] state_current;

// state transfer, sequential circuit
always @(posedge clock or negedge reset_n) begin
    if (!reset_n)
        state_current <= IDLE;
    else
        state_current <= state_next;
end

// state switch, combinational circuit
always @(*) begin
    case (state_current)
        IDLE: begin
            if (enable && start) begin
                state_next = GET_START;
            end
            else begin
                state_next = IDLE;
            end
        end
        GET_START: begin
            if(scl_rising_edge) begin
                state_next = READ_ADDRESS;
            end
            else begin
                state_next = GET_START;
            end
        end
        READ_ADDRESS: begin
            if (read_finish) begin
                state_next = WRITE_ADDRESS_ACK;
            end
            else begin
                state_next = READ_ADDRESS;
            end
        end
        WRITE_ADDRESS_ACK: begin
            if (scl_falling_edge) begin
                if (data_read[7:1] == address) begin
                    if (data_read[0]) begin
                        state_next = WAIT_TO_READ;
                    end
                    else begin
                        state_next = WRITE_DATA;
                    end
                end
                else begin
                    state_next = WAIT;
                end
            end
            else begin
                state_next = WRITE_ADDRESS_ACK;
            end
        end
        WAIT_TO_READ: begin
            if (scl_rising_edge) begin
                state_next = READ_DATA;
            end
            else begin
                state_next = WAIT_TO_READ;
            end
        end
        READ_DATA: begin
            if (start) begin
                state_next = GET_START;
            end
            else if (stop) begin
                state_next = IDLE;
            end
            else if (read_finish) begin
                state_next = WRITE_DATA_ACK;
            end
            else
                state_next = READ_DATA;
        end
        WRITE_DATA_ACK: begin
            if(scl_falling_edge) begin
                state_next = WAIT_TO_READ;
            end
            else begin
                state_next = WRITE_DATA_ACK;
            end
        end
        WRITE_DATA: begin
            if (write_finish)
                state_next = WAIT_TO_CHECK;
            else
                state_next = WRITE_DATA;
        end
        WAIT_TO_CHECK: begin
            if (scl_rising_edge) begin
                state_next = CHECK_DATA_ACK;
            end
            else begin
                state_next = WAIT_TO_CHECK;
            end
        end
        CHECK_DATA_ACK: begin
            if(check_finish) begin
                if(get_ack) begin
                    state_next = WRITE_DATA;
                end
                else begin
                    state_next = WAIT;
                end
            end
            else begin
                state_next = CHECK_DATA_ACK;
            end
        end
        WAIT: begin
            if (start) begin
                state_next = GET_START;
            end
            else if(stop) begin
                state_next = IDLE;
            end
            else begin
                state_next = WAIT;
            end
        end
        default: begin
            state_next = IDLE;
        end
    endcase
end

// outputs
// signal to control submodules, combinational circuit
always @(*) begin
    if (!reset_n) begin
        {write_enable, ack_enable, read_enable, check_enable} = 4'b0000;
        ack_data = 1'b0;
    end
    else begin
        case (state_current)
            IDLE: begin
                {write_enable, ack_enable, read_enable, check_enable} = 4'b0000;
                ack_data = 1'b0;
            end
            GET_START: begin
                if (scl_rising_edge) begin
                    read_enable = 1'b1;
                end
                else begin
                    read_enable = 1'b0;
                end
                {write_enable, ack_enable, check_enable} = 3'b000;
                ack_data = 1'b0;
            end
            READ_ADDRESS: begin
                if (read_finish) begin
                    if (data_read[7:1] == address) begin
                        ack_enable = 1'b1;
                        ack_data = 1'b0;
                    end
                    else begin
                        ack_enable = 1'b1;
                        ack_data = 1'b1;
                    end
                end
                else begin
                    ack_enable = 1'b0;
                    ack_data = 1'b0;
                end
            end
            WRITE_ADDRESS_ACK: begin
                if (scl_falling_edge) begin
                    if (data_read[0]) begin
                        {write_enable, ack_enable, read_enable, check_enable} = 4'b0100;
                    end
                    else begin
                        {write_enable, ack_enable, read_enable, check_enable} = 4'b1000;
                    end
                end
                else begin
                    {write_enable, ack_enable, read_enable, check_enable} = 4'b0100;
                end
                ack_data = 1'b0;
            end
            WAIT_TO_READ: begin
                if (scl_rising_edge) begin
                    read_enable = 1'b1;
                end
                else begin
                    read_enable = 1'b0;
                end
                {write_enable, ack_enable, check_enable} = 4'b0000;
                ack_data = 1'b0;
            end
            READ_DATA: begin
                if (read_finish) begin
                    ack_enable = 1'b1;
                    ack_data = read_error;
                end
                else begin
                    ack_enable = 1'b0;
                    ack_data = 1'b0;
                end
                {write_enable, read_enable, check_enable} = 3'b000;
            end
            WRITE_DATA_ACK: begin
                if(scl_falling_edge) begin
                    {write_enable, ack_enable, read_enable, check_enable} = 4'b0000;
                end
                else begin
                    {write_enable, ack_enable, read_enable, check_enable} = 4'b0100;
                end
                ack_data = 1'b0;
            end
            WRITE_DATA: begin
                {write_enable, ack_enable, read_enable, check_enable} = 4'b0000;
                ack_data = 1'b0;
            end
            WAIT_TO_CHECK: begin
                if (scl_rising_edge) begin
                    check_enable = 1'b1;
                end
                else begin
                    check_enable = 1'b0;
                end
                {write_enable, ack_enable, read_enable} = 3'b000;
                ack_data = 1'b0;
            end
            CHECK_DATA_ACK: begin
                if (check_finish && get_ack) begin
                    write_enable = 1'b1;
                end
                else begin
                    write_enable = 1'b0;
                end
                {ack_enable, read_enable, check_enable} = 4'b0000;
                ack_data = 1'b0;
            end
            WAIT: begin
                {write_enable, ack_enable, read_enable, check_enable} = 4'b0000;
                ack_data = 1'b0;
            end
            default: begin
                {write_enable, ack_enable, read_enable, check_enable} = 4'b0000;
                ack_data = 1'b0;
            end
        endcase
    end
end

// external outputs
// generate read_write_flag
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        read_write_flag <= 1'b0;
    end
    else if (read_finish && (state_current == READ_ADDRESS)) begin
        read_write_flag <= data_read[0];
    end
    else begin
        read_write_flag <= read_write_flag;
    end
end
// generate bus_status, 1 for bus busy, 0 for free
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        bus_status <= 1'b0;
    end
    else if (start) begin
        bus_status <= 1'b1;
    end
    else if (stop) begin
        bus_status <= 1'b0;
    end
    else begin
        bus_status <= bus_status;
    end
end
// generate data_finish
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        data_finish <= 1'b0;
    end
    else if (read_finish && (state_current == READ_DATA)) begin
        data_finish <= 1'b1;
    end
    else if (write_finish && (state_current == WRITE_DATA)) begin
        data_finish <= 1'b1;
    end
    else begin
        data_finish <= 1'b0;
    end
end
// generate transfer_status
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        transfer_status <= 1'b0;
    end
    else begin
        case (state_current)
            IDLE, GET_START, WAIT: begin
                transfer_status <= 1'b0;
            end
            WRITE_ADDRESS_ACK: begin
                transfer_status <= 1'b1;
            end
            default: begin
                transfer_status <= transfer_status;
            end
        endcase
    end
end
// generate error
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        error <= 1'b0;
    end
    else if (start) begin
        error <= 1'b0;
    end
    else if ((state_current == READ_DATA) && read_error) begin
        error <= 1'b1;
    end
    else begin
        error <= error;
    end
end

endmodule
