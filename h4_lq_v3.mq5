//+------------------------------------------------------------------+
//| h4_lq_v3.mq5                                                      |
//| H4 breach hunt + M2 Engulfing Volume Absorption entry model       |
//| v3.88: setup score calculated only after sweep pattern confirmed |
//| v3.87: single CalculateSetupTradeScore per M2 bar (removed FromStopLoss duplicate) |
//| v3.86: zone score — each weight input counts at most once (ConfluenceScoring v1.2) |
//| v3.85: fix GetMaxPossibleScore HighLow stack (ConfluenceScoring v1.1) — superseded |
//| v3.84: remove dead v2 FVG/touch-vol/hunt-session code (engulf-only live path) |
//| v3.83: entry order type input (limit/market/stop) + pending order expiry timer |
//| v3.82: score CSV write mode skips swing TP calc + order placement (score log only) |
//| v3.81: score log — running int P100 only (no g_allScores array); flush on deinit |
//| v3.80: solo TP fallback respects 10% proximity vs cluster TPs + other chosen levels |
//| v3.79: swing TP fallback — individual swing levels when cluster TPs < 3 (same R:R + front-run) |
//| v3.78: score CSV write/read switch; P100/P90 from all positive scores (not top-K) |
//| v3.77: zone location score only when bull setup low / bear setup high is inside zone |
//| v3.76: in-memory score logging storage disabled (ScoreP100 risk lookup still active) |
//| v3.75: score-logging CSV output disabled (ScoreP100 risk lookup still active) |
//| v3.74: tester risk sizing uses ScoreP100 from permutation summary CSV (fallback: theoretical max) |
//| v3.73: upsert permutation row in shared optimization_permutation_summary.csv |
//| v3.72: score summary CSV in agent Files root (not OptimizationData subfolder) |
//| v3.71: one shared optimization CSV row per permutation (weights + ScoreP100/P90) |
//| v3.70: in-memory top-K score buffer (score>0 only); single CSV flush on deinit |
//| v3.69: comment cluster multiplier (cluster flag unused) + remove from optimization CSV permutation |
//| v3.68: replace Protected/Swing weights with per-TF HighLow zone weights (W1/D1/H4/M15) |
//| v3.67: FVG min gap on registered (post-inset) height; cascade-mitigate overlapping FVG peers |
//| v3.66: MTF FVG zones require min gap = N% of TF chart height (default 1%) |
//| v3.65: remove legacy H4 BOS pending-confirm track; MTF SMC BOS sets bias + logs |
//| v3.64: run breach/mitigation on leg-close bars for existing zones (defer only new zone origin bar) |
//| v3.63: swing zones merge by leg origin time only — keep separate highs/lows at different levels |
//| v3.58: purge all chart rects per slot + orphan sweep; fix stale rects on slot reuse |
//| v3.57: per-TF bar-close cleanup deletes mitigated/expired zone + FVG chart objects |
//| v3.56: zone rect width = InputSmcZoneExpiryBars from zoneOriginBarTime (matches expiry) |
//| v3.55: breach on wick or close-through; same-bar breach+mitigate; isActive=false on mitigate |
//| v3.54: persistent zone ledger — no destructive refresh; additive registration; multi swing zones + FIFO |
//| v3.53: leg-close flag from swing step; leg-close draws only new zone; sync rects; bias then mitigate per zone |
//| v3.52: leg-close detected via swing history count; force fresh zone state on leg registration |
//| v3.51: leg-close bar — register swing zone only; skip clear/breach/bias/mitigation for all zones |
//| v3.50: swing zones always at leg close (no price filter); no unbroken overwrite; persist unmitigated ledger zones |
//| v3.49: zone isBreached on wick entry; bias then mitigate only after breached + close outside |
//| v3.47: zone mitigation — enter zone (wick) then close outside only (any direction); preserve swing ledger |
//| v3.46: HTF bias — BOS sets direction; same-TF zone touch + close outside sets direction on bar close |
//| v3.45: MTF direction HUD (W1/D1/H4/M15) replaces H4-only bias HUD |
//| v3.44: keep all MTF FVG instances in lookback until mitigated or expired (not latest-only) |
//| v3.43: MTF SMC FVG zone = gap itself; 1% inset on price-facing edge (not M2/swing liq. bands) |
//| v3.41: register bull zones only below price, bear zones only above current price |
//| v3.40: SMC zone rectangles per TF follow InputDrawMtfSwingLegs* toggles |
//| v3.39: swing zones — completed legs only; skip active (open) leg extremes |
//| v3.38: swing zones — dedicated slots + directional mitigation (no instant mitigate on leg-close bar) |
//| v3.37: fix swing zones on leg close — violation only after leg end; register last closed leg |
//| v3.36: per-TF inputs to draw MTF swing legs (W1/D1/H4/M15) on leg close |
//| v3.35: per-TF MTF swing leg API — completed-leg highs/lows + unified replay step |
//| v3.34: remove narrative H4 swing — H4 legs/BOS/pivots use MTF SMC tracker only |
//| v3.33: SMC zone chart object names include TF tag (W1/D1/H4/M15) |
//| v3.32: liquidity zones — high=[high, high+buffer], low=[low-buffer, low] (one-sided 10%) |
//| v3.31: HTF professional bias — BOS default + zone mitigation/reversal override (W1/D1/H4) |
//| v3.62: remove broken high/low zone registration on BOS; keep protected/FVG/swing zones |
//| v3.61: per-permutation CSV — weight name/value header + score rows (one file per pass) |
//| v3.59: OptimizationData.csv logs score+context+all confluence weight inputs per valid setup |
//| v3.30: log setup scores to ScoreDistribution.csv before score gate on valid M2 sweep pattern |
//| v3.29: entry requires setupScore >= InputMinScore (signed; 0 blocks negative) |
//| v3.28: optional hollow rectangles for active SMC zones |
//| v3.27: SMC zones register/mitigate/expire on each zone TF bar close only |
//| v3.26: risk metrics logged inline in GetOptimizedLotSize (no extra helper functions) |
//| v3.25: log clampedRatio and riskPercent alongside setupScore on trade placement |
//| v3.24: remove pre-entry TP3 pending-order cancel (market entry replaces limit-only guard) |
//| v3.23: zone expiry — inactive for score after N bars on zone timeframe (default 292) |
//| v3.22: zone mitigation — exit zone (reverse or break) excludes from score |
//| v3.21: unbroken swing highs/lows as resistance/support in zone matrix (28 zones) |
//| v3.20: dynamic score-normalized risk sizing + InputMinScore entry gate |
//| v3.19: log confluence setup score on each successful order placement |
//| v3.18: Confluence scoring engine — optimizable zone + BOS alignment weights |
//| v3.17: SMC broken/protected zone buffer = N% of each TF chart height |
//| v3.16: SMC zone fusion — overlap clustering + confluence score multiplier |
//| v3.15: SMC protected extremes — bull leg low / bear leg high on BOS (20 zones) |
//| v3.14: MTF SMC confluence engine — W1/D1/H4/M15 swings + 14-zone matrix |
//| v3.13: leg vol spike = max(last bar of ref leg, first bar of next leg) vs avg vol in ref leg |
//| v3.12: exhaustion pass when volC > volB (latest same-dir leg volume higher) |
//| v3.11: exhaustion uses last 2 same-dir legs only (volC < volB) |
//| v3.10: sweep setup = 2 events in countdown (wick sweep + close reject on bar 1 edge) |
//| v3.09: vol spike validates swing-leg ref at formation; multi-level sweep picks extreme/earliest |
//| v3.08: local extreme band anchors to M2 swing-leg sweep ref (not chart lookback high/low) |
//| v3.07: direct M2 swing-leg sweep scan on bar close — hunt arming removed |
//| v3.06: local extreme band uses full sweep countdown window extremes |
//| v3.05: M2 swing-leg sweep-reject entry (countdown bars) replaces engulf footprint |
//| v3.04: volume-breach record array + hunt arming disabled; H4 swing + BOS kept |
//| v3.03: engulf local-extreme band widened to -2%..+20% of chart height |
//| v3.02: engulf pair local-extreme band — bear pair high within prev local high + N% chart |
//| v3.01: exhaustion leg filter — min leg range % of M2 chart height (replaces min bar count) |
//| v3.00: replace M2 touch/FVG with engulfing vol absorption + exhaustion gate |
//+------------------------------------------------------------------+
#define H4_LQ_V3_VERSION "3.88"
// Breach record array + hunt arming: uncomment next line to re-enable.
// #define H4_LQ_VOLUME_BREACH_ENABLED
#property copyright ""
#property version   H4_LQ_V3_VERSION
#property description "h4_lq_v3 â€” H4 breach hunt + engulfing volume absorption"

#include <Trade\Trade.mqh>

input group "Tester performance"
input bool   InputFastTesterMode = false; // true: no hunt logs, no chart objects/HUDs (faster backtest)

input group "Narrative timeframes"
input ENUM_TIMEFRAMES InputM2NarrativeTimeframe  = PERIOD_M2;  // FVG, hunt, entry management (H4 via MTF SMC)

input bool   InputSwitchChartToH4       = true;

input bool   InputDrawM2SwingLegs        = false; // chart trend lines/labels only; does not disable M2 swing or hunt logic
input color  InputM2SwingLineColor       = clrMediumPurple;
input bool   InputDrawM2SwingAnchorLevel = true;  // realtime horizontal line at M2 leg flip anchor (priceAnchorLevel)
input color  InputM2SwingAnchorColor     = clrYellow;
input int    InputM2SwingWarmupBars      = 500; // 0 = off: replay M2 on attach (plot_swing_h1_m5_copy)

input group "H4 breach â†’ M2 engulfing absorption"
input bool   InputEnableEngulfHuntAfterH4Breach = true;
input int    InputH4BreachBufferChartBarCount = 74; // H4 bars: buffer reference height + active volume breach records
input int    InputH4LiquidityPivotLookbackBars = 1166; // replay lookback for liquidity pivot rebuild (chart/analysis)
input bool   InputDrawImpulseCancelBufferZone = true;  // hollow rect while hunt ON
input color  InputImpulseCancelBufferColor    = clrDarkOrange;
input int    InputChartRangeBarCount     = 147;
input bool   InputShowLiquidityHuntHud   = true;
input bool   InputLogHuntEvents          = true;  // Experts tab: hunt / engulf / BOS

input group "H4 SMC trade direction filter"
input bool   InputEnableH4BosTradeDirectionBias = true;  // block trades against H4 GetProfessionalBias

const double H4_BREACH_ANCHOR_MULTIPLIER = 0.2; // wick+body vs prior 5-bar avg â€” breaches / hunt / liquidity pivots
const double M2_SWING_ANCHOR_MULTIPLIER  = 1.0; // M2 body vs prior 5-bar avg (plot_swing_h1_m5_copy)
const double M2_TOUCH_VOLUME_MIN_EXPAND_RATIO = 3.0; // touch window: max & touch bar vs window min tick vol
const double H4_BOS_ANCHOR_MULTIPLIER    = 1.0; // full bar range vs prior 5-bar avg â€” BOS only (plot_swing_h4)
const double H4_BREACH_BUFFER_PERCENT_NEAR = 0.0;  // below high / above low
const double H4_BREACH_BUFFER_PERCENT_FAR  = 10.0; // above high / below low

enum ENUM_TRADE_ENTRY_ORDER_TYPE
{
   TRADE_ENTRY_ORDER_LIMIT  = 0,  // BuyLimit / SellLimit @ reference entry
   TRADE_ENTRY_ORDER_MARKET = 1,  // Buy / Sell at market
   TRADE_ENTRY_ORDER_STOP   = 2   // BuyStop / SellStop (reference + offset points)
};

input group "Engulfing absorption trade"
input bool   InputEnableAutomatedTrading = true;   // false = log trade plan only (no orders)
input ENUM_TRADE_ENTRY_ORDER_TYPE InputTradeEntryOrderType = TRADE_ENTRY_ORDER_LIMIT;
input int    InputPendingStopEntryOffsetPoints = 2;    // stop entry: buy above / sell below reference (1..2 pts)
input int    InputPendingOrderExpirySeconds    = 60;   // limit/stop: cancel pendings after T sec if unfilled; 0=off
input bool   InputDrawTradeSwingGroupTpZones   = true; // chart only: swing high/low group rects + TP lines on order
input int    InputTradeSwingLookbackM2Bars     = 292;  // M2 bars scanned for swing highs (bull) / lows (bear)
input double InputTradeSwingProximityPercentOfChartRange = 10.0; // cluster + buffer band = N% of M2 chart height
input double InputTradeSwingTpFrontRunPercentOfChartRange = 2.0; // TP front-run offset = N% of M2 chart height
input color  InputTradeSwingProximityRectColorBull = clrLimeGreen;
input color  InputTradeSwingProximityLineColorBull = clrLimeGreen;
input color  InputTradeSwingProximityRectColorBear = clrCrimson;
input color  InputTradeSwingProximityLineColorBear = clrCrimson;
input double InputTradeSwingTpMinRewardToRisk = 2.0; // skip line/TP when reward:risk below this (1:2 = 2.0)
input double InputEngulfSlBufferPercentChart    = 2.0; // SL beyond engulf ref extreme; 0=SL at ref extreme
input int    InputEngulfMinSlPoints           = 0;     // min entryâ€“SL pts; 0=broker stops level only when widening SL
input int    InputEngulfVolAvgBarCount        = 15;  // avg tick vol baseline for engulf pair spike check
input double InputEngulfExhaustionMinLegRangePercentChart = 15.0; // exhaustion: leg H-L >= N% of InputChartRangeBarCount M2 height; 0=off
input int    InputEngulfExhaustionLegCount    = 2;   // same-dir legs: volC (latest) must exceed volB (prior)
input double InputEngulfPairLocalExtremeMinOffsetPercentChart = -2.0; // bear: pair high >= prev local high + N% chart (-2 = 2% below); bull mirrored; 0 w/ max=0=off
input double InputEngulfPairLocalExtremeMaxOffsetPercentChart = 20.0; // bear: pair high <= prev local high + N% chart; bull mirrored
input int    InputEngulfSweepCountdownBars      = 2;   // M2 bars: sweep ref swing extreme then close back (1..N)

input group "MTF SMC confluence engine"
input bool   InputEnableMtfSmcEngine           = true;
input int    InputSmcFvgLookbackBars           = 50;  // W1/D1/H4/M15: scan last N bars for 3-bar FVGs
input double InputSmcFvgZonePriceFacingInsetPercentChart = 1.0; // trim MTF FVG top (bull) / bottom (bear) by N% of TF chart height — price-facing edge
input double InputSmcFvgMinGapPercentChart           = 1.0; // min registered FVG zone height (after inset) = N% of TF chart height; 0=off
input double InputSmcBrokenLevelBufferPercentChart = 10.0; // SMC zone extension = N% of TF chart height above highs / below lows
input int    InputSmcMtfWarmupBars             = 300; // 0=off: replay MTF swings on attach
input int    InputSmcZoneExpiryBars            = 292; // zone expires when older than N bars on its TF

input group "MTF swing leg chart visuals"
input bool   InputDrawMtfSwingLegsW1   = false; // W1 swing legs + SMC zone rectangles
input color  InputMtfSwingLegColorW1   = clrSilver;
input bool   InputDrawMtfSwingLegsD1   = false; // D1 swing legs + SMC zone rectangles
input color  InputMtfSwingLegColorD1   = clrDodgerBlue;
input bool   InputDrawMtfSwingLegsH4   = true;  // H4 swing legs + SMC zone rectangles
input color  InputMtfSwingLegColorH4   = clrGold;
input bool   InputDrawMtfSwingLegsM15  = false; // M15 swing legs + SMC zone rectangles
input color  InputMtfSwingLegColorM15  = clrMediumSeaGreen;
input bool   InputShowMtfDirectionHud  = true;  // top-right W1/D1/H4/M15 professional bias arrows

input group "Confluence Scoring Weights"
input int    InputWeight_WeeklyFVG             = 10;
input int    InputWeight_DailyFVG              = 8;
input int    InputWeight_H4FVG                 = 5;
input int    InputWeight_M15FVG                = 2;
input int    InputWeight_W1_HighLowZones       = 10; // W1 swing/protected highs+lows (same default as W1 FVG)
input int    InputWeight_D1_HighLowZones       = 8;  // D1 swing/protected highs+lows (same default as D1 FVG)
input int    InputWeight_H4_HighLowZones       = 5;  // H4 swing/protected highs+lows (same default as H4 FVG)
input int    InputWeight_M15_HighLowZones      = 2;  // M15 swing/protected highs+lows (same default as M15 FVG)
// input double InputClusterMultiplier            = 1.5; // unused (isClustered is never set true)
input double InputMinScore                     = 0.0;  // min signed setupScore to allow entry; 0=block score<0
input double InputBaseRiskPercent            = 1.0;  // equity % at ScoreP100 (tester) or theoretical max; scaled by |score|/denom

input group "Optimization score logging"
input bool   InputScoreLogWriteCsv             = false; // true=score P100 CSV only (no TP calc/orders); false=read CSV for risk sizing

input group "Timeframe Alignment Weights"
input int    InputWeight_W1_BOS                = 16;
input int    InputWeight_D1_BOS                = 8;
input int    InputWeight_H4_BOS                = 4;
input int    InputWeight_M15_BOS               = 2;

#define InputTouchVolSlBufferPercentChart    InputEngulfSlBufferPercentChart
#define InputTouchVolMinSlPoints             InputEngulfMinSlPoints

input group "BOS SL/TP management"
input bool   InputEnableBosMoveSlAndTp = false; // disable trailing/moving SL & TP on BOS for now

const string H4_LQ_LOG_PREFIX = "h4_lq_v3";

//+------------------------------------------------------------------+
bool H4LqLoggingEnabled()
{
   return (!InputFastTesterMode && InputLogHuntEvents);
}

//+------------------------------------------------------------------+
bool H4LqChartDrawEnabled(const bool featureFlag = true)
{
   return (!InputFastTesterMode && featureFlag);
}

//+------------------------------------------------------------------+
bool ScoreLogWriteModeSkipsTrading()
{
   return InputScoreLogWriteCsv;
}

// --- trade sizing (3 swing-TP orders + 1 fixed 2R order; USD risk from score normalization) ---
const ulong    LQ_EXPERT_MAGIC                    = 940029;
const double   LQ_STOP_BUFFER_PERCENT_CHART       = 1.0;
const int      LQ_FVG_TRADE_MAX_M2_BAR_SHIFT      = 24;
const int      LQ_TP_COUNT                        = 3;

CTrade         g_trade;

// --- swing structs (plot_swing_h1_m5_copy.mq5) ---
struct Swing
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection; // 1 = up, -1 = down, 0 = unset
   int      keyLevelId;
};

struct SwingState
{
   Swing    currentSwingLeg;
   Swing    swingHistory[20];
   int      swingHistoryCount;
   double   priceAnchorLevel;
};

struct LiquidityPool
{
   double poolLowPrice;
   double poolHighPrice;
   bool   isSupplyPool;
};

struct M2SwingExtremePoint
{
   double   extremePrice;
   datetime legStartTime;
   datetime legEndTime;
};

// --- MTF SMC confluence (Phase 1–3) ---
enum ENUM_SMC_ZONE_TYPE
{
   ZONE_BULL_WEEKLY_FVG,
   ZONE_BULL_DAILY_FVG,
   ZONE_BULL_H4_FVG,
   ZONE_BULL_M15_FVG,
   ZONE_BULL_PROTECTED_DAILY_LOW,
   ZONE_BULL_PROTECTED_H4_LOW,
   ZONE_BULL_PROTECTED_M15_LOW,
   ZONE_BULL_SWING_W1_LOW,
   ZONE_BULL_SWING_DAILY_LOW,
   ZONE_BULL_SWING_H4_LOW,
   ZONE_BULL_SWING_M15_LOW,
   ZONE_BEAR_WEEKLY_FVG,
   ZONE_BEAR_DAILY_FVG,
   ZONE_BEAR_H4_FVG,
   ZONE_BEAR_M15_FVG,
   ZONE_BEAR_PROTECTED_DAILY_HIGH,
   ZONE_BEAR_PROTECTED_H4_HIGH,
   ZONE_BEAR_PROTECTED_M15_HIGH,
   ZONE_BEAR_SWING_W1_HIGH,
   ZONE_BEAR_SWING_DAILY_HIGH,
   ZONE_BEAR_SWING_H4_HIGH,
   ZONE_BEAR_SWING_M15_HIGH,
   SMC_ZONE_TYPE_COUNT
};

struct SMCZoneRecord
{
   ENUM_SMC_ZONE_TYPE type;
   double             topPrice;
   double             bottomPrice;
   bool               isActive;
   bool               isClustered;
   bool               isMitigated;
   bool               isBreached;
   bool               isExpired;
   datetime           zoneOriginBarTime;
};

struct SMCZoneMitigationLedgerEntry
{
   bool               inUse;
   ENUM_SMC_ZONE_TYPE type;
   double             topPrice;
   double             bottomPrice;
   bool               isMitigated;
   bool               isBreached;
   bool               isExpired;
   datetime           zoneOriginBarTime;
};

#define SMC_ZONE_LEDGER_CAPACITY              256
#define SMC_ZONE_MITIGATION_LEDGER_CAPACITY   (SMC_ZONE_LEDGER_CAPACITY * 2)

struct SMCMtfFvgInstance
{
   bool               inUse;
   ENUM_SMC_ZONE_TYPE type;
   ENUM_TIMEFRAMES    timeframe;
   double             topPrice;
   double             bottomPrice;
   bool               isMitigated;
   bool               isBreached;
   bool               isExpired;
   datetime           zoneOriginBarTime;
};

#define SMC_MTF_FVG_INSTANCE_CAPACITY 256

struct MTFSwingTracker
{
   ENUM_TIMEFRAMES timeframe;
   SwingState      swing;
   int             lastBosDirection;     // 1 bull BOS, -1 bear BOS, 0 none
   double          lastBosLevel;
   datetime        lastBosBarOpenTime;
   datetime        lastBrokenLegEndTime;
   double          lastBrokenLegHigh;
   double          lastBrokenLegLow;
};

#define BIAS_BULLISH  1
#define BIAS_BEARISH -1

struct ProfessionalBiasOverrideState
{
   int      overrideBias;     // current TF direction: 1 bull / -1 bear / 0 unset
   datetime overrideTime;     // TF bar open when direction last changed
};

ProfessionalBiasOverrideState g_profBiasOverrideW1;
ProfessionalBiasOverrideState g_profBiasOverrideD1;
ProfessionalBiasOverrideState g_profBiasOverrideH4;
ProfessionalBiasOverrideState g_profBiasOverrideM15;

#define LiquidityPoolCapacity 32

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
struct V2HuntSession
{
   bool     active;
   bool     h4HighWasBreached;
   double   h4BreachedLegLevelPrice;
   datetime h4BreachedLegEndTime;
   double   closeWhenH4LiquidityBreached;
   double   pathMinLowSinceH4Breach;
   double   pathMaxHighSinceH4Breach;
   double   impulseCloseExtremeSinceH4Breach;
   datetime sessionId;
   double   lastEngulfPairExtremeChecked; // bear: pair high; bull: pair low; 0=none yet
   bool     tradeOrdersActive;
   datetime ordersFvgFormationTime;
   bool     tradeIsBuy;
   double   tradeEntryPrice;
   double   tradeTp1Price;
   double   preEntryCancelTpLevel;
   bool     firstOppBosMgmtDone;
};

#define H4_LIQUIDITY_PIVOT_CAPACITY 600
#define H4_REPLAY_LEG_CAPACITY      512

struct H4LiquidityPivot
{
   double   levelPrice;
   datetime legEndTime;
   double   legHighPrice;
   double   legLowPrice;
   int      swingDirection; // 1 = up leg (high liquidity), -1 = down leg (low liquidity)
};

struct H4ReplayLeg
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection;
};

#ifdef H4_LQ_VOLUME_BREACH_ENABLED
#define H4_LEG_VOLUME_BREACH_CAPACITY 24

struct H4LegVolumeBreachRecord
{
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection;
   double   breachLevelPrice;
   datetime volumeBarOpenTime;
   bool     swept;
};

struct H4ActiveLegVolumeBreachTrack
{
   datetime legStartTime;
   int      swingDirection;
   datetime windowStartOpenTime;
   long     maxTickVolume;
   datetime maxVolumeBarOpenTime;
   double   breachLevelPrice;
};

H4LegVolumeBreachRecord      g_h4LegVolumeBreaches[H4_LEG_VOLUME_BREACH_CAPACITY];
int                          g_h4LegVolumeBreachCount = 0;
H4ActiveLegVolumeBreachTrack g_h4ActiveLegVolumeTrack;
#endif // H4_LQ_VOLUME_BREACH_ENABLED

SwingState     g_m2Swing;
LiquidityPool  g_liquidityPools[LiquidityPoolCapacity];
int            g_liquidityPoolCount = 0;
datetime g_lastM2BarOpen  = 0;

MTFSwingTracker g_mtfSwingW1;
MTFSwingTracker g_mtfSwingD1;
MTFSwingTracker g_mtfSwingH4;
MTFSwingTracker g_mtfSwingM15;
datetime        g_lastMtfBarOpenW1  = 0;
datetime        g_lastMtfBarOpenD1  = 0;
datetime        g_lastMtfBarOpenH4  = 0;
datetime        g_lastMtfBarOpenM15 = 0;
SMCZoneRecord   g_activeZones[SMC_ZONE_LEDGER_CAPACITY];
SMCZoneMitigationLedgerEntry g_zoneMitigationLedger[SMC_ZONE_MITIGATION_LEDGER_CAPACITY];
SMCMtfFvgInstance g_mtfFvgInstances[SMC_MTF_FVG_INSTANCE_CAPACITY];

#include "ConfluenceScoring.mqh"
#include "ScoreLogger.mqh"

V2HuntSession g_v2Hunts[V2_MAX_HUNT_SESSIONS];

H4LiquidityPivot g_h4DescHighPivots[H4_LIQUIDITY_PIVOT_CAPACITY];
int               g_h4DescHighPivotCount = 0;
H4LiquidityPivot g_h4AscLowPivots[H4_LIQUIDITY_PIVOT_CAPACITY];
int               g_h4AscLowPivotCount = 0;

int                 g_h4LastLoggedEffectiveBias    = 0;
bool                g_h4EffectiveBiasLogReady      = false;
bool     g_huntTradeOrdersActive         = false;
datetime g_huntOrdersFvgFormationTime    = 0;
bool     g_huntTradeIsBuy                = false;
double   g_huntTradeEntryPrice           = 0.0;
double   g_huntPreEntryCancelTpLevel      = 0.0;
string   g_huntTradeSessionCommentPrefix = "";
bool     g_huntFirstOppBosMgmtDone       = false;
datetime g_lastHuntPosMgmtM2BarTime      = 0;
datetime g_pendingEntryOrderExpiryDeadline = 0;
datetime g_pendingEntryOrderExpirySessionId  = 0;
bool     g_pendingEntryOrderExpiryTimerOn    = false;

void   PushLiquidityPoolFromClosedSwing(const double poolLowPrice, const double poolHighPrice,
                                        const bool isSupplyPool);
void   SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                     const double highPrice, const double lowPrice, const int lastClosedBarShift = 1);
void   SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice);
void   DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                         const double labelPrice, const bool isUplegSwingDirection, const int keyLevelIdForLabel);
bool   MtfSwingLegDrawEnabled(const ENUM_TIMEFRAMES timeframe);
color  MtfSwingLegLineColor(const ENUM_TIMEFRAMES timeframe);
void   MtfSwingLegObjectPrefixes(const ENUM_TIMEFRAMES timeframe, string &trendPrefix, string &labelPrefix);
void   DrawMtfClosedSwingLegVisual(const Swing &leg, const ENUM_TIMEFRAMES timeframe);
void   DeleteMtfSwingLegChartObjects();
void   SwingCloseH4Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                            const int lastClosedBarShift = 1);
void   SwingCloseH4ToHistory(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                              const int lastClosedBarShift = 1);

void   SwingCloseM2Leg(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                       const string chartObjectNamePrefix, const string labelPrefix,
                       const int lastClosedBarShift = 1);
void   UpdateM2LiveSwingLegVisualIf(const SwingState &swingState, const ENUM_TIMEFRAMES timeframe);
void   UpdateM2LiveSwingLegVisualOnTick();
void   UpdateM2SwingAnchorVisualRealtime(const SwingState &swingState);
void   ProcessSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int sh,
                               const color swingLineColor, const string trendPrefix, const string labelPrefix,
                               const bool replayOnly = false);
void   UpdateMTFSwings();
void   UpdateSMCZoneMatrix();
void   SMCResetMtfFvgInstances();
void   SMCUpdateMtfFvgInstancesMitigationForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCExpireMtfFvgInstancesForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCDeleteMtfFvgZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCDrawMtfFvgZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCClearActiveZonesForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCRefreshZonesForTimeframe(const ENUM_TIMEFRAMES timeframe, MTFSwingTracker &tracker,
                                      const bool legClosedThisBar);
void   SMCRegisterSwingZoneFromJustClosedLeg(const MTFSwingTracker &tracker,
                                                const ENUM_SMC_ZONE_TYPE bullSwingLowType,
                                                const ENUM_SMC_ZONE_TYPE bearSwingHighType,
                                                int &outRegisteredSlot);
void   SMCSeedSwingZonesFromHistory(const MTFSwingTracker &tracker,
                                       const ENUM_SMC_ZONE_TYPE bullSwingLowType,
                                       const ENUM_SMC_ZONE_TYPE bearSwingHighType);
void   SMCApplyZoneExitBiasAndMitigationForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCAdvanceZoneBreachLedgerOnBarClose(const ENUM_TIMEFRAMES timeframe);
void   SMCExpireZonesPastBarLimitForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCDeleteZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe);
string SMCZoneRectangleObjectNameForSlot(const int slotIndex);
void   SMCDeleteZoneRectangleForSlot(const int slotIndex);
void   SMCDrawZoneRectangleForSlot(const int slotIndex);
void   SMCDeactivateZoneLedgerSlot(const int slotIndex);
void   SMCDeleteAllZoneRectangleObjectsForSlot(const int slotIndex);
void   SMCCleanupMitigatedExpiredZoneChartObjectsForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCSyncZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCDeleteMtfFvgRectangleForInstance(const ENUM_SMC_ZONE_TYPE zoneType,
                                             const datetime originBarTime);
void   SMCMitigateOverlappingMtfFvgPeers(const int sourceIndex);
void   SMCSyncMtfFvgZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe);
void   SMCDrawZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe);
int    RegisterOrMergeZone(const ENUM_SMC_ZONE_TYPE newType, const double top, const double bottom,
                              const datetime originBarTime, const bool forceFreshZoneState);
void   WarmupMTFSwingsFromHistory();
bool   SMCGetMtfSwingTracker(const ENUM_TIMEFRAMES timeframe, MTFSwingTracker &tracker);
int    GetProfessionalBias(const ENUM_TIMEFRAMES timeframe);
void   ResetProfessionalBiasOverrideState();
void   ProfessionalBiasSetDirection(const ENUM_TIMEFRAMES timeframe, const int bias,
                                       const datetime setBarOpen);
void   SMCUpdateProfessionalBiasFromZoneBarClose(const ENUM_TIMEFRAMES timeframe);
int    GetZoneTimeframeStrength(const ENUM_SMC_ZONE_TYPE type);
void   SMCRegisterLiquidityHighZone(const ENUM_SMC_ZONE_TYPE type, const double level, const double buffer);
void   SMCRegisterLiquidityLowZone(const ENUM_SMC_ZONE_TYPE type, const double level, const double buffer);
void   SMCMapUnbrokenSwingZones(const MTFSwingTracker &tracker,
                                 const ENUM_SMC_ZONE_TYPE bullSwingLowType,
                                 const ENUM_SMC_ZONE_TYPE bearSwingHighType);
void   SMCUpdateActiveZonesMitigation();
void   SMCExpireZonesPastBarLimit();
double CalculateTotalTradeScore(const bool isBullishTrade, const double setupLow, const double setupHigh);
bool   V3ResolveSetupExtremesForZoneScoring(const bool isBuy, double &outSetupLow, double &outSetupHigh);
double CalculateSetupTradeScore(const bool isBullishTrade);
double GetRiskNormalizationScore();
bool   SetupScoreAllowsTradeEntry(const double setupScore);
double GetOptimizedLotSize(const double entryPrice, const double stopLoss, const double score,
                            const bool isBuy, const double riskUsdFraction = 1.0);
ENUM_TIMEFRAMES SMCZoneTypeToTimeframe(const ENUM_SMC_ZONE_TYPE type);
double SMCSwingLevelBufferForTimeframe(const ENUM_TIMEFRAMES timeframe);
double SMCSwingLevelBufferForZoneType(const ENUM_SMC_ZONE_TYPE type);
bool   CollectM2SwingExtremesBackwardFromFormation(const datetime formationTime, const int lookbackBars,
                                                    const int legDirection,
                                                    M2SwingExtremePoint &outPoints[], int &outPointCount);
bool   BuildTradeSwingGroupTakeProfits(const bool isBullishTrade, const datetime formationTime,
                                       const double entryPrice, const double stopLossPrice,
                                       double &outTakeProfitPrices[], int &outTakeProfitCount);
void   ProcessM2SwingStep();
void   WarmupM2SwingFromHistory();
#ifdef H4_LQ_VOLUME_BREACH_ENABLED
void   UpdateH4LegLiquidityBreachMemoryOnM2Bar();
bool   H4VolumeBreachLevelsMatch(const double levelA, const double levelB);
bool   H4IsVolumeBreachRecordSwept(const datetime legKey, const int swingDirection,
                                    const double breachLevel);
void   H4MarkVolumeBreachRecordSwept(const datetime legKey, const int swingDirection,
                                      const double breachLevel);
bool   WasH4VolumeBreachLevelViolatedSinceFormation(const int swingDirection,
                                                      const double breachLevel,
                                                      const datetime levelFormedOpenTime,
                                                      const double pointSize);
#endif // H4_LQ_VOLUME_BREACH_ENABLED

void   RefreshLiquidityHuntHud();
double ReferenceChartHeightForFairValueGapFilterM2();
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(InputEnableEngulfHuntAfterH4Breach && InputScoreLogWriteCsv)
      FlushScoreLogToFile();

   DeleteMtfSwingLegChartObjects();
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_ANCHOR, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_RECT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_LBL, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_SMC_ZONE_RECT, -1, -1);
   ObjectDelete(0, LQ_OBJ_HUNT_HUD);
   DeleteMtfDirectionHudObjects();
   ObjectsDeleteAll(0, LQ_OBJ_IMPULSE_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_RECALC_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_POINT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_RECT_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_LINE_PREFIX, -1, -1);

   if(g_pendingEntryOrderExpiryTimerOn)
   {
      EventKillTimer();
      g_pendingEntryOrderExpiryTimerOn = false;
   }
   ClearPendingEntryOrderExpiry();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   ProcessPendingEntryOrderExpiry();
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdateMTFSwings();
   if(H4LqChartDrawEnabled())
   {
      UpdateM2SwingAnchorVisualRealtime(g_m2Swing);
      UpdateM2LiveSwingLegVisualOnTick();
   }

   const datetime tM2 = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(tM2 != g_lastM2BarOpen)
   {
      g_lastM2BarOpen = tM2;
      if(InputEnableEngulfHuntAfterH4Breach)
         ProcessHuntEngulfingOnM2BarClose();
#ifdef H4_LQ_VOLUME_BREACH_ENABLED
      UpdateH4LegLiquidityBreachMemoryOnM2Bar();
      if(H4LqChartDrawEnabled(InputDrawMtfSwingLegsH4))
         RebuildAllH4VolumeBreachMarkers();
#endif
      ProcessM2SwingStep();
      ManageHuntOpenPositionsOnM2BarClose();
      if(H4LqChartDrawEnabled(InputShowLiquidityHuntHud))
         RefreshLiquidityHuntHud();
   }
}

//+------------------------------------------------------------------+
void WarmupM2SwingFromHistory()
{
   if(InputM2SwingWarmupBars <= 0)
      return;
   const int bars = iBars(_Symbol, InputM2NarrativeTimeframe);
   const int minNeed = 8;
   if(bars < minNeed)
      return;
   const int n = (int)MathMin(bars - 2, InputM2SwingWarmupBars);
   if(n < 1)
      return;
   for(int k = n; k >= 1; k--)
   {
      ProcessSwingStepAtShift(g_m2Swing, InputM2NarrativeTimeframe, k, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL,
                              true);
   }
}

//+------------------------------------------------------------------+
void PushLiquidityPoolFromClosedSwing(const double poolLowPrice, const double poolHighPrice,
                                      const bool isSupplyPool)
{
   if(poolLowPrice >= poolHighPrice)
      return;

   if(g_liquidityPoolCount < LiquidityPoolCapacity)
   {
      g_liquidityPools[g_liquidityPoolCount].poolLowPrice  = poolLowPrice;
      g_liquidityPools[g_liquidityPoolCount].poolHighPrice = poolHighPrice;
      g_liquidityPools[g_liquidityPoolCount].isSupplyPool   = isSupplyPool;
      g_liquidityPoolCount++;
   }
   else
   {
      for(int poolShiftIndex = 1; poolShiftIndex < LiquidityPoolCapacity; poolShiftIndex++)
         g_liquidityPools[poolShiftIndex - 1] = g_liquidityPools[poolShiftIndex];
      g_liquidityPools[LiquidityPoolCapacity - 1].poolLowPrice  = poolLowPrice;
      g_liquidityPools[LiquidityPoolCapacity - 1].poolHighPrice = poolHighPrice;
      g_liquidityPools[LiquidityPoolCapacity - 1].isSupplyPool  = isSupplyPool;
   }
}

//+------------------------------------------------------------------+
void SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                   const double highPrice, const double lowPrice, const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.swingDirection = swingDirection;
   swingState.currentSwingLeg.legHighPrice   = highPrice;
   swingState.currentSwingLeg.legLowPrice    = lowPrice;
   swingState.currentSwingLeg.keyLevelId     = 0;
   swingState.currentSwingLeg.legStartTime   = iTime(_Symbol, timeframe, lastClosedBarShift);
}

//+------------------------------------------------------------------+
void SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice)
{
   if(highPrice > swingState.currentSwingLeg.legHighPrice)
      swingState.currentSwingLeg.legHighPrice = highPrice;
   if(lowPrice < swingState.currentSwingLeg.legLowPrice)
      swingState.currentSwingLeg.legLowPrice = lowPrice;
}

