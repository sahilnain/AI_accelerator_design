module tb_gemm_accelerator_top_nxn;
    // Parameters
    parameter int unsigned InDataWidth    = 8;
    parameter int unsigned OutDataWidth   = 32;
    parameter int unsigned AddrWidth      = 16;
    parameter int unsigned SizeAddrWidth  = 8;
    parameter int unsigned NumKernels         = 1;
    parameter int unsigned NumParallelLanes   = 4;

    // wires and regs
    logic                            clk_i;
    logic                            rst_ni;
    logic                            start_i;
    logic        [SizeAddrWidth-1:0] M_size_i = 8;
    logic        [SizeAddrWidth-1:0] K_size_i = 20;
    logic        [SizeAddrWidth-1:0] N_size_i = 12;
    logic        [SizeAddrWidth-1:0] M_count;
    logic        [SizeAddrWidth-1:0] N_count;
    logic        [AddrWidth-1:0]     sram_a_addr_o  [NumKernels][0:NumParallelLanes-1];
    logic        [AddrWidth-1:0]     sram_b_addr_o  [NumKernels][0:NumParallelLanes-1];
    logic        [AddrWidth-1:0]     sram_c_addr_o  [NumKernels][0:NumParallelLanes-1];
    logic signed [InDataWidth-1:0]   sram_a_rdata_i [NumKernels][0:NumParallelLanes-1];
    logic signed [InDataWidth-1:0]   sram_b_rdata_i [NumKernels][0:NumParallelLanes-1];
    logic signed [OutDataWidth-1:0]  sram_c_wdata_o [NumKernels][0:NumParallelLanes-1];
    logic                            sram_c_we_o    [NumKernels][0:NumParallelLanes-1];
    logic                            done_o;


    // VCD dump of all signals
    initial begin
        $dumpfile("tb_gemm_accelerator_top_nxn.vcd");
        $dumpvars(0, tb_gemm_accelerator_top_nxn);
        $dumpvars(1, tb_gemm_accelerator_top_nxn);
    end

    // Dummy write deactivate signals
    logic sram_dummy_we_o [0:NumKernels-1][0:NumParallelLanes-1];
    logic signed [InDataWidth-1:0] sram_dummy_data [0:NumKernels-1][0:NumParallelLanes-1];
    // set it to zero
    always_comb begin
      for (int i = 0; i < NumKernels; i++) begin
        for (int j = 0; j < NumParallelLanes; j++) begin
          sram_dummy_we_o[i][j] = 1'b0;
          sram_dummy_data[i][j] = '0;
        end
      end
    end

  parameter int unsigned DataDepth     = 4096;

    // Generate multiport memeory instances for input A,B and output C
    multi_multi_port_memory #(
      .NumKernels ( NumKernels ),
      .NumPorts   ( NumParallelLanes ),
      .DataWidth  ( InDataWidth  ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
    ) i_sram_a (
      .clk_i         ( clk_i        ),
      .rst_ni        ( rst_ni       ),
      .mem_addr_i    ( sram_a_addr_o ),
      .mem_we_i      ( sram_dummy_we_o ),
      .mem_wr_data_i ( sram_dummy_data ),
      .mem_rd_data_o ( sram_a_rdata_i )
    );

    multi_multi_port_memory #(
      .NumKernels ( NumKernels ),
      .NumPorts   ( NumParallelLanes ),
      .DataWidth  ( InDataWidth  ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
    ) i_sram_b (
      .clk_i         ( clk_i        ),
      .rst_ni        ( rst_ni       ),
      .mem_addr_i    ( sram_b_addr_o ),
      .mem_we_i      ( sram_dummy_we_o           ),
      .mem_wr_data_i ( sram_dummy_data          ),
      .mem_rd_data_o ( sram_b_rdata_i )
    );

    multi_multi_port_memory #(
      .NumKernels ( NumKernels ),
      .NumPorts   ( NumParallelLanes ),
      .DataWidth  ( OutDataWidth ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
    ) i_sram_c (
      .clk_i         ( clk_i        ),
      .rst_ni        ( rst_ni       ),
      .mem_addr_i    ( sram_c_addr_o ),
      .mem_we_i      ( sram_c_we_o   ),
      .mem_wr_data_i ( sram_c_wdata_o ),
      .mem_rd_data_o ( /* Unused */  )
    );


    // Clock generation
    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;  // 100MHz clock
    end

    gemm_accelerator_top_nxn #(
      .InDataWidth        ( 8    ),
      .OutDataWidth       ( 32   ),
      .AddrWidth          ( 16   ),
      .SizeAddrWidth      ( 8    ),
      .NumParallelLanes   ( 4    )
    ) i_dut (
      .clk_i            ( clk_i            ),
      .rst_ni           ( rst_ni           ),
      .start_i          ( start_i          ),
      .K_size_i         ( K_size_i         ),
      .N_size_i         ( N_size_i         ),
      .M_count          ( M_count          ),
      .N_count          ( N_count          ),
      .sram_a_addr_o    ( sram_a_addr_o[0]    ),
      .sram_b_addr_o    ( sram_b_addr_o[0]    ),
      .sram_c_addr_o    ( sram_c_addr_o[0]    ),
      .sram_a_rdata_i   ( sram_a_rdata_i[0]   ),
      .sram_b_rdata_i   ( sram_b_rdata_i[0]   ),
      .sram_c_wdata_o   ( sram_c_wdata_o[0]   ),
      .sram_c_we_o      ( sram_c_we_o[0]      ),
      .done_o           ( done_o           )
    );

    //---------------------------
    // Tasks and functions
    //---------------------------
    `include "includes/common_tasks.svh"

    // Print
    always_ff @(posedge clk_i) begin
      if (done_o) begin
        $display("===== GEMM operation completed. ===== ");
      end
    end

    always_ff @(posedge clk_i) begin
      $display("T %0t", $time);
      // Print addresses for verification
      for (int lane = 0; lane < NumParallelLanes; lane++) begin
          $display("Lane %0d: SRAM A Addr: %0d, SRAM B Addr: %0d, SRAM C Addr: %0d, SRAM Valid: %0b", lane, sram_a_addr_o[0][lane], sram_b_addr_o[0][lane], sram_c_addr_o[0][lane], sram_c_we_o[0][lane]);
      end
    end

    initial begin
        // Initialize memories with random data
        for (integer m = 0; m < M_size_i; m++) begin
          for (integer k = 0; k < K_size_i; k++) begin
            i_sram_a.memory[m*K_size_i+k] =  m+1;//$urandom() % (2 ** InDataWidth);
          end
        end

        for (integer k = 0; k < K_size_i; k++) begin
          for (integer n = 0; n < N_size_i; n++) begin
            i_sram_b.memory[k*N_size_i+n] =  1;//$urandom() % (2 ** InDataWidth);
          end
        end
        // Initial reset
        rst_ni    = 1'b0;
        
        M_count = 1;
        N_count = 1;

        clk_delay(1);

        // Release reset
        rst_ni = 1'b1;
        clk_delay(10);

        // Start the operation
        start_i = 1'b1;
        clk_delay(1);
        start_i = 1'b0;

        $display("Starting check of SRAM");
        $display("NumParallelLanes: %0d", NumParallelLanes);



        for (int i = 0; i < 40; i++) begin

          start_i = 1'b0;
          
          if (done_o) begin
            $display("Done signal received at cycle %0d", i);
            N_count = N_count + 1;
            clk_delay(1);
            start_i = 1'b1;
            clk_delay(1);
            start_i = 1'b0;
          end

          clk_delay(1);
        end

        $finish;
    end
    
endmodule