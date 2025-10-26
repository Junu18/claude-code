`timescale 1ns / 1ps

module APB_Master (
    // global signals
    input  logic        PCLK,
    input  logic        PRESET,
    // APB Interface Signals
    output logic [31:0] PADDR,
    output logic        PWRITE,
    output logic        PENABLE,
    output logic [31:0] PWDATA,
    // PSEL signals
    output logic        PSEL_RAM,
    output logic        PSEL_GPO,
    output logic        PSEL_GPI,
    output logic        PSEL_GPIO,
    output logic        PSEL_UART,
    output logic        PSEL_FND,
    // PRDATA signals
    input  logic [31:0] PRDATA_RAM,
    input  logic [31:0] PRDATA_GPO,
    input  logic [31:0] PRDATA_GPI,
    input  logic [31:0] PRDATA_GPIO,
    input  logic [31:0] PRDATA_UART,
    input  logic [31:0] PRDATA_FND,
    // PREADY signals
    input  logic        PREADY_RAM,
    input  logic        PREADY_GPO,
    input  logic        PREADY_GPI,
    input  logic        PREADY_GPIO,
    input  logic        PREADY_UART,
    input  logic        PREADY_FND,
    // Internal Interface Signals
    input  logic        transfer,
    output logic        ready,
    input  logic        write,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
    logic [5:0] pselx;
    logic [2:0] mux_sel;
    logic decoder_en;
    logic [31:0] temp_addr_reg, temp_addr_next, temp_wdata_reg, temp_wdata_next;
    logic temp_write_reg, temp_write_next;

    assign PSEL_RAM  = pselx[0];
    assign PSEL_GPO  = pselx[1];
    assign PSEL_GPI  = pselx[2];
    assign PSEL_GPIO = pselx[3];
    assign PSEL_UART = pselx[4];
    assign PSEL_FND  = pselx[5];

    typedef enum {
        IDLE,
        SETUP,
        ACCESS
    } apb_state_e;

    apb_state_e state, state_next;

    always_ff @(posedge PCLK, posedge PRESET) begin
        if (PRESET) begin
            state          <= IDLE;
            temp_addr_reg  <= 0;
            temp_wdata_reg <= 0;
            temp_write_reg <= 0;
        end else begin
            state          <= state_next;
            temp_addr_reg  <= temp_addr_next;
            temp_wdata_reg <= temp_wdata_next;
            temp_write_reg <= temp_write_next;
        end
    end

    always_comb begin
        state_next      = state;
        decoder_en      = 1'b0;
        PENABLE         = 1'b0;
        temp_addr_next  = temp_addr_reg;
        temp_wdata_next = temp_wdata_reg;
        temp_write_next = temp_write_reg;
        PADDR           = temp_addr_reg;
        PWRITE          = temp_write_reg;
        PWDATA          = temp_wdata_reg;
        case (state)
            IDLE: begin
                decoder_en = 1'b0;
                if (transfer) begin
                    state_next = SETUP;
                    temp_addr_next = addr;  // latching
                    temp_wdata_next = wdata;
                    temp_write_next = write;
                end
            end
            SETUP: begin
                decoder_en = 1'b1;
                PENABLE    = 1'b0;
                PADDR      = temp_addr_reg;
                PWRITE     = temp_write_reg;
                state_next = ACCESS;
                if (temp_write_reg) begin
                    PWDATA = temp_wdata_reg;
                end
            end
            ACCESS: begin
                decoder_en = 1'b1;
                PENABLE    = 1'b1;
                if (ready) begin                   
                state_next = IDLE;
                decoder_en = 1'b0;
                PENABLE    = 1'b0;                
                end
            end
        endcase
    end

    APB_Decoder U_APB_Decoder (
        .en     (decoder_en),
        .sel    (temp_addr_reg),
        .y      (pselx),
        .mux_sel(mux_sel)
    );

    APB_Mux U_APB_Mux (
        .sel   (mux_sel),
        .rdata0(PRDATA_RAM),
        .rdata1(PRDATA_GPO),
        .rdata2(PRDATA_GPI),
        .rdata3(PRDATA_GPIO),
        .rdata4(PRDATA_UART),
        .rdata5(PRDATA_FND),
        .ready0(PREADY_RAM),
        .ready1(PREADY_GPO),
        .ready2(PREADY_GPI),
        .ready3(PREADY_GPIO),
        .ready4(PREADY_UART),
        .ready5(PREADY_FND),
        .rdata (rdata),
        .ready (ready)
    );

endmodule

module APB_Decoder (
    input  logic        en,
    input  logic [31:0] sel,
    output logic [ 5:0] y,
    output logic [ 2:0] mux_sel
);
    always_comb begin
        y = 6'b000000;
        if (en) begin
            casex (sel)
                32'h1000_0xxx: y = 6'b000001;
                32'h1000_1xxx: y = 6'b000010;
                32'h1000_2xxx: y = 6'b000100;
                32'h1000_3xxx: y = 6'b001000;
                32'h1000_4xxx: y = 6'b010000;
                32'h1000_5xxx: y = 6'b100000;
                default:       y = 6'b000000;
            endcase
        end
    end

    always_comb begin
        mux_sel = 3'dx;
        if (en) begin
            casex (sel)
                32'h1000_0xxx: mux_sel = 3'd0;
                32'h1000_1xxx: mux_sel = 3'd1;
                32'h1000_2xxx: mux_sel = 3'd2;
                32'h1000_3xxx: mux_sel = 3'd3;
                32'h1000_4xxx: mux_sel = 3'd4;
                32'h1000_5xxx: mux_sel = 3'd5;
                default : mux_sel = 3'd0;
            endcase
        end
    end
endmodule

module APB_Mux (
    input  logic [ 2:0] sel,
    input  logic [31:0] rdata0,
    input  logic [31:0] rdata1,
    input  logic [31:0] rdata2,
    input  logic [31:0] rdata3,
    input  logic [31:0] rdata4,
    input  logic [31:0] rdata5,
    input  logic        ready0,
    input  logic        ready1,
    input  logic        ready2,
    input  logic        ready3,
    input  logic        ready4,
    input  logic        ready5,
    output logic [31:0] rdata,
    output logic        ready
);

    always_comb begin
        rdata = 32'b0;
        case (sel)
            3'd0: rdata = rdata0;
            3'd1: rdata = rdata1;
            3'd2: rdata = rdata2;
            3'd3: rdata = rdata3;
            3'd4: rdata = rdata4;
            3'd5: rdata = rdata5;
        endcase
    end

    always_comb begin
        ready = 1'b0;
        case (sel)
            3'd0: ready = ready0;
            3'd1: ready = ready1;
            3'd2: ready = ready2;
            3'd3: ready = ready3;
            3'd4: ready = ready4;
            3'd5: ready = ready5;
        endcase
    end
endmodule
