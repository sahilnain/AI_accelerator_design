// ------
// Gemm Sub Controller
//
// Description:
// This is the sub-kernel controller for the GeMM accelerator.
// the sub kernel is of size MxM = 4x4 usually.
// Need a M and N counter only

module gemm_sub_controller #(
    parameter int unsigned AddrWidth = 16,
    parameter unsigned [7:0] kernel_size = 4 
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic start_i,
    input  logic input_valid_i,
    output logic result_valid_o,
    output logic busy_o,
    output logic done_o,
    // The the sub-matrix current M, and N counts
    output logic [AddrWidth-1:0] N_sub_count_o
);
    //-----------------------
    // Wires and logic
    //-----------------------
    logic move_N_counter;
    logic move_counter;

    assign move_N_counter = move_counter;

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
    // A[m][n] * B[n][m] = C[m][m]
    //-----------------------
    // N Counter
    ceiling_counter #(
        .Width        (      AddrWidth ),
        .HasCeiling   (              1 )
    ) i_N_counter (
        .clk_i        ( clk_i          ),
        .rst_ni       ( rst_ni         ),
        .tick_i       ( move_N_counter ),
        .clear_i      ( clear_counters ),
        .ceiling_i    ( kernel_size    ),
        .count_o      ( N_sub_count_o  ),
        .last_value_o ( last_counter_last_value )
    );

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
                        && N_sub_count_o == '0 ) begin
                // Check when result_valid_o should be asserted
                result_valid_o = 1'b1;
            end
        end

        ControllerFinish: begin
            done_o         = 1'b1;
            result_valid_o = 1'b1;
            clear_counters = 1'b1;
            next_state     = ControllerBusy; // Always keep it busy free running
        end

        default: begin
            next_state = ControllerIdle;
        end
        endcase
    end

endmodule