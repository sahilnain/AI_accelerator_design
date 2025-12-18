//--------------------------
// Useful functions for testing
//--------------------------
function automatic void gemm_golden(
  input  logic [AddrWidth-1:0] M,
  input  logic [AddrWidth-1:0] K,
  input  logic [AddrWidth-1:0] N,
  input  logic signed [ InDataWidth-1:0] A_i [DataDepth],
  input  logic signed [ InDataWidth-1:0] B_i [DataDepth],
  output logic signed [OutDataWidth-1:0] Y_o [DataDepth]
);
  int unsigned m, n, k;
  int signed acc;

  for (m = 0; m < M; m++) begin
    for (n = 0; n<N; n++) begin
      acc = 0;
      for (k = 0; k < K; k++) begin
        acc += $signed(A_i[m*K + k]) * $signed(B_i[k*N + n]);
      end
      Y_o[m*N + n] = acc;
    end
end
endfunction

function automatic void remap_to_4x4_blocks_row(
  input  int M, // number of rows
  input  int N, // number of columns
  input  logic signed [InDataWidth-1:0] A_i [DataDepth], 
  output logic signed [InDataWidth-1:0] A_o [DataDepth]
);
  int m, n;
  
  // Coordinate variables
  int blk_row, blk_col;   // Coordinates of the 4x4 block
  int sub_row, sub_col;   // Coordinates inside the 4x4 block
  int blocks_per_row;     // How many blocks fit in the width
  int block_idx;          // Linear index of the block
  int new_width;          // New width in terms of number of elements
  
  blocks_per_row = N >> 2; // N / 4
  new_width = M * blocks_per_row; // M * blocks_per_row

  for (m = 0; m < M; m++) begin
    for (n = 0; n < N; n++) begin
      blk_row = m >> 2;
      blk_col = n >> 2;

      sub_row = m & 2'b11; // m % 4
      sub_col = n & 2'b11; // n % 4

      // Number of the block in linear memory
      block_idx = (blk_row * blocks_per_row) + blk_col;

      // block_idx * 4 + sub_row * new_width + sub_col
      A_o[ (block_idx<<2) + (sub_row*new_width) + sub_col ] = A_i[m*N + n];
      
    end
  end
endfunction

function automatic void remap_4x4_blocks_to_normal(
  // To remap result output matrix from 4x4 block format back to normal row-major format
  input  int M, // number of rows
  input  int N, // number of columns
  input  logic signed [InDataWidth-1:0] A_i [DataDepth], 
  output logic signed [InDataWidth-1:0] A_o [DataDepth]
);
  int m, n;
  
  // Coordinate variables
  int blk_row, blk_col;   // Coordinates of the 4x4 block
  int sub_row, sub_col;   // Coordinates inside the 4x4 block
  int blocks_per_row;     // How many blocks can fit in a reconstructed row
  int blocks_per_col;     // How many blocks can fit in a reconstructed column
  int block_idx;          // Linear index of the block
  int new_width;          // New width in terms of number of elements
  
  blocks_per_row = N >> 2; // N / 4
  new_width = M * blocks_per_row; // M * blocks_per_row

  for (m = 0; m < M; m++) begin
    for (n = 0; n < N; n++) begin
      blk_row = m >> 2;
      blk_col = n >> 2;

      sub_row = m & 2'b11; // m % 4
      sub_col = n & 2'b11; // n % 4

      // Number of the block in linear memory
      block_idx = (blk_row * blocks_per_row) + blk_col;

      // block_idx * 4 + sub_row * new_width + sub_col
      A_o[m*N + n] = A_i[ (block_idx<<2) + (sub_row*new_width) + sub_col ];
    end
  end

endfunction

function automatic void remap_to_4x4_blocks_col(
  input  int M, // number of rows
  input  int N, // number of columns
  input  logic signed [InDataWidth-1:0] A_i [DataDepth], 
  output logic signed [InDataWidth-1:0] A_o [DataDepth]
);
  int m, n;
  
  // Coordinate variables
  int blk_row, blk_col;   // Coordinates of the 4x4 block
  int sub_row, sub_col;   // Coordinates inside the 4x4 block
  int blocks_per_row;     // How many blocks fit in the height
  int block_idx;          // Linear index of the block
  int new_height;          // New width in terms of number of elements
  
  blocks_per_row = N >> 2; // N / 4
  new_height = N * blocks_per_row; // N * blocks_per_row

  for (m = 0; m < M; m++) begin
    for (n = 0; n < N; n++) begin
      blk_row = m >> 2;
      blk_col = n >> 2;

      sub_row = m & 2'b11; // m % 4
      sub_col = n & 2'b11; // n % 4

      // Number of the block in linear memory
      block_idx = (blk_row * blocks_per_row) + blk_col;

      // block_idx * 16 + sub_row * 4 + sub_col
      A_o[ (block_idx<<4) + (sub_row<<2) + sub_col ] = A_i[m*N + n];
      
    end
  end
endfunction

function automatic void row_major_to_col_major(
  input  int M, // number of rows
  input  int N, // number of columns
  input  logic signed [InDataWidth-1:0] A_i [DataDepth], 
  output logic signed [InDataWidth-1:0] A_o [DataDepth]
);
  int m, n;

  for (m = 0; m < M; m++) begin
    for (n = 0; n < N; n++) begin
      A_o[n*M + m] = A_i[m*N + n];
    end
  end
endfunction

function automatic void remap_to_4x4_blocks_col_col_major(
  input  int M, // number of rows
  input  int N, // number of columns
  input  logic signed [InDataWidth-1:0] A_i [DataDepth], 
  output logic signed [InDataWidth-1:0] A_o [DataDepth]
);

  logic signed [InDataWidth-1:0] temp_memory [DataDepth];

  remap_to_4x4_blocks_col(M, N, A_i, temp_memory);
  row_major_to_col_major(M, N, temp_memory, A_o);
endfunction