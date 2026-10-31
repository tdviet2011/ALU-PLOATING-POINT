`timescale 1ns / 1ps
//==============================================================================
// Floating_Point_to_Integer.v  -  float32 -> signed 32-bit integer (truncate)
//
// Algorithm
//   |x| < 1                  -> 0
//   1 <= |x| < 2^31          -> n = E - 127 (0..30); magnitude = {1,M} shifted
//                               by (n - 23); negate when the sign bit is set
//                               (round toward zero)
//   x = -2^31                -> 0x80000000 (exact)
//   |x| >= 2^31, +/-Inf      -> saturate to 0x7FFFFFFF / 0x80000000, Overflow = 1
//   NaN                      -> 0, Overflow = 1
//
// Fixes against the original
//   - It only cleared fraction bits and returned a float, not an integer.
//   - For |x| < 1 it kept the exponent, so trunc(0.75) returned 0.5.
//   - Inf/NaN and values >= 2^31 are now handled (saturation + Overflow flag).
//==============================================================================
module Floating_Point_to_Integer(
    input  [31:0]     a_operand,
    output reg [31:0] Integer_1,      // two's complement integer
    output reg        Overflow        // saturated, Inf or NaN
);
    wire        s = a_operand[31];
    wire [7:0]  e = a_operand[30:23];
    wire [23:0] m = {1'b1, a_operand[22:0]};
    reg  [31:0] mag;
    integer     n;

    always @(*) begin
        Overflow = 1'b0;
        mag      = 32'd0;
        n        = 0;
        if (e == 8'hFF && a_operand[22:0] != 23'd0) begin          // NaN
            Integer_1 = 32'd0;
            Overflow  = 1'b1;
        end else if (e < 8'd127) begin                             // |x| < 1
            Integer_1 = 32'd0;
        end else if (e >= 8'd158) begin                            // |x| >= 2^31
            if (s && e == 8'd158 && a_operand[22:0] == 23'd0)
                Integer_1 = 32'h80000000;                          // exactly -2^31
            else begin
                Integer_1 = s ? 32'h80000000 : 32'h7FFFFFFF;
                Overflow  = 1'b1;
            end
        end else begin                                             // 1 <= |x| < 2^31
            n = e - 127;
            if (n >= 23) mag = m << (n - 23);
            else         mag = m >> (23 - n);
            Integer_1 = s ? (~mag + 32'd1) : mag;
        end
    end
endmodule
