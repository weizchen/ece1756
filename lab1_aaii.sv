module lab1_pipelined #
(
	parameter WIDTHIN = 16,		// Input format is Q2.14 (2 integer bits + 14 fractional bits = 16 bits)
	parameter WIDTHOUT = 32,	// Intermediate/Output format is Q7.25 (7 integer bits + 25 fractional bits = 32 bits)
	// Taylor coefficients for the first five terms in Q2.14 format
	parameter [WIDTHIN-1:0] A0 = 16'b01_00000000000000, // a0 = 1
	parameter [WIDTHIN-1:0] A1 = 16'b01_00000000000000, // a1 = 1
	parameter [WIDTHIN-1:0] A2 = 16'b00_10000000000000, // a2 = 1/2
	parameter [WIDTHIN-1:0] A3 = 16'b00_00101010101010, // a3 = 1/6
	parameter [WIDTHIN-1:0] A4 = 16'b00_00001010101010, // a4 = 1/24
	parameter [WIDTHIN-1:0] A5 = 16'b00_00000010001000  // a5 = 1/120
)
(
	input clk,
	input reset,	
	
	input i_valid,
	input i_ready,
	output o_valid,
	output o_ready,
	
	input [WIDTHIN-1:0] i_x,
	output [WIDTHOUT-1:0] o_y
);

// Pipeline stage registers
logic [WIDTHIN-1:0] x_stage1, x_stage2, x_stage3, x_stage4, x_stage5;
logic [WIDTHOUT-1:0] m0_out_stage1, a0_out_stage1;
logic [WIDTHOUT-1:0] m1_out_stage2, a1_out_stage2;
logic [WIDTHOUT-1:0] m2_out_stage3, a2_out_stage3;
logic [WIDTHOUT-1:0] m3_out_stage4, a3_out_stage4;
logic [WIDTHOUT-1:0] m4_out_stage5, a4_out_stage5;

// Valid signal pipeline
logic valid_stage1, valid_stage2, valid_stage3, valid_stage4, valid_stage5;

// Intermediate computation signals
logic [WIDTHOUT-1:0] m0_out, a0_out, m1_out, a1_out, m2_out, a2_out, m3_out, a3_out, m4_out, a4_out;

// Control signals
logic enable;

// Stage 1: A5 * x
mult16x16 Mult0 (.i_dataa(A5), .i_datab(x_stage1), .o_res(m0_out));
addr32p16 Addr0 (.i_dataa(m0_out), .i_datab(A4), .o_res(a0_out));

// Stage 2: (A5 * x + A4) * x
mult32x16 Mult1 (.i_dataa(a0_out_stage1), .i_datab(x_stage2), .o_res(m1_out));
addr32p16 Addr1 (.i_dataa(m1_out), .i_datab(A3), .o_res(a1_out));

// Stage 3: ((A5 * x + A4) * x + A3) * x
mult32x16 Mult2 (.i_dataa(a1_out_stage2), .i_datab(x_stage3), .o_res(m2_out));
addr32p16 Addr2 (.i_dataa(m2_out), .i_datab(A2), .o_res(a2_out));

// Stage 4: (((A5 * x + A4) * x + A3) * x + A2) * x
mult32x16 Mult3 (.i_dataa(a2_out_stage3), .i_datab(x_stage4), .o_res(m3_out));
addr32p16 Addr3 (.i_dataa(m3_out), .i_datab(A1), .o_res(a3_out));

// Stage 5: ((((A5 * x + A4) * x + A3) * x + A2) * x + A1) * x
mult32x16 Mult4 (.i_dataa(a3_out_stage4), .i_datab(x_stage5), .o_res(m4_out));
addr32p16 Addr4 (.i_dataa(m4_out), .i_datab(A0), .o_res(a4_out));

// Combinational logic
always_comb begin
	enable = i_ready;
end

// Pipeline registers
always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		// Reset all pipeline stages
		x_stage1 <= 0; x_stage2 <= 0; x_stage3 <= 0; x_stage4 <= 0; x_stage5 <= 0;
		m0_out_stage1 <= 0; a0_out_stage1 <= 0;
		m1_out_stage2 <= 0; a1_out_stage2 <= 0;
		m2_out_stage3 <= 0; a2_out_stage3 <= 0;
		m3_out_stage4 <= 0; a3_out_stage4 <= 0;
		m4_out_stage5 <= 0; a4_out_stage5 <= 0;
		valid_stage1 <= 0; valid_stage2 <= 0; valid_stage3 <= 0; valid_stage4 <= 0; valid_stage5 <= 0;
	end else if (enable) begin
		// Stage 1: Input stage
		x_stage1 <= i_x;
		valid_stage1 <= i_valid;
		
		// Stage 2: First multiplication and addition
		x_stage2 <= x_stage1;
		m0_out_stage1 <= m0_out;
		a0_out_stage1 <= a0_out;
		valid_stage2 <= valid_stage1;
		
		// Stage 3: Second multiplication and addition
		x_stage3 <= x_stage2;
		m1_out_stage2 <= m1_out;
		a1_out_stage2 <= a1_out;
		valid_stage3 <= valid_stage2;
		
		// Stage 4: Third multiplication and addition
		x_stage4 <= x_stage3;
		m2_out_stage3 <= m2_out;
		a2_out_stage3 <= a2_out;
		valid_stage4 <= valid_stage3;
		
		// Stage 5: Fourth multiplication and addition
		x_stage5 <= x_stage4;
		m3_out_stage4 <= m3_out;
		a3_out_stage4 <= a3_out;
		valid_stage5 <= valid_stage4;
		
		// Stage 6: Final multiplication and addition (output stage)
		m4_out_stage5 <= m4_out;
		a4_out_stage5 <= a4_out;
	end
end

// Output assignments
assign o_y = a4_out_stage5;
assign o_ready = i_ready;  // Ready as long as receiver is ready
assign o_valid = valid_stage5 & i_ready;  // Valid when pipeline has valid data and receiver is ready

endmodule

/*******************************************************************************************/

// Multiplier module for the first 16x16 multiplication
module mult16x16 (
	input  [15:0] i_dataa,
	input  [15:0] i_datab,
	output [31:0] o_res
);

logic [31:0] result;

always_comb begin
	result = i_dataa * i_datab;
end

// The result of Q2.14 x Q2.14 is in the Q4.28 format. Therefore we need to change it
// to the Q7.25 format specified in the assignment by shifting right and padding with zeros.
assign o_res = {3'b000, result[31:3]};

endmodule

/*******************************************************************************************/

// Multiplier module for all the remaining 32x16 multiplications
module mult32x16 (
	input  [31:0] i_dataa,
	input  [15:0] i_datab,
	output [31:0] o_res
);

logic [47:0] result;

always_comb begin
	result = i_dataa * i_datab;
end

// The result of Q7.25 x Q2.14 is in the Q9.39 format. Therefore we need to change it
// to the Q7.25 format specified in the assignment by selecting the appropriate bits
// (i.e. dropping the most-significant 2 bits and least-significant 14 bits).
assign o_res = result[45:14];

endmodule

/*******************************************************************************************/

// Adder module for all the 32b+16b addition operations 
module addr32p16 (
	input [31:0] i_dataa,
	input [15:0] i_datab,
	output [31:0] o_res
);

// The 16-bit Q2.14 input needs to be aligned with the 32-bit Q7.25 input by zero padding
assign o_res = i_dataa + {5'b00000, i_datab, 11'b00000000000};

endmodule

/*******************************************************************************************/
