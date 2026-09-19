`timescale 1ns / 1ps

module decoder (
    input  wire [3:0] opcode,
    input  wire [3:0] operand,
    output reg  [2:0] r0_sel,
    output reg        r0_load,
    output reg  [1:0] r1_sel,
    output reg        r1_load,
    output reg  [2:0] alu_op,
    output reg        alu_enable,
    output reg        flags_write,
    output reg        branch_unconditional,
    output reg        branch_on_c,
    output reg        branch_on_v,
    output reg        io_read,
    output reg        io_write,
    output reg        io_valid,
    output reg        io_port,
    output reg        halt
);

localparam [2:0] R0_SEL_HOLD = 3'd0;
localparam [2:0] R0_SEL_ALU  = 3'd1;
localparam [2:0] R0_SEL_IMM  = 3'd2;
localparam [2:0] R0_SEL_R1   = 3'd3;
localparam [2:0] R0_SEL_PORT = 3'd4;

localparam [1:0] R1_SEL_HOLD = 2'd0;
localparam [1:0] R1_SEL_ALU  = 2'd1;
localparam [1:0] R1_SEL_IMM  = 2'd2;
localparam [1:0] R1_SEL_R0   = 2'd3;

localparam [2:0] ALU_ADD = 3'd0;
localparam [2:0] ALU_SUB = 3'd1;
localparam [2:0] ALU_AND = 3'd2;
localparam [2:0] ALU_XOR = 3'd3;

always @* begin
    r0_sel              = R0_SEL_HOLD;
    r0_load             = 1'b0;
    r1_sel              = R1_SEL_HOLD;
    r1_load             = 1'b0;
    alu_op              = ALU_AND;
    alu_enable          = 1'b0;
    flags_write         = 1'b0;
    branch_unconditional = 1'b0;
    branch_on_c         = 1'b0;
    branch_on_v         = 1'b0;
    io_read             = 1'b0;
    io_write            = 1'b0;
    io_valid            = 1'b0;
    io_port             = 1'b0;
    halt                = 1'b0;

    case (opcode)
        4'h0: begin
            // NOP
        end

        4'h1: begin
            r0_sel  = R0_SEL_IMM;
            r0_load = 1'b1;
        end

        4'h2: begin
            r1_sel  = R1_SEL_IMM;
            r1_load = 1'b1;
        end

        4'h3: begin
            r0_sel      = R0_SEL_ALU;
            r0_load     = 1'b1;
            alu_op      = ALU_ADD;
            alu_enable  = 1'b1;
            flags_write = 1'b1;
        end

        4'h4: begin
            r0_sel      = R0_SEL_ALU;
            r0_load     = 1'b1;
            alu_op      = ALU_SUB;
            alu_enable  = 1'b1;
            flags_write = 1'b1;
        end

        4'h5: begin
            r0_sel     = R0_SEL_ALU;
            r0_load    = 1'b1;
            alu_op     = ALU_AND;
            alu_enable = 1'b1;
        end

        4'h6: begin
            r0_sel     = R0_SEL_ALU;
            r0_load    = 1'b1;
            alu_op     = ALU_XOR;
            alu_enable = 1'b1;
        end

        4'h7: begin
            branch_unconditional = 1'b1;
        end

        4'h8: begin
            branch_on_c = 1'b1;
        end

        4'h9: begin
            branch_on_v = 1'b1;
        end

        4'hA: begin
            if (operand <= 4'd1) begin
                r0_sel   = R0_SEL_PORT;
                r0_load  = 1'b1;
                io_read  = 1'b1;
                io_valid = 1'b1;
                io_port  = operand[0];
            end
        end

        4'hB: begin
            if (operand <= 4'd1) begin
                io_write = 1'b1;
                io_valid = 1'b1;
                io_port  = operand[0];
            end
        end

        4'hC: begin
            r0_sel  = R0_SEL_R1;
            r0_load = 1'b1;
        end

        4'hD: begin
            r1_sel  = R1_SEL_R0;
            r1_load = 1'b1;
        end

        4'hE: begin
            halt = 1'b1;
        end

        4'hF: begin
            // RESERVED: NOP
        end

        default: begin
            // All four-bit opcodes are covered above.
        end
    endcase
end

endmodule
