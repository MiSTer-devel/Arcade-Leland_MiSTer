// Ataxx board bring-up bench: streams sim/ataxx_image.bin (make_ataxx_image.py) through the
// HPS loader path and logs the master/slave I/O for comparison with a MAME trace.
//   vlib work && vlog -mfcu -sv -suppress 2244 +define+SIM_NO_SOUND -f flist_board_nosnd.txt leland_board_ax_tb.sv
//   vsim -c -GUSE_ALTDDIO=0 work.leland_board_ax_tb -do "run -all; quit"
// +define+RUN_LEN_MS=N sets the run length after loading (default 20).

`timescale 1ns / 1ps

`ifndef FETCH_LOG
  `define FETCH_LOG 0
`endif
`ifndef RUN_LEN_MS
  `define RUN_LEN_MS 20
`endif

module leland_board_ax_tb;

localparam CLK_PERIOD = 20.83;
localparam IMG_LEN = 7340304;

reg clk_sys = 0;
always #(CLK_PERIOD/2) clk_sys = ~clk_sys;

reg clk_sdram = 0;
initial begin
	#(3.472);
	forever #(CLK_PERIOD/2) clk_sdram = ~clk_sdram;
end

reg reset          = 1;
reg sdram_init     = 1;
reg ioctl_download = 0;
reg [15:0] ioctl_index = 0;
reg        ioctl_wr = 0;
reg [26:0] ioctl_addr = 0;
reg [7:0]  ioctl_data = 0;
wire       ioctl_wait;

wire [15:0] SDRAM_DQ;
wire [12:0] SDRAM_A;
wire  [1:0] SDRAM_BA;
wire        SDRAM_CLK, SDRAM_CKE, SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_DQML, SDRAM_DQMH;

wire        ce_pix, HBlank, HSync, VBlank, VSync;
wire [23:0] rgb;
wire signed [15:0] audio_out;

leland_board #(.USE_ALTDDIO(1'b0), .DL_SETTLE_CYCLES(24'd10000)) dut
(
	.clk_sys(clk_sys),
	.clk_sdram(clk_sdram),
	.reset(reset),
	.sdram_init(sdram_init),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_data),
	.ioctl_wait(ioctl_wait),

	.nvl_download(1'b0), .nvl_index(16'd0), .nvl_wr(1'b0), .nvl_addr(27'd0), .nvl_data(8'd0),
	.nv_rd_addr(8'd0), .nv_rd_data(), .nv_dirty(), .nv_dirty_clr(1'b0),

	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),

	.ce_pix(ce_pix),
	.HBlank(HBlank), .HSync(HSync), .VBlank(VBlank), .VSync(VSync),
	.rgb(rgb),

	.p1_btn(4'h0), .p2_btn(4'h0), .p3_btn(4'h0),
	.p1_wheel(8'h00), .p2_wheel(8'h00), .p3_wheel(8'h00),
	.p1_wheel_y(8'h00), .p2_wheel_y(8'h00),
	.p1_pedal(8'h00), .p2_pedal(8'h00), .p3_pedal(8'h00),
	.p1_joy(8'h00), .p2_joy(8'h00), .p3_joy(8'h00), .p4_joy(8'h00),

	.service(1'b0),
	.audio_out(audio_out)
);

mt48lc16m16a2 chip
(
	.Dq(SDRAM_DQ), .Addr(SDRAM_A), .Ba(SDRAM_BA), .Clk(SDRAM_CLK), .Cke(SDRAM_CKE),
	.Cs_n(SDRAM_nCS), .Ras_n(SDRAM_nRAS), .Cas_n(SDRAM_nCAS), .We_n(SDRAM_nWE),
	.Dqm({SDRAM_DQMH, SDRAM_DQML})
);

reg [7:0] img [0:IMG_LEN-1];
integer fd, rd_count, k;

task ioctl_write_byte(input [26:0] addr, input [7:0] data);
	begin
		@(posedge clk_sys);
		while (ioctl_wait) @(posedge clk_sys);
		ioctl_data <= data;
		ioctl_addr <= addr + 1'b1;
		ioctl_wr   <= 1'b1;
		@(posedge clk_sys);
		ioctl_wr   <= 1'b0;
	end
endtask

initial begin
	fd = $fopen("ataxx_image.bin", "rb");
	if (fd == 0) begin
		$display("ERROR: sim/ataxx_image.bin missing (python make_ataxx_image.py ataxx.zip ataxx_image.bin)");
		$finish;
	end
	rd_count = $fread(img, fd);
	$fclose(fd);
	if (rd_count != IMG_LEN) begin
		$display("ERROR: image is %0d bytes, expected %0d", rd_count, IMG_LEN);
		$finish;
	end

	sdram_init = 1;
	reset      = 1;
	repeat (10) @(posedge clk_sys);
	sdram_init = 0;
	repeat (5) @(posedge clk_sys);

	ioctl_download = 1'b1;
	@(posedge clk_sys);
	ioctl_addr <= 27'd0;
	for (k = 0; k < IMG_LEN; k = k + 1)
		ioctl_write_byte(k, img[k]);
	repeat (20) @(posedge clk_sys);
	ioctl_download = 1'b0;

	$display("=== load done t=%0t (game_id=%0d class=%0d ataxx_sel=%0b) ===", $time,
	         dut.hdr_game_id, dut.hdr_board_class_raw, dut.ataxx_sel);
	reset = 1'b0;

	#(`RUN_LEN_MS * 64'd1_000_000);
	$display("=== run end t=%0t ===", $time);
	ffd = $fopen("vram_ax.bin", "wb");
	for (k = 0; k < 131072; k = k + 1)
		$fwrite(ffd, "%c", dut.vram.mem[k]);
	$fclose(ffd);
	ffd = $fopen("qram_ax.bin", "wb");
	for (k = 0; k < 65536; k = k + 1)
		$fwrite(ffd, "%c", dut.qram.mem[k]);
	$fclose(ffd);
	for (k = 0; k < 64; k = k + 1)
		$display("PAL[%0d]=%02x%02x  PAL[%0d]=%02x%02x", k, dut.palram.mem[2*k+1], dut.palram.mem[2*k],
		         k + 64, dut.palram.mem[2*(k+64)+1], dut.palram.mem[2*(k+64)]);
	$finish;
