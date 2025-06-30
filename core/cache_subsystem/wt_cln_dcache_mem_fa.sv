// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Simple Fully Associative Cache Memory for WT_CLN DCache
// Author: AI Assistant
// Description: Minimal FA cache implementation with direct integration

module wt_cln_dcache_mem_fa
  import ariane_pkg::*;
  import wt_cln_cache_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter int unsigned           NumPorts = 3
) (
    input logic clk_i,
    input logic rst_ni,
    
    // Read ports
    input logic [NumPorts-1:0][CVA6Cfg.DCACHE_TAG_WIDTH-1:0] rd_tag_i,
    input logic [NumPorts-1:0][CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0] rd_off_i,
    input logic [NumPorts-1:0] rd_req_i,
    input logic [NumPorts-1:0] rd_tag_only_i,
    output logic [NumPorts-1:0] rd_ack_o,
    output logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] rd_vld_bits_o,
    output logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] rd_hit_oh_o,
    output logic [CVA6Cfg.XLEN-1:0] rd_data_o,
    
    // Write port 0 - cache line writes
    input logic wr_cl_vld_i,
    input logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] wr_cl_we_i,
    input logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] wr_cl_tag_i,
    input logic [CVA6Cfg.DCACHE_LINE_WIDTH-1:0] wr_cl_data_i,
    input logic [CVA6Cfg.DCACHE_LINE_WIDTH/8-1:0] wr_cl_data_be_i,
    input logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] wr_vld_bits_i,
    
    // Single word write port
    input logic [CVA6Cfg.DCACHE_SET_ASSOC-1:0] wr_req_i,
    output logic wr_ack_o,
    input logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0] wr_off_i,
    input logic [CVA6Cfg.XLEN-1:0] wr_data_i,
    input logic [(CVA6Cfg.XLEN/8)-1:0] wr_data_be_i
);

    // FA cache storage - 8 fully associative entries
    localparam FA_ENTRIES = CVA6Cfg.DCACHE_SET_ASSOC;
    localparam WORDS_PER_LINE = CVA6Cfg.DCACHE_LINE_WIDTH / CVA6Cfg.XLEN;
    
    // Storage arrays with proper coherency tracking
    logic [FA_ENTRIES-1:0] fa_way_valid_q, fa_way_valid_d;
    logic [FA_ENTRIES-1:0][CVA6Cfg.DCACHE_TAG_WIDTH-1:0] tags_q;
    logic [FA_ENTRIES-1:0][CVA6Cfg.DCACHE_LINE_WIDTH-1:0] data_q;
    
    // Read/write conflict detection
    logic rd_wr_address_conflict;
    logic [CVA6Cfg.PLEN-CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0] rd_cl_addr, wr_cl_addr;
    
    // Read pipeline registers
    logic rd_req_q;
    logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] rd_tag_q;
    logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0] rd_off_q;
    logic [$clog2(NumPorts)-1:0] rd_port_q;
    
    // Port selection - simple priority encoder
    logic rd_valid;
    logic [$clog2(NumPorts)-1:0] rd_port;
    logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0] rd_tag;
    logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-1:0] rd_off;
    
    always_comb begin
        rd_valid = 1'b0;
        rd_port = '0;
        rd_tag = '0;
        rd_off = '0;
        
        // Simple priority encoder for read requests
        for (int i = 0; i < NumPorts; i++) begin
            if (rd_req_i[i]) begin
                rd_valid = 1'b1;
                rd_port = i[$clog2(NumPorts)-1:0];
                rd_tag = rd_tag_i[i];
                rd_off = rd_off_i[i];
                break;
            end
        end
    end
    
    // Read/write conflict detection - only conflict on actual address matches
    assign rd_cl_addr = {rd_tag};  // FA: only tag (no index)
    assign wr_cl_addr = {wr_cl_tag_i};  // FA: only tag (no index)
    assign rd_wr_address_conflict = wr_cl_vld_i && (rd_cl_addr == wr_cl_addr);
    
    // Single word write is acknowledged if no address conflict
    assign wr_ack_o = |wr_req_i && !rd_wr_address_conflict;
    
    //////////////////////////////////////////////////////////////////////////
    // Pipeline Stage 1: Register request
    //////////////////////////////////////////////////////////////////////////
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rd_req_q <= 1'b0;
            rd_tag_q <= '0;
            rd_off_q <= '0;
            rd_port_q <= '0;
        end else begin
            rd_req_q <= rd_valid;
            rd_tag_q <= rd_tag;
            rd_off_q <= rd_off;
            rd_port_q <= rd_port;
        end
    end
    
    //////////////////////////////////////////////////////////////////////////
    // Storage Arrays - Simple registers for FA cache
    //////////////////////////////////////////////////////////////////////////
    
    // Valid bit logic with proper coherency
    always_comb begin
        fa_way_valid_d = fa_way_valid_q;
        
        // Cache line writes have priority and use explicit valid bits
        if (wr_cl_vld_i && |wr_cl_we_i) begin
            fa_way_valid_d = (fa_way_valid_q & ~wr_cl_we_i) | wr_vld_bits_i;
        end else if (|wr_req_i) begin
            // Single word writes only set valid if no cache line write
            fa_way_valid_d = fa_way_valid_q | wr_req_i;
        end
    end
    
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fa_way_valid_q <= '0;
            tags_q <= '0;
            data_q <= '0;
        end else begin
            // Update valid bits
            fa_way_valid_q <= fa_way_valid_d;
            
            // Cache line writes
            if (wr_cl_vld_i) begin
                for (int i = 0; i < FA_ENTRIES; i++) begin
                    if (wr_cl_we_i[i]) begin
                        tags_q[i] <= wr_cl_tag_i;
                        // Apply byte enables
                        for (int j = 0; j < CVA6Cfg.DCACHE_LINE_WIDTH/8; j++) begin
                            if (wr_cl_data_be_i[j]) begin
                                data_q[i][j*8 +: 8] <= wr_cl_data_i[j*8 +: 8];
                            end
                        end
                    end
                end
            end
            
            // Single word writes
            for (int i = 0; i < FA_ENTRIES; i++) begin
                if (wr_req_i[i]) begin
                    automatic logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-CVA6Cfg.XLEN_ALIGN_BYTES-1:0] word_idx;
                    word_idx = wr_off_i[CVA6Cfg.DCACHE_OFFSET_WIDTH-1:CVA6Cfg.XLEN_ALIGN_BYTES];
                    
                    // Write to specific word with byte enables
                    for (int j = 0; j < CVA6Cfg.XLEN/8; j++) begin
                        if (wr_data_be_i[j]) begin
                            data_q[i][word_idx*CVA6Cfg.XLEN + j*8 +: 8] <= wr_data_i[j*8 +: 8];
                        end
                    end
                end
            end
        end
    end
    
    //////////////////////////////////////////////////////////////////////////
    // Pipeline Stage 2: Hit detection and data selection
    //////////////////////////////////////////////////////////////////////////
    
    logic [FA_ENTRIES-1:0] hit_vector;
    logic hit;
    logic [$clog2(FA_ENTRIES)-1:0] hit_way;
    logic [CVA6Cfg.XLEN-1:0] hit_data;
    
    // Parallel tag comparison with proper valid bit checking
    always_comb begin
        hit_vector = '0;
        for (int i = 0; i < FA_ENTRIES; i++) begin
            if (fa_way_valid_q[i] && (tags_q[i] == rd_tag_q)) begin
                hit_vector[i] = 1'b1;
            end
        end
        hit = |hit_vector;
    end
    
    // Priority encoder for hit way
    always_comb begin
        hit_way = '0;
        for (int i = FA_ENTRIES-1; i >= 0; i--) begin
            if (hit_vector[i]) begin
                hit_way = i[$clog2(FA_ENTRIES)-1:0];
            end
        end
    end
    
    // Data selection
    always_comb begin
        automatic logic [CVA6Cfg.DCACHE_OFFSET_WIDTH-CVA6Cfg.XLEN_ALIGN_BYTES-1:0] word_idx;
        word_idx = rd_off_q[CVA6Cfg.DCACHE_OFFSET_WIDTH-1:CVA6Cfg.XLEN_ALIGN_BYTES];
        
        if (hit) begin
            hit_data = data_q[hit_way][word_idx*CVA6Cfg.XLEN +: CVA6Cfg.XLEN];
        end else begin
            hit_data = '0;
        end
    end
    
    // Output assignments with conflict handling
    assign rd_vld_bits_o = fa_way_valid_q;
    assign rd_hit_oh_o = rd_req_q ? hit_vector : '0;
    assign rd_data_o = hit_data;
    
    // Generate acknowledgments for each port - block on address conflicts
    always_comb begin
        rd_ack_o = '0;
        if (rd_req_q && !rd_wr_address_conflict) begin
            rd_ack_o[rd_port_q] = 1'b1;
        end
    end

endmodule