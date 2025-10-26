`timescale 1ns / 1ps

parameter BAUD_RATE = 9_600;
parameter CLOCK_PERIOD_NS = 10;
parameter CLOCK_PER_BIT = 100_000_000 / BAUD_RATE;
parameter BIT_PERIOD = CLOCK_PER_BIT * CLOCK_PERIOD_NS;

// Interface
interface uart_periph_if;
    // APB Interface
    logic        PCLK;
    logic        PRESET;
    logic [ 3:0] PADDR;
    logic [31:0] PWDATA;
    logic        PWRITE;
    logic        PENABLE;
    logic        PSEL;
    logic [31:0] PRDATA;
    logic        PREADY;

    // UART Interface
    logic        rx;
    logic        tx;

    // Expected data (for checking)
    logic [ 7:0] exp_data;
endinterface

// Transaction class
class transaction;
    rand bit [7:0] data;
    rand bit is_tx;  // 1: TX test, 0: RX test

    bit [7:0] received_data;
    bit [7:0] read_data;

    constraint data_range {
        data inside {[8'h20 : 8'h7E]};  // Printable ASCII
    }

    // Functional Coverage
    covergroup cg_uart_data;
        option.per_instance = 1;

        // Data value coverage
        cp_data: coverpoint data {
            bins low = {[8'h00 : 8'h3F]};
            bins mid = {[8'h40 : 8'h7F]};
            bins high = {[8'h80 : 8'hFF]};
            bins zero = {8'h00};
            bins max = {8'hFF};
        }

        // Direction coverage
        cp_direction: coverpoint is_tx {
            bins tx_test = {1}; bins rx_test = {0};
        }

        // Cross coverage
        cross_data_dir: cross cp_data, cp_direction;

        // Corner cases
        cp_corners: coverpoint data {
            bins corner_cases[] = {8'h00, 8'h01, 8'h7F, 8'h80, 8'hFE, 8'hFF};
        }
    endgroup

    function new();
        cg_uart_data = new();
    endfunction

    function void sample_coverage();
        cg_uart_data.sample();
    endfunction

    function void display(string tag);
        if (is_tx)
            $display(
                "[%0t][%s] TX: send=0x%h recv=0x%h",
                $time,
                tag,
                data,
                received_data
            );
        else
            $display(
                "[%0t][%s] RX: send=0x%h read=0x%h", $time, tag, data, read_data
            );
    endfunction
endclass

// Generator
class generator;
    transaction tr;
    mailbox #(transaction) gen2drv;
    event next_gen;
    int total_count = 0;

    function new(mailbox#(transaction) gen2drv, event next_gen);
        this.gen2drv  = gen2drv;
        this.next_gen = next_gen;
    endfunction

    task run(int count);
        repeat (count) begin
            tr = new();
            assert (tr.randomize())
            else $error("[Gen] Randomization failed!");
            gen2drv.put(tr);
            total_count++;
            $display("[Gen] Generated data=0x%h, is_tx=%0d", tr.data, tr.is_tx);
            @(next_gen);
        end
    endtask
endclass

// Driver
class driver;
    transaction tr;
    mailbox #(transaction) gen2drv;
    virtual uart_periph_if vif;
    event next_gen;
    event next_mon;

    function new(mailbox#(transaction) gen2drv, virtual uart_periph_if vif,
                 event next_gen, event next_mon);
        this.gen2drv = gen2drv;
        this.vif = vif;
        this.next_gen = next_gen;
        this.next_mon = next_mon;
    endfunction

    task reset();
        vif.PCLK = 0;
        vif.PRESET = 1;
        vif.PADDR = 0;
        vif.PWDATA = 0;
        vif.PWRITE = 0;
        vif.PENABLE = 0;
        vif.PSEL = 0;
        vif.rx = 1;
        repeat (10) @(posedge vif.PCLK);
        vif.PRESET = 0;
        repeat (5) @(posedge vif.PCLK);
        $display("[Drv] Reset done");
    endtask

    task apb_write(logic [3:0] addr, logic [31:0] data);
        @(posedge vif.PCLK);
        vif.PSEL = 1;
        vif.PADDR = addr;
        vif.PWDATA = data;
        vif.PWRITE = 1;
        vif.PENABLE = 0;

        @(posedge vif.PCLK);
        vif.PENABLE = 1;

        @(posedge vif.PCLK);
        wait (vif.PREADY == 1);

        @(posedge vif.PCLK);
        vif.PSEL = 0;
        vif.PENABLE = 0;
        vif.PWRITE = 0;
    endtask

    task apb_read(logic [3:0] addr, output logic [31:0] data);
        @(posedge vif.PCLK);
        vif.PSEL = 1;
        vif.PADDR = addr;
        vif.PWRITE = 0;
        vif.PENABLE = 0;

        @(posedge vif.PCLK);
        vif.PENABLE = 1;

        @(posedge vif.PCLK);
        wait (vif.PREADY == 1);
        data = vif.PRDATA;

        @(posedge vif.PCLK);
        vif.PSEL = 0;
        vif.PENABLE = 0;
    endtask

    task uart_send_byte(logic [7:0] data);
        int i;
        // Start bit
        vif.rx = 0;
        #(BIT_PERIOD);

        // Data bits (LSB first)
        for (i = 0; i < 8; i++) begin
            vif.rx = data[i];
            #(BIT_PERIOD);
        end

        // Stop bit
        vif.rx = 1;
        #(BIT_PERIOD);
    endtask

    task run();
        forever begin
            gen2drv.get(tr);

            if (tr.is_tx) begin
                // TX Test: APB Write -> UART TX
                $display("[Drv] TX Test: Writing 0x%h to TDR", tr.data);
                apb_write(4'h8, {24'h0, tr.data});  // TDR offset = 0x08
                vif.exp_data = tr.data;
            end else begin
                // RX Test: UART RX -> APB Read
                $display("[Drv] RX Test: Sending 0x%h via UART", tr.data);
                uart_send_byte(tr.data);
                vif.exp_data = tr.data;

                // Wait for RX to be ready
                repeat (100) @(posedge vif.PCLK);
            end

            ->next_mon;
        end
    endtask
endclass

// Monitor
class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb;
    virtual uart_periph_if vif;
    event next_mon;

    logic [7:0] uart_received;

    function new(mailbox#(transaction) mon2scb, virtual uart_periph_if vif,
                 event next_mon);
        this.mon2scb = mon2scb;
        this.vif = vif;
        this.next_mon = next_mon;
    endfunction

    task uart_receive_byte(output logic [7:0] data);
        int i;

        // Wait for start bit
        wait (vif.tx == 0);

        // Wait to middle of start bit
        #(BIT_PERIOD / 2);

        if (vif.tx != 0) $error("[Mon] Start bit error!");

        // Sample data bits
        for (i = 0; i < 8; i++) begin
            #(BIT_PERIOD);
            data[i] = vif.tx;
        end

        // Check stop bit
        #(BIT_PERIOD);
        if (vif.tx != 1) $error("[Mon] Stop bit error!");

        #(BIT_PERIOD / 2);
    endtask

    task run();
        forever begin
            @(next_mon);
            tr = new();

            if (tr.is_tx) begin
                // Monitor TX pin
                uart_receive_byte(uart_received);
                tr.received_data = uart_received;
                tr.data = vif.exp_data;
                $display("[Mon] TX: Received 0x%h from UART tx pin",
                         uart_received);
            end else begin
                // Read from APB RDR
                logic [31:0] read_val;
                repeat (50) @(posedge vif.PCLK);  // Wait for RX done

                // Check USR[0] (RX_READY)
                logic [31:0] status;

                @(posedge vif.PCLK);
                vif.PSEL = 1;
                vif.PADDR = 4'h0;
                vif.PWRITE = 0;
                vif.PENABLE = 0;
                @(posedge vif.PCLK);
                vif.PENABLE = 1;
                @(posedge vif.PCLK);
                wait (vif.PREADY == 1);
                status = vif.PRDATA;
                @(posedge vif.PCLK);
                vif.PSEL = 0;
                vif.PENABLE = 0;

                $display("[Mon] USR = 0x%h (RX_READY=%b)", status, status[0]);

                // Read RDR
                @(posedge vif.PCLK);
                vif.PSEL = 1;
                vif.PADDR = 4'hC;  // RDR offset = 0x0C
                vif.PWRITE = 0;
                vif.PENABLE = 0;
                @(posedge vif.PCLK);
                vif.PENABLE = 1;
                @(posedge vif.PCLK);
                wait (vif.PREADY == 1);
                read_val = vif.PRDATA;
                @(posedge vif.PCLK);
                vif.PSEL = 0;
                vif.PENABLE = 0;

                tr.read_data = read_val[7:0];
                tr.data = vif.exp_data;
                $display("[Mon] RX: Read 0x%h from APB RDR", tr.read_data);
            end

            mon2scb.put(tr);
        end
    endtask
endclass

// Scoreboard
class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb;
    event next_gen;

    int pass_count = 0;
    int fail_count = 0;

    // TX/RX 분리 카운트
    int tx_pass_count = 0;
    int tx_fail_count = 0;
    int rx_pass_count = 0;
    int rx_fail_count = 0;

    // Protocol Coverage
    covergroup cg_apb_protocol @(posedge next_gen);
        option.per_instance = 1;

        cp_addr: coverpoint tr.is_tx {
            bins tdr_write = {1};  // TDR write (0x8)
            bins rdr_read = {0};  // RDR read (0xC)
        }
    endgroup

    // Status register coverage
    bit usr_rx_ready = 0;
    bit usr_tx_ready = 0;
    bit usr_tx_empty = 0;
    bit usr_rx_full  = 0;

    covergroup cg_status;
        option.per_instance = 1;

        cp_rx_ready: coverpoint usr_rx_ready;
        cp_tx_ready: coverpoint usr_tx_ready;
        cp_tx_empty: coverpoint usr_tx_empty;
        cp_rx_full: coverpoint usr_rx_full;

        // State combinations
        cross_status: cross cp_rx_ready, cp_tx_ready;
    endgroup

    function new(mailbox#(transaction) mon2scb, event next_gen);
        this.mon2scb = mon2scb;
        this.next_gen = next_gen;
        cg_apb_protocol = new();
        cg_status = new();
    endfunction

    task run();
        forever begin
            mon2scb.get(tr);

            // Sample coverage
            tr.sample_coverage();
            cg_status.sample();

            if (tr.is_tx) begin
                if (tr.data == tr.received_data) begin
                    $display("[Scb] TX PASS: 0x%h == 0x%h", tr.data,
                             tr.received_data);
                    pass_count++;
                    tx_pass_count++;
                end else begin
                    $display("[Scb] TX FAIL: Expected=0x%h, Got=0x%h", tr.data,
                             tr.received_data);
                    fail_count++;
                    tx_fail_count++;
                end
            end else begin
                if (tr.data == tr.read_data) begin
                    $display("[Scb] RX PASS: 0x%h == 0x%h", tr.data,
                             tr.read_data);
                    pass_count++;
                    rx_pass_count++;
                end else begin
                    $display("[Scb] RX FAIL: Expected=0x%h, Got=0x%h", tr.data,
                             tr.read_data);
                    fail_count++;
                    rx_fail_count++;
                end
            end

            ->next_gen;
        end
    endtask

    function void report_coverage();
        real cov_percent;

        $display("\n=====================================");
        $display("======== COVERAGE REPORT ============");

        cov_percent = $get_coverage();
        $display("Overall Coverage: %.2f%%", cov_percent);

        $display("\nData Coverage:");
        $display("  Total: %.2f%%", tr.cg_uart_data.get_coverage());

        $display("\nProtocol Coverage:");
        $display("  Total: %.2f%%", cg_apb_protocol.get_coverage());

        $display("\nStatus Coverage:");
        $display("  Total: %.2f%%", cg_status.get_coverage());

        $display("=====================================\n");
    endfunction
endclass

// Environment
class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    mailbox #(transaction) gen2drv;
    mailbox #(transaction) mon2scb;
    event next_gen;
    event next_mon;

    virtual uart_periph_if vif;

    function new(virtual uart_periph_if vif);
        this.vif = vif;
        gen2drv = new();
        mon2scb = new();
        gen = new(gen2drv, next_gen);
        drv = new(gen2drv, vif, next_gen, next_mon);
        mon = new(mon2scb, vif, next_mon);
        scb = new(mon2scb, next_gen);
    endfunction

    task reset();
        drv.reset();
    endtask

    task run(int count);
        fork
            gen.run(count);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #100_000;
        report();
    endtask

    task report();
        $display("\n=====================================");
        $display("========== TEST REPORT ==============");
        $display("=====================================");
        $display("Total Tests : %4d", gen.total_count);
        $display("Pass Tests  : %4d", scb.pass_count);
        $display("Fail Tests  : %4d", scb.fail_count);
        $display("-------------------------------------");
        $display("TX Path Tests:");
        $display("  TX Pass   : %4d", scb.tx_pass_count);
        $display("  TX Fail   : %4d", scb.tx_fail_count);
        $display("  TX Total  : %4d", scb.tx_pass_count + scb.tx_fail_count);
        $display("-------------------------------------");
        $display("RX Path Tests:");
        $display("  RX Pass   : %4d", scb.rx_pass_count);
        $display("  RX Fail   : %4d", scb.rx_fail_count);
        $display("  RX Total  : %4d", scb.rx_pass_count + scb.rx_fail_count);
        $display("=====================================");

        if (scb.fail_count == 0) begin
            $display("========== ALL TESTS PASSED =========");
            $display("  TX Path: %0d/%0d PASSED", scb.tx_pass_count,
                     scb.tx_pass_count + scb.tx_fail_count);
            $display("  RX Path: %0d/%0d PASSED", scb.rx_pass_count,
                     scb.rx_pass_count + scb.rx_fail_count);
        end else begin
            $display("========== SOME TESTS FAILED ========");
            if (scb.tx_fail_count > 0)
                $display("  TX Path: %0d FAILURES", scb.tx_fail_count);
            if (scb.rx_fail_count > 0)
                $display("  RX Path: %0d FAILURES", scb.rx_fail_count);
        end

        $display("=====================================");

        // Coverage report
        scb.report_coverage();
    endtask
endclass

// Testbench Top
module tb_UART_Periph;
    uart_periph_if vif ();
    environment env;

    // DUT
    UART_Periph dut (
        .PCLK   (vif.PCLK),
        .PRESET (vif.PRESET),
        .PADDR  (vif.PADDR),
        .PWDATA (vif.PWDATA),
        .PWRITE (vif.PWRITE),
        .PENABLE(vif.PENABLE),
        .PSEL   (vif.PSEL),
        .PRDATA (vif.PRDATA),
        .PREADY (vif.PREADY),
        .rx     (vif.rx),
        .tx     (vif.tx)
    );

    // Clock generation
    always #5 vif.PCLK = ~vif.PCLK;

    initial begin
        env = new(vif);
        env.reset();
        env.run(50);  // Run 50 random tests
        #10_000;
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("uart_periph.vcd");
        $dumpvars(0, tb_UART_Periph);
    end
endmodule
