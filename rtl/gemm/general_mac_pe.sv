//-----------------------
// Simple MAC processing element
// 
// Description:
// This module implements a simple Multiply-Accumulate (MAC) processing element (PE)
// that can handle multiple input pairs simultaneously. It takes in multiple pairs of
// input operands, performs multiplication on each pair, and accumulates the results.
// The PE supports initialization and accumulation control signals.
// This has an output stationary structure.
//
// Parameters:
// - InDataWidth  : Width of the input data (default: 8 bits)
// - NumInputs    : Number of input pairs to process simultaneously (default: 1)
// - OutDataWidth : Width of the output data (default: 32 bits)
//
// Ports:
// - clk_i        : Clock input
// - rst_ni       : Active-low reset input
// - a_i         : Input operand A (array of NumInputs elements)
// - b_i         : Input operand B (array of NumInputs elements)
// - a_valid_i    : Valid signal for input A
// - b_valid_i    : Valid signal for input B
// - init_save_i  : Initialization signal for saving the first multiplication result
// - c_o          : Output accumulated result
//-----------------------

module general_mac_pe #(
  parameter int unsigned InDataWidth  = 8,
  parameter int unsigned NumInputs    = 1,
  parameter int unsigned OutDataWidth = 32
)(
  // Clock and reset
  input  logic clk_i,
  input  logic rst_ni,
  // Input operands
  input  logic signed [NumInputs-1:0][InDataWidth-1:0] a_i,
  input  logic signed [NumInputs-1:0][InDataWidth-1:0] b_i,
  // Valid signals for inputs
  input  logic a_valid_i,
  input  logic b_valid_i,
  // Mux selection for accumulation flush
  input  logic [1:0] acc_mux_sel,
  // Accumulated outputs from previous PEs
  input  logic signed [OutDataWidth-1:0] acc_north,
  input  logic signed [OutDataWidth-1:0] acc_west,
  // Pass inputs to next PE
  output logic signed [NumInputs-1:0][InDataWidth-1:0] a_o_east,
  output logic signed [NumInputs-1:0][InDataWidth-1:0] b_o_south,
  // Output accumulation
  output logic signed [OutDataWidth-1:0] acc_east,
  output logic signed [OutDataWidth-1:0] acc_south
);

  // Wires and logic
  logic acc_valid;
  logic signed [NumInputs-1:0][InDataWidth-1:0] regA, regB;
  logic signed [OutDataWidth-1:0] mult_result;
  logic signed [OutDataWidth-1:0] acc_mux_in, c_o, accumulation_result;
  logic [1:0] reg_mux_sel;
  logic acc_clr_i;

  // assign acc_valid = a_valid_i && b_valid_i;
  assign acc_south = c_o;
  assign acc_east  = c_o;
  assign a_o_east  = regA;
  assign b_o_south = regB;

  // always_ff @(posedge clk_i or negedge rst_ni) begin
  //   if (!rst_ni) begin
  //     reg_mux_sel <= '0;
  //   end else begin
  //     reg_mux_sel <= acc_mux_sel;
  //   end
  // end

  // FF for the inputs
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      regA <= '0;
      regB <= '0;
    end else begin
      if(a_valid_i)
        regA <= a_i;
      else
        regA <= '0;

      if(b_valid_i)
        regB <= b_i;
      else
        regB <= '0;
    end
  end

  // Combined multiplication
  always_comb begin
    mult_result = '0;
    for (int i = 0; i < NumInputs; i++) begin
      mult_result += $signed(regA[i]) * $signed(regB[i]);
    end
  end

  always_comb begin
    // Default
    accumulation_result = mult_result + c_o;
  end
  
  // Accumulation unit
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      c_o <= '0;
    end else if (acc_valid) begin
      c_o <= acc_mux_in;
    end else if (acc_clr_i) begin
      c_o <= '0;
    end else begin
      c_o <= c_o;
    end
  end

  // Mux for accumulator
  always_comb begin
    case (acc_mux_sel)
      2'b00: begin 
        acc_mux_in = accumulation_result; // Normal operation
        acc_clr_i  =  0;
        acc_valid  =  1;
      end
      2'b01: begin
        acc_mux_in = acc_north; // Flush from north
        acc_clr_i  =  0;
        acc_valid  =  1;
      end
      2'b10: begin
        acc_mux_in = acc_west;  // Flush from west
        acc_clr_i  =  0;
        acc_valid  =  1;
      end
      2'b11: begin
        acc_mux_in = '0;         
        acc_clr_i  =  1;        // Clear
        acc_valid  =  0;
      end
      default: begin
        acc_mux_in = '0;
        acc_clr_i  =  0;        // Clear
        acc_valid  =  0;
      end
    endcase
  end
endmodule
