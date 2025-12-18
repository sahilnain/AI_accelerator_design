//------------------------------------------------------------------------------
// Module: gemm_accelerator_top_nxnxn
//
// Description:
//   Multi-Kernel Wrapper for GeMM Accelerator.
//   This module instantiates multiple (NumKernels) 4x4 Systolic Arrays.
//   It acts as a Tile Controller, breaking down large matrices (M, N, K)
//   into smaller chunks that fit into the sub-modules.
//
//   - Matrix A is Broadcast (Shared across kernels).
//   - Matrix B is Split (Different columns for different kernels).
//   - Matrix C is Split (Different columns for different kernels).
//------------------------------------------------------------------------------

module gemm_accelerator_top_nxnxn #(
  parameter int unsigned InDataWidth      = 8,
  parameter int unsigned OutDataWidth     = 32,
  parameter int unsigned AddrWidth        = 16,
  parameter int unsigned SizeAddrWidth    = 8,
  parameter int unsigned NumKernels       = 4,
  parameter int unsigned NumParallelLanes = 4
) (
  // Clock & Reset
  input  logic                            clk_i,
  input  logic                            rst_ni,

  // Control
  input  logic                            start_i,
  output logic                            done_o,

  // Matrix Dimensions (Global)
  input  logic        [SizeAddrWidth-1:0] M_size_i,
  input  logic        [SizeAddrWidth-1:0] K_size_i,
  input  logic        [SizeAddrWidth-1:0] N_size_i,

  // SRAM Addresses (Shared/Master)
  output logic        [    AddrWidth-1:0] sram_a_addr_o,
  output logic        [    AddrWidth-1:0] sram_b_addr_o,
  output logic        [    AddrWidth-1:0] sram_c_addr_o,

  // Data Buses (Wide)
  // A is broadcast: Width = 1 Lane set
  input  logic signed [InDataWidth*NumParallelLanes-1:0]              sram_a_rdata_i, 
  // B is unique: Width = NumKernels * Lane set
  input  logic signed [InDataWidth*NumKernels*NumParallelLanes-1:0]   sram_b_rdata_i,
  // C is unique: Width = NumKernels * Lane set
  output logic signed [OutDataWidth*NumKernels*NumParallelLanes-1:0]  sram_c_wdata_o,
  // Write Enable (Single bit, assumes lockstep write)
  output logic                            sram_c_we_o
);

  //----------------------------------------------------------------------------
  // 1. Data Packing & Unpacking
  //----------------------------------------------------------------------------
  
  // Internal Arrays for easier indexing
  logic signed [InDataWidth-1:0]  sram_a_unpacked [NumParallelLanes]; // Shared A
  logic signed [InDataWidth-1:0]  sram_b_packed   [NumKernels][NumParallelLanes];
  logic signed [OutDataWidth-1:0] sram_c_packed   [NumKernels][NumParallelLanes];

  // 1A. Unpack Input A (Broadcast to all kernels, so we just unpack once)
  always_comb begin
    for (int n = 0; n < NumParallelLanes; n++) begin
      sram_a_unpacked[n] = sram_a_rdata_i[(n + 1)*InDataWidth-1 -: InDataWidth];
    end
  end

  // 1B. Unpack Input B (Unique per kernel)
  always_comb begin
    for (int k = 0; k < NumKernels; k++) begin
      for (int n = 0; n < NumParallelLanes; n++) begin
        // Slicing the wide bus: [ (Index+1)*Width - 1 : Index*Width ]
        sram_b_packed[k][n] = sram_b_rdata_i[((k*NumParallelLanes) + n + 1)*InDataWidth-1 -: InDataWidth];
      end
    end
  end

  // 1C. Pack Output C
  always_comb begin
    for (int k = 0; k < NumKernels; k++) begin
      for (int n = 0; n < NumParallelLanes; n++) begin
        sram_c_wdata_o[((k*NumParallelLanes) + n + 1)*OutDataWidth-1 -: OutDataWidth] = sram_c_packed[k][n];
      end
    end
  end

  //----------------------------------------------------------------------------
  // 2. Global Tile Counters (M, N, K)
  //----------------------------------------------------------------------------
  // These counters track which "Block" of the large matrix we are processing.
  // Flow: Compute full K depth for current M,N tile -> Move to Next N -> Move to Next M

  logic tick_k, tick_n, tick_m;
  logic done_k, done_n, done_m;
  logic [SizeAddrWidth-1:0] count_k, count_n, count_m;

  // K Counter (Inner Loop - Depth)
  ceiling_counter #(
    .Width      ( SizeAddrWidth ),
    .HasCeiling ( 1 )
  ) i_cnt_k (
    .clk_i      ( clk_i ),
    .rst_ni     ( rst_ni ),
    .clear_i    ( start_i ),
    .tick_i     ( tick_k ),
    .ceiling_i  ( K_size_i ), 
    .count_o    ( count_k ),
    .last_value_o ( done_k )
  );

  // N Counter (Middle Loop - Columns)
  ceiling_counter #(
    .Width      ( SizeAddrWidth ),
    .HasCeiling ( 1 )
  ) i_cnt_n (
    .clk_i      ( clk_i ),
    .rst_ni     ( rst_ni ),
    .clear_i    ( start_i ),
    .tick_i     ( done_k ), // Tick when K depth is done
    .ceiling_i  ( N_size_i>>$clog2(NumParallelLanes*NumKernels) ), // Adjusted for blocking factor and parallelism
    .count_o    ( count_n ),
    .last_value_o ( done_n )
  );
  logic done_last;
  // M Counter (Outer Loop - Rows)
  ceiling_counter #(
    .Width      ( SizeAddrWidth ),
    .HasCeiling ( 1 )
  ) i_cnt_m (
    .clk_i      ( clk_i ),
    .rst_ni     ( rst_ni ),
    .clear_i    ( start_i ),
    .tick_i     ( done_n ),
    .ceiling_i  ( M_size_i>>2 ), // Adjusted for blocking factor
    .count_o    ( count_m ),
    .last_value_o ( done_last ) // Final done signal
  );

  //----------------------------------------------------------------------------
  // 3. Main FSM (Tile Controller)
  //----------------------------------------------------------------------------
  
  typedef enum logic [2:0] {
    IDLE,
    START_KERNELS,
    K_FILL,
    K_FLOOD,
    K_FLUSH,
    K_FLOOD_LAST,
    K_FLUSH_LAST,
    DONE
  } state_t;

  state_t current_state, next_state;
  logic   start_kernels_comb; // Signal to trigger sub-modules
  logic   all_kernels_done;   // Aggregate done signal


  logic signed [InDataWidth-1:0]  skewed_data_a   [NumParallelLanes]; // Shared A
  logic signed [InDataWidth-1:0]  skewed_data_b   [NumKernels][NumParallelLanes];

  // For a simple Mux at the entrance to guard the Systolic Array
  logic signed [  InDataWidth-1:0] a_data [NumParallelLanes];
  logic signed [  InDataWidth-1:0] b_data [NumKernels][NumParallelLanes];

  assign a_data = (current_state == K_FILL) ? sram_a_unpacked : '{default: '0};
  // 

  genvar i, j;

  // Generate the skewed data for A
  generate
    for (i = 0; i < NumParallelLanes; i++) begin : gen_skew_a
      if ( i == 0 ) begin
        assign skewed_data_a[0] = a_data[0];
      end else begin
        register_chain #(
          .Depth    (i),
          .DataWidth(InDataWidth)
        ) i_reg_chain_a (
          .clk_i      ( clk_i ),
          .rst_ni     ( rst_ni ),
          .data_in_i  ( a_data[i] ),
          .data_out_o ( skewed_data_a[i] )
        );
      end
      
    end
  endgenerate

  // Generate the Kernels
  logic        [1:0]               control_pe;
  logic                             valid_data;
  logic        [NumKernels-1:0]     sub_done;
  logic        [NumKernels-1:0]     all_weights_sent;
  logic        [NumKernels-1:0]     done_pe;
  generate
    for (i = 0; i < NumKernels; i++) begin : gen_kernels
      assign b_data[i] = (current_state == K_FILL) ? sram_b_packed[i] : '{default: '0};
      for (j = 0; j < NumParallelLanes; j++) begin : gen_lanes
        // Skewing logic for B
        if ( j == 0 ) begin
          assign skewed_data_b[i][0] = b_data[i][0];
        end else begin
          register_chain #(
            .Depth    (j),
            .DataWidth(InDataWidth)
          ) i_reg_chain_b (
            .clk_i      ( clk_i ),
            .rst_ni     ( rst_ni ),
            .data_in_i  ( b_data[i][j] ),
            .data_out_o ( skewed_data_b[i][j] )
          );
        end
      end

      // Generate the Systolic Array Kernel
      gemm_systolic_array_top #(
        .numInputs      ( NumParallelLanes ),
        .dataWidth_I    ( InDataWidth      ),
        .dataWidth_O    ( OutDataWidth     )
      ) i_systolic_array (
        .clk_i          ( clk_i            ),
        .rst_ni         ( rst_ni           ),
        .valid_data     ( valid_data       ),
        .acc_mux_sel    ( control_pe       ), // Flush control
        // Inputs
        .sram_a_rdata_i ( skewed_data_a    ),
        .sram_b_rdata_i ( skewed_data_b[i]    ),
        // Outputs
        .sram_c_wdata_o ( sram_c_packed[i]   ),
        .done_o         ( done_pe[i]          )
      );  

    end
  endgenerate


  // ----------------------------------------------------------------------------
  // 3. Sequential Logic: State Transition
  // ----------------------------------------------------------------------------


  logic [2:0] wait_flooding;
  logic [1:0] wait_flushing;  logic [1:0] offset_c_sram;
  assign offset_c_sram = wait_flushing; 

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) current_state <= IDLE;
    else         current_state <= next_state;
  end

  always_comb begin
    
    case (current_state)
      IDLE:begin
        if (start_i) next_state = START_KERNELS;
      end 
      START_KERNELS: begin
          next_state = K_FILL;
      end
      K_FILL: begin
        if (done_last) next_state = K_FLOOD_LAST; // Final Flood
        else begin
          if (done_k) next_state = K_FLOOD; // Sent full row of weights
        end
      end
      K_FLOOD: begin
        // Wait for pipeline to fill/process
        if (wait_flooding >= 3'd6) next_state = K_FLUSH;
      end
      K_FLUSH: begin
        // Wait for pipeline to drain
        if (wait_flushing == 0) next_state = START_KERNELS;
      end
      K_FLOOD_LAST: begin
        // Wait for pipeline to fill/process
        if (wait_flooding >= 3'd6) next_state = K_FLUSH_LAST;
      end
      K_FLUSH_LAST: begin
        // Wait for pipeline to drain
        if (wait_flushing == 0) next_state = DONE;
      end
      DONE: begin
        next_state = IDLE;
      end
      default: 
        next_state = IDLE;
    endcase
  end

  // Output Logic
  always_comb begin
    // Defaults
    valid_data  = 1'b0;
    done_o      = 1'b0;
    control_pe  = 2'b11; // Default Clear
    sram_c_we_o = 1'b0; 
    tick_k      = 1'b0;

    case (current_state)
      IDLE: begin
        control_pe = 2'b11; // Clear
      end

      START_KERNELS: begin
        control_pe = 2'b11; // Clear
      end

      K_FILL: begin
        tick_k = 1'b1;
        valid_data = 1'b1;
        control_pe = 2'b00; // Normal Operation
      end

      K_FLOOD, K_FLOOD_LAST: begin
        valid_data = 1'b1;
        control_pe = 2'b00; // Normal Operation
      end

      K_FLUSH, K_FLUSH_LAST: begin
        valid_data = 1'b0;
        control_pe = 2'b01; // Flush South
        sram_c_we_o = 1'b1; // Enable writing during flush
      end

      DONE: begin
        done_o = 1'b1;
        control_pe = 2'b11; // Clear
      end
      default:
        control_pe = 2'b11; // Clear
    endcase
  end

  ///----------------------------------------------------------------------------
  // Address controller
  //----------------------------------------------------------------------------
  logic [SizeAddrWidth-1:0] reg_count_n, reg_count_m;
  // register to hold current count values for Output address calculation

  // 2. Sequential Logic: Manage the Counter
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wait_flooding <= '0;
      wait_flushing <= 2'd3;
      reg_count_n <= '0;
      reg_count_m <= '0;
    end else begin
      // Only count when we are in the Flooding state
      if (current_state == K_FILL) begin
          reg_count_n <= count_n;
          reg_count_m <= count_m;
      end 
      if ((current_state == K_FLOOD) || (current_state == K_FLOOD_LAST)) begin
          wait_flooding <= wait_flooding + 1;
      end else begin
          // Reset counter when not in the state so it's ready for next time
          wait_flooding <= '0;
      end

      if ((current_state == K_FLUSH) || (current_state == K_FLUSH_LAST)) begin
          wait_flushing <= wait_flushing - 1;
      end else begin
          // Reset counter when not in the state so it's ready for next time
          wait_flushing <= 2'd3;
      end
    end
  end

  always_comb begin
    // Due to the packing of addresses
    sram_a_addr_o = count_m + count_k*(M_size_i>>2); 
    sram_b_addr_o = count_n + count_k*(N_size_i>>4); 
    // Have to use a register counter since it updates before we can 
    // capture the output
    // offset SRAM due to filling from South (first value obtained are the one at the bottom)
    sram_c_addr_o = (reg_count_n) + reg_count_m*(N_size_i>>2) + offset_c_sram*(N_size_i>>4);
  end


endmodule