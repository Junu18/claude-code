`timescale 1ns / 1ps

module spi_upcounter_cu (
    //global signals
    input  logic clk,
    input  logic reset,
    // btn signals
    input  logic i_runstop,
    input  logic i_clear,
    output logic o_runstop,
    output logic o_clear
);

    typedef enum {
        STOP,
        RUN,
        CLEAR
    } state_t;

    state_t state, state_next;
    logic runstop_reg, runstop_next;
    logic clear_reg, clear_next;

    assign o_runstop = runstop_reg;
    assign o_clear   = clear_reg;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            state       <= STOP;
            runstop_reg <= 1'b0;
            clear_reg   <= 1'b0;
        end else begin
            state       <= state_next;
            runstop_reg <= runstop_next;
            clear_reg   <= clear_next;
        end
    end

    always_comb begin
        state_next   = state;
        runstop_next = runstop_reg;
        clear_next   = clear_reg;

        case (state)
            STOP: begin
                runstop_next = 1'b0;
                clear_next   = 1'b0;
                if (i_clear) begin
                    state_next = CLEAR;
                end else if (i_runstop) begin
                    // 버튼 누르면 RUN으로 전환 (레벨 방식)
                    state_next = RUN;
                end
            end

            RUN: begin
                runstop_next = 1'b1;
                if (i_clear) begin
                    state_next = CLEAR;
                end else if (!i_runstop) begin
                    // 버튼 떼면 STOP으로 전환 (레벨 방식)
                    state_next = STOP;
                end
            end

            CLEAR: begin
                clear_next = 1'b1;
                if (!i_clear) begin
                    // 버튼 떼면 STOP으로 전환
                    state_next = STOP;
                end
            end
        endcase
    end
endmodule
