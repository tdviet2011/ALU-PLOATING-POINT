`timescale 1ns / 1ps
//==============================================================================
// Multiplication.v  -  IEEE 754 single precision multiplier
// Original author: Sheetal Swaroop Burada (2019), Dayalbagh Educational Institute.
//
// Algorithm (purely combinational)
//   1. sign   = sign(a) XOR sign(b)
//   2. 24 x 24 -> 48-bit significand product (hidden bit = 1, or 0 for subnormal
//      inputs, which use exponent 1).
//   3. Normalise the product with a leading-zero count, so subnormal inputs
//      are handled too. The exponent of the normalised product is
//         e = ea + eb - 126 - lz     (reduces to ea + eb - 127 (+1) for normals)
//   4. Round to nearest-even and pack (fp_round_pack), which also produces
//      gradual underflow (subnormal results) and overflow to Inf.
//
// Fixes against the original
//   - The file did not compile: 'endmodule' and 'assign result' were missing and
//     four signals were assigned twice.
//   - The 'zero' flag was derived from the product mantissa, so every power of
//     two (1.0 * 1.0, 2.0 * 0.5, ...) was reported as zero. It now tests the
//     operands.
//   - Rounding added 1 on guard & sticky only: no round-half-to-even and the
//     carry out of the mantissa (0x7FFFFF + 1) never reached the exponent.
//   - Inf/NaN operands returned 0; now NaN, Inf and Inf * 0 = NaN follow IEEE.
//   - Subnormal inputs/results are supported (previously flushed or garbage).
//
// Port order is unchanged: a, b, Exception, Overflow, Underflow, result.
//==============================================================================
module Multiplication(
    input  [31:0] a_operand,
    input  [31:0] b_operand,
    output        Exception,       // an operand is Inf or NaN (exponent = 255)
    output        Overflow,        // finite operands, result rounds to Inf
    output        Underflow,       // result is subnormal and inexact
    output [31:0] result
);
    wire       sign = a_operand[31] ^ b_operand[31];
    wire [7:0] ea   = a_operand[30:23];
    wire [7:0] eb   = b_operand[30:23];

    wire a_nan  = (ea == 8'hFF) && (a_operand[22:0] != 23'd0);
    wire b_nan  = (eb == 8'hFF) && (b_operand[22:0] != 23'd0);
    wire a_inf  = (ea == 8'hFF) && (a_operand[22:0] == 23'd0);
    wire b_inf  = (eb == 8'hFF) && (b_operand[22:0] == 23'd0);
    wire a_zero = (a_operand[30:0] == 31'd0);
    wire b_zero = (b_operand[30:0] == 31'd0);

    assign Exception = (ea == 8'hFF) | (eb == 8'hFF);

    // effective exponents and significands (subnormal: exponent 1, hidden bit 0)
    wire [7:0]  ea_e = (ea == 8'd0) ? 8'd1 : ea;
    wire [7:0]  eb_e = (eb == 8'd0) ? 8'd1 : eb;
    wire [23:0] ma   = {(ea != 8'd0), a_operand[22:0]};
    wire [23:0] mb   = {(eb != 8'd0), b_operand[22:0]};

    wire [47:0] product = ma * mb;

    // normalise so that the MSB of the 48-bit product is 1
    wire [47:0] pn;
    wire [6:0]  lz;
    priority_encoder #(48) pe (.in(product), .out(pn), .lz(lz));

    wire signed [11:0] e = $signed({4'b0000, ea_e}) + $signed({4'b0000, eb_e})
                         - 12'sd126 - $signed({5'b00000, lz});

    wire [31:0] packed_res;
    wire        pk_of, pk_uf;
    fp_round_pack #(48) rp (.sign(sign), .e(e), .n(pn),
                            .result(packed_res), .overflow(pk_of), .underflow(pk_uf));

    wire invalid = a_nan | b_nan | (a_inf & b_zero) | (b_inf & a_zero);   // Inf * 0
    wire special = invalid | a_inf | b_inf | a_zero | b_zero;

    assign result = invalid          ? 32'h7FC00000 :
                    (a_inf | b_inf)  ? {sign, 8'hFF, 23'd0} :
                    (a_zero | b_zero)? {sign, 31'd0} :
                                       packed_res;

    assign Overflow  = ~special & pk_of;
    assign Underflow = ~special & pk_uf;
endmodule
