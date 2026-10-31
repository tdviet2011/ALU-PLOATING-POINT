`timescale 1ns / 1ps

module Floating_Point_to_Integer(
    input  [31:0] a_operand,
    output [31:0] Integer_1
);

reg [22:0] frac_new;
reg [22:0] mask;
integer n;

always @(*) begin

    frac_new = 23'd0;
    mask     = 23'd0;

    // exp < 127 => |x| < 1
    if(a_operand[30:23] <= 8'd126) begin
        frac_new = 23'd0;
    end
// exp >= 150 => mọi bit fraction đều thuộc phần nguyên
    else if(a_operand[30:23] >= 8'd150) begin
        frac_new = a_operand[22:0];
    end
    // 127 <= exp <= 149
    else begin
        n = a_operand[30:23] - 127;

        mask = 23'h7FFFFF << (23 - n);

        frac_new = a_operand[22:0] & mask;

    end
	 
end

assign Integer_1 =
{
    a_operand[31],      // sign
    a_operand[30:23],   // exponent giữ nguyên
    frac_new            // fraction đã bỏ phần lẻ
};
endmodule