//+------------------------------------------------------------------+
void DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                       const double labelPrice, const bool isUplegSwingDirection, const int keyLevelIdForLabel)
{
   const string chartObjectName = chartObjectNamePrefix + IntegerToString((long)labelBarTime);
   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);

   const double symbolPointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double labelVerticalOffset =
      isUplegSwingDirection ? (labelPrice + symbolPointSize * 8.0) : (labelPrice - symbolPointSize * 8.0);

   if(!ObjectCreate(0, chartObjectName, OBJ_TEXT, 0, labelBarTime, labelVerticalOffset))
      return;

   string txt = isUplegSwingDirection ? "High" : "Low";
   if(keyLevelIdForLabel > 0)
      txt = StringFormat("%s #%d", txt, keyLevelIdForLabel);

   ObjectSetString(0, chartObjectName, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, isUplegSwingDirection ? clrDodgerBlue : clrOrange);
   ObjectSetInteger(0, chartObjectName, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, chartObjectName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, chartObjectName, OBJPROP_ANCHOR,
                    isUplegSwingDirection ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void DeleteMtfSwingLegChartObjects()
{
   ObjectsDeleteAll(0, PFX_MTF_W1_TR, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_W1_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_D1_TR, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_D1_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_H4_TR, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_H4_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_M15_TR, -1, -1);
   ObjectsDeleteAll(0, PFX_MTF_M15_LBL, -1, -1);
}

//+------------------------------------------------------------------+
bool MtfSwingLegDrawEnabled(const ENUM_TIMEFRAMES timeframe)
{
   if(!H4LqChartDrawEnabled())
      return false;
   switch(timeframe)
   {
      case PERIOD_W1:  return InputDrawMtfSwingLegsW1;
      case PERIOD_D1:  return InputDrawMtfSwingLegsD1;
      case PERIOD_H4:  return InputDrawMtfSwingLegsH4;
      case PERIOD_M15: return InputDrawMtfSwingLegsM15;
   }
   return false;
}

//+------------------------------------------------------------------+
color MtfSwingLegLineColor(const ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_W1:  return InputMtfSwingLegColorW1;
      case PERIOD_D1:  return InputMtfSwingLegColorD1;
      case PERIOD_H4:  return InputMtfSwingLegColorH4;
      case PERIOD_M15: return InputMtfSwingLegColorM15;
   }
   return clrSilver;
}

//+------------------------------------------------------------------+
void MtfSwingLegObjectPrefixes(const ENUM_TIMEFRAMES timeframe, string &trendPrefix, string &labelPrefix)
{
   trendPrefix = "";
   labelPrefix = "";
   switch(timeframe)
   {
      case PERIOD_W1:
         trendPrefix = PFX_MTF_W1_TR;
         labelPrefix = PFX_MTF_W1_LBL;
         break;
      case PERIOD_D1:
         trendPrefix = PFX_MTF_D1_TR;
         labelPrefix = PFX_MTF_D1_LBL;
         break;
      case PERIOD_H4:
         trendPrefix = PFX_MTF_H4_TR;
         labelPrefix = PFX_MTF_H4_LBL;
         break;
      case PERIOD_M15:
         trendPrefix = PFX_MTF_M15_TR;
         labelPrefix = PFX_MTF_M15_LBL;
         break;
   }
}

//+------------------------------------------------------------------+
void DrawMtfClosedSwingLegVisual(const Swing &leg, const ENUM_TIMEFRAMES timeframe)
{
   if(!MtfSwingLegDrawEnabled(timeframe) || leg.swingDirection == 0 || leg.legStartTime == 0 || leg.legEndTime == 0)
      return;

   string trendPrefix = "";
   string labelPrefix = "";
   MtfSwingLegObjectPrefixes(timeframe, trendPrefix, labelPrefix);
   if(trendPrefix == "" || labelPrefix == "")
      return;

   const string chartObjectName =
      trendPrefix + IntegerToString((long)leg.legStartTime) + "_" + IntegerToString((long)leg.legEndTime);

   double trendLineStartPrice;
   double trendLineEndPrice;
   if(leg.swingDirection == 1)
   {
      trendLineStartPrice = leg.legLowPrice;
      trendLineEndPrice   = leg.legHighPrice;
   }
   else
   {
      trendLineStartPrice = leg.legHighPrice;
      trendLineEndPrice   = leg.legLowPrice;
   }

   datetime tRightDraw = leg.legEndTime;
   if(tRightDraw <= leg.legStartTime)
      tRightDraw = leg.legStartTime + (datetime)PeriodSeconds(timeframe);

   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);

   if(ObjectCreate(0, chartObjectName, OBJ_TREND, 0, leg.legStartTime, trendLineStartPrice,
                   tRightDraw, trendLineEndPrice))
   {
      ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, MtfSwingLegLineColor(timeframe));
      ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, chartObjectName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, chartObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }

   const bool isUplegSwingDirection = (leg.swingDirection == 1);
   DrawSwingLegLabel(labelPrefix, leg.legEndTime, trendLineEndPrice, isUplegSwingDirection, 0);
}

//+------------------------------------------------------------------+
string M2SwingCompletedTrendObjectName(const datetime legStartTime, const datetime legEndTime)
{
   return PFX_M2_TREND + IntegerToString((long)legStartTime) + "_" + IntegerToString((long)legEndTime);
}

//+------------------------------------------------------------------+
bool SetM2SwingTrendSegment(const string objectName, const datetime timeStart, const double priceStart,
                            const datetime timeEnd, const double priceEnd, const color lineColor,
                            const bool rayRight)
{
   if(timeStart == 0 || timeEnd == 0)
      return false;

   datetime t1 = timeStart;
   datetime t2 = timeEnd;
   if(t2 <= t1)
      t2 = t1 + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);

   if(ObjectFind(0, objectName) < 0)
   {
      if(!ObjectCreate(0, objectName, OBJ_TREND, 0, t1, priceStart, t2, priceEnd))
         return false;
      ObjectSetInteger(0, objectName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, objectName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objectName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, objectName, OBJPROP_RAY_RIGHT, rayRight);
      ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objectName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, objectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
   else
   {
      ObjectSetInteger(0, objectName, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, objectName, OBJPROP_PRICE, 0, priceStart);
      ObjectSetInteger(0, objectName, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, objectName, OBJPROP_PRICE, 1, priceEnd);
      ObjectSetInteger(0, objectName, OBJPROP_COLOR, lineColor);
      ObjectSetInteger(0, objectName, OBJPROP_RAY_RIGHT, rayRight);
   }
   return true;
}

//+------------------------------------------------------------------+
// plot_swing_h1_m5_copy SwingClose â€” M2 only (no H1 keyLevelId).
//+------------------------------------------------------------------+
void SwingCloseM2Leg(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                     const string chartObjectNamePrefix, const string labelPrefix,
                     const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.keyLevelId = 0;

   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   if(timeframe == InputM2NarrativeTimeframe && H4LqChartDrawEnabled(InputDrawM2SwingLegs))
      ObjectDelete(0, PFX_M2_TREND + "LIVE");

   const string chartObjectName =
      M2SwingCompletedTrendObjectName(swingState.currentSwingLeg.legStartTime,
                                      swingState.currentSwingLeg.legEndTime);

   double trendLineStartPrice;
   double trendLineEndPrice;
   if(swingState.currentSwingLeg.swingDirection == 1)
   {
      trendLineStartPrice = swingState.currentSwingLeg.legLowPrice;
      trendLineEndPrice   = swingState.currentSwingLeg.legHighPrice;
   }
   else
   {
      trendLineStartPrice = swingState.currentSwingLeg.legHighPrice;
      trendLineEndPrice   = swingState.currentSwingLeg.legLowPrice;
   }

   if(H4LqChartDrawEnabled(InputDrawM2SwingLegs))
   {
      SetM2SwingTrendSegment(chartObjectName, swingState.currentSwingLeg.legStartTime, trendLineStartPrice,
                             swingState.currentSwingLeg.legEndTime, trendLineEndPrice, swingLineColor, false);

      const bool isUplegSwingDirection = (swingState.currentSwingLeg.swingDirection == 1);
      DrawSwingLegLabel(labelPrefix, swingState.currentSwingLeg.legEndTime, trendLineEndPrice,
                        isUplegSwingDirection, swingState.currentSwingLeg.keyLevelId);
   }

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
void UpdateM2LiveSwingLegVisualCore(const SwingState &swingState, const double legHighPrice,
                                    const double legLowPrice)
{
   if(!H4LqChartDrawEnabled(InputDrawM2SwingLegs) || swingState.currentSwingLeg.swingDirection == 0)
      return;

   datetime tEnd = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(tEnd <= swingState.currentSwingLeg.legStartTime)
      tEnd = swingState.currentSwingLeg.legStartTime + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);

   double trendLineStartPrice;
   double trendLineEndPrice;
   if(swingState.currentSwingLeg.swingDirection == 1)
   {
      trendLineStartPrice = legLowPrice;
      trendLineEndPrice   = legHighPrice;
   }
   else
   {
      trendLineStartPrice = legHighPrice;
      trendLineEndPrice   = legLowPrice;
   }

   SetM2SwingTrendSegment(PFX_M2_TREND + "LIVE", swingState.currentSwingLeg.legStartTime,
                          trendLineStartPrice, tEnd, trendLineEndPrice, InputM2SwingLineColor, false);
}

//+------------------------------------------------------------------+
void UpdateM2LiveSwingLegVisualIf(const SwingState &swingState, const ENUM_TIMEFRAMES timeframe)
{
   if(timeframe != InputM2NarrativeTimeframe)
      return;
   UpdateM2LiveSwingLegVisualCore(swingState, swingState.currentSwingLeg.legHighPrice,
                                  swingState.currentSwingLeg.legLowPrice);
}

//+------------------------------------------------------------------+
void UpdateM2LiveSwingLegVisualOnTick()
{
   if(g_m2Swing.currentSwingLeg.swingDirection == 0)
      return;

   double effHigh = g_m2Swing.currentSwingLeg.legHighPrice;
   double effLow  = g_m2Swing.currentSwingLeg.legLowPrice;
   const double barHigh = iHigh(_Symbol, InputM2NarrativeTimeframe, 0);
   const double barLow  = iLow(_Symbol, InputM2NarrativeTimeframe, 0);
   if(barHigh > effHigh)
      effHigh = barHigh;
   if(barLow < effLow)
      effLow = barLow;

   UpdateM2LiveSwingLegVisualCore(g_m2Swing, effHigh, effLow);
}

//+------------------------------------------------------------------+
//| Realtime segment at priceAnchorLevel â€” close cross vs this flips the M2 leg. |
//+------------------------------------------------------------------+
void UpdateM2SwingAnchorVisualRealtime(const SwingState &swingState)
{
   const string liveName = PFX_M2_ANCHOR + "LIVE";

   if(!H4LqChartDrawEnabled(InputDrawM2SwingAnchorLevel) ||
      swingState.currentSwingLeg.swingDirection == 0 ||
      swingState.priceAnchorLevel <= 0.0)
   {
      ObjectDelete(0, liveName);
      return;
   }

   const datetime tStart = swingState.currentSwingLeg.legStartTime;
   datetime       tEnd   = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(tEnd <= tStart)
      tEnd = tStart + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);

   const double anchorPrice = swingState.priceAnchorLevel;

   if(ObjectFind(0, liveName) < 0)
   {
      if(!ObjectCreate(0, liveName, OBJ_TREND, 0, tStart, anchorPrice, tEnd, anchorPrice))
         return;
      ObjectSetInteger(0, liveName, OBJPROP_COLOR, InputM2SwingAnchorColor);
      ObjectSetInteger(0, liveName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, liveName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, liveName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, liveName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, liveName, OBJPROP_BACK, false);
      ObjectSetInteger(0, liveName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, liveName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
   else
   {
      ObjectSetInteger(0, liveName, OBJPROP_TIME, 0, tStart);
      ObjectSetDouble(0, liveName, OBJPROP_PRICE, 0, anchorPrice);
      ObjectSetInteger(0, liveName, OBJPROP_TIME, 1, tEnd);
      ObjectSetDouble(0, liveName, OBJPROP_PRICE, 1, anchorPrice);
      ObjectSetInteger(0, liveName, OBJPROP_COLOR, InputM2SwingAnchorColor);
   }
}

//+------------------------------------------------------------------+
// plot_swing_h1_m5_copy ProcessSwingStepAtShift (M2 timeframe).
//+------------------------------------------------------------------+
void ProcessSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int sh,
                             const color swingLineColor, const string trendPrefix, const string labelPrefix,
                             const bool replayOnly)
{
   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, sh);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, sh);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, sh);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, sh);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);
   // Anchor tolerance: M2 = body vs 0.2Ã— prior avg; H4 = wick AND body vs 0.5Ã— prior avg.
   const double lastClosedBarBodyRange = MathAbs(lastClosedBarClose - lastClosedBarOpen);
   const double lastClosedBarWickRange  = lastClosedBarHigh - lastClosedBarLow;

   if(swingState.currentSwingLeg.swingDirection == 0)
   {
      if(candleDirection == 0)
         return;
      SwingStartNew(swingState, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow, sh);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      if(!replayOnly)
      {
         UpdateM2LiveSwingLegVisualIf(swingState, timeframe);
         UpdateM2SwingAnchorVisualRealtime(swingState);
      }
      return;
   }

   double sumRangeFivePriorBars = 0.0;
   const int barsTotal = iBars(_Symbol, timeframe);
   int       rangeBarCount = 0;
   for(int barShiftIndex = sh + 1; barShiftIndex <= sh + 5; barShiftIndex++)
   {
      if(barShiftIndex >= barsTotal)
         break;
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, barShiftIndex) - iLow(_Symbol, timeframe, barShiftIndex));
      rangeBarCount++;
   }
   const double averageRangeFiveBars = (rangeBarCount > 0) ? sumRangeFivePriorBars / (double)rangeBarCount : 0.0;

   const double anchorDecentMovementMultiplier = 0.2; // M2 body vs prior 5-bar avg
   const double minDecentRange = averageRangeFiveBars * anchorDecentMovementMultiplier;
   const bool isDecentMovement =
      (timeframe == InputM2NarrativeTimeframe)
      ? (lastClosedBarBodyRange > minDecentRange)
      : (lastClosedBarWickRange > minDecentRange && lastClosedBarBodyRange > minDecentRange);

   const double anchorForFlipCheck = swingState.priceAnchorLevel;
   int nextSwingDirection = swingState.currentSwingLeg.swingDirection;
   if(swingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < anchorForFlipCheck)
      nextSwingDirection = -1;
   else if(swingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > anchorForFlipCheck)
      nextSwingDirection = 1;

   if(nextSwingDirection == swingState.currentSwingLeg.swingDirection)
   {
      if(isDecentMovement && candleDirection == swingState.currentSwingLeg.swingDirection)
         swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);
      if(!replayOnly)
      {
         UpdateM2LiveSwingLegVisualIf(swingState, timeframe);
         UpdateM2SwingAnchorVisualRealtime(swingState);
      }
   }
   else
   {
      const int closingLegDirection = swingState.currentSwingLeg.swingDirection;

      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

      SwingCloseM2Leg(swingState, timeframe, swingLineColor, trendPrefix, labelPrefix, sh);

      Swing closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
      double newSwingLegHigh = lastClosedBarHigh;
      double newSwingLegLow  = lastClosedBarLow;
      if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
         newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
      else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
         newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

      SwingStartNew(swingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow, sh);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      if(!replayOnly)
      {
         UpdateM2LiveSwingLegVisualIf(swingState, timeframe);
         UpdateM2SwingAnchorVisualRealtime(swingState);
      }
   }
}

//+------------------------------------------------------------------+
void ProcessM2SwingStep()
{
   ProcessSwingStepAtShift(g_m2Swing, InputM2NarrativeTimeframe, 1, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL);
}

