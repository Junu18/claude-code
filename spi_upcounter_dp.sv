`timescale 1ns / 1ps

module spi_upcounter_dp (
    input  logic        clk,
    input  logic        reset,
    input  logic        i_o_runstop,
    input  logic        i_o_clear,
    output logic [13:0] counter
);

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 14'd0;
        end else if (i_o_clear) begin
            counter <= 14'd0;
        end else if (i_o_runstop) begin
            // run 상태일 때만 카운터 증가
            // stop일 때는 i_o_runstop = 0 이기 때문에 카운터는 정지
            counter <= counter + 1;
        end
    end

endmodule
