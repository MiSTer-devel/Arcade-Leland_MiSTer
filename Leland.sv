//============================================================================
//  Leland - MiSTer FPGA Core
//  Leland / Tradewest 1989
//
//  Copyright (C) 2026 shimian5
//
//  This program is free software: you can redistribute it and/or modify it under the
//  terms of the GNU General Public License as published by the Free Software
//  Foundation, either version 3 of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT ANY
//  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
//  PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with this
//  program. If not, see <https://www.gnu.org/licenses/>.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

//----------------------------------------------------------------
// Unused port defaults
//----------------------------------------------------------------
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
// SDRAM pins are driven by leland_board. The DDR3 port is shared by leland_ddr_loader and
// leland_retimer (see the DDR3 mux below).

assign VGA_SL       = 0;
assign VGA_F1       = 0;
assign VGA_SCALER   = 0;
assign VGA_DISABLE  = 0;
assign HDMI_FREEZE  = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

// Signed 16-bit mono audio from the sound board, duplicated to both channels (the real
// board is mono).
assign AUDIO_S   = 1;
assign AUDIO_L   = audio_out;
assign AUDIO_R   = audio_out;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = 0;
assign BUTTONS   = 0;

//----------------------------------------------------------------
// OSD / HPS configuration
//----------------------------------------------------------------
wire [1:0] ar = status[122:121];
assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"Leland;;",
	"-;",
	// Video settings live on their own page.
	"P1,Video Settings;",
	"P1O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	// CRT retimer (status bits in use: 0,10,12:19,121:122).
	// Polarity is inverted on purpose: the default (0) is the retimed 60 Hz
	// output, because native 65.95 Hz will not sync on many CRTs and the
	// OSD is then unreadable, so the option could never be changed.
	"P1O[12],Video Timing,CRT 60Hz,Native 66Hz;",
	"P1O[16:13],CRT V Position,0,Up 1,Up 2,Up 3,Up 4,Up 5,Up 6,Up 7,Up 8,Up 9,Up 10,Up 11,Up 12,Down 1,Down 2,Down 3;",
	// Photometric (timing stays 262 lines / 60 Hz): resamples the 240 source
	// lines onto fewer output lines in linear light, so the picture gets shorter.
	"P1O[19:17],CRT V Size,240 (native),236,232,228,224,220,216,208;",
	"-;",
	"O[10],D-Pad Steering,Velocity,Position;",
	// Fires one timed Test press (with Blue Nitro / P1 Start held) and closes the
	// OSD, which opens the operator menu (Bookkeeping, Diagnostics, Game Set-Up).
	// It is an OSD action rather than a mappable button so it can't be hit by
	// accident during play. status[4] is only used as this trigger.
	"R[4],Service Menu;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	// The 4th button ("Start") exists for Pig Out, whose input scheme maps J1 bits 4-7 to
	// button 1, button 2, start and coin; without it there is nothing to bind to bit 7 and
	// Pig Out never sees a coin. Off-Road uses bit 7 as "Menu Enter" (see svc_req).
	"J1,Nitro,Coin,Gas,Start;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

// ROM loading
wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
// ioctl_wait comes from leland_ddr_loader (which passes through leland_board's
// stall, see board_wait below) -- stalls HPS during SDRAM writes / init
wire        ioctl_wait;