//+------------------------------------------------------------------+
void SwingCloseH4Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                          const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   const double poolLowPrice  = swingState.currentSwingLeg.legLowPrice;
   const double poolHighPrice = swingState.currentSwingLeg.legHighPrice;
   const bool   isSupplyPool  = (swingState.currentSwingLeg.swingDirection == 1);
   PushLiquidityPoolFromClosedSwing(poolLowPrice, poolHighPrice, isSupplyPool);

   if(lastClosedBarShift == 1)
      DrawMtfClosedSwingLegVisual(swingState.currentSwingLeg, timeframe);

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
void SwingCloseH4ToHistory(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                            const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   if(lastClosedBarShift == 1)
      DrawMtfClosedSwingLegVisual(swingState.currentSwingLeg, timeframe);

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
void RefreshLiquidityHuntHud()
{
   if(!H4LqChartDrawEnabled(InputShowLiquidityHuntHud))
   {
      ObjectDelete(0, LQ_OBJ_HUNT_HUD);
      return;
   }
   if(ObjectFind(0, LQ_OBJ_HUNT_HUD) < 0)
   {
      if(!ObjectCreate(0, LQ_OBJ_HUNT_HUD, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_XDISTANCE, 6);
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_YDISTANCE, 18);
      ObjectSetString(0, LQ_OBJ_HUNT_HUD, OBJPROP_FONT, "Tahoma");
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_HIDDEN, false);
   }
   const string txt = InputEnableEngulfHuntAfterH4Breach ? "v3: engulf scan ON" : "v3: engulf scan OFF";
   ObjectSetString(0, LQ_OBJ_HUNT_HUD, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_COLOR,
                    InputEnableEngulfHuntAfterH4Breach ? clrLime : clrSilver);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
string H4TradeDirectionBiasText(const int bias)
{
   if(bias == 1)
      return "bull";
   if(bias == -1)
      return "bear";
   return "neutral";
}

//+------------------------------------------------------------------+
void LogH4TradeDirectionBiasIfChanged()
{
   if(!H4LqLoggingEnabled() || !InputEnableH4BosTradeDirectionBias)
      return;

   const int bias = GetH4TradeDirectionBias();
   if(!g_h4EffectiveBiasLogReady)
   {
      g_h4LastLoggedEffectiveBias = bias;
      g_h4EffectiveBiasLogReady   = true;
      return;
   }

   if(bias == g_h4LastLoggedEffectiveBias)
      return;

   MTFSwingTracker h4Tracker;
   string bosDetail = "no BOS on tracker";
   if(SMCGetMtfSwingTracker(PERIOD_H4, h4Tracker) && h4Tracker.lastBosBarOpenTime > 0)
   {
      bosDetail = StringFormat("%s BOS bar=%s lvl=%.5f",
                               h4Tracker.lastBosDirection == 1 ? "bull" : "bear",
                               TimeToString(h4Tracker.lastBosBarOpenTime, TIME_DATE | TIME_MINUTES),
                               h4Tracker.lastBosLevel);
   }

   LogHuntEvent("H4_BIAS",
                StringFormat("%s -> %s (SMC H4 professional bias; %s)",
                             H4TradeDirectionBiasText(g_h4LastLoggedEffectiveBias),
                             H4TradeDirectionBiasText(bias),
                             bosDetail));
   g_h4LastLoggedEffectiveBias = bias;
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForTimeframeBarCount(const ENUM_TIMEFRAMES timeframe,
                                                 const int barCount)
{
   if(barCount < 1 || timeframe == PERIOD_CURRENT)
      return 0.0;

   const int totalBars = iBars(_Symbol, timeframe);
   if(totalBars < 4)
      return 0.0;

   const int useBarCount = (int)MathMin((double)barCount, (double)(totalBars - 1));
   if(useBarCount < 1)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = 1; barShiftIndex <= useBarCount; barShiftIndex++)
   {
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, timeframe, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, timeframe, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForM2BarCount(const int barCount)
{
   return ReferenceChartHeightForTimeframeBarCount(InputM2NarrativeTimeframe, barCount);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForH4BarCount(const int barCount)
{
   return ReferenceChartHeightForTimeframeBarCount(PERIOD_H4, barCount);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForH4BreachBuffer()
{
   return ReferenceChartHeightForH4BarCount(InputH4BreachBufferChartBarCount);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForM2BarCountFromShift(const int newestBarShift, const int barCount)
{
   if(barCount < 1 || newestBarShift < 0)
      return 0.0;

   const int totalBars = iBars(_Symbol, InputM2NarrativeTimeframe);
   if(totalBars < 4)
      return 0.0;

   const int startShift = newestBarShift;
   const int endShift   = newestBarShift + barCount;
   if(startShift >= totalBars)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = startShift; barShiftIndex <= endShift; barShiftIndex++)
   {
      if(barShiftIndex >= totalBars)
         break;
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, InputM2NarrativeTimeframe, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, InputM2NarrativeTimeframe, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

//+------------------------------------------------------------------+
void SortM2SwingExtremesNewestFirst(M2SwingExtremePoint &points[], const int pointCount)
{
   for(int i = 0; i < pointCount - 1; i++)
   {
      for(int j = i + 1; j < pointCount; j++)
      {
         if(points[j].legEndTime > points[i].legEndTime)
         {
            const M2SwingExtremePoint tmp = points[i];
            points[i] = points[j];
            points[j] = tmp;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool M2SwingExtremePointExists(const M2SwingExtremePoint &points[], const int pointCount,
                               const datetime legEndTime)
{
   for(int i = 0; i < pointCount; i++)
   {
      if(points[i].legEndTime == legEndTime)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void AppendM2SwingExtremePoint(M2SwingExtremePoint &points[], int &pointCount,
                               const double extremePrice, const datetime legStartTime,
                               const datetime legEndTime)
{
   if(legEndTime == 0 || M2SwingExtremePointExists(points, pointCount, legEndTime))
      return;

   const int newIdx = pointCount;
   ArrayResize(points, pointCount + 1);
   points[newIdx].extremePrice = extremePrice;
   points[newIdx].legStartTime = legStartTime;
   points[newIdx].legEndTime   = legEndTime;
   pointCount++;
}

//+------------------------------------------------------------------+
void TryAppendM2SwingExtremeFromClosedLeg(const Swing &closedLeg, const int legDirection,
                                           const int windowNewestShift, const int windowOldestShift,
                                           M2SwingExtremePoint &outPoints[], int &outPointCount)
{
   if(closedLeg.swingDirection != legDirection || closedLeg.legEndTime == 0)
      return;

   int legEndShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, closedLeg.legEndTime, true);
   if(legEndShift < 0)
      legEndShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, closedLeg.legEndTime, false);
   if(legEndShift < 0 || legEndShift < windowNewestShift || legEndShift > windowOldestShift)
      return;

   const double extremePrice = (legDirection == 1) ? closedLeg.legHighPrice : closedLeg.legLowPrice;
   AppendM2SwingExtremePoint(outPoints, outPointCount, extremePrice,
                             closedLeg.legStartTime, closedLeg.legEndTime);
}

//+------------------------------------------------------------------+
void CollectM2SwingExtremesFromSwingHistory(const SwingState &swingState, const int formationShift,
                                             const int lookbackBars, const int legDirection,
                                             M2SwingExtremePoint &outPoints[], int &outPointCount)
{
   const int windowNewestShift = MathMax(formationShift, 1);
   const int windowOldestShift = formationShift + lookbackBars;

   for(int historyIndex = 0; historyIndex < swingState.swingHistoryCount; historyIndex++)
   {
      TryAppendM2SwingExtremeFromClosedLeg(swingState.swingHistory[historyIndex], legDirection,
                                           windowNewestShift, windowOldestShift,
                                           outPoints, outPointCount);
   }
}

//+------------------------------------------------------------------+
//| Same M2 swing legs already drawn on chart (PFX_M2_TREND) â€” optional supplement when draw is on. |
//+------------------------------------------------------------------+
void CollectM2SwingExtremesFromDrawnTrendLines(const int formationShift, const int lookbackBars,
                                               const int legDirection,
                                               M2SwingExtremePoint &outPoints[], int &outPointCount)
{
   const int windowNewestShift = MathMax(formationShift, 1);
   const int windowOldestShift = formationShift + lookbackBars;

   const int objectTotal = ObjectsTotal(0, 0, OBJ_TREND);
   for(int objIndex = objectTotal - 1; objIndex >= 0; objIndex--)
   {
      const string objName = ObjectName(0, objIndex, 0, OBJ_TREND);
      if(StringFind(objName, PFX_M2_TREND) != 0)
         continue;
      if(StringFind(objName, "LIVE") >= 0)
         continue;

      const datetime legEndTime   = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 1);
      const datetime legStartTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
      const int      legEndShift  = iBarShift(_Symbol, InputM2NarrativeTimeframe, legEndTime, true);
      if(legEndShift < 0 || legEndShift < windowNewestShift || legEndShift > windowOldestShift)
         continue;

      const double priceStart = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
      const double priceEnd   = ObjectGetDouble(0, objName, OBJPROP_PRICE, 1);

      if(legDirection == 1)
      {
         if(priceEnd <= priceStart)
            continue;
         AppendM2SwingExtremePoint(outPoints, outPointCount, priceEnd, legStartTime, legEndTime);
      }
      else
      {
         if(priceEnd >= priceStart)
            continue;
         AppendM2SwingExtremePoint(outPoints, outPointCount, priceEnd, legStartTime, legEndTime);
      }
   }
}

//+------------------------------------------------------------------+
//| From FVG/order formation bar: replay M2 swings backward up to lookbackBars; |
//| collect completed up-leg highs (bull) or down-leg lows (bear), newest first. |
//+------------------------------------------------------------------+
bool CollectM2SwingExtremesBackwardFromFormation(const datetime formationTime, const int lookbackBars,
                                                  const int legDirection,
                                                  M2SwingExtremePoint &outPoints[], int &outPointCount)
{
   outPointCount = 0;
   ArrayResize(outPoints, 0);
   if(formationTime == 0 || lookbackBars < 1 || (legDirection != 1 && legDirection != -1))
      return false;

   int formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, true);
   if(formationShift < 0)
      formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, false);
   if(formationShift < 0)
      return false;

   const int barsTotal = iBars(_Symbol, InputM2NarrativeTimeframe);
   if(barsTotal < 4)
      return false;

   const int windowNewestShift = MathMax(formationShift, 1);
   const int windowOldestShift = formationShift + lookbackBars;
   const int startReplayShift  = (int)MathMin((double)windowOldestShift, (double)(barsTotal - 2));
   const int endReplayShift    = windowNewestShift;
   if(startReplayShift < endReplayShift)
      return false;

   const int swingWarmupBars = MathMax(120, lookbackBars);
   const int replayFromShift = (int)MathMin((double)(startReplayShift + swingWarmupBars),
                                            (double)(barsTotal - 2));

   SwingState replayState;
   ZeroMemory(replayState);

   for(int barShift = replayFromShift; barShift >= endReplayShift; barShift--)
   {
      const int newestIdxBefore = replayState.swingHistoryCount - 1;
      const datetime newestEndBefore = (newestIdxBefore >= 0)
                                       ? replayState.swingHistory[newestIdxBefore].legEndTime
                                       : 0;

      ProcessSwingStepAtShift(replayState, InputM2NarrativeTimeframe, barShift,
                              InputM2SwingLineColor, "", "", true);

      if(barShift > startReplayShift)
         continue;

      const int newestIdxAfter = replayState.swingHistoryCount - 1;
      if(newestIdxAfter < 0)
         continue;

      const datetime newestEndAfter = replayState.swingHistory[newestIdxAfter].legEndTime;
      if(newestEndAfter == 0 || newestEndAfter == newestEndBefore)
         continue;

      TryAppendM2SwingExtremeFromClosedLeg(replayState.swingHistory[newestIdxAfter], legDirection,
                                           windowNewestShift, windowOldestShift,
                                           outPoints, outPointCount);
   }

   CollectM2SwingExtremesFromSwingHistory(g_m2Swing, formationShift, lookbackBars, legDirection,
                                        outPoints, outPointCount);

   if(H4LqChartDrawEnabled(InputDrawM2SwingLegs))
   {
      CollectM2SwingExtremesFromDrawnTrendLines(formationShift, lookbackBars, legDirection,
                                                outPoints, outPointCount);
   }

   if(outPointCount < 1)
      return false;

   SortM2SwingExtremesNewestFirst(outPoints, outPointCount);
   return true;
}

//+------------------------------------------------------------------+
bool SwingGroupLineMeetsMinRiskReward(const bool isBuy, const double entryPrice,
                                      const double stopLossPrice, const double tpLinePrice,
                                      const double minRewardToRisk)
{
   if(minRewardToRisk <= 0.0 || entryPrice <= 0.0 || stopLossPrice <= 0.0 || tpLinePrice <= 0.0)
      return false;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double risk      = MathAbs(entryPrice - stopLossPrice);
   if(risk <= pointSize)
      return false;

   const double reward = isBuy ? (tpLinePrice - entryPrice) : (entryPrice - tpLinePrice);
   if(reward <= pointSize)
      return false;

   return (reward / risk >= minRewardToRisk);
}

//+------------------------------------------------------------------+
void AppendUniqueTakeProfitLevel(double &tpPrices[], int &tpCount, const double tpPrice)
{
   const double normalized = NormalizeDouble(tpPrice, _Digits);
   for(int i = 0; i < tpCount; i++)
   {
      if(MathAbs(tpPrices[i] - normalized) <= SymbolInfoDouble(_Symbol, SYMBOL_POINT))
         return;
   }

   ArrayResize(tpPrices, tpCount + 1);
   tpPrices[tpCount] = normalized;
   tpCount++;
}

//+------------------------------------------------------------------+
void SortTakeProfitLevelsNearestFirst(const bool isBuy, double &tpPrices[], const int tpCount)
{
   for(int i = 0; i < tpCount - 1; i++)
   {
      for(int j = i + 1; j < tpCount; j++)
      {
         const bool swap =
            isBuy ? (tpPrices[j] < tpPrices[i]) : (tpPrices[j] > tpPrices[i]);
         if(swap)
         {
            const double tmp = tpPrices[i];
            tpPrices[i] = tpPrices[j];
            tpPrices[j] = tmp;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool TakeProfitLevelWithinProximityBand(const double tpLinePrice,
                                        const double &existingTpPrices[],
                                        const int existingTpCount,
                                        const double proximityBand)
{
   if(proximityBand <= 0.0 || existingTpCount < 1)
      return false;

   for(int i = 0; i < existingTpCount; i++)
   {
      if(MathAbs(existingTpPrices[i] - tpLinePrice) <= proximityBand)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int AppendIndividualSwingTakeProfitLevels(const bool isBuy, const double entryPrice,
                                          const double stopLossPrice,
                                          const M2SwingExtremePoint &points[], const int pointCount,
                                          const double frontRunOffset, const double proximityBand,
                                          double &outTakeProfitPrices[], int &outTakeProfitCount,
                                          const int maxTakeProfitCount, int &outSkippedRewardToRisk,
                                          int &outSkippedProximity)
{
   outSkippedRewardToRisk = 0;
   outSkippedProximity    = 0;
   int added = 0;
   for(int i = 0; i < pointCount && outTakeProfitCount < maxTakeProfitCount; i++)
   {
      double linePrice = points[i].extremePrice;
      if(frontRunOffset > 0.0)
      {
         if(isBuy)
            linePrice -= frontRunOffset;
         else
            linePrice += frontRunOffset;
      }

      if(TakeProfitLevelWithinProximityBand(linePrice, outTakeProfitPrices, outTakeProfitCount,
                                            proximityBand))
      {
         outSkippedProximity++;
         continue;
      }

      if(!SwingGroupLineMeetsMinRiskReward(isBuy, entryPrice, stopLossPrice, linePrice,
                                           InputTradeSwingTpMinRewardToRisk))
      {
         outSkippedRewardToRisk++;
         continue;
      }

      const int beforeCount = outTakeProfitCount;
      AppendUniqueTakeProfitLevel(outTakeProfitPrices, outTakeProfitCount, linePrice);
      if(outTakeProfitCount > beforeCount)
         added++;
   }
   return added;
}

//+------------------------------------------------------------------+
//| Group swing extremes → qualifying line TPs (min R:R) + optional chart zones. |
//| Falls back to individual swing levels when cluster count < LQ_TP_COUNT.        |
//+------------------------------------------------------------------+
bool BuildTradeSwingGroupTakeProfits(const bool isBullishTrade, const datetime formationTime,
                                     const double entryPrice, const double stopLossPrice,
                                     double &outTakeProfitPrices[], int &outTakeProfitCount)
{
   outTakeProfitCount = 0;
   ArrayResize(outTakeProfitPrices, 0);

   if(ScoreLogWriteModeSkipsTrading())
      return false;

   if(InputTradeSwingProximityPercentOfChartRange <= 0.0 || formationTime == 0)
      return false;

   const int legDirection = isBullishTrade ? 1 : -1;
   M2SwingExtremePoint points[];
   int                 pointCount = 0;
   if(!CollectM2SwingExtremesBackwardFromFormation(formationTime, InputTradeSwingLookbackM2Bars,
                                                    legDirection, points, pointCount))
      return false;

   int formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, true);
   if(formationShift < 0)
      formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, false);
   if(formationShift < 0)
      formationShift = 1;

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(formationShift, InputTradeSwingLookbackM2Bars);
   if(chartHeight <= 0.0)
      return false;

   const double proximityBand =
      chartHeight * (InputTradeSwingProximityPercentOfChartRange / 100.0);
   const double frontRunOffset =
      (InputTradeSwingTpFrontRunPercentOfChartRange > 0.0)
      ? chartHeight * (InputTradeSwingTpFrontRunPercentOfChartRange / 100.0)
      : 0.0;

   bool used[];
   ArrayResize(used, pointCount);
   ArrayInitialize(used, false);

   datetime timeRight = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(timeRight == 0)
      timeRight = TimeCurrent();
   const int m2PeriodSec = (int)PeriodSeconds(InputM2NarrativeTimeframe);
   if(m2PeriodSec > 0)
      timeRight += (datetime)m2PeriodSec;

   const string formationTag = IntegerToString((long)formationTime);
   const color  rectColor    = isBullishTrade ? InputTradeSwingProximityRectColorBull
                                              : InputTradeSwingProximityRectColorBear;
   const color  lineColor    = isBullishTrade ? InputTradeSwingProximityLineColorBull
                                              : InputTradeSwingProximityLineColorBear;
   const bool   isBuy        = isBullishTrade;

   int groupSeq      = 0;
   int groupsSkipped = 0;

   for(int i = 0; i < pointCount; i++)
   {
      if(used[i])
         continue;

      int members[];
      ArrayResize(members, 1);
      members[0] = i;

      for(int j = 0; j < pointCount; j++)
      {
         if(j == i || used[j])
            continue;
         if(MathAbs(points[j].extremePrice - points[i].extremePrice) <= proximityBand)
         {
            const int memberSize = ArraySize(members);
            ArrayResize(members, memberSize + 1);
            members[memberSize] = j;
         }
      }

      if(ArraySize(members) < 2)
         continue;

      datetime mostRecentTime = 0;
      datetime earliestEnd    = timeRight;
      double   linePrice      = 0.0;
      double   groupExtreme   = isBullishTrade ? -1.0e100 : 1.0e100;

      for(int m = 0; m < ArraySize(members); m++)
      {
         const int idx = members[m];
         used[idx]     = true;

         if(points[idx].legEndTime >= mostRecentTime)
         {
            mostRecentTime = points[idx].legEndTime;
            linePrice      = points[idx].extremePrice;
         }
         if(points[idx].legEndTime < earliestEnd)
            earliestEnd = points[idx].legEndTime;

         if(isBullishTrade)
            groupExtreme = MathMax(groupExtreme, points[idx].extremePrice);
         else
            groupExtreme = MathMin(groupExtreme, points[idx].extremePrice);
      }
      if(mostRecentTime <= 0)
         continue;

      if(frontRunOffset > 0.0)
      {
         if(isBuy)
            linePrice -= frontRunOffset;
         else
            linePrice += frontRunOffset;
      }

      if(!SwingGroupLineMeetsMinRiskReward(isBuy, entryPrice, stopLossPrice, linePrice,
                                           InputTradeSwingTpMinRewardToRisk))
      {
         groupsSkipped++;
         continue;
      }

      AppendUniqueTakeProfitLevel(outTakeProfitPrices, outTakeProfitCount, linePrice);

      if(!H4LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
      {
         groupSeq++;
         continue;
      }

      double zoneLow  = 0.0;
      double zoneHigh = 0.0;
      if(isBullishTrade)
      {
         zoneHigh = groupExtreme;
         zoneLow  = groupExtreme - proximityBand;
      }
      else
      {
         zoneLow  = groupExtreme;
         zoneHigh = groupExtreme + proximityBand;
      }

      const string rectName = LQ_OBJ_TRADE_SWGRP_RECT_PREFIX + formationTag + "_" + IntegerToString(groupSeq);
      if(ObjectFind(0, rectName) < 0)
      {
         if(!ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, earliestEnd, zoneHigh, timeRight, zoneLow))
         {
            groupSeq++;
            continue;
         }
      }
      else
      {
         ObjectSetInteger(0, rectName, OBJPROP_TIME, 0, earliestEnd);
         ObjectSetDouble(0, rectName, OBJPROP_PRICE, 0, zoneHigh);
         ObjectSetInteger(0, rectName, OBJPROP_TIME, 1, timeRight);
         ObjectSetDouble(0, rectName, OBJPROP_PRICE, 1, zoneLow);
      }
      ObjectSetInteger(0, rectName, OBJPROP_COLOR, rectColor);
      ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, rectName, OBJPROP_FILL, false);
      ObjectSetInteger(0, rectName, OBJPROP_BACK, false);
      ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, rectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

      const string lineName = LQ_OBJ_TRADE_SWGRP_LINE_PREFIX + formationTag + "_" + IntegerToString(groupSeq);
      if(ObjectFind(0, lineName) >= 0)
         ObjectDelete(0, lineName);
      if(ObjectCreate(0, lineName, OBJ_TREND, 0, mostRecentTime, linePrice, timeRight, linePrice))
      {
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, lineName, OBJPROP_BACK, false);
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, false);
         ObjectSetInteger(0, lineName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      }

      groupSeq++;
   }

   int soloAdded          = 0;
   int soloSkippedRR      = 0;
   int soloSkippedProx    = 0;
   const int clusterTpCount = outTakeProfitCount;
   if(outTakeProfitCount < LQ_TP_COUNT)
   {
      soloAdded = AppendIndividualSwingTakeProfitLevels(isBuy, entryPrice, stopLossPrice,
                                                        points, pointCount, frontRunOffset,
                                                        proximityBand,
                                                        outTakeProfitPrices, outTakeProfitCount,
                                                        LQ_TP_COUNT, soloSkippedRR,
                                                        soloSkippedProx);
   }

   if(outTakeProfitCount < 1)
   {
      LogHuntEvent("TRADE_SWGRP_SKIP",
                   StringFormat("%s no TP lines met min R:R %.2f clusterSkipped=%d soloSkippedRR=%d soloSkippedProx=%d",
                                isBullishTrade ? "bull" : "bear",
                                InputTradeSwingTpMinRewardToRisk, groupsSkipped,
                                soloSkippedRR, soloSkippedProx));
      return false;
   }

   SortTakeProfitLevelsNearestFirst(isBuy, outTakeProfitPrices, outTakeProfitCount);

   if(outTakeProfitCount > LQ_TP_COUNT)
      outTakeProfitCount = LQ_TP_COUNT;

   if(soloAdded > 0)
   {
      LogHuntEvent("TRADE_SWGRP_SOLO",
                   StringFormat("%s soloTps=%d clusterTps=%d soloSkippedRR=%d soloSkippedProx=%d",
                                isBullishTrade ? "bull" : "bear", soloAdded,
                                clusterTpCount, soloSkippedRR, soloSkippedProx));
   }

   LogHuntEvent("TRADE_SWGRP_TP",
                StringFormat("%s tps=%d clusterDrawn=%d clusterSkippedRR=%d soloAdded=%d nearest=%.5f farthest=%.5f",
                             isBullishTrade ? "bull" : "bear", outTakeProfitCount, groupSeq,
                             groupsSkipped, soloAdded, outTakeProfitPrices[0],
                             outTakeProfitPrices[outTakeProfitCount - 1]));

   if(H4LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
      ChartRedraw(0);

   return true;
}

//+------------------------------------------------------------------+
int GetH4TradeDirectionBias()
{
   if(!InputEnableH4BosTradeDirectionBias)
      return 0;

   return GetProfessionalBias(PERIOD_H4);
}

//+------------------------------------------------------------------+
bool FvgTradeAllowedByH4BosBias(const bool isBullishFairValueGap, string &outBlockReason)
{
   outBlockReason = "";
   if(!InputEnableH4BosTradeDirectionBias)
      return true;

   const int bias = GetH4TradeDirectionBias();
   if(bias == 0)
      return true;

   const int tradeDir = isBullishFairValueGap ? 1 : -1;
   if(tradeDir != bias)
   {
      outBlockReason = StringFormat("H4 BOS overall bias %s blocks %s FVG",
                                    bias == 1 ? "bull" : "bear",
                                    isBullishFairValueGap ? "bull" : "bear");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void DeleteMtfDirectionHudObjects()
{
   ObjectDelete(0, LQ_OBJ_MTF_BIAS_HUD_W1);
   ObjectDelete(0, LQ_OBJ_MTF_BIAS_HUD_D1);
   ObjectDelete(0, LQ_OBJ_MTF_BIAS_HUD_H4);
   ObjectDelete(0, LQ_OBJ_MTF_BIAS_HUD_M15);
}

//+------------------------------------------------------------------+
void RefreshMtfDirectionHudRow(const string objectName, const string tfLabel,
                                const ENUM_TIMEFRAMES timeframe, const int rowIndex)
{
   const int yDistance = 18 + rowIndex * 18;

   if(ObjectFind(0, objectName) < 0)
   {
      if(!ObjectCreate(0, objectName, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, objectName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, objectName, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, 8);
      ObjectSetString(0, objectName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
   }

   ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, yDistance);

   const int   bias  = GetProfessionalBias(timeframe);
   string      arrow = ShortToString(0x2014);
   color       col   = clrSilver;
   if(bias == BIAS_BULLISH)
   {
      arrow = ShortToString(0x2191);
      col   = clrLime;
   }
   else if(bias == BIAS_BEARISH)
   {
      arrow = ShortToString(0x2193);
      col   = clrTomato;
   }

   ObjectSetString(0, objectName, OBJPROP_TEXT, tfLabel + " " + arrow);
   ObjectSetInteger(0, objectName, OBJPROP_COLOR, col);
   ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 13);
}

//+------------------------------------------------------------------+
void RefreshMtfDirectionHud()
{
   if(!H4LqChartDrawEnabled(InputShowMtfDirectionHud))
   {
      DeleteMtfDirectionHudObjects();
      return;
   }

   RefreshMtfDirectionHudRow(LQ_OBJ_MTF_BIAS_HUD_W1,  "W1",  PERIOD_W1,  0);
   RefreshMtfDirectionHudRow(LQ_OBJ_MTF_BIAS_HUD_D1,  "D1",  PERIOD_D1,  1);
   RefreshMtfDirectionHudRow(LQ_OBJ_MTF_BIAS_HUD_H4,  "H4",  PERIOD_H4,  2);
   RefreshMtfDirectionHudRow(LQ_OBJ_MTF_BIAS_HUD_M15, "M15", PERIOD_M15, 3);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForFairValueGapFilterM2()
{
   return ReferenceChartHeightForM2BarCount(InputChartRangeBarCount);
}

bool TryGetH4LegBarOpenTimeFromEnd(const datetime legStartTime, const datetime legEndTime,
                                    const int nFromEnd, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legEndTime == 0 || nFromEnd < 1)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   int shiftEnd   = iBarShift(_Symbol, timeframe, legEndTime, false);
   int shiftStart = iBarShift(_Symbol, timeframe, legStartTime, false);
   if(shiftEnd < 0 || shiftStart < 0)
      return false;

   if(shiftStart < shiftEnd)
   {
      const int tmp = shiftStart;
      shiftStart    = shiftEnd;
      shiftEnd      = tmp;
   }

   const int barCount = shiftStart - shiftEnd + 1;
   int indexFromEnd = nFromEnd;
   if(indexFromEnd > barCount)
      indexFromEnd = barCount;

   const int targetShift = shiftEnd + (barCount - indexFromEnd);
   outBarOpenTime = iTime(_Symbol, timeframe, targetShift);
   return outBarOpenTime > 0;
}

//+------------------------------------------------------------------+
double H4BreachLevelPriceFromVolumeBar(const int swingDirection, const int h4BarShift)
{
   if(h4BarShift < 0)
      return 0.0;
   if(swingDirection == 1)
      return iLow(_Symbol, PERIOD_H4, h4BarShift);
   if(swingDirection == -1)
      return iHigh(_Symbol, PERIOD_H4, h4BarShift);
   return 0.0;
}

//+------------------------------------------------------------------+
bool H4BarHasDecentMovementForLegDirection(const int barShift, const int legSwingDirection)
{
   if(barShift < 0 || legSwingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const double barOpen  = iOpen(_Symbol, timeframe, barShift);
   const double barClose = iClose(_Symbol, timeframe, barShift);
   const double barHigh  = iHigh(_Symbol, timeframe, barShift);
   const double barLow   = iLow(_Symbol, timeframe, barShift);

   const int candleDirection =
      (barClose > barOpen) ? 1 : ((barClose < barOpen) ? -1 : 0);
   if(candleDirection != legSwingDirection)
      return false;

   const double bodyRange = MathAbs(barClose - barOpen);
   const double wickRange = barHigh - barLow;

   const int barsTotal = iBars(_Symbol, timeframe);
   double sumRangeFivePriorBars = 0.0;
   int    rangeBarCount = 0;
   for(int priorShift = barShift + 1; priorShift <= barShift + 5; priorShift++)
   {
      if(priorShift >= barsTotal)
         break;
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, priorShift) - iLow(_Symbol, timeframe, priorShift));
      rangeBarCount++;
   }

   const double averageRangeFiveBars =
      (rangeBarCount > 0) ? sumRangeFivePriorBars / (double)rangeBarCount : 0.0;
   const double minDecentRange = averageRangeFiveBars * H4_BREACH_ANCHOR_MULTIPLIER;

   return wickRange > minDecentRange && bodyRange > minDecentRange;
}

//+------------------------------------------------------------------+
bool M2BarHasDecentMovementForLegDirection(const int barShift, const int legSwingDirection)
{
   if(barShift < 0 || legSwingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const double barOpen  = iOpen(_Symbol, timeframe, barShift);
   const double barClose = iClose(_Symbol, timeframe, barShift);
   const double barHigh  = iHigh(_Symbol, timeframe, barShift);
   const double barLow   = iLow(_Symbol, timeframe, barShift);

   const int candleDirection =
      (barClose > barOpen) ? 1 : ((barClose < barOpen) ? -1 : 0);
   if(candleDirection != legSwingDirection)
      return false;

   const double bodyRange = MathAbs(barClose - barOpen);

   const int barsTotal = iBars(_Symbol, timeframe);
   double sumRangeFivePriorBars = 0.0;
   int    rangeBarCount = 0;
   for(int priorShift = barShift + 1; priorShift <= barShift + 5; priorShift++)
   {
      if(priorShift >= barsTotal)
         break;
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, priorShift) - iLow(_Symbol, timeframe, priorShift));
      rangeBarCount++;
   }

   const double averageRangeFiveBars =
      (rangeBarCount > 0) ? sumRangeFivePriorBars / (double)rangeBarCount : 0.0;
   const double minDecentRange = averageRangeFiveBars * M2_SWING_ANCHOR_MULTIPLIER;

   return bodyRange > minDecentRange;
}

//+------------------------------------------------------------------+
bool M2TryGetLegLastDecentMovementBarOpen(const datetime legStartTime, const datetime legProgressEnd,
                                            const int swingDirection, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   int shiftNewer = iBarShift(_Symbol, timeframe, legProgressEnd, true);
   int shiftOlder = iBarShift(_Symbol, timeframe, legStartTime, true);
   if(shiftNewer < 0 || shiftOlder < 0)
      return false;

   if(shiftOlder < shiftNewer)
   {
      const int tmp = shiftOlder;
      shiftOlder    = shiftNewer;
      shiftNewer    = tmp;
   }

   for(int barShift = shiftNewer; barShift <= shiftOlder; barShift++)
   {
      if(!M2BarHasDecentMovementForLegDirection(barShift, swingDirection))
         continue;

      outBarOpenTime = iTime(_Symbol, timeframe, barShift);
      return outBarOpenTime > 0;
   }

   return false;
}

//+------------------------------------------------------------------+
datetime M2ProgressEndOpenForDecentLookup(const datetime legProgressEndOpen)
{
   if(legProgressEndOpen == 0)
      return 0;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int shiftNewer = iBarShift(_Symbol, timeframe, legProgressEndOpen, true);
   if(shiftNewer < 0)
      return legProgressEndOpen;

   const int shiftOlder = shiftNewer + 1;
   if(shiftOlder >= iBars(_Symbol, timeframe))
      return legProgressEndOpen;

   const datetime olderOpen = iTime(_Symbol, timeframe, shiftOlder);
   return (olderOpen > 0) ? olderOpen : legProgressEndOpen;
}

//+------------------------------------------------------------------+
bool M2TryGetVolumeWindowBoundFromLastDecent(const datetime legStartTime, const datetime legProgressEnd,
                                              const int swingDirection, datetime &outBoundInclusiveOpen)
{
   outBoundInclusiveOpen = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0)
      return false;

   const datetime decentLookupEnd = M2ProgressEndOpenForDecentLookup(legProgressEnd);

   datetime lastDecentOpen = 0;
   if(!M2TryGetLegLastDecentMovementBarOpen(legStartTime, decentLookupEnd, swingDirection,
                                              lastDecentOpen))
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int shiftDecent = iBarShift(_Symbol, timeframe, lastDecentOpen, true);
   if(shiftDecent < 0)
      return false;

   const int shiftBoundInclusive = shiftDecent + 2;
   if(shiftBoundInclusive >= iBars(_Symbol, timeframe))
      return false;

   outBoundInclusiveOpen = iTime(_Symbol, timeframe, shiftBoundInclusive);
   return outBoundInclusiveOpen > 0;
}

//+------------------------------------------------------------------+
bool M2VolumeWindowShiftRangeValid(const datetime windowStartInclusive, const datetime windowEndInclusive)
{
   if(windowStartInclusive == 0 || windowEndInclusive == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, timeframe, windowEndInclusive, true);
   if(shiftStartOlder < 0 || shiftEndNewer < 0)
      return false;

   return shiftEndNewer <= shiftStartOlder;
}

//+------------------------------------------------------------------+
bool M2TryResolveLegVolumeWindowEnd(const datetime legStartTime, const datetime legProgressEnd,
                                     const int swingDirection, const datetime windowStartInclusive,
                                     const int lastClosedBarShift, datetime &outWindowEndInclusiveOpen)
{
   outWindowEndInclusiveOpen = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0 || lastClosedBarShift < 1)
      return false;

   datetime decentBoundOpen = 0;
   if(M2TryGetVolumeWindowBoundFromLastDecent(legStartTime, legProgressEnd, swingDirection,
                                               decentBoundOpen) &&
      M2VolumeWindowShiftRangeValid(windowStartInclusive, decentBoundOpen))
   {
      outWindowEndInclusiveOpen = decentBoundOpen;
      return true;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   for(int shiftBound = lastClosedBarShift + 2; shiftBound >= lastClosedBarShift; shiftBound--)
   {
      if(shiftBound >= barsTotal)
         continue;

      const datetime boundOpen = iTime(_Symbol, timeframe, shiftBound);
      if(boundOpen == 0)
         continue;
      if(!M2VolumeWindowShiftRangeValid(windowStartInclusive, boundOpen))
         continue;

      outWindowEndInclusiveOpen = boundOpen;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
bool M2TryGetTouchLegVolumeWindowStart(const int touchLegDirection, datetime &outWindowStartOpen)
{
   outWindowStartOpen = 0;
   if(touchLegDirection == 0 || g_m2Swing.swingHistoryCount < 1)
      return false;

   const Swing prevLeg = g_m2Swing.swingHistory[g_m2Swing.swingHistoryCount - 1];
   if(prevLeg.legEndTime == 0 || prevLeg.legStartTime == 0 || prevLeg.swingDirection == 0)
      return false;

   if(M2TryGetVolumeWindowBoundFromLastDecent(prevLeg.legStartTime, prevLeg.legEndTime,
                                               prevLeg.swingDirection, outWindowStartOpen))
      return true;

   outWindowStartOpen = prevLeg.legStartTime;
   return outWindowStartOpen > 0;
}

//+------------------------------------------------------------------+
bool M2CollectTickVolumesInOpenTimeWindow(const datetime windowStartInclusive,
                                           const datetime windowEndInclusive,
                                           long &outVolumes[], int &outCount)
{
   outCount = 0;
   ArrayResize(outVolumes, 0);
   if(windowStartInclusive == 0 || windowEndInclusive == 0)
      return false;
   if(!M2VolumeWindowShiftRangeValid(windowStartInclusive, windowEndInclusive))
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, timeframe, windowEndInclusive, true);

   const int barCount = shiftStartOlder - shiftEndNewer + 1;
   if(barCount < 1)
      return false;

   ArrayResize(outVolumes, barCount);
   int writeIndex = 0;
   for(int barShift = shiftStartOlder; barShift >= shiftEndNewer; barShift--)
   {
      const long barVol = iTickVolume(_Symbol, timeframe, barShift);
      if(barVol < 0)
         return false;
      outVolumes[writeIndex++] = barVol;
   }

   outCount = writeIndex;
   return outCount >= 1;
}

//+------------------------------------------------------------------+
bool M2TouchLegVolumeIsAscendingPattern(const long &volumes[], const int count)
{
   if(count < 2)
      return false;

   int increaseEvents = 0;
   int decreaseEvents = 0;
   for(int i = 1; i < count; i++)
   {
      if(volumes[i] > volumes[i - 1])
         increaseEvents++;
      else if(volumes[i] < volumes[i - 1])
         decreaseEvents++;
   }

   if(volumes[count - 1] <= volumes[0])
      return false;

   return increaseEvents > decreaseEvents;
}

//+------------------------------------------------------------------+
bool M2ValidateTouchLegVolumeIncreasePattern(const long &volumes[], const int count)
{
   if(count < 2)
      return false;

   return M2TouchLegVolumeIsAscendingPattern(volumes, count);
}

//+------------------------------------------------------------------+
string M2FormatTickVolumeArrayLog(const long &volumes[], const int count,
                                   const datetime windowStartOpen, const datetime windowEndOpen)
{
   string text = "vols=[";
   if(count > 0)
   {
      for(int i = 0; i < count; i++)
      {
         if(i > 0)
            text += ",";
         text += IntegerToString(volumes[i]);
      }
   }
   text += "]";
   if(windowStartOpen != 0 && windowEndOpen != 0)
   {
      text += StringFormat(" n=%d lastLeg3rdLast=%s touchBar=%s",
                           count,
                           TimeToString(windowStartOpen, TIME_DATE | TIME_MINUTES),
                           TimeToString(windowEndOpen, TIME_DATE | TIME_MINUTES));
   }
   else if(count <= 0)
      text += " (window empty or unavailable)";
   return text;
}

bool H4TryGetLegLastDecentMovementBarOpen(const datetime legStartTime, const datetime legProgressEnd,
                                           const int swingDirection, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   int shiftNewer = iBarShift(_Symbol, timeframe, legProgressEnd, true);
   int shiftOlder = iBarShift(_Symbol, timeframe, legStartTime, true);
   if(shiftNewer < 0 || shiftOlder < 0)
      return false;

   if(shiftOlder < shiftNewer)
   {
      const int tmp = shiftOlder;
      shiftOlder    = shiftNewer;
      shiftNewer    = tmp;
   }

   for(int barShift = shiftNewer; barShift <= shiftOlder; barShift++)
   {
      if(!H4BarHasDecentMovementForLegDirection(barShift, swingDirection))
         continue;

      outBarOpenTime = iTime(_Symbol, timeframe, barShift);
      return outBarOpenTime > 0;
   }

   return false;
}

//+------------------------------------------------------------------+
datetime H4ProgressEndOpenForDecentLookup(const datetime legProgressEndOpen)
{
   if(legProgressEndOpen == 0)
      return 0;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftNewer = iBarShift(_Symbol, timeframe, legProgressEndOpen, true);
   if(shiftNewer < 0)
      return legProgressEndOpen;

   const int shiftOlder = shiftNewer + 1;
   if(shiftOlder >= iBars(_Symbol, timeframe))
      return legProgressEndOpen;

   const datetime olderOpen = iTime(_Symbol, timeframe, shiftOlder);
   return (olderOpen > 0) ? olderOpen : legProgressEndOpen;
}

//+------------------------------------------------------------------+
bool H4TryGetVolumeBreachWindowBoundFromLastDecent(const datetime legStartTime,
                                                    const datetime legProgressEnd,
                                                    const int swingDirection,
                                                    datetime &outBoundInclusiveOpen)
{
   outBoundInclusiveOpen = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0)
      return false;

   const datetime decentLookupEnd = H4ProgressEndOpenForDecentLookup(legProgressEnd);

   datetime lastDecentOpen = 0;
   if(!H4TryGetLegLastDecentMovementBarOpen(legStartTime, decentLookupEnd, swingDirection,
                                              lastDecentOpen))
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftDecent = iBarShift(_Symbol, timeframe, lastDecentOpen, true);
   if(shiftDecent < 0)
      return false;

   const int shiftBoundInclusive = shiftDecent + 2;
   if(shiftBoundInclusive >= iBars(_Symbol, timeframe))
      return false;

   outBoundInclusiveOpen = iTime(_Symbol, timeframe, shiftBoundInclusive);
   return outBoundInclusiveOpen > 0;
}

//+------------------------------------------------------------------+
bool H4TryGetLegVolumeBreachWindowStartForScan(const datetime legStartTime,
                                               const datetime legProgressEnd,
                                               const int swingDirection,
                                               datetime &outWindowStartInclusiveOpen)
{
   return H4TryGetVolumeBreachWindowBoundFromLastDecent(legStartTime, legProgressEnd, swingDirection,
                                                           outWindowStartInclusiveOpen);
}

//+------------------------------------------------------------------+
bool H4TryGetLegVolumeBreachWindowEndForScan(const datetime legStartTime,
                                             const datetime legProgressEnd,
                                             const int swingDirection,
                                             datetime &outWindowEndInclusiveOpen)
{
   return H4TryGetVolumeBreachWindowBoundFromLastDecent(legStartTime, legProgressEnd, swingDirection,
                                                         outWindowEndInclusiveOpen);
}

//+------------------------------------------------------------------+
bool H4VolumeBreachWindowShiftRangeValid(const datetime windowStartInclusive,
                                         const datetime windowEndInclusive)
{
   if(windowStartInclusive == 0 || windowEndInclusive == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, timeframe, windowEndInclusive, true);
   if(shiftStartOlder < 0 || shiftEndNewer < 0)
      return false;

   return shiftEndNewer <= shiftStartOlder;
}

//+------------------------------------------------------------------+
bool H4TryResolveLegVolumeBreachWindowEnd(const datetime legStartTime,
                                          const datetime legProgressEnd,
                                          const int swingDirection,
                                          const datetime windowStartInclusive,
                                          const int lastClosedBarShift,
                                          datetime &outWindowEndInclusiveOpen)
{
   outWindowEndInclusiveOpen = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0 || lastClosedBarShift < 1)
      return false;

   datetime decentBoundOpen = 0;
   if(H4TryGetLegVolumeBreachWindowEndForScan(legStartTime, legProgressEnd, swingDirection,
                                               decentBoundOpen) &&
      H4VolumeBreachWindowShiftRangeValid(windowStartInclusive, decentBoundOpen))
   {
      outWindowEndInclusiveOpen = decentBoundOpen;
      return true;
   }

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int barsTotal = iBars(_Symbol, timeframe);
   for(int shiftBound = lastClosedBarShift + 2; shiftBound >= lastClosedBarShift; shiftBound--)
   {
      if(shiftBound >= barsTotal)
         continue;

      const datetime boundOpen = iTime(_Symbol, timeframe, shiftBound);
      if(boundOpen == 0)
         continue;
      if(!H4VolumeBreachWindowShiftRangeValid(windowStartInclusive, boundOpen))
         continue;

      outWindowEndInclusiveOpen = boundOpen;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
bool FindMaxVolumeH4BarBetweenOpenTimes(const datetime rangeStartOpen, const datetime rangeEndOpen,
                                         datetime &outBarOpenTime, long &outMaxVolume)
{
   outBarOpenTime = 0;
   outMaxVolume   = -1;
   if(rangeStartOpen == 0 || rangeEndOpen == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   datetime rangeLo = rangeStartOpen;
   datetime rangeHi = rangeEndOpen;
   if(rangeLo > rangeHi)
   {
      const datetime tmp = rangeLo;
      rangeLo = rangeHi;
      rangeHi = tmp;
   }

   int shiftNewer = iBarShift(_Symbol, timeframe, rangeHi, false);
   int shiftOlder = iBarShift(_Symbol, timeframe, rangeLo, false);
   if(shiftNewer < 0 || shiftOlder < 0)
      return false;

   if(shiftOlder < shiftNewer)
   {
      const int tmp = shiftOlder;
      shiftOlder    = shiftNewer;
      shiftNewer    = tmp;
   }

   for(int barShift = shiftNewer; barShift <= shiftOlder; barShift++)
   {
      const long barVol = iTickVolume(_Symbol, timeframe, barShift);
      if(barVol < 0)
         continue;
      if(barVol > outMaxVolume)
      {
         outMaxVolume   = barVol;
         outBarOpenTime = iTime(_Symbol, timeframe, barShift);
      }
   }
   return outBarOpenTime > 0 && outMaxVolume >= 0;
}

//+------------------------------------------------------------------+
void H4ScanVolumeWindowMonotonic(const int swingDirection, const datetime windowStartInclusive,
                                  const datetime windowEndInclusive, long &inOutMaxVolume,
                                  datetime &inOutMaxBarOpenTime, double &inOutBreachLevel)
{
   if(swingDirection == 0 || windowStartInclusive == 0 || windowEndInclusive == 0)
      return;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, timeframe, windowEndInclusive, true);
   if(shiftStartOlder < 0 || shiftEndNewer < 0)
      return;

   if(shiftEndNewer > shiftStartOlder)
      return;

   for(int barShift = shiftEndNewer; barShift <= shiftStartOlder; barShift++)
   {
      const long barVol = iTickVolume(_Symbol, timeframe, barShift);
      if(barVol < 0 || barVol <= inOutMaxVolume)
         continue;

      inOutMaxVolume      = barVol;
      inOutMaxBarOpenTime = iTime(_Symbol, timeframe, barShift);
      inOutBreachLevel    = H4BreachLevelPriceFromVolumeBar(swingDirection, barShift);
   }
}

//+------------------------------------------------------------------+
bool ComputeH4LegVolumeBreachLevel(const Swing &lastLeg, const Swing &prevLeg, const bool hasPrevLeg,
                                    double &outBreachLevel, datetime &outVolumeBarOpenTime)
{
   outBreachLevel       = 0.0;
   outVolumeBarOpenTime = 0;

   if(lastLeg.swingDirection == 0 || lastLeg.legEndTime == 0 || lastLeg.legStartTime == 0)
      return false;

   datetime windowStartOpen = lastLeg.legStartTime;
   if(hasPrevLeg && prevLeg.legEndTime != 0)
   {
      if(!H4TryGetLegVolumeBreachWindowStartForScan(prevLeg.legStartTime, prevLeg.legEndTime,
                                                     prevLeg.swingDirection, windowStartOpen))
         windowStartOpen = prevLeg.legStartTime;
   }

   long     maxVol        = -1;
   datetime maxVolBarOpen = 0;
   double   breachLevel   = 0.0;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftLegEnd   = iBarShift(_Symbol, timeframe, lastLeg.legEndTime, true);
   const int shiftLegStart = iBarShift(_Symbol, timeframe, lastLeg.legStartTime, true);
   if(shiftLegEnd < 0 || shiftLegStart < 0)
      return false;

   for(int barShift = shiftLegStart; barShift >= shiftLegEnd; barShift--)
   {
      const datetime progressEndOpen = iTime(_Symbol, timeframe, barShift);
      if(progressEndOpen == 0)
         continue;

      datetime windowEndInclusive = 0;
      if(!H4TryGetLegVolumeBreachWindowEndForScan(lastLeg.legStartTime, progressEndOpen,
                                                   lastLeg.swingDirection, windowEndInclusive))
         continue;

      H4ScanVolumeWindowMonotonic(lastLeg.swingDirection, windowStartOpen, windowEndInclusive,
                                   maxVol, maxVolBarOpen, breachLevel);
   }

   datetime finalWindowEndInclusive = 0;
   if(H4TryGetLegVolumeBreachWindowEndForScan(lastLeg.legStartTime, lastLeg.legEndTime,
                                               lastLeg.swingDirection, finalWindowEndInclusive))
      H4ScanVolumeWindowMonotonic(lastLeg.swingDirection, windowStartOpen, finalWindowEndInclusive,
                                   maxVol, maxVolBarOpen, breachLevel);

   if(maxVolBarOpen == 0 || breachLevel <= 0.0)
   {
      if(lastLeg.swingDirection == 1)
         outBreachLevel = lastLeg.legHighPrice;
      else
         outBreachLevel = lastLeg.legLowPrice;
      outVolumeBarOpenTime = lastLeg.legEndTime;
      return outBreachLevel > 0.0;
   }

   outBreachLevel       = breachLevel;
   outVolumeBarOpenTime = maxVolBarOpen;
   return true;
}

#ifdef H4_LQ_VOLUME_BREACH_ENABLED
// --- H4 volume breach record array, push, sweep, chart rays (disabled v3.04) ---

//+------------------------------------------------------------------+
void H4ResetActiveLegVolumeBreachTrack()
{
   ZeroMemory(g_h4ActiveLegVolumeTrack);
   g_h4ActiveLegVolumeTrack.maxTickVolume = -1;
}

//+------------------------------------------------------------------+
void RememberH4LegVolumeBreachRecord(const datetime legStartTime, const datetime legEndTime,
                                      const int swingDirection, const double breachLevel,
                                      const datetime volumeBarOpenTime)
{
   if(legStartTime == 0 || swingDirection == 0 || breachLevel <= 0.0)
      return;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(legEndTime == 0 && g_h4LegVolumeBreaches[i].legEndTime == 0 &&
         g_h4LegVolumeBreaches[i].legStartTime == legStartTime)
      {
         if(!H4VolumeBreachLevelsMatch(g_h4LegVolumeBreaches[i].breachLevelPrice, breachLevel))
            g_h4LegVolumeBreaches[i].swept = false;
         g_h4LegVolumeBreaches[i].swingDirection    = swingDirection;
         g_h4LegVolumeBreaches[i].breachLevelPrice    = breachLevel;
         g_h4LegVolumeBreaches[i].volumeBarOpenTime = volumeBarOpenTime;
         return;
      }
      if(g_h4LegVolumeBreaches[i].legStartTime == legStartTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection)
      {
         if(!H4VolumeBreachLevelsMatch(g_h4LegVolumeBreaches[i].breachLevelPrice, breachLevel))
            g_h4LegVolumeBreaches[i].swept = false;
         if(legEndTime > 0)
            g_h4LegVolumeBreaches[i].legEndTime = legEndTime;
         g_h4LegVolumeBreaches[i].breachLevelPrice    = breachLevel;
         g_h4LegVolumeBreaches[i].volumeBarOpenTime = volumeBarOpenTime;
         return;
      }
      if(legEndTime > 0 && g_h4LegVolumeBreaches[i].legEndTime == legEndTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection)
      {
         if(!H4VolumeBreachLevelsMatch(g_h4LegVolumeBreaches[i].breachLevelPrice, breachLevel))
            g_h4LegVolumeBreaches[i].swept = false;
         g_h4LegVolumeBreaches[i].legStartTime        = legStartTime;
         g_h4LegVolumeBreaches[i].breachLevelPrice    = breachLevel;
         g_h4LegVolumeBreaches[i].volumeBarOpenTime = volumeBarOpenTime;
         return;
      }
   }

   if(g_h4LegVolumeBreachCount < H4_LEG_VOLUME_BREACH_CAPACITY)
   {
      const int index = g_h4LegVolumeBreachCount;
      g_h4LegVolumeBreaches[index].legStartTime        = legStartTime;
      g_h4LegVolumeBreaches[index].legEndTime          = legEndTime;
      g_h4LegVolumeBreaches[index].swingDirection       = swingDirection;
      g_h4LegVolumeBreaches[index].breachLevelPrice     = breachLevel;
      g_h4LegVolumeBreaches[index].volumeBarOpenTime  = volumeBarOpenTime;
      g_h4LegVolumeBreaches[index].swept              = false;
      g_h4LegVolumeBreachCount++;
      return;
   }

   DeleteH4VolumeBreachLevelRay(g_h4LegVolumeBreaches[0].legStartTime);
   for(int shiftIndex = 1; shiftIndex < H4_LEG_VOLUME_BREACH_CAPACITY; shiftIndex++)
      g_h4LegVolumeBreaches[shiftIndex - 1] = g_h4LegVolumeBreaches[shiftIndex];

   const int lastIndex = H4_LEG_VOLUME_BREACH_CAPACITY - 1;
   g_h4LegVolumeBreaches[lastIndex].legStartTime        = legStartTime;
   g_h4LegVolumeBreaches[lastIndex].legEndTime          = legEndTime;
   g_h4LegVolumeBreaches[lastIndex].swingDirection       = swingDirection;
   g_h4LegVolumeBreaches[lastIndex].breachLevelPrice     = breachLevel;
   g_h4LegVolumeBreaches[lastIndex].volumeBarOpenTime  = volumeBarOpenTime;
   g_h4LegVolumeBreaches[lastIndex].swept              = false;
}

//+------------------------------------------------------------------+
bool TryGetH4VolumeBreachWindowStartFromLastCompletedLeg(const SwingState &swingState,
                                                          datetime &outWindowStartOpen)
{
   outWindowStartOpen = 0;
   if(swingState.swingHistoryCount < 1)
      return false;

   const Swing leg = swingState.swingHistory[swingState.swingHistoryCount - 1];
   if(leg.legEndTime == 0 || leg.legStartTime == 0 || leg.swingDirection == 0)
      return false;

   if(H4TryGetLegVolumeBreachWindowStartForScan(leg.legStartTime, leg.legEndTime, leg.swingDirection,
                                                 outWindowStartOpen))
      return true;

   outWindowStartOpen = leg.legStartTime;
   return outWindowStartOpen > 0;
}

//+------------------------------------------------------------------+
void H4OnH4ActiveLegStarted(SwingState &swingState, const int lastClosedBarShift)
{
   H4ResetActiveLegVolumeBreachTrack();

   if(swingState.currentSwingLeg.swingDirection == 0 || swingState.currentSwingLeg.legStartTime == 0)
      return;

   g_h4ActiveLegVolumeTrack.legStartTime         = swingState.currentSwingLeg.legStartTime;
   g_h4ActiveLegVolumeTrack.swingDirection      = swingState.currentSwingLeg.swingDirection;
   g_h4ActiveLegVolumeTrack.windowStartOpenTime = swingState.currentSwingLeg.legStartTime;

   if(!TryGetH4VolumeBreachWindowStartFromLastCompletedLeg(swingState,
                                                           g_h4ActiveLegVolumeTrack.windowStartOpenTime))
      g_h4ActiveLegVolumeTrack.windowStartOpenTime = swingState.currentSwingLeg.legStartTime;

   H4PurgeStaleActiveLegVolumeBreachRecords(swingState.currentSwingLeg.legStartTime);
   H4OnH4ActiveLegBarClosed(swingState, lastClosedBarShift);
}

//+------------------------------------------------------------------+
void H4OnH4ActiveLegBarClosed(SwingState &swingState, const int lastClosedBarShift)
{
   if(swingState.currentSwingLeg.swingDirection == 0 || swingState.currentSwingLeg.legStartTime == 0)
      return;
   if(g_h4ActiveLegVolumeTrack.legStartTime != swingState.currentSwingLeg.legStartTime)
      return;

   g_h4ActiveLegVolumeTrack.swingDirection = swingState.currentSwingLeg.swingDirection;

   if(lastClosedBarShift < 1)
      return;

   const datetime lastClosedOpen = iTime(_Symbol, PERIOD_H4, lastClosedBarShift);
   if(lastClosedOpen == 0)
      return;

   datetime windowEndInclusive = 0;
   if(!H4TryResolveLegVolumeBreachWindowEnd(swingState.currentSwingLeg.legStartTime,
                                             lastClosedOpen,
                                             swingState.currentSwingLeg.swingDirection,
                                             g_h4ActiveLegVolumeTrack.windowStartOpenTime,
                                             lastClosedBarShift,
                                             windowEndInclusive))
      return;

   H4ScanVolumeWindowMonotonic(g_h4ActiveLegVolumeTrack.swingDirection,
                                g_h4ActiveLegVolumeTrack.windowStartOpenTime,
                                windowEndInclusive,
                                g_h4ActiveLegVolumeTrack.maxTickVolume,
                                g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime,
                                g_h4ActiveLegVolumeTrack.breachLevelPrice);

   if(g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime == 0 ||
      g_h4ActiveLegVolumeTrack.breachLevelPrice <= 0.0)
      return;

   RememberH4LegVolumeBreachRecord(swingState.currentSwingLeg.legStartTime, 0,
                                    g_h4ActiveLegVolumeTrack.swingDirection,
                                    g_h4ActiveLegVolumeTrack.breachLevelPrice,
                                    g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime);
}

//+------------------------------------------------------------------+
void H4PurgeStaleActiveLegVolumeBreachRecords(const datetime keepLegStartTime)
{
   int writeIndex = 0;
   for(int readIndex = 0; readIndex < g_h4LegVolumeBreachCount; readIndex++)
   {
      const H4LegVolumeBreachRecord rec = g_h4LegVolumeBreaches[readIndex];
      if(rec.legEndTime == 0 && rec.legStartTime != keepLegStartTime)
      {
         DeleteH4VolumeBreachLevelRay(rec.legStartTime);
         continue;
      }

      if(writeIndex != readIndex)
         g_h4LegVolumeBreaches[writeIndex] = rec;
      writeIndex++;
   }
   g_h4LegVolumeBreachCount = writeIndex;
}

//+------------------------------------------------------------------+
void H4FinalizeActiveLegVolumeBreach(const Swing &closedLeg)
{
   if(closedLeg.legStartTime == 0 || closedLeg.legEndTime == 0 || closedLeg.swingDirection == 0)
      return;

   double breachLevel = 0.0;
   datetime volumeBarOpenTime = 0;
   bool     resolvedFromTrack = false;

   if(g_h4ActiveLegVolumeTrack.legStartTime == closedLeg.legStartTime &&
      g_h4ActiveLegVolumeTrack.swingDirection == closedLeg.swingDirection)
   {
      datetime finalizeWindowEndInclusive = 0;
      if(closedLeg.legEndTime > 0 &&
         H4TryGetLegVolumeBreachWindowEndForScan(closedLeg.legStartTime, closedLeg.legEndTime,
                                                   closedLeg.swingDirection, finalizeWindowEndInclusive))
      {
         H4ScanVolumeWindowMonotonic(closedLeg.swingDirection,
                                      g_h4ActiveLegVolumeTrack.windowStartOpenTime,
                                      finalizeWindowEndInclusive,
                                      g_h4ActiveLegVolumeTrack.maxTickVolume,
                                      g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime,
                                      g_h4ActiveLegVolumeTrack.breachLevelPrice);
      }

      if(g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime > 0 &&
         g_h4ActiveLegVolumeTrack.breachLevelPrice > 0.0)
      {
         breachLevel       = g_h4ActiveLegVolumeTrack.breachLevelPrice;
         volumeBarOpenTime = g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime;
         resolvedFromTrack = true;
      }
   }

   if(!resolvedFromTrack)
   {
      Swing prevLeg;
      ZeroMemory(prevLeg);
      const bool hasPrevLeg = (g_mtfSwingH4.swing.swingHistoryCount > 1);
      if(hasPrevLeg)
         prevLeg = g_mtfSwingH4.swing.swingHistory[g_mtfSwingH4.swing.swingHistoryCount - 2];

      if(!ComputeH4LegVolumeBreachLevel(closedLeg, prevLeg, hasPrevLeg, breachLevel, volumeBarOpenTime))
         return;
   }

   RememberH4LegVolumeBreachRecord(closedLeg.legStartTime, closedLeg.legEndTime,
                                    closedLeg.swingDirection, breachLevel, volumeBarOpenTime);
   H4PurgeStaleActiveLegVolumeBreachRecords(0);
   H4ResetActiveLegVolumeBreachTrack();
}

//+------------------------------------------------------------------+
void H4RestoreActiveLegVolumeBreachTrackFromSwing()
{
   if(g_mtfSwingH4.swing.currentSwingLeg.swingDirection == 0 || g_mtfSwingH4.swing.currentSwingLeg.legStartTime == 0)
   {
      H4ResetActiveLegVolumeBreachTrack();
      return;
   }
   H4OnH4ActiveLegStarted(g_mtfSwingH4.swing);
}

//+------------------------------------------------------------------+
bool TryGetH4LegVolumeBreachLevel(const datetime legEndTime, const int swingDirection,
                                   double &outBreachLevel, datetime &outVolumeBarOpenTime)
{
   outBreachLevel       = 0.0;
   outVolumeBarOpenTime = 0;
   if(legEndTime == 0)
      return false;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(g_h4LegVolumeBreaches[i].legEndTime == legEndTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection)
      {
         outBreachLevel       = g_h4LegVolumeBreaches[i].breachLevelPrice;
         outVolumeBarOpenTime = g_h4LegVolumeBreaches[i].volumeBarOpenTime;
         return outBreachLevel > 0.0;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryResolveH4LegVolumeBreachLevel(const datetime legStartTime, const datetime legEndTime,
                                       const int swingDirection, double &outBreachLevel,
                                       datetime &outVolumeBarOpenTime)
{
   outBreachLevel       = 0.0;
   outVolumeBarOpenTime = 0;
   if(legStartTime == 0 || swingDirection == 0)
      return false;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(g_h4LegVolumeBreaches[i].legStartTime == legStartTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection &&
         g_h4LegVolumeBreaches[i].breachLevelPrice > 0.0)
      {
         outBreachLevel       = g_h4LegVolumeBreaches[i].breachLevelPrice;
         outVolumeBarOpenTime = g_h4LegVolumeBreaches[i].volumeBarOpenTime;
         return outVolumeBarOpenTime > 0;
      }
   }

   if(legEndTime > 0)
      return TryGetH4LegVolumeBreachLevel(legEndTime, swingDirection, outBreachLevel,
                                            outVolumeBarOpenTime);

   return false;
}

//+------------------------------------------------------------------+
bool IsH4BarWithinBreachBufferChartWindow(const datetime barOpenTime)
{
   const int barCount = InputH4BreachBufferChartBarCount;
   if(barCount < 1 || barOpenTime <= 0)
      return false;

   const int barShift = iBarShift(_Symbol, PERIOD_H4, barOpenTime, false);
   if(barShift < 0)
      return false;

   return barShift >= 1 && barShift <= barCount;
}

//+------------------------------------------------------------------+
bool IsH4LegVolumeBreachActiveInBufferWindow(const datetime legEndTime, const int swingDirection)
{
   if(legEndTime == 0 || swingDirection == 0)
      return false;

   double breachLevel = 0.0;
   datetime volumeBarOpenTime = 0;
   if(TryGetH4LegVolumeBreachLevel(legEndTime, swingDirection, breachLevel, volumeBarOpenTime))
   {
      if(volumeBarOpenTime > 0 && IsH4BarWithinBreachBufferChartWindow(volumeBarOpenTime))
         return true;
   }

   return IsH4BarWithinBreachBufferChartWindow(legEndTime);
}

//+------------------------------------------------------------------+
void H4ClearVolumeBreachMemoryAndChart()
{
   g_h4LegVolumeBreachCount = 0;
   H4ResetActiveLegVolumeBreachTrack();
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);
}

//+------------------------------------------------------------------+
void RebuildH4LegVolumeBreachLevelsFromSwingHistory()
{
   g_h4LegVolumeBreachCount = 0;

   for(int legIndex = 0; legIndex < g_mtfSwingH4.swing.swingHistoryCount; legIndex++)
   {
      const Swing lastLeg = g_mtfSwingH4.swing.swingHistory[legIndex];
      Swing       prevLeg;
      ZeroMemory(prevLeg);
      const bool hasPrevLeg = (legIndex > 0);

      if(hasPrevLeg)
         prevLeg = g_mtfSwingH4.swing.swingHistory[legIndex - 1];

      double breachLevel = 0.0;
      datetime volumeBarOpenTime = 0;
      if(!ComputeH4LegVolumeBreachLevel(lastLeg, prevLeg, hasPrevLeg, breachLevel, volumeBarOpenTime))
         continue;

      RememberH4LegVolumeBreachRecord(lastLeg.legStartTime, lastLeg.legEndTime,
                                       lastLeg.swingDirection, breachLevel, volumeBarOpenTime);
   }
}

//+------------------------------------------------------------------+
void DeleteH4VolumeBreachLevelRay(const datetime legStartTime)
{
   if(legStartTime == 0)
      return;

   const string objName =
      ChartObjectNamePrefixH4VolumeBreachRay + IntegerToString((long)legStartTime);
   ObjectDelete(0, objName);
}

//+------------------------------------------------------------------+
void DrawH4VolumeBreachLevelRay(const datetime legStartTime, const datetime legEndTime,
                                 const int swingDirection, const datetime volumeBarOpenTime,
                                 const double breachLevel)
{
   if(!H4LqChartDrawEnabled(InputDrawMtfSwingLegsH4) || legStartTime == 0 || swingDirection == 0 ||
      volumeBarOpenTime == 0 || breachLevel <= 0.0)
      return;

   const color rayColor = (swingDirection == 1)
                          ? H4_VOLUME_BREACH_RAY_COLOR_UP
                          : H4_VOLUME_BREACH_RAY_COLOR_DOWN;

   const string objName =
      ChartObjectNamePrefixH4VolumeBreachRay + IntegerToString((long)legStartTime);

   const int h4PeriodSec = (int)PeriodSeconds(PERIOD_H4);
   if(h4PeriodSec < 1)
      return;

   const int bufferBars = InputH4BreachBufferChartBarCount;
   if(bufferBars < 1)
      return;

   const datetime timeEnd =
      volumeBarOpenTime + (datetime)((long)bufferBars * (long)h4PeriodSec);

   if(ObjectFind(0, objName) < 0)
   {
      if(!ObjectCreate(0, objName, OBJ_TREND, 0, volumeBarOpenTime, breachLevel, timeEnd, breachLevel))
         return;
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, volumeBarOpenTime);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, breachLevel);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeEnd);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, breachLevel);
   }

   ObjectSetInteger(0, objName, OBJPROP_COLOR, rayColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_ZORDER, H4_VOLUME_BREACH_RAY_ZORDER);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void RebuildAllH4VolumeBreachMarkers()
{
   if(!H4LqChartDrawEnabled(InputDrawMtfSwingLegsH4))
   {
      ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);
      return;
   }

   ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      const H4LegVolumeBreachRecord rec = g_h4LegVolumeBreaches[i];
      if(rec.legStartTime == 0 || rec.swingDirection == 0 || rec.breachLevelPrice <= 0.0)
         continue;

      if(rec.legEndTime == 0 &&
         (g_mtfSwingH4.swing.currentSwingLeg.legStartTime != rec.legStartTime ||
          g_mtfSwingH4.swing.currentSwingLeg.swingDirection != rec.swingDirection))
         continue;

      if(rec.swept)
         continue;

      if(!IsH4LegVolumeBreachActiveInBufferWindow(rec.legEndTime == 0 ? rec.legStartTime : rec.legEndTime,
                                                   rec.swingDirection) &&
         rec.legEndTime != 0)
         continue;

      if(rec.legEndTime == 0)
      {
         datetime volumeBarOpenTime = rec.volumeBarOpenTime;
         if(volumeBarOpenTime == 0)
            volumeBarOpenTime = rec.legStartTime;
         if(!IsH4BarWithinBreachBufferChartWindow(volumeBarOpenTime))
            continue;
      }

      DrawH4VolumeBreachLevelRay(rec.legStartTime, rec.legEndTime, rec.swingDirection,
                                  rec.volumeBarOpenTime, rec.breachLevelPrice);
   }
}

//+------------------------------------------------------------------+
bool H4VolumeBreachLevelsMatch(const double levelA, const double levelB)
{
   if(levelA <= 0.0 || levelB <= 0.0)
      return false;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   return MathAbs(levelA - levelB) <= eps;
}

//+------------------------------------------------------------------+
bool H4IsVolumeBreachRecordSwept(const datetime legKey, const int swingDirection,
                                  const double breachLevel)
{
   if(swingDirection == 0 || breachLevel <= 0.0)
      return false;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      const H4LegVolumeBreachRecord rec = g_h4LegVolumeBreaches[i];
      if(rec.swingDirection != swingDirection)
         continue;
      if(!H4VolumeBreachLevelsMatch(rec.breachLevelPrice, breachLevel))
         continue;
      if(legKey != 0 && legKey != rec.legStartTime && legKey != rec.legEndTime)
         continue;
      return rec.swept;
   }
   return false;
}

//+------------------------------------------------------------------+
void H4MarkVolumeBreachRecordSwept(const datetime legKey, const int swingDirection,
                                    const double breachLevel)
{
   if(swingDirection == 0 || breachLevel <= 0.0)
      return;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(g_h4LegVolumeBreaches[i].swingDirection != swingDirection)
         continue;
      if(!H4VolumeBreachLevelsMatch(g_h4LegVolumeBreaches[i].breachLevelPrice, breachLevel))
         continue;
      if(legKey != 0 && legKey != g_h4LegVolumeBreaches[i].legStartTime &&
         legKey != g_h4LegVolumeBreaches[i].legEndTime)
         continue;

      g_h4LegVolumeBreaches[i].swept = true;
      DeleteH4VolumeBreachLevelRay(g_h4LegVolumeBreaches[i].legStartTime);
      return;
   }
}

//+------------------------------------------------------------------+
//| Up-leg level (green): H4 low below level after vol bar. Down-leg (pink): H4 high above. |
//+------------------------------------------------------------------+
bool WasH4VolumeBreachLevelViolatedSinceFormation(const int swingDirection,
                                                    const double breachLevel,
                                                    const datetime levelFormedOpenTime,
                                                    const double pointSize)
{
   if(swingDirection == 0 || breachLevel <= 0.0 || levelFormedOpenTime == 0)
      return false;

   const double eps = (pointSize > 0.0 ? pointSize : 0.00001);
   const int formationShift =
      iBarShift(_Symbol, PERIOD_H4, levelFormedOpenTime, false);
   if(formationShift < 0)
      return false;

   for(int barShift = formationShift - 1; barShift >= 1; barShift--)
   {
      if(swingDirection == 1)
      {
         const double barLow = iLow(_Symbol, PERIOD_H4, barShift);
         if(barLow > 0.0 && barLow < breachLevel - eps)
            return true;
      }
      else if(swingDirection == -1)
      {
         const double barHigh = iHigh(_Symbol, PERIOD_H4, barShift);
         if(barHigh > 0.0 && barHigh > breachLevel + eps)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Mark volume breach levels swept (each M2 close + once on attach). |
//+------------------------------------------------------------------+
void UpdateH4LegLiquidityBreachMemoryOnM2Bar()
{
   if(InputH4BreachBufferChartBarCount < 1)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(g_h4LegVolumeBreaches[i].swingDirection == 0 || g_h4LegVolumeBreaches[i].breachLevelPrice <= 0.0)
         continue;

      if(g_h4LegVolumeBreaches[i].swept)
         continue;

      const bool isActiveLeg = (g_h4LegVolumeBreaches[i].legEndTime == 0);
      if(isActiveLeg)
      {
         if(g_mtfSwingH4.swing.currentSwingLeg.legStartTime != g_h4LegVolumeBreaches[i].legStartTime ||
            g_mtfSwingH4.swing.currentSwingLeg.swingDirection != g_h4LegVolumeBreaches[i].swingDirection)
            continue;

         datetime volumeBarOpenTime = g_h4LegVolumeBreaches[i].volumeBarOpenTime;
         if(volumeBarOpenTime == 0)
            volumeBarOpenTime = g_h4LegVolumeBreaches[i].legStartTime;
         if(!IsH4BarWithinBreachBufferChartWindow(volumeBarOpenTime))
            continue;
      }
      else if(!IsH4LegVolumeBreachActiveInBufferWindow(g_h4LegVolumeBreaches[i].legEndTime,
                                                        g_h4LegVolumeBreaches[i].swingDirection))
      {
         continue;
      }

      datetime scanFromOpenTime = g_h4LegVolumeBreaches[i].volumeBarOpenTime;
      if(scanFromOpenTime == 0)
         scanFromOpenTime = (g_h4LegVolumeBreaches[i].legEndTime > 0)
                            ? g_h4LegVolumeBreaches[i].legEndTime
                            : g_h4LegVolumeBreaches[i].legStartTime;

      if(!WasH4VolumeBreachLevelViolatedSinceFormation(g_h4LegVolumeBreaches[i].swingDirection,
                                                        g_h4LegVolumeBreaches[i].breachLevelPrice,
                                                        scanFromOpenTime, pointSize))
         continue;

      g_h4LegVolumeBreaches[i].swept = true;
      DeleteH4VolumeBreachLevelRay(g_h4LegVolumeBreaches[i].legStartTime);
      if(H4LqLoggingEnabled())
      {
         const datetime legKey = (g_h4LegVolumeBreaches[i].legEndTime > 0)
                                 ? g_h4LegVolumeBreaches[i].legEndTime
                                 : g_h4LegVolumeBreaches[i].legStartTime;
         LogHuntEvent("BREACH_SWEPT",
                      StringFormat("H4 %s leg %s level=%.5f volBar=%s price %s level â€” skip hunt",
                                   g_h4LegVolumeBreaches[i].swingDirection == 1 ? "up" : "down",
                                   TimeToString(legKey, TIME_DATE | TIME_MINUTES),
                                   g_h4LegVolumeBreaches[i].breachLevelPrice,
                                   TimeToString(scanFromOpenTime, TIME_DATE | TIME_MINUTES),
                                   g_h4LegVolumeBreaches[i].swingDirection == 1 ? "below" : "above"));
      }
   }
}

#endif // H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
bool TryPushH4ReplayLeg(H4ReplayLeg &replayLegs[], int &replayLegCount, const Swing &closedLeg)
{
   if(closedLeg.swingDirection == 0 || closedLeg.legEndTime == 0)
      return false;
   if(replayLegCount >= H4_REPLAY_LEG_CAPACITY)
      return false;

   replayLegs[replayLegCount].legHighPrice    = closedLeg.legHighPrice;
   replayLegs[replayLegCount].legLowPrice     = closedLeg.legLowPrice;
   replayLegs[replayLegCount].legStartTime    = closedLeg.legStartTime;
   replayLegs[replayLegCount].legEndTime      = closedLeg.legEndTime;
   replayLegs[replayLegCount].swingDirection = closedLeg.swingDirection;
   replayLegCount++;
   return true;
}

//+------------------------------------------------------------------+
//| Replay one closed TF bar; append completed legs (no live side effects). |
//+------------------------------------------------------------------+
void MtfSwingStepReplayAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                                const int lastClosedBarShift,
                                H4ReplayLeg &replayLegs[], int &replayLegCount)
{
   bool unusedLegClosed = false;
   ProcessMTFSwingStepAtShiftCollect(swingState, timeframe, lastClosedBarShift,
                                      H4_BOS_ANCHOR_MULTIPLIER, false,
                                      replayLegs, replayLegCount, true, unusedLegClosed);
}

//+------------------------------------------------------------------+
//| MTF SMC Confluence Engine — Phase 1: multi-timeframe swing trackers |
//+------------------------------------------------------------------+
void ProcessMTFSwingStepAtShiftCollect(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                                        const int lastClosedBarShift, const double anchorMultiplier,
                                        const bool useWickAndBodyForDecent,
                                        H4ReplayLeg &replayLegs[], int &replayLegCount,
                                        const bool collectCompletedLegs, bool &outLegClosedThisBar)
{
   outLegClosedThisBar = false;
   const int sh = lastClosedBarShift;

   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, sh);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, sh);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, sh);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, sh);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);

   const double lastClosedBarBodyRange = MathAbs(lastClosedBarClose - lastClosedBarOpen);
   const double lastClosedBarWickRange  = lastClosedBarHigh - lastClosedBarLow;

   if(swingState.currentSwingLeg.swingDirection == 0)
   {
      if(candleDirection == 0)
         return;
      SwingStartNew(swingState, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow, sh);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      return;
   }

   double sumRangeFivePriorBars = 0.0;
   const int barsTotal = iBars(_Symbol, timeframe);
   int       rangeBarCount = 0;
   for(int barShiftIndex = sh + 1; barShiftIndex <= sh + 5; barShiftIndex++)
   {
      if(barShiftIndex >= barsTotal)
         break;
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, barShiftIndex) - iLow(_Symbol, timeframe, barShiftIndex));
      rangeBarCount++;
   }
   const double averageRangeFiveBars = (rangeBarCount > 0) ? sumRangeFivePriorBars / (double)rangeBarCount : 0.0;
   const double minDecentRange       = averageRangeFiveBars * anchorMultiplier;
   const bool isDecentMovement =
      useWickAndBodyForDecent
      ? (lastClosedBarWickRange > minDecentRange && lastClosedBarBodyRange > minDecentRange)
      : (lastClosedBarWickRange > minDecentRange);

   const double anchorForFlipCheck = swingState.priceAnchorLevel;
   int nextSwingDirection = swingState.currentSwingLeg.swingDirection;
   if(swingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < anchorForFlipCheck)
      nextSwingDirection = -1;
   else if(swingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > anchorForFlipCheck)
      nextSwingDirection = 1;

   if(nextSwingDirection == swingState.currentSwingLeg.swingDirection)
   {
      if(isDecentMovement && candleDirection == swingState.currentSwingLeg.swingDirection)
         swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);
      return;
   }

   SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

   Swing closedSwingLeg = swingState.currentSwingLeg;
   if(collectCompletedLegs)
   {
      closedSwingLeg.legEndTime = iTime(_Symbol, timeframe, sh);
      TryPushH4ReplayLeg(replayLegs, replayLegCount, closedSwingLeg);
      outLegClosedThisBar = true;
   }
   else
   {
      SwingCloseH4ToHistory(swingState, timeframe, sh);
      outLegClosedThisBar = true;
      if(swingState.swingHistoryCount < 1)
         return;
      closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
   }

   double newSwingLegHigh = lastClosedBarHigh;
   double newSwingLegLow  = lastClosedBarLow;
   if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
      newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
   else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
      newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

   SwingStartNew(swingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow, sh);
   swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
}

