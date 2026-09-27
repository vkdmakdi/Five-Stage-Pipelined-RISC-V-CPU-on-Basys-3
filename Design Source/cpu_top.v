`timescale 1ns / 1ps
module cpu_top #(
    parameter integer CLK_DIVIDER = 5_000_000
) (
    input  wire       clk_in,
    input  wire       reset,
    output wire [7:0] led
);
    localparam integer COUNT_WIDTH = (CLK_DIVIDER < 2) ? 1 : $clog2(CLK_DIVIDER);

    reg [COUNT_WIDTH-1:0] divider_count = {COUNT_WIDTH{1'b0}};
    wire cpu_step = (divider_count == CLK_DIVIDER - 1);
    wire [31:0] debug_pc;

    // Advance the CPU once per divider interval without creating a new clock.
    always @(posedge clk_in) begin
        if (reset) begin
            divider_count <= {COUNT_WIDTH{1'b0}};
        end else if (cpu_step) begin
            divider_count <= {COUNT_WIDTH{1'b0}};
        end else begin
            divider_count <= divider_count + 1'b1;
        end
    end

    cpu cpu_core (
        .clk(clk_in),
        .reset(reset),
        .step_en(cpu_step),
        .debug_pc(debug_pc)
    );

    // Binary instruction-word address, useful for bring-up and logic probing.
    assign led = debug_pc[9:2];
endmodule
