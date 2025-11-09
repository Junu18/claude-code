`timescale 1ns / 1ps

module spi_upcounter_dp (
    input  logic        clk,
    input  logic        reset,
    input  logic        i_o_runstop,
    input  logic        i_o_clear,
    input  logic        tick,          // tick 신호 추가
    output logic [13:0] counter
);

    always_ff @(posedge clk) begin
        if (reset) begin
            counter <= 14'd0;
        end else if (i_o_clear) begin
            counter <= 14'd0;
        end else if (i_o_runstop && tick) begin
            // run 상태 + tick일 때만 카운터 증가 (1초마다 1씩)
            counter <= counter + 1;
        end
    end

endmodule