//+------------------------------------------------------------------+
void ProcessMTFSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                                 const int lastClosedBarShift, const double anchorMultiplier,
                                 const bool useWickAndBodyForDecent, bool &outLegClosedThisBar)
{
   H4ReplayLeg unusedReplayLegs[];
   int         unusedReplayLegCount = 0;
   ProcessMTFSwingStepAtShiftCollect(swingState, timeframe, lastClosedBarShift, anchorMultiplier,
                                      useWickAndBodyForDecent, unusedReplayLegs, unusedReplayLegCount,
                                      false, outLegClosedThisBar);
}

//+------------------------------------------------------------------+
bool SMCTryDetectBosOnBar(const SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                           const int barShift, int &outDirection, double &outBrokenLevel,
                           datetime &outBarOpenTime, datetime &outLegEndTime,
                           double &outLegHigh, double &outLegLow)
{
   outDirection   = 0;
   outBrokenLevel = 0.0;
   outBarOpenTime = 0;
   outLegEndTime  = 0;
   outLegHigh     = 0.0;
   outLegLow      = 0.0;

   if(barShift < 1 || swingState.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, timeframe, barShift);
   const double prevClose  = iClose(_Symbol, timeframe, barShift + 1);
   const double pointSize    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps          = (pointSize > 0.0 ? pointSize : 0.00001);

   outBarOpenTime = iTime(_Symbol, timeframe, barShift);
   if(outBarOpenTime == 0)
      return false;

   for(int historyIndex = swingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(swingState.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double legHigh = swingState.swingHistory[historyIndex].legHighPrice;
      if(closePrice > legHigh + eps && prevClose <= legHigh + eps)
      {
         outDirection   = 1;
         outBrokenLevel = legHigh;
         outLegEndTime  = swingState.swingHistory[historyIndex].legEndTime;
         outLegHigh     = swingState.swingHistory[historyIndex].legHighPrice;
         outLegLow      = swingState.swingHistory[historyIndex].legLowPrice;
         return true;
      }
      break;
   }

   for(int historyIndex = swingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(swingState.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double legLow = swingState.swingHistory[historyIndex].legLowPrice;
      if(closePrice < legLow - eps && prevClose >= legLow - eps)
      {
         outDirection   = -1;
         outBrokenLevel = legLow;
         outLegEndTime  = swingState.swingHistory[historyIndex].legEndTime;
         outLegHigh     = swingState.swingHistory[historyIndex].legHighPrice;
         outLegLow      = swingState.swingHistory[historyIndex].legLowPrice;
         return true;
      }
      break;
   }

   return false;
}

//+------------------------------------------------------------------+
string SMCMtfTimeframeLogTag(const ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_W1:  return "W1";
      case PERIOD_D1:  return "D1";
      case PERIOD_H4:  return "H4";
      case PERIOD_M15: return "M15";
   }
   return EnumToString(timeframe);
}

//+------------------------------------------------------------------+
void SMCUpdateTrackerBosOnBar(MTFSwingTracker &tracker, const int barShift)
{
   int        bosDir = 0;
   double     bosLevel = 0.0;
   datetime   barOpen = 0;
   datetime   legEnd = 0;
   double     legHigh = 0.0;
   double     legLow = 0.0;
   if(!SMCTryDetectBosOnBar(tracker.swing, tracker.timeframe, barShift, bosDir, bosLevel, barOpen,
                             legEnd, legHigh, legLow))
      return;

   tracker.lastBosDirection     = bosDir;
   tracker.lastBosLevel         = bosLevel;
   tracker.lastBosBarOpenTime   = barOpen;
   tracker.lastBrokenLegEndTime = legEnd;
   tracker.lastBrokenLegHigh    = legHigh;
   tracker.lastBrokenLegLow     = legLow;

   if(tracker.timeframe != 0)
      ProfessionalBiasSetDirection(tracker.timeframe, bosDir, barOpen);

   if(H4LqLoggingEnabled())
   {
      LogHuntEvent("MTF_BOS",
                   StringFormat("%s %s BOS bar=%s legEnd=%s lvl=%.5f",
                                SMCMtfTimeframeLogTag(tracker.timeframe),
                                bosDir == 1 ? "bull" : "bear",
                                TimeToString(barOpen, TIME_DATE | TIME_MINUTES),
                                TimeToString(legEnd, TIME_DATE | TIME_MINUTES),
                                bosLevel));
   }
}

//+------------------------------------------------------------------+
void SMCUpdateTrackerOnBarClose(MTFSwingTracker &tracker, const ENUM_TIMEFRAMES timeframe,
                                 datetime &lastBarOpen)
{
   const datetime barOpen = iTime(_Symbol, timeframe, 0);
   if(barOpen == 0 || barOpen == lastBarOpen)
      return;

   lastBarOpen = barOpen;
   if(tracker.timeframe == 0)
      tracker.timeframe = timeframe;

   bool legClosedThisBar = false;
   ProcessMTFSwingStepAtShift(tracker.swing, timeframe, 1, H4_BOS_ANCHOR_MULTIPLIER, false,
                              legClosedThisBar);

   SMCRefreshZonesForTimeframe(timeframe, tracker, legClosedThisBar);
   SMCUpdateTrackerBosOnBar(tracker, 1);

   if(timeframe == PERIOD_H4)
   {
      RebuildH4LiquidityPivotLevels();
      if(InputEnableH4BosTradeDirectionBias)
         LogH4TradeDirectionBiasIfChanged();
#ifdef H4_LQ_VOLUME_BREACH_ENABLED
      if(H4LqChartDrawEnabled(InputDrawMtfSwingLegsH4))
         RebuildAllH4VolumeBreachMarkers();
#endif
   }
}

//+------------------------------------------------------------------+
void WarmupMTFSwingTracker(MTFSwingTracker &tracker, const ENUM_TIMEFRAMES timeframe,
                            datetime &lastBarOpen)
{
   tracker.timeframe = timeframe;
   ZeroMemory(tracker.swing);
   tracker.lastBosDirection = 0;
   tracker.lastBosLevel     = 0.0;
   tracker.lastBrokenLegHigh = 0.0;
   tracker.lastBrokenLegLow  = 0.0;

   if(InputSmcMtfWarmupBars <= 0)
   {
      lastBarOpen = iTime(_Symbol, timeframe, 0);
      return;
   }

   const int bars = iBars(_Symbol, timeframe);
   const int n = (int)MathMin(bars - 2, InputSmcMtfWarmupBars);
   if(n >= 1)
   {
      for(int k = n; k >= 1; k--)
      {
         bool unusedLegClosed = false;
         ProcessMTFSwingStepAtShift(tracker.swing, timeframe, k, H4_BOS_ANCHOR_MULTIPLIER, false,
                                    unusedLegClosed);
         SMCUpdateTrackerBosOnBar(tracker, k);
      }
   }

   lastBarOpen = iTime(_Symbol, timeframe, 0);
}

//+------------------------------------------------------------------+
void WarmupMTFSwingsFromHistory()
{
   if(!InputEnableMtfSmcEngine)
      return;

   WarmupMTFSwingTracker(g_mtfSwingW1,  PERIOD_W1,  g_lastMtfBarOpenW1);
   WarmupMTFSwingTracker(g_mtfSwingD1,  PERIOD_D1,  g_lastMtfBarOpenD1);
   WarmupMTFSwingTracker(g_mtfSwingH4,  PERIOD_H4,  g_lastMtfBarOpenH4);
   WarmupMTFSwingTracker(g_mtfSwingM15, PERIOD_M15, g_lastMtfBarOpenM15);
}

//+------------------------------------------------------------------+
void UpdateMTFSwings()
{
   if(!InputEnableMtfSmcEngine)
      return;

   SMCUpdateTrackerOnBarClose(g_mtfSwingW1,  PERIOD_W1,  g_lastMtfBarOpenW1);
   SMCUpdateTrackerOnBarClose(g_mtfSwingD1,  PERIOD_D1,  g_lastMtfBarOpenD1);
   SMCUpdateTrackerOnBarClose(g_mtfSwingH4,  PERIOD_H4,  g_lastMtfBarOpenH4);
   SMCUpdateTrackerOnBarClose(g_mtfSwingM15, PERIOD_M15, g_lastMtfBarOpenM15);

   if(H4LqChartDrawEnabled(InputShowMtfDirectionHud))
      RefreshMtfDirectionHud();
}

//+------------------------------------------------------------------+
//| MTF SMC Phase 3–4 — zone matrix + fusion clustering               |
//+------------------------------------------------------------------+
bool SMCZoneTypeIsBullish(const ENUM_SMC_ZONE_TYPE type)
{
   return type < ZONE_BEAR_WEEKLY_FVG;
}

//+------------------------------------------------------------------+
bool SMCZoneTypeIsSwingLiquidity(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_SWING_W1_LOW:
      case ZONE_BULL_SWING_DAILY_LOW:
      case ZONE_BULL_SWING_H4_LOW:
      case ZONE_BULL_SWING_M15_LOW:
      case ZONE_BEAR_SWING_W1_HIGH:
      case ZONE_BEAR_SWING_DAILY_HIGH:
      case ZONE_BEAR_SWING_H4_HIGH:
      case ZONE_BEAR_SWING_M15_HIGH:
         return true;
      default:
         return false;
   }
}

//+------------------------------------------------------------------+
bool SMCZoneTypeIsMtfFvg(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_WEEKLY_FVG:
      case ZONE_BULL_DAILY_FVG:
      case ZONE_BULL_H4_FVG:
      case ZONE_BULL_M15_FVG:
      case ZONE_BEAR_WEEKLY_FVG:
      case ZONE_BEAR_DAILY_FVG:
      case ZONE_BEAR_H4_FVG:
      case ZONE_BEAR_M15_FVG:
         return true;
      default:
         return false;
   }
}

//+------------------------------------------------------------------+
bool SMCZonePassesCurrentPriceSideFilter(const ENUM_SMC_ZONE_TYPE type,
                                          const double top, const double bottom)
{
   if(top <= bottom)
      return false;

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(currentPrice <= 0.0)
      currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   if(currentPrice <= 0.0)
      currentPrice = iClose(_Symbol, PERIOD_CURRENT, 0);
   if(currentPrice <= 0.0)
      return true;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   if(SMCZoneTypeIsBullish(type))
      return top < currentPrice - eps;
   return bottom > currentPrice + eps;
}

//+------------------------------------------------------------------+
int GetZoneTimeframeStrength(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_WEEKLY_FVG:
      case ZONE_BEAR_WEEKLY_FVG:
         return 4;
      case ZONE_BULL_DAILY_FVG:
      case ZONE_BULL_PROTECTED_DAILY_LOW:
      case ZONE_BULL_SWING_DAILY_LOW:
      case ZONE_BEAR_DAILY_FVG:
      case ZONE_BEAR_PROTECTED_DAILY_HIGH:
      case ZONE_BEAR_SWING_DAILY_HIGH:
         return 3;
      case ZONE_BULL_H4_FVG:
      case ZONE_BULL_PROTECTED_H4_LOW:
      case ZONE_BULL_SWING_H4_LOW:
      case ZONE_BEAR_H4_FVG:
      case ZONE_BEAR_PROTECTED_H4_HIGH:
      case ZONE_BEAR_SWING_H4_HIGH:
         return 2;
      case ZONE_BULL_M15_FVG:
      case ZONE_BULL_PROTECTED_M15_LOW:
      case ZONE_BULL_SWING_M15_LOW:
      case ZONE_BEAR_M15_FVG:
      case ZONE_BEAR_PROTECTED_M15_HIGH:
      case ZONE_BEAR_SWING_M15_HIGH:
         return 1;
      case ZONE_BULL_SWING_W1_LOW:
      case ZONE_BEAR_SWING_W1_HIGH:
         return 4;
   }
   return 0;
}

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES SMCZoneTypeToTimeframe(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_WEEKLY_FVG:
      case ZONE_BEAR_WEEKLY_FVG:
         return PERIOD_W1;
      case ZONE_BULL_DAILY_FVG:
      case ZONE_BULL_PROTECTED_DAILY_LOW:
      case ZONE_BULL_SWING_DAILY_LOW:
      case ZONE_BEAR_DAILY_FVG:
      case ZONE_BEAR_PROTECTED_DAILY_HIGH:
      case ZONE_BEAR_SWING_DAILY_HIGH:
         return PERIOD_D1;
      case ZONE_BULL_H4_FVG:
      case ZONE_BULL_PROTECTED_H4_LOW:
      case ZONE_BULL_SWING_H4_LOW:
      case ZONE_BEAR_H4_FVG:
      case ZONE_BEAR_PROTECTED_H4_HIGH:
      case ZONE_BEAR_SWING_H4_HIGH:
         return PERIOD_H4;
      case ZONE_BULL_M15_FVG:
      case ZONE_BULL_PROTECTED_M15_LOW:
      case ZONE_BULL_SWING_M15_LOW:
      case ZONE_BEAR_M15_FVG:
      case ZONE_BEAR_PROTECTED_M15_HIGH:
      case ZONE_BEAR_SWING_M15_HIGH:
         return PERIOD_M15;
      case ZONE_BULL_SWING_W1_LOW:
      case ZONE_BEAR_SWING_W1_HIGH:
         return PERIOD_W1;
   }
   return PERIOD_CURRENT;
}

//+------------------------------------------------------------------+
bool SMCGetMtfSwingTracker(const ENUM_TIMEFRAMES timeframe, MTFSwingTracker &tracker)
{
   switch(timeframe)
   {
      case PERIOD_W1:  tracker = g_mtfSwingW1;  return true;
      case PERIOD_D1:  tracker = g_mtfSwingD1;  return true;
      case PERIOD_H4:  tracker = g_mtfSwingH4;  return true;
      case PERIOD_M15: tracker = g_mtfSwingM15; return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Per-TF MTF swing leg access — completed legs + unbroken extremes. |
//+------------------------------------------------------------------+
bool MtfIsSwingTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   return timeframe == PERIOD_W1 || timeframe == PERIOD_D1
       || timeframe == PERIOD_H4 || timeframe == PERIOD_M15;
}

//+------------------------------------------------------------------+
bool MtfCopySwingState(const ENUM_TIMEFRAMES timeframe, SwingState &outSwingState)
{
   MTFSwingTracker tracker;
   if(!SMCGetMtfSwingTracker(timeframe, tracker))
      return false;
   outSwingState = tracker.swing;
   return true;
}

//+------------------------------------------------------------------+
bool MtfTryNthCompletedSwingLeg(const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                                 const int nFromLatest,
                                 double &outLegHigh, double &outLegLow,
                                 datetime &outLegStartTime, datetime &outLegEndTime)
{
   outLegHigh      = 0.0;
   outLegLow       = 0.0;
   outLegStartTime = 0;
   outLegEndTime   = 0;
   if(!MtfIsSwingTimeframe(timeframe) || swingDirection == 0 || nFromLatest < 1)
      return false;

   SwingState swingState;
   if(!MtfCopySwingState(timeframe, swingState))
      return false;

   int legsFound = 0;
   for(int i = swingState.swingHistoryCount - 1; i >= 0; i--)
   {
      const Swing leg = swingState.swingHistory[i];
      if(leg.swingDirection != swingDirection || leg.legEndTime == 0)
         continue;
      legsFound++;
      if(legsFound == nFromLatest)
      {
         outLegHigh      = leg.legHighPrice;
         outLegLow       = leg.legLowPrice;
         outLegStartTime = leg.legStartTime;
         outLegEndTime   = leg.legEndTime;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool MtfTryLatestCompletedUpLegHigh(const ENUM_TIMEFRAMES timeframe, double &outHigh,
                                     datetime &outLegEndTime)
{
   datetime legStart = 0;
   double   legLow   = 0.0;
   return MtfTryNthCompletedSwingLeg(timeframe, 1, 1, outHigh, legLow, legStart, outLegEndTime);
}

//+------------------------------------------------------------------+
bool MtfTryLatestCompletedDownLegLow(const ENUM_TIMEFRAMES timeframe, double &outLow,
                                      datetime &outLegEndTime)
{
   datetime legStart = 0;
   double   legHigh  = 0.0;
   return MtfTryNthCompletedSwingLeg(timeframe, -1, 1, legHigh, outLow, legStart, outLegEndTime);
}

//+------------------------------------------------------------------+
bool MtfTryLatestUnbrokenSwingHigh(const ENUM_TIMEFRAMES timeframe, double &outLevel)
{
   SwingState swingState;
   if(!MtfCopySwingState(timeframe, swingState))
      return false;
   return SMCTryGetLatestUnbrokenSwingHigh(swingState, timeframe, outLevel);
}

//+------------------------------------------------------------------+
bool MtfTryLatestUnbrokenSwingLow(const ENUM_TIMEFRAMES timeframe, double &outLevel)
{
   SwingState swingState;
   if(!MtfCopySwingState(timeframe, swingState))
      return false;
   return SMCTryGetLatestUnbrokenSwingLow(swingState, timeframe, outLevel);
}

//+------------------------------------------------------------------+
bool MtfTryDetectBosCrossOnBar(const ENUM_TIMEFRAMES timeframe, const int barShift,
                                int &outDirection, double &outBrokenLevel,
                                datetime &outBarOpenTime, datetime &outLegEndTime)
{
   outDirection   = 0;
   outBrokenLevel = 0.0;
   outBarOpenTime = 0;
   outLegEndTime  = 0;

   SwingState swingState;
   if(!MtfCopySwingState(timeframe, swingState))
      return false;

   double legHigh = 0.0;
   double legLow  = 0.0;
   return SMCTryDetectBosOnBar(swingState, timeframe, barShift, outDirection, outBrokenLevel,
                               outBarOpenTime, outLegEndTime, legHigh, legLow);
}

//+------------------------------------------------------------------+
void ResetProfessionalBiasOverrideState()
{
   ZeroMemory(g_profBiasOverrideW1);
   ZeroMemory(g_profBiasOverrideD1);
   ZeroMemory(g_profBiasOverrideH4);
   ZeroMemory(g_profBiasOverrideM15);
}

//+------------------------------------------------------------------+
void ProfessionalBiasGetOverrideState(const ENUM_TIMEFRAMES timeframe,
                                       int &overrideBias, datetime &overrideTime)
{
   overrideBias = 0;
   overrideTime = 0;
   if(timeframe == PERIOD_W1)
   {
      overrideBias = g_profBiasOverrideW1.overrideBias;
      overrideTime = g_profBiasOverrideW1.overrideTime;
   }
   else if(timeframe == PERIOD_D1)
   {
      overrideBias = g_profBiasOverrideD1.overrideBias;
      overrideTime = g_profBiasOverrideD1.overrideTime;
   }
   else if(timeframe == PERIOD_H4)
   {
      overrideBias = g_profBiasOverrideH4.overrideBias;
      overrideTime = g_profBiasOverrideH4.overrideTime;
   }
   else if(timeframe == PERIOD_M15)
   {
      overrideBias = g_profBiasOverrideM15.overrideBias;
      overrideTime = g_profBiasOverrideM15.overrideTime;
   }
}

//+------------------------------------------------------------------+
void ProfessionalBiasSetDirection(const ENUM_TIMEFRAMES timeframe, const int bias,
                                     const datetime setBarOpen)
{
   if(bias == 0)
      return;

   if(timeframe == PERIOD_W1)
   {
      g_profBiasOverrideW1.overrideBias = bias;
      g_profBiasOverrideW1.overrideTime = setBarOpen;
   }
   else if(timeframe == PERIOD_D1)
   {
      g_profBiasOverrideD1.overrideBias = bias;
      g_profBiasOverrideD1.overrideTime = setBarOpen;
   }
   else if(timeframe == PERIOD_H4)
   {
      g_profBiasOverrideH4.overrideBias = bias;
      g_profBiasOverrideH4.overrideTime = setBarOpen;
   }
   else if(timeframe == PERIOD_M15)
   {
      g_profBiasOverrideM15.overrideBias = bias;
      g_profBiasOverrideM15.overrideTime = setBarOpen;
   }
}

//+------------------------------------------------------------------+
bool SMCZoneBarCloseRejectionBias(const double top, const double bottom,
                                   const double barClose, const double eps,
                                   int &outBias)
{
   outBias = 0;
   if(top <= bottom || barClose <= 0.0)
      return false;

   const bool closeInside = (barClose >= bottom - eps && barClose <= top + eps);
   if(closeInside)
      return false;

   if(barClose < bottom - eps)
   {
      outBias = BIAS_BEARISH;
      return true;
   }
   if(barClose > top + eps)
   {
      outBias = BIAS_BULLISH;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void SMCUpdateProfessionalBiasFromZoneBarClose(const ENUM_TIMEFRAMES timeframe)
{
   const double barClose = iClose(_Symbol, timeframe, 1);
   const datetime barOpen = iTime(_Symbol, timeframe, 1);
   if(barClose <= 0.0 || barOpen == 0)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   int          rejectionBias = 0;

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive || g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
         continue;
      if(!g_activeZones[i].isBreached)
         continue;
      if(SMCZoneTypeToTimeframe(g_activeZones[i].type) != timeframe)
         continue;

      int zoneBias = 0;
      if(SMCZoneBarCloseRejectionBias(g_activeZones[i].topPrice, g_activeZones[i].bottomPrice,
                                      barClose, eps, zoneBias))
         rejectionBias = zoneBias;
   }

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         continue;
      if(!g_mtfFvgInstances[f].isBreached)
         continue;
      if(g_mtfFvgInstances[f].timeframe != timeframe)
         continue;

      int zoneBias = 0;
      if(SMCZoneBarCloseRejectionBias(g_mtfFvgInstances[f].topPrice, g_mtfFvgInstances[f].bottomPrice,
                                      barClose, eps, zoneBias))
         rejectionBias = zoneBias;
   }

   if(rejectionBias != 0)
      ProfessionalBiasSetDirection(timeframe, rejectionBias, barOpen);
}

//+------------------------------------------------------------------+
int GetProfessionalBias(const ENUM_TIMEFRAMES timeframe)
{
   int storedBias = 0;
   datetime storedBarOpen = 0;
   ProfessionalBiasGetOverrideState(timeframe, storedBias, storedBarOpen);
   if(storedBias != 0)
      return storedBias;

   MTFSwingTracker tracker;
   if(!SMCGetMtfSwingTracker(timeframe, tracker))
      return 0;

   return tracker.lastBosDirection;
}

//+------------------------------------------------------------------+
double SMCSwingLevelBufferForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const double pointSize = (_Point > 0.0 ? _Point : 0.00001);
   if(InputSmcBrokenLevelBufferPercentChart <= 0.0)
      return pointSize;

   const int lookbackBars = MathMax(3, InputSmcFvgLookbackBars);
   const double chartHeight =
      ReferenceChartHeightForTimeframeBarCount(timeframe, lookbackBars);
   if(chartHeight <= 0.0)
      return pointSize;

   return chartHeight * (InputSmcBrokenLevelBufferPercentChart / 100.0);
}

//+------------------------------------------------------------------+
double SMCSwingLevelBufferForZoneType(const ENUM_SMC_ZONE_TYPE type)
{
   return SMCSwingLevelBufferForTimeframe(SMCZoneTypeToTimeframe(type));
}

//+------------------------------------------------------------------+
void SMCResetActiveZones()
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      g_activeZones[i].type               = (ENUM_SMC_ZONE_TYPE)0;
      g_activeZones[i].topPrice           = 0.0;
      g_activeZones[i].bottomPrice        = 0.0;
      g_activeZones[i].isActive           = false;
      g_activeZones[i].isClustered        = false;
      g_activeZones[i].isMitigated        = false;
      g_activeZones[i].isBreached         = false;
      g_activeZones[i].isExpired          = false;
      g_activeZones[i].zoneOriginBarTime  = 0;
   }

   for(int i = 0; i < SMC_ZONE_MITIGATION_LEDGER_CAPACITY; i++)
      g_zoneMitigationLedger[i].inUse = false;

   SMCResetMtfFvgInstances();
}

//+------------------------------------------------------------------+
bool SMCActiveZoneOverlapsPrices(const SMCZoneRecord &zone, const ENUM_SMC_ZONE_TYPE type,
                                  const double top, const double bottom, const double mergeBuffer)
{
   if(!zone.isActive || zone.type != type)
      return false;
   return top > zone.bottomPrice - mergeBuffer && bottom < zone.topPrice + mergeBuffer;
}

//+------------------------------------------------------------------+
int SMCFindActiveZoneSlotByTypeAndPrice(const ENUM_SMC_ZONE_TYPE type,
                                         const double top, const double bottom)
{
   const double mergeBuffer = SMCSwingLevelBufferForZoneType(type);
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(SMCActiveZoneOverlapsPrices(g_activeZones[i], type, top, bottom, mergeBuffer))
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
int SMCFindActiveZoneSlotByTypeAndOrigin(const ENUM_SMC_ZONE_TYPE type,
                                          const datetime originBarTime)
{
   if(originBarTime <= 0)
      return -1;

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
         continue;
      if(g_activeZones[i].type != type)
         continue;
      if(g_activeZones[i].zoneOriginBarTime == originBarTime)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
void SMCDeactivateZoneLedgerSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return;

   SMCDeleteAllZoneRectangleObjectsForSlot(slotIndex);
   g_activeZones[slotIndex].isActive           = false;
   g_activeZones[slotIndex].isClustered        = false;
   g_activeZones[slotIndex].isMitigated         = false;
   g_activeZones[slotIndex].isBreached          = false;
   g_activeZones[slotIndex].isExpired           = false;
   g_activeZones[slotIndex].zoneOriginBarTime   = 0;
}

//+------------------------------------------------------------------+
int SMCAllocZoneLedgerSlot()
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
      {
         SMCDeleteAllZoneRectangleObjectsForSlot(i);
         return i;
      }
   }

   int          evictIdx    = -1;
   datetime     oldestOrigin = 0;
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
         continue;
      if(g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
      {
         evictIdx = i;
         break;
      }
      if(evictIdx < 0
         || (g_activeZones[i].zoneOriginBarTime > 0
             && (oldestOrigin == 0 || g_activeZones[i].zoneOriginBarTime < oldestOrigin)))
      {
         oldestOrigin = g_activeZones[i].zoneOriginBarTime;
         evictIdx     = i;
      }
   }

   if(evictIdx < 0)
      return -1;

   SMCDeactivateZoneLedgerSlot(evictIdx);
   return evictIdx;
}

