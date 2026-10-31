`timescale 1ns / 1ps
//==============================================================================
// ADD_SUB.v  -  IEEE 754 single precision adder / subtractor
// Original author: Sheetal Swaroop Burada (2019), Dayalbagh Educational Institute.
// Rewritten: correct rounding, subnormals, Inf/NaN, overflow/underflow flags.
//
// Algorithm (purely combinational)
//   1. Operand b gets the effective sign  sb = sign(b) XOR AddBar_Sub, so a - b
//      is handled as a + (-b).
//   2. Order the operands by magnitude (x >= y) so the subtraction never goes
//      negative and the result sign is the sign of x.
//   3. Alignment: shift y right by d = ex - ey. The shifted-out bits are
//      collapsed into one sticky bit, giving 3 extra bits (guard, round, sticky).
//      (Subnormals use exponent 1 and hidden bit 0.)
//   4. Add or subtract the 27-bit extended significands (28-bit result).
//   5. Normalise with a leading-zero count (priority_encoder), then round to
//      nearest-even and pack (fp_round_pack).
//
// Fixes against the original
//   - Two's complement of the shifted significand was only 24 bits wide, so for
//     an exponent difference >= 24 the carry was lost and the result was wrong
//     (3e38 - 1.0 gave 1.7e38).
//   - x - x returned 2^-24 instead of +0.
//   - No guard/round/sticky bits: results were truncated (up to 1 ULP off);
//     now round-to-nearest-even, bit-exact against IEEE 754.
//   - Inf/NaN operands returned 0; now NaN -> qNaN, Inf +- Inf handled.
//   - Overflow (result > 3.4e38) is detected and returns +/-Inf; Underflow flag
//     added.
//   - Removed the always-true 'perform' signal and the extra exponent adder.
//
// Ports: the first five keep the original order (a, b, AddBar_Sub, Exception,
// result); Overflow/Underflow are new and come last.
//==============================================================================
module Addition_Subtraction(
    input  [31:0] a_operand,
    input  [31:0] b_operand,
    input         AddBar_Sub,      // 0: a + b, 1: a - b
    output        Exception,       // an operand is Inf or NaN (exponent = 255)
    output [31:0] result,
    output        Overflow,        // finite operands, result rounds to Inf
    output        Underflow        // result is subnormal and inexact
);
    //-------------------------------------------------------------- classify
    wire       sa = a_operand[31];
    wire       sb = b_operand[31] ^ AddBar_Sub;      // effective sign of b
    wire [7:0] ea = a_operand[30:23];
    wire [7:0] eb = b_operand[30:23];

    wire a_nan = (ea == 8'hFF) && (a_operand[22:0] != 23'd0);
    wire b_nan = (eb == 8'hFF) && (b_operand[22:0] != 23'd0);
    wire a_inf = (ea == 8'hFF) && (a_operand[22:0] == 23'd0);
    wire b_inf = (eb == 8'hFF) && (b_operand[22:0] == 23'd0);

    assign Exception = (ea == 8'hFF) | (eb == 8'hFF);

    //------------------------------------------- order by magnitude (x >= y)
    wire        swap = (a_operand[30:0] < b_operand[30:0]);
    wire [31:0] x    = swap ? b_operand : a_operand;
    wire [31:0] y    = swap ? a_operand : b_operand;
    wire        sx   = swap ? sb : sa;               // result sign
    wire        sy   = swap ? sa : sb;
    wire        eff_sub = sx ^ sy;                   // magnitudes subtract

    // effective exponent: subnormals (exp = 0) behave as exponent 1, hidden bit 0
    wire [7:0]  ex = (x[30:23] == 8'd0) ? 8'd1 : x[30:23];
    wire [7:0]  ey = (y[30:23] == 8'd0) ? 8'd1 : y[30:23];
    wire [23:0] mx = {(x[30:23] != 8'd0), x[22:0]};
    wire [23:0] my = {(y[30:23] != 8'd0), y[22:0]};

    //------------------------------------------------------------- alignment
    wire [7:0]  d    = ex - ey;
    wire [63:0] wide = {my, 3'b000, 37'd0};
    wire [63:0] shy  = (d >= 8'd64) ? 64'd0 : (wide >> d);
    wire        lost = (d >= 8'd64) ? (wide != 64'd0) : ((shy << d) != wide);
    // 24 significand bits + guard + round + sticky (all lower bits OR-ed in)
    wire [26:0] yext = {shy[63:38], shy[37] | (|shy[36:0]) | lost};
    wire [26:0] xext = {mx, 3'b000};

    //---------------------------------------------------------- add / subtract
    wire [27:0] r = eff_sub ? ({1'b0, xext} - {1'b0, yext})
                            : ({1'b0, xext} + {1'b0, yext});
    wire        r_zero = (r == 28'd0);

    //------------------------------------------ normalise, round and pack
    wire [27:0] rn;
    wire [6:0]  lz;
    priority_encoder #(28) pe (.in(r), .out(rn), .lz(lz));

    // r[26] carries the weight of exponent ex; r[27] is the carry-out
    wire signed [11:0] e = $signed({4'b0000, ex}) + 12'sd1 - $signed({5'b00000, lz});

    wire [31:0] packed_res;
    wire        pk_of, pk_uf;
    fp_round_pack #(28) rp (.sign(sx), .e(e), .n(rn),
                            .result(packed_res), .overflow(pk_of), .underflow(pk_uf));

    //------------------------------------------------------------ result mux
    // exact zero: +0, except (-0) + (-0) = -0
    wire zero_sign = eff_sub ? 1'b0 : sx;
    wire invalid   = a_nan | b_nan | (a_inf & b_inf & (sa != sb));   // Inf - Inf
    wire special   = invalid | a_inf | b_inf;

    assign result = invalid ? 32'h7FC00000 :
                    a_inf   ? {sa, 8'hFF, 23'd0} :
                    b_inf   ? {sb, 8'hFF, 23'd0} :
                    r_zero  ? {zero_sign, 31'd0} :
                              packed_res;

    assign Overflow  = ~special & ~r_zero & pk_of;
    assign Underflow = ~special & ~r_zero & pk_uf;
endmodule
