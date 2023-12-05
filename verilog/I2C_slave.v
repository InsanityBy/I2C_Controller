module I2C_slave (
    input            clk,
    input            rst_n,
    input            slave_en,
    input      [6:0] slave_addr,
    input      [7:0] byte_write_i,     // 1-byte data write to I2C bus
    output     [7:0] byte_read_o,      // 1-byte data read from I2C bus
    output reg       read_write_flag,  // 1 for read, 0 for write
    output reg       byte_finish,
    output reg       transmit_busy,
    output reg       transmit_err,
    input            scl_i,
    output           scl_o,
    input            sda_i,
    output           sda_o
);

    // instantiate submodule to write 1 byte
    reg write_en;
    wire write_finish, write_sda_o;
    I2C_slave_write_byte write_byte (
        .clk              (clk),
        .rst_n            (rst_n),
        .byte_write_en    (write_en),
        .byte_write_i     (byte_write_i),
        .byte_write_finish(write_finish),
        .scl_i            (scl_i),
        .sda_o            (write_sda_o)
    );

    // instantiate submodule to write ACK
    reg ack_en;
    wire ack_finish, ack_sda_o;
    I2C_slave_write_bit write_ack (
        .clk             (clk),
        .rst_n           (rst_n),
        .bit_write_en    (ack_en),
        .bit_write_i     (1'b0),
        .bit_write_finish(ack_finish),
        .scl_i           (scl_i),
        .sda_o           (ack_sda_o)
    );

    // instantiate submodule to read 1 byte
    reg read_en;
    wire read_err, read_finish;
    I2C_slave_read_byte read_byte (
        .clk             (clk),
        .rst_n           (rst_n),
        .byte_read_en    (read_en),
        .byte_read_o     (byte_read_o),
        .byte_read_err   (read_err),
        .byte_read_finish(read_finish),
        .scl_i           (scl_i),
        .sda_i           (sda_i)
    );

    // instantiate submodule to check ACK/NACK
    reg check_en;
    wire check_read_o, check_err, check_finish;
    wire get_ack;
    assign get_ack = check_finish && (~check_read_o) && (~check_err);
    I2C_slave_read_bit check_ACK (
        .clk            (clk),
        .rst_n          (rst_n),
        .bit_read_en    (check_en),
        .bit_read_o     (check_read_o),
        .bit_read_err   (check_err),
        .bit_read_finish(check_finish),
        .scl_i          (scl_i),
        .sda_i          (sda_i)
    );

    // detect sda_i falling and rising edge
    reg sda_last;
    wire sda_rise, sda_fall;
    // save sda_i last state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_last <= 1'b1;
        end
        else begin
            sda_last <= sda_i;
        end
    end
    // sda_i falling edge: 1 -> 0
    assign sda_fall = sda_last && (~sda_i);
    // sda_i rising edge: 0 -> 1
    assign sda_rise = (~sda_last) && sda_i;

    // detect start and stop conditions
    wire start, stop;
    // start: scl high, sda_i 1 -> 0
    assign start = scl_i && sda_fall;
    // stop: scl high, sda_i 0 -> 1
    assign stop  = scl_i && sda_rise;

    // detect scl_i falling edge
    reg  scl_last;
    wire scl_fall;
    // save scl_i last state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_last <= 1'b1;
        end
        else begin
            scl_last <= scl_i;
        end
    end
    // scl_i falling edge: 0 -> 1
    assign scl_fall = scl_last && (~scl_i);

    // finite state machine
    // state encode
    parameter IDLE = 8'h00;
    parameter GET_START = 8'h01;

    parameter READ_ADDRESS = 8'h02;
    parameter WRITE_ADDRESS_ACK = 8'h04;

    parameter READ_DATA = 8'h08;
    parameter WRITE_DATA_ACK = 8'h10;

    parameter WRITE_DATA = 8'h20;
    parameter CHECK_DATA_ACK = 8'h40;

    parameter WAIT = 8'h80;

    // state variable
    reg [7:0] state_next;
    reg [7:0] state_current;

    // state transfer, sequential circuit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_current <= IDLE;
        end
        else begin
            state_current <= state_next;
        end
    end

    // state switch, combinational circuit
    always @(*) begin
        case (state_current)
            IDLE: begin
                if (slave_en && start) begin
                    state_next = GET_START;
                end
                else begin
                    state_next = IDLE;
                end
            end
            GET_START: begin
                if (scl_fall) begin
                    state_next = READ_ADDRESS;
                end
                else begin
                    state_next = GET_START;
                end
            end
            READ_ADDRESS: begin
                if (read_finish) begin
                    if (byte_read_o[7:1] == slave_addr) begin
                        state_next = WRITE_ADDRESS_ACK;
                    end
                    else begin
                        state_next = WAIT;
                    end
                end
                else begin
                    state_next = READ_ADDRESS;
                end
            end
            WRITE_ADDRESS_ACK: begin
                if (ack_finish) begin
                    if (byte_read_o[0]) begin
                        state_next = READ_DATA;
                    end
                    else begin
                        state_next = WRITE_DATA;
                    end
                end
                else begin
                    state_next = WRITE_ADDRESS_ACK;
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
                else begin
                    state_next = READ_DATA;
                end
            end
            WRITE_DATA_ACK: begin
                if (ack_finish) begin
                    state_next = READ_DATA;
                end
                else begin
                    state_next = WRITE_DATA_ACK;
                end
            end
            WRITE_DATA: begin
                if (write_finish) begin
                    state_next = CHECK_DATA_ACK;
                end
                else begin
                    state_next = WRITE_DATA;
                end
            end
            CHECK_DATA_ACK: begin
                if (check_finish) begin
                    if (get_ack) begin
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
                else if (stop) begin
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

    // output signal to control submodules, combinational circuit
    always @(*) begin
        if (!rst_n) begin
            {read_en, ack_en, write_en, check_en} = 4'b0000;
        end
        else begin
            case (state_current)
                IDLE: begin
                    {read_en, ack_en, write_en, check_en} = 4'b0000;
                end
                GET_START: begin
                    if (scl_fall) begin
                        {read_en, ack_en, write_en, check_en} = 4'b1000;
                    end
                    else begin
                        {read_en, ack_en, write_en, check_en} = 4'b0000;
                    end
                end
                READ_ADDRESS: begin
                    if (read_finish) begin
                        if (byte_read_o[7:1] == slave_addr) begin
                            {read_en, ack_en, write_en, check_en} = 4'b0100;
                        end
                        else begin
                            {read_en, ack_en, write_en, check_en} = 4'b0000;
                        end
                    end
                    else begin
                        {read_en, ack_en, write_en, check_en} = 4'b1000;
                    end
                end
                WRITE_ADDRESS_ACK: begin
                    if (ack_finish) begin
                        if (byte_read_o[0]) begin
                            {read_en, ack_en, write_en, check_en} = 4'b1000;
                        end
                        else begin
                            {read_en, ack_en, write_en, check_en} = 4'b0010;
                        end
                    end
                    else begin
                        {read_en, ack_en, write_en, check_en} = 4'b0100;
                    end
                end
                READ_DATA: begin
                    if (start) begin
                        {read_en, ack_en, write_en, check_en} = 4'b0000;
                    end
                    else if (stop) begin
                        {read_en, ack_en, write_en, check_en} = 4'b0000;
                    end
                    else if (read_finish) begin
                        {read_en, ack_en, write_en, check_en} = 4'b0100;
                    end
                    else begin
                        {read_en, ack_en, write_en, check_en} = 4'b1000;
                    end
                end
                WRITE_DATA_ACK: begin
                    if (ack_finish) begin
                        {read_en, ack_en, write_en, check_en} = 4'b1000;
                    end
                    else begin
                        {read_en, ack_en, write_en, check_en} = 4'b0100;
                    end
                end
                WRITE_DATA: begin
                    if (write_finish) begin
                        {read_en, ack_en, write_en, check_en} = 4'b0001;
                    end
                    else begin
                        {read_en, ack_en, write_en, check_en} = 4'b0010;
                    end
                end
                CHECK_DATA_ACK: begin
                    if (check_finish) begin
                        if (get_ack) begin
                            {read_en, ack_en, write_en, check_en} = 4'b0010;
                        end
                        else begin
                            {read_en, ack_en, write_en, check_en} = 4'b0000;
                        end
                    end
                    else begin
                        {read_en, ack_en, write_en, check_en} = 4'b0001;
                    end
                end
                WAIT: begin
                    {read_en, ack_en, write_en, check_en} = 4'b0000;
                end
                default: begin
                    {read_en, ack_en, write_en, check_en} = 4'b0000;
                end
            endcase
        end
    end

    // external outputs
    // sda_o
    assign sda_o = ack_en ? ack_sda_o : (write_en ? write_sda_o : 1'b1);

    // read_write_flag
    always @(*) begin
        case (state_current)
            IDLE, GET_START, READ_ADDRESS, WRITE_ADDRESS_ACK, WAIT: begin
                read_write_flag = 1'b0;
            end
            READ_DATA, WRITE_DATA_ACK: begin
                read_write_flag = 1'b1;
            end
            WRITE_DATA, CHECK_DATA_ACK: begin
                read_write_flag = 1'b0;
            end
            default: begin
                read_write_flag = 1'b0;
            end
        endcase
    end

    // byte_finish
    always @(*) begin
        case (state_current)
            WRITE_DATA_ACK: begin
                byte_finish = ack_finish;
            end
            CHECK_DATA_ACK: begin
                byte_finish = check_finish;
            end
            default: begin
                byte_finish = 1'b0;
            end
        endcase
    end

    // transmit_busy
    always @(*) begin
        case (state_current)
            IDLE, GET_START, READ_ADDRESS, WRITE_ADDRESS_ACK, WAIT: begin
                transmit_busy = 1'b0;
            end
            READ_DATA, WRITE_DATA_ACK, WRITE_DATA, CHECK_DATA_ACK: begin
                transmit_busy = 1'b1;
            end
            default: begin
                transmit_busy = 1'b0;
            end
        endcase
    end

    // transmit_err
    always @(*) begin
        transmit_err = read_err;
    end

endmodule
