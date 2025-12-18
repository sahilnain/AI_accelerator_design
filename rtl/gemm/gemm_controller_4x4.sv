//---------------------------
// The GeMM Controller Module
//
// Description:
// This module implements the controller for the 1-MAC GeMM accelerator.
// It manages the operation by controlling the M, K, and N counters,
// which get into the address generation logic in the accelerator top.
//
// Unique to this controller is the interplay of counters and the
// main state machine. The controller uses the counters' last value
// signals to determine when to move to the next state.
//
// Parameters:
// - AddrWidth : Width of the address bus for SRAMs and counters.
//
// Ports:
// - clk_i        : Clock input.
// - rst_ni       : Active-low reset input.
// - start_i      : Start signal to initiate the GeMM operation.
// - input_valid_i: Input valid signal indicating data is ready.
// - result_valid_o: Result valid signal indicating output data is ready.
// - busy_o       : Busy signal indicating the controller is processing.
// - done_o       : Done signal indicating completion of the GeMM operation.
// - M_size_i     : Size of matrix M (number of rows in A and C).
// - K_size_i     : Size of matrix K (number of columns in A and rows in B).
// - N_size_i     : Size of matrix N (number of columns in B and C).
// - M_count_o    : Current count of M dimension.
// - K_count_o    : Current count of K dimension.
// - N_count_o    : Current count of N dimension.
//---------------------------

module gemm_controller #(
  parameter int unsigned AddrWidth = 16
)(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic start_i,
  input  logic input_valid_i,
  output logic result_valid_o,
  output logic busy_o,
  output logic done_o,
  // The target M, K, and N sizes
  input  logic [AddrWidth-1:0] M_size_i,
  input  logic [AddrWidth-1:0] K_size_i,
  input  logic [AddrWidth-1:0] N_size_i,
  // The the current M, K, and N counts
  output logic [AddrWidth-1:0] M_count_o,
  output logic [AddrWidth-1:0] K_count_o,
  output logic [AddrWidth-1:0] N_count_o,
  // The the sub-matrix current M, and N counts (kernel)
  output logic [AddrWidth-1:0] M_sub_count_o,
  output logic [AddrWidth-1:0] N_sub_count_o
);

  //-----------------------
  // Wires and logic
  //-----------------------
  logic move_K_counter;
  logic move_N_counter;
  logic move_M_counter;
  logic move_counter;

  assign move_K_counter = move_counter;

  logic clear_counters;
  logic last_counter_last_value;

  // State machine states
  typedef enum logic [1:0] {
    ControllerIdle,
    ControllerBusy,
    ControllerFinish
  } controller_state_t;

  controller_state_t current_state, next_state;

  assign busy_o = (current_state == ControllerBusy  ) ||
                  (current_state == ControllerFinish);

  //-----------------------
  // DESIGN NOTE:
  // Counters for M, K, and N dimensions.
  // These counters are used to keep track of the current position
  // in the matrix multiplication process.
  //
  // They are instantiated using a generic ceiling_counter module.
  // Each counter increments based on the move_counter signal
  // and resets when clear_counters is asserted.
  //
  // Practically, for a single MAC we use a simple for-loop scheme:
  //
  // for m = 0 to M-1
  //   for n = 0 to N-1
  //     for k = 0 to K-1
  //       C[m][n] += A[m][k] * B[k][n]
  //
  // This is the dataflow that the counters help to manage.
  // This will change when we start to have more spatial parallelism.
  // For example, when we isert parfor loops, then the effective counters
  // get divided by some parallelism factor S. Refer to lecture 3 again
  // for more details on this.
  //
  // In the counter instantiations below, take note that
  // the last_value_o output is used to signal when the counter
  // has reached its ceiling value. This is crucial for the controller
  // to determine when to transition states and manage the overall flow.
  //-----------------------

  // Counters for M, K, N

  // K Counter
  ceiling_counter #(
    .Width        (      AddrWidth ),
    .HasCeiling   (              1 )
  ) i_K_counter (
    .clk_i        ( clk_i          ),
    .rst_ni       ( rst_ni         ),
    .tick_i       ( move_K_counter ),
    .clear_i      ( clear_counters ),
    .ceiling_i    ( K_size_i >> 2  ),
    .count_o      ( K_count_o      ),
    .last_value_o ( move_N_counter )
  );

  // N Counter
  ceiling_counter #(
    .Width        (      AddrWidth ),
    .HasCeiling   (              1 )
  ) i_N_counter (
    .clk_i        ( clk_i          ),
    .rst_ni       ( rst_ni         ),
    .tick_i       ( move_N_counter ),
    .clear_i      ( clear_counters ),
    .ceiling_i    ( N_size_i  >> 2 ),
    .count_o      ( N_count_o      ),
    .last_value_o ( move_M_counter )
  );

  // M Counter
  ceiling_counter #(
    .Width        (               AddrWidth ),
    .HasCeiling   (                       1 )
  ) i_M_counter (
    .clk_i        ( clk_i                   ),
    .rst_ni       ( rst_ni                  ),
    .tick_i       ( move_M_counter          ),
    .clear_i      ( clear_counters          ),
    .ceiling_i    ( M_size_i           >> 2 ),
    .count_o      ( M_count_o               ),
    .last_value_o ( last_counter_last_value )
  );

  //-----------------------
  // DESIGN NOTE:
  // Below is the contoller state machine where we split the sequential
  // updates from the change of states.
  //
  // When making FSMs, it's a good practice to separate the
  // sequential logic (state updates) from the combinational logic
  // (next state and outputs). This separation helps in
  // avoiding unintended latches and makes the design clearer.
  // You can clearly follow as you read along what each state does,
  // and how the outputs change for the given state and a certain input.
  // Note that the output of the counters are also inputs to the FSM logic.
  // Hence that is why the counters and the FSM are tightly coupled together.
  //
  // Moreover, this FSM is more of a mealy machine, that means
  // the output signals depend on both the current state and
  // the inputs. This is evident in how result_valid_o and done_o
  // are generated based on the current state and input conditions.
  //
  // Depending on how you want to design your controller,
  // states and the operations can differ. Just make sure to be
  // consistent with your design choices.
  //-----------------------

  // Main controller state machine
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      current_state <= ControllerIdle;
    end else begin
      current_state <= next_state;
    end
  end

  always_comb begin
    // Default assignments
    next_state     = current_state;
    clear_counters = 1'b0;
    move_counter   = 1'b0;
    result_valid_o = 1'b0;
    done_o         = 1'b0;

    case (current_state)
      ControllerIdle: begin
        if (start_i) begin
          move_counter = input_valid_i;
          next_state   = ControllerBusy;
        end
      end

      ControllerBusy: begin
        move_counter = input_valid_i;
        // Check if we are done
        if (last_counter_last_value) begin
          next_state = ControllerFinish;
        end else if (input_valid_i
                     && K_count_o == '0 
                     && (M_count_o != '0 || N_count_o != '0)) begin
          // Check when result_valid_o should be asserted
          result_valid_o = 1'b1;
        end
      end

      ControllerFinish: begin
        done_o         = 1'b1;
        result_valid_o = 1'b1;
        clear_counters = 1'b1;
        next_state     = ControllerIdle;
      end

      default: begin
        next_state = ControllerIdle;
      end
    endcase
  end
endmodule
