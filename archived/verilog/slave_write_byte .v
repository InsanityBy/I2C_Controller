module I2C_slave_write_byte (
    input clk,
    input rst_n,
    input byte_write_en,  // enable, expected to be high at or after scl falling edge
    input [7:0] byte_write_i,  // 1-byte data write to I2C bus
    output reg byte_write_finish,
    input scl_i,
    output sda_o
);

    // instantiate I2C_slave_write_bit
    wire bit_write_en, bit_write_i, bit_write_finish;
    I2C_slave_write_bit write_bit (
        .clk             (clk),
        .rst_n           (rst_n),
        .bit_write_en    (bit_write_en),
        .bit_write_i     (bit_write_i),
        .bit_write_finish(bit_write_finish),
        .scl_i           (scl_i),
        .sda_o           (sda_o)
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

    // 3-bit counter for writing 1-byte data bit by bit
    reg [2:0] counter;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 3'b000;
        end
        else if (!byte_write_en) begin
            counter <= 3'b000;
        end
        else if (bit_write_finish) begin
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

    // track whether module has been enabled to prevent unexpected finish flag
    reg enabled;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled <= 1'b0;
        end
        else if (byte_write_en) begin
            enabled <= 1'b1;
        end
        else if ((~byte_write_en) || ((counter == 3'b111) && bit_write_finish)) begin
            enabled <= 1'b0;
        end
        else begin
            enabled <= enabled;
        end
    end

    // bit_write_en
    assign bit_write_en = byte_write_en;

    // load data from shift register to bit_write_i
    reg [7:0] shift_register;
    assign bit_write_i = shift_register[7];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_register <= 8'b0000_0000;
        end
        else if (~enabled) begin
            shift_register <= byte_write_i;
        end
        else if (bit_write_finish) begin
            shift_register <= {shift_register[6:0], 1'b0};
        end
        else begin
            shift_register <= shift_register;
        end
    end

    // byte_write_finish, when 8-bit data writing finished
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_write_finish <= 1'b0;
        end
        else if (bit_write_finish && (counter == 3'b111)) begin
            byte_write_finish <= 1'b1;
        end
        else begin
            byte_write_finish <= 1'b0;
        end
    end
endmodule
