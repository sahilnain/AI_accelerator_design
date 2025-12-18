// -----
// Simple parametizable register chain
//
// Parameters:
// - Depth      : Number of registers in the chain.
// - DataWidth  : Width of the data stored in each register.
//
// Ports:
// - clk_i      : Clock input.
// - rst_ni     : Active-low reset input.
// - data_in_i  : Input data to be registered.
// - data_out_o : Output data from the last register in the chain.
//----------------------------

module register_chain #(
  parameter int Depth     = 3,
  parameter int DataWidth = 8
)(
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic [DataWidth-1:0]     data_in_i,
  output logic [DataWidth-1:0]     data_out_o
);

  // Internal register array
  // systemverilog array to hold the registers
  logic [DataWidth-1:0] registers [0:Depth-1];

  // Shift data through the register chain
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Asynchronous reset of all registers to 0
      for (int i = 0; i < Depth; i++) begin
        registers[i] <= '0;
      end
    end else begin
      // Shift data through the chain
      registers[0] <= data_in_i;
      for (int i = 1; i < Depth; i++) begin
        registers[i] <= registers[i-1];
      end
    end
  end

  // Output from the last register in the chain
  assign data_out_o = registers[Depth-1];

endmodule