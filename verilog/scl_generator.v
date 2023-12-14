/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: scl_generator.v
 * create date: 2023.12.09
 * last modified date: 2023.12.12
 *
 * design name: I2C_controller
 * module name: scl_generator
 * description:
 *     generate scl in master mode, support clock synchronization and stretch
 *     f_{scl_o} = f_{clk}/(2*(scl_div+1))
 * dependencies:
 *     (none)
 *
 * revision:
 * V1.0 - 2023.12.11
 *     initial version
 * V1.1 - 2023.12.12
 *     rename signals
 */

module scl_generator (
    input clk,
    input rst_n,
    // control
    input scl_en,
    input scl_wait,  // stretch scl to wait, can ONLY be set when scl low
    input [7:0] set_scl_div,  // 1~255, f_{scl_o} = f_{clk}/(2*(scl_div+1))
    // status
    output reg [7:0] scl_div,  // current scl_div value
    output reg scl_stretched,
    // I2C
    input scl_i,
    output reg scl_o
);

    // set scl divisor
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_div <= 8'h01;
        end
        else if (!scl_en) begin  // scl_div can ONLY be set when module disabled
            if (set_scl_div == 8'b0) begin
                scl_div <= 8'h01;
            end
            else begin
                scl_div <= set_scl_div;
            end
        end
        else begin
            scl_div <= scl_div;
        end
    end

    // counter to divide clock and generate scl_o
    reg [8:0] scl_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_cnt <= 9'b0;
        end
        else if (!scl_en) begin  // reset when module disabled
            scl_cnt <= 9'b0;
        end
        else if (scl_wait || scl_stretched) begin  // stop to wait
            scl_cnt <= scl_cnt;
        end
        else if (scl_cnt == {1'b0, scl_div}) begin  // scl_o falls
            scl_cnt <= 9'h100;
        end
        else if (scl_cnt == {1'b1, scl_div}) begin  // scl_o rises
            scl_cnt <= 9'b0;
        end
        else begin
            scl_cnt <= scl_cnt + 1;
        end
    end

    // scl_o, combinational circuit
    always @(*) begin
        scl_o = ~scl_cnt[8];
    end

    // detect scl_o rising edge
    reg scl_last, scl_rise;
    // save scl_o last state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_last <= 1'b1;
        end
        else begin
            scl_last <= scl_o;
        end
    end
    // scl_o rising edge: 0 -> 1
    always @(*) begin
        scl_rise = (~scl_last) && scl_o;
    end

    // finite state machine to check clock stretch
    // state encode
    parameter IDLE = 1'b0;
    parameter WAIT = 1'b1;

    // state variable
    reg state_next, state_current;

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
                if (scl_rise && (~scl_i)) begin  // scl is stretched
                    state_next = WAIT;
                end
                else begin
                    state_next = IDLE;
                end
            end
            WAIT: begin
                if (scl_i) begin  // wait till scl_i released
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

    // state output, combinational circuit
    always @(*) begin
        case (state_current)
            IDLE: begin
                scl_stretched = 1'b0;
            end
            WAIT: begin
                scl_stretched = 1'b1;
            end
            default: begin
                scl_stretched = 1'b0;
            end
        endcase
    end

endmodule
