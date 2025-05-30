// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
// Date: 13.09.2018
// Description: Write-through cache subsystem with hybrid mode support
// 
// Modified for hybrid mode implementation: Allows switching between
// set associative mode (faster, standard WT cache) and fully associative mode
// (better isolation with privilege-based accesses)

import ariane_pkg::*;
import wt_cache_pkg::*;
import wt_hybrid_cache_pkg::*;
import riscv::*;

module wt_hybche #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg     = '0,
  parameter int unsigned                DREQ_DEPTH  = 2,
  parameter logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]SET_MASK    = '1,
  parameter logic                       HYBRID_MODE = 1'b1, // Enable hybrid mode
  parameter wt_hybrid_cache_pkg::force_mode_e FORCE_MODE   = wt_hybrid_cache_pkg::FORCE_MODE_DYNAMIC,
  parameter wt_hybrid_cache_pkg::replacement_policy_e REPL_POLICY = wt_hybrid_cache_pkg::REPL_POLICY_RETAIN,
  parameter wt_hybrid_cache_pkg::replacement_algo_e   REPL_ALGO   = wt_hybrid_cache_pkg::REPL_ALGO_RR,
  // Seed value for the hash function when operating in fully associative mode
  parameter logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] HASH_SEED = wt_hybrid_cache_pkg::DEFAULT_HASH_SEED[CVA6Cfg.DCACHE_TAG_WIDTH-1:0],
  parameter type axi_req_t = logic,
  parameter type axi_resp_t = logic,
  parameter type dcache_req_i_t = logic,
  parameter type dcache_req_o_t = logic
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,

  input  logic                           flush_i,      // flush the dcache, flush and kill have to be asserted together
  output logic                           flush_ack_o,  // acknowledge successful flush
  
  // Privilege mode input
  input  logic [1:0]                     priv_lvl_i,   // From CSR, used for hybrid mode (2'b00=U, 2'b01=S, 2'b11=M)
  
  // From PTW
  input  logic                           enable_translation_i, // CSR from PTW, determines if MMU is enabled
  
  // SRAM interface
  output logic                           sram_en_o,
  output logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]    sram_we_o,
  output logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0]  sram_idx_o,
  output logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0]    sram_tag_o,
  output logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0]   sram_data_o,
  input  logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0]   sram_data_i,
  
  // Cache management
  input  logic                           cache_en_i,   // from CSR
  input  logic                           cache_flush_i,// high until acknowledged
  output logic                           cache_flush_ack_o,
  
  // Core request ports
  input  dcache_req_i_t [CVA6Cfg.NrLoadPipeRegs+CVA6Cfg.NrStorePipeRegs-1:0] dcache_req_ports_i,
  output dcache_req_o_t [CVA6Cfg.NrLoadPipeRegs+CVA6Cfg.NrStorePipeRegs-1:0] dcache_req_ports_o,
  
  // Cache status outputs
  output logic                           dcache_miss_o,
  output logic                           wbuffer_empty_o,
  output logic                           wbuffer_not_ni_o,
  output logic [CVA6Cfg.NrLoadPipeRegs+CVA6Cfg.NrStorePipeRegs-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0] miss_vld_bits_o,
  
  // AMO interface (basic implementation)
  output amo_resp_t                      dcache_amo_resp_o,
  
  // AXI port
  output axi_req_t  axi_req_o,
  input  axi_resp_t axi_resp_i
);

  // Determine cache operation mode
  logic use_set_assoc_mode;
  
  // If hybrid mode is enabled, determine operational mode based on privilege level
  // Use set associative mode for machine mode (highest performance)
  // Use fully associative mode for supervisor/user mode (better isolation)
  // This can be overridden by FORCE_MODE parameter
  always_comb begin
    if (HYBRID_MODE) begin
      case(FORCE_MODE)
        wt_hybrid_cache_pkg::FORCE_MODE_DYNAMIC: begin
          // Dynamic mode - switch based on privilege level
          // M-mode (3) uses fully associative, S-mode (1) and U-mode (0) use set associative
          use_set_assoc_mode = (priv_lvl_i != 2'b11); // NOT Machine mode
        end
        wt_hybrid_cache_pkg::FORCE_MODE_SET_ASS: begin
          // Force set associative mode (like standard WT cache)
          use_set_assoc_mode = 1'b1;
        end
        wt_hybrid_cache_pkg::FORCE_MODE_FULL_ASS: begin
          // Force fully associative mode
          use_set_assoc_mode = 1'b0;
        end
        default: begin
          // Default to set associative for undefined cases
          use_set_assoc_mode = 1'b1;
        end
      endcase
    end else begin
      // When hybrid mode is disabled, always use set associative mode
      use_set_assoc_mode = 1'b1;
    end
  end

  // Track privilege mode changes to trigger flush if needed
  logic prev_set_assoc_mode_q;
  logic mode_change;
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      prev_set_assoc_mode_q <= 1'b1; // Default to set associative after reset
    end else begin
      prev_set_assoc_mode_q <= use_set_assoc_mode;
    end
  end
  
  // Detect mode change
  assign mode_change = (prev_set_assoc_mode_q != use_set_assoc_mode);
  
  // Flush control signal - flush on explicit request or on mode change when REPL_POLICY_FLUSH is used
  logic flush_cache;
  assign flush_cache = flush_i || (mode_change && (REPL_POLICY == wt_hybrid_cache_pkg::REPL_POLICY_FLUSH));

  // Internal cache components
  wt_hybche_mem #(
    .CVA6Cfg       ( CVA6Cfg            ),
    .SET_MASK      ( SET_MASK           ),
    .HYBRID_MODE   ( HYBRID_MODE        ),
    .FORCE_MODE    ( FORCE_MODE         ),
    .REPL_POLICY   ( REPL_POLICY        ),
    .REPL_ALGO     ( REPL_ALGO          ),
    .HASH_SEED     ( HASH_SEED          ),
    .NumPorts      ( NumPorts           ),
    .wbuffer_t     ( wbuffer_t          )
  ) i_wt_hybche_mem (
    .clk_i,
    .rst_ni,
    .use_set_assoc_mode_i ( use_set_assoc_mode ),
    .flush_i              ( flush_cache        ),
    .flush_ack_o          ( mem_flush_ack ),
    .enable_translation_i,
    .sram_en_o,
    .sram_we_o,
    .sram_idx_o,
    .sram_tag_o,
    .sram_data_o,
    .sram_data_i,
    .rd_tag_i             ( rd_tag ),
    .rd_idx_i             ( rd_idx ),
    .rd_off_i             ( rd_off ),
    .rd_req_i             ( rd_req ),
    .rd_tag_only_i        ( rd_tag_only ),
    .rd_prio_i            ( rd_prio ),
    .rd_ack_o             ( rd_ack ),
    .rd_vld_bits_o        ( rd_vld_bits ),
    .rd_hit_oh_o          ( rd_hit_oh ),
    .rd_data_o            ( rd_data ),
    .rd_user_o            ( rd_user ),
    .wr_cl_vld_i          ( miss_cl_vld ),
    .wr_cl_nc_i           ( miss_cl_nc ),
    .wr_cl_we_i           ( miss_cl_we ),
    .wr_cl_tag_i          ( miss_cl_tag ),
    .wr_cl_idx_i          ( miss_cl_idx ),
    .wr_cl_off_i          ( miss_cl_off ),
    .wr_cl_data_i         ( miss_cl_data ),
    .wr_cl_user_i         ( miss_cl_user ),
    .wr_cl_data_be_i      ( miss_cl_data_be ),
    .wr_vld_bits_i        ( miss_cl_vld_bits ),
    .wr_req_i             ( wr_req ),
    .wr_ack_o             ( wr_ack ),
    .wr_idx_i             ( wr_idx ),
    .wr_off_i             ( wr_off ),
    .wr_data_i            ( wr_data ),
    .wr_user_i            ( wr_user ),
    .wr_data_be_i         ( wr_data_be ),
    .wbuffer_data_i       ( wbuffer_data )
  );
  
  // Additional internal signals needed for component interconnection
  localparam int unsigned NumPorts = CVA6Cfg.NrLoadPipeRegs + CVA6Cfg.NrStorePipeRegs;
  
  // Miss interface signals
  logic [NumPorts-1:0] miss_req, miss_ack, miss_we;
  logic [NumPorts-1:0] miss_nc;
  logic [NumPorts-1:0][riscv::PLEN-1:0] miss_paddr;
  logic [NumPorts-1:0][CVA6Cfg.XLEN-1:0] miss_wdata;
  logic [NumPorts-1:0][CVA6Cfg.DCACHE_USER_WIDTH-1:0] miss_wuser;
  logic [NumPorts-1:0][2:0] miss_size;
  logic [NumPorts-1:0][CVA6Cfg.MEM_TID_WIDTH-1:0] miss_id;
  logic [NumPorts-1:0] miss_replay, miss_rtrn_vld;
  logic [NumPorts-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0] miss_vld_bits;
  
  // Read interface signals for memory access
  logic [NumPorts-1:0][CVA6Cfg.DCACHE_TAG_WIDTH-1:0] rd_tag;
  logic [NumPorts-1:0][CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] rd_idx;
  logic [NumPorts-1:0][CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0] rd_off;
  logic [NumPorts-1:0] rd_req, rd_tag_only, rd_ack;
  logic [NumPorts-1:0] rd_prio;
  
  // Memory interface signals
  logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0] rd_data;
  logic [CVA6Cfg.DCACHE_USER_LINE_WIDTH-1:0] rd_user;
  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] rd_vld_bits, rd_hit_oh;
  
  // Write buffer interface signals  
  logic wbuf_valid, wbuf_ready;
  logic [riscv::PLEN-1:0] wbuf_addr;
  logic [CVA6Cfg.XLEN-1:0] wbuf_wdata;
  logic [CVA6Cfg.XLEN/8-1:0] wbuf_be;
  logic wr_cl_vld;
  
  // Write buffer outputs for interface compatibility
  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] wr_req;
  logic wr_ack;
  logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] wr_idx;
  logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0] wr_off;
  logic [CVA6Cfg.XLEN-1:0] wr_data;
  logic [CVA6Cfg.XLEN/8-1:0] wr_data_be;
  logic [CVA6Cfg.DCACHE_USER_WIDTH-1:0] wr_user;
  
  // Write buffer data for forwarding and transaction tracking
  typedef struct packed {
    logic [CVA6Cfg.DCACHE_TAG_WIDTH+(CVA6Cfg.DCACHE_INDEX_WIDTH-CVA6Cfg.XLEN_ALIGN_BYTES)-1:0] wtag;
    logic [CVA6Cfg.XLEN-1:0] data;
    logic [CVA6Cfg.DCACHE_USER_WIDTH-1:0] user;
    logic [(CVA6Cfg.XLEN/8)-1:0] dirty;
    logic [(CVA6Cfg.XLEN/8)-1:0] valid;
    logic [(CVA6Cfg.XLEN/8)-1:0] txblock;
    logic checked;
    logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] hit_oh;
  } wbuffer_t;
  
  wbuffer_t [CVA6Cfg.WtDcacheWbufDepth-1:0] wbuffer_data;
  logic [CVA6Cfg.DCACHE_MAX_TX-1:0][CVA6Cfg.PLEN-1:0] tx_paddr;
  logic [CVA6Cfg.DCACHE_MAX_TX-1:0] tx_vld;
  
  // Internal control signals
  logic mem_ready, mem_valid;
  logic mode_flush_req, mode_flush_ack;
  logic wbuffer_empty;
  logic mem_flush_ack;
  logic ctrl_flush_ack;
  logic miss_busy;
  
  // AXI arbitration signals
  axi_req_t axi_req_miss, axi_req_wbuf;
  
  // Cache controller
  wt_hybche_ctrl #(
    .CVA6Cfg       ( CVA6Cfg            ),
    .SET_MASK      ( SET_MASK           ),
    .HYBRID_MODE   ( HYBRID_MODE        ),
    .FORCE_MODE    ( FORCE_MODE         ),
    .REPL_POLICY   ( REPL_POLICY        )
  ) i_wt_hybche_ctrl (
    .clk_i,
    .rst_ni,
    .flush_i              ( flush_cache        ),
    .flush_ack_o          ( ctrl_flush_ack     ),
    .cache_en_i           ( cache_en_i         ),
    .cache_flush_i        ( cache_flush_i      ),
    .cache_flush_ack_o    ( cache_flush_ack_o  ),
    .use_set_assoc_mode_i ( use_set_assoc_mode ),
    .mode_change_i        ( mode_change        ),
    .miss_req_i           ( |miss_req          ),
    .miss_ack_o           ( /* handled by miss unit */ ),
    .miss_dirty_i         ( 1'b0               ), // Write-through, no dirty data
    .miss_addr_i          ( miss_paddr[0]      ), // Use first port address for now
    .miss_busy_o          ( miss_busy          ),
    .mode_flush_req_o     ( mode_flush_req     ),
    .mode_flush_ack_i     ( mode_flush_ack     ),
    .sram_en_o            ( /* connected through mem */ ),
    .sram_we_o            ( /* connected through mem */ ),
    .mem_ready_i          ( mem_ready          ),
    .mem_valid_o          ( mem_valid          ),
    .trans_cnt_o          ( /* unused for now */ ),
    .set_hit_cnt_o        ( /* unused for now */ ),
    .full_hit_cnt_o       ( /* unused for now */ )
  );
  
  // Miss handling unit - handles cache line refills from memory
  logic miss_unit_busy;
  logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] miss_cl_tag;
  logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] miss_cl_idx;
  logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0] miss_cl_off;
  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] miss_cl_we;
  logic miss_cl_vld, miss_cl_nc;
  logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0] miss_cl_data;
  logic [CVA6Cfg.DCACHE_USER_LINE_WIDTH-1:0] miss_cl_user;
  logic [CVA6Cfg.DCACHE_LINE_WIDTH/8-1:0] miss_cl_data_be;
  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] miss_cl_vld_bits;
  
  wt_hybche_missunit #(
    .CVA6Cfg       ( CVA6Cfg            ),
    .SET_MASK      ( SET_MASK           ),
    .HYBRID_MODE   ( HYBRID_MODE        ),
    .FORCE_MODE    ( FORCE_MODE         ),
    .REPL_POLICY   ( REPL_POLICY        ),
    .axi_req_t     ( axi_req_t          ),
    .axi_resp_t    ( axi_resp_t         )
  ) i_wt_hybche_missunit (
    .clk_i,
    .rst_ni,
    .use_set_assoc_mode_i ( use_set_assoc_mode ),
    .mode_change_i        ( mode_change        ),
    .cache_en_i           ( cache_en_i         ),
    .flush_i              ( flush_cache        ),
    .flush_ack_o          ( /* handled by ctrl */ ),
    // Arbitrate between multiple miss requests from ports
    .miss_req_i           ( |miss_req          ),
    .miss_ack_o           ( miss_ack[0]        ), // Connect to first port for now
    .miss_nc_i            ( miss_nc[0]         ), // Connect to first port for now
    .miss_addr_i          ( miss_paddr[0]      ), // Connect to first port for now
    .miss_busy_o          ( miss_unit_busy     ),
    .mode_flush_req_i     ( mode_flush_req     ),
    .mode_flush_ack_o     ( mode_flush_ack     ),
    .axi_req_o            ( axi_req_miss       ),
    .axi_resp_i           ( axi_resp_i         ),
    // Memory interface for cache memory access (internal signals)
    .mem_req_o            ( /* unused */       ),
    .mem_addr_o           ( /* unused */       ),
    .mem_we_o             ( /* unused */       ),
    .mem_way_o            ( /* unused */       ),
    .mem_busy_o           ( /* unused */       ),
    // Cache line memory interface
    .wr_cl_vld_o          ( miss_cl_vld        ),
    .wr_cl_nc_o           ( miss_cl_nc         ),
    .wr_cl_we_o           ( miss_cl_we         ),
    .wr_cl_tag_o          ( miss_cl_tag        ),
    .wr_cl_idx_o          ( miss_cl_idx        ),
    .wr_cl_off_o          ( miss_cl_off        ),
    .wr_cl_data_o         ( miss_cl_data       ),
    .wr_cl_user_o         ( miss_cl_user       ),
    .wr_cl_data_be_o      ( miss_cl_data_be    ),
    .wr_vld_bits_o        ( miss_cl_vld_bits   )
  );
  
  // Miss acknowledgment distribution and return signaling
  // The miss unit handles one request at a time, so broadcast acknowledgments
  for (genvar k = 0; k < NumPorts; k++) begin : gen_miss_ack
    assign miss_ack[k] = miss_ack[0]; // Broadcast acknowledgment to all ports
    assign miss_replay[k] = 1'b0;     // No replay logic needed for write-through
    assign miss_rtrn_vld[k] = 1'b0;   // Return valid handled by memory interface
  end
  
  // Memory interface connections to hybrid cache memory
  logic mem_gnt;
  logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] mem_rd_tag;
  logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] mem_rd_idx; 
  logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0] mem_rd_off;
  logic mem_rd_req, mem_rd_tag_only;
  logic [NumPorts-1:0] mem_rd_prio;
  
  // Memory arbitration - route signals to memory module
  assign mem_rd_prio = rd_prio;
  assign mem_rd_tag = rd_tag[0];  // Simple arbitration for now
  assign mem_rd_idx = rd_idx[0];
  assign mem_rd_off = rd_off[0];
  assign mem_rd_req = |rd_req;
  assign mem_rd_tag_only = rd_tag_only[0];

  assign mem_gnt = 1'b1;
  
  // Distribute read responses to all ports that requested
  for (genvar k = 0; k < NumPorts; k++) begin : gen_rd_ack
    assign rd_ack[k] = rd_req[k] ? mem_gnt : 1'b0;
  end
  
  // Connect hybrid cache memory module to read interface and memory interfaces
  // (The i_wt_hybche_mem module is instantiated above with these connections)
  
  // Read responses are provided by the memory module

  // Combine flush acknowledge from the controller and memory module
  assign flush_ack_o = ctrl_flush_ack | mem_flush_ack;
  
  ///////////////////////////////////////////////////////
  // Core interface implementation
  ///////////////////////////////////////////////////////
  
  // Read port controllers (NumPorts-1 read ports, 1 write port)
  for (genvar k = 0; k < NumPorts - 1; k++) begin : gen_rd_ports
    // Set high priority for important ports (MMU, normal reads, accelerator)
    if ((k == 0 && (CVA6Cfg.MmuPresent || CVA6Cfg.RVZCMT)) || (k == 1) || (k == 2 && CVA6Cfg.EnableAccelerator)) begin
      assign rd_prio[k] = 1'b1;
      
      // Use standard wt_dcache_ctrl for now - can be specialized later for hybrid features
      wt_dcache_ctrl #(
          .CVA6Cfg(CVA6Cfg),
          .DCACHE_CL_IDX_WIDTH($clog2(CVA6Cfg.DCACHE_NUM_WORDS)),
          .dcache_req_i_t(dcache_req_i_t),
          .dcache_req_o_t(dcache_req_o_t),
          .RdTxId(0)
      ) i_rd_ctrl (
          .clk_i          (clk_i),
          .rst_ni         (rst_ni),
          .cache_en_i     (cache_en_i),
          // Core interface
          .req_port_i     (dcache_req_ports_i[k]),
          .req_port_o     (dcache_req_ports_o[k]),
          // Miss interface
          .miss_req_o     (miss_req[k]),
          .miss_ack_i     (miss_ack[k]),
          .miss_we_o      (miss_we[k]),
          .miss_wdata_o   (miss_wdata[k]),
          .miss_wuser_o   (miss_wuser[k]),
          .miss_vld_bits_o(miss_vld_bits[k]),
          .miss_paddr_o   (miss_paddr[k]),
          .miss_nc_o      (miss_nc[k]),
          .miss_size_o    (miss_size[k]),
          .miss_id_o      (miss_id[k]),
          .miss_replay_i  (miss_replay[k]),
          .miss_rtrn_vld_i(miss_rtrn_vld[k]),
          // Write collision detection
          .wr_cl_vld_i    (wr_cl_vld),
          // Memory interface
          .rd_tag_o       (rd_tag[k]),
          .rd_idx_o       (rd_idx[k]),
          .rd_off_o       (rd_off[k]),
          .rd_req_o       (rd_req[k]),
          .rd_tag_only_o  (rd_tag_only[k]),
          .rd_ack_i       (rd_ack[k]),
          .rd_data_i      (rd_data),
          .rd_user_i      (rd_user),
          .rd_vld_bits_i  (rd_vld_bits),
          .rd_hit_oh_i    (rd_hit_oh)
      );
    end else begin
      assign rd_prio[k] = 1'b0;
      assign dcache_req_ports_o[k] = '0;
      assign miss_req[k] = 1'b0;
      assign miss_we[k] = 1'b0;
      assign miss_wdata[k] = '0;
      assign miss_wuser[k] = '0;
      assign miss_vld_bits[k] = '0;
      assign miss_paddr[k] = '0;
      assign miss_nc[k] = 1'b0;
      assign miss_size[k] = '0;
      assign miss_id[k] = '0;
      assign rd_tag[k] = '0;
      assign rd_idx[k] = '0;
      assign rd_off[k] = '0;
      assign rd_req[k] = 1'b0;
      assign rd_tag_only[k] = 1'b0;
    end
  end
  
  // Write port controller (last port is write port)
  if (NumPorts > 0) begin : gen_wr_port
    wt_dcache_wbuffer #(
        .CVA6Cfg(CVA6Cfg),
        .DEPTH(CVA6Cfg.WtDcacheWbufDepth),
        .RdTxId(1)
    ) i_wt_dcache_wbuffer (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .cache_en_i     (cache_en_i),
        .empty_o        (wbuffer_empty),
        .not_ni_o       (/* unused for now */),
        // Core interface (write port)
        .req_port_i     (dcache_req_ports_i[NumPorts-1]),
        .req_port_o     (dcache_req_ports_o[NumPorts-1]),
        // Miss interface (for AMOs)
        .miss_req_o     (miss_req[NumPorts-1]),
        .miss_ack_i     (miss_ack[NumPorts-1]),
        .miss_we_o      (miss_we[NumPorts-1]),
        .miss_wdata_o   (miss_wdata[NumPorts-1]),
        .miss_wuser_o   (miss_wuser[NumPorts-1]),
        .miss_vld_bits_o(miss_vld_bits[NumPorts-1]),
        .miss_paddr_o   (miss_paddr[NumPorts-1]),
        .miss_nc_o      (miss_nc[NumPorts-1]),
        .miss_size_o    (miss_size[NumPorts-1]),
        .miss_id_o      (miss_id[NumPorts-1]),
        .miss_rtrn_vld_i(miss_rtrn_vld[NumPorts-1]),
        .miss_rtrn_id_i (/* unused for now */),
        // Memory interface
        .rd_tag_o       (rd_tag[NumPorts-1]),
        .rd_idx_o       (rd_idx[NumPorts-1]),
        .rd_off_o       (rd_off[NumPorts-1]),
        .rd_req_o       (rd_req[NumPorts-1]),
        .rd_tag_only_o  (rd_tag_only[NumPorts-1]),
        .rd_ack_i       (rd_ack[NumPorts-1]),
        .rd_data_i      (rd_data),
        .rd_vld_bits_i  (rd_vld_bits),
        .rd_hit_oh_i    (rd_hit_oh),
        // Cache line write interface
        .wr_cl_vld_i    (wr_cl_vld),
        .wr_cl_idx_i    (miss_cl_idx), // From miss unit
        // Word write interface
        .wr_req_o       (wr_req),
        .wr_ack_i       (wr_ack),
        .wr_idx_o       (wr_idx),
        .wr_off_o       (wr_off),
        .wr_data_o      (wr_data),
        .wr_data_be_o   (wr_data_be),
        .wr_user_o      (wr_user),
        // Write buffer forwarding
        .wbuffer_data_o (wbuffer_data),
        .tx_paddr_o     (tx_paddr),
        .tx_vld_o       (tx_vld)
    );
  end
  
  ///////////////////////////////////////////////////////
  // AXI arbitration - simple priority scheme
  ///////////////////////////////////////////////////////
  
  // Write acknowledgment for memory interface comes from the memory
  assign wbuf_ready = 1'b1; // Always ready for now
  assign axi_req_wbuf = '0; // No direct AXI interface from write buffer for now
  
  // Miss unit has higher priority than write buffer
  assign axi_req_o = miss_unit_busy ? axi_req_miss : axi_req_wbuf;
  
  // Connect miss busy signal for internal logic
  assign miss_busy = miss_unit_busy;
  
  ///////////////////////////////////////////////////////
  // Additional outputs required by subsystem interface  
  ///////////////////////////////////////////////////////
  
  // Miss indication - OR of all port miss requests or miss unit busy
  assign dcache_miss_o = |miss_req || miss_unit_busy;
  
  // Write buffer status
  assign wbuffer_empty_o = wbuffer_empty;
  assign wbuffer_not_ni_o = !wbuffer_empty;
  
  // Miss valid bits for performance counters
  assign miss_vld_bits_o = miss_vld_bits;
  
  // AMO interface - connect to write port's AMO handling
  // (This is simplified - full AMO support would need additional logic)
  assign dcache_amo_resp_o = '0;  // TODO: implement proper AMO response
  
endmodule
