//+------------------------------------------------------------------+
//| h4_lq_v3.mq5                                                      |
//| H4 breach hunt + M2 Engulfing Volume Absorption entry model       |
//| v3.125: M15 TP move no longer requires a prior TP hit — moves all open OV_TP legs |
//| v3.124: M15 TP watch arms at entry — bull waits for entry up-leg or first up-leg after entry bear-leg |
//| v3.123: fix M15 leg-close TP move — run on M15 snapshot tick; keep snapshot until modify succeeds |
//| v3.122: midnight hour blackout (00:00-01:00 server) — block entries; close open hunt positions at 00:00 |
//| v3.121: split BOS SL/TP inputs; M15 leg-close TP move (3% below/above closed leg extreme) |
//| v3.120: InputMinScorePercentile extended to P0..P90 (tighter entry gate for large no-SMC trade sets) |
//| v3.119: fast tester mode skips OnDeinit chart-object cleanup (nothing was drawn) |
//| v3.118: fast tester mode gates OnTick on new-M2-bar iTime check (skips intra-bar ticks) |
//| v3.117: write mode emits setup_zone_types.bin; read mode loads bin (weight-slot mask) → 2 active percentiles |
//| v3.116: InputVerifyPermutationScores gates read-mode deinit replay → setup_zone_scores.json |
//| v3.115: OnInit computes P0..P100 in-process from setup_zone_types.json (tester-safe; no .exe spawn) |
//| v3.113: percentile dropdowns + OnInit runs optimize_score_adaptive.exe for thresholds |
//| v3.112: read-mode deinit replays setup_zone_types.json → setup_zone_scores.json |
//| v3.111: write-mode JSON = zoneTypes + mtfBias only; script = percentile lookup per weights |
//| v3.109: RISK_SIZE log includes scoreDenom for manual InputRiskDenomScore verification |
//| v3.108: manual InputMinScoreThreshold + InputRiskDenomScore (no threshold file required) |
//| v3.107: threshold files read from Terminal/Common/Files (tester-compatible) |
//| v3.106: read percentile thresholds from score_adaptive_results.xlsx Thresholds sheet |
//| v3.105: fail OnInit if read-mode thresholds unloadable; block trades when thresholds missing |
//| v3.104: InitScoreThresholds — recompute P0..P100 from setup_zone_types.json when CSV missing/mismatched |
//| v3.103: InputMinScorePercentile (P0/P10/P20/P30) + InputScoreDenominatorPercentile (P80/P90/P100) from score_adaptive_thresholds.csv |
//| v3.102: swing TP risk split follows actual TP count found (1=100%, 2=2:1, 3=3:1:1) |
//| v3.99: InputBaseRiskUsd — fixed account-currency risk per leg budget (was equity %)
//| v3.98: setup JSON includes mtfBias W1/D1/H4/M15 at log time (-1/0/1)
//| v3.97: P/L via positionId bindings at placement; resolved on deinit only
//| v3.96: setup JSON logged immediately; profitLoss added when all legs close
//| v3.95: write mode trades + flat risk; JSON includes profitLoss[] per setup
//| v3.94: write mode logs matching zone types to setup_zone_types.json (no score calc)
//| v3.93: modular split into h4_lq_v3_helpers/*.mqh
//| v3.92: solo fallback fills only remaining TP slots (nearest qualifying levels) |
//| v3.91: merge cluster + solo TPs, sort nearest-first, then assign TP1..TPn |
//| v3.90: InputTradeSwingTpCount — 2 TP (2:1 risk) or 3 TP (3:1:1 risk) + 2R addon |
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
#define H4_LQ_V3_VERSION "3.130"
// Breach record array + hunt arming: uncomment next line to re-enable.
// #define H4_LQ_VOLUME_BREACH_ENABLED
#property copyright ""
#property version   H4_LQ_V3_VERSION
#property description "h4_lq_v3 â€” H4 breach hunt + engulfing volume absorption"