//+------------------------------------------------------------------+
void SMCApplyFreshZoneStateToSlot(const int slotIndex, const datetime originBarTime)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return;

   g_activeZones[slotIndex].isMitigated = false;
   g_activeZones[slotIndex].isBreached  = false;
   g_activeZones[slotIndex].isExpired   = false;
   if(originBarTime > 0)
      g_activeZones[slotIndex].zoneOriginBarTime = originBarTime;

   const int ledgerIndex = SMCFindMitigationLedgerIndex(g_activeZones[slotIndex].type,
                                                        g_activeZones[slotIndex].topPrice,
                                                        g_activeZones[slotIndex].bottomPrice, true,
                                                        g_activeZones[slotIndex].zoneOriginBarTime);
   if(ledgerIndex < 0)
      return;

   g_zoneMitigationLedger[ledgerIndex].isMitigated       = false;
   g_zoneMitigationLedger[ledgerIndex].isBreached        = false;
   g_zoneMitigationLedger[ledgerIndex].isExpired         = false;
   g_zoneMitigationLedger[ledgerIndex].zoneOriginBarTime = g_activeZones[slotIndex].zoneOriginBarTime;
}

//+------------------------------------------------------------------+
bool SMCLedgerOverlapsZonePrices(const SMCZoneMitigationLedgerEntry &entry,
                                  const ENUM_SMC_ZONE_TYPE type,
                                  const double top, const double bottom,
                                  const double mergeBuffer)
{
   if(!entry.inUse || entry.type != type)
      return false;
   return top > entry.bottomPrice - mergeBuffer && bottom < entry.topPrice + mergeBuffer;
}

//+------------------------------------------------------------------+
int SMCFindMitigationLedgerIndex(const ENUM_SMC_ZONE_TYPE type, const double top,
                                  const double bottom, const bool createIfMissing,
                                  const datetime originBarTime = 0)
{
   const double mergeBuffer = SMCSwingLevelBufferForZoneType(type);
   int          freeIndex   = -1;

   if(originBarTime > 0 && SMCZoneTypeIsSwingLiquidity(type))
   {
      for(int i = 0; i < SMC_ZONE_MITIGATION_LEDGER_CAPACITY; i++)
      {
         if(!g_zoneMitigationLedger[i].inUse)
         {
            if(freeIndex < 0)
               freeIndex = i;
            continue;
         }
         if(g_zoneMitigationLedger[i].type == type
            && g_zoneMitigationLedger[i].zoneOriginBarTime == originBarTime)
            return i;
      }

      if(!createIfMissing || freeIndex < 0)
         return -1;

      g_zoneMitigationLedger[freeIndex].inUse               = true;
      g_zoneMitigationLedger[freeIndex].type                = type;
      g_zoneMitigationLedger[freeIndex].topPrice            = top;
      g_zoneMitigationLedger[freeIndex].bottomPrice         = bottom;
      g_zoneMitigationLedger[freeIndex].isMitigated         = false;
      g_zoneMitigationLedger[freeIndex].isBreached          = false;
      g_zoneMitigationLedger[freeIndex].isExpired           = false;
      g_zoneMitigationLedger[freeIndex].zoneOriginBarTime   = originBarTime;
      return freeIndex;
   }

   for(int i = 0; i < SMC_ZONE_MITIGATION_LEDGER_CAPACITY; i++)
   {
      if(!g_zoneMitigationLedger[i].inUse)
      {
         if(freeIndex < 0)
            freeIndex = i;
         continue;
      }
      if(SMCLedgerOverlapsZonePrices(g_zoneMitigationLedger[i], type, top, bottom, mergeBuffer))
         return i;
   }

   if(!createIfMissing || freeIndex < 0)
      return -1;

   g_zoneMitigationLedger[freeIndex].inUse               = true;
   g_zoneMitigationLedger[freeIndex].type                = type;
   g_zoneMitigationLedger[freeIndex].topPrice            = top;
   g_zoneMitigationLedger[freeIndex].bottomPrice         = bottom;
   g_zoneMitigationLedger[freeIndex].isMitigated  = false;
   g_zoneMitigationLedger[freeIndex].isBreached   = false;
   g_zoneMitigationLedger[freeIndex].isExpired    = false;
   const ENUM_TIMEFRAMES originTf = SMCZoneTypeToTimeframe(type);
   g_zoneMitigationLedger[freeIndex].zoneOriginBarTime   =
      (originTf != PERIOD_CURRENT ? iTime(_Symbol, originTf, 1) : 0);
   return freeIndex;
}

//+------------------------------------------------------------------+
void SMCApplyMitigationLedgerToSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY || !g_activeZones[slotIndex].isActive)
      return;

   const ENUM_SMC_ZONE_TYPE type   = g_activeZones[slotIndex].type;
   const double             top    = g_activeZones[slotIndex].topPrice;
   const double             bottom = g_activeZones[slotIndex].bottomPrice;
   const datetime           origin = g_activeZones[slotIndex].zoneOriginBarTime;
   const int ledgerIndex = SMCFindMitigationLedgerIndex(type, top, bottom, true, origin);
   if(ledgerIndex < 0)
      return;

   g_zoneMitigationLedger[ledgerIndex].topPrice    = top;
   g_zoneMitigationLedger[ledgerIndex].bottomPrice = bottom;
   g_activeZones[slotIndex].isMitigated  = g_zoneMitigationLedger[ledgerIndex].isMitigated;
   g_activeZones[slotIndex].isBreached   = g_zoneMitigationLedger[ledgerIndex].isBreached;
   g_activeZones[slotIndex].isExpired    = g_zoneMitigationLedger[ledgerIndex].isExpired;
   g_activeZones[slotIndex].zoneOriginBarTime   = g_zoneMitigationLedger[ledgerIndex].zoneOriginBarTime;
   if(g_activeZones[slotIndex].zoneOriginBarTime == 0)
   {
      const ENUM_TIMEFRAMES originTf = SMCZoneTypeToTimeframe(type);
      if(originTf != PERIOD_CURRENT)
      {
         g_activeZones[slotIndex].zoneOriginBarTime = iTime(_Symbol, originTf, 1);
         g_zoneMitigationLedger[ledgerIndex].zoneOriginBarTime =
            g_activeZones[slotIndex].zoneOriginBarTime;
      }
   }
}

//+------------------------------------------------------------------+
void SMCSaveZoneMitigationToLedger(const SMCZoneRecord &zone)
{
   const int ledgerIndex =
      SMCFindMitigationLedgerIndex(zone.type, zone.topPrice, zone.bottomPrice, true,
                                   zone.zoneOriginBarTime);
   if(ledgerIndex < 0)
      return;

   g_zoneMitigationLedger[ledgerIndex].type               = zone.type;
   g_zoneMitigationLedger[ledgerIndex].topPrice           = zone.topPrice;
   g_zoneMitigationLedger[ledgerIndex].bottomPrice        = zone.bottomPrice;
   g_zoneMitigationLedger[ledgerIndex].isMitigated  = zone.isMitigated;
   g_zoneMitigationLedger[ledgerIndex].isBreached   = zone.isBreached;
   g_zoneMitigationLedger[ledgerIndex].isExpired    = zone.isExpired;
   g_zoneMitigationLedger[ledgerIndex].zoneOriginBarTime    = zone.zoneOriginBarTime;
}

//+------------------------------------------------------------------+
bool SMCZonePastExpiryBarLimit(const ENUM_SMC_ZONE_TYPE type, const datetime zoneOriginBarTime)
{
   if(zoneOriginBarTime == 0 || InputSmcZoneExpiryBars <= 0)
      return false;

   const ENUM_TIMEFRAMES tf = SMCZoneTypeToTimeframe(type);
   if(tf == PERIOD_CURRENT)
      return false;

   const int originShift = iBarShift(_Symbol, tf, zoneOriginBarTime, true);
   if(originShift < 0)
      return true;

   return originShift > InputSmcZoneExpiryBars;
}

//+------------------------------------------------------------------+
datetime SMCZoneRectangleTimeRight(const ENUM_TIMEFRAMES timeframe, const datetime zoneOriginBarTime)
{
   if(zoneOriginBarTime <= 0)
      return 0;

   const int periodSec = PeriodSeconds(timeframe);
   if(periodSec <= 0)
      return zoneOriginBarTime;

   const int expiryBars = (InputSmcZoneExpiryBars > 0 ? InputSmcZoneExpiryBars : 292);
   return zoneOriginBarTime + (datetime)(periodSec * expiryBars);
}

//+------------------------------------------------------------------+
void SMCExpireZonesPastBarLimit()
{
   SMCExpireZonesPastBarLimitForTimeframe(PERIOD_W1);
   SMCExpireZonesPastBarLimitForTimeframe(PERIOD_D1);
   SMCExpireZonesPastBarLimitForTimeframe(PERIOD_H4);
   SMCExpireZonesPastBarLimitForTimeframe(PERIOD_M15);
}

//+------------------------------------------------------------------+
void SMCExpireZonesPastBarLimitForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive || g_activeZones[i].isExpired)
         continue;
      if(SMCZoneTypeToTimeframe(g_activeZones[i].type) != timeframe)
         continue;

      if(SMCZonePastExpiryBarLimit(g_activeZones[i].type, g_activeZones[i].zoneOriginBarTime))
      {
         g_activeZones[i].isExpired = true;
         SMCSaveZoneMitigationToLedger(g_activeZones[i]);
      }
   }
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool SMCBarWicksIntoZone(const double top, const double bottom,
                          const double barHigh, const double barLow, const double eps)
{
   return (barHigh >= bottom - eps && barLow <= top + eps);
}

//+------------------------------------------------------------------+
bool SMCBarClosesOutsideZone(const double top, const double bottom,
                              const double barClose, const double eps)
{
   return (barClose < bottom - eps || barClose > top + eps);
}

//+------------------------------------------------------------------+
//| Gap/skip: close on far side of zone (bull below bottom, bear above top). |
//+------------------------------------------------------------------+
bool SMCBarClosesThroughZoneOppositeSide(const ENUM_SMC_ZONE_TYPE zoneType,
                                          const double top, const double bottom,
                                          const double barClose, const double eps)
{
   if(barClose <= 0.0)
      return false;
   if(SMCZoneTypeIsBullish(zoneType))
      return barClose < bottom - eps;
   return barClose > top + eps;
}

//+------------------------------------------------------------------+
bool SMCZoneOriginBarDeferMitigation(const datetime barOpen, const datetime zoneOriginBarTime)
{
   return (zoneOriginBarTime > 0 && barOpen > 0 && barOpen <= zoneOriginBarTime);
}

//+------------------------------------------------------------------+
bool SMCZoneDeferMitigationOnThisBar(const ENUM_SMC_ZONE_TYPE zoneType,
                                      const datetime barOpen,
                                      const datetime zoneOriginBarTime)
{
   if(SMCZoneTypeIsMtfFvg(zoneType))
      return false;
   return SMCZoneOriginBarDeferMitigation(barOpen, zoneOriginBarTime);
}

//+------------------------------------------------------------------+
//| Step 1 breach (wick OR close-through). Step 2 mitigate once breached + close outside (same or later bar). |
//+------------------------------------------------------------------+
bool SMCApplyZoneBreachAndMitigationOnClosedBar(bool &isBreached, bool &isMitigated,
                                                 const ENUM_SMC_ZONE_TYPE zoneType,
                                                 const double top, const double bottom,
                                                 const double barHigh, const double barLow,
                                                 const double barClose, const double eps,
                                                 const datetime barOpen,
                                                 const datetime zoneOriginBarTime,
                                                 int &outBias)
{
   outBias = 0;
   if(isMitigated || top <= bottom)
      return false;
   if(SMCZoneDeferMitigationOnThisBar(zoneType, barOpen, zoneOriginBarTime))
      return false;
   if(barClose <= 0.0 || barHigh <= 0.0 || barLow <= 0.0)
      return false;

   const bool wickBreach         = SMCBarWicksIntoZone(top, bottom, barHigh, barLow, eps);
   const bool closeThroughBreach = SMCBarClosesThroughZoneOppositeSide(zoneType, top, bottom, barClose, eps);
   const bool closeOutside       = SMCBarClosesOutsideZone(top, bottom, barClose, eps);

   if(!isBreached && (wickBreach || closeThroughBreach))
      isBreached = true;

   if(!isBreached || !closeOutside)
      return false;

   int zoneBias = 0;
   if(SMCZoneBarCloseRejectionBias(top, bottom, barClose, eps, zoneBias))
      outBias = zoneBias;

   isMitigated = true;
   return true;
}

//+------------------------------------------------------------------+
void SMCApplyZoneBreachOnClosedBar(bool &isBreached,
                                    const ENUM_SMC_ZONE_TYPE zoneType,
                                    const double top, const double bottom,
                                    const double barHigh, const double barLow,
                                    const double barClose,
                                    const double eps,
                                    const datetime barOpen,
                                    const datetime zoneOriginBarTime)
{
   if(top <= bottom || isBreached)
      return;
   if(SMCZoneDeferMitigationOnThisBar(zoneType, barOpen, zoneOriginBarTime))
      return;

   if(SMCBarWicksIntoZone(top, bottom, barHigh, barLow, eps))
      isBreached = true;
   else if(barClose > 0.0
           && SMCBarClosesThroughZoneOppositeSide(zoneType, top, bottom, barClose, eps))
      isBreached = true;
}

//+------------------------------------------------------------------+
void SMCApplyZoneMitigationOnClosedBar(bool &isMitigated, bool &isBreached,
                                        const ENUM_SMC_ZONE_TYPE zoneType,
                                        const double top, const double bottom,
                                        const double barHigh, const double barLow,
                                        const double barClose, const double eps,
                                        const datetime barOpen,
                                        const datetime zoneOriginBarTime,
                                        int &outBias)
{
   SMCApplyZoneBreachAndMitigationOnClosedBar(isBreached, isMitigated, zoneType,
                                              top, bottom, barHigh, barLow, barClose, eps,
                                              barOpen, zoneOriginBarTime, outBias);
}

//+------------------------------------------------------------------+
void SMCAdvanceZoneBreachLedgerOnBarClose(const ENUM_TIMEFRAMES timeframe)
{
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   const double barHigh   = iHigh(_Symbol, timeframe, 1);
   const double barLow    = iLow(_Symbol, timeframe, 1);
   const double barClose  = iClose(_Symbol, timeframe, 1);
   const datetime barOpen = iTime(_Symbol, timeframe, 1);
   if(barHigh <= 0.0 || barLow <= 0.0 || barClose <= 0.0)
      return;

   for(int i = 0; i < SMC_ZONE_MITIGATION_LEDGER_CAPACITY; i++)
   {
      if(!g_zoneMitigationLedger[i].inUse || g_zoneMitigationLedger[i].isMitigated
         || g_zoneMitigationLedger[i].isExpired)
         continue;
      if(SMCZoneTypeToTimeframe(g_zoneMitigationLedger[i].type) != timeframe)
         continue;

      int unusedBias = 0;
      SMCApplyZoneBreachAndMitigationOnClosedBar(g_zoneMitigationLedger[i].isBreached,
                                                  g_zoneMitigationLedger[i].isMitigated,
                                                  g_zoneMitigationLedger[i].type,
                                                  g_zoneMitigationLedger[i].topPrice,
                                                  g_zoneMitigationLedger[i].bottomPrice,
                                                  barHigh, barLow, barClose, eps, barOpen,
                                                  g_zoneMitigationLedger[i].zoneOriginBarTime,
                                                  unusedBias);
   }
}

//+------------------------------------------------------------------+
void SMCUpdateZoneBreachForActiveZonesTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   SMCApplyZoneExitBiasAndMitigationForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void SMCUpdateMtfFvgZoneBreachForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   // Unified in SMCApplyZoneExitBiasAndMitigationForTimeframe.
}

//+------------------------------------------------------------------+
void SMCUpdateActiveZonesMitigation()
{
   SMCUpdateActiveZonesMitigationForTimeframe(PERIOD_W1);
   SMCUpdateActiveZonesMitigationForTimeframe(PERIOD_D1);
   SMCUpdateActiveZonesMitigationForTimeframe(PERIOD_H4);
   SMCUpdateActiveZonesMitigationForTimeframe(PERIOD_M15);
}

//+------------------------------------------------------------------+
void SMCUpdateActiveZonesMitigationForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   SMCApplyZoneExitBiasAndMitigationForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
//| Breach (wick or close-through) then mitigate (close-outside) same bar; bias on exit. |
//+------------------------------------------------------------------+
void SMCApplyZoneExitBiasAndMitigationForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   const double barHigh   = iHigh(_Symbol, timeframe, 1);
   const double barLow    = iLow(_Symbol, timeframe, 1);
   const double barClose  = iClose(_Symbol, timeframe, 1);
   const datetime barOpen = iTime(_Symbol, timeframe, 1);
   if(barHigh <= 0.0 || barLow <= 0.0 || barClose <= 0.0 || barOpen == 0)
      return;

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive || g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
         continue;

      const ENUM_SMC_ZONE_TYPE zoneType = g_activeZones[i].type;
      if(SMCZoneTypeToTimeframe(zoneType) != timeframe)
         continue;

      const int ledgerIndex = SMCFindMitigationLedgerIndex(zoneType,
                                                            g_activeZones[i].topPrice,
                                                            g_activeZones[i].bottomPrice, false,
                                                            g_activeZones[i].zoneOriginBarTime);
      if(ledgerIndex >= 0 && g_zoneMitigationLedger[ledgerIndex].isBreached)
         g_activeZones[i].isBreached = true;

      int zoneBias = 0;
      const bool mitigatedNow = SMCApplyZoneBreachAndMitigationOnClosedBar(
         g_activeZones[i].isBreached,
         g_activeZones[i].isMitigated,
         zoneType,
         g_activeZones[i].topPrice,
         g_activeZones[i].bottomPrice,
         barHigh, barLow, barClose, eps, barOpen,
         g_activeZones[i].zoneOriginBarTime,
         zoneBias);

      if(zoneBias != 0)
         ProfessionalBiasSetDirection(timeframe, zoneBias, barOpen);

      if(mitigatedNow)
      {
         g_activeZones[i].isActive = false;
         SMCSaveZoneMitigationToLedger(g_activeZones[i]);
         SMCDeleteAllZoneRectangleObjectsForSlot(i);
      }
      else if(g_activeZones[i].isBreached)
         SMCSaveZoneMitigationToLedger(g_activeZones[i]);
   }

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         continue;
      if(g_mtfFvgInstances[f].timeframe != timeframe)
         continue;

      int zoneBias = 0;
      const bool mitigatedNow = SMCApplyZoneBreachAndMitigationOnClosedBar(
         g_mtfFvgInstances[f].isBreached,
         g_mtfFvgInstances[f].isMitigated,
         g_mtfFvgInstances[f].type,
         g_mtfFvgInstances[f].topPrice,
         g_mtfFvgInstances[f].bottomPrice,
         barHigh, barLow, barClose, eps, barOpen,
         g_mtfFvgInstances[f].zoneOriginBarTime,
         zoneBias);

      if(zoneBias != 0)
         ProfessionalBiasSetDirection(timeframe, zoneBias, barOpen);

      if(mitigatedNow)
      {
         SMCMitigateOverlappingMtfFvgPeers(f);
         g_mtfFvgInstances[f].inUse = false;
         SMCDeleteMtfFvgRectangleForInstance(g_mtfFvgInstances[f].type,
                                             g_mtfFvgInstances[f].zoneOriginBarTime);
      }
   }
}

//+------------------------------------------------------------------+
bool SMCZoneRegistrationAllowed(const ENUM_SMC_ZONE_TYPE type,
                                 const double top, const double bottom)
{
   if(SMCZoneTypeIsSwingLiquidity(type))
      return true;

   if(SMCZonePassesCurrentPriceSideFilter(type, top, bottom))
      return true;

   const int ledgerIndex = SMCFindMitigationLedgerIndex(type, top, bottom, false);
   if(ledgerIndex >= 0 && g_zoneMitigationLedger[ledgerIndex].inUse
      && !g_zoneMitigationLedger[ledgerIndex].isMitigated
      && !g_zoneMitigationLedger[ledgerIndex].isExpired)
      return true;

   return false;
}

//+------------------------------------------------------------------+
int RegisterOrMergeZone(const ENUM_SMC_ZONE_TYPE newType, const double top,
                         const double bottom, const datetime originBarTime = 0,
                         const bool forceFreshZoneState = false)
{
   if(newType < 0 || newType >= SMC_ZONE_TYPE_COUNT)
      return -1;
   if(top <= bottom)
      return -1;
   if(SMCZoneTypeIsMtfFvg(newType))
      return -1;
   if(!SMCZoneRegistrationAllowed(newType, top, bottom))
      return -1;

   datetime origin = originBarTime;
   if(origin <= 0)
   {
      const ENUM_TIMEFRAMES originTf = SMCZoneTypeToTimeframe(newType);
      if(originTf != PERIOD_CURRENT)
         origin = iTime(_Symbol, originTf, 1);
   }

   int slot = -1;
   if(SMCZoneTypeIsSwingLiquidity(newType) && origin > 0)
      slot = SMCFindActiveZoneSlotByTypeAndOrigin(newType, origin);
   else
      slot = SMCFindActiveZoneSlotByTypeAndPrice(newType, top, bottom);
   if(slot < 0)
   {
      slot = SMCAllocZoneLedgerSlot();
      if(slot < 0)
         return -1;

      SMCDeleteAllZoneRectangleObjectsForSlot(slot);

      g_activeZones[slot].type               = newType;
      g_activeZones[slot].topPrice           = top;
      g_activeZones[slot].bottomPrice        = bottom;
      g_activeZones[slot].isActive           = true;
      g_activeZones[slot].isClustered        = false;
      g_activeZones[slot].zoneOriginBarTime  = origin;
      if(forceFreshZoneState)
         SMCApplyFreshZoneStateToSlot(slot, origin);
      else
      {
         g_activeZones[slot].isMitigated = false;
         g_activeZones[slot].isBreached  = false;
         g_activeZones[slot].isExpired   = false;
      }
      SMCApplyMitigationLedgerToSlot(slot);
      return slot;
   }

   g_activeZones[slot].topPrice    = top;
   g_activeZones[slot].bottomPrice = bottom;
   if(origin > 0)
      g_activeZones[slot].zoneOriginBarTime = origin;
   if(forceFreshZoneState)
      SMCApplyFreshZoneStateToSlot(slot, origin);
   SMCApplyMitigationLedgerToSlot(slot);
   return slot;
}

//+------------------------------------------------------------------+
bool SMCDetectFvgAtMiddleShift(const ENUM_TIMEFRAMES timeframe, const int middleShift,
                                bool &outIsBullish, double &outBottom, double &outTop)
{
   outIsBullish = false;
   outBottom    = 0.0;
   outTop       = 0.0;

   const int oldestShift = middleShift + 1;
   const int newestShift = middleShift - 1;
   if(middleShift < 1 || oldestShift >= iBars(_Symbol, timeframe))
      return false;

   const double oldestHigh = iHigh(_Symbol, timeframe, oldestShift);
   const double oldestLow  = iLow(_Symbol, timeframe, oldestShift);
   const double newestHigh = iHigh(_Symbol, timeframe, newestShift);
   const double newestLow  = iLow(_Symbol, timeframe, newestShift);

   if(newestLow > oldestHigh)
   {
      outIsBullish = true;
      outBottom    = oldestHigh;
      outTop       = newestLow;
      return outTop > outBottom;
   }

   if(newestHigh < oldestLow)
   {
      outIsBullish = false;
      outBottom    = newestHigh;
      outTop       = oldestLow;
      return outTop > outBottom;
   }

   return false;
}

//+------------------------------------------------------------------+
bool SMCFvgGapMeetsMinPercentOfChart(const ENUM_TIMEFRAMES timeframe,
                                      const double gapBottom, const double gapTop)
{
   const double gapSize = gapTop - gapBottom;
   if(gapSize <= 0.0)
      return false;

   if(InputSmcFvgMinGapPercentChart <= 0.0)
      return true;

   const int lookbackBars = MathMax(3, InputSmcFvgLookbackBars);
   const double chartHeight = ReferenceChartHeightForTimeframeBarCount(timeframe, lookbackBars);
   if(chartHeight <= 0.0)
      return false;

   const double minGap = chartHeight * (InputSmcFvgMinGapPercentChart / 100.0);
   return gapSize >= minGap;
}

//+------------------------------------------------------------------+
bool SMCFvgMitigated(const ENUM_TIMEFRAMES timeframe, const int formationNewestShift,
                      const bool isBullish, const double bottomPrice, const double topPrice)
{
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   for(int shift = formationNewestShift - 1; shift >= 0; shift--)
   {
      const double barClose = iClose(_Symbol, timeframe, shift);
      if(isBullish && barClose < bottomPrice - eps)
         return true;
      if(!isBullish && barClose > topPrice + eps)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
double SMCFvgPriceFacingInsetForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   if(InputSmcFvgZonePriceFacingInsetPercentChart <= 0.0)
      return 0.0;

   const int lookbackBars = MathMax(3, InputSmcFvgLookbackBars);
   const double chartHeight = ReferenceChartHeightForTimeframeBarCount(timeframe, lookbackBars);
   if(chartHeight <= 0.0)
      return 0.0;

   return chartHeight * (InputSmcFvgZonePriceFacingInsetPercentChart / 100.0);
}

//+------------------------------------------------------------------+
bool SMCApplyMtfFvgGapZoneEdges(const ENUM_TIMEFRAMES timeframe, const bool isBullish,
                                 const double gapBottom, const double gapTop,
                                 double &outBottom, double &outTop)
{
   outBottom = gapBottom;
   outTop    = gapTop;

   const double inset = SMCFvgPriceFacingInsetForTimeframe(timeframe);
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minGap    = (pointSize > 0.0 ? pointSize : 0.00001);

   if(inset > 0.0)
   {
      if(isBullish)
         outTop = gapTop - inset;
      else
         outBottom = gapBottom + inset;
   }

   return outTop > outBottom + minGap;
}

//+------------------------------------------------------------------+
void SMCResetMtfFvgInstances()
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
      g_mtfFvgInstances[i].inUse = false;

   SMCDeleteMtfFvgZoneRectanglesForTimeframe(PERIOD_W1);
   SMCDeleteMtfFvgZoneRectanglesForTimeframe(PERIOD_D1);
   SMCDeleteMtfFvgZoneRectanglesForTimeframe(PERIOD_H4);
   SMCDeleteMtfFvgZoneRectanglesForTimeframe(PERIOD_M15);
}

//+------------------------------------------------------------------+
int SMCFindMtfFvgInstanceIndex(const ENUM_SMC_ZONE_TYPE type, const datetime originBarTime)
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
   {
      if(!g_mtfFvgInstances[i].inUse)
         continue;
      if(g_mtfFvgInstances[i].type != type)
         continue;
      if(g_mtfFvgInstances[i].zoneOriginBarTime == originBarTime)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
int SMCAllocMtfFvgInstanceIndex()
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
   {
      if(!g_mtfFvgInstances[i].inUse)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
void SMCUpsertMtfFvgInstance(const ENUM_SMC_ZONE_TYPE type, const double bottom, const double top,
                                const datetime originBarTime)
{
   if(!SMCZoneTypeIsMtfFvg(type) || top <= bottom || originBarTime <= 0)
      return;

   int idx = SMCFindMtfFvgInstanceIndex(type, originBarTime);
   if(idx < 0)
   {
      idx = SMCAllocMtfFvgInstanceIndex();
      if(idx < 0)
         return;

      g_mtfFvgInstances[idx].inUse              = true;
      g_mtfFvgInstances[idx].type               = type;
      g_mtfFvgInstances[idx].timeframe          = SMCZoneTypeToTimeframe(type);
      g_mtfFvgInstances[idx].isMitigated = false;
      g_mtfFvgInstances[idx].isBreached  = false;
      g_mtfFvgInstances[idx].isExpired   = false;
      g_mtfFvgInstances[idx].zoneOriginBarTime  = originBarTime;
   }

   g_mtfFvgInstances[idx].topPrice    = top;
   g_mtfFvgInstances[idx].bottomPrice = bottom;
}

//+------------------------------------------------------------------+
bool SMCPriceRangesOverlap(const double topA, const double bottomA,
                            const double topB, const double bottomB, const double eps)
{
   return topA > bottomB - eps && bottomA < topB + eps;
}

//+------------------------------------------------------------------+
void SMCMitigateOverlappingMtfFvgPeers(const int sourceIndex)
{
   if(sourceIndex < 0 || sourceIndex >= SMC_MTF_FVG_INSTANCE_CAPACITY)
      return;
   if(!g_mtfFvgInstances[sourceIndex].inUse)
      return;

   const ENUM_SMC_ZONE_TYPE sourceType = g_mtfFvgInstances[sourceIndex].type;
   const ENUM_TIMEFRAMES    sourceTf   = g_mtfFvgInstances[sourceIndex].timeframe;
   const double             sourceTop  = g_mtfFvgInstances[sourceIndex].topPrice;
   const double             sourceBot  = g_mtfFvgInstances[sourceIndex].bottomPrice;
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(f == sourceIndex)
         continue;
      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         continue;
      if(g_mtfFvgInstances[f].type != sourceType)
         continue;
      if(g_mtfFvgInstances[f].timeframe != sourceTf)
         continue;
      if(!SMCPriceRangesOverlap(sourceTop, sourceBot,
                                g_mtfFvgInstances[f].topPrice, g_mtfFvgInstances[f].bottomPrice, eps))
         continue;

      g_mtfFvgInstances[f].isMitigated = true;
      g_mtfFvgInstances[f].inUse       = false;
      SMCDeleteMtfFvgRectangleForInstance(g_mtfFvgInstances[f].type,
                                          g_mtfFvgInstances[f].zoneOriginBarTime);
   }
}

//+------------------------------------------------------------------+
void SMCUpdateMtfFvgInstancesMitigationForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   // FVG exit bias + mitigation handled in SMCApplyZoneExitBiasAndMitigationForTimeframe.
}

//+------------------------------------------------------------------+
void SMCExpireMtfFvgInstancesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
   {
      if(!g_mtfFvgInstances[i].inUse || g_mtfFvgInstances[i].isExpired)
         continue;
      if(g_mtfFvgInstances[i].timeframe != timeframe)
         continue;

      if(SMCZonePastExpiryBarLimit(g_mtfFvgInstances[i].type, g_mtfFvgInstances[i].zoneOriginBarTime))
         g_mtfFvgInstances[i].isExpired = true;
   }
}

//+------------------------------------------------------------------+
string SMCMtfFvgRectangleObjectName(const ENUM_SMC_ZONE_TYPE zoneType, const datetime originBarTime)
{
   const ENUM_TIMEFRAMES zoneTf = SMCZoneTypeToTimeframe(zoneType);
   return LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(zoneTf) + "_FVG_"
          + IntegerToString((long)originBarTime);
}

//+------------------------------------------------------------------+
void SMCDeleteMtfFvgZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const string prefix = LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(timeframe) + "_FVG_";
   ObjectsDeleteAll(0, prefix, -1, -1);
}

//+------------------------------------------------------------------+
void SMCDeleteMtfFvgRectangleForInstance(const ENUM_SMC_ZONE_TYPE zoneType,
                                            const datetime originBarTime)
{
   const string objName = SMCMtfFvgRectangleObjectName(zoneType, originBarTime);
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
}

