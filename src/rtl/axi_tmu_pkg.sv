// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Chaoqun Liang <chaoqun.liang@unibo.it>

`include "axi/typedef.svh"
`include "register_interface/typedef.svh"

package axi_tmu_pkg;

  //******* COMMON TO ALL IMPLEMENTATIONS *******//

  typedef enum logic [1:0] {
    ILT_MODE = 2'b00,
    CLT_MODE = 2'b01,
    PLT_MODE = 2'b10
  } tmu_mode_e;

  // Monitor parameters
  parameter int unsigned MaxUniqIds    = 2;
  parameter int unsigned MaxTxnsPerId  = 32;
  parameter int unsigned MaxWrTxns     = 64;
  parameter int unsigned MaxRdTxns     = 64;
  parameter int unsigned HsCntWidth    = 4;
  parameter int unsigned PrescalerDiv  = 1;
  // AXI parameters
  parameter int unsigned AxiAddrWidth  = 32;
  parameter int unsigned AxiDataWidth  = 32;
  parameter int unsigned AxiIdWidth    = 6;
  parameter int unsigned AxiIntIdWidth = (MaxUniqIds > 1) ? $clog2(MaxUniqIds) : 1;
  parameter int unsigned AxiUserWidth  = 1;
  parameter int unsigned AxiLogDepth   = 1;

  // AXI type dependent parameters; do not override!
  parameter type addr_t   = logic [AxiAddrWidth-1:0];
  parameter type data_t   = logic [AxiDataWidth-1:0];
  parameter type strb_t   = logic [AxiDataWidth/8-1:0];
  parameter type id_t     = logic [AxiIdWidth-1:0];
  parameter type intid_t  = logic [AxiIntIdWidth-1:0];
  parameter type user_t   = logic [AxiUserWidth-1:0];

  `AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t, id_t, user_t);
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t);
  `AXI_TYPEDEF_B_CHAN_T(b_chan_t, id_t, user_t);
  `AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t, id_t, user_t);
  `AXI_TYPEDEF_R_CHAN_T(r_chan_t, data_t, id_t, user_t);
  `AXI_TYPEDEF_REQ_T(mgr_req_t, aw_chan_t, w_chan_t, ar_chan_t);
  `AXI_TYPEDEF_RESP_T(mgr_rsp_t, b_chan_t, r_chan_t );

  /// Intermediate AXI types
  `AXI_TYPEDEF_AW_CHAN_T(int_aw_t, addr_t, intid_t, user_t);
  `AXI_TYPEDEF_W_CHAN_T(w_t, data_t, strb_t, user_t);
  `AXI_TYPEDEF_B_CHAN_T(int_b_t, intid_t, user_t);
  `AXI_TYPEDEF_AR_CHAN_T(int_ar_t, addr_t, intid_t, user_t);
  `AXI_TYPEDEF_R_CHAN_T(int_r_t, data_t, intid_t, user_t);
  `AXI_TYPEDEF_REQ_T(sbr_req_t, int_aw_t, w_t, int_ar_t);
  `AXI_TYPEDEF_RESP_T(sbr_rsp_t, int_b_t, int_r_t );

  `REG_BUS_TYPEDEF_ALL(cfg, logic [31:0], logic [31:0], logic [7:0]);

  typedef enum logic [2:0] {
    TMU_FLT_NONE     = 3'd0,
    TMU_FLT_TIMEOUT  = 3'd1,   // guard timeout (wr/rd)
    TMU_FLT_SLVERR   = 3'd2,   // self-reported RESP!=OKAY
    TMU_FLT_OVERFLOW = 3'd3,   // resource overflow/ovf event
    TMU_FLT_PROTO    = 3'd4    // unexpected BID/RID etc.
  } tmu_fault_type_t;

  typedef enum logic [1:0] {
    TMU_DIR_NONE  = 2'd0,
    TMU_DIR_READ  = 2'd1,
    TMU_DIR_WRITE = 2'd2
  } tmu_dir_t;

  // Phase code carried by the top, independent of the selected implementation.
  // The guards use tmu_phase_ilt_t / tmu_phase_clt_t / tmu_phase_plt_t;
  // PH_*_NONE must be 0 in all.
  typedef logic [2:0] tmu_phase_t;

  //******* ILT IMPLEMENTATION VARIABLES *******//

  typedef enum logic [2:0] {
    PH_ILT_NONE = 3'd0,
    // Write phases (ILT)
    PH_ILT_AW   = 3'd1,
    PH_ILT_B    = 3'd2,
    // Read phases (ILT)
    PH_ILT_AR   = 3'd3,
    PH_ILT_R    = 3'd4
  } tmu_phase_ilt_t;

  //******* CLT/PLT IMPLEMENTATION VARIABLES *******//

  typedef enum logic [1:0] {
    WRITE_ADDRESS,
    WRITE_DATA,
    WRITE_RESPONSE
  } write_state_t;

  typedef enum logic [1:0] {
    READ_ADDRESS,
    READ_DATA
  } read_state_t;

  typedef enum logic [2:0] {
    PH_CLT_NONE  = 3'd0,
    // Write channels (CLT)
    PH_CLT_AW    = 3'd1,
    PH_CLT_WDATA = 3'd2,
    PH_CLT_BRSP  = 3'd3,
    // Read channels (CLT)
    PH_CLT_AR    = 3'd4,
    PH_CLT_RDATA = 3'd5
  } tmu_phase_clt_t;

  typedef enum logic [3:0] {
    PH_PLT_NONE   = 4'd0,
    // Write phases
    PH_PLT_AW     = 4'd1,  // AWVALID->AWREADY
    PH_PLT_WOWN   = 4'd2,  // Owner wait for first W
    PH_PLT_WFIRST = 4'd3,  // WVALID(first)->WREADY(first)
    PH_PLT_WDATA  = 4'd4,  // WFIRST->WLAST (burst window)
    PH_PLT_W2B    = 4'd5,  // WLAST->BVALID (per-ID)
    PH_PLT_B2BR   = 4'd6,  // BVALID->BREADY (per-ID)
    // Read phases (re-use same enum space)
    PH_PLT_AR     = 4'd7,  // ARVALID->ARREADY
    PH_PLT_RHEAD  = 4'd8,  // ARHS->RFIRST (head waits)
    PH_PLT_RV2RR  = 4'd9,  // RVALID(first)->RREADY
    PH_PLT_RDATA  = 4'd10  // RFIRST->RLAST (head txn)
  } tmu_phase_plt_t;

  typedef struct packed {
    logic             fvalid;
    tmu_fault_type_t  ftype;
    tmu_dir_t         fdir;
    tmu_phase_plt_t   fphase;
    logic [AxiIntIdWidth-1:0]  fid;  // large enough for IntIdWidth (pack/mask on write)
  } tmu_fault_log_t;

endpackage