#include <Trade\Trade.mqh>

input group "Tester performance"
input bool   InputFastTesterMode = false; // true: no hunt logs, no chart objects/HUDs (faster backtest)

input group "Midnight hour blackout"
input bool   InputEnableMidnightHourBlackout = true; // 00:00-01:00 server time: block new entries; close open hunt positions once at 00:00

input group "Narrative timeframes"
input ENUM_TIMEFRAMES InputM2NarrativeTimeframe  = PERIOD_M2;  // FVG, hunt, entry management (H4 via MTF SMC)

input bool   InputSwitchChartToH4       = true;

input bool   InputDrawM2SwingLegs        = false; // chart trend lines/labels only; does not disable M2 swing or hunt logic
input color  InputM2SwingLineColor       = clrMediumPurple;
input bool   InputDrawM2SwingAnchorLevel = true;  // realtime horizontal line at M2 leg flip anchor (priceAnchorLevel)
input color  InputM2SwingAnchorColor     = clrYellow;
input int    InputM2SwingWarmupBars      = 500; // 0 = off: replay M2 on attach (plot_swing_h1_m5_copy)
input double InputM2SwingAnchorMultiplier = 0.2; // M2 swing: bar body must exceed N× avg(5 prior bar ranges)

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


#include "h4_lq_v3_helpers/H4LqV3Types.mqh"
#include "h4_lq_v3_helpers/H4LqV3Constants.mqh"

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

enum ENUM_TRADE_SWING_TP_COUNT
{
   TRADE_SWING_TP_TWO   = 2, // 2 swing TPs — risk split 2:1 (+ separate 2R order)
   TRADE_SWING_TP_THREE = 3  // 3 swing TPs — risk split 3:1:1 (+ separate 2R order)
};

input ENUM_TRADE_SWING_TP_COUNT InputTradeSwingTpCount = TRADE_SWING_TP_THREE;
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
input double InputSmcSwingAnchorMultiplier      = 1.0; // MTF swing engine: bar range must exceed N× avg(5 prior bar ranges)

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

enum ENUM_SCORE_PERCENTILE_MIN
{
   SCORE_PERCENTILE_MIN_P0  = 0,   // entry gate: score > P0 of positive setup scores
   SCORE_PERCENTILE_MIN_P10 = 10,  // entry gate: score > P10 of positive setup scores
   SCORE_PERCENTILE_MIN_P20 = 20,  // entry gate: score > P20 of positive setup scores
   SCORE_PERCENTILE_MIN_P30 = 30,  // entry gate: score > P30 of positive setup scores
   SCORE_PERCENTILE_MIN_P40 = 40,  // entry gate: score > P40 of positive setup scores
   SCORE_PERCENTILE_MIN_P50 = 50,  // entry gate: score > P50 of positive setup scores
   SCORE_PERCENTILE_MIN_P60 = 60,  // entry gate: score > P60 of positive setup scores
   SCORE_PERCENTILE_MIN_P70 = 70,  // entry gate: score > P70 of positive setup scores
   SCORE_PERCENTILE_MIN_P80 = 80,  // entry gate: score > P80 of positive setup scores
   SCORE_PERCENTILE_MIN_P90 = 90   // entry gate: score > P90 of positive setup scores
};

enum ENUM_SCORE_PERCENTILE_DENOM
{
   SCORE_PERCENTILE_DENOM_P80  = 80,  // risk sizing denom = P80 of positive scores
   SCORE_PERCENTILE_DENOM_P90  = 90,  // risk sizing denom = P90 of positive scores
   SCORE_PERCENTILE_DENOM_P100 = 100  // risk sizing denom = P100 of positive scores
};

