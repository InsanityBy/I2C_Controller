/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: scl_generator.v
 * create date: 2023.12.09
 * last modified date: 2023.12.21
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
 * V1.2 - 2023.12.21
 *     refactor: move setting scl_div external
 *               modify scl stretch detect
 */

module scl_generator (
    input clk,
    input rst_n,
    // control
    input scl_en,
    input scl_wait,  // stretch scl to wait, can ONLY be set when scl low
    input [7:0] scl_div,  // 1~255, f_{scl_o} = f_{clk}/(2*(scl_div+1))
    // status
    output reg scl_stretched,  // scl is stretched by other devices
    // I2C
    input scl_i,
    output reg scl_o
);

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

    // detect scl being stretched
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_stretched <= 1'b0;
        end
        else if (scl_o != scl_i) begin
            scl_stretched <= 1'b1;
        end
        else begin
            scl_stretched <= 1'b0;
        end
    end

endmodule
