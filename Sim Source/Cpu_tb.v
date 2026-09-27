`timescale 1ns / 1ps
module cpu_tb;
    reg clk = 1'b0;
    reg reset = 1'b1;
    integer stall_count = 0;
    integer redirect_count = 0;
    integer final_store_seen = 0;
    reg [31:0] auipc_pc = 32'hxxxxxxxx;
    reg [31:0] jal_pc = 32'hxxxxxxxx;
    reg [31:0] jalr_pc = 32'hxxxxxxxx;

    wire [31:0] debug_pc;
    cpu UUT (.clk(clk), .reset(reset), .step_en(1'b1), .debug_pc(debug_pc));
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (reset) begin
            stall_count = 0;
            redirect_count = 0;
        end else begin
            if (UUT.load_use_stall)
                stall_count = stall_count + 1;
            if (UUT.ex_redirect)
                redirect_count = redirect_count + 1;
            if (UUT.idex_valid && UUT.idex_instr[6:0] == 7'b0010111 && UUT.idex_rd == 5'd23)
                auipc_pc = UUT.idex_pc;
            if (UUT.idex_valid && UUT.idex_instr[6:0] == 7'b1101111 && UUT.idex_rd == 5'd1)
                jal_pc = UUT.idex_pc;
            if (UUT.idex_valid && UUT.idex_instr[6:0] == 7'b1100111 && UUT.idex_rd == 5'd2)
                jalr_pc = UUT.idex_pc;
            if (UUT.exmem_valid && UUT.exmem_memwrite && UUT.exmem_alu_result == 32'd68)
                final_store_seen = 1;
        end
    end

    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(0, cpu_tb);
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        wait (final_store_seen);
        #1;

        if (UUT.RF.regs[0] !== 32'h00000000) $fatal(1, "x0: expected 00000000, got %h", UUT.RF.regs[0]);
        if (UUT.RF.regs[3] !== 32'hfffffffb) $fatal(1, "ADD: x3 expected fffffffb, got %h", UUT.RF.regs[3]);
        if (UUT.RF.regs[4] !== 32'hfffffff5) $fatal(1, "SUB: x4 expected fffffff5, got %h", UUT.RF.regs[4]);
        if (UUT.RF.regs[5] !== 32'd24) $fatal(1, "SLL: x5 expected 24, got %h", UUT.RF.regs[5]);
        if (UUT.RF.regs[6] !== 32'd1) $fatal(1, "SLT: x6 expected 1, got %h", UUT.RF.regs[6]);
        if (UUT.RF.regs[7] !== 32'd0) $fatal(1, "SLTU: x7 expected 0, got %h", UUT.RF.regs[7]);
        if (UUT.RF.regs[8] !== 32'hfffffffb) $fatal(1, "XOR: x8 expected fffffffb, got %h", UUT.RF.regs[8]);
        if (UUT.RF.regs[9] !== 32'h1fffffff) $fatal(1, "SRL: x9 expected 1fffffff, got %h", UUT.RF.regs[9]);
        if (UUT.RF.regs[10] !== 32'hffffffff) $fatal(1, "SRA: x10 expected ffffffff, got %h", UUT.RF.regs[10]);
        if (UUT.RF.regs[11] !== 32'hfffffffb) $fatal(1, "OR: x11 expected fffffffb, got %h", UUT.RF.regs[11]);
        if (UUT.RF.regs[12] !== 32'd0) $fatal(1, "AND: x12 expected 0, got %h", UUT.RF.regs[12]);
        if (UUT.RF.regs[13] !== 32'd20) $fatal(1, "ADDI: x13 expected 20, got %h", UUT.RF.regs[13]);
        if (UUT.RF.regs[14] !== 32'd1) $fatal(1, "SLTI: x14 expected 1, got %h", UUT.RF.regs[14]);
        if (UUT.RF.regs[15] !== 32'd0) $fatal(1, "SLTIU: x15 expected 0, got %h", UUT.RF.regs[15]);
        if (UUT.RF.regs[16] !== 32'hfffffff7) $fatal(1, "XORI: x16 expected fffffff7, got %h", UUT.RF.regs[16]);
        if (UUT.RF.regs[17] !== 32'd85) $fatal(1, "ORI: x17 expected 85, got %h", UUT.RF.regs[17]);
        if (UUT.RF.regs[18] !== 32'd0) $fatal(1, "ANDI: x18 expected 0, got %h", UUT.RF.regs[18]);
        if (UUT.RF.regs[19] !== 32'd12) $fatal(1, "SLLI: x19 expected 12, got %h", UUT.RF.regs[19]);
        if (UUT.RF.regs[20] !== 32'h3ffffffe) $fatal(1, "SRLI: x20 expected 3ffffffe, got %h", UUT.RF.regs[20]);
        if (UUT.RF.regs[21] !== 32'hfffffffe) $fatal(1, "SRAI: x21 expected fffffffe, got %h", UUT.RF.regs[21]);
        if (UUT.RF.regs[22] !== 32'h12345000) $fatal(1, "LUI: x22 expected 12345000, got %h", UUT.RF.regs[22]);
        if (auipc_pc === 32'hxxxxxxxx || UUT.RF.regs[23] !== auipc_pc) $fatal(1, "AUIPC: x23=%h, instruction PC=%h", UUT.RF.regs[23], auipc_pc);
        if (UUT.RF.regs[25] !== 32'hffffff80) $fatal(1, "LB sign extension: x25=%h", UUT.RF.regs[25]);
        if (UUT.RF.regs[26] !== 32'd128) $fatal(1, "LBU zero extension: x26=%h", UUT.RF.regs[26]);
        if (UUT.RF.regs[27] !== 32'd291) $fatal(1, "LH: x27=%h", UUT.RF.regs[27]);
        if (UUT.RF.regs[28] !== 32'd291) $fatal(1, "LHU: x28=%h", UUT.RF.regs[28]);
        if (UUT.RF.regs[29] !== 32'h0123807f) $fatal(1, "LW: x29=%h", UUT.RF.regs[29]);
        if (UUT.RF.regs[30] !== 32'h12345678) $fatal(1, "LW after SW / forwarding: x30=%h", UUT.RF.regs[30]);
        if (jal_pc === 32'hxxxxxxxx || UUT.RF.regs[1] !== jal_pc + 32'd4) $fatal(1, "JAL link: x1=%h, expected PC+4 from %h", UUT.RF.regs[1], jal_pc);
        if (jalr_pc === 32'hxxxxxxxx || UUT.RF.regs[2] !== jalr_pc + 32'd4) $fatal(1, "JALR link: x2=%h, expected PC+4 from %h", UUT.RF.regs[2], jalr_pc);
        if (UUT.RF.regs[31] !== 32'd0) $fatal(1, "Jump flush marker: x31 should remain zero, got %h", UUT.RF.regs[31]);

        if (UUT.DMEM.mem[0] !== 8'h7f || UUT.DMEM.mem[1] !== 8'h80 || UUT.DMEM.mem[2] !== 8'h23 || UUT.DMEM.mem[3] !== 8'h01)
            $fatal(1, "SB/SH bytes incorrect: %h %h %h %h", UUT.DMEM.mem[0], UUT.DMEM.mem[1], UUT.DMEM.mem[2], UUT.DMEM.mem[3]);
        if (UUT.DMEM.mem[8] !== 8'h78 || UUT.DMEM.mem[9] !== 8'h56 || UUT.DMEM.mem[10] !== 8'h34 || UUT.DMEM.mem[11] !== 8'h12)
            $fatal(1, "SW bytes at 8 incorrect");
        if (UUT.DMEM.mem[12] !== 8'h78 || UUT.DMEM.mem[13] !== 8'h56 || UUT.DMEM.mem[14] !== 8'h34 || UUT.DMEM.mem[15] !== 8'h12)
            $fatal(1, "Load-to-store forwarding bytes at 12 incorrect");
        if (UUT.DMEM.mem[16] !== 8'h79 || UUT.DMEM.mem[17] !== 8'h56 || UUT.DMEM.mem[18] !== 8'h34 || UUT.DMEM.mem[19] !== 8'h12)
            $fatal(1, "Load-use dependent result bytes at 16 incorrect");
        if (UUT.DMEM.mem[100] !== 8'h00 || UUT.DMEM.mem[104] !== 8'h63 || UUT.DMEM.mem[108] !== 8'h00 || UUT.DMEM.mem[112] !== 8'h63 || UUT.DMEM.mem[116] !== 8'h63 || UUT.DMEM.mem[120] !== 8'h00)
            $fatal(1, "One or more BEQ/BNE/BLT/BGE/BLTU/BGEU outcomes are incorrect");
        if (UUT.DMEM.mem[64] !== 8'h00 || UUT.DMEM.mem[68] !== 8'h00)
            $fatal(1, "JAL/JALR failed to flush the marker instruction");
        if (stall_count !== 2) $fatal(1, "Expected two load-use stalls, saw %0d", stall_count);
        if (redirect_count !== 5) $fatal(1, "Expected three taken branches plus JAL/JALR redirects, saw %0d", redirect_count);

        $display("PASS: 77-instruction RV32I pipeline test; ALU, loads/stores, forwarding, 2 load-use stalls, all 6 branches, JAL/JALR links and flushes.");
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "FAIL: pipelined test timed out waiting for final store");
    end
endmodule
