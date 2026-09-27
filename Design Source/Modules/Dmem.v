`timescale 1ns / 1ps
module dmem #(
    parameter integer MEM_BYTES = 256
) (
    input  wire        clk,
    input  wire        we,
    input  wire [1:0]  size,   // 00=byte, 01=halfword, 10=word
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);

    // The 256-byte default keeps this FPGA demo within the target device.
    reg [7:0] mem [0:MEM_BYTES-1];
    wire byte_ok = (addr < MEM_BYTES);
    wire half_ok = (addr <= MEM_BYTES-2);
    wire word_ok = (addr <= MEM_BYTES-4);

    // Little-endian byte writes. Out-of-range accesses are ignored.
    always @(posedge clk) begin
        if (we) begin
            case (size)
                2'b00: if (byte_ok)
                    mem[addr] <= wdata[7:0];
                2'b01: if (half_ok) begin
                    mem[addr]     <= wdata[7:0];
                    mem[addr + 1] <= wdata[15:8];
                end
                2'b10: if (word_ok) begin
                    mem[addr]     <= wdata[7:0];
                    mem[addr + 1] <= wdata[15:8];
                    mem[addr + 2] <= wdata[23:16];
                    mem[addr + 3] <= wdata[31:24];
                end
                default: ;
            endcase
        end
    end

    // Unwritten bytes are unspecified; invalid reads return zero.
    always @(*) begin
        rdata = 32'b0;
        case (size)
            2'b00: if (byte_ok)
                rdata = {24'b0, mem[addr]};
            2'b01: if (half_ok)
                rdata = {16'b0, mem[addr + 1], mem[addr]};
            2'b10: if (word_ok)
                rdata = {mem[addr + 3], mem[addr + 2], mem[addr + 1], mem[addr]};
            default: ;
        endcase
    end
endmodule
