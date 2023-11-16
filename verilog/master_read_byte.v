module I2C_master_read_byte (input clock,
                             input reset_n,
                             input go,
                             output data,
                             output reg load,
                             output reg finish,
                             output reg error,
                             input sda,
                             output reg scl);
    
    // instantiate submodule to read 1-bit
    // reg and wire connect to submodule
    reg       read_bit_go;
    wire      read_bit_finish, read_bit_error;
    wire      scl_w;
    
    // connect outputs of the submodule to this module's
    always @(*) begin
        scl  = scl_w;
        load = read_bit_finish; // drive shifter to load each bit data
    end
    
    // synchronize signal to eliminate glitches
    reg read_bit_finish_sync;
    always @(posedge clock) begin
        read_bit_finish_sync <= read_bit_finish;
    end
    
    I2C_master_read_bit read_bit(
    .clock(clock),
    .reset_n(reset_n),
    .go(read_bit_go),
    .data(data),
    .finish(read_bit_finish),
    .error(read_bit_error),
    .sda(sda),
    .scl(scl_w)
    );
    
    // 4-bit counter: drive submodule to read 8 times when reading 1 byte data
    // only increase 1 after reading 1 bit
    reg [3:0] counter;
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n)
            counter <= 4'b0000;
        else if (read_bit_error)
            counter <= 4'b0000;
        else if ((go == 1'b1) && (finish == 1'b0)) begin
            if (read_bit_finish_sync) begin
                if (counter == 4'b1111)
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
    
    // output, sequential circuit to handle race and hazard
    always @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            finish <= 1'b0;
        end
        else begin
            case(counter)
                4'b0000: begin
                    read_bit_go <= 1'b1;
                    finish      <= 1'b0;
                end
                4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101, 4'b0110, 4'b0111: begin
                    read_bit_go <= 1'b1;
                    finish      <= 1'b0;
                end
                4'b1000: begin
                    read_bit_go <= 1'b1;
                    finish      <= 1'b1;
                end
            endcase
        end
    end
endmodule
