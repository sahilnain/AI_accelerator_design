module tb_4x4x4_sys_gemm;
  //---------------------------
  // Design Time Parameters
  //---------------------------

  //---------------------------
  // DESIGN NOTE:
  // Parameters are a way to customize your design at
  // compile time. Here we define the data width,
  // memory depth, and number of ports for the
  // multi-port memory instances used in the DUT.
  //
  // In other test benches, you can also have test parameters,
  // such as the number of tests to run, or the sizes of
  // matrices to be used in the tests.
  //
  // You can customize these parameters as needed.
  // Or you can also add your own parameters.
  //---------------------------

  // General Parameters
  parameter int unsigned InDataWidth   = 8;
  parameter int unsigned OutDataWidth  = 32;
  parameter int unsigned DataDepth     = 4096;
  parameter int unsigned AddrWidth     = (DataDepth <= 1) ? 1 : $clog2(DataDepth);
  parameter int unsigned SizeAddrWidth = 8;
  logic [AddrWidth-1:0] test_depth;

  // Kernel parameters
    parameter int unsigned NumKernels       = 4;
    parameter int unsigned NumParallelLanes = 4;

  // Test Parameters
  parameter int unsigned MaxNum   = 32;
  parameter int unsigned NumTests = 1;

  parameter int unsigned SingleM = 4;
  parameter int unsigned SingleK = 16;
  parameter int unsigned SingleN = 64;

  //---------------------------
  // Wires
  //---------------------------

  // Size control
  logic [SizeAddrWidth-1:0] M_i, K_i, N_i;

  // Clock, reset, and other signals
  logic clk_i;
  logic rst_ni;
  logic start;
  logic done;

  //---------------------------
  // Memory
  //---------------------------
  // Golden data dump
  logic signed [OutDataWidth-1:0] G_memory [DataDepth];
  logic signed [OutDataWidth-1:0] tmp_unpacked_result [DataDepth];
  logic signed [OutDataWidth-1:0] unpacked_result [DataDepth];
  logic signed [OutDataWidth-1:0] Shape_shift_result [DataDepth];

  // Memory control
  logic [AddrWidth-1:0] sram_a_addr;
  logic [AddrWidth-1:0] sram_b_addr;
  logic [AddrWidth-1:0] sram_c_addr;

  // Memory access
  logic signed [ (InDataWidth*NumParallelLanes-1):0] sram_a_rdata; // input reuse
  logic signed [ (InDataWidth*NumParallelLanes*NumKernels-1):0] sram_b_rdata;
  logic signed [ (OutDataWidth*NumParallelLanes*NumKernels)-1:0] sram_c_wdata;

  // TMP for proper layout
  logic signed [InDataWidth-1:0] tmp_sram_a_rdata [DataDepth];
  logic signed [InDataWidth-1:0] tmp_sram_b_rdata [DataDepth];
  logic signed [OutDataWidth-1:0] tmp_sram_c_wdata [DataDepth];
  logic                           sram_c_we;

  //---------------------------
  // Declaration of input and output memories
  //---------------------------

  // Input memory A
  // Note: this is read only

  // ---- 
  // Single Port memory instances 
  // ----
  // Input Reuse
  single_port_memory #(
      .DataWidth  ( InDataWidth*NumParallelLanes ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
  ) i_sram_a_single (
      .clk_i         ( clk_i        ),
      .rst_ni        ( rst_ni       ),
      .mem_addr_i    ( sram_a_addr ),
      .mem_we_i      ( '0           ),
      .mem_wr_data_i ( '0           ),
      .mem_rd_data_o ( sram_a_rdata )
    );

  single_port_memory #(
      .DataWidth  ( InDataWidth*NumParallelLanes*NumKernels ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
    ) i_sram_b_single (
      .clk_i         ( clk_i        ),
      .rst_ni        ( rst_ni       ),
      .mem_addr_i    ( sram_b_addr ),
      .mem_we_i      ( '0           ),
      .mem_wr_data_i ( '0           ),
      .mem_rd_data_o ( sram_b_rdata )
    );

    // Dummy SRAM for easy GOLDEN comparison
      single_port_memory #(
      .DataWidth  ( InDataWidth ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
  ) i_sram_a_single_DUMMY (
      .clk_i         ( clk_i        ),
      .rst_ni        ( rst_ni       ),
      .mem_addr_i    ( '0 ),
      .mem_we_i      ( '0           ),
      .mem_wr_data_i ( '0           ),
      .mem_rd_data_o ( /* unused */ )
    );

  single_port_memory #(
      .DataWidth  ( InDataWidth ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
    ) i_sram_b_single_DUMMY (
      .clk_i         ( clk_i        ),
      .rst_ni        ( rst_ni       ),
      .mem_addr_i    ( '0 ),
      .mem_we_i      ( '0           ),
      .mem_wr_data_i ( '0           ),
      .mem_rd_data_o ( /* unused */ )
    );

    //assign sram_c_we = sram_c_we_o[0][0]; // any of the lanes writing enables the single port memory

    single_port_memory #(
      .DataWidth  ( OutDataWidth*NumParallelLanes*NumKernels ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
    ) i_sram_c_single (
      .clk_i         ( clk_i        ),
      .rst_ni        ( rst_ni       ),
      .mem_addr_i    ( sram_c_addr ),
      .mem_we_i      ( sram_c_we    ),
      .mem_wr_data_i ( sram_c_wdata ),
      .mem_rd_data_o ( /* unused */ )
    );


  // ---- 
  // Single Port memory instances (for reference)
  // ----
  single_port_memory #(
      .DataWidth  ( InDataWidth  ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
  ) i_sram_a_REF (
    .clk_i         ( '0        ),
    .rst_ni        ( '0       ),
    .mem_addr_i    ( '0 ),
    .mem_we_i      ( '0           ),
    .mem_wr_data_i ( '0           ),
    .mem_rd_data_o ( /* unused */)
  );

  single_port_memory #(
      .DataWidth  ( InDataWidth  ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
  ) i_sram_b_REF (
    .clk_i         ( '0        ),
    .rst_ni        ( '0       ),
    .mem_addr_i    ( '0 ),
    .mem_we_i      ( '0           ),
    .mem_wr_data_i ( '0           ),
    .mem_rd_data_o ( /* unused */ )
  );

  //---------------------------
  // DUT instantiation
  //---------------------------
    gemm_accelerator_top_nxnxn #(
        .InDataWidth        ( InDataWidth    ),
        .OutDataWidth       ( OutDataWidth   ),
        .AddrWidth          ( AddrWidth     ),
        .SizeAddrWidth      ( SizeAddrWidth    ),
        .NumKernels         ( NumKernels    ),
        .NumParallelLanes   ( NumParallelLanes    )
    ) i_dut (
        .clk_i            ( clk_i            ),
        .rst_ni           ( rst_ni           ),
        .start_i          ( start          ),
        .M_size_i         ( M_i         ),
        .K_size_i         ( K_i         ),
        .N_size_i         ( N_i         ),
        .sram_a_addr_o    ( sram_a_addr    ),
        .sram_b_addr_o    ( sram_b_addr    ),
        .sram_c_addr_o    ( sram_c_addr    ),
        .sram_a_rdata_i   ( sram_a_rdata   ),
        .sram_b_rdata_i   ( sram_b_rdata   ),
        .sram_c_wdata_o   ( sram_c_wdata   ),
        .sram_c_we_o      ( sram_c_we      ),
        .done_o           ( done           )
    );

  //---------------------------
  // Tasks and functions
  //---------------------------
  `include "includes/common_tasks.svh"
  `include "includes/test_tasks.svh"
  `include "includes/test_func.svh"

  //---------------------------
  // Test control
  //---------------------------

  // Clock generation
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;  // 100MHz clock
  end

  //---------------------------
  // DESIGN NOTE:
  //
  // The sequence driver is usually the main stimulus
  // generator for the test bench. Here is where
  // you define the sequence of operations to be
  // performed during the simulation.
  //
  // It often starts with an initial reset sequence,
  // by loading default values and asserting the reset.
  //
  // We also do for-loops to run multiple tests
  // with different input parameters. In this case,
  // we randomize the matrix sizes for each test.
  //
  // You can also customize in here the way
  // the memories are initialized, how the golden
  // results are generated, and how the results
  // are verified.
  //
  // Refer to the tasks and functions included above
  // for more details.
  //---------------------------
  // Sequence driver

  int counter;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni || start)
      counter <= '0;
    else if (!done)
      counter <= counter + 1;
    if (done)
     $display("Total cycles: %0d", counter);
    
  end

  initial begin

    // Initial reset
    start  = 1'b0;
    rst_ni = 1'b0;
    #50;
    rst_ni = 1'b1;

    for (integer num_test = 0; num_test < NumTests; num_test++) begin
      $display("Test number: %0d", num_test);

      if (NumTests > 1) begin
        M_i = $urandom_range(1, MaxNum);
        K_i = $urandom_range(1, MaxNum);
        N_i = $urandom_range(1, MaxNum);
      end else begin
        M_i = SingleM;
        K_i = SingleK;
        N_i = SingleN;
      end

      $display("M: %0d, K: %0d, N: %0d", M_i, K_i, N_i);

      //---------------------------
  $display("A===========================");
      // Initialize memories with random data
      for (integer m = 0; m < M_i; m++) begin
        for (integer k = 0; k < K_i; k++) begin
          i_sram_a_single_DUMMY.memory[m*K_i+k] = $urandom() % (2 ** InDataWidth);
          $write("%h, ", i_sram_a_single_DUMMY.memory[m*K_i+k]);
        end
        $display("");
      end

  $display("B===========================");
      for (integer k = 0; k < K_i; k++) begin
        for (integer n = 0; n < N_i; n++) begin
          i_sram_b_single_DUMMY.memory[k*N_i+n] = $urandom() % (2 ** InDataWidth);
          $write("%h, ", i_sram_b_single_DUMMY.memory[k*N_i+n]);
        end
        $display("");
      end
        // Generate golden result
      gemm_golden(M_i, K_i, N_i, 
        i_sram_a_single_DUMMY.memory, i_sram_b_single_DUMMY.memory, G_memory);

      // --------------------------------------------
      // Memory Layout Transformation 
      // --------------------------------------------
      if ( SingleN == 4 ) begin
        $display("Special case 2");
        // Transpose operation
        M_i = SingleN;
        N_i = SingleM;
        // B^T in matrix A
        for( integer m = 0; m < M_i; m++ ) begin
          for ( integer k = 0; k < K_i; k++ ) begin
            tmp_sram_a_rdata[m*K_i + k] = i_sram_b_single_DUMMY.memory[m*K_i + k];
          end
        end

        // A^T in matrix B
        for ( integer k = 0; k < K_i; k++ ) begin
          for ( integer n = 0; n < N_i; n++ ) begin
            tmp_sram_b_rdata[k*N_i + n] = i_sram_a_single_DUMMY.memory[n*K_i + k];
          end
        end

        $display("After Layout  Case Special ===========================");


          $display("A  ===========================");
        // Initialize memories with random data
        for (integer k = 0; k < K_i; k++)  begin
          for (integer m = 0; m < M_i; m++) begin
            $write("%h, ", tmp_sram_a_rdata[m*K_i+k]);
          end
          $display("");
        end

        $display("B ===========================");
        for (integer n = 0; n < N_i; n++)  begin
           for (integer k = 0; k < K_i; k++) begin
            $write("%h, ", tmp_sram_b_rdata[k*N_i+n]);
          end
          $display("");
        end

      end else begin 
        row_major_to_col_major(
          M_i,
          K_i,
          i_sram_a_single_DUMMY.memory,
          tmp_sram_a_rdata
        );

        // Write to tmp sram_b_rdata for consistency
        for (integer k = 0; k < K_i; k++) begin
          for (integer n = 0; n < N_i; n++) begin
            tmp_sram_b_rdata[k*N_i + n] = i_sram_b_single_DUMMY.memory[k*N_i + n];
          end
        end
        $display("After Layout  ===========================");


          $display("A  ===========================");
        // Initialize memories with random data
        for (integer m = 0; m < M_i; m++) begin
          for (integer k = 0; k < K_i; k++) begin
            $write("%h, ", tmp_sram_a_rdata[m*K_i+k]);
          end
          $display("");
        end

        $display("B ===========================");
        for (integer k = 0; k < K_i; k++) begin
          for (integer n = 0; n < N_i; n++) begin
            $write("%h, ", tmp_sram_b_rdata[k*N_i+n]);
          end
          $display("");
        end

      end


      // --------------------------------------------
      // Memory packing 
      // --------------------------------------------

      // Handle the bit packing for actual inputs
      // Assuming row-major storage for both A and B
      // TODO find a cleaner way to do this
      $display("A - Packed ===========================");
      for (integer m = 0; m < M_i; m++) begin
        for (integer k = 0; k < (K_i>>2); k++) begin // divide by 4
          i_sram_a_single.memory[m*(K_i>>2)+k] =
            { tmp_sram_a_rdata[m*K_i + k*4 + 3],
              tmp_sram_a_rdata[m*K_i + k*4 + 2],
              tmp_sram_a_rdata[m*K_i + k*4 + 1],
              tmp_sram_a_rdata[m*K_i + k*4 + 0] };
          $write("%h, ", i_sram_a_single.memory[m*(K_i>>2)+k]);
        end
        $display("");
      end
      $display("B - Packed ===========================");
      for (integer k = 0; k < K_i; k++) begin
        for (integer n = 0; n < (N_i>>$clog2(NumKernels*NumParallelLanes)); n++) begin // divide by 4
          i_sram_b_single.memory[k*(N_i>>$clog2(NumKernels*NumParallelLanes))+n] =
            { tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 15],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 14],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 13],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 12],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 11],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 10],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 9],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 8], 
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 7],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 6],  
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 5],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 4], 
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 3],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 2],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 1],
              tmp_sram_b_rdata[k*N_i + n*NumKernels*NumParallelLanes + 0] };
          $write("%h, ", i_sram_b_single.memory[k*(N_i>>$clog2(NumKernels*NumParallelLanes))+n]);
        end
        $display("");
      end

      // Just delay 1 cycle
      clk_delay(1);

      // Execute the GeMM
      start_and_wait_gemm();

      // Verify the result
      test_depth = M_i * N_i;
      $display("Verifying result with depth %0d", test_depth);


      // Unpack the result from the single port memory
      begin
        for (integer m = 0; m < M_i; m++) begin
          for (integer n = 0; n < (N_i>>$clog2(NumKernels*NumParallelLanes)); n++) begin // divide by 4
            for (integer lane = 0; lane < NumParallelLanes*NumKernels; lane++) begin
              tmp_unpacked_result[m*N_i + n*NumParallelLanes*NumKernels + lane] =
                i_sram_c_single.memory[m*(N_i>>$clog2(NumKernels*NumParallelLanes))+n][ (lane*OutDataWidth) +: OutDataWidth ];
            end
          end
        end
      end

      // Reswap M_i and N_i if special case Swap back
      if ( SingleN == 4 ) begin
        // Remap back
        M_i = SingleM;
        N_i = SingleN;
        for (integer m = 0; m < M_i; m++) begin
          for (integer n = 0; n < N_i; n++) begin
             unpacked_result[m*N_i+n] = tmp_unpacked_result[n*M_i+m];
          end
          $display("");
        end
      end else begin
        // Direct copy
        for (integer m = 0; m < M_i; m++) begin
          for (integer n = 0; n < N_i; n++) begin
             unpacked_result[m*N_i+n] = tmp_unpacked_result[m*N_i+n];
          end
          $display("");
        end
      end 

      $display("C - Unpacked ===========================");
      for (integer m = 0; m < M_i; m++) begin
        for (integer n = 0; n < N_i; n++) begin
          $write("%h, ", unpacked_result[m*N_i+n]);
        end
        $display("");
      end

      // Print Golden
      $display("G - Golden ===========================");
      for (integer m = 0; m < M_i; m++) begin
        for (integer n = 0; n < N_i; n++) begin
          $write("%h, ", G_memory[m*N_i+n]);
        end
        $display("");
      end



      verify_result_c(G_memory, unpacked_result, test_depth,
                      1 // Set this to 1 to make mismatches fatal
      );

      // Just some trailing cycles
      // For easier monitoring in waveform
      clk_delay(10);
    end

    $display("T: %t All test tasks completed successfully!", $time);
    $finish;
  end


endmodule
