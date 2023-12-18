module I2C_master (
           input clock,
           input reset_n,
           input transfer_control,       // 1 to start transfer, 0 to end
           input byte_control,           // 1 to start reading/writing 1-byte data
           input read_write,             // 1 for read, 0 for write
           input combined_enable,        // enable combined mode
           input [6: 0] targret_address,  // target address
           input [7: 0] data_in,          // data to write
           output reg [7: 0] data_out,    // data read from I2C bus
           output reg data_finish,       // data reading/writing finished
           output reg transfer_busy,     // transfer status, 1 for reading/writing in process
           output reg bus_busy,          // I2C bus status, 1 for bus busy
           output reg error,             // indicates an error during reading
           input scl_in,
           output reg scl_out,
           input sda_in,
           output sda_out);

// instantiate submodules
// submodule to write 1 byte
// command for different write operation
parameter IDLE_COMMAND = 3'b000;
parameter START_COMMAND = 3'b001;
parameter DATA_COMMAND = 3'b011;
parameter ACK_COMMAND = 3'b111;
parameter NACK_COMMAND = 3'b101;
parameter STOP_COMMAND = 3'b100;
// reg and wire connect to submodule
reg write_go, write_data;
reg [2: 0] write_command;
wire write_load, write_finish, write_scl, write_sda;
// connect
assign sda_out = write_sda;
I2C_master_write_byte write_byte(
                          .clock(clock),
                          .reset_n(reset_n),
                          .go(write_go),
                          .data(write_data),
                          .command(write_command),
                          .load(write_load),
                          .finish(write_finish),
                          .scl(write_scl),
                          .sda(write_sda));

// submodule to read 1 byte
// reg and wire connect to submodule
reg read_go;
wire read_data, read_load, read_finish, read_error, read_scl, read_sda;
// connect
assign read_sda = sda_in;
I2C_master_read_byte read_byte(
                         .clock(clock),
                         .reset_n(reset_n),
                         .go(read_go),
                         .data(read_data),
                         .load(read_load),
                         .finish(read_finish),
                         .error(read_error),
                         .scl(read_scl),
                         .sda(read_sda));

// submodule to check ACK/NACK
// reg and wire connect to submodule
reg check_go;
wire check_data, check_finish, check_error, check_scl, check_sda;
wire get_ack;
// connect
assign check_sda = sda_in;
assign get_ack = check_finish && (~check_error) && (~check_data);
I2C_master_read_bit check_ACK(
                        .clock(clock),
                        .reset_n(reset_n),
                        .go(check_go),
                        .data(check_data),
                        .finish(check_finish),
                        .error(check_error),
                        .scl(check_scl),
                        .sda(check_sda));

// scl connection
always @( * ) begin
    if (write_go)
        scl_out = write_scl;
    else if (check_go)
        scl_out = check_scl;
    else if (read_go)
        scl_out = read_scl;
    else
        scl_out = 1'bz;
end

// check I2C bus status
// detect sda falling and rising edge
reg [1: 0] sda_state;
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        sda_state <= 2'b00;
    end
    else begin
        sda_state <= {sda_state[0], sda_in};
    end
end
reg bus_detect; // 1 for bus busy, 0 for free
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        bus_detect <= 1'b0;
    end
    else if (scl_in) begin
        case (sda_state)
            2'b00, 2'b11:
                bus_detect <= bus_detect;
            2'b01:
                bus_detect <= 1'b0; // bus free after detect STOP bit
            2'b10:
                bus_detect <= 1'b1; // bus busy after detect START bit
        endcase
    end
    else begin
        bus_detect <= bus_detect;
    end
end

// latch settings at transfer_control rising edge
// detect transfer_control rising edge
reg [1: 0] transfer_control_state;
wire transfer_control_rising;
assign transfer_control_rising = (~transfer_control_state[1]) && transfer_control_state[0];
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        transfer_control_state <= 2'b00;
    end
    else begin
        transfer_control_state <= {transfer_control_state[0], transfer_control};
    end
end
// latch settings
reg current_read_write; // latch read/write setting before start
reg current_combined_mode; // latch combined mode setting before start
reg [7: 0] current_address; // latch address during transfer
always @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        current_read_write <= 1'b0;
        current_combined_mode <= 1'b0;
        current_address <= 8'h00;
    end
    else if (transfer_control_rising) begin
        current_read_write <= read_write;
        current_combined_mode <= combined_enable;
        current_address <= targret_address;
    end
    else begin
        current_read_write <= current_read_write;
        current_combined_mode <= current_combined_mode;
        current_address <= current_address;
    end
end

