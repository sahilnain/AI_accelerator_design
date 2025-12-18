`timescale 1ns / 1ps

module tb_ripple_M_N_counter;

    // -------------------------------------------------------
    // 1. Parameters & Signals
    // -------------------------------------------------------
    parameter int Width = 8;
    parameter int Chain_Length = 4;

    logic                     clk_i;
    logic                     rst_ni;
    logic                     start_i;
    logic     [Width-1:0]     M_size_i;
    logic     [Width-1:0]     N_size_i;
    logic signed    [Width-1:0]     M_prev; // Input to 1st stage
    logic signed    [Width-1:0]     N_prev; // Input to 1st stage
    
    // Outputs are arrays
    logic     [Width-1:0]     M_count_o [Chain_Length];
    logic     [Width-1:0]     N_count_o [Chain_Length];
    logic                     last_value_o[Chain_Length];
    logic                     done_o[Chain_Length];

    // -------------------------------------------------------
    // 2. DUT Instantiation
    // -------------------------------------------------------
    ripple_M_N_counter #(
        .Width(Width),
        .Chain_Length(Chain_Length)
    ) dut (
        .clk_i      ( clk_i     ),
        .rst_ni     ( rst_ni    ),
        .start_i    ( start_i   ),
        .M_size_i   ( M_size_i  ),
        .N_size_i   ( N_size_i  ),
        .M_count_o  ( M_count_o ),
        .N_count_o  ( N_count_o ),
        .last_value_o ( last_value_o ), 
        .done_o     ( done_o    )
    );

    // -------------------------------------------------------
    // 3. Clock Generation
    // -------------------------------------------------------
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i; // 100MHz clock (10ns period)
    end

    // -------------------------------------------------------
    // 4. Test Stimulus
    // -------------------------------------------------------
    initial begin
        // --- Initialization ---
        rst_ni   = 0;
        start_i  = 0;
        M_size_i = 8'd5; // Matrix Row Limit
        N_size_i = 8'd3; // Matrix Col Limit
        M_prev   = 0;
        N_prev   = -1;

        // --- Reset Sequence ---
        @(negedge clk_i);
        rst_ni = 1;
        $display("\n=== Simulation Start: Chain Length = %0d ===", Chain_Length);

        // --- Test Case 1: Single Pulse Propagation ---
        $display("\n--- Test 1: Single Pulse (Seed: M=0, N=-1) ---");
        // We expect this to ripple: (0,0) -> (0,1) -> (0,2) -> (0,3) -> (1,0) ...
        // depending on how many stages vs logic. 
        // Logic is: If N!=Max, N+1. Else N=0, M+1.
        
        drive_input(0, -1); // Start the ripple with prev=0,0
        
        // Wait for the ripple to exit the pipe
        repeat(Chain_Length + 2) @(posedge clk_i);


        // --- Test Case 2: Wrapping Logic (Column End) ---
        $display("\n--- Test 2: Column Wrap (Seed: M=0, N=3 [Max-1]) ---");
        // Logic check: N_prev is 3. N_size is 4. Next should be N=0, M=1.
        
        drive_input(0, 3);
        repeat(Chain_Length + 2) @(posedge clk_i);


        // --- Test Case 3: Full Pipeline Stream ---
        $display("\n--- Test 3: Continuous Streaming ---");
        // We will feed data every cycle to fill the pipeline
        
        // Cycle 1 input
        drive_input(0, 3);
        repeat(Chain_Length) @(posedge clk_i);


        $display("\n=== Force new, should restart ===");
        // This should restart the counter as we hit the end
        drive_input(0, 3);
        repeat(Chain_Length + 2) @(posedge clk_i);


        $display("\n=== Simulation Complete ===");
        $finish;
    end

    // -------------------------------------------------------
    // 5. Helper Tasks
    // -------------------------------------------------------
    
    // Drive input for one cycle then clear (Blocking wait)
    task drive_input(input int m, input int n);
        @(negedge clk_i);
        M_prev = m;
        N_prev = n;
        start_i = 1;
        @(negedge clk_i);
        start_i = 0;
    endtask

    // Drive input non-blocking (doesn't wait for start_i to clear)
    task drive_input_nb(input int m, input int n);
        #1; // minimal delay to set after clock edge
        M_prev = m;
        N_prev = n;
        start_i = 1;
    endtask

    // -------------------------------------------------------
    // 6. Output Monitor (Visualization)
    // -------------------------------------------------------
    // This block prints the state of the pipeline every cycle
    always @(posedge clk_i) begin
        if (rst_ni) begin
            #1; // Wait for outputs to settle after posedge
            $write("T=%0t | In: St=%b (%0d,%0d) | Pipe: ", $time, start_i, M_prev, N_prev);
            
            for (int i = 0; i < Chain_Length; i++) begin
                // Accessing internal 'done' signal via hierarchical path if needed, 
                // but we can infer validity by checking if data is non-zero or observing propagation.
                // However, since 'done' is internal to DUT, we look at the outputs.
                // Let's format it as [M,N]
                $write("[%0d,%0d] ", M_count_o[i], N_count_o[i]);
            end
            
            if (done_o[Chain_Length-1]) $write(" -> DONE Pulse");
            if (last_value_o.or()) $write(" -> LAST VALUE Reached");
            $write("\n");
        end
    end

    // Optional: Generate waveform file
    initial begin
        $dumpfile("ripple_counter.vcd");
        $dumpvars(0, tb_ripple_M_N_counter);
    end

endmodule