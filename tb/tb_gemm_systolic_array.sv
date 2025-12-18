//--------------------------
// MAC PE Testbench
// - Unit test to check the functionality of the PE
//--------------------------

module tb_gemm_systolic_array;

  //---------------------------
  // Design Time Parameters
  //---------------------------

  // MAC Parameters
  parameter int unsigned InDataWidth  = 8;
  parameter int unsigned OutDataWidth = 32;
  parameter int unsigned NumInputs    = 4;

  parameter int unsigned M    = 4;
  parameter int unsigned N    = 4;

  //---------------------------
  // Test Parameters
  //---------------------------
  parameter int unsigned NumTests = 1;

  //---------------------------
  // Wires
  //---------------------------

  // Clock and reset
  logic clk_i, rst_ni, valid_i;
  logic signed [  InDataWidth-1:0] sram_a_rdata_i [NumInputs];
  logic signed [  InDataWidth-1:0] sram_b_rdata_i [NumInputs];
  logic        [1:0]                         acc_mux_sel;
  logic signed [ OutDataWidth-1:0] sram_c_wdata_o [NumInputs];
  logic                                      done_o;

  logic signed[  InDataWidth-1:0] dbg_a_sram_1;
  assign dbg_a_sram_1 = sram_a_rdata_i[0];
  logic signed[  InDataWidth-1:0] dbg_a_sram_2;
  assign dbg_a_sram_2 = sram_a_rdata_i[1];
  logic signed[  InDataWidth-1:0] dbg_a_sram_3;
  assign dbg_a_sram_3 = sram_a_rdata_i[2];
  logic signed[  InDataWidth-1:0] dbg_a_sram_4;
  assign dbg_a_sram_4 = sram_a_rdata_i[3];

  logic signed[  InDataWidth-1:0] dbg_b_sram_1;
  assign dbg_b_sram_1 = sram_b_rdata_i[0];
  logic signed[  InDataWidth-1:0] dbg_b_sram_2;
  assign dbg_b_sram_2 = sram_b_rdata_i[1];
  logic signed[  InDataWidth-1:0] dbg_b_sram_3;
  assign dbg_b_sram_3 = sram_b_rdata_i[2];
  logic signed[  InDataWidth-1:0] dbg_b_sram_4;
  assign dbg_b_sram_4 = sram_b_rdata_i[3];

  logic signed[ OutDataWidth-1:0] dbg_out_c_4;
  assign dbg_out_c_4 = sram_c_wdata_o[3];
  logic signed[ OutDataWidth-1:0] dbg_out_c_3;
  assign dbg_out_c_3 = sram_c_wdata_o[2];
  logic signed[ OutDataWidth-1:0] dbg_out_c_2;
  assign dbg_out_c_2 = sram_c_wdata_o[1];
  logic signed[ OutDataWidth-1:0] dbg_out_c_1;
  assign dbg_out_c_1 = sram_c_wdata_o[0];

  // Input signals
  logic signed [M][N][InDataWidth-1:0] a_i;
  logic signed [M][N][InDataWidth-1:0] b_i;
  logic signed [M][N][OutDataWidth-1:0] golden_c_o, c_o;

  // // Output signal
  // logic signed [OutDataWidth-1:0] c_o;
  // logic signed [OutDataWidth-1:0] golden_c_o;

  // logic        [1:0] acc_mux_sel;
  // logic signed [OutDataWidth-1:0] acc_north;
  // logic signed [OutDataWidth-1:0] acc_west;
  // logic signed [NumInputs-1:0][InDataWidth-1:0] a_o_east;
  // logic signed [NumInputs-1:0][InDataWidth-1:0] b_o_south;
  // logic signed [OutDataWidth-1:0] acc_east;
  // logic signed [OutDataWidth-1:0] acc_south;

  // Instantiate the MAC PE module
  gemm_systolic_array_top #(
    .numInputs(NumInputs),
    .dataWidth_I(InDataWidth),
    .dataWidth_O(OutDataWidth)
  ) small_kernel (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .valid_data(valid_i),
    .sram_a_rdata_i(sram_a_rdata_i),
    .sram_b_rdata_i(sram_b_rdata_i), // Need to expand this width for multiple PEs
    .acc_mux_sel(acc_mux_sel),
    .sram_c_wdata_o(sram_c_wdata_o),
    .done_o(done_o)
  );

  //---------------------------
  // Tasks and functions
  //---------------------------
  `include "includes/common_tasks.svh"

  function automatic void mac_pe_golden(
    input  logic signed [M][N][InDataWidth-1:0] A_i,
    input  logic signed [M][N][InDataWidth-1:0] B_i,
    output logic signed [M][N][OutDataWidth-1:0] C_o
  );
    int unsigned i, j, k;
    C_o = '0;
    for (i = 0; i < M; i++) begin
      for (j = 0; j < N; j++) begin
        for (k = 0; k < N; k++) begin
          C_o[i][j] = $signed(C_o[i][j]) + $signed(A_i[i][k]) * $signed(B_i[k][j]);
        end
      end
    end

  endfunction

  //---------------------------
  // Start of testbench
  //---------------------------

  // Clock generation
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;  // 100MHz clock
  end

  // Test control
  initial begin

    // Initialize inputs
    clk_i          = 1'b0;
    rst_ni         = 1'b0;
    valid_i        = 1'b0;
    acc_mux_sel    = 2'b00;

    for (int i = 0; i < NumInputs; i++) begin
      sram_a_rdata_i[i] = '0;
      sram_b_rdata_i[i] = '0;
    end

    for (int j = 0; j < M; j++) begin
      for (int i = 0; i < N; i++) begin
        a_i[i][j] = '0;
        b_i[i][j] = '0;
        clk_delay(1);
      end
    end

    clk_delay(3);

    // Release reset
    #1;
    rst_ni = 1;

    // 1 cycle delay after reset
    clk_delay(1);

    // Driver control
    for (int i = 0; i < NumTests; i++) begin

      // Generate random inputs
      for (int j = 0; j < M; j++) begin
        for (int i = 0; i < N; i++) begin
          a_i[i][j] = i*j*-1;
          b_i[i][j] = j-1;
          clk_delay(1);
        end
      end

      // Calculate golden value
      mac_pe_golden(a_i, b_i, golden_c_o);

      // Set the valid signals
      valid_i = 1;
      // clk_delay(1);

      // Prefill stage
      sram_a_rdata_i = {a_i[0][0], 8'b0, 8'b0, 8'b0 };
      sram_b_rdata_i = {b_i[0][0], 8'b0, 8'b0, 8'b0 };
      acc_mux_sel    = 2'b00; // Use accumulation
      clk_delay(1);

      sram_a_rdata_i = {a_i[0][1], a_i[1][0],  8'b0, 8'b0 };
      sram_b_rdata_i = {b_i[1][0], b_i[0][1],  8'b0, 8'b0 };
      clk_delay(1);

      sram_a_rdata_i = {a_i[0][2], a_i[1][1],  a_i[2][0],8'b0  };
      sram_b_rdata_i = {b_i[2][0], b_i[1][1],  b_i[0][2],8'b0  };
      clk_delay(1);

      sram_a_rdata_i = {a_i[0][3], a_i[1][2], a_i[2][1], a_i[3][0]   };
      sram_b_rdata_i = {b_i[3][0], b_i[2][1], b_i[1][2], b_i[0][3]   };
      clk_delay(1);

      sram_a_rdata_i = {8'b0, a_i[1][3], a_i[2][2],a_i[3][1]   };
      sram_b_rdata_i = {8'b0, b_i[3][1], b_i[2][2],b_i[1][3]   };
      clk_delay(1);

      sram_a_rdata_i = { 8'b0, 8'b0,  a_i[2][3], a_i[3][2]};
      sram_b_rdata_i = { 8'b0, 8'b0,  b_i[3][2], b_i[2][3]};
      clk_delay(1);

      sram_a_rdata_i = {8'b0, 8'b0, 8'b0,a_i[3][3]};
      sram_b_rdata_i = {8'b0, 8'b0, 8'b0,b_i[3][3]};
      clk_delay(1);
      //  Extra clock cycles for the input to propagate till end
      clk_delay(1);
      clk_delay(1);
      clk_delay(1);

      // Output should be ready, remove valid and change the mux to flush out values
      valid_i        = 0;
      // acc_mux_sel    = 2'b01; // Read from south
      acc_mux_sel    = 2'b10; // Read from east

      // acc_mux_sel    = 2'b10; // Read from east
      // for (int i = 0; i < NumInputs; i++) begin
      //   sram_a_rdata_i[i] = '0;
      //   sram_b_rdata_i[i] = '0;
      // end
      
      // clk_delay(1);
      // clk_delay(1);
      // acc_mux_sel    = 2'b01; // Read from south
      // // clk_delay(1);

      for (int cycle = 0; cycle < N; cycle++) begin
        clk_delay(1);
        // Read and compare the output values
        for (int i = 0; i < NumInputs; i++) begin
          if(acc_mux_sel    == 2'b01)
            c_o[M - 1 - cycle][i] = $signed(sram_c_wdata_o[i]);
          else if(acc_mux_sel == 2'b10)
            c_o[i][M - 1 - cycle] = $signed(sram_c_wdata_o[i]);
          else begin
            $error("Test failed: put a correct acc_mux_sel");
            $fatal;
          end
        end
        // clk_delay(1);
      end

      // $display("Input A:");
      // for (int row = 0; row < M; row++) begin
      //   for (int col = 0; col < N; col++) begin
      //     $display("%d", $signed(a_i[row][col]));
      //   end
      // end

      // $display("Input B:");
      // for (int row = 0; row < M; row++) begin
      //   for (int col = 0; col < N; col++) begin
      //     $display("%d", $signed(b_i[row][col]));
      //   end
      // end

      // $display("Expected:");
      // for (int row = 0; row < M; row++) begin
      //   for (int col = 0; col < N; col++) begin
      //     $display("%0d", $signed(golden_c_o[row][col]));
      //     // if (c_o[row][col] !== golden_c_o[row][col]) begin
      //     //   $error("Test %0d failed: C[%0d][%0d] = %0d, expected %0d", i, row,  col, c_o[row][col], golden_c_o[row][col]);
      //     // end
      //   end
      // end

      $display("Actual:");
      for (int row = 0; row < M; row++) begin
        for (int col = 0; col < N; col++) begin
          // $display("%0d", $signed(c_o[row][col]));
          if (c_o[row][col] !== golden_c_o[row][col]) begin
            $error("Test %0d failed: C[%0d][%0d] = %0d, expected %0d", i, row,  col, $signed(c_o[row][col]), $signed(golden_c_o[row][col]));
            $fatal;
          end
        end
      end

      $display("Test %0d passed.", i);
    end

    // Finish simulation after some time
    clk_delay(5);
    $display("All tests passed!");

    $finish;
  end

endmodule
