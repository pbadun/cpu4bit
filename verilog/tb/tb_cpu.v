`timescale 1ns / 1ps

module tb_cpu;

reg         clk;
reg         reset;
wire [7:0]  mem_data;
wire [7:0]  mem_addr;
reg [3:0]   port0_in;
wire [3:0]  port0_out;
reg [3:0]   port1_in;
wire [3:0]  port1_out;

reg [7:0] memory [0:255];

wire [3:0] r0;
wire [3:0] r1;
wire [7:0] pc;
wire [7:0] ir;
wire       c;
wire       v;
wire       halted;

integer errors;
integer i;

cpu dut (
    .clk       (clk),
    .reset     (reset),
    .mem_data  (mem_data),
    .mem_addr  (mem_addr),
    .port0_in  (port0_in),
    .port0_out (port0_out),
    .port1_in  (port1_in),
    .port1_out (port1_out),
    .r0        (r0),
    .r1        (r1),
    .pc        (pc),
    .ir        (ir),
    .c         (c),
    .v         (v),
    .halted    (halted)
);

assign mem_data = memory[mem_addr];

always #5 clk = ~clk;

task clear_memory;
    integer index;
    begin
        for (index = 0; index < 256; index = index + 1) begin
            memory[index] = 8'h00;
        end
    end
endtask

task putb;
    input [7:0] address;
    input [7:0] value;
    begin
        memory[address] = value;
    end
endtask

task reset_dut;
    begin
        reset = 1'b1;
        #1;
        reset = 1'b0;
        #1;
    end
endtask

task run_cycles;
    input integer count;
    integer index;
    begin
        for (index = 0; index < count; index = index + 1) begin
            @(posedge clk);
        end
        #1;
    end
endtask

task check4;
    input [3:0] expected;
    input [3:0] actual;
    input [1023:0] label;
    begin
        if (actual !== expected) begin
            $display("FAIL: %0s expected 0x%0h, got 0x%0h", label, expected, actual);
            errors = errors + 1;
        end
    end
endtask

task check8;
    input [7:0] expected;
    input [7:0] actual;
    input [1023:0] label;
    begin
        if (actual !== expected) begin
            $display("FAIL: %0s expected 0x%0h, got 0x%0h", label, expected, actual);
            errors = errors + 1;
        end
    end
endtask

task check_bit;
    input expected;
    input actual;
    input [1023:0] label;
    begin
        if (actual !== expected) begin
            $display("FAIL: %0s expected %0d, got %0d", label, expected, actual);
            errors = errors + 1;
        end
    end
endtask

task pass;
    input [1023:0] label;
    begin
        $display("PASS: %0s", label);
    end
endtask

initial begin
    clk = 1'b0;
    reset = 1'b0;
    port0_in = 4'd0;
    port1_in = 4'd0;
    errors = 0;
    clear_memory();

    // Test 1: LDI0 and LDI1.
    clear_memory();
    putb(8'd0, 8'h15);
    putb(8'd1, 8'h23);
    putb(8'd2, 8'hE0);
    reset_dut();
    run_cycles(2);
    check4(4'd5, r0, "LDI0 loads R0");
    check4(4'd0, r1, "R1 remains reset before LDI1");
    run_cycles(2);
    check4(4'd5, r0, "LDI0 preserves R0");
    check4(4'd3, r1, "LDI1 loads R1");
    run_cycles(2);
    check_bit(1'b1, halted, "LDI test reaches HALT");
    pass("Test 1 - LDI");

    // Test 2: ADD without carry.
    clear_memory();
    putb(8'd0, 8'h15);
    putb(8'd1, 8'h23);
    putb(8'd2, 8'h30);
    putb(8'd3, 8'hE0);
    reset_dut();
    run_cycles(6);
    check4(4'd8, r0, "ADD result");
    check_bit(1'b0, c, "ADD carry clear");
    check_bit(1'b1, v, "ADD 5 + 3 sets signed overflow");
    run_cycles(2);
    check_bit(1'b1, halted, "ADD test reaches HALT");
    pass("Test 2 - ADD");

    // Test 3: ADD carry.
    clear_memory();
    putb(8'd0, 8'h1F);
    putb(8'd1, 8'h21);
    putb(8'd2, 8'h30);
    putb(8'd3, 8'hE0);
    reset_dut();
    run_cycles(6);
    check4(4'd0, r0, "ADD wrapped result");
    check_bit(1'b1, c, "ADD carry set");
    check_bit(1'b0, v, "ADD carry case has no signed overflow");
    run_cycles(2);
    pass("Test 3 - Carry");

    // Test 4: signed ADD overflow.
    clear_memory();
    putb(8'd0, 8'h17);
    putb(8'd1, 8'h21);
    putb(8'd2, 8'h30);
    putb(8'd3, 8'hE0);
    reset_dut();
    run_cycles(6);
    check4(4'd8, r0, "ADD signed overflow result");
    check_bit(1'b0, c, "ADD overflow case has no carry");
    check_bit(1'b1, v, "ADD signed overflow set");
    run_cycles(2);
    pass("Test 4 - Overflow");

    // Test 5: SUB without borrow.
    clear_memory();
    putb(8'd0, 8'h12);
    putb(8'd1, 8'h21);
    putb(8'd2, 8'h40);
    putb(8'd3, 8'hE0);
    reset_dut();
    run_cycles(6);
    check4(4'd1, r0, "SUB result");
    check_bit(1'b0, c, "SUB borrow clear");
    check_bit(1'b0, v, "SUB overflow clear");
    run_cycles(2);
    pass("Test 5 - SUB");

    // Test 6: SUB borrow.
    clear_memory();
    putb(8'd0, 8'h11);
    putb(8'd1, 8'h22);
    putb(8'd2, 8'h40);
    putb(8'd3, 8'hE0);
    reset_dut();
    run_cycles(6);
    check4(4'hF, r0, "SUB wrapped result");
    check_bit(1'b1, c, "SUB borrow set");
    check_bit(1'b0, v, "SUB borrow case has no signed overflow");
    run_cycles(2);
    pass("Test 6 - Borrow");

    // Test 7: logical operations and preservation of flags.
    clear_memory();
    putb(8'd0, 8'h17);
    putb(8'd1, 8'h21);
    putb(8'd2, 8'h30);
    putb(8'd3, 8'h1F);
    putb(8'd4, 8'h23);
    putb(8'd5, 8'h50);
    putb(8'd6, 8'h60);
    putb(8'd7, 8'hE0);
    reset_dut();
    run_cycles(12);
    check4(4'd3, r0, "AND result");
    check_bit(1'b0, c, "AND preserves carry");
    check_bit(1'b1, v, "AND preserves overflow");
    run_cycles(2);
    check4(4'd0, r0, "XOR result");
    check_bit(1'b0, c, "XOR preserves carry");
    check_bit(1'b1, v, "XOR preserves overflow");
    run_cycles(2);
    pass("Test 7 - AND/XOR");

    // Test 7b: logical operations preserve a set carry flag.
    clear_memory();
    putb(8'd0, 8'h1F);
    putb(8'd1, 8'h21);
    putb(8'd2, 8'h30);
    putb(8'd3, 8'h15);
    putb(8'd4, 8'h23);
    putb(8'd5, 8'h50);
    putb(8'd6, 8'h60);
    putb(8'd7, 8'hE0);
    reset_dut();
    run_cycles(12);
    check4(4'd1, r0, "AND result with carry set");
    check_bit(1'b1, c, "AND preserves set carry");
    run_cycles(2);
    check4(4'd2, r0, "XOR result with carry set");
    check_bit(1'b1, c, "XOR preserves set carry");
    run_cycles(2);
    pass("Test 7b - logical flag preservation");

    // Test 8: MOV01.
    clear_memory();
    putb(8'd0, 8'h15);
    putb(8'd1, 8'h23);
    putb(8'd2, 8'hC0);
    putb(8'd3, 8'hE0);
    reset_dut();
    run_cycles(6);
    check4(4'd3, r0, "MOV01 result in R0");
    check4(4'd3, r1, "MOV01 source R1 unchanged");
    run_cycles(2);
    pass("Test 8 - MOV01");

    // Test 8b: MOV10.
    clear_memory();
    putb(8'd0, 8'h15);
    putb(8'd1, 8'h23);
    putb(8'd2, 8'hD0);
    putb(8'd3, 8'hE0);
    reset_dut();
    run_cycles(6);
    check4(4'd5, r0, "MOV10 source R0 unchanged");
    check4(4'd5, r1, "MOV10 result in R1");
    run_cycles(2);
    pass("Test 8b - MOV10");

    // Test 9: positive relative JMP.
    clear_memory();
    putb(8'd0, 8'h72);
    putb(8'd1, 8'h00);
    putb(8'd2, 8'h00);
    putb(8'd3, 8'h17);
    putb(8'd4, 8'hE0);
    reset_dut();
    run_cycles(2);
    check8(8'd3, pc, "positive JMP target PC");
    run_cycles(2);
    check4(4'd7, r0, "positive JMP target executed");
    run_cycles(2);
    pass("Test 9a - positive JMP");

    // Test 9b: negative relative JMP in a finite control-flow path.
    clear_memory();
    putb(8'd0, 8'h72);
    putb(8'd1, 8'h00);
    putb(8'd2, 8'h72);
    putb(8'd3, 8'h7E);
    putb(8'd4, 8'h00);
    putb(8'd5, 8'h26);
    putb(8'd6, 8'hE0);
    reset_dut();
    run_cycles(2);
    run_cycles(2);
    check8(8'd2, pc, "negative JMP target PC");
    run_cycles(2);
    run_cycles(2);
    check4(4'd6, r1, "negative JMP path continues");
    run_cycles(2);
    pass("Test 9b - negative JMP");

    // Test 10: JC taken.
    clear_memory();
    putb(8'd0, 8'h1F);
    putb(8'd1, 8'h21);
    putb(8'd2, 8'h30);
    putb(8'd3, 8'h81);
    putb(8'd4, 8'h00);
    putb(8'd5, 8'h16);
    putb(8'd6, 8'hE0);
    reset_dut();
    run_cycles(6);
    check_bit(1'b1, c, "JC setup carry");
    run_cycles(2);
    check8(8'd5, pc, "JC taken target PC");
    run_cycles(2);
    run_cycles(2);
    check4(4'd6, r0, "JC taken skips NOP");
    run_cycles(2);
    pass("Test 10a - JC taken");

    // Test 10b: JC not taken.
    clear_memory();
    putb(8'd0, 8'h12);
    putb(8'd1, 8'h21);
    putb(8'd2, 8'h40);
    putb(8'd3, 8'h81);
    putb(8'd4, 8'h17);
    putb(8'd5, 8'hE0);
    reset_dut();
    run_cycles(6);
    check_bit(1'b0, c, "JC setup carry clear");
    run_cycles(2);
    check8(8'd4, pc, "JC not-taken fall-through PC");
    run_cycles(2);
    run_cycles(2);
    check4(4'd7, r0, "JC not-taken executes next instruction");
    run_cycles(2);
    pass("Test 10b - JC not taken");

    // Test 11: JV taken.
    clear_memory();
    putb(8'd0, 8'h17);
    putb(8'd1, 8'h21);
    putb(8'd2, 8'h30);
    putb(8'd3, 8'h91);
    putb(8'd4, 8'h00);
    putb(8'd5, 8'h18);
    putb(8'd6, 8'hE0);
    reset_dut();
    run_cycles(6);
    check_bit(1'b1, v, "JV setup overflow");
    run_cycles(2);
    check8(8'd5, pc, "JV taken target PC");
    run_cycles(2);
    run_cycles(2);
    check4(4'd8, r0, "JV taken skips NOP");
    run_cycles(2);
    pass("Test 11a - JV taken");

    // Test 11b: JV not taken.
    clear_memory();
    putb(8'd0, 8'h12);
    putb(8'd1, 8'h21);
    putb(8'd2, 8'h40);
    putb(8'd3, 8'h91);
    putb(8'd4, 8'h17);
    putb(8'd5, 8'hE0);
    reset_dut();
    run_cycles(6);
    check_bit(1'b0, v, "JV setup overflow clear");
    run_cycles(2);
    check8(8'd4, pc, "JV not-taken fall-through PC");
    run_cycles(2);
    run_cycles(2);
    check4(4'd7, r0, "JV not-taken executes next instruction");
    run_cycles(2);
    pass("Test 11b - JV not taken");

    // Test 12: I/O port selection and output registers.
    clear_memory();
    port0_in = 4'd5;
    port1_in = 4'd10;
    putb(8'd0, 8'hA0);
    putb(8'd1, 8'hB0);
    putb(8'd2, 8'hA1);
    putb(8'd3, 8'hB1);
    putb(8'd4, 8'hE0);
    reset_dut();
    run_cycles(2);
    check4(4'd5, r0, "IN PORT0 loads R0");
    run_cycles(2);
    check4(4'd5, port0_out, "OUT PORT0 updates output");
    run_cycles(2);
    check4(4'd10, r0, "IN PORT1 loads R0");
    run_cycles(2);
    check4(4'd10, port1_out, "OUT PORT1 updates output");
    run_cycles(2);
    pass("Test 12 - I/O");

    // Test 13: HALT holds architectural state.
    clear_memory();
    putb(8'd0, 8'h15);
    putb(8'd1, 8'h23);
    putb(8'd2, 8'hE0);
    reset_dut();
    run_cycles(2);
    run_cycles(2);
    run_cycles(2);
    check8(8'd3, pc, "HALT PC after fetch increment");
    check4(4'd5, r0, "HALT R0 before hold check");
    check4(4'd3, r1, "HALT R1 before hold check");
    check_bit(1'b1, halted, "HALT state entered");
    run_cycles(6);
    check8(8'd3, pc, "HALT holds PC");
    check4(4'd5, r0, "HALT holds R0");
    check4(4'd3, r1, "HALT holds R1");
    check_bit(1'b1, halted, "HALT remains asserted");
    pass("Test 13 - HALT");

    // Test 14: PC wraparound from 0xFF to 0x00.
    clear_memory();
    for (i = 0; i < 255; i = i + 1) begin
        memory[i] = 8'h00;
    end
    putb(8'hFF, 8'h19);
    reset_dut();
    run_cycles(512);
    check8(8'd0, pc, "PC wraps after instruction at 0xFF");
    check4(4'd9, r0, "instruction at 0xFF executes after wrap path");
    check_bit(1'b0, halted, "PC wrap test is not halted");
    pass("Test 14 - PC wraparound");

    // Reserved opcode and invalid I/O operands behave as NOP.
    clear_memory();
    putb(8'd0, 8'hF7);
    putb(8'd1, 8'hA2);
    putb(8'd2, 8'hB2);
    putb(8'd3, 8'h15);
    putb(8'd4, 8'hE0);
    reset_dut();
    run_cycles(2);
    check8(8'd1, pc, "RESERVED opcode advances PC");
    run_cycles(2);
    check8(8'd2, pc, "invalid IN operand advances PC");
    check4(4'd0, r0, "invalid IN operand does not load R0");
    run_cycles(2);
    check8(8'd3, pc, "invalid OUT operand advances PC");
    check4(4'd0, port0_out, "invalid OUT operand leaves PORT0 unchanged");
    check4(4'd0, port1_out, "invalid OUT operand leaves PORT1 unchanged");
    run_cycles(2);
    check4(4'd5, r0, "program continues after invalid I/O");
    run_cycles(2);
    pass("Reserved and invalid I/O operands");

    // Exact control sequence printed in the technical specification.
    // Its MOV01 instruction follows the documented ISA and therefore does
    // not produce the specification's stated R1 = 9 final value.
    clear_memory();
    putb(8'd0, 8'h15);
    putb(8'd1, 8'h23);
    putb(8'd2, 8'h30);
    putb(8'd3, 8'h21);
    putb(8'd4, 8'h30);
    putb(8'd5, 8'hC0);
    putb(8'd6, 8'hB0);
    putb(8'd7, 8'hE0);
    reset_dut();
    run_cycles(10);
    run_cycles(2);
    check4(4'd1, r0, "TZ control listing MOV01 result in R0");
    check4(4'd1, r1, "TZ control listing MOV01 leaves R1");
    run_cycles(2);
    check4(4'd1, port0_out, "TZ control listing OUT PORT0");
    run_cycles(2);
    check_bit(1'b1, halted, "TZ control listing HALT");
    pass("TZ control listing with MOV01");

    // Intended final-state control program, corrected to MOV10.
    clear_memory();
    putb(8'd0, 8'h15);
    putb(8'd1, 8'h23);
    putb(8'd2, 8'h30);
    putb(8'd3, 8'h21);
    putb(8'd4, 8'h30);
    putb(8'd5, 8'hD0);
    putb(8'd6, 8'hB0);
    putb(8'd7, 8'hE0);
    reset_dut();
    run_cycles(2);
    check4(4'd5, r0, "control program LDI0");
    run_cycles(2);
    check4(4'd3, r1, "control program LDI1");
    run_cycles(2);
    check4(4'd8, r0, "control program first ADD");
    run_cycles(2);
    check4(4'd1, r1, "control program reloads R1");
    run_cycles(2);
    check4(4'd9, r0, "control program second ADD");
    run_cycles(2);
    check4(4'd9, r1, "control program MOV10");
    run_cycles(2);
    check4(4'd9, port0_out, "control program OUT PORT0");
    run_cycles(2);
    check_bit(1'b1, halted, "control program HALT");
    check4(4'd9, r0, "control program final R0");
    check4(4'd9, r1, "control program final R1");
    check4(4'd9, port0_out, "control program final PORT0");
    pass("Control program");

    if (errors == 0) begin
        $display("ALL TESTS PASSED");
    end else begin
        $display("TESTS FAILED: %0d error(s)", errors);
    end
    $finish;
end

endmodule