//+------------------------------------------------------------------+
void SMCDrawMtfFvgRectangleForInstance(const int instanceIndex)
{
   if(instanceIndex < 0 || instanceIndex >= SMC_MTF_FVG_INSTANCE_CAPACITY)
      return;
   if(!g_mtfFvgInstances[instanceIndex].inUse || g_mtfFvgInstances[instanceIndex].isMitigated
      || g_mtfFvgInstances[instanceIndex].isExpired)
      return;

   const ENUM_TIMEFRAMES timeframe = g_mtfFvgInstances[instanceIndex].timeframe;
   if(!MtfSwingLegDrawEnabled(timeframe))
      return;

   const datetime timeLeft = g_mtfFvgInstances[instanceIndex].zoneOriginBarTime;
   const datetime timeRight = SMCZoneRectangleTimeRight(timeframe, timeLeft);
   const string objName = SMCMtfFvgRectangleObjectName(g_mtfFvgInstances[instanceIndex].type,
                                                        g_mtfFvgInstances[instanceIndex].zoneOriginBarTime);
   const double top    = g_mtfFvgInstances[instanceIndex].topPrice;
   const double bottom = g_mtfFvgInstances[instanceIndex].bottomPrice;
   if(timeLeft <= 0 || timeRight <= 0 || top <= bottom)
      return;

   if(ObjectFind(0, objName) < 0)
   {
      if(!ObjectCreate(0, objName, OBJ_RECTANGLE, 0, timeLeft, top, timeRight, bottom))
         return;
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, timeLeft);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, top);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeRight);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, bottom);
   }

   const color rectColor = SMCZoneTypeIsBullish(g_mtfFvgInstances[instanceIndex].type)
                           ? clrLimeGreen : clrDeepPink;
   ObjectSetInteger(0, objName, OBJPROP_COLOR, rectColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_FILL, false);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void SMCSyncMtfFvgZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_MTF_FVG_INSTANCE_CAPACITY; i++)
   {
      if(g_mtfFvgInstances[i].timeframe != timeframe)
         continue;

      if(g_mtfFvgInstances[i].inUse && !g_mtfFvgInstances[i].isMitigated && !g_mtfFvgInstances[i].isExpired)
         SMCDrawMtfFvgRectangleForInstance(i);
      else if(g_mtfFvgInstances[i].zoneOriginBarTime > 0)
         SMCDeleteMtfFvgRectangleForInstance(g_mtfFvgInstances[i].type,
                                             g_mtfFvgInstances[i].zoneOriginBarTime);
   }
}

//+------------------------------------------------------------------+
void SMCDrawMtfFvgZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   SMCSyncMtfFvgZoneRectanglesForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void SMCMapUnmitigatedFvgsForTimeframe(const ENUM_TIMEFRAMES timeframe,
                                        const ENUM_SMC_ZONE_TYPE bullZoneType,
                                        const ENUM_SMC_ZONE_TYPE bearZoneType)
{
   const int lookback = MathMax(3, InputSmcFvgLookbackBars);

   for(int middleShift = 2; middleShift <= lookback; middleShift++)
   {
      bool   isBullish = false;
      double bottom = 0.0;
      double top    = 0.0;
      if(!SMCDetectFvgAtMiddleShift(timeframe, middleShift, isBullish, bottom, top))
         continue;

      const ENUM_SMC_ZONE_TYPE zoneType = isBullish ? bullZoneType : bearZoneType;
      double regBottom = 0.0;
      double regTop    = 0.0;
      if(!SMCApplyMtfFvgGapZoneEdges(timeframe, isBullish, bottom, top, regBottom, regTop))
         continue;

      if(!SMCFvgGapMeetsMinPercentOfChart(timeframe, regBottom, regTop))
         continue;

      const int formationNewestShift = middleShift - 1;
      if(SMCFvgMitigated(timeframe, formationNewestShift, isBullish, regBottom, regTop))
         continue;

      const datetime origin = iTime(_Symbol, timeframe, middleShift);
      if(origin <= 0)
         continue;

      SMCUpsertMtfFvgInstance(zoneType, regBottom, regTop, origin);
   }
}

//+------------------------------------------------------------------+
bool SMCSwingExtremeViolatedSinceLegEnd(const ENUM_TIMEFRAMES timeframe,
                                         const datetime legStartTime,
                                         const datetime legEndTime,
                                         const bool checkHighViolation,
                                         const double level)
{
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   const int barsTotal = iBars(_Symbol, timeframe);
   if(barsTotal < 2)
      return false;

   for(int barShift = 1; barShift < barsTotal; barShift++)
   {
      const datetime barOpen = iTime(_Symbol, timeframe, barShift);
      if(barOpen == 0)
         continue;

      // Completed leg: only count closes on bars strictly after leg end (not the closing bar itself).
      if(legEndTime > 0)
      {
         if(barOpen <= legEndTime)
            continue;
      }
      else if(legStartTime > 0 && barOpen < legStartTime)
         continue;

      const double barClose = iClose(_Symbol, timeframe, barShift);
      if(checkHighViolation && barClose > level + eps)
         return true;
      if(!checkHighViolation && barClose < level - eps)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool SMCTryGetLatestUnbrokenSwingHigh(const SwingState &swingState,
                                       const ENUM_TIMEFRAMES timeframe,
                                       double &outLevel)
{
   outLevel = 0.0;

   for(int historyIndex = swingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(swingState.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double legHigh = swingState.swingHistory[historyIndex].legHighPrice;
      if(legHigh <= 0.0)
         continue;
      if(!SMCSwingExtremeViolatedSinceLegEnd(timeframe,
                                             swingState.swingHistory[historyIndex].legStartTime,
                                             swingState.swingHistory[historyIndex].legEndTime,
                                             true, legHigh))
      {
         outLevel = legHigh;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
bool SMCTryGetLatestUnbrokenSwingLow(const SwingState &swingState,
                                      const ENUM_TIMEFRAMES timeframe,
                                      double &outLevel)
{
   outLevel = 0.0;

   for(int historyIndex = swingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(swingState.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double legLow = swingState.swingHistory[historyIndex].legLowPrice;
      if(legLow <= 0.0)
         continue;
      if(!SMCSwingExtremeViolatedSinceLegEnd(timeframe,
                                             swingState.swingHistory[historyIndex].legStartTime,
                                             swingState.swingHistory[historyIndex].legEndTime,
                                             false, legLow))
      {
         outLevel = legLow;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
void SMCRegisterDedicatedSwingHighZone(const ENUM_SMC_ZONE_TYPE type, const double level,
                                        const double buffer, const datetime originBarTime = 0,
                                        const bool forceFreshZoneState = false)
{
   if(level <= 0.0 || buffer <= 0.0)
      return;
   RegisterOrMergeZone(type, level + buffer, level, originBarTime, forceFreshZoneState);
}

//+------------------------------------------------------------------+
void SMCRegisterDedicatedSwingLowZone(const ENUM_SMC_ZONE_TYPE type, const double level,
                                         const double buffer, const datetime originBarTime = 0,
                                         const bool forceFreshZoneState = false)
{
   if(level <= 0.0 || buffer <= 0.0)
      return;
   RegisterOrMergeZone(type, level, level - buffer, originBarTime, forceFreshZoneState);
}

//+------------------------------------------------------------------+
void SMCRegisterLiquidityHighZone(const ENUM_SMC_ZONE_TYPE type, const double level, const double buffer)
{
   if(level <= 0.0 || buffer <= 0.0)
      return;
   RegisterOrMergeZone(type, level + buffer, level, 0, false);
}

//+------------------------------------------------------------------+
void SMCRegisterLiquidityLowZone(const ENUM_SMC_ZONE_TYPE type, const double level, const double buffer)
{
   if(level <= 0.0 || buffer <= 0.0)
      return;
   RegisterOrMergeZone(type, level, level - buffer, 0, false);
}

//+------------------------------------------------------------------+
void SMCSeedSwingZonesFromHistory(const MTFSwingTracker &tracker,
                                   const ENUM_SMC_ZONE_TYPE bullSwingLowType,
                                   const ENUM_SMC_ZONE_TYPE bearSwingHighType)
{
   if(tracker.timeframe == 0 || tracker.swing.swingHistoryCount <= 0)
      return;

   const double buffer = SMCSwingLevelBufferForTimeframe(tracker.timeframe);
   for(int historyIndex = 0; historyIndex < tracker.swing.swingHistoryCount; historyIndex++)
   {
      const Swing leg = tracker.swing.swingHistory[historyIndex];
      if(leg.legEndTime <= 0)
         continue;

      if(leg.swingDirection == 1 && leg.legHighPrice > 0.0)
         SMCRegisterDedicatedSwingHighZone(bearSwingHighType, leg.legHighPrice, buffer, leg.legEndTime, false);
      else if(leg.swingDirection == -1 && leg.legLowPrice > 0.0)
         SMCRegisterDedicatedSwingLowZone(bullSwingLowType, leg.legLowPrice, buffer, leg.legEndTime, false);
   }
}

//+------------------------------------------------------------------+
void SMCMapUnbrokenSwingZones(const MTFSwingTracker &tracker,
                               const ENUM_SMC_ZONE_TYPE bullSwingLowType,
                               const ENUM_SMC_ZONE_TYPE bearSwingHighType)
{
   SMCSeedSwingZonesFromHistory(tracker, bullSwingLowType, bearSwingHighType);
}

//+------------------------------------------------------------------+
void SMCRegisterSwingZoneFromJustClosedLeg(const MTFSwingTracker &tracker,
                                             const ENUM_SMC_ZONE_TYPE bullSwingLowType,
                                             const ENUM_SMC_ZONE_TYPE bearSwingHighType,
                                             int &outRegisteredSlot)
{
   outRegisteredSlot = -1;
   if(tracker.swing.swingHistoryCount <= 0)
      return;

   const Swing  closedLeg = tracker.swing.swingHistory[tracker.swing.swingHistoryCount - 1];
   const double buffer    = SMCSwingLevelBufferForTimeframe(tracker.timeframe);
   if(closedLeg.legEndTime <= 0)
      return;

   if(closedLeg.swingDirection == 1 && closedLeg.legHighPrice > 0.0)
      outRegisteredSlot = RegisterOrMergeZone(bearSwingHighType,
                                              closedLeg.legHighPrice + buffer,
                                              closedLeg.legHighPrice,
                                              closedLeg.legEndTime, true);
   else if(closedLeg.swingDirection == -1 && closedLeg.legLowPrice > 0.0)
      outRegisteredSlot = RegisterOrMergeZone(bullSwingLowType,
                                              closedLeg.legLowPrice,
                                              closedLeg.legLowPrice - buffer,
                                              closedLeg.legEndTime, true);
}

//+------------------------------------------------------------------+
void SMCMapProtectedStructuralZone(const MTFSwingTracker &tracker,
                                    const ENUM_SMC_ZONE_TYPE bullProtectedLowType,
                                    const ENUM_SMC_ZONE_TYPE bearProtectedHighType)
{
   if(tracker.lastBosDirection == 0 || tracker.lastBosLevel <= 0.0)
      return;

   const double buffer = SMCSwingLevelBufferForTimeframe(tracker.timeframe);

   if(tracker.lastBosDirection == 1)
   {
      if(tracker.lastBrokenLegLow > 0.0)
         SMCRegisterLiquidityLowZone(bullProtectedLowType, tracker.lastBrokenLegLow, buffer);
   }
   else if(tracker.lastBosDirection == -1)
   {
      if(tracker.lastBrokenLegHigh > 0.0)
         SMCRegisterLiquidityHighZone(bearProtectedHighType, tracker.lastBrokenLegHigh, buffer);
   }
}

//+------------------------------------------------------------------+
void SMCClearActiveZonesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_ZONE_TYPE_COUNT; i++)
   {
      const ENUM_SMC_ZONE_TYPE slotType = g_activeZones[i].isActive
         ? g_activeZones[i].type
         : (ENUM_SMC_ZONE_TYPE)i;
      if(SMCZoneTypeToTimeframe(slotType) != timeframe)
         continue;
      if(SMCZoneTypeIsMtfFvg(slotType))
         continue;

      g_activeZones[i].type               = (ENUM_SMC_ZONE_TYPE)i;
      g_activeZones[i].topPrice           = 0.0;
      g_activeZones[i].bottomPrice        = 0.0;
      g_activeZones[i].isActive           = false;
      g_activeZones[i].isClustered        = false;
      g_activeZones[i].isMitigated  = false;
      g_activeZones[i].isBreached   = false;
      g_activeZones[i].isExpired    = false;
      g_activeZones[i].zoneOriginBarTime  = 0;
   }
}

//+------------------------------------------------------------------+
string SMCZoneTimeframeTag(const ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_W1:  return "W1";
      case PERIOD_D1:  return "D1";
      case PERIOD_H4:  return "H4";
      case PERIOD_M15: return "M15";
   }
   return "TF";
}

//+------------------------------------------------------------------+
string SMCZoneRectangleObjectNameFromRecord(const ENUM_SMC_ZONE_TYPE zoneType,
                                             const int slotIndex,
                                             const datetime zoneOriginBarTime)
{
   if(zoneType < 0 || zoneType >= SMC_ZONE_TYPE_COUNT || zoneOriginBarTime <= 0)
      return "";

   const ENUM_TIMEFRAMES zoneTf = SMCZoneTypeToTimeframe(zoneType);
   return LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(zoneTf) + "_"
          + IntegerToString((int)zoneType) + "_S" + IntegerToString(slotIndex) + "_"
          + IntegerToString((long)zoneOriginBarTime);
}

//+------------------------------------------------------------------+
string SMCZoneRectangleObjectNameForSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return "";

   return SMCZoneRectangleObjectNameFromRecord(g_activeZones[slotIndex].type, slotIndex,
                                               g_activeZones[slotIndex].zoneOriginBarTime);
}

//+------------------------------------------------------------------+
void SMCDeleteZoneRectangleForSlot(const int slotIndex)
{
   const string objName = SMCZoneRectangleObjectNameForSlot(slotIndex);
   if(objName != "" && ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);

   if(slotIndex >= 0 && slotIndex < SMC_ZONE_TYPE_COUNT)
   {
      const ENUM_SMC_ZONE_TYPE zoneType = (ENUM_SMC_ZONE_TYPE)slotIndex;
      const string legacyName = LQ_OBJ_PREFIX_SMC_ZONE_RECT + IntegerToString(slotIndex);
      if(ObjectFind(0, legacyName) >= 0)
         ObjectDelete(0, legacyName);

      const string legacyTfName = LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(SMCZoneTypeToTimeframe(zoneType))
                                + "_" + IntegerToString(slotIndex);
      if(ObjectFind(0, legacyTfName) >= 0)
         ObjectDelete(0, legacyTfName);
   }
}

//+------------------------------------------------------------------+
//| Delete every non-FVG zone rectangle tied to a ledger slot index.  |
//+------------------------------------------------------------------+
void SMCDeleteAllZoneRectangleObjectsForSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return;

   SMCDeleteZoneRectangleForSlot(slotIndex);

   const string slotToken = "_S" + IntegerToString(slotIndex) + "_";
   const int total = ObjectsTotal(0, 0, -1);
   for(int o = total - 1; o >= 0; o--)
   {
      const string objName = ObjectName(0, o, 0, -1);
      if(StringFind(objName, LQ_OBJ_PREFIX_SMC_ZONE_RECT) != 0)
         continue;
      if(StringFind(objName, "_FVG_") >= 0)
         continue;
      if(StringFind(objName, slotToken) < 0)
         continue;
      ObjectDelete(0, objName);
   }
}

//+------------------------------------------------------------------+
bool SMCZoneChartObjectShouldRemain(const string objName, const ENUM_TIMEFRAMES timeframe)
{
   if(objName == "")
      return false;

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive || g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
         continue;
      if(SMCZoneTypeToTimeframe(g_activeZones[i].type) != timeframe)
         continue;
      if(SMCZoneRectangleObjectNameForSlot(i) == objName)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool SMCMtfFvgChartObjectShouldRemain(const string objName, const ENUM_TIMEFRAMES timeframe)
{
   if(objName == "")
      return false;

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         continue;
      if(g_mtfFvgInstances[f].timeframe != timeframe)
         continue;
      if(SMCMtfFvgRectangleObjectName(g_mtfFvgInstances[f].type,
                                      g_mtfFvgInstances[f].zoneOriginBarTime) == objName)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void SMCSweepOrphanZoneChartObjectsForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const string zonePrefix = LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(timeframe) + "_";
   const string fvgPrefix  = zonePrefix + "FVG_";
   const int total = ObjectsTotal(0, 0, -1);

   for(int o = total - 1; o >= 0; o--)
   {
      const string objName = ObjectName(0, o, 0, -1);
      if(StringFind(objName, zonePrefix) != 0)
         continue;

      if(StringFind(objName, fvgPrefix) == 0)
      {
         if(!SMCMtfFvgChartObjectShouldRemain(objName, timeframe))
            ObjectDelete(0, objName);
         continue;
      }

      if(!SMCZoneChartObjectShouldRemain(objName, timeframe))
         ObjectDelete(0, objName);
   }
}

//+------------------------------------------------------------------+
void SMCDrawZoneRectangleForSlot(const int slotIndex)
{
   if(slotIndex < 0 || slotIndex >= SMC_ZONE_LEDGER_CAPACITY)
      return;
   if(!g_activeZones[slotIndex].isActive || g_activeZones[slotIndex].isMitigated || g_activeZones[slotIndex].isExpired)
      return;
   if(SMCZoneTypeIsMtfFvg(g_activeZones[slotIndex].type))
      return;

   const ENUM_TIMEFRAMES timeframe = SMCZoneTypeToTimeframe(g_activeZones[slotIndex].type);
   if(!MtfSwingLegDrawEnabled(timeframe))
      return;

   const datetime timeLeft = (g_activeZones[slotIndex].zoneOriginBarTime > 0
                              ? g_activeZones[slotIndex].zoneOriginBarTime
                              : iTime(_Symbol, timeframe, 1));
   const datetime timeRight = SMCZoneRectangleTimeRight(timeframe, timeLeft);
   const string objName = SMCZoneRectangleObjectNameForSlot(slotIndex);
   const double top = g_activeZones[slotIndex].topPrice;
   const double bottom = g_activeZones[slotIndex].bottomPrice;
   if(timeRight <= 0 || timeLeft <= 0 || top <= bottom || objName == "")
      return;

   if(ObjectFind(0, objName) < 0)
   {
      if(!ObjectCreate(0, objName, OBJ_RECTANGLE, 0, timeLeft, top, timeRight, bottom))
         return;
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, timeLeft);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, top);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeRight);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, bottom);
   }

   const color rectColor = SMCZoneTypeIsBullish(g_activeZones[slotIndex].type) ? clrLimeGreen : clrDeepPink;
   ObjectSetInteger(0, objName, OBJPROP_COLOR, rectColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_FILL, false);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void SMCSyncZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
         continue;
      if(SMCZoneTypeIsMtfFvg(g_activeZones[i].type))
         continue;
      if(SMCZoneTypeToTimeframe(g_activeZones[i].type) != timeframe)
         continue;

      if(g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
         SMCDeleteAllZoneRectangleObjectsForSlot(i);
      else
         SMCDrawZoneRectangleForSlot(i);
   }
}

//+------------------------------------------------------------------+
void SMCCleanupMitigatedExpiredZoneChartObjectsForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(g_activeZones[i].isMitigated || g_activeZones[i].isExpired || !g_activeZones[i].isActive)
      {
         SMCDeleteAllZoneRectangleObjectsForSlot(i);
         continue;
      }

      const ENUM_SMC_ZONE_TYPE zoneType = g_activeZones[i].type;
      if(zoneType < 0 || zoneType >= SMC_ZONE_TYPE_COUNT)
         continue;
      if(SMCZoneTypeIsMtfFvg(zoneType))
         continue;
      if(SMCZoneTypeToTimeframe(zoneType) != timeframe)
         continue;
   }

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(g_mtfFvgInstances[f].timeframe != timeframe)
         continue;
      if(g_mtfFvgInstances[f].zoneOriginBarTime <= 0)
         continue;

      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         SMCDeleteMtfFvgRectangleForInstance(g_mtfFvgInstances[f].type,
                                             g_mtfFvgInstances[f].zoneOriginBarTime);
   }

   SMCSweepOrphanZoneChartObjectsForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void SMCDeleteZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   const string prefix = LQ_OBJ_PREFIX_SMC_ZONE_RECT + SMCZoneTimeframeTag(timeframe) + "_";
   const int total = ObjectsTotal(0, 0, -1);
   for(int o = total - 1; o >= 0; o--)
   {
      const string objName = ObjectName(0, o, 0, -1);
      if(StringFind(objName, prefix) == 0 && StringFind(objName, "_FVG_") < 0)
         ObjectDelete(0, objName);
   }
}

//+------------------------------------------------------------------+
void SMCDrawZoneRectanglesForTimeframe(const ENUM_TIMEFRAMES timeframe)
{
   SMCSyncZoneRectanglesForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void SMCRefreshZonesForTimeframe(const ENUM_TIMEFRAMES timeframe, MTFSwingTracker &tracker,
                                  const bool legClosedThisBar)
{
   if(!InputEnableMtfSmcEngine)
      return;

   if(legClosedThisBar)
   {
      int registeredSlot = -1;
      switch(timeframe)
      {
         case PERIOD_W1:
            SMCRegisterSwingZoneFromJustClosedLeg(tracker, ZONE_BULL_SWING_W1_LOW, ZONE_BEAR_SWING_W1_HIGH,
                                                  registeredSlot);
            break;
         case PERIOD_D1:
            SMCRegisterSwingZoneFromJustClosedLeg(tracker, ZONE_BULL_SWING_DAILY_LOW, ZONE_BEAR_SWING_DAILY_HIGH,
                                                  registeredSlot);
            break;
         case PERIOD_H4:
            SMCRegisterSwingZoneFromJustClosedLeg(tracker, ZONE_BULL_SWING_H4_LOW, ZONE_BEAR_SWING_H4_HIGH,
                                                  registeredSlot);
            break;
         case PERIOD_M15:
            SMCRegisterSwingZoneFromJustClosedLeg(tracker, ZONE_BULL_SWING_M15_LOW, ZONE_BEAR_SWING_M15_HIGH,
                                                  registeredSlot);
            break;
         default:
            return;
      }

      if(registeredSlot >= 0)
         SMCDrawZoneRectangleForSlot(registeredSlot);

      SMCApplyZoneExitBiasAndMitigationForTimeframe(timeframe);
      SMCExpireZonesPastBarLimitForTimeframe(timeframe);
      SMCExpireMtfFvgInstancesForTimeframe(timeframe);
      SMCCleanupMitigatedExpiredZoneChartObjectsForTimeframe(timeframe);
      SMCSyncZoneRectanglesForTimeframe(timeframe);
      SMCSyncMtfFvgZoneRectanglesForTimeframe(timeframe);
      return;
   }

   switch(timeframe)
   {
      case PERIOD_W1:
         SMCMapUnmitigatedFvgsForTimeframe(PERIOD_W1, ZONE_BULL_WEEKLY_FVG, ZONE_BEAR_WEEKLY_FVG);
         break;

      case PERIOD_D1:
         SMCMapUnmitigatedFvgsForTimeframe(PERIOD_D1, ZONE_BULL_DAILY_FVG, ZONE_BEAR_DAILY_FVG);
         SMCMapProtectedStructuralZone(tracker,
                                       ZONE_BULL_PROTECTED_DAILY_LOW, ZONE_BEAR_PROTECTED_DAILY_HIGH);
         break;

      case PERIOD_H4:
         SMCMapUnmitigatedFvgsForTimeframe(PERIOD_H4, ZONE_BULL_H4_FVG, ZONE_BEAR_H4_FVG);
         SMCMapProtectedStructuralZone(tracker,
                                       ZONE_BULL_PROTECTED_H4_LOW, ZONE_BEAR_PROTECTED_H4_HIGH);
         break;

      case PERIOD_M15:
         SMCMapUnmitigatedFvgsForTimeframe(PERIOD_M15, ZONE_BULL_M15_FVG, ZONE_BEAR_M15_FVG);
         SMCMapProtectedStructuralZone(tracker,
                                       ZONE_BULL_PROTECTED_M15_LOW, ZONE_BEAR_PROTECTED_M15_HIGH);
         break;

      default:
         return;
   }

   SMCApplyZoneExitBiasAndMitigationForTimeframe(timeframe);
   SMCExpireZonesPastBarLimitForTimeframe(timeframe);
   SMCExpireMtfFvgInstancesForTimeframe(timeframe);
   SMCCleanupMitigatedExpiredZoneChartObjectsForTimeframe(timeframe);
   SMCSyncZoneRectanglesForTimeframe(timeframe);
   SMCSyncMtfFvgZoneRectanglesForTimeframe(timeframe);
}

//+------------------------------------------------------------------+
void UpdateSMCZoneMatrix()
{
   if(!InputEnableMtfSmcEngine)
      return;

   SMCSeedSwingZonesFromHistory(g_mtfSwingW1,  ZONE_BULL_SWING_W1_LOW,  ZONE_BEAR_SWING_W1_HIGH);
   SMCSeedSwingZonesFromHistory(g_mtfSwingD1,  ZONE_BULL_SWING_DAILY_LOW, ZONE_BEAR_SWING_DAILY_HIGH);
   SMCSeedSwingZonesFromHistory(g_mtfSwingH4,  ZONE_BULL_SWING_H4_LOW,  ZONE_BEAR_SWING_H4_HIGH);
   SMCSeedSwingZonesFromHistory(g_mtfSwingM15, ZONE_BULL_SWING_M15_LOW, ZONE_BEAR_SWING_M15_HIGH);

   SMCRefreshZonesForTimeframe(PERIOD_W1,  g_mtfSwingW1,  false);
   SMCRefreshZonesForTimeframe(PERIOD_D1,  g_mtfSwingD1,  false);
   SMCRefreshZonesForTimeframe(PERIOD_H4,  g_mtfSwingH4,  false);
   SMCRefreshZonesForTimeframe(PERIOD_M15, g_mtfSwingM15, false);
}

//+------------------------------------------------------------------+
//| Completed H4 swing legs in lookback: up-leg high / down-leg low pivots only.   |
//| Pivot up high: legHigh beats every newer up-leg high; pivot down low: vice versa. |
//+------------------------------------------------------------------+
void RebuildH4LiquidityPivotLevels()
{
   g_h4DescHighPivotCount = 0;
   g_h4AscLowPivotCount   = 0;

   if(InputH4LiquidityPivotLookbackBars < 2)
      return;

   const int barsTotal = iBars(_Symbol, PERIOD_H4);
   if(barsTotal < 3)
      return;

   const int maxShift =
      (int)MathMin((double)InputH4LiquidityPivotLookbackBars, (double)(barsTotal - 2));
   if(maxShift < 1)
      return;

   H4ReplayLeg replayLegs[H4_REPLAY_LEG_CAPACITY];
   int          replayLegCount = 0;
   SwingState   replaySwing;
   ZeroMemory(replaySwing);

   for(int shift = maxShift; shift >= 1; shift--)
      MtfSwingStepReplayAtShift(replaySwing, PERIOD_H4, shift, replayLegs, replayLegCount);

   if(replayLegCount <= 0)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   for(int legIndex = replayLegCount - 1; legIndex >= 0; legIndex--)
   {
      if(replayLegs[legIndex].swingDirection != 1)
         continue;

      bool isPivotHigh = true;
      for(int newerIndex = legIndex + 1; newerIndex < replayLegCount; newerIndex++)
      {
         if(replayLegs[newerIndex].swingDirection != 1)
            continue;
         if(replayLegs[newerIndex].legHighPrice >= replayLegs[legIndex].legHighPrice - eps)
         {
            isPivotHigh = false;
            break;
         }
      }

      if(!isPivotHigh || g_h4DescHighPivotCount >= H4_LIQUIDITY_PIVOT_CAPACITY)
         continue;

      Swing lastSwing;
      ZeroMemory(lastSwing);
      lastSwing.legHighPrice    = replayLegs[legIndex].legHighPrice;
      lastSwing.legLowPrice     = replayLegs[legIndex].legLowPrice;
      lastSwing.legStartTime    = replayLegs[legIndex].legStartTime;
      lastSwing.legEndTime      = replayLegs[legIndex].legEndTime;
      lastSwing.swingDirection  = replayLegs[legIndex].swingDirection;

      Swing prevSwing;
      ZeroMemory(prevSwing);
      const bool hasPrevLeg = (legIndex > 0);
      if(hasPrevLeg)
      {
         prevSwing.legHighPrice   = replayLegs[legIndex - 1].legHighPrice;
         prevSwing.legLowPrice    = replayLegs[legIndex - 1].legLowPrice;
         prevSwing.legStartTime   = replayLegs[legIndex - 1].legStartTime;
         prevSwing.legEndTime     = replayLegs[legIndex - 1].legEndTime;
         prevSwing.swingDirection = replayLegs[legIndex - 1].swingDirection;
      }

      double breachLevel = replayLegs[legIndex].legHighPrice;
      datetime volumeBarOpenTime = 0;
      ComputeH4LegVolumeBreachLevel(lastSwing, prevSwing, hasPrevLeg, breachLevel, volumeBarOpenTime);

      const int outIndex = g_h4DescHighPivotCount;
      g_h4DescHighPivots[outIndex].levelPrice     = breachLevel;
      g_h4DescHighPivots[outIndex].legEndTime      = replayLegs[legIndex].legEndTime;
      g_h4DescHighPivots[outIndex].legHighPrice    = replayLegs[legIndex].legHighPrice;
      g_h4DescHighPivots[outIndex].legLowPrice     = replayLegs[legIndex].legLowPrice;
      g_h4DescHighPivots[outIndex].swingDirection  = 1;
      g_h4DescHighPivotCount++;
   }

   for(int legIndex = replayLegCount - 1; legIndex >= 0; legIndex--)
   {
      if(replayLegs[legIndex].swingDirection != -1)
         continue;

      bool isPivotLow = true;
      for(int newerIndex = legIndex + 1; newerIndex < replayLegCount; newerIndex++)
      {
         if(replayLegs[newerIndex].swingDirection != -1)
            continue;
         if(replayLegs[newerIndex].legLowPrice <= replayLegs[legIndex].legLowPrice + eps)
         {
            isPivotLow = false;
            break;
         }
      }

      if(!isPivotLow || g_h4AscLowPivotCount >= H4_LIQUIDITY_PIVOT_CAPACITY)
         continue;

      Swing lastSwing;
      ZeroMemory(lastSwing);
      lastSwing.legHighPrice    = replayLegs[legIndex].legHighPrice;
      lastSwing.legLowPrice     = replayLegs[legIndex].legLowPrice;
      lastSwing.legStartTime    = replayLegs[legIndex].legStartTime;
      lastSwing.legEndTime      = replayLegs[legIndex].legEndTime;
      lastSwing.swingDirection  = replayLegs[legIndex].swingDirection;

      Swing prevSwing;
      ZeroMemory(prevSwing);
      const bool hasPrevLeg = (legIndex > 0);
      if(hasPrevLeg)
      {
         prevSwing.legHighPrice   = replayLegs[legIndex - 1].legHighPrice;
         prevSwing.legLowPrice    = replayLegs[legIndex - 1].legLowPrice;
         prevSwing.legStartTime   = replayLegs[legIndex - 1].legStartTime;
         prevSwing.legEndTime     = replayLegs[legIndex - 1].legEndTime;
         prevSwing.swingDirection = replayLegs[legIndex - 1].swingDirection;
      }

      double breachLevel = replayLegs[legIndex].legLowPrice;
      datetime volumeBarOpenTime = 0;
      ComputeH4LegVolumeBreachLevel(lastSwing, prevSwing, hasPrevLeg, breachLevel, volumeBarOpenTime);

      const int outIndex = g_h4AscLowPivotCount;
      g_h4AscLowPivots[outIndex].levelPrice     = breachLevel;
      g_h4AscLowPivots[outIndex].legEndTime      = replayLegs[legIndex].legEndTime;
      g_h4AscLowPivots[outIndex].legHighPrice    = replayLegs[legIndex].legHighPrice;
      g_h4AscLowPivots[outIndex].legLowPrice     = replayLegs[legIndex].legLowPrice;
      g_h4AscLowPivots[outIndex].swingDirection  = -1;
      g_h4AscLowPivotCount++;
   }
}

#ifdef H4_LQ_VOLUME_BREACH_ENABLED
// --- M2 wick breach detect + hunt accept (disabled v3.04) ---

//+------------------------------------------------------------------+
bool M2WickCrossesAboveLevel(const double level, const double barHigh, const double prevHigh,
                             const double pointSize)
{
   return (barHigh > level + pointSize && prevHigh <= level + pointSize);
}

//+------------------------------------------------------------------+
bool M2WickCrossesBelowLevel(const double level, const double barLow, const double prevLow,
                             const double pointSize)
{
   return (barLow < level - pointSize && prevLow >= level - pointSize);
}

#endif // H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
//| Breach buffer band (% of H4 reference height): high 2% below..10% above; low 2% above..10% below. |
//+------------------------------------------------------------------+
void H4BreachBufferBandForUpLegHigh(const double breachLevel, double &outBandLow, double &outBandHigh)
{
   const double referenceHeight = ReferenceChartHeightForH4BreachBuffer();
   if(referenceHeight <= 0.0)
   {
      outBandLow  = breachLevel;
      outBandHigh = breachLevel;
      return;
   }

   outBandLow  = breachLevel - referenceHeight * (H4_BREACH_BUFFER_PERCENT_NEAR / 100.0);
   outBandHigh = breachLevel + referenceHeight * (H4_BREACH_BUFFER_PERCENT_FAR / 100.0);
}

//+------------------------------------------------------------------+
void H4BreachBufferBandForDownLegLow(const double breachLevel, double &outBandLow, double &outBandHigh)
{
   const double referenceHeight = ReferenceChartHeightForH4BreachBuffer();
   if(referenceHeight <= 0.0)
   {
      outBandLow  = breachLevel;
      outBandHigh = breachLevel;
      return;
   }

   outBandLow  = breachLevel - referenceHeight * (H4_BREACH_BUFFER_PERCENT_FAR / 100.0);
   outBandHigh = breachLevel + referenceHeight * (H4_BREACH_BUFFER_PERCENT_NEAR / 100.0);
}

//+------------------------------------------------------------------+
#ifdef H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
bool M2WickCrossesIntoH4UpBreachBuffer(const double bandLow, const double bandHigh,
                                        const double barHigh, const double prevHigh,
                                        const double pointSize)
{
   if(prevHigh >= bandLow - pointSize)
      return false;
   return barHigh >= bandLow - pointSize;
}

//+------------------------------------------------------------------+
bool M2WickCrossesIntoH4DownBreachBuffer(const double bandLow, const double bandHigh,
                                          const double barLow, const double prevLow,
                                          const double pointSize)
{
   if(prevLow <= bandHigh + pointSize)
      return false;
   return barLow <= bandHigh + pointSize;
}

//+------------------------------------------------------------------+
bool TryAcceptH4BreachForHunt(const bool h4HighBreached, const double breachLevel,
                               const datetime legEnd, double &outLevel, bool &outHighBreached,
                               datetime &outLegEndTime)
{
   if(breachLevel <= 0.0 || legEnd == 0)
      return false;

   outLevel        = breachLevel;
   outLegEndTime   = legEnd;
   outHighBreached = h4HighBreached;
   return true;
}

#endif // H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void LogHuntEvent(const string eventName, const string detail = "")
{
   if(!H4LqLoggingEnabled())
      return;

   const datetime barTime = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   const string timeText  = (barTime != 0) ? TimeToString(barTime, TIME_DATE | TIME_MINUTES) : "no-bar";

   if(StringLen(detail) > 0)
      PrintFormat("%s [%s] %s | %s", H4_LQ_LOG_PREFIX, timeText, eventName, detail);
   else
      PrintFormat("%s [%s] %s", H4_LQ_LOG_PREFIX, timeText, eventName);
}

//+------------------------------------------------------------------+
void ApplyTradeFillingModeFromSymbol()
{
   const long fillingMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(fillingMode == 0)
      return;
   if((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
int TouchVolEffectiveMinSlPoints()
{
   int minPts = InputTouchVolMinSlPoints;
   const int brokerPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(brokerPts > minPts)
      minPts = brokerPts;
   return minPts;
}

//+------------------------------------------------------------------+
bool ApplyTouchVolMinimumSlDistance(const bool isBuy, const double entryPrice,
                                     double &inOutStopLossPrice)
{
   if(entryPrice <= 0.0 || inOutStopLossPrice <= 0.0)
      return false;

   const int    minPts    = TouchVolEffectiveMinSlPoints();
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pointSize <= 0.0)
      return false;

   const double minDistance = (minPts > 0 ? (double)minPts * pointSize : 0.0);

   if(isBuy)
   {
      if(minDistance > 0.0)
      {
         const double maxSl = entryPrice - minDistance;
         if(inOutStopLossPrice >= maxSl)
            inOutStopLossPrice = NormalizeDouble(maxSl, _Digits);
      }
      return inOutStopLossPrice < entryPrice;
   }

   if(minDistance > 0.0)
   {
      const double minSl = entryPrice + minDistance;
      if(inOutStopLossPrice <= minSl)
         inOutStopLossPrice = NormalizeDouble(minSl, _Digits);
   }
   return inOutStopLossPrice > entryPrice;
}

//+------------------------------------------------------------------+
//| Buy hunt: vol bar low + N% chart height. Sell hunt: vol bar high âˆ’ N%. |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Scan opposite M2 leg backward for most recent decent impulse; return origin bar shift. |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 61.8% OTE on full opposite M2 leg range (down leg: from low; up leg: from high). |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool V2TryGetLastCompletedM2Leg(const int legDirection, double &outLegLow, double &outLegHigh,
                                   datetime &outLegStartTime, datetime &outLegEndTime)
{
   outLegLow  = 0.0;
   outLegHigh = 0.0;
   outLegStartTime = 0;
   outLegEndTime   = 0;
   if(legDirection == 0 || g_m2Swing.swingHistoryCount < 1)
      return false;

   for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m2Swing.swingHistory[historyIndex].swingDirection != legDirection)
         continue;
      outLegLow         = g_m2Swing.swingHistory[historyIndex].legLowPrice;
      outLegHigh        = g_m2Swing.swingHistory[historyIndex].legHighPrice;
      outLegStartTime   = g_m2Swing.swingHistory[historyIndex].legStartTime;
      outLegEndTime     = g_m2Swing.swingHistory[historyIndex].legEndTime;
      return (outLegLow > 0.0 && outLegHigh > 0.0);
   }
   return false;
}

double LossPerLotFromTickSpec(const double entryPrice, const double stopLossPrice)
{
   const double slDistance = MathAbs(entryPrice - stopLossPrice);
   if(slDistance <= 0.0)
      return 0.0;

   const double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   return (slDistance / tickSize) * tickValue;
}

