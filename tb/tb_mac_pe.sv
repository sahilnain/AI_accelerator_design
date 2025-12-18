//--------------------------
// MAC PE Testbench
// - Unit test to check the functionality of the PE
//--------------------------

module tb_mac_pe;

  //---------------------------
  // Design Time Parameters
  //---------------------------

  // MAC Parameters
  parameter int unsigned InDataWidth  = 8;
  parameter int unsigned OutDataWidth = 32;
  parameter int unsigned NumInputs    = 1;

  //---------------------------
  // Test Parameters
  //---------------------------
  parameter int unsigned NumTests = 1;

  //---------------------------
  // Wires
  //---------------------------

  // Clock and reset
  logic clk_i, rst_ni;

  // Input signals
  logic signed [NumInputs-1:0][InDataWidth-1:0] a_i, b_i;
  logic a_valid_i, b_valid_i;

  // Output signal
  logic signed [OutDataWidth-1:0] c_o;
  logic signed [OutDataWidth-1:0] golden_c_o;

  logic [1:0] acc_mux_sel;
  logic signed [OutDataWidth-1:0] acc_north;
  logic signed [OutDataWidth-1:0] acc_west;
  logic signed [NumInputs-1:0][InDataWidth-1:0] a_o_east;
  logic signed [NumInputs-1:0][InDataWidth-1:0] b_o_south;
  logic signed [OutDataWidth-1:0] acc_east;
  logic signed [OutDataWidth-1:0] acc_south;

  // Instantiate the MAC PE module
  general_mac_pe #(
    .InDataWidth  ( InDataWidth            ),
    .NumInputs    ( 1                      ),
    .OutDataWidth ( OutDataWidth           )
  ) i_mac_pe (
    .rst_ni       ( rst_ni           ),
    .clk_i        ( clk_i            ),
    .a_i          ( a_i              ),
    .b_i          ( b_i              ),
    .a_valid_i    ( a_valid_i        ),
    .b_valid_i    ( b_valid_i        ),
    .acc_north    ( acc_north        ),
    .acc_mux_sel  ( acc_mux_sel      ),
    .acc_west     ( acc_west         ),
    .a_o_east     ( a_o_east         ),
    .b_o_south    ( b_o_south        ),
    .acc_east     ( acc_east         ),
    .acc_south    ( acc_south        )
  );

  //---------------------------
  // Tasks and functions
  //---------------------------
  `include "includes/common_tasks.svh"

  function automatic void mac_pe_golden(
    input  logic signed [NumInputs-1:0][InDataWidth-1:0] A_i,
    input  logic signed [NumInputs-1:0][InDataWidth-1:0] B_i,
    output logic signed [OutDataWidth-1:0] C_o
  );
    int unsigned i;

    C_o = '0;
    for (i = 0; i < NumInputs; i++) begin
      C_o += $signed(A_i[i]) * $signed(B_i[i]);
    end

  endfunction

  //---------------------------
  // Start of testbench
  //---------------------------

  // Clock generation
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;  // 100MHz clock
  end

  // Test control
  initial begin

    // Initialize inputs
    clk_i       = 1'b0;
    rst_ni      = 1'b0;
    a_valid_i   = 1'b0;
    b_valid_i   = 1'b0;
    acc_mux_sel = 2'b00;
    acc_north   = '0;
    acc_west    = '0;

    for (int i = 0; i < NumInputs; i++) begin
      a_i[i] = '0;
      b_i[i] = '0;
      clk_delay(1);
    end

    clk_delay(3);

    // Release reset
    #1;
    rst_ni = 1;

    // 1 cycle delay after reset
    clk_delay(1);

    // Driver conntrol
    for (int i = 0; i < NumTests; i++) begin

      for (int j = 0; j < NumInputs; j++) begin
        a_i[j] = -1; // $urandom();
        b_i[j] = 10; //$urandom();
      end

      // Calculate golden value
      mac_pe_golden(a_i, b_i, golden_c_o);

      // Set the valid signals
      a_valid_i = 1;
      b_valid_i = 1;
      clk_delay(1);
      clk_delay(1);

      a_valid_i = 0;
      b_valid_i = 0;

      // Check if a and b are passed correctly
      if(a_o_east !== a_i) begin
        $display("Error in test A output %0d", i);
        for (int j = 0; j < NumInputs; j++) begin
          $display("A[%0d]: %d, B[%0d]: %d",
            j, $signed(a_i[j]), j, $signed(b_i[j]));
        end
        $display("OUT: %p, GOLDEN: %p", a_o_east, a_i);
        $fatal;
      end

      if(b_o_south !== b_i) begin
        $display("Error in test B output %0d", i);
        for (int j = 0; j < NumInputs; j++) begin
          $display("A[%0d]: %d, B[%0d]: %d",
            j, $signed(a_i[j]), j, $signed(b_i[j]));
        end
        $display("OUT: %p, GOLDEN: %p", b_o_south, b_i);
        $fatal;
      end

      // Check if south signal is correct is correct
      if(golden_c_o !== acc_south) begin
        $display("Error in test acc south %0d", i);
        for (int j = 0; j < NumInputs; j++) begin
          $display("A[%0d]: %d, B[%0d]: %d",
            j, $signed(a_i[j]), j, $signed(b_i[j]));
        end
        $display("OUT: %d, GOLDEN: %d", $signed(acc_south), $signed(golden_c_o));
        $fatal;
      end

      // Check if west signal is correct is correct
      if(golden_c_o !== acc_east) begin
        $display("Error in test acc east %0d", i);
        for (int j = 0; j < NumInputs; j++) begin
          $display("A[%0d]: %d, B[%0d]: %d",
            j, $signed(a_i[j]), j, $signed(b_i[j]));
        end
        $display("OUT: %d, GOLDEN: %d", $signed(acc_east), $signed(golden_c_o));
        $fatal;
      end

      // Clear the PE
      acc_mux_sel = 2'b11;
      clk_delay(1);
      if(acc_east != 2'b00) begin
        $display("Error in test acc east clear");
        $display("OUT: %d", $signed(acc_south));
        $fatal;
      end
      if(acc_south != 2'b00) begin
        $display("Error in test acc south clear");
        $display("OUT: %d", $signed(acc_south));
        $fatal;
      end

      // Check the accumulator west and south outputs using different mux values
      for (int mux_sel = 1; mux_sel < 4; mux_sel++) begin
        acc_mux_sel = mux_sel;
        acc_north = $urandom();
        acc_west  = $urandom();

        clk_delay(1);
        if(mux_sel == 1) begin
          // clk_delay(1);
          // acc_north
          if(acc_east != acc_north) begin
            $display("Error in test acc east with north mux %0d", mux_sel);
            $display("OUT: %d, GOLDEN: %d", $signed(acc_east), $signed(acc_north));
            $fatal;
          end
          if(acc_south != acc_north) begin
            $display("Error in test acc south with north mux %0d", mux_sel);
            $display("OUT: %d, GOLDEN: %d", $signed(acc_south), $signed(acc_north));
            $fatal;
          end

        end else if (mux_sel == 2) begin
          // clk_delay(1);
          // acc_east
          if(acc_east != acc_west) begin
            $display("Error in test acc east with east mux %0d", mux_sel);
            $display("OUT: %d, GOLDEN: %d", $signed(acc_east), $signed(acc_west));
            $fatal;
          end
          if(acc_south != acc_west) begin
            $display("Error in test acc south with east mux %0d", mux_sel);
            $display("OUT: %d, GOLDEN: %d", $signed(acc_south), $signed(acc_west));
            $fatal;
          end

        end else begin
          // clk_delay(1);
          // zero
          if(acc_east != '0) begin
            $display("Error in test acc east with 0 mux %0d", mux_sel);
            $display("OUT: %d", $signed(acc_east));
            $fatal;
          end
          if(acc_south != '0) begin
            $display("Error in test acc south with 0 mux %0d", mux_sel);
            $display("OUT: %d", $signed(acc_south));
            $fatal;
          end

        end

      end

      $display("Test %0d passed.", i);
    end

    // Finish simulation after some time
    clk_delay(5);
    $display("All tests passed!");

    $finish;
  end

endmodule