input ENUM_SCORE_PERCENTILE_MIN   InputMinScorePercentile          = SCORE_PERCENTILE_MIN_P30; // entry gate percentile (from optimizer)
input ENUM_SCORE_PERCENTILE_DENOM InputScoreDenominatorPercentile  = SCORE_PERCENTILE_DENOM_P80; // risk denom percentile (from optimizer)
input double InputBaseRiskUsd                  = 100.0; // fixed risk per swing-TP budget (account ccy); scaled by |score|/denom

input group "Optimization score logging"
input bool   InputScoreLogWriteCsv             = false; // true=log setup_zone_types.json (zones+bias); false=read-mode trading
input bool   InputVerifyPermutationScores      = false; // read-mode only: on deinit, replay setup_zone_types.json → setup_zone_scores.json

input group "Timeframe Alignment Weights"
input int    InputWeight_W1_BOS                = 16;
input int    InputWeight_D1_BOS                = 8;
input int    InputWeight_H4_BOS                = 4;
input int    InputWeight_M15_BOS               = 2;

#define InputTouchVolSlBufferPercentChart    InputEngulfSlBufferPercentChart
#define InputTouchVolMinSlPoints             InputEngulfMinSlPoints

input group "BOS SL/TP management"
input bool   InputEnableBosMoveSl                  = false; // tiered SL: TP1 hit→BE, TP1+TP2 hit→structural (M2 BOS+FVG)
input bool   InputEnableBosMoveTp                  = false; // M15 leg close: move remaining swing-TP legs to offset from leg extreme
input double InputBosMoveTpM15OffsetPercentChart   = 3.0;  // bull: TP = M15 up-leg high − N% M15 chart height; bear: low + N%

CTrade         g_trade;

ProfessionalBiasOverrideState g_profBiasOverrideW1;
ProfessionalBiasOverrideState g_profBiasOverrideD1;
ProfessionalBiasOverrideState g_profBiasOverrideH4;
ProfessionalBiasOverrideState g_profBiasOverrideM15;

#ifdef H4_LQ_VOLUME_BREACH_ENABLED
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
M15ClosedLegSnapshot g_m15ClosedLegForTpMgmt;
datetime             g_lastM15TpMgmtAppliedLegEndTime = 0;
int                  g_huntM15TpEntryLegDirection     = 0;
datetime             g_huntM15TpEntryLegStartTime     = 0;
bool                 g_huntM15TpWatchArmed            = false;
datetime             g_lastMidnightBlackoutCloseDay    = 0;
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

#include "h4_lq_v3_helpers/H4LqV3All.mqh"

int OnInit()
{
   if(InputScoreLogWriteCsv)
      ScoreLogResetBuffer();
   else if(!InitScoreThresholds())
   {
      Print("Score thresholds: init failed — trades blocked until setup_zone_types.bin (or .json) is available in MQL5/Files.");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InputEnableEngulfHuntAfterH4Breach && InputScoreLogWriteCsv)
      FlushSetupZoneTypesJsonToFile();
   else if(!InputScoreLogWriteCsv && InputVerifyPermutationScores)
      ScoreLogWriteVerifyScoresFromSetupJson();

   // Fast tester mode never draws chart objects, so there is nothing to clean up.
   if(!InputFastTesterMode)
   {
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
   }

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
   ProcessMidnightHourBlackout();

   const datetime tM2 = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   const bool newM2Bar = (tM2 != g_lastM2BarOpen);

   // Fast tester mode: skip every intra-bar tick. The EA only acts on the M2
   // bar close, chart/HUD work is already off, and W1/D1/H4 boundaries align to
   // M2 (M15 boundaries resolve on the next M2 close). One iTime compare/tick.
   if(InputFastTesterMode && !newM2Bar)
      return;

   UpdateMTFSwings();
   ProcessHuntM15LegCloseTpIfReady();
   if(H4LqChartDrawEnabled())
   {
      UpdateM2SwingAnchorVisualRealtime(g_m2Swing);
      UpdateM2LiveSwingLegVisualOnTick();
   }

   if(newM2Bar)
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