//+------------------------------------------------------------------+
double CalculateVolumeForFixedUsdRisk(const bool isBuy, const double entryPrice,
                                      const double stopLossPrice, const double riskAccountCurrency)
{
   const ENUM_ORDER_TYPE profitOrderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double lossPerLot = 0.0;
   double profitAtStop = 0.0;
   if(OrderCalcProfit(profitOrderType, _Symbol, 1.0, entryPrice, stopLossPrice, profitAtStop))
   {
      lossPerLot = (profitAtStop < 0.0) ? -profitAtStop : profitAtStop;
   }
   if(lossPerLot <= 0.0)
      lossPerLot = LossPerLotFromTickSpec(entryPrice, stopLossPrice);
   if(lossPerLot <= 0.0)
      return 0.0;

   double volume = riskAccountCurrency / lossPerLot;
   const double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double volumeMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double volumeMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(volumeStep > 0.0)
      volume = MathFloor(volume / volumeStep) * volumeStep;
   if(volume < volumeMin)
      volume = volumeMin;
   if(volume > volumeMax)
      volume = volumeMax;

   return volume;
}

//+------------------------------------------------------------------+
bool SetupScoreAllowsTradeEntry(const double setupScore)
{
   return (setupScore >= InputMinScore);
}

//+------------------------------------------------------------------+
double GetOptimizedLotSize(const double entryPrice, const double stopLoss, const double score,
                            const bool isBuy, const double riskUsdFraction = 1.0)
{
   const double scoreDenom = GetRiskNormalizationScore();
   if(scoreDenom <= 0.0 || InputBaseRiskPercent <= 0.0 || riskUsdFraction <= 0.0)
      return 0.0;

   const double alignmentRatio = MathAbs(score) / scoreDenom;
   const double clampedRatio   = MathMax(0.1, MathMin(2.0, alignmentRatio));
   const double riskPercent    = InputBaseRiskPercent * clampedRatio;
   const double riskUsd        = AccountInfoDouble(ACCOUNT_EQUITY) * riskPercent / 100.0 * riskUsdFraction;

   LogHuntEvent("RISK_SIZE",
                StringFormat("setupScore=%.2f scoreDenom=%.2f clampedRatio=%.3f riskPercent=%.3f%% legFrac=%.3f riskUsd=%.2f",
                             score, scoreDenom, clampedRatio, riskPercent, riskUsdFraction, riskUsd));

   return CalculateVolumeForFixedUsdRisk(isBuy, entryPrice, stopLoss, riskUsd);
}

//+------------------------------------------------------------------+
bool StopsDistanceAllowed(const bool isBuy, const double entryPrice, const double stopLossPrice,
                          const double takeProfitPrice)
{
   const int stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double pointSize     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minDistance   = (double)stopsLevelPoints * pointSize;
   if(minDistance <= 0.0)
      return true;

   if(isBuy)
   {
      if(MathAbs(entryPrice - stopLossPrice) < minDistance)
         return false;
      if(MathAbs(takeProfitPrice - entryPrice) < minDistance)
         return false;
   }
   else
   {
      if(MathAbs(stopLossPrice - entryPrice) < minDistance)
         return false;
      if(MathAbs(entryPrice - takeProfitPrice) < minDistance)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool TryNthM2CompletedSwingLeg(const int swingDirection, const int nFromLatest,
                               double &outLegHigh, double &outLegLow, datetime &outLegEndTime)
{
   outLegEndTime = 0;
   if(swingDirection == 0 || nFromLatest < 1)
      return false;

   int legsFound = 0;
   for(int i = g_m2Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_m2Swing.swingHistory[i].swingDirection != swingDirection)
         continue;
      legsFound++;
      if(legsFound == nFromLatest)
      {
         outLegHigh    = g_m2Swing.swingHistory[i].legHighPrice;
         outLegLow     = g_m2Swing.swingHistory[i].legLowPrice;
         outLegEndTime = g_m2Swing.swingHistory[i].legEndTime;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
// Close crossed above latest completed M2 up-leg high (bullish price BOS).
bool TryDetectM2PriceBreakAboveLatestUpLegHigh(double &outBrokenLevel)
{
   outBrokenLevel = 0.0;
   if(g_m2Swing.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, InputM2NarrativeTimeframe, 1);
   const double prevClose  = iClose(_Symbol, InputM2NarrativeTimeframe, 2);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m2Swing.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double swingLegHighPrice = g_m2Swing.swingHistory[historyIndex].legHighPrice;
      if(closePrice > swingLegHighPrice + pointSize && prevClose <= swingLegHighPrice + pointSize)
      {
         outBrokenLevel = swingLegHighPrice;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
// Close crossed below latest completed M2 down-leg low (bearish price BOS).
bool TryDetectM2PriceBreakBelowLatestDownLegLow(double &outBrokenLevel)
{
   outBrokenLevel = 0.0;
   if(g_m2Swing.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, InputM2NarrativeTimeframe, 1);
   const double prevClose  = iClose(_Symbol, InputM2NarrativeTimeframe, 2);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m2Swing.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double swingLegLowPrice = g_m2Swing.swingHistory[historyIndex].legLowPrice;
      if(closePrice < swingLegLowPrice - pointSize && prevClose >= swingLegLowPrice - pointSize)
      {
         outBrokenLevel = swingLegLowPrice;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
string V2HuntTradeCommentPrefix(const datetime huntSessionId)
{
   if(huntSessionId == 0)
      return "LQ2_HS0_";
   return "LQ2_HS" + IntegerToString((long)huntSessionId) + "_";
}

//+------------------------------------------------------------------+
string HuntTradeOrderCommentPrefix(const datetime huntSessionId = 0)
{
   if(huntSessionId != 0)
      return V2HuntTradeCommentPrefix(huntSessionId);
   if(g_huntTradeSessionCommentPrefix != "")
      return g_huntTradeSessionCommentPrefix;
   return "LQ2_HS0_";
}

bool HuntTradeCommentMatchesSession(const string orderComment)
{
   if(g_huntTradeSessionCommentPrefix == "")
      return false;
   return (StringFind(orderComment, g_huntTradeSessionCommentPrefix) == 0);
}

//+------------------------------------------------------------------+
bool HuntTradeCommentIsOurs(const string orderComment)
{
   if(HuntTradeCommentMatchesSession(orderComment))
      return true;
   return (StringFind(orderComment, "LQ2_HS") == 0);
}

//+------------------------------------------------------------------+
bool IsOurHuntPendingOrderTicket(const ulong orderTicket)
{
   if(orderTicket == 0 || !OrderSelect(orderTicket))
      return false;
   if(OrderGetString(ORDER_SYMBOL) != _Symbol)
      return false;
   if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
      return false;

   const ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
   if(orderState != ORDER_STATE_PLACED && orderState != ORDER_STATE_PARTIAL)
      return false;

   const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT &&
      orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP &&
      orderType != ORDER_TYPE_BUY_STOP_LIMIT && orderType != ORDER_TYPE_SELL_STOP_LIMIT)
      return false;

   return HuntTradeCommentIsOurs(OrderGetString(ORDER_COMMENT));
}

//+------------------------------------------------------------------+
bool ParseHuntSessionIdFromTradeComment(const string orderComment, datetime &outSessionId)
{
   outSessionId = 0;
   if(StringFind(orderComment, "LQ2_HS") != 0)
      return false;

   const int afterPrefix   = 6;
   const int underscorePos = StringFind(orderComment, "_", afterPrefix);
   if(underscorePos <= afterPrefix)
      return false;

   const string sessionTag = StringSubstr(orderComment, afterPrefix, underscorePos - afterPrefix);
   const long   sessionUnix = StringToInteger(sessionTag);
   if(sessionUnix <= 0)
      return false;

   outSessionId = (datetime)sessionUnix;
   return true;
}

//+------------------------------------------------------------------+
bool TryParseFormationTimeFromHuntOrderComment(const string orderComment, datetime &outFormationTime)
{
   outFormationTime = 0;
   int lastUnderscorePos = -1;
   int searchFrom      = 0;
   while(true)
   {
      const int found = StringFind(orderComment, "_", searchFrom);
      if(found < 0)
         break;
      lastUnderscorePos = found;
      searchFrom        = found + 1;
   }

   if(lastUnderscorePos < 0)
      return false;

   const string formationTag = StringSubstr(orderComment, lastUnderscorePos + 1);
   if(StringLen(formationTag) < 8)
      return false;

   const long formationUnix = StringToInteger(formationTag);
   if(formationUnix <= 0)
      return false;

   outFormationTime = (datetime)formationUnix;
   return true;
}

datetime HuntSessionIdFromTradeCommentPrefix(const string commentPrefix)
{
   if(StringFind(commentPrefix, "LQ2_HS") != 0)
      return 0;

   const int afterPrefix = 6;
   const int underscorePos = StringFind(commentPrefix, "_", afterPrefix);
   if(underscorePos <= afterPrefix)
      return 0;

   const long sessionUnix = StringToInteger(StringSubstr(commentPrefix, afterPrefix,
                                                         underscorePos - afterPrefix));
   if(sessionUnix <= 0)
      return 0;

   return (datetime)sessionUnix;
}

//+------------------------------------------------------------------+
void EnsureHuntTradeSessionCommentPrefixFromOrdersOrPositions()
{
   if(g_huntTradeSessionCommentPrefix != "")
      return;

   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(!IsOurHuntPendingOrderTicket(ticket))
         continue;
      const string comment = OrderGetString(ORDER_COMMENT);
      const int cqPos = StringFind(comment, "_CQ_");
      const int ovPos = StringFind(comment, "_OV_");
      const int tagPos = (cqPos >= 0 ? cqPos : ovPos);
      if(tagPos >= 0)
         g_huntTradeSessionCommentPrefix = StringSubstr(comment, 0, tagPos + 1);
      else
         g_huntTradeSessionCommentPrefix = comment;
      return;
   }

   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      if(PositionGetSymbol(positionIndex) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "LQ2_HS") != 0)
         continue;
      const int cqPos = StringFind(comment, "_CQ_");
      const int ovPos = StringFind(comment, "_OV_");
      const int tagPos = (cqPos >= 0 ? cqPos : ovPos);
      if(tagPos >= 0)
         g_huntTradeSessionCommentPrefix = StringSubstr(comment, 0, tagPos + 1);
      else
         g_huntTradeSessionCommentPrefix = comment;
      return;
   }
}

//+------------------------------------------------------------------+
bool HasOurHuntTradeOpenPosition()
{
   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      if(PositionGetSymbol(positionIndex) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(HuntTradeCommentIsOurs(PositionGetString(POSITION_COMMENT)))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool StopLossModifyAllowed(const bool isBuy, const double newStopLoss, const double takeProfitPrice)
{
   const int    stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double pointSize        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minDistance      = (double)stopsLevelPoints * pointSize;
   const double bid              = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask              = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBuy)
   {
      if(bid <= 0.0)
         return false;
      if(minDistance > 0.0 && newStopLoss >= bid - minDistance)
         return false;
      if(takeProfitPrice > 0.0 && minDistance > 0.0 && takeProfitPrice <= ask + minDistance)
         return false;
   }
   else
   {
      if(ask <= 0.0)
         return false;
      if(minDistance > 0.0 && newStopLoss <= ask + minDistance)
         return false;
      if(takeProfitPrice > 0.0 && minDistance > 0.0 && takeProfitPrice >= bid - minDistance)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool HuntTradeCommentIsCloseQuarter(const string orderComment)
{
   return (StringFind(orderComment, "_CQ_") >= 0);
}

//+------------------------------------------------------------------+
bool HuntTradeCommentIsOverall(const string orderComment)
{
   return (StringFind(orderComment, "_OV_") >= 0);
}

//+------------------------------------------------------------------+
bool HuntTradeCommentIsOvTpIndex(const string orderComment, const int tpIndex)
{
   if(tpIndex < 1 || tpIndex > LQ_TP_COUNT)
      return false;
   return (StringFind(orderComment, "_OV_TP" + IntegerToString(tpIndex) + "_") >= 0);
}

//+------------------------------------------------------------------+
void ClearHuntTradeSessionIfNoOpenPositions()
{
   if(HasOurHuntTradeOpenPosition())
      return;
   g_huntTradeSessionCommentPrefix = "";
   g_huntFirstOppBosMgmtDone       = false;
   g_lastHuntPosMgmtM2BarTime      = 0;
}

//+------------------------------------------------------------------+
bool M2LegContainsFvg(const datetime legStart, const datetime legEnd, const bool checkBullish)
{
   if(legStart == 0 || legEnd == 0)
      return false;
   int shiftStart = iBarShift(_Symbol, InputM2NarrativeTimeframe, legStart, true);
   int shiftEnd = iBarShift(_Symbol, InputM2NarrativeTimeframe, legEnd, true);
   if(shiftStart < 0)
      shiftStart = iBarShift(_Symbol, InputM2NarrativeTimeframe, legStart, false);
   if(shiftEnd < 0)
      shiftEnd = 1;
   if(shiftStart < shiftEnd)
   {
      int tmp = shiftStart;
      shiftStart = shiftEnd;
      shiftEnd = tmp;
   }

   if(shiftStart - shiftEnd < 2)
      return false;

   for(int i = shiftEnd; i <= shiftStart - 2; i++)
   {
      const double bar1High = iHigh(_Symbol, InputM2NarrativeTimeframe, i + 2);
      const double bar1Low  = iLow(_Symbol, InputM2NarrativeTimeframe, i + 2);
      const double bar3High = iHigh(_Symbol, InputM2NarrativeTimeframe, i);
      const double bar3Low  = iLow(_Symbol, InputM2NarrativeTimeframe, i);

      if(checkBullish && bar3Low > bar1High)
         return true;
      if(!checkBullish && bar3High < bar1Low)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryGetLatestQualifiedSlExtreme(const bool isBuy, double &outGroupExtreme)
{
    outGroupExtreme = 0.0;
    if(g_m2Swing.swingHistoryCount < 2) return false;

    const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    const double tolerance = (pointSize > 0.0 ? pointSize : 0.00001);
    
    int targetLegIndex = -1;

    // 1. Find most recent completed leg that caused a BOS AND has an FVG
    for(int i = g_m2Swing.swingHistoryCount - 1; i >= 1; i--)
    {
        const Swing leg = g_m2Swing.swingHistory[i];

        if(isBuy && leg.swingDirection == 1)
        {
            double prevHigh = 0.0;
            for(int j = i - 1; j >= 0; j--) {
                if(g_m2Swing.swingHistory[j].swingDirection == -1) {
                    prevHigh = g_m2Swing.swingHistory[j].legHighPrice;
                    break;
                }
            }
            if(prevHigh > 0.0 && leg.legHighPrice > prevHigh + tolerance)
            {
                if(M2LegContainsFvg(leg.legStartTime, leg.legEndTime, true))
                {
                    targetLegIndex = i;
                    break;
                }
            }
        }
        else if(!isBuy && leg.swingDirection == -1)
        {
            double prevLow = 0.0;
            for(int j = i - 1; j >= 0; j--) {
                if(g_m2Swing.swingHistory[j].swingDirection == 1) {
                    prevLow = g_m2Swing.swingHistory[j].legLowPrice;
                    break;
                }
            }
            if(prevLow > 0.0 && leg.legLowPrice < prevLow - tolerance)
            {
                if(M2LegContainsFvg(leg.legStartTime, leg.legEndTime, false))
                {
                    targetLegIndex = i;
                    break;
                }
            }
        }
    }

    if(targetLegIndex < 0) return false;

    const double originExtreme = isBuy ? g_m2Swing.swingHistory[targetLegIndex].legLowPrice 
                                       : g_m2Swing.swingHistory[targetLegIndex].legHighPrice;
    const datetime originTime  = g_m2Swing.swingHistory[targetLegIndex].legStartTime;

    // 2. Group the origin extreme with nearby equal highs/lows
    int formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, originTime, false);
    if(formationShift < 0) formationShift = 1;
    const double chartHeight = ReferenceChartHeightForM2BarCountFromShift(formationShift, InputTradeSwingLookbackM2Bars);
    const double proximityBand = chartHeight * (InputTradeSwingProximityPercentOfChartRange / 100.0);

    outGroupExtreme = originExtreme;
    datetime earliestTime = originTime;

    for(int i = 0; i < g_m2Swing.swingHistoryCount; i++)
    {
        const Swing leg = g_m2Swing.swingHistory[i];
        if(isBuy && leg.swingDirection == 1)
        {
            if(MathAbs(leg.legLowPrice - originExtreme) <= proximityBand)
            {
                outGroupExtreme = MathMin(outGroupExtreme, leg.legLowPrice);
                if(leg.legStartTime > 0 && leg.legStartTime < earliestTime) earliestTime = leg.legStartTime;
            }
        }
        else if(!isBuy && leg.swingDirection == -1)
        {
            if(MathAbs(leg.legHighPrice - originExtreme) <= proximityBand)
            {
                outGroupExtreme = MathMax(outGroupExtreme, leg.legHighPrice);
                if(leg.legStartTime > 0 && leg.legStartTime < earliestTime) earliestTime = leg.legStartTime;
            }
        }
    }
    
    // 3. Draw the Proximity Buffer Visual (Blue Rectangle)
    if(H4LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
    {
        double boundLow = 0.0;
        double boundHigh = 0.0;
        
        // Match TP logic: anchor to the extreme and project 10% inward
        if(isBuy)
        {
            boundLow  = outGroupExtreme;
            boundHigh = outGroupExtreme + proximityBand;
        }
        else
        {
            boundHigh = outGroupExtreme;
            boundLow  = outGroupExtreme - proximityBand;
        }

        datetime timeRight = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
        if(timeRight == 0) timeRight = TimeCurrent();
        
        const string objName = "LQ2_SL_PROX_R_" + IntegerToString((long)originTime);
        if(ObjectFind(0, objName) < 0)
        {
            ObjectCreate(0, objName, OBJ_RECTANGLE, 0, earliestTime, boundHigh, timeRight, boundLow);
        }
        else
        {
            ObjectSetInteger(0, objName, OBJPROP_TIME, 0, earliestTime);
            ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, boundHigh);
            ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeRight);
            ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, boundLow);
        }
        
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDodgerBlue); // Distinct Blue Color
        ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, objName, OBJPROP_FILL, false);
        ObjectSetInteger(0, objName, OBJPROP_BACK, false);
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
        ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    
    return true;
}

//+------------------------------------------------------------------+
void ManageHuntTradeTieredStopLoss(const bool isBuy)
{
   if(!InputEnableBosMoveSlAndTp) return;

   bool hasTp1 = false, hasTp2 = false, hasTp3 = false;
   double entryPrice = 0.0;
   
   // 1. Scan open positions to deduce which TPs have been hit/closed
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC) continue;
      
      string comment = PositionGetString(POSITION_COMMENT);
      if(!HuntTradeCommentIsOurs(comment)) continue;
      
      if(HuntTradeCommentIsOvTpIndex(comment, 1)) hasTp1 = true;
      if(HuntTradeCommentIsOvTpIndex(comment, 2)) hasTp2 = true;
      if(HuntTradeCommentIsOvTpIndex(comment, 3)) hasTp3 = true;
      
      if(entryPrice == 0.0) entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   }
   
   if(entryPrice <= 0.0) return; // No open positions for this hunt

   double newStopLoss = 0.0;
   int currentStage = 0;

   // STAGE 2: TP1 and TP2 are HIT (Only TP3 remains)
   if(!hasTp1 && !hasTp2 && hasTp3)
   {
      currentStage = 2;
      double groupExtreme = 0.0;
      
      // Look backward for the latest structural BOS + FVG, group it with equal highs/lows
      if(TryGetLatestQualifiedSlExtreme(isBuy, groupExtreme))
      {
         const double chartHeight = ReferenceChartHeightForFairValueGapFilterM2();
         const double buffer2Percent = chartHeight * 0.02;

         if(isBuy) newStopLoss = NormalizeDouble(groupExtreme - buffer2Percent, _Digits);
         else      newStopLoss = NormalizeDouble(groupExtreme + buffer2Percent, _Digits);
      }
   }
   // STAGE 1: TP1 is HIT (TP2 and/or TP3 still remain)
   else if(!hasTp1 && (hasTp2 || hasTp3))
   {
      currentStage = 1;
      newStopLoss = NormalizeDouble(entryPrice, _Digits); // Move to Break-Even
   }
   
   if(newStopLoss <= 0.0 || currentStage == 0) return; // Nothing to update

   // 2. Apply the modification to surviving positions
   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();

   int modifiedCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC) continue;
      if(!HuntTradeCommentIsOurs(PositionGetString(POSITION_COMMENT))) continue;

      double currentSl = PositionGetDouble(POSITION_SL);
      double currentTp = PositionGetDouble(POSITION_TP);
      bool posIsBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      if(posIsBuy != isBuy) continue;

      // NEVER move SL backwards (widen risk)
      if(isBuy && currentSl > 0.0 && newStopLoss <= currentSl) continue;
      if(!isBuy && currentSl > 0.0 && newStopLoss >= currentSl) continue;

      if(!StopLossModifyAllowed(posIsBuy, newStopLoss, currentTp)) continue;

      if(g_trade.PositionModify(ticket, newStopLoss, currentTp))
      {
         modifiedCount++;
      }
   }
   
   if(modifiedCount > 0)
   {
       LogHuntEvent("TRADE_SL_TIERED", 
                    StringFormat("Tiered SL moved to %.5f | Stage: %s", 
                                 newStopLoss, 
                                 currentStage == 2 ? "TP2 Hit -> Structural - 2%" : "TP1 Hit -> Break-Even"));
   }
}

//+------------------------------------------------------------------+
void ManageHuntOpenPositionsOnM2BarClose()
{
   if(!HasOurHuntTradeOpenPosition())
   {
      ClearHuntTradeSessionIfNoOpenPositions();
      return;
   }

   EnsureHuntTradeSessionCommentPrefixFromOrdersOrPositions();

   const datetime closedM2BarTime = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   if(closedM2BarTime == 0 || closedM2BarTime == g_lastHuntPosMgmtM2BarTime)
      return;
   g_lastHuntPosMgmtM2BarTime = closedM2BarTime;

   bool isBuy         = g_huntTradeIsBuy;
   bool haveTradeSide = false;
   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      if(PositionGetSymbol(positionIndex) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!HuntTradeCommentIsOurs(PositionGetString(POSITION_COMMENT)))
         continue;
      isBuy         = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      haveTradeSide = true;
      break;
   }
   if(!haveTradeSide && !g_huntTradeOrdersActive)
      return;

   ManageHuntTradeTieredStopLoss(isBuy);
}

//| huntSessionId=0: all LQ2_HS pendings; else that session only (TP3 / chart-range cancel). |
//+------------------------------------------------------------------+
void CancelOurHuntPendingOrders(const datetime huntSessionId)
{
   const int    huntIndex = V2FindHuntSlotBySessionId(huntSessionId);
   const string sessionPrefix =
      (huntSessionId != 0 ? V2HuntTradeCommentPrefix(huntSessionId) : "");

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   int deletedCount = 0;
   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(orderState != ORDER_STATE_PLACED && orderState != ORDER_STATE_PARTIAL)
         continue;

      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT &&
         orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP &&
         orderType != ORDER_TYPE_BUY_STOP_LIMIT && orderType != ORDER_TYPE_SELL_STOP_LIMIT)
         continue;

      const string comment = OrderGetString(ORDER_COMMENT);
      if(StringFind(comment, "LQ2_HS") != 0)
         continue;
      if(sessionPrefix != "" && StringFind(comment, sessionPrefix) != 0)
         continue;

      if(g_trade.OrderDelete(ticket))
         deletedCount++;
   }

   if(deletedCount > 0)
   {
      if(huntIndex >= 0)
         V2LogHuntEvent(huntIndex, "HUNT_PENDING_DELETE",
                        StringFormat("deleted=%d", deletedCount));
      else if(huntSessionId != 0)
         LogHuntEvent("HUNT_PENDING_DELETE",
                      StringFormat("HS%lld deleted=%d", (long)huntSessionId, deletedCount));
      else
         LogHuntEvent("HUNT_PENDING_DELETE", StringFormat("deleted=%d", deletedCount));
   }
}

//+------------------------------------------------------------------+
void ResetHuntTradePlacementGateOnly()
{
   g_huntTradeOrdersActive      = false;
   g_huntOrdersFvgFormationTime = 0;
}

//+------------------------------------------------------------------+
void ResetHuntTradeState()
{
   g_huntTradeOrdersActive      = false;
   g_huntOrdersFvgFormationTime = 0;
   g_huntTradeIsBuy             = false;
   g_huntTradeEntryPrice        = 0.0;
   g_huntPreEntryCancelTpLevel  = 0.0;
   if(!HasOurHuntTradeOpenPosition())
   {
      g_huntTradeSessionCommentPrefix = "";
      g_huntFirstOppBosMgmtDone       = false;
      g_lastHuntPosMgmtM2BarTime      = 0;
   }
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool V2HuntHasOpenPositionForSession(const datetime huntSessionId)
{
   const string prefix = V2HuntTradeCommentPrefix(huntSessionId);
   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      if(PositionGetSymbol(positionIndex) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), prefix) == 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool V2HuntHasPendingOrdersForSession(const datetime huntSessionId)
{
   const string prefix = V2HuntTradeCommentPrefix(huntSessionId);
   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(orderState != ORDER_STATE_PLACED && orderState != ORDER_STATE_PARTIAL)
         continue;

      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT &&
         orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP &&
         orderType != ORDER_TYPE_BUY_STOP_LIMIT && orderType != ORDER_TYPE_SELL_STOP_LIMIT)
         continue;

      if(StringFind(OrderGetString(ORDER_COMMENT), prefix) == 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool ResolveHuntFvgOrderPlacementGate(const datetime formationTime, const datetime huntSessionId,
                                      bool &outReplacePendingOnly)
{
   outReplacePendingOnly = false;
   const int huntIndex = V2FindHuntSlotBySessionId(huntSessionId);

   if(V2HuntHasOpenPositionForSession(huntSessionId))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt position open â€” one trade setup per hunt");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
void RegisterHuntTradeAfterSuccessfulPlace(const bool isBuy, const double entryPrice,
                                           const double takeProfitTp1Price,
                                           const double preEntryCancelTpLevel,
                                           const datetime fvgFormationTime,
                                           const datetime huntSessionId)
{
   const int huntIndex = V2FindHuntSlotBySessionId(huntSessionId);
   if(huntIndex >= 0)
   {
      g_v2Hunts[huntIndex].tradeOrdersActive      = true;
      g_v2Hunts[huntIndex].ordersFvgFormationTime = fvgFormationTime;
      g_v2Hunts[huntIndex].tradeIsBuy             = isBuy;
      g_v2Hunts[huntIndex].tradeEntryPrice        = entryPrice;
      g_v2Hunts[huntIndex].tradeTp1Price          = takeProfitTp1Price;
      g_v2Hunts[huntIndex].preEntryCancelTpLevel  = preEntryCancelTpLevel;
      g_v2Hunts[huntIndex].firstOppBosMgmtDone    = false;
   }
   g_huntTradeOrdersActive           = true;
   g_huntOrdersFvgFormationTime      = fvgFormationTime;
   g_huntTradeIsBuy                  = isBuy;
   g_huntTradeEntryPrice             = entryPrice;
   g_huntPreEntryCancelTpLevel       = preEntryCancelTpLevel;
   g_huntTradeSessionCommentPrefix   = V2HuntTradeCommentPrefix(huntSessionId);
   g_huntFirstOppBosMgmtDone         = false;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Bull: bid > top+1% M2 chart rng â†’ BuyLimit @ top+1%; else market buy.          |
//| Bear: ask < lowâˆ’1% M2 chart rng â†’ SellLimit @ lowâˆ’1%; else market sell.         |
//+------------------------------------------------------------------+
// Latest completed H4 same-dir leg (MTF SMC). TP = 0.9x / 1.4x / 1.9x from entry.
double M2PendingStopEntryPrice(const bool isBuy, const double referenceEntryPrice)
{
   if(referenceEntryPrice <= 0.0)
      return 0.0;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pointSize <= 0.0)
      return 0.0;

   int offsetPoints = InputPendingStopEntryOffsetPoints;
   if(offsetPoints < 1)
      offsetPoints = 1;
   else if(offsetPoints > 2)
      offsetPoints = 2;

   const double offsetPrice = (double)offsetPoints * pointSize;
   double stopEntry = isBuy
                      ? referenceEntryPrice + offsetPrice
                      : referenceEntryPrice - offsetPrice;
   stopEntry = NormalizeDouble(stopEntry, _Digits);

   const int stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double minDistance   = (double)stopsLevelPoints * pointSize;
   const double ask           = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid           = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(isBuy)
   {
      const double minBuyStop = ask + minDistance;
      if(stopEntry <= minBuyStop)
         stopEntry = NormalizeDouble(minBuyStop + offsetPrice, _Digits);
   }
   else
   {
      const double maxSellStop = bid - minDistance;
      if(stopEntry >= maxSellStop)
         stopEntry = NormalizeDouble(maxSellStop - offsetPrice, _Digits);
   }

   return stopEntry;
}

//+------------------------------------------------------------------+
double ResolveTradeEntryPriceForOrderType(const bool isBuy, const double referenceEntryPrice)
{
   if(referenceEntryPrice <= 0.0)
      return 0.0;

   switch(InputTradeEntryOrderType)
   {
      case TRADE_ENTRY_ORDER_MARKET:
      {
         double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                    : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(marketPrice <= 0.0)
            marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_LAST)
                                : SymbolInfoDouble(_Symbol, SYMBOL_LAST);
         return (marketPrice > 0.0 ? NormalizeDouble(marketPrice, _Digits) : 0.0);
      }
      case TRADE_ENTRY_ORDER_STOP:
         return M2PendingStopEntryPrice(isBuy, referenceEntryPrice);
      case TRADE_ENTRY_ORDER_LIMIT:
      default:
         return NormalizeDouble(referenceEntryPrice, _Digits);
   }
}

//+------------------------------------------------------------------+
bool TradeEntryOrderTypeIsPending(const ENUM_TRADE_ENTRY_ORDER_TYPE orderType)
{
   return (orderType == TRADE_ENTRY_ORDER_LIMIT || orderType == TRADE_ENTRY_ORDER_STOP);
}

//+------------------------------------------------------------------+
bool ValidateTradeOrderEntryVsStop(const bool isBuy, const double orderEntry, const double stopLoss,
                                    string &outReason)
{
   outReason = "";
   if(orderEntry <= 0.0)
   {
      outReason = "order entry invalid";
      return false;
   }
   if(isBuy && orderEntry <= stopLoss)
   {
      outReason = StringFormat("buy entry<=SL entry=%.5f sl=%.5f", orderEntry, stopLoss);
      return false;
   }
   if(!isBuy && orderEntry >= stopLoss)
   {
      outReason = StringFormat("sell entry>=SL entry=%.5f sl=%.5f", orderEntry, stopLoss);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool HasOurHuntPendingEntryOrders(const datetime huntSessionId)
{
   const string sessionPrefix =
      (huntSessionId != 0 ? V2HuntTradeCommentPrefix(huntSessionId) : "");

   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(orderState != ORDER_STATE_PLACED && orderState != ORDER_STATE_PARTIAL)
         continue;

      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT &&
         orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP &&
         orderType != ORDER_TYPE_BUY_STOP_LIMIT && orderType != ORDER_TYPE_SELL_STOP_LIMIT)
         continue;

      const string comment = OrderGetString(ORDER_COMMENT);
      if(StringFind(comment, "LQ2_HS") != 0)
         continue;
      if(sessionPrefix != "" && StringFind(comment, sessionPrefix) != 0)
         continue;

      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void ClearPendingEntryOrderExpiry()
{
   g_pendingEntryOrderExpiryDeadline = 0;
   g_pendingEntryOrderExpirySessionId = 0;
   if(g_pendingEntryOrderExpiryTimerOn && !HasOurHuntPendingEntryOrders(0))
   {
      EventKillTimer();
      g_pendingEntryOrderExpiryTimerOn = false;
   }
}

//+------------------------------------------------------------------+
void ArmPendingEntryOrderExpiry(const datetime huntSessionId)
{
   if(InputPendingOrderExpirySeconds <= 0)
      return;
   if(!TradeEntryOrderTypeIsPending(InputTradeEntryOrderType))
      return;

   g_pendingEntryOrderExpiryDeadline  = TimeCurrent() + (datetime)InputPendingOrderExpirySeconds;
   g_pendingEntryOrderExpirySessionId = huntSessionId;

   if(!g_pendingEntryOrderExpiryTimerOn)
   {
      EventSetTimer(1);
      g_pendingEntryOrderExpiryTimerOn = true;
   }
}

//+------------------------------------------------------------------+
void ProcessPendingEntryOrderExpiry()
{
   if(g_pendingEntryOrderExpiryDeadline == 0)
      return;

   if(TimeCurrent() < g_pendingEntryOrderExpiryDeadline)
   {
      if(!HasOurHuntPendingEntryOrders(g_pendingEntryOrderExpirySessionId))
         ClearPendingEntryOrderExpiry();
      return;
   }

   if(!HasOurHuntPendingEntryOrders(g_pendingEntryOrderExpirySessionId))
   {
      ClearPendingEntryOrderExpiry();
      return;
   }

   CancelOurHuntPendingOrders(g_pendingEntryOrderExpirySessionId);
   LogHuntEvent("PENDING_EXPIRE",
                StringFormat("HS%lld cancelled unfilled pendings after %d sec orderType=%d",
                             (long)g_pendingEntryOrderExpirySessionId,
                             InputPendingOrderExpirySeconds,
                             (int)InputTradeEntryOrderType));
   ClearPendingEntryOrderExpiry();
}

//+------------------------------------------------------------------+
void FinalizeTradePlacementBatch(const bool isBuy, const double orderEntry, const double tp1,
                                  const double farthestTp, const datetime formationTime,
                                  const datetime huntSessionId, const int placedCount)
{
   if(placedCount <= 0)
      return;

   if(TradeEntryOrderTypeIsPending(InputTradeEntryOrderType))
      ArmPendingEntryOrderExpiry(huntSessionId);

   RegisterHuntTradeAfterSuccessfulPlace(isBuy, orderEntry, tp1, farthestTp, formationTime,
                                         huntSessionId);
}

//+------------------------------------------------------------------+
bool PlaceOneFvgTradeOrder(const bool isBuy, const ENUM_TRADE_ENTRY_ORDER_TYPE orderType,
                           const double entryPrice, const double stopLossPrice, const double takeProfitPrice,
                           const double volume, const string comment, const double setupScore)
{
   if(volume <= 0.0)
   {
      LogHuntEvent("TRADE_ORDER_FAIL", StringFormat("%s volume=0", comment));
      return false;
   }

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   g_trade.SetDeviationInPoints(30);
   ApplyTradeFillingModeFromSymbol();

   bool ok = false;
   switch(orderType)
   {
      case TRADE_ENTRY_ORDER_MARKET:
         if(isBuy)
            ok = g_trade.Buy(volume, _Symbol, 0.0, stopLossPrice, takeProfitPrice, comment);
         else
            ok = g_trade.Sell(volume, _Symbol, 0.0, stopLossPrice, takeProfitPrice, comment);
         break;

      case TRADE_ENTRY_ORDER_STOP:
         if(isBuy)
            ok = g_trade.BuyStop(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                                 ORDER_TIME_GTC, 0, comment);
         else
            ok = g_trade.SellStop(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                                  ORDER_TIME_GTC, 0, comment);
         break;

      case TRADE_ENTRY_ORDER_LIMIT:
      default:
         if(isBuy)
            ok = g_trade.BuyLimit(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                                  ORDER_TIME_GTC, 0, comment);
         else
            ok = g_trade.SellLimit(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                                   ORDER_TIME_GTC, 0, comment);
         break;
   }

   if(!ok)
      LogHuntEvent("TRADE_ORDER_FAIL",
                   StringFormat("%s type=%d ret=%d %s", comment, (int)orderType,
                                (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
   else
      LogHuntEvent("TRADE_ORDER",
                   StringFormat("type=%d setupScore=%.2f %s %s entry=%.5f",
                                (int)orderType, setupScore,
                                isBuy ? "buy" : "sell", comment, entryPrice));
   return ok;
}

//+------------------------------------------------------------------+
bool PlaceFvgTradeOrderForSetup(const bool isBuy, const double referenceEntryPrice,
                                 const double stopLossPrice, const double takeProfitPrice,
                                 const double volume, const string comment, const double setupScore)
{
   const double entryPrice = ResolveTradeEntryPriceForOrderType(isBuy, referenceEntryPrice);
   if(entryPrice <= 0.0)
   {
      LogHuntEvent("TRADE_ORDER_FAIL", StringFormat("%s entry resolve failed", comment));
      return false;
   }

   return PlaceOneFvgTradeOrder(isBuy, InputTradeEntryOrderType, entryPrice,
                                stopLossPrice, takeProfitPrice, volume, comment, setupScore);
}

//+------------------------------------------------------------------+
double ComputeDoubleRiskTakeProfitPrice(const bool isBuy, const double entryPrice,
                                         const double stopLossPrice)
{
   const double slDistance = MathAbs(entryPrice - stopLossPrice);
   if(slDistance <= 0.0)
      return 0.0;

   if(isBuy)
      return NormalizeDouble(entryPrice + 2.0 * slDistance, _Digits);
   return NormalizeDouble(entryPrice - 2.0 * slDistance, _Digits);
}

//+------------------------------------------------------------------+
bool TryPlaceFvgTradeDoubleRiskAddonOrder(const bool isBuy, const double referenceEntryPrice,
                                           const double stopLossPrice,
                                           const string huntCommentPrefix, const string formationTag,
                                           int &inOutPlacedCount, int &inOutZeroVolumeCount,
                                           const double setupScore)
{
   const double orderEntry =
      ResolveTradeEntryPriceForOrderType(isBuy, referenceEntryPrice);
   const double takeProfit2R =
      ComputeDoubleRiskTakeProfitPrice(isBuy, orderEntry, stopLossPrice);
   if(takeProfit2R <= 0.0)
      return false;

   if(!StopsDistanceAllowed(isBuy, orderEntry, stopLossPrice, takeProfit2R))
      return false;

   const string comment2R = StringFormat("%sOV_2R_%s", huntCommentPrefix, formationTag);
   const double volume2R  =
      GetOptimizedLotSize(orderEntry, stopLossPrice, setupScore, isBuy, 1.0);
   if(volume2R <= 0.0)
   {
      inOutZeroVolumeCount++;
      return false;
   }

   if(!PlaceFvgTradeOrderForSetup(isBuy, referenceEntryPrice, stopLossPrice, takeProfit2R,
                                  volume2R, comment2R, setupScore))
      return false;

   inOutPlacedCount++;
   return true;
}

//+------------------------------------------------------------------+
bool IsFvgAutomatedTradingAllowed(string &outBlockReason)
{
   outBlockReason = "";
   if(!InputEnableAutomatedTrading)
   {
      outBlockReason = "InputEnableAutomatedTrading=false (log only)";
      return false;
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      outBlockReason = "terminal AutoTrading off";
      return false;
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      outBlockReason = "EA trading not allowed on this chart";
      return false;
   }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      outBlockReason = "ACCOUNT_TRADE_EXPERT disabled";
      return false;
   }
   const long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      outBlockReason = "symbol trading disabled";
      return false;
   }
   return true;
}

bool TryPlaceEngulfAbsorptionTradeSetup(const int huntIndex, const bool isBuy,
                                         const double entryPrice, const double stopLossPrice,
                                         const datetime signalBarOpenTime,
                                         const datetime huntSessionId,
                                         const double setupScore)
{
   if(ScoreLogWriteModeSkipsTrading())
      return false;

   if(signalBarOpenTime == 0)
      return false;
   if(huntIndex >= V2_MAX_HUNT_SESSIONS)
      return false;

   if(!SetupScoreAllowsTradeEntry(setupScore))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("setupScore=%.2f < min %.2f", setupScore, InputMinScore));
      return false;
   }

   string bosBiasBlockReason = "";
   if(!FvgTradeAllowedByH4BosBias(isBuy, bosBiasBlockReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", bosBiasBlockReason);
      return false;
   }

   bool replacePendingOnly = false;
   if(!ResolveHuntFvgOrderPlacementGate(signalBarOpenTime, huntSessionId, replacePendingOnly))
      return false;

   const double normalizedEntry = NormalizeDouble(entryPrice, _Digits);
   const double referenceEntry  = normalizedEntry;
   double stopLoss = NormalizeDouble(stopLossPrice, _Digits);
   if(!ApplyTouchVolMinimumSlDistance(isBuy, referenceEntry, stopLoss))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "engulf SL distance invalid");
      return false;
   }

   const double orderEntry =
      ResolveTradeEntryPriceForOrderType(isBuy, referenceEntry);
   string entrySideReason = "";
   if(!ValidateTradeOrderEntryVsStop(isBuy, orderEntry, stopLoss, entrySideReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", entrySideReason);
      return false;
   }

   double takeProfitPrices[];
   int    takeProfitCount = 0;
   if(!BuildTradeSwingGroupTakeProfits(isBuy, signalBarOpenTime, orderEntry,
                                       stopLoss, takeProfitPrices, takeProfitCount))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("no swing-group TP with min R:R %.2f entry=%.5f sl=%.5f",
                                  InputTradeSwingTpMinRewardToRisk, orderEntry, stopLoss));
      return false;
   }

   for(int tpIndex = 0; tpIndex < takeProfitCount; tpIndex++)
   {
      if(!StopsDistanceAllowed(isBuy, orderEntry, stopLoss, takeProfitPrices[tpIndex]))
      {
         V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                          StringFormat("broker stops level tp=%d", tpIndex + 1));
         return false;
      }
   }

   if(InputBaseRiskPercent <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "InputBaseRiskPercent invalid");
      return false;
   }

   const double tpRiskWeights[3] = {3.0, 1.0, 1.0};
   const double riskTotalParts   = tpRiskWeights[0] + tpRiskWeights[1] + tpRiskWeights[2];
   const string huntCommentPrefix = V2HuntTradeCommentPrefix(huntSessionId);
   const string formationTag      = TimeToString(signalBarOpenTime, TIME_DATE | TIME_MINUTES);
   const string logDetail =
      StringFormat("buy=%s ref=%.5f orderEntry=%.5f sl=%.5f type=%d signal=%s score=%.2f",
                   isBuy ? "Y" : "N", referenceEntry, orderEntry, stopLoss,
                   (int)InputTradeEntryOrderType, formationTag, setupScore);

   string tradeBlockReason = "";
   if(!IsFvgAutomatedTradingAllowed(tradeBlockReason))
   {
      LogHuntEvent("TRADE_PLAN", logDetail + " | " + tradeBlockReason);
      return false;
   }

   int placedCount    = 0;
   int zeroVolumeCount = 0;

   for(int tpIndex = 0; tpIndex < takeProfitCount; tpIndex++)
   {
      const string commentOv =
         StringFormat("%sOV_TP%d_%s", huntCommentPrefix, tpIndex + 1, formationTag);
      const double riskFraction = tpRiskWeights[tpIndex] / riskTotalParts;
      const double volumeOv =
         GetOptimizedLotSize(orderEntry, stopLoss, setupScore, isBuy, riskFraction);
      if(volumeOv <= 0.0)
         zeroVolumeCount++;
      else if(PlaceFvgTradeOrderForSetup(isBuy, referenceEntry,
                                         stopLoss, takeProfitPrices[tpIndex], volumeOv,
                                         commentOv, setupScore))
         placedCount++;
   }

   TryPlaceFvgTradeDoubleRiskAddonOrder(isBuy, referenceEntry, stopLoss,
                                         huntCommentPrefix, formationTag, placedCount,
                                         zeroVolumeCount, setupScore);

   const int orderTargetCount = takeProfitCount + 1;
   if(placedCount > 0)
   {
      const double farthestTp = takeProfitPrices[takeProfitCount - 1];
      FinalizeTradePlacementBatch(isBuy, orderEntry, takeProfitPrices[0],
                                  farthestTp, signalBarOpenTime, huntSessionId, placedCount);
      LogHuntEvent("TRADE_PLACE",
                   StringFormat("ENG_%s placed=%d/%d %s", formationTag, placedCount,
                                orderTargetCount, logDetail));
      return true;
   }

   V2LogHuntEvent(huntIndex, "TRADE_FAIL",
                  StringFormat("ENG_%s zeroVol=%d %s", formationTag, zeroVolumeCount, logDetail));
   return false;
}

