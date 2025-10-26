`timescale 1ns / 1ps

// Vivado 호환 SystemVerilog 검증 환경
parameter BAUD_RATE = 9_600;
parameter CLOCK_PERIOD_NS = 10;
parameter CLOCK_PER_BIT = 100_000_000 / BAUD_RATE;
parameter BIT_PERIOD = CLOCK_PER_BIT * CLOCK_PERIOD_NS;

// Interface
interface uart_periph_if;
    logic        PCLK;
    logic        PRESET;
    logic [ 3:0] PADDR;
    logic [31:0] PWDATA;
    logic        PWRITE;
    logic        PENABLE;
    logic        PSEL;
    logic [31:0] PRDATA;
    logic        PREADY;
    logic        rx;
    logic        tx;
    logic [7:0]  exp_data;
    logic        is_tx_test;  // TX/RX 구분용 플래그
endinterface

// Transaction class
class transaction;
    rand bit [7:0] data;
    rand bit is_tx;
    bit [7:0] received_data;
    bit [7:0] read_data;
    
    constraint data_range {
        data inside {[8'h20:8'h7E]};
    }
    
    function void display(string tag);
        if (is_tx)
            $display("[%0t][%s] TX: send=0x%h recv=0x%h", $time, tag, data, received_data);
        else
            $display("[%0t][%s] RX: send=0x%h read=0x%h", $time, tag, data, read_data);
    endfunction
endclass

// Generator
class generator;
    transaction tr;
    mailbox #(transaction) gen2drv;
    event next_gen;
    int total_count = 0;
    
    function new(mailbox#(transaction) g2d, event nxt);
        this.gen2drv = g2d;
        this.next_gen = nxt;
    endfunction
    
    task run(int count);
        repeat(count) begin
            tr = new();
            void'(tr.randomize());
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
    
    function new(mailbox#(transaction) g2d, virtual uart_periph_if v, 
                 event ng, event nm);
        this.gen2drv = g2d;
        this.vif = v;
        this.next_gen = ng;
        this.next_mon = nm;
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
        repeat(10) @(posedge vif.PCLK);
        vif.PRESET = 0;
        repeat(5) @(posedge vif.PCLK);
        $display("[Drv] Reset done");
    endtask
    
    task apb_write(input [3:0] addr, input [31:0] data);
        @(posedge vif.PCLK);
        vif.PSEL = 1;
        vif.PADDR = addr;
        vif.PWDATA = data;
        vif.PWRITE = 1;
        vif.PENABLE = 0;
        @(posedge vif.PCLK);
        vif.PENABLE = 1;
        @(posedge vif.PCLK);
        wait(vif.PREADY == 1);
        @(posedge vif.PCLK);
        vif.PSEL = 0;
        vif.PENABLE = 0;
        vif.PWRITE = 0;
    endtask
    
    task apb_read(input [3:0] addr, output [31:0] rdata);
        @(posedge vif.PCLK);
        vif.PSEL = 1;
        vif.PADDR = addr;
        vif.PWRITE = 0;
        vif.PENABLE = 0;
        @(posedge vif.PCLK);
        vif.PENABLE = 1;
        @(posedge vif.PCLK);
        wait(vif.PREADY == 1);
        rdata = vif.PRDATA;
        @(posedge vif.PCLK);
        vif.PSEL = 0;
        vif.PENABLE = 0;
    endtask
    
    task uart_send_byte(input [7:0] data);
        int i;
        vif.rx = 0;
        #BIT_PERIOD;
        for (i = 0; i < 8; i++) begin
            vif.rx = data[i];
            #BIT_PERIOD;
        end
        vif.rx = 1;
        #BIT_PERIOD;
    endtask
    
    task run();
        forever begin
            gen2drv.get(tr);
            
            if (tr.is_tx) begin
                $display("[Drv] TX Test: Writing 0x%h to TDR", tr.data);
                apb_write(4'h8, {24'h0, tr.data});
                vif.exp_data = tr.data;
                vif.is_tx_test = 1;
                
                // TX FIFO → uart_tx 처리 대기
                // UART 전송 완료까지 충분한 시간 대기
                #(BIT_PERIOD * 12);  // Start + 8 data + Stop bit + 여유
            end else begin
                $display("[Drv] RX Test: Sending 0x%h via UART", tr.data);
                uart_send_byte(tr.data);
                vif.exp_data = tr.data;
                vif.is_tx_test = 0;
                repeat(100) @(posedge vif.PCLK);
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
    
    function new(mailbox#(transaction) m2s, virtual uart_periph_if v, event nm);
        this.mon2scb = m2s;
        this.vif = v;
        this.next_mon = nm;
    endfunction
    
    task uart_receive_byte(output [7:0] data);
        int i;
        wait(vif.tx == 0);
        #(BIT_PERIOD / 2);
        if (vif.tx != 0) 
            $error("[Mon] Start bit error!");
        for (i = 0; i < 8; i++) begin
            #BIT_PERIOD;
            data[i] = vif.tx;
        end
        #BIT_PERIOD;
        if (vif.tx != 1)
            $error("[Mon] Stop bit error!");
        #(BIT_PERIOD / 2);
    endtask
    
    task run();
        forever begin
            @(next_mon);
            tr = new();
            
            // 인터페이스 플래그로 TX/RX 구분
            if (vif.is_tx_test) begin
                // TX Test
                automatic bit [7:0] uart_rx_data;
                
                // tx 핀이 idle 상태가 될 때까지 대기 (이전 전송 완료)
                wait(vif.tx == 1);
                repeat(10) @(posedge vif.PCLK);
                
                // 새로운 전송 시작 대기
                uart_receive_byte(uart_rx_data);
                tr.received_data = uart_rx_data;
                tr.data = vif.exp_data;
                tr.is_tx = 1;
                $display("[Mon] TX: Received 0x%h from UART tx pin", uart_rx_data);
            end else begin
                // RX Test
                automatic bit [31:0] read_val;
                automatic bit [31:0] status;
                repeat(50) @(posedge vif.PCLK);
                
                @(posedge vif.PCLK);
                vif.PSEL = 1;
                vif.PADDR = 4'h0;
                vif.PWRITE = 0;
                vif.PENABLE = 0;
                @(posedge vif.PCLK);
                vif.PENABLE = 1;
                @(posedge vif.PCLK);
                wait(vif.PREADY == 1);
                status = vif.PRDATA;
                @(posedge vif.PCLK);
                vif.PSEL = 0;
                vif.PENABLE = 0;
                
                $display("[Mon] USR = 0x%h (RX_READY=%b)", status, status[0]);
                
                @(posedge vif.PCLK);
                vif.PSEL = 1;
                vif.PADDR = 4'hC;
                vif.PWRITE = 0;
                vif.PENABLE = 0;
                @(posedge vif.PCLK);
                vif.PENABLE = 1;
                @(posedge vif.PCLK);
                wait(vif.PREADY == 1);
                read_val = vif.PRDATA;
                @(posedge vif.PCLK);
                vif.PSEL = 0;
                vif.PENABLE = 0;
                
                tr.read_data = read_val[7:0];
                tr.data = vif.exp_data;
                tr.is_tx = 0;
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
    int tx_pass_count = 0;
    int tx_fail_count = 0;
    int rx_pass_count = 0;
    int rx_fail_count = 0;
    
    function new(mailbox#(transaction) m2s, event ng);
        this.mon2scb = m2s;
        this.next_gen = ng;
    endfunction
    
    task run();
        forever begin
            mon2scb.get(tr);
            
            if (tr.is_tx) begin
                if (tr.data == tr.received_data) begin
                    $display("[Scb] TX PASS: 0x%h == 0x%h", tr.data, tr.received_data);
                    pass_count++;
                    tx_pass_count++;
                end else begin
                    $display("[Scb] TX FAIL: Expected=0x%h, Got=0x%h", 
                             tr.data, tr.received_data);
                    fail_count++;
                    tx_fail_count++;
                end
            end else begin
                if (tr.data == tr.read_data) begin
                    $display("[Scb] RX PASS: 0x%h == 0x%h", tr.data, tr.read_data);
                    pass_count++;
                    rx_pass_count++;
                end else begin
                    $display("[Scb] RX FAIL: Expected=0x%h, Got=0x%h", 
                             tr.data, tr.read_data);
                    fail_count++;
                    rx_fail_count++;
                end
            end
            
            ->next_gen;
        end
    endtask
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
    
    function new(virtual uart_periph_if v);
        this.vif = v;
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
        $display("\n========================================");
        $display("========== TEST REPORT =================");
        $display("========================================");
        $display("Total Tests : %4d", gen.total_count);
        $display("Pass Tests  : %4d", scb.pass_count);
        $display("Fail Tests  : %4d", scb.fail_count);
        $display("----------------------------------------");
        $display("TX Path Tests:");
        $display("  TX Pass   : %4d", scb.tx_pass_count);
        $display("  TX Fail   : %4d", scb.tx_fail_count);
        $display("  TX Total  : %4d", scb.tx_pass_count + scb.tx_fail_count);
        $display("----------------------------------------");
        $display("RX Path Tests:");
        $display("  RX Pass   : %4d", scb.rx_pass_count);
        $display("  RX Fail   : %4d", scb.rx_fail_count);
        $display("  RX Total  : %4d", scb.rx_pass_count + scb.rx_fail_count);
        $display("========================================");
        
        if (scb.fail_count == 0) begin
            $display("========== ALL TESTS PASSED ============");
            $display("  TX Path: %0d/%0d PASSED", 
                     scb.tx_pass_count, scb.tx_pass_count + scb.tx_fail_count);
            $display("  RX Path: %0d/%0d PASSED", 
                     scb.rx_pass_count, scb.rx_pass_count + scb.rx_fail_count);
        end else begin
            $display("========== SOME TESTS FAILED ===========");
            if (scb.tx_fail_count > 0)
                $display("  TX Path: %0d FAILURES", scb.tx_fail_count);
            if (scb.rx_fail_count > 0)
                $display("  RX Path: %0d FAILURES", scb.rx_fail_count);
        end
        
        $display("========================================");
    endtask
endclass

// Testbench Top
module tb_UART_Periph;
    uart_periph_if vif();
    environment env;
    
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
    
    always #5 vif.PCLK = ~vif.PCLK;
    
    initial begin
        env = new(vif);
        env.reset();
        env.run(50);
        #10_000;
        $finish;
    end

endmodule