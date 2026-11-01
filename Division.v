`timescale 1ns / 1ps
//==============================================================================
// Division.v  -  IEEE 754 single precision divider (exact, round-to-nearest-even)
//
// Algorithm: unrolled restoring (long) division of the significands.
//   1. Subnormal operands are normalised first (leading-zero count) so both
//      significands na, nb have their MSB at bit 23: na/nb is in (0.5, 2).
//   2. 26 quotient bits  Q = floor(na * 2^25 / nb)  are produced by 26 compare-
//      subtract steps; the final remainder gives the sticky bit.
//         Q[25] = 1  ->  na/nb >= 1, exponent  e = ea' - eb' + 127
//         Q[25] = 0  ->  na/nb <  1, exponent  e = ea' - eb' + 126
//      Q has 24 significand bits + guard + (remainder != 0) as sticky, which is
//      exactly what round-to-nearest-even needs (fp_round_pack).
//   3. Special cases: NaN, 0/0, Inf/Inf -> NaN; Inf/x -> Inf; x/Inf -> 0;
//      x/0 -> Inf; 0/x -> 0.
//
// Why this replaced the Newton-Raphson datapath of the original design
//   The original computed 1/b with a seed constant and 3 Newton-Raphson
//   iterations (X(n+1) = X(n) * (2 - D*X(n))), i.e. 8 24x24 multipliers and
//   4 floating point adders in one combinational chain, then multiplied by a.
//   It was wrong in 46% of the cases with a mantissa >= 1.875 (seed constant
//   -37/17 instead of -32/17) and, after fixing that, still 2-4 ULP off because
//   every adder/multiplier truncated. The restoring divider uses no multipliers
//   (0 DSP blocks), returns bit-exact IEEE results and handles subnormals.
//   Its drawback is the same as any combinational divider: a long carry chain
//   (26 sequential 25-bit subtractors); pipeline it if timing is critical.
//
// Port order: a, b, Exception, result; Overflow/Underflow are new (last).
//==============================================================================
module Division(
    input  [31:0] a_operand,
    input  [31:0] b_operand,
    output        Exception,       // an operand is Inf or NaN (exponent = 255)
    output [31:0] result,
    output        Overflow,        // finite operands, result rounds to Inf
    output        Underflow        // result is subnormal and inexact
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

    //------------------------------------------- unpack and normalise operands
    wire [7:0]  ea_e = (ea == 8'd0) ? 8'd1 : ea;      // subnormal: exponent 1
    wire [7:0]  eb_e = (eb == 8'd0) ? 8'd1 : eb;
    wire [23:0] ma   = {(ea != 8'd0), a_operand[22:0]};
    wire [23:0] mb   = {(eb != 8'd0), b_operand[22:0]};

    wire [23:0] na, nb;                               // MSB at bit 23
    wire [6:0]  lza, lzb;
    priority_encoder #(24) pea (.in(ma), .out(na), .lz(lza));
    priority_encoder #(24) peb (.in(mb), .out(nb), .lz(lzb));

    //---------------------------------------- restoring division, 26 bits
    reg [25:0] q;
    reg [24:0] r, t;
    reg        rem_nz;
    integer    i;

    always @(*) begin
        q = 26'd0;
        // first quotient bit: na >= nb ? (na and nb are both in [2^23, 2^24))
        if (na >= nb) begin
            q[25] = 1'b1;
            r     = {1'b0, na} - {1'b0, nb};
        end else begin
            q[25] = 1'b0;
            r     = {1'b0, na};
        end
        // remaining 25 bits: shift the remainder, subtract the divisor if it fits
        for (i = 24; i >= 0; i = i - 1) begin
            t = {r[23:0], 1'b0};                      // r < nb < 2^24
            if (t >= {1'b0, nb}) begin
                q[i] = 1'b1;
                r    = t - {1'b0, nb};
            end else begin
                q[i] = 1'b0;
                r    = t;
            end
        end
        rem_nz = (r != 25'd0);
    end

    //------------------------------------------ build n[27:0], round and pack
    // n[27:4] significand, n[3] guard, n[2:0] sticky (remainder folded into n[0])
    wire [27:0] n = (q[25] ? {q, 2'b00} : {q[24:0], 3'b000}) | {27'd0, rem_nz};

    wire signed [11:0] e = $signed({4'b0000, ea_e}) - $signed({5'b00000, lza})
                         - $signed({4'b0000, eb_e}) + $signed({5'b00000, lzb})
                         + (q[25] ? 12'sd127 : 12'sd126);

    wire [31:0] packed_res;
    wire        pk_of, pk_uf;
    fp_round_pack #(28) rp (.sign(sign), .e(e), .n(n),
                            .result(packed_res), .overflow(pk_of), .underflow(pk_uf));

    //------------------------------------------------------------ result mux
    wire invalid = a_nan | b_nan | (a_zero & b_zero) | (a_inf & b_inf);
    wire special = invalid | a_inf | b_inf | a_zero | b_zero;

    assign result = invalid ? 32'h7FC00000 :
                    a_inf   ? {sign, 8'hFF, 23'd0} :     // Inf / x
                    b_inf   ? {sign, 31'd0}        :     // x / Inf
                    b_zero  ? {sign, 8'hFF, 23'd0} :     // x / 0
                    a_zero  ? {sign, 31'd0}        :     // 0 / x
                              packed_res;

    assign Overflow  = ~special & pk_of;
    assign Underflow = ~special & pk_uf;
endmodule
