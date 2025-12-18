module tb_register_chain;
  //---------------------------
  // Design Time Parameters
  //---------------------------

  parameter int Depth     = 4;
  parameter int DataWidth = 8;

  //---------------------------
  // Wires
  //---------------------------

  logic                     clk_i;
  logic                     rst_ni;
  logic [DataWidth-1:0]     data_in_i;
  logic [DataWidth-1:0]     data_out_o;

  //---------------------------
  // DUT Instantiation
  //---------------------------

  register_chain #(
    .Depth(Depth),
    .DataWidth(DataWidth)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .data_in_i(data_in_i),
    .data_out_o(data_out_o)
  );

  //---------------------------
  // Clock Generation
  //---------------------------

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i; // 10 time units clock period
  end

  //---------------------------
  // Test Sequence
  //---------------------------

  initial begin
    // Initialize signals
    rst_ni = 0;
    data_in_i = '0;

    // Release reset after some time
    #15;
    rst_ni = 1;

    $display("Starting Register Chain Test...");
    $display("Depth: %0d, DataWidth: %0d", Depth, DataWidth);
    // Apply test vectors
    for (int i = 0; i < Depth + 5; i++) begin
      data_in_i = i;
      #10; // Wait for one clock cycle
      $display("Cycle %0d: data_in_i = %0d, data_out_o = %0d", i, data_in_i, data_out_o);
    end

    // Finish simulation
    #20;
    $finish;
  end

endmodule