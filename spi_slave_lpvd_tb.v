///////////////////////////////////////////////////////////////////////////////
// Description:       Simple test bench for SPI Master and Slave modules (Verilog)
// Converted from SystemVerilog to Verilog
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module SPI_Slave_TB;

  parameter SPI_MODE = 1; // CPOL = 0, CPHA = 1
  parameter SPI_CLK_DELAY = 20;  // 2.5 MHz
  parameter MAIN_CLK_DELAY = 2;  // 25 MHz

  // Clock polarity/phase signals
  wire w_CPOL;
  wire w_CPHA;

  assign w_CPOL = (SPI_MODE == 2) | (SPI_MODE == 3);
  assign w_CPHA = (SPI_MODE == 1) | (SPI_MODE == 3);

  reg r_Rst_L = 1'b0;

  reg [7:0] dataPayload [0:255];
  reg [7:0] dataLength;

  // SPI signals
  wire w_SPI_Clk;
  reg r_SPI_En = 1'b0;
  reg r_Clk = 1'b0;
  reg r_Master_CS_n = 1'b1;
  wire w_SPI_CS_n;
  wire w_SPI_MOSI;
  wire w_SPI_MISO;

  // Master Specific
  reg [7:0] r_Master_TX_Byte = 8'h00;
  reg r_Master_TX_DV = 1'b0;
  wire w_Master_TX_Ready;
  wire r_Master_RX_DV;
  wire [7:0] r_Master_RX_Byte;

  // Slave Specific
  wire       w_Slave_RX_DV;
  reg        r_Slave_TX_DV;
  wire [7:0] w_Slave_RX_Byte;
  reg  [7:0] r_Slave_TX_Byte;

  // Clock Generator
  always #(MAIN_CLK_DELAY) r_Clk = ~r_Clk;

  // Instantiate Slave
  SPI_Slave #( .SPI_MODE(SPI_MODE) ) SPI_Slave_UUT (
    .i_Rst_L(r_Rst_L),
    .i_Clk(r_Clk),
    .o_RX_DV(w_Slave_RX_DV),
    .o_RX_Byte(w_Slave_RX_Byte),
    .i_TX_DV(w_Slave_RX_DV),
    .i_TX_Byte(w_Slave_RX_Byte), // Loopback
    .i_SPI_Clk(w_SPI_Clk),
    .o_SPI_MISO(w_SPI_MISO),
    .i_SPI_MOSI(w_SPI_MOSI),
    .i_SPI_CS_n(r_Master_CS_n)
  );

  // Instantiate Master
  SPI_Master #(
    .SPI_MODE(SPI_MODE),
    .CLKS_PER_HALF_BIT(2)
    //.NUM_SLAVES(1)
  ) SPI_Master_UUT (
    .i_Rst_L(r_Rst_L),
    .i_Clk(r_Clk),
    .i_TX_Byte(r_Master_TX_Byte),
    .i_TX_DV(r_Master_TX_DV),
    .o_TX_Ready(w_Master_TX_Ready),
    .o_RX_DV(r_Master_RX_DV),
    .o_RX_Byte(r_Master_RX_Byte),
    .o_SPI_Clk(w_SPI_Clk),
    .i_SPI_MISO(w_SPI_MISO),
    .o_SPI_MOSI(w_SPI_MOSI)
  );

  // Send single byte task
  task SendSingleByte;
    input [7:0] data;
    begin
      @(posedge r_Clk);
      r_Master_TX_Byte <= data;
      r_Master_TX_DV   <= 1'b1;
      r_Master_CS_n    <= 1'b0;
      @(posedge r_Clk);
      r_Master_TX_DV <= 1'b0;
      @(posedge w_Master_TX_Ready);
      r_Master_CS_n    <= 1'b1;
    end
  endtask

  // Send multi-byte task
  task SendMultiByte;
    input [7:0] length;
    integer ii;
    begin
      @(posedge r_Clk);
      r_Master_CS_n    <= 1'b0;
      for (ii = 0; ii < length; ii = ii + 1) begin
        @(posedge r_Clk);
        r_Master_TX_Byte <= dataPayload[ii];
        r_Master_TX_DV   <= 1'b1;
        @(posedge r_Clk);
        r_Master_TX_DV <= 1'b0;
        @(posedge w_Master_TX_Ready);
      end
      r_Master_CS_n <= 1'b1;
    end
  endtask

  initial begin
    repeat(10) @(posedge r_Clk);
    r_Rst_L  = 1'b0;
    repeat(10) @(posedge r_Clk);
    r_Rst_L       = 1'b1;
    r_Slave_TX_Byte <= 8'h5A;
    r_Slave_TX_DV   <= 1'b1;
    repeat(10) @(posedge r_Clk);
    r_Slave_TX_DV   <= 1'b0;

    SendSingleByte(8'hC1);
    repeat(100) @(posedge r_Clk);

    dataPayload[0]  = 8'h00;
    dataPayload[1]  = 8'h01;
    dataPayload[2]  = 8'h80;
    dataPayload[3]  = 8'hFF;
    dataPayload[4]  = 8'h55;
    dataPayload[5]  = 8'hAA;
    dataLength      = 6;

    SendMultiByte(dataLength);

    repeat(100) @(posedge r_Clk);
    $finish;
  end

endmodule
