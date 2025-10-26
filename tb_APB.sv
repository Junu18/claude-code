`timescale 1ns / 1ps

//=============================================================
// APB-UART Interface
//=============================================================
interface APB_UART_IF(input logic PCLK);
    logic        PRESET;
    logic [3:0]  PADDR;
    logic [31:0] PWDATA;
    logic        PWRITE;
    logic        PENABLE;
    logic        PSEL;
    logic [31:0] PRDATA;
    logic        PREADY;
    logic        tx;
    logic        rx;
endinterface


//=============================================================
// Transaction Class
//=============================================================
class transaction;
    rand logic [3:0]  PADDR;
    rand logic [31:0] PWDATA;
    rand logic        PWRITE;
    rand logic        PENABLE;
    rand logic        PSEL;

    logic [31:0] PRDATA;
    logic        PREADY;
    logic        tx;
    logic        rx;

    // Valid APB address range (UART registers)
    constraint c_paddr { PADDR inside {4'h0, 4'h4, 4'h8, 4'hC}; }

    task display(string name);
        $display("[%0t][%s] PADDR=%h PWDATA=%h PWRITE=%b PENABLE=%b PSEL=%b PRDATA=%h PREADY=%b",
                 $time, name, PADDR, PWDATA, PWRITE, PENABLE, PSEL, PRDATA, PREADY);
    endtask
endclass


//=============================================================
// Generator Class
//=============================================================
class generator;
    mailbox #(transaction) gen2drv;
    event drv_done;

    function new(mailbox#(transaction) gen2drv, event drv_done);
        this.gen2drv = gen2drv;
        this.drv_done = drv_done;
    endfunction

    task run(int repeat_count);
        transaction tr;
        repeat (repeat_count) begin
            tr = new();
            if (!tr.randomize()) $error("Randomization failed!");
            tr.display("GEN");
            gen2drv.put(tr);
            @(drv_done);
        end
    endtask
endclass


//=============================================================
// Driver Class
//=============================================================
class driver;
    virtual APB_UART_IF vif;
    mailbox #(transaction) gen2drv;
    event drv_done;

    function new(mailbox#(transaction) gen2drv, virtual APB_UART_IF vif, event drv_done);
        this.vif = vif;
        this.gen2drv = gen2drv;
        this.drv_done = drv_done;
    endfunction

    task run();
        transaction tr;
        forever begin
            gen2drv.get(tr);
            tr.display("DRV");

            // --- Setup phase
            vif.PADDR   <= tr.PADDR;
            vif.PWDATA  <= tr.PWDATA;
            vif.PWRITE  <= tr.PWRITE;
            vif.PSEL    <= 1'b1;
            vif.PENABLE <= 1'b0;

            @(posedge vif.PCLK);

            // --- Access phase
            vif.PENABLE <= 1'b1;

            // Wait until slave asserts PREADY
            wait (vif.PREADY == 1'b1);
            @(posedge vif.PCLK);

            // --- Deassert signals
            vif.PSEL    <= 1'b0;
            vif.PENABLE <= 1'b0;

            // notify generator
            -> drv_done;
        end
    endtask
endclass


//=============================================================
// Monitor Class
//=============================================================
class monitor;
    virtual APB_UART_IF vif;
    mailbox #(transaction) mon2scb;

    function new(mailbox#(transaction) mon2scb, virtual APB_UART_IF vif);
        this.vif = vif;
        this.mon2scb = mon2scb;
    endfunction

    task run();
        transaction tr;
        forever begin
            @(posedge vif.PREADY);
            tr = new();
            tr.PADDR   = vif.PADDR;
            tr.PWDATA  = vif.PWDATA;
            tr.PWRITE  = vif.PWRITE;
            tr.PENABLE = vif.PENABLE;
            tr.PSEL    = vif.PSEL;
            tr.PRDATA  = vif.PRDATA;
            tr.PREADY  = vif.PREADY;
            tr.tx      = vif.tx;
            tr.rx      = vif.rx;
            tr.display("MON");
            mon2scb.put(tr);
        end
    endtask
endclass


//=============================================================
// Scoreboard Class
//=============================================================
class scoreboard;
    mailbox #(transaction) mon2scb;

    function new(mailbox#(transaction) mon2scb);
        this.mon2scb = mon2scb;
    endfunction

    task run();
        transaction tr;
        forever begin
            mon2scb.get(tr);
            tr.display("SCB");
            if (tr.PWRITE)
                $display("[SCB] WRITE OK : Addr=%h, Data=%h", tr.PADDR, tr.PWDATA);
            else
                $display("[SCB] READ  OK : Addr=%h, Data=%h", tr.PADDR, tr.PRDATA);
        end
    endtask
endclass


//=============================================================
// Top-level Testbench
//=============================================================
module tb_UART_Periph;

    // ---------------------------------------------------------
    // Clock Generation
    // ---------------------------------------------------------
    logic PCLK = 0;
    always #5 PCLK = ~PCLK;  // 100MHz

    // ---------------------------------------------------------
    // Interface & DUT
    // ---------------------------------------------------------
    APB_UART_IF intf(PCLK);

    UART_Periph dut (
        .PCLK   (intf.PCLK),
        .PRESET (intf.PRESET),
        .PADDR  (intf.PADDR),
        .PWDATA (intf.PWDATA),
        .PWRITE (intf.PWRITE),
        .PENABLE(intf.PENABLE),
        .PSEL   (intf.PSEL),
        .PRDATA (intf.PRDATA),
        .PREADY (intf.PREADY),
        .tx     (intf.tx),
        .rx     (intf.rx)
    );

    // ---------------------------------------------------------
    // Mailboxes & Components
    // ---------------------------------------------------------
    mailbox #(transaction) gen2drv = new();
    mailbox #(transaction) mon2scb = new();
    event drv_done;

    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard scb;

    // ---------------------------------------------------------
    // Reset Sequence + Simulation Run
    // ---------------------------------------------------------
    initial begin
        // Initial signal setup
        intf.PRESET = 1'b1;
        intf.PADDR  = '0;
        intf.PWDATA = '0;
        intf.PWRITE = 1'b0;
        intf.PENABLE= 1'b0;
        intf.PSEL   = 1'b0;
        intf.rx     = 1'b1; // idle UART line = high
        intf.tx     = 1'b1;

        // Release reset after few cycles
        repeat (5) @(posedge PCLK);
        intf.PRESET = 1'b0;
        $display("[%0t] RESET DEASSERTED", $time);

        // Component instantiation
        gen = new(gen2drv, drv_done);
        drv = new(gen2drv, intf, drv_done);
        mon = new(mon2scb, intf);
        scb = new(mon2scb);

        // Parallel processes
        fork
            gen.run(50);
            drv.run();
            mon.run();
            scb.run();
        join_none

        #10000;
        $finish;
    end

endmodule