//+------------------------------------------------------------------+
void V2InitHuntSlot(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   g_v2Hunts[huntIndex].active                         = false;
   g_v2Hunts[huntIndex].h4HighWasBreached             = false;
   g_v2Hunts[huntIndex].h4BreachedLegLevelPrice       = 0.0;
   g_v2Hunts[huntIndex].h4BreachedLegEndTime         = 0;
   g_v2Hunts[huntIndex].closeWhenH4LiquidityBreached  = 0.0;
   g_v2Hunts[huntIndex].pathMinLowSinceH4Breach            = 0.0;
   g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach           = 0.0;
   g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach = 0.0;
   g_v2Hunts[huntIndex].sessionId                      = 0;
   g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked    = 0.0;
   g_v2Hunts[huntIndex].tradeOrdersActive              = false;
   g_v2Hunts[huntIndex].ordersFvgFormationTime         = 0;
   g_v2Hunts[huntIndex].tradeIsBuy                     = false;
   g_v2Hunts[huntIndex].tradeEntryPrice                = 0.0;
   g_v2Hunts[huntIndex].tradeTp1Price                  = 0.0;
   g_v2Hunts[huntIndex].preEntryCancelTpLevel          = 0.0;
   g_v2Hunts[huntIndex].firstOppBosMgmtDone            = false;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void V2InitAllHuntSlots()
{
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
      V2InitHuntSlot(i);
}

int V2FindHuntSlotBySessionId(const datetime sessionId)
{
   if(sessionId == 0)
      return -1;
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
   {
      if(g_v2Hunts[i].sessionId == sessionId)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
string V2HuntObjectSuffix(const datetime sessionId)
{
   return IntegerToString((long)sessionId) + "_";
}

void V2LogHuntEvent(const int huntIndex, const string eventName, const string detail = "")
{
   if(!H4LqLoggingEnabled())
      return;
   string prefix = "";
   if(huntIndex >= 0 && huntIndex < V2_MAX_HUNT_SESSIONS && g_v2Hunts[huntIndex].sessionId != 0)
      prefix = "HS" + IntegerToString((long)g_v2Hunts[huntIndex].sessionId) + " ";
   else if(huntIndex >= 0)
      prefix = "HS? ";
   if(StringLen(detail) > 0)
      LogHuntEvent(eventName, prefix + detail);
   else
      LogHuntEvent(eventName, prefix);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| H4 up-leg breach â†’ bull FVG; H4 down-leg breach â†’ bear FVG.       |
//| Touch recalc: active opposite M2 leg while open; else last completed opposite. |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Same-dir extreme tracked while hunt is ON (path max high / min low). |
//| v3 legacy stubs
//| Hunt ON only. Opposite M2 BOS clears marked same-dir FVGs.       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool M2TryGetLegBarOpenFromEnd(const datetime legStartTime, const datetime legEndTime,
                                const int barsFromEnd, datetime &outBarOpen)
{
   outBarOpen = 0;
   if(legStartTime == 0 || legEndTime == 0 || barsFromEnd < 1)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int endShift = iBarShift(_Symbol, timeframe, legEndTime, true);
   if(endShift < 0)
      return false;

   const int targetShift = endShift + (barsFromEnd - 1);
   if(targetShift >= iBars(_Symbol, timeframe))
      return false;

   const datetime targetOpen = iTime(_Symbol, timeframe, targetShift);
   if(targetOpen == 0 || targetOpen < legStartTime)
      return false;

   outBarOpen = targetOpen;
   return true;
}

//+------------------------------------------------------------------+
//| v3 — Engulfing Volume Absorption model                             |
//+------------------------------------------------------------------+
bool M2BarIsBullishAtShift(const int barShift)
{
   const double openPrice  = iOpen(_Symbol, InputM2NarrativeTimeframe, barShift);
   const double closePrice = iClose(_Symbol, InputM2NarrativeTimeframe, barShift);
   return closePrice > openPrice;
}

//+------------------------------------------------------------------+
bool M2BarIsBearishAtShift(const int barShift)
{
   const double openPrice  = iOpen(_Symbol, InputM2NarrativeTimeframe, barShift);
   const double closePrice = iClose(_Symbol, InputM2NarrativeTimeframe, barShift);
   return closePrice < openPrice;
}

//+------------------------------------------------------------------+
bool M2SwingLegMeetsExhaustionMinRange(const Swing &leg, const double chartHeight)
{
   if(InputEngulfExhaustionMinLegRangePercentChart <= 0.0)
      return true;
   if(chartHeight <= 0.0 || leg.legHighPrice <= 0.0 || leg.legLowPrice <= 0.0)
      return false;

   const double legRange = leg.legHighPrice - leg.legLowPrice;
   const double minRange = chartHeight * (InputEngulfExhaustionMinLegRangePercentChart / 100.0);
   return legRange >= minRange;
}

//+------------------------------------------------------------------+
bool M2SumLegTickVolumeFromPrevLegWindow(const Swing &prevLeg, const Swing &curLeg, long &outSum)
{
   outSum = 0;
   datetime winStart = 0;
   datetime winEnd   = 0;
   if(!M2TryGetLegBarOpenFromEnd(prevLeg.legStartTime, prevLeg.legEndTime, 2, winStart))
      return false;
   if(!M2TryGetLegBarOpenFromEnd(curLeg.legStartTime, curLeg.legEndTime, 2, winEnd))
      return false;

   long     vols[];
   int      count = 0;
   if(!M2CollectTickVolumesInOpenTimeWindow(winStart, winEnd, vols, count) || count < 1)
      return false;

   for(int i = 0; i < count; i++)
      outSum += vols[i];
   return true;
}

//+------------------------------------------------------------------+
double M2EngulfSlBufferPrice(const int barShift)
{
   if(InputEngulfSlBufferPercentChart <= 0.0)
      return 0.0;

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(barShift, InputChartRangeBarCount);
   if(chartHeight <= 0.0)
      return 0.0;
   return chartHeight * (InputEngulfSlBufferPercentChart / 100.0);
}

//+------------------------------------------------------------------+
double M2AvgTickVolumeLastBars(const int lastClosedBarShift, const int barCount)
{
   if(lastClosedBarShift < 1 || barCount < 1)
      return 0.0;

   long   totalVol = 0;
   int    validBars = 0;
   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);

   for(int shift = lastClosedBarShift; shift < lastClosedBarShift + barCount; shift++)
   {
      if(shift >= barsTotal)
         break;
      const long barVol = iTickVolume(_Symbol, timeframe, shift);
      if(barVol < 0)
         continue;
      totalVol += barVol;
      validBars++;
   }

   if(validBars < 1)
      return 0.0;
   return (double)totalVol / (double)validBars;
}

//+------------------------------------------------------------------+
bool V3DetectBearishEngulfFootprint(const int candle1Shift, const int candle2Shift)
{
   if(candle1Shift < 1 || candle2Shift < 1)
      return false;
   if(!M2BarIsBullishAtShift(candle1Shift))
      return false;
   if(!M2BarIsBearishAtShift(candle2Shift))
      return false;

   const double c1Open = iOpen(_Symbol, InputM2NarrativeTimeframe, candle1Shift);
   const double c2Close = iClose(_Symbol, InputM2NarrativeTimeframe, candle2Shift);
   return c2Close < c1Open;
}

//+------------------------------------------------------------------+
bool V3DetectBullishEngulfFootprint(const int candle1Shift, const int candle2Shift)
{
   if(candle1Shift < 1 || candle2Shift < 1)
      return false;
   if(!M2BarIsBearishAtShift(candle1Shift))
      return false;
   if(!M2BarIsBullishAtShift(candle2Shift))
      return false;

   const double c1Open = iOpen(_Symbol, InputM2NarrativeTimeframe, candle1Shift);
   const double c2Close = iClose(_Symbol, InputM2NarrativeTimeframe, candle2Shift);
   return c2Close > c1Open;
}

//+------------------------------------------------------------------+
struct V3SweepRefCandidate
{
   double   refLevel;
   datetime legEndTime;
   Swing    leg;
};

//+------------------------------------------------------------------+
bool V3M2PricesEqual(const double priceA, const double priceB, const double eps)
{
   return MathAbs(priceA - priceB) <= eps;
}

//+------------------------------------------------------------------+
int V3FindM2SwingLegHistoryIndex(const Swing &leg)
{
   for(int i = 0; i < g_m2Swing.swingHistoryCount; i++)
   {
      if(g_m2Swing.swingHistory[i].legStartTime == leg.legStartTime &&
         g_m2Swing.swingHistory[i].legEndTime == leg.legEndTime &&
         g_m2Swing.swingHistory[i].swingDirection == leg.swingDirection)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
bool V3TryGetM2LegAvgTickVolume(const Swing &leg, double &outLegAvg, int &outBarCount)
{
   outLegAvg   = 0.0;
   outBarCount = 0;
   if(leg.legStartTime == 0 || leg.legEndTime == 0)
      return false;

   long legVols[];
   int  legVolCount = 0;
   if(!M2CollectTickVolumesInOpenTimeWindow(leg.legStartTime, leg.legEndTime, legVols, legVolCount) ||
      legVolCount < 1)
      return false;

   long sumVol = 0;
   for(int i = 0; i < legVolCount; i++)
      sumVol += legVols[i];

   outLegAvg   = (double)sumVol / (double)legVolCount;
   outBarCount = legVolCount;
   return outLegAvg > 0.0;
}

//+------------------------------------------------------------------+
bool V3TryGetM2LegTransitionSpikeVolume(const Swing &leg, const int legHistoryIndex,
                                         long &outSpikeVol, datetime &outNextLegStartTime)
{
   outSpikeVol         = 0;
   outNextLegStartTime = 0;
   if(leg.legEndTime == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int lastBarShift = iBarShift(_Symbol, timeframe, leg.legEndTime, false);
   if(lastBarShift < 0)
      return false;

   const long volLastLegBar = iTickVolume(_Symbol, timeframe, lastBarShift);
   if(volLastLegBar < 0)
      return false;

   const int oppositeDir = -leg.swingDirection;
   Swing     nextLeg;
   ZeroMemory(nextLeg);
   bool haveNextLeg = false;

   if(legHistoryIndex >= 0 && legHistoryIndex + 1 < g_m2Swing.swingHistoryCount)
   {
      nextLeg = g_m2Swing.swingHistory[legHistoryIndex + 1];
      haveNextLeg = (nextLeg.swingDirection == oppositeDir && nextLeg.legStartTime > 0);
   }
   else if(g_m2Swing.currentSwingLeg.swingDirection == oppositeDir &&
           g_m2Swing.currentSwingLeg.legStartTime > 0)
   {
      nextLeg     = g_m2Swing.currentSwingLeg;
      haveNextLeg = true;
   }

   long spikeVol = volLastLegBar;
   if(haveNextLeg)
   {
      outNextLegStartTime = nextLeg.legStartTime;
      const int firstNextShift = iBarShift(_Symbol, timeframe, nextLeg.legStartTime, false);
      if(firstNextShift >= 0)
      {
         const long volFirstNextBar = iTickVolume(_Symbol, timeframe, firstNextShift);
         if(volFirstNextBar >= 0)
            spikeVol = MathMax(volLastLegBar, volFirstNextBar);
      }
   }

   outSpikeVol = spikeVol;
   return outSpikeVol > 0;
}

//+------------------------------------------------------------------+
bool V3SwingLegRefVolumeSpikeValid(const Swing &leg, string &outDetail)
{
   outDetail = "";
   if(leg.legEndTime == 0 || leg.legStartTime == 0)
   {
      outDetail = "leg times unavailable";
      return false;
   }

   double legAvg = 0.0;
   int    legBarCount = 0;
   if(!V3TryGetM2LegAvgTickVolume(leg, legAvg, legBarCount))
   {
      outDetail = "leg avg vol unavailable";
      return false;
   }

   const int legHistoryIndex = V3FindM2SwingLegHistoryIndex(leg);
   long      spikeVol        = 0;
   datetime  nextLegStart     = 0;
   if(!V3TryGetM2LegTransitionSpikeVolume(leg, legHistoryIndex, spikeVol, nextLegStart))
   {
      outDetail = "leg transition spike vol unavailable";
      return false;
   }

   outDetail = StringFormat("legVol spikeMax=%lld legAvg=%.0f bars=%d legEnd=%s nextLeg=%s",
                            (long)spikeVol, legAvg, legBarCount,
                            TimeToString(leg.legEndTime, TIME_DATE | TIME_MINUTES),
                            nextLegStart > 0
                               ? TimeToString(nextLegStart, TIME_DATE | TIME_MINUTES)
                               : "none");
   return (double)spikeVol > legAvg;
}

//+------------------------------------------------------------------+
//| Bear: (1) wick above ref somewhere in 1..countdown, (2) shift-1 close below ref with edge. |
//| Bull mirrored. Fires once on the rejecting close, not every bar the window still matches.   |
//+------------------------------------------------------------------+
bool V3CountdownTwoEventSweepSetup(const bool isBuy, const int countdown,
                                    const double refLevel, const double eps,
                                    double &outWindowSlExtreme, int &outTriggerShift)
{
   outWindowSlExtreme = isBuy ? 1.0e100 : -1.0e100;
   outTriggerShift    = 1;

   if(countdown < 1 || refLevel <= 0.0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   if(barsTotal < countdown + 2)
      return false;

   const double close1 = iClose(_Symbol, timeframe, 1);
   const double close2 = iClose(_Symbol, timeframe, 2);

   bool wickSweepInWindow = false;

   for(int shift = 1; shift <= countdown; shift++)
   {
      const double barHigh = iHigh(_Symbol, timeframe, shift);
      const double barLow  = iLow(_Symbol, timeframe, shift);

      if(isBuy)
      {
         outWindowSlExtreme = MathMin(outWindowSlExtreme, barLow);
         if(barLow < refLevel - eps)
            wickSweepInWindow = true;
      }
      else
      {
         outWindowSlExtreme = MathMax(outWindowSlExtreme, barHigh);
         if(barHigh > refLevel + eps)
            wickSweepInWindow = true;
      }
   }

   if(!wickSweepInWindow)
      return false;

   if(isBuy)
   {
      if(close1 <= refLevel + eps)
         return false;
      if(close2 > refLevel + eps)
         return false;
   }
   else
   {
      if(close1 >= refLevel - eps)
         return false;
      if(close2 < refLevel - eps)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
int V3BuildSweptSwingRefCandidates(const bool isBuy, const int countdown, const double eps,
                                    V3SweepRefCandidate &outCandidates[])
{
   ArrayResize(outCandidates, 0);
   const int legDirection = isBuy ? -1 : 1;

   V3SweepRefCandidate crossed[];
   int crossedCount = 0;

   for(int legIndex = 0; legIndex < g_m2Swing.swingHistoryCount; legIndex++)
   {
      const Swing leg = g_m2Swing.swingHistory[legIndex];
      if(leg.swingDirection != legDirection || leg.legEndTime == 0)
         continue;

      const double refLevel = isBuy ? leg.legLowPrice : leg.legHighPrice;
      if(refLevel <= 0.0)
         continue;

      double windowSlExtreme = 0.0;
      int    triggerShift    = 0;
      if(!V3CountdownTwoEventSweepSetup(isBuy, countdown, refLevel, eps,
                                         windowSlExtreme, triggerShift))
         continue;

      ArrayResize(crossed, crossedCount + 1);
      crossed[crossedCount].refLevel   = refLevel;
      crossed[crossedCount].legEndTime = leg.legEndTime;
      crossed[crossedCount].leg        = leg;
      crossedCount++;
   }

   if(crossedCount < 1)
      return 0;

   // Equal highs/lows: keep earliest legEndTime per price.
   V3SweepRefCandidate unique[];
   int uniqueCount = 0;

   for(int i = 0; i < crossedCount; i++)
   {
      bool merged = false;
      for(int u = 0; u < uniqueCount; u++)
      {
         if(!V3M2PricesEqual(crossed[i].refLevel, unique[u].refLevel, eps))
            continue;
         if(crossed[i].legEndTime < unique[u].legEndTime)
            unique[u] = crossed[i];
         merged = true;
         break;
      }
      if(!merged)
      {
         ArrayResize(unique, uniqueCount + 1);
         unique[uniqueCount++] = crossed[i];
      }
   }

   // Priority: bear = highest swept high first; bull = lowest swept low first.
   for(int i = 0; i < uniqueCount - 1; i++)
   {
      for(int j = i + 1; j < uniqueCount; j++)
      {
         bool swapNeeded = false;
         if(isBuy)
            swapNeeded = (unique[j].refLevel < unique[i].refLevel);
         else
            swapNeeded = (unique[j].refLevel > unique[i].refLevel);

         if(swapNeeded)
         {
            const V3SweepRefCandidate tmp = unique[i];
            unique[i] = unique[j];
            unique[j] = tmp;
         }
      }
   }

   ArrayResize(outCandidates, uniqueCount);
   for(int i = 0; i < uniqueCount; i++)
      outCandidates[i] = unique[i];
   return uniqueCount;
}

//+------------------------------------------------------------------+
bool V3TryGetM2SwingLegRefLevel(const bool isBuy, double &outRefLevel)
{
   outRefLevel = 0.0;
   const int  legDirection = isBuy ? -1 : 1;
   double     legLow       = 0.0;
   double     legHigh      = 0.0;
   datetime   legStart     = 0;
   datetime   legEnd       = 0;
   if(!V2TryGetLastCompletedM2Leg(legDirection, legLow, legHigh, legStart, legEnd))
      return false;

   outRefLevel = isBuy ? legLow : legHigh;
   return outRefLevel > 0.0;
}

//+------------------------------------------------------------------+
//| Two events in countdown: wick sweep then shift-1 close reject (edge). Multi-leg + leg vol. |
//+------------------------------------------------------------------+
bool V3DetectM2SwingSweepRejectInCountdown(const bool isBuy, const int countdown,
                                            double &outRefLevel, double &outWindowSlExtreme,
                                            int &outOldestShift, int &outNewestShift,
                                            string &outDetail)
{
   outRefLevel        = 0.0;
   outWindowSlExtreme = 0.0;
   outOldestShift     = countdown;
   outNewestShift     = 1;
   outDetail          = "";

   if(countdown < 1)
   {
      outDetail = "countdown < 1";
      return false;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   if(barsTotal < countdown + 2)
   {
      outDetail = "insufficient M2 bars";
      return false;
   }

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   V3SweepRefCandidate candidates[];
   const int candidateCount = V3BuildSweptSwingRefCandidates(isBuy, countdown, eps, candidates);
   if(candidateCount < 1)
   {
      outDetail = "no two-event sweep on shift-1 close";
      return false;
   }

   for(int candidateIndex = 0; candidateIndex < candidateCount; candidateIndex++)
   {
      const V3SweepRefCandidate candidate = candidates[candidateIndex];
      double windowSlExtreme = 0.0;
      int    triggerShift    = 0;

      if(!V3CountdownTwoEventSweepSetup(isBuy, countdown, candidate.refLevel, eps,
                                         windowSlExtreme, triggerShift))
         continue;

      string volDetail = "";
      if(!V3SwingLegRefVolumeSpikeValid(candidate.leg, volDetail))
      {
         V2LogHuntEvent(-1, "SWEEP_REF_INVALID",
                        StringFormat("%s ref=%.5f leg=%s — %s",
                                     isBuy ? "bull" : "bear",
                                     candidate.refLevel,
                                     TimeToString(candidate.legEndTime, TIME_DATE | TIME_MINUTES),
                                     volDetail));
         continue;
      }

      outRefLevel        = candidate.refLevel;
      outWindowSlExtreme = windowSlExtreme;
      outOldestShift     = countdown;
      outNewestShift     = triggerShift;
      outDetail = StringFormat("ref=%.5f leg=%s candidates=%d idx=%d %s",
                               candidate.refLevel,
                               TimeToString(candidate.legEndTime, TIME_DATE | TIME_MINUTES),
                               candidateCount, candidateIndex + 1, volDetail);
      return true;
   }

   outDetail = StringFormat("no swept ref passed leg vol (%d two-event)", candidateCount);
   return false;
}

//+------------------------------------------------------------------+
bool M2PrevLocalExtremeBeforeEngulfPair(const bool wantHigh, const int pairOldestShift,
                                         double &outExtreme)
{
   outExtreme = 0.0;
   const int lookbackStart = pairOldestShift + 1;
   const int lookbackEnd   = InputChartRangeBarCount;
   if(lookbackStart > lookbackEnd)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   bool found = false;

   for(int shift = lookbackStart; shift <= lookbackEnd; shift++)
   {
      if(shift >= barsTotal)
         break;
      if(wantHigh)
      {
         const double barHigh = iHigh(_Symbol, timeframe, shift);
         if(!found || barHigh > outExtreme)
         {
            outExtreme = barHigh;
            found = true;
         }
      }
      else
      {
         const double barLow = iLow(_Symbol, timeframe, shift);
         if(!found || barLow < outExtreme)
         {
            outExtreme = barLow;
            found = true;
         }
      }
   }
   return found;
}

//+------------------------------------------------------------------+
bool V3EngulfPairLocalExtremeBandValid(const bool isBuy, const int countdown,
                                        const double sweepRefLevel, string &outDetail)
{
   outDetail = "";
   if(InputEngulfPairLocalExtremeMinOffsetPercentChart == 0.0 &&
      InputEngulfPairLocalExtremeMaxOffsetPercentChart == 0.0)
      return true;

   if(countdown < 1)
   {
      outDetail = "countdown < 1";
      return false;
   }

   if(sweepRefLevel <= 0.0)
   {
      outDetail = "sweep ref level unavailable";
      return false;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   if(barsTotal < countdown + 1)
   {
      outDetail = "insufficient M2 bars";
      return false;
   }

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(1, InputChartRangeBarCount);
   if(chartHeight <= 0.0)
   {
      outDetail = "chart height unavailable";
      return false;
   }

   const double minOffset =
      chartHeight * (InputEngulfPairLocalExtremeMinOffsetPercentChart / 100.0);
   const double maxOffset =
      chartHeight * (InputEngulfPairLocalExtremeMaxOffsetPercentChart / 100.0);
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps = (pointSize > 0.0 ? pointSize : 0.00001);

   double windowHigh = -1.0e100;
   double windowLow  = 1.0e100;
   for(int shift = 1; shift <= countdown; shift++)
   {
      windowHigh = MathMax(windowHigh, iHigh(_Symbol, timeframe, shift));
      windowLow  = MathMin(windowLow, iLow(_Symbol, timeframe, shift));
   }

   if(isBuy)
   {
      const double bandHigh = sweepRefLevel - minOffset;
      const double bandLow  = sweepRefLevel - maxOffset;
      outDetail = StringFormat("windowLow=%.5f sweepRefLow=%.5f band=%.5f..%.5f",
                               windowLow, sweepRefLevel, bandLow, bandHigh);
      return windowLow <= bandHigh + eps && windowLow >= bandLow - eps;
   }

   const double bandLow  = sweepRefLevel + minOffset;
   const double bandHigh = sweepRefLevel + maxOffset;
   outDetail = StringFormat("windowHigh=%.5f sweepRefHigh=%.5f band=%.5f..%.5f",
                            windowHigh, sweepRefLevel, bandLow, bandHigh);
   return windowHigh >= bandLow - eps && windowHigh <= bandHigh + eps;
}

//+------------------------------------------------------------------+
bool V3EngulfVolumeSpikeValid(const int candle1Shift, const int candle2Shift)
{
   const long vol1 = iTickVolume(_Symbol, InputM2NarrativeTimeframe, candle1Shift);
   const long vol2 = iTickVolume(_Symbol, InputM2NarrativeTimeframe, candle2Shift);
   if(vol1 < 0 || vol2 < 0)
      return false;

   const double pairAvg = 0.5 * ((double)vol1 + (double)vol2);
   const double baselineAvg = M2AvgTickVolumeLastBars(candle2Shift, InputEngulfVolAvgBarCount);
   if(baselineAvg <= 0.0)
      return false;

   return pairAvg > baselineAvg;
}

//+------------------------------------------------------------------+
bool V3ValidateM2LegExhaustion(const bool isBuy, string &outDetail)
{
   outDetail = "";
   const bool isBearSetup = !isBuy;
   const int  exhaustLegDir = isBearSetup ? 1 : -1;

   datetime lookbackStart = iTime(_Symbol, InputM2NarrativeTimeframe, InputChartRangeBarCount);
   if(lookbackStart == 0)
   {
      outDetail = "lookback unavailable";
      return false;
   }

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(1, InputChartRangeBarCount);
   if(InputEngulfExhaustionMinLegRangePercentChart > 0.0 && chartHeight <= 0.0)
   {
      outDetail = "chart height unavailable";
      return false;
   }

   const int requiredLegCount = 2;
   long legVolumes[];
   ArrayResize(legVolumes, requiredLegCount);
   int found = 0;

   for(int legIndex = g_m2Swing.swingHistoryCount - 1; legIndex >= 0 && found < requiredLegCount; legIndex--)
   {
      const Swing leg = g_m2Swing.swingHistory[legIndex];
      if(leg.swingDirection != exhaustLegDir)
         continue;
      if(leg.legEndTime == 0 || leg.legStartTime == 0)
         continue;
      if(leg.legEndTime < lookbackStart)
         continue;
      if(!M2SwingLegMeetsExhaustionMinRange(leg, chartHeight))
         continue;
      if(legIndex < 1)
         continue;

      long sumVol = 0;
      if(!M2SumLegTickVolumeFromPrevLegWindow(g_m2Swing.swingHistory[legIndex - 1], leg, sumVol))
         continue;

      legVolumes[found++] = sumVol;
   }

   if(found < 2)
   {
      outDetail = StringFormat("need 2 %s legs w/ vol window found=%d",
                               isBearSetup ? "up" : "down", found);
      return false;
   }

   const long volC = legVolumes[0]; // latest same-dir leg
   const long volB = legVolumes[1]; // prior same-dir leg
   outDetail = StringFormat("volC=%lld volB=%lld", (long)volC, (long)volB);

   return volC > volB;
}

bool V3M2SwingSweepSetupPatternValidCore(const bool isBuy, const double barClose,
                                          double &outStopLoss, datetime &outSignalBarOpen,
                                          double &outRefLevel, int &outCountdown,
                                          string &outExhaustDetail)
{
   outStopLoss = 0.0;
   outSignalBarOpen = 0;
   outRefLevel = 0.0;
   outCountdown = 0;
   outExhaustDetail = "";

   const int countdown = MathMax(1, InputEngulfSweepCountdownBars);
   outCountdown = countdown;

   double refLevel = 0.0;
   double windowSlExtreme = 0.0;
   int    c1Shift = 0;
   int    c2Shift = 0;
   string sweepDetail = "";
   if(!V3DetectM2SwingSweepRejectInCountdown(isBuy, countdown, refLevel, windowSlExtreme,
                                              c1Shift, c2Shift, sweepDetail))
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;

   string localBandDetail = "";
   if(!V3EngulfPairLocalExtremeBandValid(isBuy, countdown, refLevel, localBandDetail))
      return false;

   string exhaustDetail = "";
   if(!V3ValidateM2LegExhaustion(isBuy, exhaustDetail))
      return false;

   const double stopLoss = NormalizeDouble(windowSlExtreme, _Digits);
   if(stopLoss <= 0.0 || (isBuy && stopLoss >= barClose) || (!isBuy && stopLoss <= barClose))
      return false;

   outStopLoss = stopLoss;
   outSignalBarOpen = iTime(_Symbol, timeframe, c2Shift);
   outRefLevel = refLevel;
   outExhaustDetail = exhaustDetail;
   return true;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void V3TryScanM2SwingSweepSetup(const bool isBuy, const double barClose)
{
   double stopLoss = 0.0;
   datetime signalBarOpen = 0;
   double refLevel = 0.0;
   int countdown = 0;
   string exhaustDetail = "";
   if(V3M2SwingSweepSetupPatternValidCore(isBuy, barClose, stopLoss, signalBarOpen,
                                           refLevel, countdown, exhaustDetail))
   {
      const double entryPrice = barClose;
      const double setupScore = CalculateSetupTradeScore(isBuy);

      V2LogHuntEvent(-1, "SWEEP_SIGNAL",
                     StringFormat("%s entry=%.5f sl=%.5f ref=%.5f cd=%d score=%.2f %s bar=%s",
                                  isBuy ? "bull" : "bear", entryPrice, stopLoss, refLevel, countdown,
                                  setupScore, exhaustDetail,
                                  TimeToString(signalBarOpen, TIME_DATE | TIME_MINUTES)));

      if(InputScoreLogWriteCsv)
      {
         LogAllSetupScores(setupScore);
         return;
      }

      if(!SetupScoreAllowsTradeEntry(setupScore))
      {
         V2LogHuntEvent(-1, "SWEEP_SKIP",
                        StringFormat("%s setupScore=%.2f < min %.2f",
                                     isBuy ? "bull" : "bear", setupScore, InputMinScore));
         return;
      }

      TryPlaceEngulfAbsorptionTradeSetup(-1, isBuy, entryPrice, stopLoss,
                                          signalBarOpen, signalBarOpen, setupScore);
      return;
   }

   const int countdownBars = MathMax(1, InputEngulfSweepCountdownBars);

   double windowSlExtreme = 0.0;
   int    c1Shift = 0;
   int    c2Shift = 0;
   string sweepDetail = "";
   if(!V3DetectM2SwingSweepRejectInCountdown(isBuy, countdownBars, refLevel, windowSlExtreme,
                                              c1Shift, c2Shift, sweepDetail))
      return;

   string localBandDetail = "";
   if(!V3EngulfPairLocalExtremeBandValid(isBuy, countdownBars, refLevel, localBandDetail))
   {
      V2LogHuntEvent(-1, "SWEEP_SKIP",
                     StringFormat("%s local extreme band fail — %s",
                                  isBuy ? "bull" : "bear", localBandDetail));
      return;
   }

   if(!V3ValidateM2LegExhaustion(isBuy, exhaustDetail))
   {
      V2LogHuntEvent(-1, "SWEEP_SKIP",
                     StringFormat("%s exhaustion fail — %s",
                                  isBuy ? "bull" : "bear", exhaustDetail));
      return;
   }

   const double slCheck = NormalizeDouble(windowSlExtreme, _Digits);
   if(slCheck <= 0.0 || (isBuy && slCheck >= barClose) || (!isBuy && slCheck <= barClose))
      V2LogHuntEvent(-1, "SWEEP_SKIP",
                     StringFormat("%s SL vs entry invalid", isBuy ? "bull" : "bear"));
}

#ifdef H4_LQ_VOLUME_BREACH_ENABLED
// --- hunt arm on H4 volume breach (disabled v3.04) ---

//+------------------------------------------------------------------+
#endif // H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
#ifdef H4_LQ_VOLUME_BREACH_ENABLED
// --- M2 wick vs breach-record level → hunt arm (disabled v3.04) ---

#endif // H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
bool V3ResolveSetupExtremesForZoneScoring(const bool isBuy, double &outSetupLow, double &outSetupHigh)
{
   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   outSetupLow  = iLow(_Symbol, timeframe, 1);
   outSetupHigh = iHigh(_Symbol, timeframe, 1);
   if(outSetupLow <= 0.0 || outSetupHigh <= 0.0)
      return false;

   const int countdown = MathMax(1, InputEngulfSweepCountdownBars);
   double refLevel = 0.0;
   double windowSlExtreme = 0.0;
   int    c1Shift = 0;
   int    c2Shift = 0;
   string sweepDetail = "";
   if(V3DetectM2SwingSweepRejectInCountdown(isBuy, countdown, refLevel, windowSlExtreme,
                                             c1Shift, c2Shift, sweepDetail)
      && windowSlExtreme > 0.0)
   {
      if(isBuy)
         outSetupLow = windowSlExtreme;
      else
         outSetupHigh = windowSlExtreme;
   }

   return true;
}

//+------------------------------------------------------------------+
double CalculateSetupTradeScore(const bool isBullishTrade)
{
   double setupLow  = 0.0;
   double setupHigh = 0.0;
   V3ResolveSetupExtremesForZoneScoring(isBullishTrade, setupLow, setupHigh);
   return CalculateTotalTradeScore(isBullishTrade, setupLow, setupHigh);
}

//+------------------------------------------------------------------+
void ProcessM2EngulfDirectionOnBarClose(const bool isBuy, const double barClose)
{
   V3TryScanM2SwingSweepSetup(isBuy, barClose);
}

//+------------------------------------------------------------------+
void ProcessHuntEngulfingOnM2BarClose()
{
   if(!InputEnableEngulfHuntAfterH4Breach)
      return;

   const double barClose = iClose(_Symbol, InputM2NarrativeTimeframe, 1);

   ProcessM2EngulfDirectionOnBarClose(true, barClose);
   ProcessM2EngulfDirectionOnBarClose(false, barClose);
}

//+------------------------------------------------------------------+
