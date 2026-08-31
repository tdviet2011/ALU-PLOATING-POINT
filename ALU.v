`timescale 1ns / 1ps

module ALU(
input  [31:0] a_operand,
    input  [31:0] b_operand,
    input  [3:0]  Operation,
	 input AddBar_Sub,
    output [31:0] ALU_Output,
    output Exception,
    output Overflow,
    output Underflow
);

//====================================================
// Internal Wires
//====================================================

wire [31:0] Add_Sub_Output;
wire [31:0] Mul_Output;
wire [31:0] Div_Output;
wire [31:0] Integer_Value;

wire Add_Sub_Exception;
wire Mul_Exception;
wire Mul_Overflow;
wire Mul_Underflow;
wire Div_Exception;

// Floating Point Adder/Subtractor
//====================================================

Addition_Subtraction AU1(
    .a_operand(a_operand),
    .b_operand(b_operand),
    .AddBar_Sub(AddBar_Sub),
    .Exception(Add_Sub_Exception),
    .result(Add_Sub_Output)
);

//====================================================
// Floating Point Multiplier
//====================================================

Multiplication MU1(
    .a_operand(a_operand),
    .b_operand(b_operand),
    .Exception(Mul_Exception),
    .Overflow(Mul_Overflow),
    .Underflow(Mul_Underflow),
    .result(Mul_Output)
);

//====================================================
// Floating Point Divider
//====================================================

Division DU1(
    .a_operand(a_operand),
    .b_operand(b_operand),
    .Exception(Div_Exception),
    .result(Div_Output)
);
//====================================================
// Float -> Integer
//====================================================

Floating_Point_to_Integer FU1(
    .a_operand(a_operand),
    .Integer_1(Integer_Value)
);
//====================================================
// Output Registers
//====================================================

reg [31:0] ALU_Output_reg;

reg Exception_reg;
reg Overflow_reg;
reg Underflow_reg;

//====================================================
// ALU MUX
//====================================================
always @(*) begin

    ALU_Output_reg = 32'd0;

    Exception_reg = 1'b0;
    Overflow_reg  = 1'b0;
    Underflow_reg = 1'b0;

    case(Operation)
		4'd0:
        begin
            ALU_Output_reg = Add_Sub_Output;

            Exception_reg = Add_Sub_Exception;
        end
		  //------------------------------------------------
        // Floating Point Multiply
        //------------------------------------------------
        4'd1:
        begin
            ALU_Output_reg = Mul_Output;

            Exception_reg = Mul_Exception;
            Overflow_reg  = Mul_Overflow;
            Underflow_reg = Mul_Underflow;
        end
		  
		  //------------------------------------------------
        // Floating Point Divide
        //------------------------------------------------
        4'd2:
        begin
            ALU_Output_reg = Div_Output;

            Exception_reg = Div_Exception;
        end
		  //------------------------------------------------
        // Floating Point Subtract
        //------------------------------------------------
        4'd3:
        begin
            ALU_Output_reg = Add_Sub_Output;

            Exception_reg = Add_Sub_Exception;
        end
		   //------------------------------------------------
        // OR
        //------------------------------------------------
        4'd4:
        begin
            ALU_Output_reg = a_operand | b_operand;
        end
		  //------------------------------------------------
        // AND
        //------------------------------------------------
        4'd5:
        begin
            ALU_Output_reg = a_operand & b_operand;
        end
		     //------------------------------------------------
        // XOR
        //------------------------------------------------
        4'd6:
        begin
            ALU_Output_reg = a_operand ^ b_operand;
        end
		  //------------------------------------------------
        // Shift Left
        //------------------------------------------------
        4'd7:
        begin
            ALU_Output_reg = a_operand << 1;
        end
		   //------------------------------------------------
        // Shift Right
        //------------------------------------------------
        4'd8:
        begin
            ALU_Output_reg = a_operand >> 1;
        end
			 //------------------------------------------------
        // Float -> Integer
        //------------------------------------------------
        4'd9:
        begin
            ALU_Output_reg = Integer_Value;
        end
		  //------------------------------------------------
        // Floating Point Add
        //------------------------------------------------
        4'd10:
        begin
            ALU_Output_reg = Add_Sub_Output;
            Exception_reg = Add_Sub_Exception;
        end
		  //------------------------------------------------
        // Bitwise Complement
        //------------------------------------------------
        4'd11:
        begin
            ALU_Output_reg = ~a_operand;
        end
		   //------------------------------------------------
        // Default
        //------------------------------------------------
        default:
        begin
            ALU_Output_reg = 32'd0;
        end

    endcase
end 
//====================================================
// Outputs
//====================================================

assign ALU_Output = ALU_Output_reg;
assign Exception  = Exception_reg;
assign Overflow   = Overflow_reg;
assign Underflow  = Underflow_reg;
endmodule
