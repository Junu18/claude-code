`timescale 1ns / 1ps

module fnd_controller (
    input  logic        clk,
    input  logic        reset,
    input  logic [13:0] counter,
    output logic [ 3:0] fnd_com,
    output logic [ 7:0] fnd_data
);

    logic tick_1khz;
    logic [1:0] w_sel;
    logic [3:0] w_digit_1, w_digit_10, w_digit_100, w_digit_1000;
    logic [3:0] w_bcd;

    clk_div U_CLK_DIV (
        .clk(clk),
        .reset(reset),
        .tick_1khz(tick_1khz)
    );

    counter_4 U_COUNTER_4 (
        .clk(clk),
        .i_tick(tick_1khz),
        .reset(reset),
        .sel(w_sel)
    );

    decoder_2x4 U_DECODER_2x4 (
        .sel(w_sel),
        .fnd_com(fnd_com)
    );

    digit_spliter U_DIGIT_SPLITER (
        .counter(counter),
        .digit_1(w_digit_1),
        .digit_10(w_digit_10),
        .digit_100(w_digit_100),
        .digit_1000(w_digit_1000)
    );

    mux_4x1 U_MUX_4x1 (
        .sel(w_sel),
        .digit_1(w_digit_1),
        .digit_10(w_digit_10),
        .digit_100(w_digit_100),
        .digit_1000(w_digit_1000),
        .bcd(w_bcd)
    );

    bcd_decoder U_BCD_DECODER (
        .bcd(w_bcd),
        .fnd_data(fnd_data)
    );

endmodule

//===========================================
// Clock Divider: 100MHz -> 1kHz
//===========================================
module clk_div (
    input  logic clk,
    input  logic reset,
    output logic tick_1khz
);

    parameter F_COUNT = 100_000_000 / 1_000;
    logic [$clog2(F_COUNT)-1 : 0] count_reg;
    logic tick_reg;
    assign tick_1khz = tick_reg;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            count_reg <= 0;
            tick_reg  <= 0;
        end else begin
            if (count_reg == F_COUNT - 1) begin
                count_reg <= 0;
                tick_reg  <= 1;
            end else begin
                count_reg <= count_reg + 1;
                tick_reg  <= 0;
            end
        end
    end
endmodule

//===========================================
// Counter: 2-bit counter for FND multiplexing
//===========================================
module counter_4 (
    input  logic       clk,
    input  logic       i_tick,
    input  logic       reset,
    output logic [1:0] sel
);

    logic [1:0] counter;
    assign sel = counter;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            counter <= 0;
        end else begin
            if (i_tick) begin
                counter <= counter + 1;
            end
        end
    end

endmodule

//===========================================
// Decoder: 2-to-4 for FND common selection
//===========================================
module decoder_2x4 (
    input  logic [1:0] sel,
    output logic [3:0] fnd_com
);

    always_comb begin
        case (sel)
            2'b00:   fnd_com = 4'b1110;
            2'b01:   fnd_com = 4'b1101;
            2'b10:   fnd_com = 4'b1011;
            2'b11:   fnd_com = 4'b0111;
            default: fnd_com = 4'b1111;
        endcase
    end

endmodule

//===========================================
// Digit Splitter: 14-bit -> 4 decimal digits
//===========================================
module digit_spliter (
    input  logic [13:0] counter,
    output logic [ 3:0] digit_1,
    output logic [ 3:0] digit_10,
    output logic [ 3:0] digit_100,
    output logic [ 3:0] digit_1000
);

    assign digit_1    = counter % 10;
    assign digit_10   = (counter / 10) % 10;
    assign digit_100  = (counter / 100) % 10;
    assign digit_1000 = (counter / 1000) % 10;

endmodule

//===========================================
// 4-to-1 Multiplexer
//===========================================
module mux_4x1 (
    input  logic [1:0] sel,
    input  logic [3:0] digit_1,
    input  logic [3:0] digit_10,
    input  logic [3:0] digit_100,
    input  logic [3:0] digit_1000,
    output logic [3:0] bcd
);

    always_comb begin
        case (sel)
            2'b00:   bcd = digit_1;
            2'b01:   bcd = digit_10;
            2'b10:   bcd = digit_100;
            2'b11:   bcd = digit_1000;
            default: bcd = digit_1;
        endcase
    end

endmodule

//===========================================
// BCD to 7-segment Decoder
//===========================================
module bcd_decoder (
    input  logic [3:0] bcd,
    output logic [7:0] fnd_data
);

    always_comb begin
        case (bcd)
            4'h0: fnd_data = 8'hc0;  // 0
            4'h1: fnd_data = 8'hF9;
            4'h2: fnd_data = 8'hA4;
            4'h3: fnd_data = 8'hB0;
            4'h4: fnd_data = 8'h99;
            4'h5: fnd_data = 8'h92;
            4'h6: fnd_data = 8'h82;
            4'h7: fnd_data = 8'hF8;
            4'h8: fnd_data = 8'h80;
            4'h9: fnd_data = 8'h90;  // 9
            4'ha: fnd_data = 8'h88;
            4'hb: fnd_data = 8'h83;
            4'hc: fnd_data = 8'hc6;
            4'hd: fnd_data = 8'ha1;
            4'he: fnd_data = 8'h7f;  // dot display
            4'hf: fnd_data = 8'hff;  // all off
            default: fnd_data = 8'hff;
        endcase
    end

endmodule
