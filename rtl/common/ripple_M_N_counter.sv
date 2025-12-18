module ripple_M_N_counter #(
    parameter int Width = 8,
    parameter int Chain_Length = 4
) (
    input  logic                     clk_i,
    input  logic                     rst_ni,
    input  logic                     start_i,
    input  logic     [Width-1:0]     M_size_i,
    input  logic     [Width-1:0]     N_size_i,
    output logic     [Width-1:0]     M_count_o [Chain_Length],
    output logic     [Width-1:0]     N_count_o [Chain_Length],
    output logic                     last_value_o [Chain_Length],
    output logic                     done_o [Chain_Length]
);
    logic signed    [Width-1:0]     M_prev;
    logic signed    [Width-1:0]     N_prev;


    logic [1:0] current_state, next_state;
    // NEED RESET SIGNAL TO RESTART COUNTERS
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            M_prev <= 0;
            N_prev <= -1;
        end else if (done_o[Chain_Length-1]) begin
            M_prev <= M_count_o[Chain_Length-1];
            N_prev <= N_count_o[Chain_Length-1];
        end
    end

    genvar i;

    generate
        for (i = 0; i < Chain_Length; i++) begin : gen_counters
            M_N_counter #(
                .Width(Width)
            ) i_M_N_counter (
                .clk_i      ( clk_i ),
                .rst_ni     ( rst_ni ),
                .tick_i     ( (i == 0) ? start_i : done_o[i-1] ),
                .M_size_i   ( M_size_i ),
                .N_size_i   ( N_size_i ),
                .M_prev     ( (i == 0) ? M_prev : M_count_o[i-1] ),
                .N_prev     ( (i == 0) ? N_prev : N_count_o[i-1] ),
                .M_count_o  ( M_count_o[i] ),
                .N_count_o  ( N_count_o[i] ),
                .last_value_o ( last_value_o[i] ),
                .done_o     ( done_o[i] )
            );
        end
    endgenerate


endmodule

module M_N_counter #(
    parameter int Width = 8
) (
    input  logic                     clk_i,
    input  logic                     rst_ni,
    input  logic                     tick_i,
    input  logic     [Width-1:0]     M_size_i,
    input  logic     [Width-1:0]     N_size_i,
    input  logic   signed  [Width-1:0]     M_prev,
    input  logic   signed  [Width-1:0]     N_prev,
    output logic   signed  [Width-1:0]     M_count_o,
    output logic   signed  [Width-1:0]     N_count_o,
    output logic                     last_value_o,
    output logic                     done_o
);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            M_count_o <= '0;
            N_count_o <= '0;
            done_o <= 0;
            last_value_o <= 0;
        end else if(tick_i) begin
            // Check for last value
            if ((M_prev == M_size_i - 1) & (N_prev == N_size_i - 2)) begin
                last_value_o <= 1;
            end else begin
                last_value_o <= 0;
            end

            if (N_prev == N_size_i - 1) begin
                N_count_o = 0;

                if (M_prev == M_size_i - 1) begin
                    // This means we are done
                    done_o <= 0; // No more ripple
                    M_count_o = 0;
                end else begin
                    M_count_o = M_prev + 1;
                    done_o <= 1;
                end
            end else begin
                N_count_o = N_prev + 1;
                M_count_o = M_prev;
                done_o <= 1;
            end
        end else begin
            done_o <= 0;
        end
    end

endmodule