end

// Frame dump: every 60th frame to frame_ax_<n>.ppm (320x240 visible area)
reg [23:0] fb [0:320*240-1];
integer fx = 0, fy = 0, frame_no = 0, ffd, fi;
reg hb_d = 0, vb_d = 0;
always @(posedge clk_sys) if (ce_pix && !reset) begin
	hb_d <= HBlank;
	vb_d <= VBlank;
	if (!HBlank && !VBlank && fx < 320 && fy < 240) begin
		fb[fy*320 + fx] <= rgb;
		fx <= fx + 1;
	end
	if (HBlank && !hb_d) begin
		fx <= 0;
		if (!VBlank) fy <= fy + 1;
	end
	if (VBlank && !vb_d) begin
		if (frame_no % 60 == 59) begin
			ffd = $fopen($sformatf("frame_ax_%0d.ppm", frame_no + 1), "wb");
			$fwrite(ffd, "P6\n320 240\n255\n");
			for (fi = 0; fi < 320*240; fi = fi + 1)
				$fwrite(ffd, "%c%c%c", fb[fi][23:16], fb[fi][15:8], fb[fi][7:0]);
			$fclose(ffd);
		end
		frame_no <= frame_no + 1;
		fy <= 0;
		fx <= 0;
	end
end

reg [15:0] m_pc, s_pc;
always @(posedge clk_sys) begin
	if (dut.master_ax.CE_6M && ~dut.master_ax.mreq_n && ~dut.master_ax.m1_n) m_pc <= dut.master_ax.cpu_addr;
	if (dut.slave_ax.CE_6M && ~dut.slave_ax.mreq_n && ~dut.slave_ax.m1_n) s_pc <= dut.slave_ax.cpu_addr;
end

integer nfetch = 0;
always @(posedge clk_sys)
	if (!reset && dut.master_ax.CE_6M && ~dut.master_ax.mreq_n && ~dut.master_ax.m1_n &&
	    dut.master_ax.rfsh_n && nfetch < `FETCH_LOG) begin
		nfetch = nfetch + 1;
		$display("MFETCH #%0d pc=%04x op=%02x", nfetch, dut.master_ax.cpu_addr, dut.master_ax.cpu_din);
	end

integer mwr = 0, mrd = 0;
reg [7:0] last_rd_port = 8'hzz;
reg [15:0] last_rd_pc = 16'hzzzz;
reg wr_logged = 1'b0;
always @(posedge clk_sys) begin
	if (!dut.master_ax.io_wr) wr_logged <= 1'b0;
	if (dut.master_ax.CE_6M && dut.master_ax.io_wr && !wr_logged) begin
		wr_logged <= 1'b1;
		mwr = mwr + 1;
		$display("MIOWR #%0d port=%02x data=%02x pc=%04x", mwr, dut.master_ax.cpu_addr[7:0],
		         dut.master_ax.cpu_dout, m_pc);
	end
	if (!reset && dut.master_ax.CE_6M && dut.master_ax.io_rd &&
	    (dut.master_ax.cpu_addr[7:0] != last_rd_port || m_pc != last_rd_pc)) begin
		mrd = mrd + 1;
		$display("MIORD #%0d port=%02x data=%02x pc=%04x", mrd, dut.master_ax.cpu_addr[7:0],
		         dut.master_ax.cpu_din, m_pc);
		last_rd_port = dut.master_ax.cpu_addr[7:0];
		last_rd_pc   = m_pc;
	end
end

always @(posedge clk_sys)
	if (dut.slave_ax.CE_6M && dut.slave_ax.bank_wr)
		$display("SBANK data=%02x pc=%04x", dut.slave_ax.cpu_dout, s_pc);

endmodule
