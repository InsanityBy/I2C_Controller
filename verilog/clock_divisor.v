/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: clock_divisor.v
 * create date: 2023.12.09
 * last modified date: 2023.12.21
 *
 * design name: I2C_controller
 * module name: clock_divisor
 * description:
 *     divide the high-speed system clock for other parts of the module
 *     f_{clk_o} = f_{clk_i}/(2*(clk_div+1))
 * dependencies:
 *     (none)
 *
 * revision:
 * V1.0 - 2023.12.09
 *     initial version
 * V1.1 - 2023.12.11
 *     group module inputs and outputs
 * V1.2 - 2023.12.12
 *     rename signals
 * V1.3 - 2023.12.21
 *     refactor: move setting clk_div external
 */

module clock_divisor (
    input clk_i,
    input rst_n,
    // control
    input clk_en,
    input [3:0] clk_div,  // 0~15, f_{clk_o} = f_{clk_i}/(2*(clk_div+1))
    // clock output
    output reg clk_o
);

    // counter to divide clock
    reg [3:0] clk_cnt;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 4'b0;
            clk_o   <= 1'b0;
        end
        else if (clk_en) begin
            if (clk_cnt == clk_div) begin
                clk_cnt <= 4'b0;
                clk_o   <= ~clk_o;
            end
            else begin
                clk_cnt <= clk_cnt + 1;
                clk_o   <= clk_o;
            end
        end
        else begin
            clk_cnt <= 4'b0;
            clk_o   <= clk_o;
        end
    end

endmodule
