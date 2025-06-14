// WT_DUO cache subsystem wrapper
// Instantiates both WT and WT_CLN caches and selects between them
// based on privilege level

module wt_duo_cache_priv_adapter
  import ariane_pkg::*;
  import wt_cache_pkg::*;
  import wt_cln_cache_pkg::*;
#(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  parameter type icache_areq_t = logic,
  parameter type icache_arsp_t = logic,
  parameter type icache_dreq_t = logic,
  parameter type icache_drsp_t = logic,
  parameter type dcache_req_i_t = logic,
  parameter type dcache_req_o_t = logic,
  parameter type icache_req_t = logic,
  parameter type icache_rtrn_t = logic,
  parameter int unsigned NumPorts = 4,
  parameter type noc_req_t = logic,
  parameter type noc_resp_t = logic
) (
  input logic clk_i,
  input logic rst_ni,
  input riscv::priv_lvl_t priv_lvl_i,
  // original ports
  input logic icache_en_i,
  input logic icache_flush_i,
  output logic icache_miss_o,
  input icache_areq_t icache_areq_i,
  output icache_arsp_t icache_areq_o,
  input icache_dreq_t icache_dreq_i,
  output icache_drsp_t icache_dreq_o,
  input logic dcache_enable_i,
  input logic dcache_flush_i,
  output logic dcache_flush_ack_o,
  output logic dcache_miss_o,
  output logic [NumPorts-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0] miss_vld_bits_o,
  input amo_req_t dcache_amo_req_i,
  output amo_resp_t dcache_amo_resp_o,
  input dcache_req_i_t [NumPorts-1:0] dcache_req_ports_i,
  output dcache_req_o_t [NumPorts-1:0] dcache_req_ports_o,
  output logic wbuffer_empty_o,
  output logic wbuffer_not_ni_o,
  output noc_req_t noc_req_o,
  input noc_resp_t noc_resp_i,
  input logic [63:0] inval_addr_i,
  input logic inval_valid_i,
  output logic inval_ready_o
);

  // Determine which cache controller is active.
  // This register is updated every cycle so that privilege level
  // transitions immediately switch between WT and WT_CLN caches.
  logic use_wt;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      use_wt <= 1'b1; // machine mode after reset
    end else begin
      use_wt <= (priv_lvl_i == riscv::PRIV_LVL_M);
    end
  end

  // ---------------------------------------------------------------------------
  // WT cache instance
  // ---------------------------------------------------------------------------
  logic icache_miss_wt;
  logic dcache_flush_ack_wt;
  logic dcache_miss_wt;
  logic [NumPorts-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0] miss_vld_bits_wt;
  amo_resp_t dcache_amo_resp_wt;
  dcache_req_o_t [NumPorts-1:0] dcache_req_ports_wt;
  logic wbuffer_empty_wt;
  logic wbuffer_not_ni_wt;
  noc_req_t noc_req_wt;
  logic inval_ready_wt;

  wt_cache_subsystem #(
    .CVA6Cfg(CVA6Cfg),
    .icache_areq_t(icache_areq_t),
    .icache_arsp_t(icache_arsp_t),
    .icache_dreq_t(icache_dreq_t),
    .icache_drsp_t(icache_drsp_t),
    .dcache_req_i_t(dcache_req_i_t),
    .dcache_req_o_t(dcache_req_o_t),
    .icache_req_t(icache_req_t),
    .icache_rtrn_t(icache_rtrn_t),
    .NumPorts(NumPorts),
    .noc_req_t(noc_req_t),
    .noc_resp_t(noc_resp_t)
  ) i_wt_cache (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .icache_en_i(icache_en_i),
    .icache_flush_i(icache_flush_i),
    .icache_miss_o(icache_miss_wt),
    .icache_areq_i(icache_areq_i),
    .icache_areq_o(icache_areq_o),
    .icache_dreq_i(icache_dreq_i),
    .icache_dreq_o(icache_dreq_o),
    .dcache_enable_i(dcache_enable_i),
    .dcache_flush_i(dcache_flush_i),
    .dcache_flush_ack_o(dcache_flush_ack_wt),
    .dcache_miss_o(dcache_miss_wt),
    .miss_vld_bits_o(miss_vld_bits_wt),
    .dcache_amo_req_i(dcache_amo_req_i),
    .dcache_amo_resp_o(dcache_amo_resp_wt),
    .dcache_req_ports_i(dcache_req_ports_i),
    .dcache_req_ports_o(dcache_req_ports_wt),
    .wbuffer_empty_o(wbuffer_empty_wt),
    .wbuffer_not_ni_o(wbuffer_not_ni_wt),
    .noc_req_o(noc_req_wt),
    .noc_resp_i(noc_resp_i),
    .inval_addr_i(inval_addr_i),
    .inval_valid_i(inval_valid_i),
    .inval_ready_o(inval_ready_wt)
  );

  // ---------------------------------------------------------------------------
  // WT_CLN cache instance
  // ---------------------------------------------------------------------------
  logic icache_miss_cln;
  logic dcache_flush_ack_cln;
  logic dcache_miss_cln;
  logic [NumPorts-1:0][CVA6Cfg.DCACHE_SET_ASSOC-1:0] miss_vld_bits_cln;
  amo_resp_t dcache_amo_resp_cln;
  dcache_req_o_t [NumPorts-1:0] dcache_req_ports_cln;
  logic wbuffer_empty_cln;
  logic wbuffer_not_ni_cln;
  noc_req_t noc_req_cln;
  logic inval_ready_cln;

  wt_cln_cache_subsystem #(
    .CVA6Cfg(CVA6Cfg),
    .icache_areq_t(icache_areq_t),
    .icache_arsp_t(icache_arsp_t),
    .icache_dreq_t(icache_dreq_t),
    .icache_drsp_t(icache_drsp_t),
    .dcache_req_i_t(dcache_req_i_t),
    .dcache_req_o_t(dcache_req_o_t),
    .icache_req_t(icache_req_t),
    .icache_rtrn_t(icache_rtrn_t),
    .NumPorts(NumPorts),
    .noc_req_t(noc_req_t),
    .noc_resp_t(noc_resp_t)
  ) i_wt_cln_cache (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .icache_en_i(icache_en_i),
    .icache_flush_i(icache_flush_i),
    .icache_miss_o(icache_miss_cln),
    .icache_areq_i(icache_areq_i),
    .icache_areq_o(),
    .icache_dreq_i(icache_dreq_i),
    .icache_dreq_o(),
    .dcache_enable_i(dcache_enable_i),
    .dcache_flush_i(dcache_flush_i),
    .dcache_flush_ack_o(dcache_flush_ack_cln),
    .dcache_miss_o(dcache_miss_cln),
    .miss_vld_bits_o(miss_vld_bits_cln),
    .dcache_amo_req_i(dcache_amo_req_i),
    .dcache_amo_resp_o(dcache_amo_resp_cln),
    .dcache_req_ports_i(dcache_req_ports_i),
    .dcache_req_ports_o(dcache_req_ports_cln),
    .wbuffer_empty_o(wbuffer_empty_cln),
    .wbuffer_not_ni_o(wbuffer_not_ni_cln),
    .noc_req_o(noc_req_cln),
    .noc_resp_i(noc_resp_i),
    .inval_addr_i(inval_addr_i),
    .inval_valid_i(inval_valid_i),
    .inval_ready_o(inval_ready_cln)
  );

  // ---------------------------------------------------------------------------
  // Output multiplexing based on privilege level
  // ---------------------------------------------------------------------------
  assign icache_miss_o     = use_wt ? icache_miss_wt     : icache_miss_cln;
  assign dcache_flush_ack_o = use_wt ? dcache_flush_ack_wt : dcache_flush_ack_cln;
  assign dcache_miss_o     = use_wt ? dcache_miss_wt     : dcache_miss_cln;
  assign miss_vld_bits_o   = use_wt ? miss_vld_bits_wt   : miss_vld_bits_cln;
  assign dcache_amo_resp_o = use_wt ? dcache_amo_resp_wt : dcache_amo_resp_cln;
  assign dcache_req_ports_o = use_wt ? dcache_req_ports_wt : dcache_req_ports_cln;
  assign wbuffer_empty_o   = use_wt ? wbuffer_empty_wt   : wbuffer_empty_cln;
  assign wbuffer_not_ni_o  = use_wt ? wbuffer_not_ni_wt  : wbuffer_not_ni_cln;
  assign noc_req_o         = use_wt ? noc_req_wt         : noc_req_cln;
  assign inval_ready_o     = use_wt ? inval_ready_wt     : inval_ready_cln;

endmodule
