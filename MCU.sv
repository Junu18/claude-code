`timescale 1ns / 1ps

module MCU (
    input  logic       clk,
    input  logic       reset,
    // External Port
    output logic [7:0] gpo,
    input  logic [7:0] gpi,
    inout  logic [7:0] gpio,
    output logic [3:0] fnd_com,
    output logic [7:0] fnd_data,

    output logic tx,
    input  logic rx
);

    wire         PCLK = clk;
    wire         PRESET = reset;
    // Internal Interface Signals
    logic        transfer;
    logic        ready;
    logic        write;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;

    logic [31:0] instrCode;
    logic [31:0] instrMemAddr;
    logic        busWe;
    logic [31:0] busAddr;
    logic [31:0] busWData;
    logic [31:0] busRData;

    // APB Interface Signals
    logic [31:0] PADDR;
    logic        PWRITE;
    logic        PENABLE;
    logic [31:0] PWDATA;

    logic        PSEL_RAM;
    logic        PSEL_GPO;
    logic        PSEL_GPI;
    logic        PSEL_GPIO;
    logic        PSEL_UART;
    logic        PSEL_FND;

    logic [31:0] PRDATA_RAM;
    logic [31:0] PRDATA_GPO;
    logic [31:0] PRDATA_GPI;
    logic [31:0] PRDATA_GPIO;
    logic [31:0] PRDATA_UART;
    logic [31:0] PRDATA_FND;

    logic        PREADY_RAM;
    logic        PREADY_GPO;
    logic        PREADY_GPI;
    logic        PREADY_GPIO;
    logic        PREADY_UART;
    logic        PREADY_FND;

    assign write = busWe;
    assign addr = busAddr;
    assign wdata = busWData;
    assign busRData = rdata;

    ROM U_ROM (
        .addr(instrMemAddr),
        .data(instrCode)
    );

    CPU_RV32I U_RV32I (.*);

    APB_Master U_APB_Master (
        .*,
        .PSEL_RAM(PSEL_RAM),
        .PSEL_GPO(PSEL_GPO),
        .PSEL_GPI(PSEL_GPI),
        .PSEL_GPIO(PSEL_GPIO),
        .PSEL_UART(PSEL_UART),
        .PSEL_FND(PSEL_FND),
        .PRDATA_RAM(PRDATA_RAM),
        .PRDATA_GPO(PRDATA_GPO),
        .PRDATA_GPI(PRDATA_GPI),
        .PRDATA_GPIO(PRDATA_GPIO),
        .PRDATA_UART(PRDATA_UART),
        .PRDATA_FND(PRDATA_FND),
        .PREADY_RAM(PREADY_RAM),
        .PREADY_GPO(PREADY_GPO),
        .PREADY_GPI(PREADY_GPI),
        .PREADY_GPIO(PREADY_GPIO),
        .PREADY_UART(PREADY_UART),
        .PREADY_FND(PREADY_FND)
    );

    RAM U_RAM (
        .*,
        .PSEL  (PSEL_RAM),
        .PRDATA(PRDATA_RAM),
        .PREADY(PREADY_RAM)
    );

    GPO_Periph U_GPO_Periph (
        .*,
        .PSEL  (PSEL_GPO),
        .PRDATA(PRDATA_GPO),
        .PREADY(PREADY_GPO)
    );

    GPI_Periph U_GPI_Periph (
        .*,
        .PSEL  (PSEL_GPI),
        .PRDATA(PRDATA_GPI),
        .PREADY(PREADY_GPI)
    );

    GPIO_Periph U_GPIO_Periph (
        .*,
        .PSEL  (PSEL_GPIO),
        .PRDATA(PRDATA_GPIO),
        .PREADY(PREADY_GPIO)
    );

    UART_Periph U_UART_FIFO_Periph (
        .*,
        .PSEL(PSEL_UART),
        .PRDATA(PRDATA_UART),
        .PREADY(PREADY_UART),
        .tx(tx),
        .rx(rx)
    ); 

    FND_Periph u_FND_Periph (
    .PCLK(PCLK),
    .PRESET(PRESET),
    .PADDR(PADDR[4:0]),
    .PSEL(PSEL_FND),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PWDATA(PWDATA),
    .PRDATA(PRDATA_FND),
    .PREADY(PREADY_FND),
    .fnd_com(fnd_com),
    .fnd_data(fnd_data)
    );

    // FND_Periph u_FND_Periph (
    //     .*,
    //     .PSEL  (PSEL_FND),
    //     .PRDATA(PRDATA_FND),
    //     .PREADY(PREADY_FND)
    // );


endmodule
