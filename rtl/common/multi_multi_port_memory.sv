//-----------------------------
// Single Port Memory Module
//
// Description: This module implements a single-port memory with
// configurable data width and depth. It supports synchronous write
// operations and combinational read operations.
//
// Parameters:
// - DataWidth: Width of the data bus (default: 8 bits)
// - DataDepth: Depth of the memory (default: 4096 entries)
// - AddrWidth: Width of the address bus (calculated based on DataDepth)
//
// Ports:
// - clk_i: Clock input
// - rst_ni: Active low reset input
// - mem_addr_i: Memory address input
// - mem_we_i: Memory write enable input
// - mem_wr_data_i: Memory write data input
// - mem_rd_data_o: Memory read data output
//-----------------------------

//-----------------------------
// DESIGN NOTE:
// You are allowed to modify the Datadepth and
// DataWidth parameters to suit your design requirements.
//-----------------------------
module multi_multi_port_memory #(
    parameter int unsigned NumKernels = 4,
    parameter int unsigned NumPorts = 4,
    parameter int unsigned DataWidth = 8,
    parameter int unsigned DataDepth = 4096,
    parameter int unsigned AddrWidth = (DataDepth <= 1) ? 1 : $clog2(DataDepth)
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    input  logic        [AddrWidth-1:0] mem_addr_i [NumKernels][NumPorts],
    input  logic                        mem_we_i [NumKernels][NumPorts],
    input  logic signed [DataWidth-1:0] mem_wr_data_i [NumKernels][NumPorts],
    output logic signed [DataWidth-1:0] mem_rd_data_o [NumKernels][NumPorts]
);

  // Memory array
  logic signed [DataWidth-1:0] memory[DataDepth];

  // Memory read access
  always_comb begin
    for (int i = 0; i < NumKernels; i++) begin
      for (int j = 0; j < NumPorts; j++) begin
        mem_rd_data_o[i][j] = memory[mem_addr_i[i][j]];
      end
    end
  end

  // Memory write access
  always_ff @(posedge clk_i) begin
    // Write when write enable is asserted
    for (int i = 0; i < NumKernels; i++) begin
      for (int j = 0; j < NumPorts; j++) begin
        if (mem_we_i[i][j]) begin
          memory[mem_addr_i[i][j]] <= mem_wr_data_i[i][j];
        end
      end
    end
  end
endmodule
