`timescale 1ns / 1ps
//==============================================================================
// priority_encoder.v  -  shared helper blocks for the floating point datapath
//
//  1. priority_encoder #(W)  : leading-zero counter + normalising left shifter
//  2. fp_round_pack  #(W)    : IEEE 754 round-to-nearest-even + pack into float32
//
// Both are used by Addition_Subtraction, Multiplication and Division, so all
// three operations share one rounding / overflow / underflow implementation.
//
// Changes against the original file
//  - The original was a 25-way casex ladder. Its "default" branch (a negative
//    difference) and the all-zero branch (shift = 24) produced wrong results
//    for x - x and for exponent differences >= 24. It is replaced by a generic
//    loop that synthesises to a priority chain of W inputs.
//  - Rounding (guard / sticky bits, ties-to-even) and overflow / underflow
//    detection used to be missing; they now live in fp_round_pack.
//==============================================================================

//------------------------------------------------------------------------------
// Leading-zero counter and normaliser.
//   out = in << lz, so out[W-1] = 1 whenever in != 0.
//   lz  = number of leading zeros (= W when in == 0).
//------------------------------------------------------------------------------
module priority_encoder #(parameter W = 28)(
    input      [W-1:0] in,
    output reg [W-1:0] out,
    output reg [6:0]   lz
);
    integer i;
    reg     found;

    always @(*) begin
        lz    = W;
        found = 1'b0;
        // scan from the MSB: the first '1' fixes the shift amount
        for (i = W - 1; i >= 0; i = i - 1)
            if (!found && in[i]) begin
                lz    = W - 1 - i;
                found = 1'b1;
            end
        out = (lz >= W) ? {W{1'b0}} : (in << lz);
    end
endmodule

//------------------------------------------------------------------------------
// Round-to-nearest-even and packing.
//   n[W-1:0] : normalised significand, n[W-1] = 1 (n != 0).
//              n[W-1:W-24] = 24-bit significand (hidden bit first),
//              n[W-25]     = guard bit,
//              n[W-26:0]   = sticky bits (OR of everything below the guard).
//   e        : biased exponent that n[W-1] would carry, i.e. the value is
//              1.xxx * 2^(e-127). e can be <= 0 (result is subnormal) or
//              > 254 (result overflows).
// Subnormal results: n is shifted right by (1 - e) with the shifted-out bits
// folded into the sticky term, then rounded like a normal number.
// Packing trick: bits = ((e-1) << 23) + significand. A rounding carry out of
// the significand increments the exponent automatically, and a subnormal that
// rounds up to 2^23 becomes the smallest normal number.
//------------------------------------------------------------------------------
module fp_round_pack #(parameter W = 28)(
    input                sign,
    input  signed [11:0] e,
    input      [W-1:0]   n,
    output     [31:0]    result,
    output               overflow,    // result became +/-Inf
    output               underflow    // tiny (subnormal range) and inexact
);
    integer      sh;
    reg [W-1:0]  m;
    reg          lost, guard, sticky, inc;
    reg [23:0]   sig;
    reg [24:0]   sigr;
    reg [31:0]   base, val;
    reg          of_r, uf_r;

    always @(*) begin
        // right shift needed to reach the subnormal alignment
        sh = (e >= 12'sd1) ? 0 : (1 - e);
        if (sh == 0) begin
            m    = n;
            lost = 1'b0;
        end else if (sh >= W) begin
            m    = {W{1'b0}};
            lost = (n != {W{1'b0}});
        end else begin
            m    = n >> sh;
            lost = ((m << sh) != n);          // were any '1' bits shifted out?
        end

        sig    = m[W-1:W-24];
        guard  = m[W-25];
        sticky = (|m[W-26:0]) | lost;
        inc    = guard & (sticky | sig[0]);   // ties go to the even significand
        sigr   = {1'b0, sig} + inc;

        base   = (e >= 12'sd1) ? (e - 12'sd1) : 32'd0;
        val    = (base << 23) + sigr;
        of_r   = (val >= 32'h7F800000);
        uf_r   = (e < 12'sd1) & (guard | sticky);
    end

    assign result    = of_r ? {sign, 8'hFF, 23'h0} : {sign, val[30:0]};
    assign overflow  = of_r;
    assign underflow = uf_r;
endmodule
