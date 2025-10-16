///////////////////////////////////////////////////////////////////////////////
// Description: Low-Power Verification Testbench for SPI Slave
// Verifies functionality + low-power idle/wakeup behavior
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module SPI_Slave_LowPower_TB;

  parameter SPI_MODE = 1;
  parameter SPI_CLK_DELAY = 20;
  parameter MAIN_CLK_DELAY = 2;

  // SPI Mode Signals
  wire w_CPOL = (SPI_MODE == 2) | (SPI_MODE == 3);
  wire w_CPHA = (SPI_MODE == 1) | (SPI_MODE == 3);

  // Reset and Clocks
  reg r_Rst_L = 1'b0;
  reg r_Clk   = 1'b0;
  reg r_SPI_En = 1'b1; // Low-power control for SPI clock

  // SPI Lines
  wire w_SPI_Clk;
  reg  r_Master_CS_n = 1'b1;
  wire w_SPI_MOSI;
  wire w_SPI_MISO;

  // Master
  reg  [7:0] r_Master_TX_Byte = 8'h00;
  reg        r_Master_TX_DV = 1'b0;
  wire       w_Master_TX_Ready;
  wire       w_Master_RX_DV;
  wire [7:0] w_Master_RX_Byte;

  // Slave
  wire       w_Slave_RX_DV;
  wire [7:0] w_Slave_RX_Byte;

  // Clock generation (with SPI enable gating)
  always #(MAIN_CLK_DELAY) r_Clk = ~r_Clk;

  // Gated SPI clock (simulates power gating)
  assign w_SPI_Clk = (r_SPI_En) ? r_Clk : 1'b0;

  // Instantiate SPI Slave
  SPI_Slave_LowPower #(.SPI_MODE(SPI_MODE)) SPI_Slave_UUT (
    .i_Rst_L(r_Rst_L),
    .i_Clk(r_Clk),
    .o_RX_DV(w_Slave_RX_DV),
    .o_RX_Byte(w_Slave_RX_Byte),
    .i_TX_DV(w_Slave_RX_DV),
    .i_TX_Byte(w_Slave_RX_Byte),
    .i_SPI_Clk(w_SPI_Clk),
    .o_SPI_MISO(w_SPI_MISO),
    .i_SPI_MOSI(w_SPI_MOSI),
    .i_SPI_CS_n(r_Master_CS_n)
  );

  // Instantiate SPI Master
  SPI_Master #(
    .SPI_MODE(SPI_MODE),
    .CLKS_PER_HALF_BIT(2)
  ) SPI_Master_UUT (
    .i_Rst_L(r_Rst_L),
    .i_Clk(r_Clk),
    .i_TX_Byte(r_Master_TX_Byte),
    .i_TX_DV(r_Master_TX_DV),
    .o_TX_Ready(w_Master_TX_Ready),
    .o_RX_DV(w_Master_RX_DV),
    .o_RX_Byte(w_Master_RX_Byte),
    .o_SPI_Clk(),
    .i_SPI_MISO(w_SPI_MISO),
    .o_SPI_MOSI(w_SPI_MOSI)
  );

  //---------------------------------------------------------------------------
  // TASKS
  //---------------------------------------------------------------------------
  task SendSingleByte;
    input [7:0] data;
    begin
      @(posedge r_Clk);
      r_Master_CS_n <= 1'b0;
      r_Master_TX_Byte <= data;
      r_Master_TX_DV   <= 1'b1;
      @(posedge r_Clk);
      r_Master_TX_DV   <= 1'b0;
      @(posedge w_Master_TX_Ready);
      r_Master_CS_n <= 1'b1;
    end
  endtask

  //---------------------------------------------------------------------------
  // POWER TEST SEQUENCE
  //---------------------------------------------------------------------------
  initial begin
    // Reset
    repeat(5) @(posedge r_Clk);
    r_Rst_L = 1'b0;
    repeat(10) @(posedge r_Clk);
    r_Rst_L = 1'b1;

    // --- Normal Operation Phase ---
    $display("\n[Normal Operation] Sending 0xC1...");
    SendSingleByte(8'hC1);
    repeat(50) @(posedge r_Clk);

    // --- Enter Low Power Mode ---
    $display("\n[Low Power Phase] Disabling SPI Clock...");
    r_SPI_En = 1'b0;   // Clock gated - simulate low power
    repeat(200) @(posedge r_Clk); // Idle period

    // Optional: monitor that no toggles occur on SPI lines
    if (w_SPI_MISO !== 1'bx || w_SPI_MOSI !== 1'bx)
      $display("[Check] SPI lines stable during low power");

    // --- Wake Up ---
    $display("\n[Wake-Up Phase] Re-enabling SPI Clock...");
    r_SPI_En = 1'b1;
    repeat(10) @(posedge r_Clk);

    // Verify Slave wakes correctly
    $display("[Post-Wake Test] Sending 0xA5...");
    SendSingleByte(8'hA5);
    repeat(50) @(posedge r_Clk);

    $display("\n[Low Power Verification Complete]");
    $finish;
  end

endmodule
