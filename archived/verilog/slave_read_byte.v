module I2C_slave_read_byte (
    input clk,
    input rst_n,
    input byte_read_en,  // enable, expected to be high at or after scl falling edge
    output [7:0] byte_read_o,  // 1-byte data read from I2C bus
    output reg byte_read_err,
    output reg byte_read_finish,
    input scl_i,
    input sda_i
);

    // instantiate I2C_slave_read_bit
    wire bit_read_en, bit_read_o, bit_read_err, bit_read_finish;
    I2C_slave_read_bit read_bit (
        .clk            (clk),
        .rst_n          (rst_n),
        .bit_read_en    (bit_read_en),
        .bit_read_o     (bit_read_o),
        .bit_read_err   (bit_read_err),
        .bit_read_finish(bit_read_finish),
        .scl_i          (scl_i),
        .sda_i          (sda_i)
    );

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

    // 3-bit counter for reading 1-byte data bit by bit
    reg [2:0] counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 3'b000;
        end
        else if (!byte_read_en) begin
            counter <= 3'b000;
        end
        else if (bit_read_finish) begin
            if (counter == 3'b111) begin
                counter <= 3'b000;
            end
            else begin
                counter <= counter + 1;
            end
        end
        else begin
            counter <= counter;
        end
    end

    // track whether module has been enabled to prevent unexpected finish and error flag
    reg enabled;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled <= 1'b0;
        end
        else if (byte_read_en) begin
            enabled <= 1'b1;
        end
        else if ((~byte_read_en) || ((counter == 3'b111) && bit_read_finish)) begin
            enabled <= 1'b0;
        end
        else begin
            enabled <= enabled;
        end
    end

    // bit_read_en
    assign bit_read_en = byte_read_en;

    // save bit_read_o to shift register
    reg [7:0] shift_register;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_register <= 8'b0000_0000;
        end
        else if (bit_read_finish) begin
            shift_register <= {shift_register[6:0], bit_read_o};
        end
        else begin
            shift_register <= shift_register;
        end
    end

    // byte_read_o
    assign byte_read_o = shift_register;

    // byte_read_err, check whether error occurred while reading 1-bit data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_read_err <= 1'b0;
        end
        else if (!enabled) begin
            byte_read_err <= 1'b0;
        end
        else if (bit_read_err) begin
            byte_read_err <= 1'b1;
        end
        else begin
            byte_read_err <= byte_read_err;
        end
    end

    // byte_read_finish, when 8-bit data reding finished
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_read_finish <= 1'b0;
        end
        else if (bit_read_finish && (counter == 3'b111)) begin
            byte_read_finish <= 1'b1;
        end
        else begin
            byte_read_finish <= 1'b0;
        end
    end

endmodule
