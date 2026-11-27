`timescale 1ns / 1ps

// 32-bit register on the byte-wide SRAM bus: bit 0 reads TX ready;
// writing the low byte starts an 8-N-1 transmission.
module uart_mmio #(
    parameter [10:0] BASE_ADDR = 11'h1fc,
    parameter CLKS_PER_BIT = 868
) (
    input wire clk,
    input wire rst,
    input wire [10:0] addr,
    inout wire [7:0] data,
    input wire cs_n,
    input wire oe_n,
    input wire we_n,
    output wire tx,
    output reg overrun
);
    reg [7:0] read_buffer;
    reg [9:0] shift_reg;
    reg [31:0] clock_count;
    reg [3:0] bit_count;
    reg busy;
    wire selected = addr[10:2] == BASE_ADDR[10:2];

    assign data = (!cs_n && !oe_n && we_n && selected) ? read_buffer : 8'bz;
    assign tx = busy ? shift_reg[0] : 1'b1;

    initial begin
        if (CLKS_PER_BIT < 1 || BASE_ADDR[1:0] != 0)
            $fatal(1, "UART requires CLKS_PER_BIT >= 1 and a word-aligned BASE_ADDR");
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            read_buffer <= 8'd0;
            shift_reg <= 10'h3ff;
            clock_count <= 0;
            bit_count <= 0;
            busy <= 0;
            overrun <= 0;
        end else begin
            if (!cs_n && selected && we_n)
                read_buffer <= (addr[1:0] == 0) ? {7'd0, !busy} : 8'd0;

            if (busy) begin
                if (clock_count == CLKS_PER_BIT - 1) begin
                    clock_count <= 0;
                    shift_reg <= {1'b1, shift_reg[9:1]};
                    if (bit_count == 9)
                        busy <= 0;
                    else
                        bit_count <= bit_count + 1'b1;
                end else begin
                    clock_count <= clock_count + 1'b1;
                end
            end

            if (!cs_n && !we_n && addr == BASE_ADDR) begin
                if (busy) begin
                    overrun <= 1;
                end else begin
                    shift_reg <= {1'b1, data, 1'b0};
                    clock_count <= 0;
                    bit_count <= 0;
                    busy <= 1;
                end
            end
        end
    end
endmodule
