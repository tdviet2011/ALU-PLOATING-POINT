`timescale 1ns / 1ps

module TB_ALU;

	// Inputs
	reg [31:0] a_operand;
	reg [31:0] b_operand;
	reg [3:0] Operation;
	reg AddBar_Sub;

	// Outputs
	wire [31:0] ALU_Output;
	wire Exception;
	wire Overflow;
	wire Underflow;

	// Instantiate the Unit Under Test (UUT)
	ALU uut (
		.a_operand(a_operand), 
		.b_operand(b_operand), 
		.Operation(Operation),
		.AddBar_Sub(AddBar_Sub),
		.ALU_Output(ALU_Output), 
		.Exception(Exception), 
		.Overflow(Overflow), 
		.Underflow(Underflow)
	);
	initial begin
		$display("==============================================");
		$display("        FLOATING POINT ALU TESTBENCH");
		$display("==============================================");
		//----------------------------------
		// ADDITION
		//----------------------------------

		// 1.5 + 2.5 = 4.0
		$display("\n[ADD] 1.5 + 2.5 = 4.0");
		Operation = 4'b0000;
		AddBar_Sub = 0;
		a_operand = 32'h3FC00000;
		b_operand = 32'h40200000;
		#100;
		$display("Result = %h  Exception=%b Overflow=%b Underflow=%b",
				 ALU_Output, Exception, Overflow, Underflow);

		$display("\n[ADD] -1.5 + 2.5 = 1.0");
		Operation = 4'b0000;
		a_operand = 32'hBFC00000;
		b_operand = 32'h40200000;
		AddBar_Sub = 0;
		#100;
		$display("Result = %h  Exception=%b Overflow=%b Underflow=%b",
				 ALU_Output, Exception, Overflow, Underflow);
		//----------------------------------
		// SUBTRACTION
		//----------------------------------
		$display("\n[SUB] 5.5 - 2.5 = 3.0");
		Operation = 4'b0001;
		AddBar_Sub = 1;
		a_operand = 32'h40B00000;
		b_operand = 32'h40200000;
		#100;
		$display("Result = %h", ALU_Output);
		#100;
		$display("\n[SUB] -2.5 - (-5.5) = 3.0");
		AddBar_Sub = 1;
		Operation = 4'b0001;
		a_operand = 32'hC0200000;
		b_operand = 32'hC0B00000;
		#100;
		$display("Result = %h", ALU_Output);
		//----------------------------------
		// MULTIPLICATION
		//----------------------------------

		$display("\n[MUL] 2.0 * 3.0 = 6.0");
		Operation = 4'b0010;
		a_operand = 32'h40000000;
		b_operand = 32'h40400000;
		#100;
		$display("Result = %h", ALU_Output);
		#100;
		$display("\n[MUL] -2.5 * -4.0 = 10.0");
		Operation = 4'b0010;
		a_operand = 32'hC0200000;
		b_operand = 32'hC0800000;
		#100;
		$display("Result = %h", ALU_Output);
		//----------------------------------
		// DIVISION
		//----------------------------------

		$display("\n[DIV] 37.5 / 12.5 = 3.0");
		Operation = 4'b0011;
		a_operand = 32'h42160000;
		b_operand = 32'h41480000;
		#100;
		$display("Result = %h", ALU_Output);

		$display("\n[DIV] -62.5 / 25.0 = -2.5");
		Operation = 4'b0011;
		a_operand = 32'hC27A0000;
		b_operand = 32'h41C80000;
		#100;
		$display("Result = %h", ALU_Output);
		//----------------------------------
		// FLOAT -> INTEGER
		//----------------------------------

		$display("\n[FLOAT->INT] 10.0 -> 10");
		Operation = 4'b0100;
		a_operand = 32'h41200000;
		b_operand = 32'h00000000;
		#100;
		$display("Result = %h", ALU_Output);

		$display("\n[FLOAT->INT] -3.0 -> -3");
		Operation = 4'b0100;
		a_operand = 32'hC0400000;
		b_operand = 32'h00000000;
		#100;
		$display("Result = %h", ALU_Output);

		//----------------------------------
		// SPECIAL CASES
		//----------------------------------

		$display("\n[SPECIAL] +Inf + 1.0");
		Operation = 4'b0000;
		a_operand = 32'h7F800000;
		b_operand = 32'h3F800000;
		#100;
		$display("Result = %h  Exception=%b",
				 ALU_Output, Exception);

		$display("\n[SPECIAL] NaN * 2.0");
		Operation = 4'b0010;
		a_operand = 32'h7FC00000;
		b_operand = 32'h40000000;
		#100;
		$display("Result = %h  Exception=%b",
				 ALU_Output, Exception);

		$display("\n========== TEST FINISHED ==========");
		$finish;
end
	
      
endmodule

