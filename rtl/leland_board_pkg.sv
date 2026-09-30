// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 shimian5

//============================================================================
//  Leland-family board package: board/input enums, the 16-byte MRA header layout, the
//  canonical SDRAM region layout (sized to the family maxima) and the per-game
//  configuration table (Super Off-Road, Track-Pak, Pig Out).
//============================================================================

package leland_board_pkg;

	//--------------------------------------------------------------
	// board_class: selects structural muxes (sound board, video pipeline, EEPROM model,
	// slave bank scheme); matches header byte 2.
	//--------------------------------------------------------------
	typedef enum logic [7:0] {
		GEN1          = 8'd0,
		GEN2_REDLINE  = 8'd1,
		GEN2_QB       = 8'd2,
		GEN3_LELANDI  = 8'd3,
		GEN4_ATAXX    = 8'd4,
		GEN4_WSF      = 8'd5
	} board_class_e;

	//--------------------------------------------------------------
	// input_scheme: selects which control sources feed which game
	// ports (plan section 7). Header byte 4.
	//--------------------------------------------------------------
	typedef enum logic [7:0] {
		WHEELS3_PEDALS3 = 8'd0,
		JOY4_DIGITAL    = 8'd1,
		JOY3_DIGITAL    = 8'd2,
		TRACKBALL       = 8'd3,
		ADSTICK         = 8'd4,
		DIAL2_PEDAL2    = 8'd5,
		WHEELS3_MUXED   = 8'd6
	} input_scheme_e;

	//--------------------------------------------------------------
	// 16-byte MRA header, prepended to the index=0 download stream ahead of all ROM
	//--------------------------------------------------------------
	localparam int HDR_LEN = 16;

	localparam int HDR_OFF_MAGIC        = 0;
	localparam int HDR_OFF_VERSION      = 1;
	localparam int HDR_OFF_BOARD_CLASS  = 2;
	localparam int HDR_OFF_GAME_ID      = 3;
	localparam int HDR_OFF_INPUT_SCHEME = 4;
	localparam int HDR_OFF_FLAGS        = 5;
	// bytes 6-15: reserved (0x00)

	localparam logic [7:0] HDR_MAGIC   = 8'h4C; // 'L'
	localparam logic [7:0] HDR_VERSION = 8'h01;

	// flags byte bit assignments
	localparam int FLAG_DUAL_IO_WINDOW = 0; // dual I/O window map (offroad)
	localparam int FLAG_EEPROM_93C56   = 1; // 0 = 93C46, 1 = 93C56
	localparam int FLAG_XROM_PRESENT   = 2;
	localparam int FLAG_EXTDAC_PRESENT = 3;
	localparam int FLAG_IN4_PORT       = 4; // fixed IN4 @ raw 0x7F (pigout 4th-player port)

	//--------------------------------------------------------------
	// Canonical SDRAM layout (post-header byte addresses), sized to the whole Leland
	// family's maxima; a game pads the unused tail of its region with zero fill in the MRA.
	//--------------------------------------------------------------
	localparam logic [26:0] ADDR_MASTER_BASE = 27'h000000; // master ROM
	localparam logic [26:0] MASTER_MAX       = 27'h100000; // 1 MB reserved

	localparam logic [26:0] ADDR_SLAVE_BASE  = 27'h100000; // slave ROM
	localparam logic [26:0] SLAVE_MAX        = 27'h200000; // 2 MB reserved

	localparam logic [26:0] ADDR_SOUND_BASE  = 27'h300000; // 80186 sound ROM
	localparam logic [26:0] SOUND_MAX        = 27'h100000; // 1 MB reserved

	localparam logic [26:0] ADDR_GFX_BASE    = 27'h400000; // bg_gfx
	localparam logic [26:0] GFX_MAX          = 27'h200000; // 2 MB reserved

	// Derived copy of bg_gfx planes 0+1 interleaved into 16-bit words (word i =
	// {plane1[i], plane0[i]}), built once at boot by the repack FSM in leland_board.sv from
	// the untouched ADDR_GFX_BASE content. It sits after the 3 raw planes (0x18000 bytes)
	// inside GFX_BASE's reservation.
	localparam logic [26:0] ADDR_GFXW_BASE   = ADDR_GFX_BASE + 27'h018000;

	// Derived copy holding all 3 planes of a tile row in one 4-byte, burst-friendly entry:
	// word0 = {plane1[i], plane0[i]}, word1 = {8'h00, plane2[i]}, with the same index
	// i = tile_code*8 + riy as ADDR_GFXW_BASE. leland_video reads it with one 2-word burst.
	// Built by the same repack FSM; 4 * 0x8000 = 0x20000 bytes, right after
	// ADDR_GFXW_BASE's region.
	localparam logic [26:0] ADDR_GFXROW_BASE = ADDR_GFXW_BASE + 27'h010000;

	localparam logic [26:0] ADDR_PROM_BASE   = 27'h600000; // bg_prom (gen1-3)
	localparam logic [26:0] PROM_MAX         = 27'h040000; // 256 KB reserved

	localparam logic [26:0] ADDR_XROM_BASE   = 27'h640000; // xrom (gen4 only)
	localparam logic [26:0] XROM_MAX         = 27'h040000; // 256 KB reserved

	localparam logic [26:0] ADDR_EXTDAC_BASE = 27'h680000; // ext DAC samples (GEN4_WSF)
	localparam logic [26:0] EXTDAC_MAX       = 27'h080000; // 512 KB reserved

	localparam logic [26:0] ADDR_EEPROM_BASE = 27'h700000; // EEPROM default image
	localparam logic [26:0] EEPROM_MAX       = 27'h001000; // 4 KB reserved

	//--------------------------------------------------------------
	// Region -> bank mapping for the multi-bank open-row controller. Each gameplay read
	// client is pinned to one physical SDRAM bank so their open rows never evict each
	// other:
	//   bank 0  master Z80 ROM   (ADDR_MASTER_BASE .. ADDR_SLAVE_BASE)
	//   bank 1  slave  Z80 ROM   (ADDR_SLAVE_BASE  .. ADDR_SOUND_BASE)
	//   bank 2  80186 sound ROM  (ADDR_SOUND_BASE  .. ADDR_GFX_BASE)
	//   bank 3  gfx / prom       (ADDR_GFX_BASE    .. )
	// Both functions take a 27-bit byte address and return the bank index or the
	// region-relative offset inside that bank; the write channel uses them to derive
	// bank_sel and the relative address. Every region fits in one 8 MB bank (23-bit
	// offset).
	//--------------------------------------------------------------
	function automatic [1:0] sdram_addr_to_bank(input logic [26:0] addr);
		if      (addr < ADDR_SLAVE_BASE)  sdram_addr_to_bank = 2'd0;
		else if (addr < ADDR_SOUND_BASE)  sdram_addr_to_bank = 2'd1;
		else if (addr < ADDR_GFX_BASE)    sdram_addr_to_bank = 2'd2;
		else                              sdram_addr_to_bank = 2'd3;
	endfunction

	// Bank virtual base for each region (the offset subtracted to get the
	// region-relative byte address fed to sdram_banked's addr port).
	function automatic [22:0] sdram_bank_base(input logic [26:0] addr);
		if      (addr < ADDR_SLAVE_BASE)  sdram_bank_base = ADDR_MASTER_BASE[22:0]; // 0
		else if (addr < ADDR_SOUND_BASE)  sdram_bank_base = ADDR_SLAVE_BASE[22:0];
		else if (addr < ADDR_GFX_BASE)    sdram_bank_base = ADDR_SOUND_BASE[22:0];
		else                              sdram_bank_base = ADDR_GFX_BASE[22:0];
	endfunction

	//--------------------------------------------------------------
	// Per-game configuration table, indexed by game_id (header byte 3). All three games
	// share the same master/slave bank tables (MAME's offroad_bankswitch is shared); only
	// the I/O bases, input scheme and flags differ per row.
	//--------------------------------------------------------------
	typedef struct packed {
		board_class_e   board_class;
		input_scheme_e  input_scheme;
		logic [7:0]     flags;
		logic [7:0]     io_base;    // leland_master_input_r/output_w window base
		logic [7:0]     mvram_base; // leland_mvram_port_r/w window base
	} game_cfg_t;

	localparam int NUM_GAMES = 3;
	localparam int GAME_OFFROAD  = 0;
	localparam int GAME_OFFROADT = 1;
	localparam int GAME_PIGOUT   = 2;

	function automatic game_cfg_t game_cfg(input int game_id);
		game_cfg_t cfg;
		case (game_id)
			GAME_OFFROAD: cfg = '{
				board_class:  GEN3_LELANDI,
				input_scheme: WHEELS3_PEDALS3,
				flags:        (8'd1 << FLAG_DUAL_IO_WINDOW),
				io_base:      8'hC0, // + dual alias @ 0x80
				mvram_base:   8'h00  // + dual alias @ 0x40
			};
			GAME_OFFROADT: cfg = '{
				board_class:  GEN3_LELANDI,
				input_scheme: WHEELS3_PEDALS3,
				flags:        8'h00, // single window, no alias
				io_base:      8'h40,
				mvram_base:   8'h80
			};
			GAME_PIGOUT: cfg = '{
				board_class:  GEN3_LELANDI,
				input_scheme: JOY4_DIGITAL,
				flags:        (8'd1 << FLAG_IN4_PORT), // single window + fixed IN4@0x7F
				io_base:      8'h40,
				mvram_base:   8'h00
			};
			default: cfg = '{
				board_class:  GEN3_LELANDI,
				input_scheme: WHEELS3_PEDALS3,
				flags:        (8'd1 << FLAG_DUAL_IO_WINDOW),
				io_base:      8'hC0,
				mvram_base:   8'h00
			};
		endcase
		return cfg;
	endfunction

endpackage