// Three-player digital buttons ([3]=coin, [2]=btn2, [1]=btn1, [0]=btn0)
wire [31:0] joy1, joy2, joy3;
// 4th player (Pig Out only)
wire [31:0] joy4;
// Analog: signed -127..+127, [15:8]=Y (unused -- gas is digital, see p1_pedal
// below), [7:0]=X (one of three steering inputs combined by steering_input.sv)
wire [15:0] joy1_ana, joy2_ana, joy3_ana;
// Spinner: [8]=toggle (flips on every host update), [7:0]=signed delta
wire  [8:0] spinner1, spinner2, spinner3;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.status_menumask(0),
	.ps2_key(ps2_key),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.joystick_0(joy1),
	.joystick_1(joy2),
	.joystick_2(joy3),
	.joystick_3(joy4),
	.joystick_l_analog_0(joy1_ana),
	.joystick_l_analog_1(joy2_ana),
	.joystick_l_analog_2(joy3_ana),

	.spinner_0(spinner1),
	.spinner_1(spinner2),
	.spinner_2(spinner3),

	// Unused rumble outputs
	.joystick_0_rumble(16'd0),
	.joystick_1_rumble(16'd0),
	.joystick_2_rumble(16'd0),
	.joystick_3_rumble(16'd0)
);

//----------------------------------------------------------------
// Clock: the PLL turns 50 MHz into a 48 MHz system clock, which divides cleanly for
// the Z80 (6 MHz, CE every 8 cycles) and the 80186 (8 MHz, CE every 6); the pixel clock
// comes from a phase accumulator.
//----------------------------------------------------------------
wire clk_sys;
wire clk_sdram; // phase-shifted 48 MHz PLL output for SDRAM_CLK
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_sdram),
	.locked(pll_locked)
);

//----------------------------------------------------------------
// Fast ROM loading: an MRA <rom index="0" address="0x30000000"> makes the
// HPS copy the ROM straight into DDR3; leland_ddr_loader then replays it to
// the board as a normal download (or passes a streamed ROM through).
//----------------------------------------------------------------
wire        ld_download, ld_wr, ld_active;
wire [15:0] ld_index;
wire [26:0] ld_addr;
wire  [7:0] ld_data;
wire        board_wait;

wire        ld_acq, ld_ddr_read;
wire [28:0] ld_ddr_addr;

leland_ddr_loader ddr_loader
(
	.clk(clk_sys),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_addr(ioctl_addr),
	.ioctl_wr(ioctl_wr),
	.ioctl_data(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.o_download(ld_download),
	.o_index(ld_index),
	.o_addr(ld_addr),
	.o_wr(ld_wr),
	.o_data(ld_data),
	.b_wait(board_wait),
	.active(ld_active),

	.ddr_acquire(ld_acq),
	.ddr_addr(ld_ddr_addr),
	.ddr_read(ld_ddr_read),
	.ddr_busy(DDRAM_BUSY),
	.ddr_rdata(DDRAM_DOUT),
	.ddr_rdata_ready(DDRAM_DOUT_READY)
);

wire reset      = RESET | status[0] | buttons[1] | ioctl_download | ld_active | ~pll_locked;
wire sdram_init = RESET | ~pll_locked;

//----------------------------------------------------------------
// Video signals from board
//----------------------------------------------------------------
wire       ce_pix;
wire       HBlank, HSync, VBlank, VSync;
wire [23:0] rgb;        // 24-bit colour after palette lookup

wire signed [15:0] audio_out; // mono, from the sound board's DAC mixer

//----------------------------------------------------------------
// Steering: analog stick, d-pad and spinner are combined into the free-running virtual
// dial that leland_board's p*_wheel ports expect (the real wheel is a free-spinning
// encoder, see leland_master.sv).
//----------------------------------------------------------------
reg vblank_d;
always @(posedge clk_sys) vblank_d <= VBlank;
wire ce_frame = VBlank & ~vblank_d; // once-per-frame pulse for the steering ramp

wire [7:0] p1_wheel_pos, p2_wheel_pos, p3_wheel_pos;

steering_input steer1
(
	.clk_sys(clk_sys), .reset(reset), .ce_frame(ce_frame),
	.dpad_pos_mode(status[10]),
	.analog_x(joy1_ana[7:0]),
	.dpad_left(joy1[1]), .dpad_right(joy1[0]),
	.spinner(spinner1),
	.wheel_pos(p1_wheel_pos)
);

steering_input steer2
(
	.clk_sys(clk_sys), .reset(reset), .ce_frame(ce_frame),
	.dpad_pos_mode(status[10]),
	.analog_x(joy2_ana[7:0]),
	.dpad_left(joy2[1]), .dpad_right(joy2[0]),
	.spinner(spinner2),
	.wheel_pos(p2_wheel_pos)
);

steering_input steer3
(
	.clk_sys(clk_sys), .reset(reset), .ce_frame(ce_frame),
	.dpad_pos_mode(status[10]),
	.analog_x(joy3_ana[7:0]),
	.dpad_left(joy3[1]), .dpad_right(joy3[0]),
	.spinner(spinner3),
	.wheel_pos(p3_wheel_pos)
);

// Gas: MiSTer has no analog trigger, so it is a digital button (3rd J1 entry) driving the
// pedal to its two endpoints (0 = released, 255 = full).
wire [7:0] p1_gas = joy1[6] ? 8'hFF : 8'h00;
wire [7:0] p2_gas = joy2[6] ? 8'hFF : 8'h00;
wire [7:0] p3_gas = joy3[6] ? 8'hFF : 8'h00;

// 4-player digital joystick for Pig Out: MiSTer's standard joystick vector low byte
// already matches leland_board's p*_joy layout ([0]=right [1]=left [2]=down [3]=up
// [4]=btn1 [5]=btn2), with the two spare fire bits used as start and coin.
wire [7:0] p1_joy = joy1[7:0];
wire [7:0] p2_joy = joy2[7:0];
wire [7:0] p3_joy = joy3[7:0];
wire [7:0] p4_joy = joy4[7:0];

//----------------------------------------------------------------
// Service / operator menu
//
// The OSD "Service Menu" action (status[4], a trigger) fires one timed press of the Test
// switch. Off-Road (manual p.17) enters its Bookkeeping/Diagnostics menu with Blue Nitro
// (P3's Nitro) held while Test is pressed; Pig Out needs Service plus P1 Start. So during
// the press Test and P3's Nitro are held together for the last 250 ms, and P1 Start is
// held for the whole 300 ms window.
//
// Inside the Off-Road menus P1's "Menu Enter" button (J1 bit 7, unused by the game)
// acts as Blue Nitro, so one controller can select (Nitro) and enter. The press is short
// enough that Blue Nitro is released before the menu is drawn; otherwise it would enter
// the first item. Only p3_btn and p1_joy[6] are touched.
//----------------------------------------------------------------
localparam [24:0] SVC_WINDOW = 25'd14_400_000;        // 300 ms at 48 MHz
localparam [24:0] SVC_TEST_AT = 25'd12_000_000;       // Test + Blue Nitro for the last 250 ms
reg  [24:0] svc_cnt = 25'd0;
reg         svc_trig_d = 1'b0;
always @(posedge clk_sys) begin
	svc_trig_d <= status[4];
	if (status[4] & ~svc_trig_d) svc_cnt <= SVC_WINDOW;
	else if (svc_cnt != 25'd0)   svc_cnt <= svc_cnt - 1'd1;
end
wire svc_start = (svc_cnt != 25'd0);
wire svc_req   = (svc_cnt != 25'd0) && (svc_cnt <= SVC_TEST_AT);
wire p3_nitro  = joy3[4] | svc_req | joy1[7];

//----------------------------------------------------------------
// Board
//----------------------------------------------------------------
leland_board board
(
	.clk_sys(clk_sys),
	.clk_sdram(clk_sdram),
	.reset(reset),
	.sdram_init(sdram_init),

	// ROM loading
	.ioctl_download(ld_download),
	.ioctl_index(ld_index),
	.ioctl_wr(ld_wr),
	.ioctl_addr(ld_addr),
	.ioctl_data(ld_data),
	.ioctl_wait(board_wait),

	// SDRAM
	.SDRAM_DQ  (SDRAM_DQ),
	.SDRAM_A   (SDRAM_A),
	.SDRAM_BA  (SDRAM_BA),
	.SDRAM_CLK (SDRAM_CLK),
	.SDRAM_CKE (SDRAM_CKE),
	.SDRAM_nCS (SDRAM_nCS),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nWE (SDRAM_nWE),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),

	// Video output
	.ce_pix(ce_pix),
	.HBlank(HBlank),
	.HSync(HSync),
	.VBlank(VBlank),
	.VSync(VSync),
	.rgb(rgb),

	// Player inputs (digital buttons + analog)
	//
	// Nitro and Coin are J1 buttons 1-2 (joystick bits 4-5): p1_btn[1] is nitro and
	// p1_btn[3] is coin, matching MAME's GIN0/GIN1 bit layout.
	.p1_btn({joy1[5], 1'b0, joy1[4], 1'b0}),
	.p2_btn({joy2[5], 1'b0, joy2[4], 1'b0}),
	.p3_btn({joy3[5], 1'b0, p3_nitro, 1'b0}),
	// Wheel: free-running virtual dial from steering_input.sv.
	.p1_wheel(p1_wheel_pos),
	.p2_wheel(p2_wheel_pos),
	.p3_wheel(p3_wheel_pos),
	// Gas: digital button (J1's 3rd entry), 0/255 -- see p1_gas comment above.
	.p1_pedal(p1_gas),
	.p2_pedal(p2_gas),
	.p3_pedal(p3_gas),

	// 4-player digital joystick (Pig Out only).
	.p1_joy(p1_joy | {1'b0, svc_start, 6'd0}), // + P1 Start held during the Service Menu press (Pig Out)
	.p2_joy(p2_joy),
	.p3_joy(p3_joy),
	.p4_joy(p4_joy),

	// Service (Test) switch, driven by the OSD "Service Menu" action
	.service(svc_req),

	.audio_out(audio_out)
);

//----------------------------------------------------------------
// Video output to MiSTer framework
//----------------------------------------------------------------
// CRT retimer (rtl/leland_retimer.sv): by default the output is regenerated at NTSC 240p
// (15.73 kHz / 60.03 Hz) from a frame buffer while the game keeps running at its native
// 65.95 Hz. With Video Timing set to Native the game's own timing goes straight to the
// framework.
wire        rt_ce, rt_hb, rt_hs, rt_vb, rt_vs;
wire [23:0] rt_rgb;
wire [28:0] rt_ddr_addr;
wire [63:0] rt_ddr_din;
wire        rt_ddr_rd, rt_ddr_we;

leland_retimer retimer
(
	.clk_sys(clk_sys),
	// keep off the shared DDR3 bus while a ROM is downloading / replaying
	.stop(ioctl_download | ld_active),

	.g_ce_pix(ce_pix),
	.g_hblank(HBlank),
	.g_vblank(VBlank),
	.g_rgb(rgb),
	.vpos(status[16:13]),
	.vsize(status[19:17]),
	.o_ce_pix(rt_ce),
	.o_hblank(rt_hb),
	.o_hsync(rt_hs),
	.o_vblank(rt_vb),
	.o_vsync(rt_vs),
	.o_rgb(rt_rgb),

	.DDRAM_CLK(),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(),
	.DDRAM_ADDR(rt_ddr_addr),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(rt_ddr_rd),
	.DDRAM_DIN(rt_ddr_din),
	.DDRAM_BE(),
	.DDRAM_WE(rt_ddr_we),
	.wf_overflow()
);

// DDR3 bus: the ROM loader owns it while replaying (the retimer is stopped for that
// whole time), the retimer otherwise. Both only use single-beat bursts with all byte
// enables.
assign DDRAM_CLK      = clk_sys;
assign DDRAM_BURSTCNT = 8'd1;
assign DDRAM_BE       = 8'hFF;
assign DDRAM_ADDR     = ld_acq ? ld_ddr_addr : rt_ddr_addr;
assign DDRAM_RD       = ld_acq ? ld_ddr_read : rt_ddr_rd;
assign DDRAM_WE       = ld_acq ? 1'b0        : rt_ddr_we;
assign DDRAM_DIN      = rt_ddr_din;

wire crt_mode = ~status[12];

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = crt_mode ? rt_ce : ce_pix;

assign VGA_DE = crt_mode ? ~(rt_hb | rt_vb) : ~(HBlank | VBlank);
assign VGA_HS = crt_mode ? rt_hs : HSync;
assign VGA_VS = crt_mode ? rt_vs : VSync;

wire [23:0] vid_rgb = crt_mode ? rt_rgb : rgb;

assign VGA_R = vid_rgb[23:16];
assign VGA_G = vid_rgb[15:8];
assign VGA_B = vid_rgb[7:0];

endmodule
