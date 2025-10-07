module lab1_shared #
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

// State machine states
typedef enum logic [2:0] {
	IDLE = 3'b000,
	STAGE1 = 3'b001,  // A5 * x + A4
	STAGE2 = 3'b010,  // (A5 * x + A4) * x + A3
	STAGE3 = 3'b011,  // ((A5 * x + A4) * x + A3) * x + A2
	STAGE4 = 3'b100,  // (((A5 * x + A4) * x + A3) * x + A2) * x + A1
	STAGE5 = 3'b101,  // ((((A5 * x + A4) * x + A3) * x + A2) * x + A1) * x + A0
	OUTPUT = 3'b110   // Output result
} state_t;

// State machine signals
state_t current_state, next_state;

// Shared multiplier and adder inputs/outputs
logic [31:0] mult_a, mult_b;
logic [31:0] add_a;
logic [15:0] add_b;
logic [31:0] mult_result, add_result;

// Storage registers
logic [WIDTHIN-1:0] x_reg;
logic [WIDTHOUT-1:0] temp_reg1, temp_reg2, temp_reg3, temp_reg4;
logic [WIDTHOUT-1:0] y_reg;

// Control signals
logic valid_reg;
logic enable;

// Shared multiplier
mult32x16 shared_mult (
	.i_dataa(mult_a),
	.i_datab(mult_b),
	.o_res(mult_result)
);

// Shared adder
addr32p16 shared_add (
	.i_dataa(add_a),
	.i_datab(add_b),
	.o_res(add_result)
);

// Combinational logic for control
always_comb begin
	enable = i_ready;
	
	// Default values
	mult_a = 0;
	mult_b = 0;
	add_a = 0;
	add_b = 0;
	next_state = current_state;
	
	case (current_state)
		IDLE: begin
			if (i_valid && i_ready) begin
				next_state = STAGE1;
			end
		end
		
		STAGE1: begin
			next_state = STAGE2;
			// A5 * x
			mult_a = {16'b0, A5};
			mult_b = {16'b0, x_reg};
		end
		
		STAGE2: begin
			next_state = STAGE3;
			// (A5 * x + A4) * x
			mult_a = temp_reg1;  // A5 * x + A4
			mult_b = {16'b0, x_reg};
		end
		
		STAGE3: begin
			next_state = STAGE4;
			// ((A5 * x + A4) * x + A3) * x
			mult_a = temp_reg3;  // ((A5 * x + A4) * x + A3)
			mult_b = {16'b0, x_reg};
		end
		
		STAGE4: begin
			next_state = STAGE5;
			// (((A5 * x + A4) * x + A3) * x + A2) * x
			mult_a = temp_reg4;  // (((A5 * x + A4) * x + A3) * x + A2)
			mult_b = {16'b0, x_reg};
		end
		
		STAGE5: begin
			next_state = OUTPUT;
			// ((((A5 * x + A4) * x + A3) * x + A2) * x + A1) * x
			mult_a = y_reg;  // ((((A5 * x + A4) * x + A3) * x + A2) * x + A1)
			mult_b = {16'b0, x_reg};
		end
		
		OUTPUT: begin
			next_state = IDLE;
		end
		
		default: begin
			next_state = IDLE;
		end
	endcase
end

// Combinational logic for adder inputs
always_comb begin
	case (current_state)
		STAGE1: begin
			// A5 * x + A4
			add_a = mult_result;  // A5 * x
			add_b = A4;  // A4
		end
		
		STAGE2: begin
			// (A5 * x + A4) * x + A3
			add_a = mult_result;  // (A5 * x + A4) * x
			add_b = A3;  // A3
		end
		
		STAGE3: begin
			// ((A5 * x + A4) * x + A3) * x + A2
			add_a = mult_result;  // ((A5 * x + A4) * x + A3) * x
			add_b = A2;  // A2
		end
		
		STAGE4: begin
			// (((A5 * x + A4) * x + A3) * x + A2) * x + A1
			add_a = mult_result;  // (((A5 * x + A4) * x + A3) * x + A2) * x
			add_b = A1;  // A1
		end
		
		STAGE5: begin
			// ((((A5 * x + A4) * x + A3) * x + A2) * x + A1) * x + A0
			add_a = mult_result;  // ((((A5 * x + A4) * x + A3) * x + A2) * x + A1) * x
			add_b = A0;  // A0
		end
		
		default: begin
			add_a = 0;
			add_b = 0;
		end
	endcase
end

// Sequential logic
always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		current_state <= IDLE;
		x_reg <= 0;
		temp_reg1 <= 0;
		temp_reg2 <= 0;
		temp_reg3 <= 0;
		temp_reg4 <= 0;
		y_reg <= 0;
		valid_reg <= 0;
	end else if (enable) begin
		current_state <= next_state;
		
		// Store input when starting computation
		if (current_state == IDLE && i_valid && i_ready) begin
			x_reg <= i_x;
			valid_reg <= i_valid;
		end
		
		// Store intermediate results based on current state
		case (current_state)
			STAGE1: begin
				temp_reg1 <= add_result;  // A5 * x + A4
			end
			
			STAGE2: begin
				temp_reg3 <= add_result;  // (A5 * x + A4) * x + A3
			end
			
			STAGE3: begin
				temp_reg4 <= add_result;  // ((A5 * x + A4) * x + A3) * x + A2
			end
			
			STAGE4: begin
				y_reg <= add_result;  // (((A5 * x + A4) * x + A3) * x + A2) * x + A1
			end
			
			STAGE5: begin
				y_reg <= add_result;  // ((((A5 * x + A4) * x + A3) * x + A2) * x + A1) * x + A0
			end
		endcase
	end
end

// Output assignments
assign o_y = y_reg;
assign o_ready = (current_state == IDLE) && i_ready;
assign o_valid = (current_state == OUTPUT) && valid_reg && i_ready;

endmodule

/*******************************************************************************************/

// Multiplier module for all multiplications (32x16)
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