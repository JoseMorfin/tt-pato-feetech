/*
 * tt_um_josemorfin_feetech: motor de paquetes para servos Feetech STS (bus serie half-duplex) del pato.
 * Jose Morfin (cowork, 20-nov-2026). Licencia Apache-2.0.
 * El micro escribe el cuerpo del paquete (ID, LEN, INSTR, parametros) byte a byte; el chip agrega
 * 0xFF 0xFF, calcula el checksum ~(suma del cuerpo) y transmite por UART 8N1 con divisor programable.
 * ui_in[7:0] dato o divisor | uio_in[0] WR | uio_in[1] GO | uio_in[2] BAUD | uio_in[3] CLR
 * uo_out[0] TX | [1] BUSY | [2] TXEN | [3] FULL | [7:4] bytes en FIFO | uio_out[7:4] checksum (nibble bajo)
 */
`default_nettype none
module tt_um_josemorfin_feetech (
    input  wire [7:0] ui_in, output wire [7:0] uo_out,
    input  wire [7:0] uio_in, output wire [7:0] uio_out, output wire [7:0] uio_oe,
    input  wire ena, input wire clk, input wire rst_n);

  reg [3:0] c1, c2, c3;
  always @(posedge clk) begin c1 <= uio_in[3:0]; c2 <= c1; c3 <= c2; end
  wire wr_p = c2[0] & ~c3[0], go_p = c2[1] & ~c3[1], baud_p = c2[2] & ~c3[2], clr = c2[3];

  reg [7:0] fifo [0:15];
  reg [4:0] n;            // bytes en la FIFO
  reg [7:0] div;          // ciclos por bit - 1
  reg [7:0] suma, chk;
  reg busy;
  reg [4:0] idx;          // 0,1 = FF; 2..n+1 = cuerpo; n+2 = checksum
  reg [3:0] bitn;         // 0..9 (start, 8 datos, stop)
  reg [7:0] cnt;
  reg [9:0] sh;
  reg tx;

  wire [4:0] total = n + 5'd3;
  wire [4:0] cuerpo_i = idx - 5'd2;
  wire [7:0] byte_actual = (idx < 5'd2) ? 8'hFF : (idx < n + 5'd2) ? fifo[cuerpo_i[3:0]] : ~suma;

  always @(posedge clk) begin
    if (!rst_n) begin
      n <= 0; div <= 8'd24; suma <= 0; chk <= 0; busy <= 0; idx <= 0; bitn <= 0; cnt <= 0;
      sh <= 10'h3FF; tx <= 1'b1;
    end else if (!busy) begin
      tx <= 1'b1;
      if (baud_p) div <= ui_in;
      if (clr) begin n <= 0; suma <= 0; end
      else if (wr_p && n < 5'd16) begin fifo[n[3:0]] <= ui_in; n <= n + 1'b1; suma <= suma + ui_in; end
      if (go_p && n != 0) begin busy <= 1'b1; idx <= 0; bitn <= 0; cnt <= 0; sh <= {1'b1, 8'hFF, 1'b0}; end
    end else begin
      if (cnt == 0 && bitn == 0) sh <= {1'b1, byte_actual, 1'b0};   // carga el byte al empezar
      if (cnt == 0) tx <= (bitn == 0) ? 1'b0 : sh[bitn];             // bit actual a la linea
      if (cnt == div) begin
        cnt <= 0;
        if (bitn == 4'd9) begin
          bitn <= 0;
          if (idx + 1'b1 == total) begin busy <= 1'b0; chk <= ~suma; n <= 0; suma <= 0; end
          else idx <= idx + 1'b1;
        end else bitn <= bitn + 1'b1;
      end else cnt <= cnt + 1'b1;
    end
  end

  assign uo_out  = {(n[4] ? 4'hF : n[3:0]), n[4], busy, busy, tx};
  assign uio_out = {chk[3:0], 4'b0000};
  assign uio_oe  = 8'b1111_0000;
  wire _unused = &{ena, uio_in[7:4], chk[7:4], 1'b0};
endmodule
