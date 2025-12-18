module tb_gemm_accelerator_top_nxnxn;
    // Parameters
    parameter int unsigned InDataWidth    = 8;
    parameter int unsigned OutDataWidth   = 32;
    parameter int unsigned AddrWidth      = 16;
    parameter int unsigned SizeAddrWidth  = 8;
    parameter int unsigned NumKernels         = 4;
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
    logic        [AddrWidth-1:0]     sram_a_addr_o  [0:NumKernels-1][0:NumParallelLanes-1];
    logic        [AddrWidth-1:0]     sram_b_addr_o  [0:NumKernels-1][0:NumParallelLanes-1];
    logic   signed     [AddrWidth-1:0]     sram_c_addr_o  [0:NumKernels-1][0:NumParallelLanes-1];
    logic signed [InDataWidth-1:0]   sram_a_rdata_i [0:NumKernels-1][0:NumParallelLanes-1];
    logic signed [InDataWidth-1:0]   sram_b_rdata_i [0:NumKernels-1][0:NumParallelLanes-1];
    logic signed [OutDataWidth-1:0]  sram_c_wdata_o [0:NumKernels-1][0:NumParallelLanes-1];
    logic                            sram_c_we_o    [0:NumKernels-1][0:NumParallelLanes-1];
    logic                            done_o;


    // VCD dump of all signals
    initial begin
        $dumpfile("tb_gemm_accelerator_top_nxnxn.vcd");
        $dumpvars(0, i_dut);
        $dumpvars(1, i_dut);
    end

    // Clock generation
    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;  // 100MHz clock
    end

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
      .start_i          ( start_i          ),
      .M_size_i         ( M_size_i         ),
      .K_size_i         ( K_size_i         ),
      .N_size_i         ( N_size_i         ),
      .sram_a_addr_o    ( sram_a_addr_o    ),
      .sram_b_addr_o    ( sram_b_addr_o    ),
      .sram_c_addr_o    ( sram_c_addr_o    ),
      .sram_a_rdata_i   ( sram_a_rdata_i   ),
      .sram_b_rdata_i   ( sram_b_rdata_i   ),
      .sram_c_wdata_o   ( sram_c_wdata_o   ),
      .sram_c_we_o      ( sram_c_we_o      ),
      .done_o           ( done_o           )
    );

    //---------------------------
    // Tasks and functions
    //---------------------------
    `include "includes/common_tasks.svh"

    initial begin
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
        for (int i = 0; i < 70; i++) begin

          $display("Cycle %0d", i);
            // Print addresses for verification
            for (int kernel = 0; kernel < NumKernels; kernel++) begin
              $display("Kernel %0d:", kernel);
              for (int lane = 0; lane < NumParallelLanes; lane++) begin
                  $display("Lane %0d: SRAM A Addr: %0d, SRAM B Addr: %0d, SRAM C Addr: %0d, SRAM Valid: %0b", lane, sram_a_addr_o[kernel][lane], sram_b_addr_o[kernel][lane], sram_c_addr_o[kernel][lane], sram_c_we_o[kernel][lane]);
              end
            end
            clk_delay(1);
        end

        $finish;
    end
    
endmodule