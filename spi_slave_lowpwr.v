///////////////////////////////////////////////////////////////////////////////
// Description: Low-Power SPI Slave
// Enhancements: Clock gating, sleep mode, selective register updates,
// and output retention for low dynamic power consumption.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module SPI_Slave_LowPower
  #(parameter SPI_MODE = 0)
  (
   input            i_Rst_L,
   input            i_Clk,
   output reg       o_RX_DV,
   output reg [7:0] o_RX_Byte,
   input            i_TX_DV,
   input  [7:0]     i_TX_Byte,
   input            i_SPI_Clk,
   output reg       o_SPI_MISO,
   input            i_SPI_MOSI,
   input            i_SPI_CS_n
   );

  // SPI mode decoding
  wire w_CPOL  = (SPI_MODE == 2) | (SPI_MODE == 3);
  wire w_CPHA  = (SPI_MODE == 1) | (SPI_MODE == 3);
  wire w_SPI_Clk = w_CPHA ? ~i_SPI_Clk : i_SPI_Clk;

  // Internal registers
  reg [2:0] r_RX_Bit_Count, r_TX_Bit_Count;
  reg [7:0] r_Temp_RX_Byte, r_RX_Byte, r_TX_Byte;
  reg       r_RX_Done, r2_RX_Done, r3_RX_Done;
  reg       r_SPI_MISO_Bit, r_Preload_MISO;

  // Low Power Control
  reg       r_Active;         // Indicates if slave is active
  reg       r_LowPower_Mode;  // Sleep mode indicator

  // ------------------------
  // 1. Activity Detection & Clock Gating
  // ------------------------
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
      r_Active <= 1'b0;
    else if (~i_SPI_CS_n)
      r_Active <= 1'b1;       // Active when chip selected
    else
      r_Active <= 1'b0;
  end

  // Generate low-power enable (clock gating)
  wire w_Clk_En = r_Active;   // Enable only when CS_n=0

  // ------------------------
  // 2. Receive Path (Clock Gated)
  // ------------------------
  always @(posedge w_SPI_Clk or posedge i_SPI_CS_n)
  begin
    if (i_SPI_CS_n)
    begin
      r_RX_Bit_Count <= 0;
      r_RX_Done      <= 1'b0;
    end
    else if (w_Clk_En)
    begin
      r_RX_Bit_Count <= r_RX_Bit_Count + 1;
      r_Temp_RX_Byte <= {r_Temp_RX_Byte[6:0], i_SPI_MOSI};

      if (r_RX_Bit_Count == 3'b111)
      begin
        r_RX_Done <= 1'b1;
        r_RX_Byte <= {r_Temp_RX_Byte[6:0], i_SPI_MOSI};
      end
      else if (r_RX_Bit_Count == 3'b010)
        r_RX_Done <= 1'b0;
    end
  end

  // ------------------------
  // 3. Clock Domain Crossing + Selective Update
  // ------------------------
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
    begin
      r2_RX_Done <= 1'b0;
      r3_RX_Done <= 1'b0;
      o_RX_DV    <= 1'b0;
      o_RX_Byte  <= 8'h00;
    end
    else if (w_Clk_En)
    begin
      r2_RX_Done <= r_RX_Done;
      r3_RX_Done <= r2_RX_Done;

      if (~r3_RX_Done & r2_RX_Done) // rising edge
      begin
        o_RX_DV   <= 1'b1;
        o_RX_Byte <= r_RX_Byte;
      end
      else
        o_RX_DV <= 1'b0;
    end
  end

  // ------------------------
  // 4. Transmit Path with Output Retention
  // ------------------------
  always @(posedge w_SPI_Clk or posedge i_SPI_CS_n)
  begin
    if (i_SPI_CS_n)
    begin
      r_TX_Bit_Count <= 3'b111;
      r_SPI_MISO_Bit <= r_TX_Byte[3'b111];
    end
    else if (w_Clk_En)
    begin
      r_TX_Bit_Count <= r_TX_Bit_Count - 1;
      r_SPI_MISO_Bit <= r_TX_Byte[r_TX_Bit_Count];
    end
  end

  // TX Byte update only on valid pulse (selective register write)
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
      r_TX_Byte <= 8'h00;
    else if (i_TX_DV && w_Clk_En)
      r_TX_Byte <= i_TX_Byte;
  end

  // Preload control
  always @(posedge w_SPI_Clk or posedge i_SPI_CS_n)
  begin
    if (i_SPI_CS_n)
      r_Preload_MISO <= 1'b1;
    else if (w_Clk_En)
      r_Preload_MISO <= 1'b0;
  end

  wire w_SPI_MISO_Mux = r_Preload_MISO ? r_TX_Byte[3'b111] : r_SPI_MISO_Bit;

  // Tri-state output during idle
  always @(*)
  begin
    if (i_SPI_CS_n)
      o_SPI_MISO = 1'bZ;      // High-Z during idle
    else
      o_SPI_MISO = w_SPI_MISO_Mux;
  end

  // ------------------------
  // 5. Low Power Sleep Mode
  // ------------------------
  always @(posedge i_Clk or negedge i_Rst_L)
  begin
    if (~i_Rst_L)
      r_LowPower_Mode <= 1'b0;
    else if (~r_Active && ~r_RX_Done)
      r_LowPower_Mode <= 1'b1;    // Enter sleep
    else if (r_Active)
      r_LowPower_Mode <= 1'b0;    // Wake up on CS_n low
  end

endmodule