// data shifter
reg [7: 0] address_shifter;  // load address to write
// address shifter
always @(posedge clock or negedge reset_n) begin
    // reload data
    if (!reset_n) begin
        address_shifter <= 8'h00;
    end
    else if (state_current == WRITE_START) begin
        address_shifter = {current_address, current_read_write};
    end
    else if (write_load && (state_current == WRITE_ADDRESS)) begin
        address_shifter <= {address_shifter[6: 0], 1'b0};
    end
    else begin
        address_shifter <= address_shifter;
    end
end

// finite state machine
// state encode
parameter IDLE = 12'h000;
parameter WRITE_START = 12'h001;
parameter WRITE_ADDRESS = 12'h002;
parameter ADDRESS_ACK = 12'h004;
parameter WAIT = 12'h008;
parameter WRITE_DATA = 12'h010;
parameter DATA_ACK = 12'h020;
parameter READ_DATA = 12'h040;
parameter WRITE_ACK = 12'h080;
parameter WRITE_NACK = 12'h100;
parameter GET_NACK = 12'h200;
parameter STOP = 12'h400;
parameter ERROR = 12'h800;

// state varibele
reg [11: 0] state_next;
reg [11: 0] state_current;

// state transfer, sequential circuit
always @(posedge clock or negedge reset_n) begin
    if (!reset_n)
        state_current <= IDLE;
    else
        state_current <= state_next;
end

// state switch, combinational circuit
always @( * ) begin
    case (state_current)
        IDLE: begin
            if (transfer_control && (~bus_detect))
                state_next = WRITE_START;
            else
                state_next = IDLE;
        end
        WRITE_START: begin
            state_next = WRITE_ADDRESS;
        end
        WRITE_ADDRESS: begin
            state_next = ADDRESS_ACK;
        end
        ADDRESS_ACK: begin
            if (check_finish) begin
                if (!get_ack)
                    state_next = GET_NACK;
                else
                    state_next = WAIT;
            end
            else begin
                state_next = ADDRESS_ACK;
            end
        end
        WAIT: begin
            case ({transfer_control, byte_control, combined_enable})
                3'b000, 3'b001, 3'b010, 3'b011: begin
                    if (current_read_write)
                        state_next = WRITE_NACK;
                    else
                        state_next = STOP;
                end
                3'b100, 3'b101: begin
                    state_next = WAIT;
                end
                3'b110: begin
                    if (current_read_write)
                        state_next = READ_DATA;
                    else
                        state_next = WRITE_DATA;
                end
                3'b111: begin
                    if (read_write == current_read_write) begin
                        if (current_read_write)
                            state_next = READ_DATA;
                        else
                            state_next = WRITE_DATA;
                    end
                    else begin
                        state_next = WRITE_START;
                    end
                end
            endcase
        end
        WRITE_DATA: begin
            if (write_finish)
                state_next = DATA_ACK;
            else
                state_next = WRITE_DATA;
        end
        DATA_ACK: begin
            if (check_finish) begin
                if (!get_ack)
                    state_next = GET_NACK;
                else
                    state_next = WAIT;
            end
            else begin
                state_next = DATA_ACK;
            end
        end
        READ_DATA: begin
            if (read_finish) begin
                if (read_error)
                    state_next = WRITE_NACK;
                else
                    state_next = WRITE_ACK;
            end
            else
                state_next = READ_DATA;
        end
        WRITE_ACK: begin
            if (write_finish)
                state_next = WAIT;
            else
                state_next = WRITE_ACK;
        end
        WRITE_NACK: begin
            if (write_finish)
                state_next = STOP;
            else
                state_next = WRITE_NACK;
        end
        GET_NACK: begin
            state_next = STOP;
        end
        STOP: begin
            if (write_finish)
                state_next = IDLE;
            else
                state_next = STOP;
        end
        default:
            state_next = IDLE;
    endcase
end

// output, combinational circuit
always @( * ) begin
    if (!reset_n) begin
        {write_go, write_command, read_go, check_go} = {1'b0, IDLE_COMMAND, 1'b0, 1'b0};
    end
    else begin
        case (state_current)
            IDLE: begin
                {write_go, write_command, read_go, check_go} = {1'b0, IDLE_COMMAND, 1'b0, 1'b0};
            end
            WRITE_START: begin
                {write_go, write_command, read_go, check_go} = {1'b1, START_COMMAND, 1'b0, 1'b0};
            end
            WRITE_ADDRESS: begin
                {write_go, write_command, read_go, check_go} = {1'b1, DATA_COMMAND, 1'b0, 1'b0};
            end
            ADDRESS_ACK, DATA_ACK: begin
                {write_go, write_command, read_go, check_go} = {1'b0, IDLE_COMMAND, 1'b0, 1'b1};
            end
            WAIT: begin
                {write_go, write_command, read_go, check_go} = {1'b0, IDLE_COMMAND, 1'b0, 1'b0};
            end
            WRITE_DATA: begin
                {write_go, write_command, read_go, check_go} = {1'b1, DATA_COMMAND, 1'b0, 1'b0};
            end
            READ_DATA: begin
                {write_go, write_command, read_go, check_go} = {1'b0, IDLE_COMMAND, 1'b1, 1'b0};
            end
            WRITE_ACK: begin
                {write_go, write_command, read_go, check_go} = {1'b1, ACK_COMMAND, 1'b0, 1'b0};
            end
            WRITE_NACK: begin
                {write_go, write_command, read_go, check_go} = {1'b1, NACK_COMMAND, 1'b0, 1'b0};
            end
            GET_NACK: begin
                {write_go, write_command, read_go, check_go} = {1'b0, IDLE_COMMAND, 1'b0, 1'b0};
            end
            STOP: begin
                {write_go, write_command, read_go, check_go} = {1'b1, STOP_COMMAND, 1'b0, 1'b0};
            end
        endcase
    end
end
endmodule
