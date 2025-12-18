module tb_remap_memory;

    parameter int unsigned InDataWidth   = 8;
    parameter int unsigned OutDataWidth  = 32;
    parameter int unsigned DataDepth     = 4096;
    parameter int unsigned AddrWidth     = (DataDepth <= 1) ? 1 : $clog2(DataDepth);
    parameter int unsigned SizeAddrWidth = 8;

    // Test Parameters
    parameter int unsigned MaxNum   = 32;
    parameter int unsigned NumTests = 10;

    parameter int unsigned SingleM = 8;
    parameter int unsigned SingleK = 12;
    parameter int unsigned SingleN = 8;

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
    logic signed [InDataWidth-1:0] B_remap_memory [DataDepth];
    logic signed [InDataWidth-1:0] B_remap_memory_inv [DataDepth];
    logic signed [InDataWidth-1:0] B_remap_memory_row [DataDepth];

    // Memory control
    logic [AddrWidth-1:0] sram_a_addr;
    logic [AddrWidth-1:0] sram_b_addr;
    logic [AddrWidth-1:0] sram_b_remap_addr;
    logic [AddrWidth-1:0] sram_c_addr;

    // Memory access
    logic signed [ InDataWidth-1:0] sram_a_rdata;
    logic signed [ InDataWidth-1:0] sram_b_rdata;
    logic signed [ InDataWidth-1:0] sram_b_remap_rdata;
    logic signed [OutDataWidth-1:0] sram_c_wdata;
    logic                           sram_c_we;

    //---------------------------
    // Tasks and functions
    //---------------------------
    `include "includes/common_tasks.svh"
    `include "includes/test_tasks.svh"
    `include "includes/test_func.svh"
    
    single_port_memory #(
      .DataWidth  ( InDataWidth  ),
      .DataDepth  ( DataDepth    ),
      .AddrWidth  ( AddrWidth    )
    ) i_sram_b (
      .clk_i         ( clk_i        ),
      .rst_ni        ( rst_ni       ),
      .mem_addr_i    ( sram_b_addr ),
      .mem_we_i      ( '0           ),
      .mem_wr_data_i ( '0           ),
      .mem_rd_data_o ( sram_b_rdata )
    );

    // single_port_memory #(
    //   .DataWidth  ( InDataWidth  ),
    //   .DataDepth  ( DataDepth    ),
    //   .AddrWidth  ( AddrWidth    )
    // ) i_sram_b_remap (
    //   .clk_i         ( clk_i        ),
    //   .rst_ni        ( rst_ni       ),
    //   .mem_addr_i    ( sram_b_remap_addr ),
    //   .mem_we_i      ( '0           ),
    //   .mem_wr_data_i ( '0           ),
    //   .mem_rd_data_o ( sram_b_remap_rdata )
    // );

    initial begin
        // Initialize memories with random data
        for (integer k = 0; k < SingleK; k++) begin
          for (integer n = 0; n < SingleN; n++) begin
            i_sram_b.memory[k*SingleN+n] =  k*SingleN+n;//$urandom() % (2 ** InDataWidth);
          end
        end
    end

    initial begin
      // Clock generation
      clk_i = 1'b0;
      forever #5 clk_i = ~clk_i;  // 100MHz clock
    end

    int counter;


    initial begin
      // Test stimulus
      rst_ni = 0;
      start = 0;
      M_i = SingleM;
      K_i = SingleK;
      N_i = SingleN;

      @(negedge clk_i);
      rst_ni = 1;

      @(negedge clk_i);
      start = 1;

      @(negedge clk_i);
      start = 0;

      remap_to_4x4_blocks_row(
        SingleK,
        SingleN,
        i_sram_b.memory,
        B_remap_memory
      );

      // Wait for some time to read all data
      #1000;

      for (integer i = 0; i < 4; i++) begin
          for (integer j = 0; j < (SingleK*SingleN)/4; j+=4) begin
              $write("%0d, %0d, %0d, %0d | ", B_remap_memory[i*(SingleK*SingleN)/4 + j], B_remap_memory[i*(SingleK*SingleN)/4 + j+1], B_remap_memory[i*(SingleK*SingleN)/4 + j+2], B_remap_memory[i*(SingleK*SingleN)/4 + j+3]);
          end
          $display("");
      end

        $display("===================Inverse==================");
        remap_4x4_blocks_to_normal(
          SingleK,
          SingleN,
          B_remap_memory,
          B_remap_memory_inv
        );

    // unit test, each element should match original
        for (integer k = 0; k < SingleK; k++) begin
            for (integer n = 0; n < SingleN; n++) begin
                if (B_remap_memory_inv[k*SingleN+n] !== i_sram_b.memory[k*SingleN+n]) begin
                    $display("Mismatch at position (%0d, %0d): expected %0d, got %0d", k, n, i_sram_b.memory[k*SingleN+n], B_remap_memory_inv[k*SingleN+n]);
                    $fatal;
                end
            end
            end

        $display("Inverse remap successful, all values match original.");

      $display("===================Col==================");

      remap_to_4x4_blocks_col(
        SingleK,
        SingleN,
        i_sram_b.memory,
        B_remap_memory
      );

      // Wait for some time to read all data
      #1000;

      for (integer i = 0; i < (SingleK*SingleN); i+=4) begin
          $display("%0d, %0d, %0d, %0d", B_remap_memory[i], B_remap_memory[i+1], B_remap_memory[i+2], B_remap_memory[i+3]);
      end


        $display("===================Row-major col==================");

      row_major_to_col_major(
        SingleK*SingleN/4,
        4,
        B_remap_memory,
        B_remap_memory_row
      );

      // Wait for some time to read all data
      #1000;

        for(integer i = 0; i < 4 ; i++) begin
            for(integer j = 0; j < (SingleK*SingleN)/4; j++) begin
                $write("%0d, ", B_remap_memory_row[j + i*(SingleK*SingleN)/4]);
            end
            $display("");
        end
      $finish;
    end

endmodule