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
// Description: Memory arrays and tag comparison for hybrid cache implementation
//
// Modified for hybrid mode implementation

import ariane_pkg::*;
import wt_cache_pkg::*;
import wt_hybrid_cache_pkg::*;

module wt_hybche_mem #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg     = '0,
  parameter logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]SET_MASK    = '1,
  // DCACHE_SET_ASSOC is assumed to be a power of two
  parameter logic                       HYBRID_MODE = 1'b1, // Enable hybrid mode
  parameter wt_hybrid_cache_pkg::force_mode_e FORCE_MODE   = wt_hybrid_cache_pkg::FORCE_MODE_DYNAMIC,
  parameter wt_hybrid_cache_pkg::replacement_policy_e REPL_POLICY = wt_hybrid_cache_pkg::REPL_POLICY_RETAIN,
  parameter wt_hybrid_cache_pkg::replacement_algo_e   REPL_ALGO   = wt_hybrid_cache_pkg::REPL_ALGO_RR,
  // Seed for the hash function used in fully associative mode.  Different seeds
  // reduce deterministic collisions and can be overridden per instance.
  parameter logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] HASH_SEED = wt_hybrid_cache_pkg::DEFAULT_HASH_SEED[CVA6Cfg.DCACHE_TAG_WIDTH-1:0],
  // Number of memory ports and write buffer type (for compatibility with the
  // standard write-through cache memory implementation)
  parameter int unsigned                          NumPorts  = 1,
  parameter type                                  wbuffer_t = logic
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,

  input  logic                           flush_i,      // flush the dcache, flush and kill have to be asserted together
  //
  // Signal asserted for a single cycle when the internal flush operation
  // completes.  This mirrors the behaviour of the standard write-through
  // cache implementation and allows external logic to reliably wait for the
  // cache to be cleared.
  //
  output logic                           flush_ack_o,
  
  // Operational mode
  input  logic                           use_set_assoc_mode_i, // Set associative or fully associative mode
  
  // From PTW
  input  logic                           enable_translation_i, // CSR from PTW, determines if MMU is enabled
  
  // SRAM interface
  output logic                           sram_en_o,
  output logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]    sram_we_o,
  output logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0]  sram_idx_o,
  output logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0]    sram_tag_o,
  // Read/write data bus of the optional external SRAM interface.  During a
  // flush this bus carries the invalidation value, otherwise it forwards the
  // data returned by the memory arrays.
  output logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0]   sram_data_o,
  input  logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0]   sram_data_i,

  // Read ports
  input  logic [NumPorts-1:0][CVA6Cfg.DCACHE_TAG_WIDTH-1:0]       rd_tag_i,
  input  logic [NumPorts-1:0][DCACHE_CL_IDX_WIDTH-1:0]            rd_idx_i,
  input  logic [NumPorts-1:0][CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0]    rd_off_i,
  input  logic [NumPorts-1:0]                                     rd_req_i,
  input  logic [NumPorts-1:0]                                     rd_tag_only_i,
  input  logic [NumPorts-1:0]                                     rd_prio_i,
  output logic [NumPorts-1:0]                                    rd_ack_o,
  output logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]                     rd_vld_bits_o,
  output logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]                     rd_hit_oh_o,
  output logic [CVA6Cfg.XLEN-1:0]                                 rd_data_o,
  output logic [CVA6Cfg.DCACHE_USER_WIDTH-1:0]                    rd_user_o,

  // Cache line write port
  input  logic                                                    wr_cl_vld_i,
  input  logic                                                    wr_cl_nc_i,
  input  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]                     wr_cl_we_i,
  input  logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0]                     wr_cl_tag_i,
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]                          wr_cl_idx_i,
  input  logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0]                  wr_cl_off_i,
  input  logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0]                    wr_cl_data_i,
  input  logic [CVA6Cfg.DCACHE_USER_LINE_WIDTH-1:0]               wr_cl_user_i,
  input  logic [CVA6Cfg.DCACHE_LINE_WIDTH/8-1:0]                  wr_cl_data_be_i,
  input  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]                     wr_vld_bits_i,

  // Single word write port
  input  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]                     wr_req_i,
  output logic                                                    wr_ack_o,
  input  logic [DCACHE_CL_IDX_WIDTH-1:0]                          wr_idx_i,
  input  logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0]                  wr_off_i,
  input  logic [CVA6Cfg.XLEN-1:0]                                 wr_data_i,
  input  logic [CVA6Cfg.DCACHE_USER_WIDTH-1:0]                    wr_user_i,
  input  logic [(CVA6Cfg.XLEN/8)-1:0]                             wr_data_be_i,

  // Forwarded write buffer contents for hazard checking
  input  wbuffer_t [CVA6Cfg.WtDcacheWbufDepth-1:0]                wbuffer_data_i
);

  ///////////////////////////////////////////////////////
  // Cache storage organization based on operation mode //
  ///////////////////////////////////////////////////////

  // Internal state and signals
  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] way_valid;         // Valid bits per way
  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] way_hit;           // Hit per way
  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] repl_way;          // Way to replace
  logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] tag_rdata [CVA6Cfg.DCACHE_SET_ASSOC-1:0]; // Tag read data

  // Simple memory arrays for data, user bits and tags
  logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0]
       data_mem   [CVA6Cfg.DCACHE_NUM_WORDS-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0];
  logic [CVA6Cfg.DCACHE_USER_LINE_WIDTH-1:0]
       user_mem   [CVA6Cfg.DCACHE_NUM_WORDS-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0];
  logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0]
       tag_mem    [CVA6Cfg.DCACHE_NUM_WORDS-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0];
  logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0]
       valid_mem  [CVA6Cfg.DCACHE_NUM_WORDS-1:0];
  
  // Flush state
  localparam int unsigned DCACHE_CL_IDX_WIDTH = $clog2(CVA6Cfg.DCACHE_NUM_WORDS);
  logic flushing_q, flushing_d;
  logic [DCACHE_CL_IDX_WIDTH-1:0] flush_cnt_q, flush_cnt_d;
  logic [DCACHE_CL_IDX_WIDTH-1:0] flush_limit;
  logic flush_ack_d, flush_ack_q;
  logic flush_done;
  
  // Operation mode specific signals
  logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] set_assoc_index; // Index for set associative mode
  logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] full_assoc_index; // Index for fully associative mode
  logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] set_assoc_tag;    // Tag for set associative mode
  logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] full_assoc_tag;   // Tag for fully associative mode (includes index bits)

  // Derive tag and index from the first read port.  This simplified
  // implementation assumes all ports access the same set at a time.
  always_comb begin
    set_assoc_index = rd_idx_i[0];
    full_assoc_index = ((rd_tag_i[0] ^ HASH_SEED ^ (rd_tag_i[0] >> $clog2(CVA6Cfg.DCACHE_SET_ASSOC))) % DCACHE_FA_SET_COUNT)
                       + DCACHE_FA_BASE_SET;
    set_assoc_tag = rd_tag_i[0];
    full_assoc_tag = {rd_idx_i[0], rd_tag_i[0]};
  end
  
  // Mode selection muxes
  logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] cache_index;
  logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] cache_tag;

  // Read currently addressed set from memory arrays
  always_comb begin
    for (int way = 0; way < CVA6Cfg.DCACHE_SET_ASSOC; way++) begin
      tag_rdata[way] = tag_mem[cache_index][way];
      way_valid[way] = valid_mem[cache_index][way];
    end
  end
  
  // Flattened signals for memory operations
  logic [CVA6Cfg.DCACHE_TAG_WIDTH*CVA6Cfg.DCACHE_SET_ASSOC-1:0] tags_flattened;

  // Round-robin replacement pointer used when all ways are valid.
  logic [$clog2(CVA6Cfg.DCACHE_SET_ASSOC)-1:0] rr_ptr_d, rr_ptr_q;
  // Simple LFSR for pseudo-random replacement if requested.
  logic [$clog2(CVA6Cfg.DCACHE_SET_ASSOC)-1:0] lfsr_d, lfsr_q;
  // Tree-based pseudo-LRU state when REPL_ALGO_PLRU is selected.
  logic [CVA6Cfg.DCACHE_SET_ASSOC-2:0]        plru_tree_d, plru_tree_q;

  // Hashed index for CAM-like lookup in fully associative mode
  logic [$clog2(CVA6Cfg.DCACHE_SET_ASSOC)-1:0] fa_hash_idx;
  
  // Fully associative lookup table - tracks which ways store which addresses in fully associative mode
  typedef struct packed {
    logic valid;
    logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] tag;  // Full address tag (includes index bits from set associative mode)
    logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] physical_set; // Where in memory the entry is actually stored
  } fa_lookup_entry_t;
  
  fa_lookup_entry_t fa_lookup_table [CVA6Cfg.DCACHE_SET_ASSOC-1:0];

  // Helper function: convert one-hot way to index
  function automatic logic [$clog2(CVA6Cfg.DCACHE_SET_ASSOC)-1:0] oh_to_idx(input logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] oh);
    for (int i = 0; i < CVA6Cfg.DCACHE_SET_ASSOC; i++) begin
      if (oh[i]) return i[$clog2(CVA6Cfg.DCACHE_SET_ASSOC)-1:0];
    end
    return '0;
  endfunction

  // Tree-based pseudo-LRU helper functions
  function automatic logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] plru_pick_oh(input logic [CVA6Cfg.DCACHE_SET_ASSOC-2:0] tree);
    logic [$clog2(CVA6Cfg.DCACHE_SET_ASSOC)-1:0] idx;
    int node = 0;
    for (int level = 0; level < $clog2(CVA6Cfg.DCACHE_SET_ASSOC); level++) begin
      idx[level] = tree[node];
      node = node*2 + 1 + tree[node];
    end
    return 1 << idx;
  endfunction

  function automatic logic [CVA6Cfg.DCACHE_SET_ASSOC-2:0] plru_access(input logic [CVA6Cfg.DCACHE_SET_ASSOC-2:0] tree,
                                                              input logic [$clog2(CVA6Cfg.DCACHE_SET_ASSOC)-1:0] way);
    int node = 0;
    for (int level = $clog2(CVA6Cfg.DCACHE_SET_ASSOC)-1; level >= 0; level--) begin
      logic dir = way[level];
      tree[node] = ~dir;
      node = node*2 + 1 + dir;
    end
    return tree;
  endfunction
  
  // Operation mode muxing
  always_comb begin
    if (use_set_assoc_mode_i) begin
      // Set associative mode - standard operation
      cache_index = set_assoc_index;
      cache_tag = set_assoc_tag;
    end else begin
      // Fully associative mode - use full tag comparison
      cache_index = full_assoc_index;
      cache_tag = full_assoc_tag;
    end
  end
  
  // Hit generation based on mode
  always_comb begin
    way_hit = '0;

    if (use_set_assoc_mode_i) begin
      // Set associative hit generation - compare tags from the selected index
      for (int i = 0; i < CVA6Cfg.DCACHE_SET_ASSOC; i++) begin
        way_hit[i] = way_valid[i] && (tag_rdata[i] == cache_tag);
      end
    end else begin
      // Compute hashed index to speed up lookup.  A seed value is included to
      // randomize the distribution of cache lines across the lookup table.
      fa_hash_idx = (cache_tag ^ HASH_SEED ^ (cache_tag >> $clog2(CVA6Cfg.DCACHE_SET_ASSOC))) & (CVA6Cfg.DCACHE_SET_ASSOC-1);

      if (fa_lookup_table[fa_hash_idx].valid && fa_lookup_table[fa_hash_idx].tag == cache_tag) begin
        way_hit[fa_hash_idx] = 1'b1;
      end else begin
        // Fallback to full search in case of hash collision
        for (int i = 0; i < CVA6Cfg.DCACHE_SET_ASSOC; i++) begin
          way_hit[i] = fa_lookup_table[i].valid && (fa_lookup_table[i].tag == cache_tag);
        end
      end
    end
  end

  // Generate read outputs
  always_comb begin
    rd_ack_o      = rd_req_i;
    rd_vld_bits_o = valid_mem[cache_index];
    rd_hit_oh_o   = way_hit;
    rd_data_o     = '0;
    rd_user_o     = '0;

    for (int way = 0; way < CVA6Cfg.DCACHE_SET_ASSOC; way++) begin
      if (way_hit[way]) begin
        rd_data_o = data_mem[cache_index][way];
        rd_user_o = user_mem[cache_index][way];
      end
    end
  end
  
  // Replacement policy implementation
  // For both modes we first try to find an invalid way. When none is
  // available we either use a round-robin pointer or a pseudo-random
  // victim based on the REPL_ALGO parameter.
  always_comb begin
    repl_way     = '0;
    rr_ptr_d     = rr_ptr_q;
    lfsr_d       = {lfsr_q[$bits(lfsr_q)-2:0],
                    lfsr_q[$bits(lfsr_q)-1] ^ lfsr_q[$bits(lfsr_q)-2]};
    plru_tree_d  = plru_tree_q;

    if (use_set_assoc_mode_i) begin
      // Search for invalid way first
      for (int i = 0; i < CVA6Cfg.DCACHE_SET_ASSOC; i++) begin
        if (!way_valid[i]) begin
          repl_way[i] = 1'b1;
          rr_ptr_d   = i + 1;
          break;
        end
      end

      if (repl_way == '0) begin
        // All ways valid - choose victim according to algorithm
        unique case (REPL_ALGO)
          wt_hybrid_cache_pkg::REPL_ALGO_RANDOM: repl_way[lfsr_q & (CVA6Cfg.DCACHE_SET_ASSOC-1)] = 1'b1;
          wt_hybrid_cache_pkg::REPL_ALGO_PLRU:   repl_way = plru_pick_oh(plru_tree_q);
          default:                               repl_way[rr_ptr_q] = 1'b1;
        endcase
        rr_ptr_d    = rr_ptr_q + 1;
      end
    end else begin
      // Fully associative mode
      for (int i = 0; i < CVA6Cfg.DCACHE_SET_ASSOC; i++) begin
        if (!fa_lookup_table[i].valid) begin
          repl_way[i] = 1'b1;
          rr_ptr_d   = i + 1;
          break;
        end
      end

      if (repl_way == '0) begin
        unique case (REPL_ALGO)
          wt_hybrid_cache_pkg::REPL_ALGO_RANDOM: repl_way[lfsr_q & (CVA6Cfg.DCACHE_SET_ASSOC-1)] = 1'b1;
          wt_hybrid_cache_pkg::REPL_ALGO_PLRU:   repl_way = plru_pick_oh(plru_tree_q);
          default:                               repl_way[rr_ptr_q] = 1'b1;
        endcase
        rr_ptr_d    = rr_ptr_q + 1;
      end
    end

    if (rr_ptr_d >= CVA6Cfg.DCACHE_SET_ASSOC)
      rr_ptr_d = '0;

    // Update PLRU tree on hit or chosen replacement
    if (REPL_ALGO == wt_hybrid_cache_pkg::REPL_ALGO_PLRU) begin
      if (|way_hit)
        plru_tree_d = plru_access(plru_tree_q, oh_to_idx(way_hit));
      else if (|repl_way)
        plru_tree_d = plru_access(plru_tree_q, oh_to_idx(repl_way));
    end
  end

  // Update replacement pointers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rr_ptr_q <= '0;
      lfsr_q   <= '1;
      plru_tree_q <= '0;
      flushing_q   <= 1'b0;
      flush_cnt_q  <= '0;
      flush_ack_q  <= 1'b0;
      // clear memory contents
      for (int set = 0; set < CVA6Cfg.DCACHE_NUM_WORDS; set++) begin
        valid_mem[set] <= '0;
        for (int way = 0; way < CVA6Cfg.DCACHE_SET_ASSOC; way++) begin
          data_mem[set][way] <= '0;
          user_mem[set][way] <= '0;
          tag_mem[set][way] <= '0;
          fa_lookup_table[way].valid <= 1'b0;
        end
      end
    end else begin
      rr_ptr_q <= rr_ptr_d;
      lfsr_q   <= lfsr_d;
      plru_tree_q <= plru_tree_d;
      flushing_q  <= flushing_d;
      flush_cnt_q <= flush_cnt_d;
      flush_ack_q <= flush_ack_d;

      // flush operation clears valid bits
      if (flushing_q) begin
        valid_mem[flush_cnt_q] <= '0;
        for (int way = 0; way < CVA6Cfg.DCACHE_SET_ASSOC; way++) begin
          data_mem[flush_cnt_q][way] <= '0;
          user_mem[flush_cnt_q][way] <= '0;
          tag_mem[flush_cnt_q][way] <= '0;
        end
      end else begin
        // cacheline writes
        if (wr_cl_vld_i) begin
          logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] wr_index;
          logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0]   wr_tag;
          wr_index = use_set_assoc_mode_i ? wr_cl_idx_i :
                      ((wr_cl_tag_i ^ HASH_SEED ^ (wr_cl_tag_i >> $clog2(CVA6Cfg.DCACHE_SET_ASSOC))) % DCACHE_FA_SET_COUNT)
                      + DCACHE_FA_BASE_SET;
          wr_tag   = use_set_assoc_mode_i ? wr_cl_tag_i : {wr_cl_idx_i, wr_cl_tag_i};
          for (int way = 0; way < CVA6Cfg.DCACHE_SET_ASSOC; way++) begin
            if (wr_cl_we_i[way]) begin
              data_mem[wr_index][way] <= wr_cl_data_i;
              user_mem[wr_index][way] <= wr_cl_user_i;
              tag_mem[wr_index][way]  <= wr_tag;
              valid_mem[wr_index][way] <= wr_vld_bits_i[way];
              if (!use_set_assoc_mode_i) begin
                fa_lookup_table[way].valid <= wr_vld_bits_i[way];
                fa_lookup_table[way].tag   <= wr_tag;
                fa_lookup_table[way].physical_set <= wr_index;
              end
            end
          end
        end

        // single word writes
        if (|wr_req_i) begin
          logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] widx;
          widx = use_set_assoc_mode_i ? wr_idx_i :
                  ((wr_idx_i ^ HASH_SEED ^ (wr_idx_i >> $clog2(CVA6Cfg.DCACHE_SET_ASSOC))) % DCACHE_FA_SET_COUNT)
                  + DCACHE_FA_BASE_SET;
          for (int way = 0; way < CVA6Cfg.DCACHE_SET_ASSOC; way++) begin
            if (wr_req_i[way]) begin
              data_mem[widx][way][CVA6Cfg.XLEN-1:0] <= wr_data_i;
              user_mem[widx][way][CVA6Cfg.DCACHE_USER_WIDTH-1:0] <= wr_user_i;
              valid_mem[widx][way] <= 1'b1;
            end
          end
        end
      end
    end
  end

  assign wr_ack_o = |wr_req_i;

  ///////////////////////////////
  // Flush control
  ///////////////////////////////

  always_comb begin
    // Default flush limit is the full number of cache sets
    flush_limit = CVA6Cfg.DCACHE_NUM_WORDS[DCACHE_CL_IDX_WIDTH-1:0];

    // When retaining data across mode switches, only iterate over the
    // fully associative subset of entries.
    if (HYBRID_MODE && (REPL_POLICY == wt_hybrid_cache_pkg::REPL_POLICY_RETAIN) &&
        !use_set_assoc_mode_i) begin
      flush_limit = CVA6Cfg.DCACHE_SET_ASSOC[DCACHE_CL_IDX_WIDTH-1:0];
    end
  end

  assign flush_done = (flush_cnt_q == flush_limit - 1) && flushing_q;


  always_comb begin
    // default assignments
    flushing_d  = flushing_q;
    flush_cnt_d = flush_cnt_q;
    flush_ack_d = 1'b0;

    // default SRAM signals
    sram_en_o   = 1'b1;
    sram_we_o   = '0;
    sram_idx_o  = cache_index;
    sram_tag_o  = cache_tag;
    sram_data_o = sram_data_i; // forward input data by default

    // start flush when requested and not already flushing
    if (flush_i && !flushing_q) begin
      flushing_d  = 1'b1;
      flush_cnt_d = use_set_assoc_mode_i ? '0 : DCACHE_FA_BASE_SET;
    end

    // handle ongoing flush
    if (flushing_q) begin
      sram_idx_o  = flush_cnt_q;
      sram_we_o   = SET_MASK;
      sram_tag_o  = '0;
      sram_data_o = '0;
      flush_cnt_d = flush_cnt_q + 1'b1;

      if (flush_done) begin
        flushing_d  = 1'b0;
        flush_cnt_d = '0;
        flush_ack_d = 1'b1;
      end
    end
  end

  // output registered acknowledge
  assign flush_ack_o = flush_ack_q;
  
  // Implementation of mode transition handling
  // If policy is REPL_POLICY_FLUSH, the entire cache is flushed on mode change
  // If policy is REPL_POLICY_RETAIN, entries are kept but reorganized based on new mode
  
  // No additional assignments required here as the SRAM interface is driven
  // in the flush control logic above.

endmodule
