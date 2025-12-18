`define M 4
`define N 4


//---------------------------
// The 1-MAC GeMM accelerator top module
//
// Description:
// This module implements a simple General Matrix-Matrix Multiplication (GeMM)
// accelerator using a single Multiply-Accumulate (MAC) Processing Element (PE).
// It interfaces with three SRAMs for input matrices A and B, and output matrix C.
//
// It includes a controller to manage the GeMM operation and address generation logic
// for accessing the SRAMs based on the current matrix sizes and counters.
//
// Parameters:
// - InDataWidth  : Width of the input data (matrix elements).
// - OutDataWidth : Width of the output data (result matrix elements).
// - AddrWidth    : Width of the address bus for SRAMs.
// - SizeAddrWidth: Width of the size parameters for matrices.
//
// Ports:
// - clk_i        : Clock input.
// - rst_ni       : Active-low reset input.
// - start_i      : Start signal to initiate the GeMM operation.
// - M_size_i     : Size of matrix M (number of rows in A and C
// - K_size_i     : Size of matrix K (number of columns in A and rows in B).
// - N_size_i     : Size of matrix N (number of columns in B and C).
// - sram_a_addr_o: Address output for SRAM A.
// - sram_b_addr_o: Address output for SRAM B.
// - sram_c_addr_o: Address output for SRAM C.
// - sram_a_rdata_i: Data input from SRAM A.
// - sram_b_rdata_i: Data input from SRAM B.
// - sram_c_wdata_o: Data output to SRAM C.
// - sram_c_we_o  : Write enable output for SRAM C.
// - done_o       : Done signal indicating completion of the GeMM operation.
//---------------------------

