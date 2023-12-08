/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: clock_divisor.v
 * create date: 2023.12.09
 * last modified date: 2023.12.09
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
 */

module clock_divisor (
    input clk_i,
    input rst_n,
    input clk_en,
    input [3:0] clk_div,  // 0~15, f_{clk_o} = f_{clk_i}/(2*(clk_div+1))
    output reg [3:0] clk_div_cur,  // current clk_div value
    output reg clk_o
);

    // set clock divisor
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            clk_div_cur <= 4'b0;
        end
        else if (!clk_en) begin  // clk_div can ONLY be set when module disabled
            clk_div_cur <= clk_div;
        end
        else begin
            clk_div_cur <= clk_div_cur;
        end
    end

    // counter to divide clock
    reg [3:0] clk_cnt;
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 4'b0;
            clk_o   <= 1'b0;
        end
        else if (clk_en) begin
            if (clk_cnt == clk_div_cur) begin
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
