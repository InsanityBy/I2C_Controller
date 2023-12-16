`timescale 1ns/10ps

module testbench();
    reg clk, rst_n, go_test;
    wire data_test, load_test, finish_test, error_test, scl_test;
    reg sda_test;
    
    // test data to write
    parameter test_data_value = 32'h1357_9bdf;
    // test number
    parameter test_number = 32;
    reg [4:0] current_test_number;
    reg [4:0] error_count;
    
    // instantiate the submodule
    I2C_master_read_byte test_module(
    .clock(clk),
    .reset_n(rst_n),
    .go(go_test),
    .data(data_test),
    .load(load_test),
    .finish(finish_test),
    .error(error_test),
    .scl(scl_test),
    .sda(sda_test)
    );
    
    // use fsdb/vcd or vcd to save wave
    initial begin
        `ifdef fsdbdump
        $display("\n******** fsdb file dump is turned on ******** \n");
        $fsdbDumpfile("wave.fsdb");
        $fsdbDumpvars(0);
        #100000
        $fsdbDumpoff;
        `endif
        `ifdef vcddump
        $display("******** vcd file dump is turned on******** ");
        $dumpfile("wave.vcd");
        $dumpvars(0);
        #100000
        $dumpoff;
        `endif
    end
    
    // generate clock and reset
    initial begin
        clk       = 0;
        rst_n     = 1;
        #10 rst_n = 0;
        #10 rst_n = 1;
        forever
            #10 clk = ~clk;
    end
    
    // detect scl falling edge to change sda
    reg [1:0] scl_state;
    reg detect;
    always @(*) begin
        detect = scl_state[1] && (~scl_state[0]);
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            scl_state <= 2'b00;
        else
            scl_state <= {scl_state[0], scl_test};
    end
    
    // write data to test module
    reg [31:0] data_to_write;
    reg [7:0] last_write;
    always @(*) begin
        sda_test = data_to_write[31];
    end
    // save last data to check
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_write <= 8'h00;
        end
        else if (load_test) begin
            last_write <= {last_write[6:0], sda_test};
        end
        else begin
            last_write <= last_write;
        end
    end
    // load data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_to_write <= test_data_value;
        end
        else if (detect) begin
            data_to_write <= {data_to_write[30:0], data_to_write[31]};
        end
        else begin
            data_to_write <= data_to_write;
        end
    end
    
    // save data
    reg [7:0] data_save;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_save <= 8'h00;
        else if (load_test)
            data_save <= {data_save[6:0], data_test};
        else
            data_save <= data_save;
    end
    
    // start master_read_byte
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            go_test             <= 1'b1;
            current_test_number <= 4'b0000;
            error_count         <= 4'b0000;
        end
        else if (finish_test) begin
            go_test             <= 1'b0;
            current_test_number <= current_test_number + 1;
            if (!error_test) begin
                if (data_save == last_write) begin
                    $display("--%02d--PASS-- write/read: %h/%h", current_test_number, last_write, data_save);
                    error_count <= error_count;
                end
                else begin
                    $display("--%02d--FAIL-- write/read: %b/%b", current_test_number, last_write, data_save);
                    error_count <= error_count + 1;
                end
            end
            else begin
                $display("--%02d--FAIL-- error while reading");
                error_count <= error_count + 1;
            end
        end
        else begin
            go_test             <= 1'b1;
            current_test_number <= current_test_number;
        end
    end
    
    // prompt and log
    initial begin
        $display("******** 'master_read_byte' module test started ********");
        // wait till finished
        wait(current_test_number == test_number - 1);
        #100
        $display("-------------------------------------------------");
        if (error_count == 0) begin
            $display("result: passed with %02d errors in %02d tests", error_count, test_number);
        end
        else begin
            $display("result: failed with %02d errors in %02d tests", error_count, test_number);
        end
        $display("******** 'master_read_byte' module test finished ********");
        $finish;
    end
    
endmodule
