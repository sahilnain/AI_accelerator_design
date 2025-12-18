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

module gemm_accelerator_top_nxn #(
  parameter int unsigned InDataWidth = 8,
  parameter int unsigned OutDataWidth = 32,
  parameter int unsigned AddrWidth = 16,
  parameter int unsigned SizeAddrWidth = 8,
  parameter int unsigned NumParallelLanes = 4
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic                            start_i,
  input  logic        [SizeAddrWidth-1:0] K_size_i,
  input  logic        [SizeAddrWidth-1:0] N_size_i,
  input  logic signed [  InDataWidth-1:0] sram_a_rdata_i,
  input  logic signed [  InDataWidth-1:0] sram_b_rdata_i [NumParallelLanes],
  output logic signed [ OutDataWidth-1:0] sram_c_wdata_o [NumParallelLanes],
  output logic                            sram_c_we_o    [NumParallelLanes],
  output logic [1:0]                      addr_offset,
  output logic                            done_o
);

  //---------------------------
  // Wires
  //---------------------------
  logic [SizeAddrWidth-1:0] K_count;
  logic [SizeAddrWidth-1:0] N_sub_count;

  logic [1:0] control_pe;

  logic sub_done;

  // Indicates if we have sent all data for current kernel
  logic all_weights_sent;

  // State machine states
  typedef enum logic [2:0] {
    TopIdle, // 000
    TopFilling, // 001
    TopFlooding, // 010
    TopFlushing, // 011
    TopFinish // 100
  } controller_state_t;
  logic [2:0] current_state, next_state;
  logic tick_i; // Tick signal for N sub-counter; to fetch new data

  // Simple Mux To fill data when needed
  logic signed [  InDataWidth-1:0] a_data [NumParallelLanes];
  logic signed [  InDataWidth-1:0] b_data [NumParallelLanes];

  assign a_data = (current_state == TopFilling) ? sram_a_rdata_i : '{default: '0};
  assign b_data = (current_state == TopFilling) ? sram_b_rdata_i : '{default: '0};



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

  ceiling_counter #(
    .Width        ( SizeAddrWidth ),
    .HasCeiling   ( 1 )
  ) i_N_sub_counter (
    .clk_i        ( clk_i                ),
    .rst_ni       ( rst_ni               ),
    .tick_i       ( tick_i           ), // When we are filling the MAC PEs
    .clear_i      ( start_i              ),
    .ceiling_i    ( NumParallelLanes[SizeAddrWidth-1:0]     ),
    .count_o      ( N_sub_count          ),
    .last_value_o (  sub_done            )
  );

    ceiling_counter #(
    .Width        ( SizeAddrWidth ),
    .HasCeiling   ( 1 )
  ) i_K_counter (
    .clk_i        ( clk_i                ),
    .rst_ni       ( rst_ni               ),
    .tick_i       ( sub_done             ), // When we are filling the MAC PEs
    .clear_i      ( start_i              ),
    .ceiling_i    ( K_size_i >> 2     ),
    .count_o      ( K_count          ),
    .last_value_o (  all_weights_sent            )
  );

    // Wait for weights to propagate through MAC PEs
    logic [2:0] wait_flooding;
    logic [1:0] wait_flushing;
    assign addr_offset = wait_flushing;

    // 2. Sequential Logic: Manage the Counter
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        wait_flooding <= '0;
        wait_flushing <= 2'd3;
      end else begin
        // Only count when we are in the Flooding state
        if (current_state == TopFlooding) begin
            wait_flooding <= wait_flooding + 1;
        end else begin
            // Reset counter when not in the state so it's ready for next time
            wait_flooding <= '0;
        end

        if (current_state == TopFlushing) begin
            wait_flushing <= wait_flushing - 1;
        end else begin
            // Reset counter when not in the state so it's ready for next time
            wait_flushing <= 2'd3;
      end
    end
    end


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

  // Input addresses for sub-matrices of A and B
  // No support for multi kernel atm
  logic signed       [    AddrWidth-1:0] sram_first_index  [NumParallelLanes];
  always_comb begin
      for (int i = 0; i < NumParallelLanes ; i++) begin
            sram_a_addr_o[i] = 
                (M_count * (NumParallelLanes*K_size_i) + K_count * NumParallelLanes + i*K_size_i + N_sub_count);
            sram_b_addr_o[i] =
                (K_count * (NumParallelLanes*N_size_i) + N_count * NumParallelLanes + i + N_sub_count*N_size_i);
            sram_c_addr_o[i] = 
                i  + (M_count * N_size_i + N_count) * NumParallelLanes + wait_flushing * N_size_i;
      end
  end
  //---------------------------
    logic valid_data;
    // FSM
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        current_state <= TopIdle;
      end else begin
        current_state <= next_state;
      end
    end

    always_comb begin
      // Default assignments
      next_state     = current_state;

      case (current_state)
        TopIdle: begin
            valid_data = 1'b0;
            done_o = 1'b0;
            control_pe = 2'b11; // Clear
            for (int i = 0; i < NumParallelLanes ; i++) begin
                sram_c_we_o[i] = 1'b0;
            end
          if (start_i) begin
            next_state   = TopFilling;
            tick_i = 1'b1;
          end else begin
            tick_i = 1'b0;
          end
        end
        
        TopFilling: begin
          control_pe = 2'b00; // Normal operation
          valid_data = 1'b1;
          if (all_weights_sent) begin
            next_state = TopFlooding;
            //tick_i = 1'b0;
          end else begin
            //tick_i = 1'b1;
          end
        end

        TopFlooding: begin
            tick_i = 1'b0;
            valid_data = 1'b1;
          // When counter hits 3, we have spent 4 cycles in this state
          if (wait_flooding == 3'd6) begin
            next_state = TopFlushing;
          end 
        end

        TopFlushing: begin
            control_pe = 2'b01; // Flushing south
            valid_data = 1'b0;
            for (int i = 0; i < NumParallelLanes ; i++) begin
                sram_c_we_o[i] = 1'b1;
            end

            if (wait_flushing == 2'd0) begin
              next_state = TopFinish;
            end
          
        end

        TopFinish: begin
            control_pe = 2'b11; // Clear
            valid_data = 1'b0;
            for (int i = 0; i < NumParallelLanes ; i++) begin
                sram_c_we_o[i] = 1'b0;
            end
          next_state     = TopIdle;
          done_o         = 1'b1;
        end

        default: begin
          next_state = TopIdle;
        end
      endcase
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
  // genvar m, k, n;
  //
  //   for (m = 0; m < M; m++) begin : gem_mac_pe_m
  //     for (n = 0; n < N; n++) begin : gem_mac_pe_n
  //         mac_module #(
  //           < insert parameters >
  //         ) i_mac_pe (
  //           < insert port connections >
  //         );
  //     end
  //   end
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

    // Create registers chaining
  logic signed [  InDataWidth-1:0] skewed_sram_a_rdata_i [NumParallelLanes];
  logic signed [  InDataWidth-1:0] skewed_sram_b_rdata_i [NumParallelLanes];
  genvar n;
  
  generate 
    for(n = 0; n < NumParallelLanes; n++) begin : gen_chain
      if (n == 0) begin
        assign skewed_sram_b_rdata_i[n] = b_data[n];
        assign skewed_sram_a_rdata_i[n] = a_data[n];
      end else begin
        register_chain #(
          .Depth(n),
          .DataWidth(InDataWidth)
        ) i_reg_chain_b (
          .clk_i  ( clk_i ),
          .rst_ni ( rst_ni ),
          .clear_i ( 0),
          .data_in_i ( b_data[n] ),
          .data_out_o ( skewed_sram_b_rdata_i[n] )
        );

        register_chain #(
          .Depth(n),
          .DataWidth(InDataWidth)
        ) i_reg_chain_a (
          .clk_i  ( clk_i ),
          .rst_ni ( rst_ni ),
          .clear_i ( 0),
          .data_in_i ( a_data[n] ),
          .data_out_o ( skewed_sram_a_rdata_i[n] )
        );
      end
    end
  endgenerate

  // The MAC PE instantiation and data path logics
  logic done_pe;
  gemm_systolic_array_top #(
    .numInputs     ( NumParallelLanes ),
    .dataWidth_I    ( InDataWidth    ),
    .dataWidth_O   ( OutDataWidth   )
  ) i_mac_pe (
    .clk_i          ( clk_i              ),
    .rst_ni         ( rst_ni             ),
    .valid_data   ( valid_data               ),
    .sram_a_rdata_i ( skewed_sram_a_rdata_i     ),
    .sram_b_rdata_i ( skewed_sram_b_rdata_i     ),
    .acc_mux_sel (control_pe), // To flush to the east
    .sram_c_wdata_o ( sram_c_wdata_o     ),
    .done_o        ( done_pe            )
  );  
  
endmodule