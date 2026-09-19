`timescale 1ns / 1ps

module alu (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire [2:0] op,
    output reg  [3:0] result,
    output reg        carry,
    output reg        overflow
);

localparam [2:0] ALU_ADD = 3'd0;
localparam [2:0] ALU_SUB = 3'd1;
localparam [2:0] ALU_AND = 3'd2;
localparam [2:0] ALU_XOR = 3'd3;

reg [4:0] add_value;
reg [4:0] sub_value;

always @* begin
    result   = 4'd0;
    carry    = 1'b0;
    overflow = 1'b0;
    add_value = 5'd0;
    sub_value = 5'd0;

    case (op)
        ALU_ADD: begin
            add_value = {1'b0, a} + {1'b0, b};
            result = add_value[3:0];
            carry = add_value[4];
            overflow = (~(a[3] ^ b[3])) & (result[3] ^ a[3]);
        end

        ALU_SUB: begin
            sub_value = {1'b0, a} - {1'b0, b};
            result = sub_value[3:0];
            carry = sub_value[4];
            overflow = (a[3] ^ b[3]) & (result[3] ^ a[3]);
        end

        ALU_AND: begin
            result = a & b;
        end

        ALU_XOR: begin
            result = a ^ b;
        end

        default: begin
            result = 4'd0;
            carry = 1'b0;
            overflow = 1'b0;
        end
    endcase
end

endmodule
