// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 shimian5

// Permutes the controller's button bits 7:4 from each game's MRA order to the layout the board
// expects. Each game lists player controls, then coin, then start, leaving out unused buttons.
//   board layout: [4]=button 1 (Nitro/Jump/Place)  [5]=button 2 or Off-Road coin
//                 [6]=start or Gas                 [7]=coin or Off-Road Menu Enter
//   Off-Road / Indy Heat: Gas, Nitro, Menu Enter, Coin
//   Pig Out:              Jump, Throw, Coin, Start
//   Ataxx:                Place, Coin, Start
// Menu Enter also comes out separately: it acts as player 3's Nitro in the service menus.

module button_map
(
	input  [7:0] game_id,
	input  [7:0] joy,     // controller bits as mapped in the OSD
	output [7:0] board,   // joy with bits 7:4 reordered for the board
	output       menu     // Menu Enter pressed (0 for games without one)
);

localparam [7:0] GAME_PIGOUT   = 8'd2;
localparam [7:0] GAME_ATAXX    = 8'd3;
localparam [7:0] GAME_INDYHEAT = 8'd4;

reg [8:0] m;
always @(*) begin
	case (game_id)
		GAME_PIGOUT:   m = {1'b0,   joy[6], joy[7], joy[5], joy[4], joy[3:0]};
		GAME_ATAXX:    m = {1'b0,   joy[5], joy[6], 1'b0,   joy[4], joy[3:0]};
		GAME_INDYHEAT: m = {joy[6], joy[7], joy[4], 1'b0,   joy[5], joy[3:0]};
		default:       m = {joy[6], joy[6], joy[4], joy[7], joy[5], joy[3:0]};
	endcase
end

assign board = m[7:0];
assign menu  = m[8];

endmodule
