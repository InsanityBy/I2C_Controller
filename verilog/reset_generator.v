/*
 * company: Peking University
 * author: insanity_by@pku.edu.cn
 *
 * file name: reset_generator.v
 * create date: 2023.12.09
 * last modified date: 2023.12.09
 *
 * design name: I2C_controller
 * module name: reset_generator
 * description:
 *     generate reset signal for async reset and sync release
 * dependencies:
 *     (none)
 *
 * revision:
 * V1.0 - 2023.12.09
 *     initial version
 */

module reset_generator (
    input clk,
    input rst_n,
    output reg rst_sync_n  // async reset and sync release
);

    reg rst_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_reg <= 1'b0;
        end
        else begin
            rst_reg <= 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_sync_n <= 1'b0;
        end
        else begin
            rst_sync_n <= rst_reg;
        end
    end

endmodule
