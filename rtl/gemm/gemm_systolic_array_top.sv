`define M 4
`define N 4

module gemm_systolic_array_top #(
  parameter int unsigned numInputs = 4,
  parameter int unsigned dataWidth_I = 8,
  parameter int unsigned dataWidth_O = 32
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic                            valid_data,
  input  logic signed [  dataWidth_I-1:0] sram_a_rdata_i [numInputs],
  input  logic signed [  dataWidth_I-1:0] sram_b_rdata_i [numInputs], // Need to expand this width for multiple PEs
  input  logic        [1:0]               acc_mux_sel,
  output logic signed [ dataWidth_O-1:0] sram_c_wdata_o[numInputs],
  output logic                            done_o
);
  
  genvar m, k, n, connect_iter;

  //---------------------------
  // Wires
  //---------------------------
  logic busy;

  // Passing A and B between PEs
  logic signed [`M][`N][dataWidth_I-1:0]  a_i;
  logic signed [`M][`N][dataWidth_I-1:0]  b_i;
  logic signed [`M][`N][dataWidth_I-1:0]  a_o_east;
  logic signed [`M][`N][dataWidth_I-1:0]  b_o_south;
  
  // Passing accumulator output between PEs
  // Inputs from North and East, outputs from West and South
  logic signed [`M][`N][dataWidth_O-1:0] acc_north; // Input
  logic signed [`M][`N][dataWidth_O-1:0] acc_west;  // Input
  logic signed [`M][`N][dataWidth_O-1:0] acc_east;  // Output
  logic signed [`M][`N][dataWidth_O-1:0] acc_south; // Output

  logic [1:0] reg_mux_sel;
  // always_ff @(posedge clk_i or negedge rst_ni) begin
  //   if(!rst_ni)
  //     reg_mux_sel <= '0;
  //   else
  //     reg_mux_sel <= acc_mux_sel;
  // end

  assign reg_mux_sel = acc_mux_sel;

  // Data width encoder for C
  always_comb begin
    for (int i = 0; i < numInputs; i++) begin
      if(reg_mux_sel == 2'b01)
          sram_c_wdata_o[i] = acc_south[`M-1][i];
      else if (reg_mux_sel == 2'b10)
          sram_c_wdata_o[i] = acc_east[i][`N-1];
      else begin 
        sram_c_wdata_o[i] = '0;
      end
    end
  end

  logic [dataWidth_O-1:0] dbg_out_c_1;
  logic [dataWidth_O-1:0] dbg_out_c_2;
  logic [dataWidth_O-1:0] dbg_out_c_3;
  logic [dataWidth_O-1:0] dbg_out_c_4;

  assign dbg_out_c_1 = sram_c_wdata_o[0];
  assign dbg_out_c_2 = sram_c_wdata_o[1];
  assign dbg_out_c_3 = sram_c_wdata_o[2];
  assign dbg_out_c_4 = sram_c_wdata_o[3];


  // Connect A and B inputs/outputs between PEs
  for(connect_iter = 0; connect_iter < `M; connect_iter++) begin : connect_a_b
    for(n = 0; n < `N; n++) begin : connect_a
      if (connect_iter == 0) begin
        assign b_i[connect_iter][n] = sram_b_rdata_i[n]; // First row gets data from SRAM B
      end else begin
        assign b_i[connect_iter][n] = b_o_south[connect_iter-1][n]; // Subsecuent rows get data from the PE above
      end
    end
    for(m = 0; m < `M; m++) begin : connect_b
      if (connect_iter == 0) begin
        assign a_i[m][connect_iter] = sram_a_rdata_i[m]; // First column gets data from SRAM A
      end else begin
        assign a_i[m][connect_iter] = a_o_east[m][connect_iter-1]; // Subsecuent columns get data from the PE to the left
      end
    end
  end

  // Connect accumulator inputs/outputs between PEs
  for(connect_iter = 0; connect_iter < `M; connect_iter++) begin : connect_acc
    for(n = 0; n < `N; n++) begin : connect_acc_north
      if (connect_iter == 0) begin
        assign acc_north[connect_iter][n] = acc_south[0][n]; // First accumulator row gets zero
      end else begin
        assign acc_north[connect_iter][n] = acc_south[connect_iter-1][n]; // Subsecuent rows get data from the PE above
      end
    end
    for(m = 0; m < `M; m++) begin : connect_acc_east
      if (connect_iter == 0) begin
        assign acc_west[m][connect_iter] = acc_east[0][m]; // First accumulator column gets zero
      end else begin
        assign acc_west[m][connect_iter] = acc_east[m][connect_iter-1]; // Subsecuent columns get data from the PE to the left
      end
    end
  end

  // Generate all PEs
  for (m = 0; m < `M; m++) begin : gem_mac_pe_m
    for (n = 0; n < `N; n++) begin : gem_mac_pe_n
        general_mac_pe #(
        .InDataWidth  ( dataWidth_I            ),
        .NumInputs    ( 1                      ),
        .OutDataWidth ( dataWidth_O           )
      ) i_mac_pe (
        .clk_i        ( clk_i                  ),
        .rst_ni       ( rst_ni                 ),
        .a_i          ( a_i[m][n]              ),
        .b_i          ( b_i[m][n]              ),
        .a_valid_i    ( valid_data             ),
        .b_valid_i    ( valid_data             ),
        .acc_north    ( acc_north[m][n]        ),
        .acc_mux_sel  ( reg_mux_sel            ),
        .acc_west     ( acc_west[m][n]         ),
        .a_o_east     ( a_o_east[m][n]         ),
        .b_o_south    ( b_o_south[m][n]        ),
        .acc_east     ( acc_east[m][n]         ),
        .acc_south    ( acc_south[m][n]        )
      );
    end
  end

endmodule
