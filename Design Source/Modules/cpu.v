`timescale 1ns / 1ps
module cpu (
    input wire clk,
    input wire reset,
    input wire step_en,
    output wire [31:0] debug_pc
);

    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_SLL  = 4'b0010;
    localparam ALU_SLT  = 4'b0011;
    localparam ALU_SLTU = 4'b0100;
    localparam ALU_XOR  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_OR   = 4'b1000;
    localparam ALU_AND  = 4'b1001;
    localparam NOP      = 32'h00000013;

    // Instruction fetch and PC.
    reg [31:0] pc;
    assign debug_pc = pc;
    reg [31:0] imem [0:1023];
    wire [31:0] if_instr;
    assign if_instr = (pc[31:12] == 20'b0) ? imem[pc[11:2]] : NOP;

    // IF/ID pipeline register.
    reg ifid_valid;
    reg [31:0] ifid_pc, ifid_instr;

    // ID decode fields and controls.
    wire [6:0] dec_opcode = ifid_instr[6:0];
    wire [4:0] dec_rd     = ifid_instr[11:7];
    wire [2:0] dec_funct3 = ifid_instr[14:12];
    wire [4:0] dec_rs1    = ifid_instr[19:15];
    wire [4:0] dec_rs2    = ifid_instr[24:20];
    wire [6:0] dec_funct7 = ifid_instr[31:25];

    // WB declarations precede their use in the register-file instance.
    reg memwb_valid;
    reg [31:0] memwb_instr, memwb_alu_result, memwb_load_data, memwb_pc4;
    reg [4:0] memwb_rd;
    reg [2:0] memwb_load_funct3;
    reg memwb_regwrite, memwb_memtoreg, memwb_link;
    wire [31:0] wb_value;
    reg [31:0] dec_imm;
    reg [3:0] dec_alu_ctrl;
    reg dec_regwrite, dec_memread, dec_memwrite, dec_memtoreg;
    reg dec_alu_src_imm, dec_alu_src_pc, dec_alu_src_zero;
    reg dec_is_branch, dec_is_jal, dec_is_jalr;
    reg [1:0] dec_mem_size;
    reg dec_uses_rs1, dec_uses_rs2;

    // Register file writes in WB and reads in ID.
    wire [31:0] rf_rdata1, rf_rdata2;
    regfile RF (
        .clk(clk), .reset(reset), .we(memwb_regwrite && step_en),
        .rs1(dec_rs1), .rs2(dec_rs2), .rd(memwb_rd), .wd(wb_value),
        .rd1(rf_rdata1), .rd2(rf_rdata2)
    );

    // ID/EX pipeline register.
    reg idex_valid;
    reg [31:0] idex_pc, idex_instr, idex_imm, idex_rs1_value, idex_rs2_value;
    reg [4:0] idex_rs1, idex_rs2, idex_rd;
    reg [2:0] idex_funct3;
    reg [3:0] idex_alu_ctrl;
    reg idex_regwrite, idex_memread, idex_memwrite, idex_memtoreg;
    reg idex_alu_src_imm, idex_alu_src_pc, idex_alu_src_zero;
    reg idex_is_branch, idex_is_jal, idex_is_jalr;
    reg [1:0] idex_mem_size;

    // EX forwarding and ALU.
    reg [31:0] ex_forward_a, ex_forward_b;
    wire [31:0] ex_alu_a = idex_alu_src_pc ? idex_pc :
                           idex_alu_src_zero ? 32'b0 : ex_forward_a;
    wire [31:0] ex_alu_b = idex_alu_src_imm ? idex_imm : ex_forward_b;
    wire [31:0] ex_alu_result;
    wire ex_zero;
    reg [31:0] wb_load_value;

    alu ALU (
        .a(ex_alu_a), .b(ex_alu_b), .alu_ctrl(idex_alu_ctrl),
        .result(ex_alu_result), .zero(ex_zero)
    );

    // EX/MEM pipeline register.
    reg exmem_valid;
    reg [31:0] exmem_instr, exmem_alu_result, exmem_store_data, exmem_pc4;
    reg [4:0] exmem_rd;
    reg [2:0] exmem_load_funct3;
    reg [1:0] exmem_mem_size;
    reg exmem_regwrite, exmem_memread, exmem_memwrite, exmem_memtoreg, exmem_link;

    // MEM stage uses a separate data memory, so IF can proceed in parallel.
    wire [31:0] mem_rdata;
    wire mem_we = exmem_valid && exmem_memwrite && !reset && step_en;
    dmem DMEM (
        .clk(clk), .we(mem_we), .size(exmem_mem_size),
        .addr(exmem_alu_result), .wdata(exmem_store_data), .rdata(mem_rdata)
    );

    // MEM/WB pipeline register.
    assign wb_value = memwb_link ? memwb_pc4 :
                      memwb_memtoreg ? wb_load_value : memwb_alu_result;

    // Hazard and redirect signals are exposed for simulation and waveform viewing.
    wire load_use_stall;
    wire ex_redirect;
    wire [31:0] ex_redirect_target;
    assign load_use_stall = idex_valid && idex_memread && (idex_rd != 5'b0) && ifid_valid &&
                            ((dec_uses_rs1 && dec_rs1 == idex_rd) ||
                             (dec_uses_rs2 && dec_rs2 == idex_rd));

    // Decode the instruction held in IF/ID.
    always @(*) begin
        dec_imm          = 32'b0;
        dec_alu_ctrl     = ALU_ADD;
        dec_regwrite     = 1'b0;
        dec_memread      = 1'b0;
        dec_memwrite     = 1'b0;
        dec_memtoreg     = 1'b0;
        dec_alu_src_imm  = 1'b0;
        dec_alu_src_pc   = 1'b0;
        dec_alu_src_zero = 1'b0;
        dec_is_branch    = 1'b0;
        dec_is_jal       = 1'b0;
        dec_is_jalr      = 1'b0;
        dec_mem_size     = 2'b10;
        dec_uses_rs1     = 1'b0;
        dec_uses_rs2     = 1'b0;

        case (dec_opcode)
            7'b0110011: begin // RV32I register-register ALU
                dec_uses_rs1 = 1'b1;
                dec_uses_rs2 = 1'b1;
                case (dec_funct3)
                    3'b000: if (dec_funct7 == 7'b0000000 || dec_funct7 == 7'b0100000) begin
                        dec_regwrite = 1'b1;
                        dec_alu_ctrl = (dec_funct7 == 7'b0100000) ? ALU_SUB : ALU_ADD;
                    end
                    3'b001: if (dec_funct7 == 7'b0000000) begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_SLL; end
                    3'b010: if (dec_funct7 == 7'b0000000) begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_SLT; end
                    3'b011: if (dec_funct7 == 7'b0000000) begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_SLTU; end
                    3'b100: if (dec_funct7 == 7'b0000000) begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_XOR; end
                    3'b101: if (dec_funct7 == 7'b0000000 || dec_funct7 == 7'b0100000) begin
                        dec_regwrite = 1'b1;
                        dec_alu_ctrl = (dec_funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
                    end
                    3'b110: if (dec_funct7 == 7'b0000000) begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_OR; end
                    3'b111: if (dec_funct7 == 7'b0000000) begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_AND; end
                    default: ;
                endcase
            end

            7'b0010011: begin // RV32I immediate ALU
                dec_uses_rs1 = 1'b1;
                dec_imm = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
                dec_alu_src_imm = 1'b1;
                case (dec_funct3)
                    3'b000: begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_ADD; end
                    3'b010: begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_SLT; end
                    3'b011: begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_SLTU; end
                    3'b100: begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_XOR; end
                    3'b110: begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_OR; end
                    3'b111: begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_AND; end
                    3'b001: if (dec_funct7 == 7'b0000000) begin dec_regwrite = 1'b1; dec_alu_ctrl = ALU_SLL; end
                    3'b101: if (dec_funct7 == 7'b0000000 || dec_funct7 == 7'b0100000) begin
                        dec_regwrite = 1'b1;
                        dec_alu_ctrl = (dec_funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
                    end
                    default: ;
                endcase
            end

            7'b0000011: begin // Loads
                dec_uses_rs1 = 1'b1;
                dec_imm = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
                dec_alu_src_imm = 1'b1;
                dec_memread = 1'b1;
                dec_memtoreg = 1'b1;
                case (dec_funct3)
                    3'b000: begin dec_regwrite = 1'b1; dec_mem_size = 2'b00; end // LB
                    3'b001: begin dec_regwrite = 1'b1; dec_mem_size = 2'b01; end // LH
                    3'b010: begin dec_regwrite = 1'b1; dec_mem_size = 2'b10; end // LW
                    3'b100: begin dec_regwrite = 1'b1; dec_mem_size = 2'b00; end // LBU
                    3'b101: begin dec_regwrite = 1'b1; dec_mem_size = 2'b01; end // LHU
                    default: begin dec_memread = 1'b0; dec_memtoreg = 1'b0; end
                endcase
            end

            7'b0100011: begin // Stores
                dec_uses_rs1 = 1'b1;
                dec_uses_rs2 = 1'b1;
                dec_imm = {{20{ifid_instr[31]}}, ifid_instr[31:25], ifid_instr[11:7]};
                dec_alu_src_imm = 1'b1;
                case (dec_funct3)
                    3'b000: begin dec_memwrite = 1'b1; dec_mem_size = 2'b00; end // SB
                    3'b001: begin dec_memwrite = 1'b1; dec_mem_size = 2'b01; end // SH
                    3'b010: begin dec_memwrite = 1'b1; dec_mem_size = 2'b10; end // SW
                    default: ;
                endcase
            end

            7'b1100011: begin // Conditional branches
                dec_uses_rs1 = 1'b1;
                dec_uses_rs2 = 1'b1;
                dec_imm = {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7], ifid_instr[30:25], ifid_instr[11:8], 1'b0};
                dec_is_branch = 1'b1;
                case (dec_funct3)
                    3'b000, 3'b001: dec_alu_ctrl = ALU_SUB;
                    3'b100, 3'b101: dec_alu_ctrl = ALU_SLT;
                    3'b110, 3'b111: dec_alu_ctrl = ALU_SLTU;
                    default: dec_is_branch = 1'b0;
                endcase
            end

            7'b1101111: begin // JAL
                dec_imm = {{11{ifid_instr[31]}}, ifid_instr[31], ifid_instr[19:12], ifid_instr[20], ifid_instr[30:21], 1'b0};
                dec_regwrite = 1'b1;
                dec_is_jal = 1'b1;
            end

            7'b1100111: if (dec_funct3 == 3'b000) begin // JALR
                dec_uses_rs1 = 1'b1;
                dec_imm = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
                dec_regwrite = 1'b1;
                dec_is_jalr = 1'b1;
            end

            7'b0110111: begin // LUI
                dec_imm = {ifid_instr[31:12], 12'b0};
                dec_alu_src_imm = 1'b1;
                dec_alu_src_zero = 1'b1;
                dec_regwrite = 1'b1;
            end

            7'b0010111: begin // AUIPC
                dec_imm = {ifid_instr[31:12], 12'b0};
                dec_alu_src_imm = 1'b1;
                dec_alu_src_pc = 1'b1;
                dec_regwrite = 1'b1;
            end
            default: ;
        endcase
    end

    // Forward most recent values into EX. Loads forward from WB after the load-use bubble.
    always @(*) begin
        ex_forward_a = idex_rs1_value;
        ex_forward_b = idex_rs2_value;
        if (exmem_valid && exmem_regwrite && !exmem_memtoreg && (exmem_rd != 5'b0) && (exmem_rd == idex_rs1))
            ex_forward_a = exmem_link ? exmem_pc4 : exmem_alu_result;
        else if (memwb_valid && memwb_regwrite && (memwb_rd != 5'b0) && (memwb_rd == idex_rs1))
            ex_forward_a = wb_value;

        if (exmem_valid && exmem_regwrite && !exmem_memtoreg && (exmem_rd != 5'b0) && (exmem_rd == idex_rs2))
            ex_forward_b = exmem_link ? exmem_pc4 : exmem_alu_result;
        else if (memwb_valid && memwb_regwrite && (memwb_rd != 5'b0) && (memwb_rd == idex_rs2))
            ex_forward_b = wb_value;
    end

    wire ex_branch_condition =
        (idex_funct3 == 3'b000) ? ex_zero :
        (idex_funct3 == 3'b001) ? !ex_zero :
        (idex_funct3 == 3'b100) ? (ex_alu_result == 32'd1) :
        (idex_funct3 == 3'b101) ? (ex_alu_result == 32'd0) :
        (idex_funct3 == 3'b110) ? (ex_alu_result == 32'd1) :
        (idex_funct3 == 3'b111) ? (ex_alu_result == 32'd0) : 1'b0;
    assign ex_redirect = idex_valid &&
                         (idex_is_jal || idex_is_jalr || (idex_is_branch && ex_branch_condition));
    assign ex_redirect_target = idex_is_jalr ? ((ex_forward_a + idex_imm) & 32'hFFFFFFFE) :
                                idex_is_jal ? (idex_pc + idex_imm) : (idex_pc + idex_imm);

    // WB load extension.
    always @(*) begin
        case (memwb_load_funct3)
            3'b000: wb_load_value = {{24{memwb_load_data[7]}}, memwb_load_data[7:0]};
            3'b001: wb_load_value = {{16{memwb_load_data[15]}}, memwb_load_data[15:0]};
            3'b010: wb_load_value = memwb_load_data;
            3'b100: wb_load_value = {24'b0, memwb_load_data[7:0]};
            3'b101: wb_load_value = {16'b0, memwb_load_data[15:0]};
            default: wb_load_value = memwb_load_data;
        endcase
    end

    // Pipeline state advances each cycle; redirects flush both younger stages.
    always @(posedge clk) begin
        if (reset) begin
            pc <= 32'b0;
            ifid_valid <= 1'b0;
            ifid_pc <= 32'b0;
            ifid_instr <= NOP;

            idex_valid <= 1'b0;
            idex_pc <= 32'b0;
            idex_instr <= NOP;
            idex_imm <= 32'b0;
            idex_rs1_value <= 32'b0;
            idex_rs2_value <= 32'b0;
            idex_rs1 <= 5'b0;
            idex_rs2 <= 5'b0;
            idex_rd <= 5'b0;
            idex_funct3 <= 3'b0;
            idex_alu_ctrl <= ALU_ADD;
            idex_regwrite <= 1'b0;
            idex_memread <= 1'b0;
            idex_memwrite <= 1'b0;
            idex_memtoreg <= 1'b0;
            idex_alu_src_imm <= 1'b0;
            idex_alu_src_pc <= 1'b0;
            idex_alu_src_zero <= 1'b0;
            idex_is_branch <= 1'b0;
            idex_is_jal <= 1'b0;
            idex_is_jalr <= 1'b0;
            idex_mem_size <= 2'b10;

            exmem_valid <= 1'b0;
            exmem_instr <= NOP;
            exmem_alu_result <= 32'b0;
            exmem_store_data <= 32'b0;
            exmem_pc4 <= 32'b0;
            exmem_rd <= 5'b0;
            exmem_load_funct3 <= 3'b0;
            exmem_mem_size <= 2'b10;
            exmem_regwrite <= 1'b0;
            exmem_memread <= 1'b0;
            exmem_memwrite <= 1'b0;
            exmem_memtoreg <= 1'b0;
            exmem_link <= 1'b0;

            memwb_valid <= 1'b0;
            memwb_instr <= NOP;
            memwb_alu_result <= 32'b0;
            memwb_load_data <= 32'b0;
            memwb_pc4 <= 32'b0;
            memwb_rd <= 5'b0;
            memwb_load_funct3 <= 3'b0;
            memwb_regwrite <= 1'b0;
            memwb_memtoreg <= 1'b0;
            memwb_link <= 1'b0;
        end else if (step_en) begin
            // MEM/WB receives the result of the instruction currently in MEM.
            memwb_valid <= exmem_valid;
            memwb_instr <= exmem_instr;
            memwb_alu_result <= exmem_alu_result;
            memwb_load_data <= mem_rdata;
            memwb_pc4 <= exmem_pc4;
            memwb_rd <= exmem_rd;
            memwb_load_funct3 <= exmem_load_funct3;
            memwb_regwrite <= exmem_regwrite;
            memwb_memtoreg <= exmem_memtoreg;
            memwb_link <= exmem_link;

            // EX/MEM receives the instruction currently in EX.
            exmem_valid <= idex_valid;
            exmem_instr <= idex_instr;
            exmem_alu_result <= ex_alu_result;
            exmem_store_data <= ex_forward_b;
            exmem_pc4 <= idex_pc + 32'd4;
            exmem_rd <= idex_rd;
            exmem_load_funct3 <= idex_funct3;
            exmem_mem_size <= idex_mem_size;
            exmem_regwrite <= idex_valid && idex_regwrite;
            exmem_memread <= idex_valid && idex_memread;
            exmem_memwrite <= idex_valid && idex_memwrite;
            exmem_memtoreg <= idex_valid && idex_memtoreg;
            exmem_link <= idex_is_jal || idex_is_jalr;

            if (ex_redirect || load_use_stall || !ifid_valid) begin
                idex_valid <= 1'b0;
                idex_pc <= 32'b0;
                idex_instr <= NOP;
                idex_imm <= 32'b0;
                idex_rs1_value <= 32'b0;
                idex_rs2_value <= 32'b0;
                idex_rs1 <= 5'b0;
                idex_rs2 <= 5'b0;
                idex_rd <= 5'b0;
                idex_funct3 <= 3'b0;
                idex_alu_ctrl <= ALU_ADD;
                idex_regwrite <= 1'b0;
                idex_memread <= 1'b0;
                idex_memwrite <= 1'b0;
                idex_memtoreg <= 1'b0;
                idex_alu_src_imm <= 1'b0;
                idex_alu_src_pc <= 1'b0;
                idex_alu_src_zero <= 1'b0;
                idex_is_branch <= 1'b0;
                idex_is_jal <= 1'b0;
                idex_is_jalr <= 1'b0;
                idex_mem_size <= 2'b10;
            end else begin
                idex_valid <= ifid_valid;
                idex_pc <= ifid_pc;
                idex_instr <= ifid_instr;
                idex_imm <= dec_imm;
                idex_rs1_value <= rf_rdata1;
                idex_rs2_value <= rf_rdata2;
                idex_rs1 <= dec_rs1;
                idex_rs2 <= dec_rs2;
                idex_rd <= dec_rd;
                idex_funct3 <= dec_funct3;
                idex_alu_ctrl <= dec_alu_ctrl;
                idex_regwrite <= dec_regwrite;
                idex_memread <= dec_memread;
                idex_memwrite <= dec_memwrite;
                idex_memtoreg <= dec_memtoreg;
                idex_alu_src_imm <= dec_alu_src_imm;
                idex_alu_src_pc <= dec_alu_src_pc;
                idex_alu_src_zero <= dec_alu_src_zero;
                idex_is_branch <= dec_is_branch;
                idex_is_jal <= dec_is_jal;
                idex_is_jalr <= dec_is_jalr;
                idex_mem_size <= dec_mem_size;
            end

            if (ex_redirect) begin
                pc <= ex_redirect_target;
                ifid_valid <= 1'b0;
                ifid_pc <= 32'b0;
                ifid_instr <= NOP;
            end else if (load_use_stall) begin
                // Hold fetch and IF/ID while inserting one bubble into ID/EX.
                pc <= pc;
                ifid_valid <= ifid_valid;
                ifid_pc <= ifid_pc;
                ifid_instr <= ifid_instr;
            end else begin
                pc <= pc + 32'd4;
                ifid_valid <= 1'b1;
                ifid_pc <= pc;
                ifid_instr <= if_instr;
            end
        end
    end

    integer imem_index;
    initial begin
        for (imem_index = 0; imem_index < 1024; imem_index = imem_index + 1)
            imem[imem_index] = NOP;
        $readmemh("test.mem", imem);
    end
endmodule


