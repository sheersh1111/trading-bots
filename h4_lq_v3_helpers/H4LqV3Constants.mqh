//+------------------------------------------------------------------+
//| H4LqV3Constants.mqh
//| Constants and object prefixes
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_H4LQV3CONSTANTS
#define H4_LQ_V3_H4LQV3CONSTANTS

const double H4_BREACH_ANCHOR_MULTIPLIER = 0.2; // wick+body vs prior 5-bar avg â€” breaches / hunt / liquidity pivots
const double M2_SWING_ANCHOR_MULTIPLIER  = 1.0; // M2 body vs prior 5-bar avg (plot_swing_h1_m5_copy)
const double M2_TOUCH_VOLUME_MIN_EXPAND_RATIO = 3.0; // touch window: max & touch bar vs window min tick vol
const double H4_BOS_ANCHOR_MULTIPLIER    = 1.0; // full bar range vs prior 5-bar avg â€” BOS only (plot_swing_h4)
const double H4_BREACH_BUFFER_PERCENT_NEAR = 0.0;  // below high / above low
const double H4_BREACH_BUFFER_PERCENT_FAR  = 10.0; // above high / below low
const string H4_LQ_LOG_PREFIX = "h4_lq_v3";
// --- trade sizing (N swing-TP orders + 1 fixed 2R order; USD risk from score normalization) ---
const ulong    LQ_EXPERT_MAGIC                    = 940029;
const double   LQ_STOP_BUFFER_PERCENT_CHART       = 1.0;
const int      LQ_FVG_TRADE_MAX_M2_BAR_SHIFT      = 24;
const int      LQ_TP_COUNT_MAX                    = 3;

const string ChartObjectNamePrefixH4VolumeBreachRay = "LQ2_H4_VOL_BREACH_";
const string PFX_MTF_W1_TR  = "LQ2_MTF_W1_TR_";
const string PFX_MTF_W1_LBL = "LQ2_MTF_W1_LB_";
const string PFX_MTF_D1_TR  = "LQ2_MTF_D1_TR_";
const string PFX_MTF_D1_LBL = "LQ2_MTF_D1_LB_";
const string PFX_MTF_H4_TR  = "LQ2_MTF_H4_TR_";
const string PFX_MTF_H4_LBL = "LQ2_MTF_H4_LB_";
const string PFX_MTF_M15_TR  = "LQ2_MTF_M15_TR_";
const string PFX_MTF_M15_LBL = "LQ2_MTF_M15_LB_";
const color  H4_VOLUME_BREACH_RAY_COLOR_UP   = clrGreen;
const color  H4_VOLUME_BREACH_RAY_COLOR_DOWN = clrDeepPink;
const int    H4_VOLUME_BREACH_RAY_ZORDER     = 128;
const string PFX_M2_TREND  = "LQ2_M2_TR_";
const string PFX_M2_LBL    = "LQ2_M2_LB_";
const string PFX_M2_ANCHOR = "LQ2_M2_AN_";
const string LQ_OBJ_PREFIX_FVG_RECT = "LQ2_M2_FVG_";
const string LQ_OBJ_PREFIX_FVG_LBL  = "LQ2_M2_FVGT_";
const string LQ_OBJ_PREFIX_SMC_ZONE_RECT = "LQ2_SMCZ_";
const string LQ_OBJ_HUNT_HUD           = "LQ2_HUNT_HUD";
const string LQ_OBJ_MTF_BIAS_HUD_W1    = "LQ4_MTF_BIAS_W1";
const string LQ_OBJ_MTF_BIAS_HUD_D1    = "LQ4_MTF_BIAS_D1";
const string LQ_OBJ_MTF_BIAS_HUD_H4    = "LQ4_MTF_BIAS_H4";
const string LQ_OBJ_MTF_BIAS_HUD_M15   = "LQ4_MTF_BIAS_M15";
const string LQ_OBJ_IMPULSE_BUFFER  = "LQ2_IMPULSE_BUF";
const string LQ_OBJ_TOUCH_POINT     = "LQ2_TOUCH_PT";
const string LQ_OBJ_IMPULSE_PREFIX      = "LQ2_IMPULSE_BUF_";
const string LQ_OBJ_TOUCH_RECALC_PREFIX = "LQ2_TRECALC_BUF_";
const string LQ_OBJ_TRADE_SWGRP_RECT_PREFIX = "LQ2_TRD_SWG_R_";
const string LQ_OBJ_TRADE_SWGRP_LINE_PREFIX = "LQ2_TRD_SWG_L_";
#define V2_MAX_HUNT_SESSIONS              2   // at most one high-breach + one low-breach hunt

#endif // H4_LQ_V3_H4LQV3CONSTANTS