module gemm_accelerator_top #(
  parameter int unsigned numInputs = 4,
  parameter int unsigned dataWidth_I = 8,
  parameter int unsigned dataWidth_O = 32,
  parameter int unsigned InDataWidth = dataWidth_I*numInputs,
  parameter int unsigned OutDataWidth = dataWidth_O*numInputs,
  parameter int unsigned AddrWidth = 16,
  parameter int unsigned SizeAddrWidth = 8
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic                            start_i,
  input  logic        [SizeAddrWidth-1:0] M_size_i,
  input  logic        [SizeAddrWidth-1:0] K_size_i,
  input  logic        [SizeAddrWidth-1:0] N_size_i,
  output logic        [    AddrWidth-1:0] sram_a_addr_o,
  output logic        [    AddrWidth-1:0] sram_b_addr_o,
  output logic        [    AddrWidth-1:0] sram_c_addr_o,
  input  logic signed [  InDataWidth-1:0] sram_a_rdata_i,
  input  logic signed [  InDataWidth-1:0] sram_b_rdata_i, // Need to expand this width for multiple PEs
  output logic signed [ OutDataWidth-1:0] sram_c_wdata_o,
  output logic                            sram_c_we_o,
  output logic                            done_o
);

  //---------------------------
  // Wires
  //---------------------------
  logic [SizeAddrWidth-1:0] M_count;
  logic [SizeAddrWidth-1:0] K_count;
  logic [SizeAddrWidth-1:0] N_count;

  logic busy;
  logic valid_data;
  assign valid_data = start_i || busy;  // Always valid in this simple design

  //---------------------------
  // DESIGN NOTE:
  // This is a simple GeMM accelerator design using a single MAC PE.
  // The controller manages just the counting capabilities.
  // Check the gemm_controller.sv file for more details.
  //
  // Essentially, it tightly couples the counters and an FSM together.
  // The address generation logic is just after this controller.
  //
  // You have the option to combine the address generation and controller
  // all in one module if you prefer. We did this intentionally to separate tasks.
  //---------------------------

  // Main GeMM controller
  gemm_controller #(
    .AddrWidth      ( SizeAddrWidth )
  ) i_gemm_controller (
    .clk_i          ( clk_i       ),
    .rst_ni         ( rst_ni      ),
    .start_i        ( start_i     ),
    .input_valid_i  ( 1'b1        ),  // Always valid in this simple design
    .result_valid_o ( sram_c_we_o ),
    .busy_o         ( busy        ),
    .done_o         ( done_o      ),
    .M_size_i       ( M_size_i    ),
    .K_size_i       ( K_size_i    ),
    .N_size_i       ( N_size_i    ),
    .M_count_o      ( M_count     ),
    .K_count_o      ( K_count     ),
    .N_count_o      ( N_count     )
  );

  //---------------------------
  // DESIGN NOTE:
  // This part is the address generation logic for the input and output SRAMs.
  // In our example, we made the assumption that both matrices A and B
  // are stored in row-major order.
  //
  // Please adjust this part to align with your designed memory layout
  // The counters are used for the matrix A and matrix B address generation;
  // for matrix C, the corresponding address is calculated at the previous cycle,
  // thus adding one cycle delay on c
  //
  // Just be careful to know on which cycle the addresses are valid.
  // Align it carefully with the testbench's memory control.
  //---------------------------

  // Input addresses for matrices A and B
  assign sram_a_addr_o = (M_count * K_size_i + K_count);
  assign sram_b_addr_o = (K_count * N_size_i + N_count);

  // Output address for matrix C
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sram_c_addr_o <= '0;
    end else if (1'b1) begin  // Always valid in this simple design
      sram_c_addr_o <= (M_count * N_size_i + N_count);
    end
  end

  // Data width decoder for A and B
  logic signed [numInputs][dataWidth_I-1:0] sram_A;
  logic signed [numInputs][dataWidth_I-1:0] sram_B;
  always_comb begin
    for (int i = 0; i < numInputs; i++) begin
      sram_A[i] = sram_a_rdata_i[(i+1)*dataWidth_I-1 : i*dataWidth_I];
      sram_B[i] = sram_b_rdata_i[(i+1)*dataWidth_I-1 : i*dataWidth_I];
    end
  end

  //---------------------------
  // DESIGN NOTE:
  // This part is the MAC PE instantiation and data path logic.
  // Check the general_mac_pe.sv file for more details.
  //
  // In this example, we only use a single MAC PE hence it is a simple design.
  // However, you can expand this part to support multiple PEs
  // by adjusting the data widths and input/output connections accordingly.
  //
  // Systemverilog has a useful mechanism to generate multiple instances
  // using generate-for loops.
  // Below is an example of a 2D generate-for loop to create a grid of PEs.
  //
  // ----------- BEGIN CODE EXAMPLE -----------
  genvar m, k, n, ic;
  logic M = `M;
  logic N = `N;

  // Passing A and B between PEs
  logic signed [M][N][InDataWidth-1:0]  a_i;
  logic signed [M][N][InDataWidth-1:0]  b_i;
  logic signed [M][N][InDataWidth-1:0]  a_o_east;
  logic signed [M][N][InDataWidth-1:0]  b_o_south;
  
  // Passing accumulator output between PEs
  // Inputs from North and East, outputs from West and South
  logic signed [M][N][OutDataWidth-1:0] acc_north; // Input
  logic signed [M][N][OutDataWidth-1:0] acc_west;  // Input
  logic signed [M][N][OutDataWidth-1:0] acc_east;  // Output
  logic signed [M][N][OutDataWidth-1:0] acc_south; // Output

  // Mux select logic for acculumation, I think this can be the same for all PEs
  logic [1:0] acc_mux_sel;
  
  // Connect A and B inputs/outputs between PEs
  for(ic = 0; ic < M; ic++) begin : connect_a_b
    for(n = 0; n < N; n++) begin : connect_a
      if (ic == 0) begin
        assign b_i[ic][n] = sram_B[n]; // First row gets data from SRAM B
      end else begin
        assign b_i[ic][n] = b_o_south[ic-1][n]; // Subsecuent rows get data from the PE above
      end
    end
    for(m = 0; m < M; m++) begin : connect_b
      if (ic == 0) begin
        assign a_i[m][ic] = sram_A[m]; // First column gets data from SRAM A
      end else begin
        assign a_i[m][ic] = a_o_east[m][ic-1]; // Subsecuent columns get data from the PE to the left
      end
    end
  end
  // Connect accumulator inputs/outputs between PEs
  for(ic = 0; ic < M; ic++) begin : connect_a_b
    for(n = 0; n < N; n++) begin : connect_acc_north
      if (ic == 0) begin
        assign acc_north[ic][n] = 0; // First accumulator row gets zero
      end else begin
        assign acc_north[ic][n] = acc_south[ic-1][n]; // Subsecuent rows get data from the PE above
      end
    end
    for(m = 0; m < M; m++) begin : connect_acc_east_1
      if (ic == 0) begin
        assign acc_east[m][ic] = 0; // First accumulator column gets zero
      end else begin
        assign acc_east[m][ic] = acc_west[m][ic-1]; // Subsecuent columns get data from the PE to the left
      end
    end
  end

  // Generate all PEs
  for (m = 0; m < M; m++) begin : gem_mac_pe_m
    for (n = 0; n < N; n++) begin : gem_mac_pe_n
        general_mac_pe #(
        .InDataWidth  ( InDataWidth            ),
        .NumInputs    ( 1                      ),
        .OutDataWidth ( OutDataWidth           )
      ) i_mac_pe (
        .clk_i        ( clk_i                  ),
        .rst_ni       ( rst_ni                 ),
        .a_i          ( a_i[m][n]              ),
        .b_i          ( b_i[m][n]              ),
        .a_valid_i    ( valid_data             ),
        .b_valid_i    ( valid_data             ),
        .init_save_i  ( sram_c_we_o || start_i ),
        .acc_north    ( acc_north[m][n]        ),
        .acc_mux_sel  ( acc_mux_sel            ),
        .acc_west     ( acc_west[m][n]         ),
        .a_o_east     ( a_o_east[m][n]         ),
        .b_o_south    ( b_o_south[m][n]        ),
        .acc_east     ( acc_east[m][n]         ),
        .acc_south    ( acc_south[m][n]        )
      );
    end
  end

  // .c_o          ( sram_c_wdata_o         )
  // ----------- END CODE EXAMPLE -----------
  // 
  // There are many guides on the internet (or even ChatGPT) about generate-for loops.
  // We will give it as an exercise to you to modify this part to support multiple MAC PEs.
  // 
  // When dealing with multiple PEs, be careful with the connection alignment
  // across different PEs as it can be tricky to debug later on.
  // Plan this very carefully, especially when delaing with the correcet data ports
  // data widths, slicing, valid signals, and so much more.
  //
  // Additionally, this MAC PE is already output stationary.
  // You have the freedom to change the dataflow as you see fit.
  //---------------------------

  // The MAC PE instantiation and data path logics
  // general_mac_pe #(
  //   .InDataWidth  ( InDataWidth            ),
  //   .NumInputs    ( 1                      ),
  //   .OutDataWidth ( OutDataWidth           )
  // ) i_mac_pe (
  //   .clk_i        ( clk_i                  ),
  //   .rst_ni       ( rst_ni                 ),
  //   .a_i          ( sram_a_rdata_i         ),
  //   .b_i          ( sram_b_rdata_i         ),
  //   .a_valid_i    ( valid_data             ),
  //   .b_valid_i    ( valid_data             ),
  //   .init_save_i  ( sram_c_we_o || start_i ),
  //   .acc_clr_i    ( !busy                  ),
  //   .c_o          ( sram_c_wdata_o         )
  // );

endmodule
