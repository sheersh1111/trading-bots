//+------------------------------------------------------------------+
//| h4_lq_v2.mq5                                                      |
//| H4 primary narrative + configurable secondary TF — liquidity hunt v2 |
//| v2.94: touch vol — if max-vol before 1st FVG pattern bar, pick bar from FVG 3-bar window (touch vol entry/SL) |
//| v2.93: touch vol entry — if max-vol bar before 1st FVG bar, use 1st FVG bar for order |
//| v2.92: InputTouchVolRequireAscendingVolume — toggle touch ascending vol validation |
//| v2.91: TOUCH_GATE_ON only via verified recalc-buffer overlap (matches chart zone) |
//| v2.90: remove TOUCH_GATE_OFF on same-dir M2 leg close before touch hit |
//| v2.89: remove swing-group hunt OFF cancel (v2.84) — no HUNT_OFF on group hit |
//| v2.88: remove hunt-off horizontal line + leg-close swing group recalc (v2.86/v2.87) |
//| v2.87: hunt-off group pick — nearest by price + time (not price-only); lookback logged |
//| v2.86: hunt-off horizontal line — swing group level on opposite/recalc-buffer leg close |
//| v2.85: touch vol w/o FVG — gate OFF + no order; hunt stays ON |
//| v2.84: hunt OFF on nearest swing low/high group hit; remove touch-vol FVG abort gate |
//| v2.83: restore touch vol FVG gate — at least one FVG in session required |
//| v2.82: revert v2.56 M2 anchor (midpoint) + v2.58 touch-vol FVG gate |
//| v2.81: touch vol SL — widest extreme across full touch vol window (not vol bar + 2 only) |
//| v2.79: HUNT_OFF log with reason on every V2EndOppositeFvgHuntSession call |
//| v2.78: touch vol entry — buy low+ / sell high− offset; always limit at vol bar (no market promote) |
//| v2.77: touch vol — 0% entry offset / 0% SL buffer allowed (SL at ref extreme, no inset) |
//| v2.76: touch vol — InputTouchVolEntryOffsetPercentChart + InputTouchVolMinSlPoints widen SL |
//| v2.75: touch vol entry — buy hunt high−3% rng / sell hunt low+3% rng (FVG-side geometry) |
//| v2.74: touch vol entry — bull low+ / bear high− 3% chart rng; flip anchor if offset overshoots bar |
//| v2.73: touch vol entry — restore 3% InputChartRangeBarCount height; SL still vol bar + 2 older |
//| v2.72: touch vol SL — widest extreme across vol bar + 2 older bars (was 1 older) |
//| v2.71: touch vol entry 3% — selected bar height (not InputChartRangeBarCount); bull low+ / bear high− |
//| v2.70: touch vol entry — bull low+3% / bear high−3% chart height; prefer massive vol leap bar (≥45) |
//| v2.55: InputFastTesterMode — master off switch for hunt logs + all chart objects/HUDs |
//| v2.54: touch vol SL — wider of max-vol bar vs prior bar extreme, then ±2% chart height |
//| v2.53: touch vol SL — max-vol bar extreme ± 2% chart height (was 1% via shared buffer) |
//| v2.52: touch vol validated — entry/SL from max-vol M2 bar (excl oldest), not FVG |
//| v2.51: revert v2.50 recalc buffer band geometry |
//| v2.49: touch recalc — buffer cross/break counts as hit; allow recalc at hunt extreme buffer |
//| v2.48: M2 touch — H4-style vol window on opposite active leg; invalidate touch if vol pattern fails |
//| v2.47: remove H4_DECENT_MOV debug log; restore hunt/BOS Print logging |
//| v2.46: breach window end fallback when new leg has no decent bar yet (shift+2..shift from last closed) |
//| v2.45: breach window start — same shift+2 bound as window end (completed-leg last decent) |
//| v2.44: breach window end — decent lookup 1 bar older; scan end 2 bars before last decent (new-bar indexing) |
//| v2.43: silence hunt/BOS logs; log H4 same-dir decent movement on each realtime H4 bar close |
//| v2.42: breach vol window — exact shift bounds [last decent completed, last decent active] both inclusive |
//| v2.41: breach vol window half-open [last decent completed, last decent active) via datetime bounds |
//| v2.40: breach vol window start — inclusive last decent on last completed leg; never exclude window-start bar |
//| v2.39: breach vol window — start at opposite-leg last decent bar; end before active-leg last decent bar |
//| v2.38: warmup keeps full H4 swing replay; only breach cache + chart rays cleared after warmup |
//| v2.37: volume breach pink/green — realtime only; breach memory/chart wiped post-warmup on attach |
//| v2.36: leg-close includes flip bar for breach (pink high); new leg skips transition bar + <2 bars |
//| v2.35: active-leg vol breach — opposite-leg 2nd-last start; window end uses closed H4 bar shift |
//| v2.34: H4 volume breach rays — OBJPROP_ZORDER 128 so lines draw above other chart objects |
//| v2.24: max-vol breach level tracks live on active H4 leg (prev 2nd-last → active 2nd-last) |
//| v2.23: swept breach = H4 price below up level / above down level after vol-bar formation |
//| v2.22: warmup uses volume breach cache + level memory; rescans after each H4 rebuild |
//| v2.21: remember swept H4 volume breach levels (price + direction), not leg id only |
//| v2.20: H4 up-leg volume breach ray — green (down leg stays deep pink) |
//| v2.19: H4 up-leg volume breach ray — purple (down leg stays deep pink) |
//| v2.18: H4 breach hunt same-dir FVG — up leg→bull, down leg→bear (was opposite) |
//| v2.17: H4 volume breach marker — horizontal ray at level from max-vol bar (not pink vline) |
//| v2.16: remove H4BreachLegIsWithinM2ChartRange — H4 buffer window + wick cross is enough |
//| v2.15: hunt activates volume breach records within InputH4BreachBufferChartBarCount H4 bars |
//| v2.14: H4 breach level = max-vol bar low/high in leg window + vertical marker |
//| v2.13: thinner H4/M2 swing leg trend lines (width 1) |
//| v2.12: impulse cancel uses H4_BREACH_BUFFER_PERCENT_FAR + 36-bar H4 height (not M2 %) |
//| v2.11: warmup marks already-breached last-N H4 leg highs/lows from M2 history |
//| v2.10: H4 breach buffer — high: 2% below..10% above; low: 2% above..10% below |
//| v2.09: H4 breach buffer fixed −2%..10% via constants (no percent inputs) |
//| v2.08: H4 breach buffer % as int tenths (−20..100) — MT5 inputs cannot be negative double |
//| v2.07: H4 breach buffer −2%..10% of 36-bar H4 chart height (was M2 chart range) |
//| v2.06: rename M15 narrative identifiers to H4 (InputH4NarrativeTimeframe default PERIOD_H4)
//| v2.05: InputH4HuntBreachLastCompletedLegs — hunt only on last N HTF completed leg highs/lows |
//| v2.04: InputDrawTradeSwingGroupTpZones — toggle swing high/low group + TP line chart draw |
//| v2.03: fix swing-group TP replay after 20-leg history cap (orders without M2 draw) |
//| v2.02: InputDrawM2SwingLegs = chart only; M2 swing/hunt/trade logic always runs |
//| v2.01: touch-recalc buffer tracks active same-dir leg; resumes on enter/cross only |
//| v2.00: fork from h4_lq v1.27 — swing-group TP/proximity zones, H4 BOS HUD decouple |
//+------------------------------------------------------------------+
#define H4_LQ_V2_VERSION "2.94"
#property copyright ""
#property version   H4_LQ_V2_VERSION
#property description "h4_lq_v2 — configurable narrative TFs, H4 breach hunt + opposite FVG"

#include <Trade\Trade.mqh>

input group "Tester performance"
input bool   InputFastTesterMode = false; // true: no hunt logs, no chart objects/HUDs (faster backtest)

input group "Narrative timeframes"
input ENUM_TIMEFRAMES InputH4NarrativeTimeframe = PERIOD_H4; // primary: breach legs, BOS, liquidity pivots
input ENUM_TIMEFRAMES InputM2NarrativeTimeframe  = PERIOD_M2;  // secondary: FVG, hunt, entry management

input bool   InputSwitchChartToH4       = true;
input int    InputWarmupBars             = 500;  // 0 = off: replay closed H4 bars on attach
input bool   InputDrawH4SwingLegVisuals = true;
input color  InputH4SwingTrendLineColor = clrGold;

input bool   InputDrawM2SwingLegs        = false; // chart trend lines/labels only; does not disable M2 swing or hunt logic
input color  InputM2SwingLineColor       = clrMediumPurple;
input bool   InputDrawM2SwingAnchorLevel = true;  // realtime horizontal line at M2 leg flip anchor (priceAnchorLevel)
input color  InputM2SwingAnchorColor     = clrYellow;
input int    InputM2SwingWarmupBars      = 500; // 0 = off: replay M2 on attach (plot_swing_h1_m5_copy)

input group "H4 breach → opposite M2 FVG (plot_swing_m2_copy)"
input bool   InputEnableOppositeFvgHuntAfterH4Breach = true;
input bool   InputEndHuntOnOppositeH4LegBeforeTouch = true; // on: hunt OFF if touch line set but price never hit it when opposite H4 leg closes (no orders)
input bool   InputDrawBosOppositeFairValueGapZones   = true;
input int    InputH4BreachBufferChartBarCount = 74; // H4 bars: buffer reference height + active volume breach records
input int    InputH4LiquidityPivotLookbackBars = 1166; // replay lookback for liquidity pivot rebuild (chart/analysis)
input double InputHuntTouchRecalcPercentBeforeSameDirExtreme = 1.0; // hunt ON: within N% M2 chart of hunt same-dir extreme → recalc touch
input bool   InputDrawHuntTouchRecalcBufferZone = true;  // hollow rect: N% M2 chart band at hunt same-dir high/low
input color  InputHuntTouchRecalcBufferColor    = clrDeepSkyBlue;
input bool   InputDrawImpulseCancelBufferZone = true;  // hollow rect while hunt ON
input color  InputImpulseCancelBufferColor    = clrDarkOrange;
input int    InputChartRangeBarCount     = 147;
input double InputFairValueGapMinimumPercentOfChartRange = 1.0; // min FVG gap = N% of M2 chart height (0=off)
input int    InputMaximumFairValueGapRectangles = 120;
input bool   InputShowLiquidityHuntHud   = true;
input bool   InputLogHuntEvents          = true;  // Experts tab: hunt / FVG / BOS

input group "H4 BOS trade direction bias"
input bool   InputEnableH4BosTradeDirectionBias = true;  // trade with last H4 close-cross BOS (bull/bear)
input bool   InputShowH4BosBiasHud              = true;  // top-right ↑ green / ↓ red (plot_swing_m2 style)

const double H4_BREACH_ANCHOR_MULTIPLIER = 0.2; // wick+body vs prior 5-bar avg — breaches / hunt / liquidity pivots
const double M2_SWING_ANCHOR_MULTIPLIER  = 1.0; // M2 body vs prior 5-bar avg (plot_swing_h1_m5_copy)
const double M2_TOUCH_VOLUME_MIN_EXPAND_RATIO = 3.0; // touch window: max & touch bar vs window min tick vol
const int    M2_TOUCH_VOLUME_MIN_INCREASE_EVENTS = 2; // bar-over-bar vol increases required when window >= 4 bars
const double H4_BOS_ANCHOR_MULTIPLIER    = 1.0; // full bar range vs prior 5-bar avg — BOS only (plot_swing_h4)
const double H4_BREACH_BUFFER_PERCENT_NEAR = 0.0;  // below high / above low
const double H4_BREACH_BUFFER_PERCENT_FAR  = 10.0; // above high / below low

input group "FVG trade (M2 opposite FVG)"
input bool   InputEnableAutomatedTrading = true;   // false = log trade plan only (no orders)
input double InputFvgTradeMinTickVolumePercentOfM2Avg = 50.0; // 0=off; formation bar tick vol vs prior M2 bars
input int    InputFvgTradeTickVolumeAvgM2BarCount     = 30;   // bars after formation (older) for average
input bool   InputDrawTradeSwingGroupTpZones   = true; // chart only: swing high/low group rects + TP lines on order
input int    InputTradeSwingLookbackM2Bars     = 292;  // M2 bars scanned for swing highs (bull) / lows (bear)
input double InputTradeSwingProximityPercentOfChartRange = 10.0; // cluster + buffer band = N% of M2 chart height
input color  InputTradeSwingProximityRectColorBull = clrLimeGreen;
input color  InputTradeSwingProximityLineColorBull = clrLimeGreen;
input color  InputTradeSwingProximityRectColorBear = clrCrimson;
input color  InputTradeSwingProximityLineColorBear = clrCrimson;
input double InputTradeSwingTpMinRewardToRisk = 2.0; // skip line/TP when reward:risk below this (1:2 = 2.0)
input double InputTouchVolEntryOffsetPercentChart = 3.0; // buy: high−N% rng; sell: low+N% rng; 0=exact bar extreme
input double InputTouchVolSlBufferPercentChart    = 2.0; // SL beyond ref extreme; 0=SL at ref extreme (no buffer)
input int    InputTouchVolMinSlPoints           = 0;     // min entry–SL pts; 0=broker stops level only when widening SL
input bool   InputTouchVolRequireAscendingVolume  = true;  // touch hit: require ascending tick-vol pattern in leg window

input group "BOS SL/TP management"
input bool   InputEnableBosMoveSlAndTp = false; // disable trailing/moving SL & TP on BOS for now

const string H4_LQ_LOG_PREFIX = "h4_lq_v2";

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

// --- hard-coded trade sizing (per FVG setup = 3 OV orders) ---
const double   LQ_RISK_USD_PER_TRADE              = 50.0;
const ulong    LQ_EXPERT_MAGIC                    = 940029;
const double   LQ_STOP_BUFFER_PERCENT_CHART       = 1.0;
const long     LQ_TOUCH_VOL_MASSIVE_LEAP_MIN          = 45;
const int      LQ_TOUCH_VOL_SL_OLDER_BAR_LOOKBACK     = 2;
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

#define LiquidityPoolCapacity 32

const string ChartObjectNamePrefixH4SwingTrendLine = "LQ2_H4_Swing_";
const string ChartObjectNamePrefixH4SwingLabelText = "LQ2_H4_SWLBL_";
const string ChartObjectNamePrefixH4VolumeBreachRay = "LQ2_H4_VOL_BREACH_";
const color  H4_VOLUME_BREACH_RAY_COLOR_UP   = clrGreen;
const color  H4_VOLUME_BREACH_RAY_COLOR_DOWN = clrDeepPink;
const int    H4_VOLUME_BREACH_RAY_ZORDER     = 128;
const string PFX_M2_TREND  = "LQ2_M2_TR_";
const string PFX_M2_LBL    = "LQ2_M2_LB_";
const string PFX_M2_ANCHOR = "LQ2_M2_AN_";
const string LQ_OBJ_PREFIX_FVG_RECT = "LQ2_M2_FVG_";
const string LQ_OBJ_PREFIX_FVG_LBL  = "LQ2_M2_FVGT_";
const string LQ_OBJ_HUNT_HUD        = "LQ2_HUNT_HUD";
const string LQ_OBJ_H4_BIAS_HUD    = "LQ4_H4_BIAS";
const string LQ_OBJ_IMPULSE_BUFFER  = "LQ2_IMPULSE_BUF";
const string LQ_OBJ_TOUCH_POINT     = "LQ2_TOUCH_PT";
const string LQ_OBJ_IMPULSE_PREFIX      = "LQ2_IMPULSE_BUF_";
const string LQ_OBJ_TOUCH_RECALC_PREFIX = "LQ2_TRECALC_BUF_";
const string LQ_OBJ_TRADE_SWGRP_RECT_PREFIX = "LQ2_TRD_SWG_R_";
const string LQ_OBJ_TRADE_SWGRP_LINE_PREFIX = "LQ2_TRD_SWG_L_";

#define V2_MAX_HUNT_SESSIONS              2   // at most one high-breach + one low-breach hunt
#define V2_HUNT_FVG_MEM_CAPACITY          16

struct V2HuntFvgMemory
{
   bool     isBullishFairValueGap;
   double   fairValueGapZoneLowPrice;
   double   fairValueGapZoneHighPrice;
   datetime fairValueGapBarOpenTime;
};

struct V2HuntSession
{
   bool     active;
   bool     h4HighWasBreached;
   double   h4BreachedLegLevelPrice;
   datetime h4BreachedLegEndTime;
   double   closeWhenH4LiquidityBreached;
   double   pathMinLowSinceH4Breach;
   double   pathMaxHighSinceH4Breach;
   double   sameDirExtremeAtLastTouchRecalc; // path high/low snapshot at last V2_TOUCH_RECALC
   double   touchRecalcBufferAnchor;         // tracks active same-dir M2 leg extreme while leg is open
   bool     touchRecalcBufferTrackActiveLeg;
   bool     touchRecalcBufferResumeAfterCross; // armed when price enters/crosses frozen buffer; resume on next same-dir leg
   double   impulseCloseExtremeSinceH4Breach;
   datetime sessionId;
   int      oppositeFvgFoundCount;
   double   touchLevel;
   bool     touchLevelReady;
   bool     postTouchFvgGateOpen;  // false after touch w/o FVG / vol fail; reopens on recalc buffer hit only
   bool     touchHitVolumeRejectLatch; // set on TOUCH_GATE_OFF vol fail; cleared on touch recalc
   datetime touchRecalcSkippedBarOpenTime; // bar when TOUCH_RECALC_SKIP; FVG next bar → trade + hunt OFF
   bool     pendingTradeFvgValid;
   bool     pendingTradeIsBullishFvg;
   double   pendingTradeZoneLow;
   double   pendingTradeZoneHigh;
   datetime pendingTradeFormationTime;
   V2HuntFvgMemory fvgMem[V2_HUNT_FVG_MEM_CAPACITY];
   int      fvgMemCount;
   int      fvgRectSequence;
   bool     tradeOrdersActive;
   datetime ordersFvgFormationTime;
   bool     tradeIsBuy;
   double   tradeEntryPrice;
   double   tradeTp1Price;
   double   preEntryCancelTpLevel;
   bool     firstOppBosMgmtDone;
};

#define BosOppositeFairValueGapMemoryCapacity 32
#define H4LegLiquidityBreachMemoryCapacity   24

struct H4LegLiquidityBreachRecord
{
   datetime legEndTime;
   int      swingDirection;
   double   breachLevelPrice;
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

#define H4_LEG_VOLUME_BREACH_CAPACITY 24

struct H4LegVolumeBreachRecord
{
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection;
   double   breachLevelPrice;
   datetime volumeBarOpenTime;
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

SwingState     g_h4Swing;     // anchor 0.5 — breaches, chart legs, liquidity pivots
SwingState     g_h4BosSwing;  // anchor 1.0 — BOS close-cross levels only (no visuals)
SwingState     g_m2Swing;
LiquidityPool  g_liquidityPools[LiquidityPoolCapacity];
int            g_liquidityPoolCount = 0;

datetime g_lastH4BarOpen = 0;
datetime g_lastM2BarOpen  = 0;

V2HuntSession g_v2Hunts[V2_MAX_HUNT_SESSIONS];

H4LegLiquidityBreachRecord g_h4LegLiquidityBreaches[H4LegLiquidityBreachMemoryCapacity];
int                         g_h4LegLiquidityBreachCount = 0;

H4LiquidityPivot g_h4DescHighPivots[H4_LIQUIDITY_PIVOT_CAPACITY];
int               g_h4DescHighPivotCount = 0;
H4LiquidityPivot g_h4AscLowPivots[H4_LIQUIDITY_PIVOT_CAPACITY];
int               g_h4AscLowPivotCount = 0;

#define H4_BOS_RECORDED_LEG_CAPACITY 32

struct H4BosRecord
{
   int      direction;   // 1 = bull BOS, -1 = bear BOS
   datetime barOpenTime;
   datetime legEndTime;  // completed H4 leg that was broken (dedupe key)
   double   brokenLevel;
};

struct H4BosRecordedLeg
{
   int      direction;
   datetime legEndTime;
};

struct H4BosPendingConfirm
{
   bool     active;
   int      direction;        // 1 bull / -1 bear
   double   brokenLevel;
   datetime legEndTime;
   datetime breakBarOpenTime; // H4 bar that closed through the level (await 1 more close)
};

H4BosPendingConfirm g_h4BosPendingConfirm;
H4BosRecord        g_h4LastBosRecord;
bool                g_h4LastBosRecordValid     = false;
H4BosRecordedLeg   g_h4BosRecordedLegs[H4_BOS_RECORDED_LEG_CAPACITY];
int                 g_h4BosRecordedLegCount    = 0;
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

void   PushLiquidityPoolFromClosedSwing(const double poolLowPrice, const double poolHighPrice,
                                        const bool isSupplyPool);
void   SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                     const double highPrice, const double lowPrice, const int lastClosedBarShift = 1);
void   SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice);
void   DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                         const double labelPrice, const bool isUplegSwingDirection, const int keyLevelIdForLabel);
void   SwingCloseH4Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                            const int lastClosedBarShift = 1);
void   ProcessH4SwingStep(const int lastClosedBarShift = 1);
void   ProcessH4BosSwingStep(const int lastClosedBarShift = 1);
void   SwingCloseH4ToHistory(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                              const int lastClosedBarShift = 1);
void   WarmupH4SwingFromHistory();

void   SwingCloseM2Leg(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                       const string chartObjectNamePrefix, const string labelPrefix,
                       const int lastClosedBarShift = 1);
void   UpdateM2LiveSwingLegVisualIf(const SwingState &swingState, const ENUM_TIMEFRAMES timeframe);
void   UpdateM2LiveSwingLegVisualOnTick();
void   UpdateM2SwingAnchorVisualRealtime(const SwingState &swingState);
void   ProcessSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int sh,
                               const color swingLineColor, const string trendPrefix, const string labelPrefix,
                               const bool replayOnly = false);
bool   CollectM2SwingExtremesBackwardFromFormation(const datetime formationTime, const int lookbackBars,
                                                    const int legDirection,
                                                    M2SwingExtremePoint &outPoints[], int &outPointCount);
bool   BuildTradeSwingGroupTakeProfits(const bool isBullishTrade, const datetime formationTime,
                                       const double entryPrice, const double stopLossPrice,
                                       double &outTakeProfitPrices[], int &outTakeProfitCount);
void   ProcessM2SwingStep();
void   WarmupM2SwingFromHistory();
void   UpdateH4LegLiquidityBreachMemoryOnM2Bar();
bool   WasH4VolumeBreachLevelViolatedSinceFormation(const int swingDirection,
                                                      const double breachLevel,
                                                      const datetime levelFormedOpenTime,
                                                      const double pointSize);

void   RefreshLiquidityHuntHud();
double ReferenceChartHeightForFairValueGapFilterM2();
bool   FairValueGapGapMeetsMinimumPercentOfRangeM2(const double zoneLowPrice, const double zoneHighPrice,
                                                   double &outGapSize, double &outChartHeight,
                                                   double &outMinGapRequired);
bool   TryDetectFairValueGapPatternOnLastClosedBarM2(bool &isBullishFairValueGap,
                                                      double &fairValueGapZoneLowPrice,
                                                      double &fairValueGapZoneHighPrice);
bool   DetectFairValueGapOnLastClosedBarM2(bool &isBullishFairValueGap, double &fairValueGapZoneLowPrice,
                                         double &fairValueGapZoneHighPrice);
bool   TryLatestH4CompletedUpLegHigh(double &outHigh);
bool   TryLatestH4CompletedDownLegLow(double &outLow);
bool   TrySecondLastH4CompletedUpLegHigh(double &outHigh);
bool   TrySecondLastH4CompletedDownLegLow(double &outLow);
bool   TryNthH4CompletedSwingLeg(const int swingDirection, const int nFromLatest,
                                  double &outLegHigh, double &outLegLow, datetime &outLegEndTime);
bool   H4VolumeBreachLevelsMatch(const double levelA, const double levelB);
bool   IsH4VolumeBreachLevelAlreadyBreached(const int swingDirection, const double breachLevel);
void   RememberH4VolumeBreachLevelSwept(const datetime legEndTime, const int swingDirection,
                                          const double breachLevel);
bool   TryGetH4LegBarOpenTimeFromEnd(const datetime legStartTime, const datetime legEndTime,
                                      const int nFromEnd, datetime &outBarOpenTime);
bool   FindMaxVolumeH4BarBetweenOpenTimes(const datetime rangeStartOpen, const datetime rangeEndOpen,
                                             datetime &outBarOpenTime, long &outMaxVolume);
double H4BreachLevelPriceFromVolumeBar(const int swingDirection, const int h4BarShift);
bool   H4BarHasDecentMovementForLegDirection(const int barShift, const int legSwingDirection);
bool   H4TryGetLegLastDecentMovementBarOpen(const datetime legStartTime, const datetime legProgressEnd,
                                              const int swingDirection, datetime &outBarOpenTime);
datetime H4ProgressEndOpenForDecentLookup(const datetime legProgressEndOpen);
bool   H4TryGetVolumeBreachWindowBoundFromLastDecent(const datetime legStartTime,
                                                      const datetime legProgressEnd,
                                                      const int swingDirection,
                                                      datetime &outBoundInclusiveOpen);
bool   H4TryGetLegVolumeBreachWindowStartForScan(const datetime legStartTime,
                                                  const datetime legProgressEnd,
                                                  const int swingDirection,
                                                  datetime &outWindowStartInclusiveOpen);
bool   H4TryGetLegVolumeBreachWindowEndForScan(const datetime legStartTime,
                                                const datetime legProgressEnd,
                                                const int swingDirection,
                                                datetime &outWindowEndInclusiveOpen);
bool   H4VolumeBreachWindowShiftRangeValid(const datetime windowStartInclusive,
                                            const datetime windowEndInclusive);
bool   H4TryResolveLegVolumeBreachWindowEnd(const datetime legStartTime,
                                             const datetime legProgressEnd,
                                             const int swingDirection,
                                             const datetime windowStartInclusive,
                                             const int lastClosedBarShift,
                                             datetime &outWindowEndInclusiveOpen);
void   H4ScanVolumeWindowMonotonic(const int swingDirection, const datetime windowStartInclusive,
                                    const datetime windowEndInclusive, long &inOutMaxVolume,
                                    datetime &inOutMaxBarOpenTime, double &inOutBreachLevel);
bool   ComputeH4LegVolumeBreachLevel(const Swing &lastLeg, const Swing &prevLeg, const bool hasPrevLeg,
                                       double &outBreachLevel, datetime &outVolumeBarOpenTime);
void   H4ResetActiveLegVolumeBreachTrack();
bool   TryGetH4VolumeBreachWindowStartFromLastCompletedLeg(const SwingState &swingState,
                                                              datetime &outWindowStartOpen);
void   H4OnH4ActiveLegStarted(SwingState &swingState, const int lastClosedBarShift = 1);
void   H4OnH4ActiveLegBarClosed(SwingState &swingState, const int lastClosedBarShift = 1);
void   H4FinalizeActiveLegVolumeBreach(const Swing &closedLeg);
void   H4PurgeStaleActiveLegVolumeBreachRecords(const datetime keepLegStartTime);
void   H4RestoreActiveLegVolumeBreachTrackFromSwing();
void   RememberH4LegVolumeBreachRecord(const datetime legStartTime, const datetime legEndTime,
                                        const int swingDirection, const double breachLevel,
                                        const datetime volumeBarOpenTime);
bool   TryGetH4LegVolumeBreachLevel(const datetime legEndTime, const int swingDirection,
                                     double &outBreachLevel, datetime &outVolumeBarOpenTime);
bool   TryResolveH4LegVolumeBreachLevel(const datetime legStartTime, const datetime legEndTime,
                                          const int swingDirection, double &outBreachLevel,
                                          datetime &outVolumeBarOpenTime);
bool   IsH4BarWithinBreachBufferChartWindow(const datetime barOpenTime);
bool   IsH4LegVolumeBreachActiveInBufferWindow(const datetime legEndTime, const int swingDirection);
void   RebuildH4LegVolumeBreachLevelsFromSwingHistory();
void   H4ClearVolumeBreachMemoryAndChart();
void   DeleteH4VolumeBreachLevelRay(const datetime legStartTime);
void   DrawH4VolumeBreachLevelRay(const datetime legStartTime, const datetime legEndTime,
                                   const int swingDirection, const datetime volumeBarOpenTime,
                                   const double breachLevel);
void   RebuildAllH4VolumeBreachMarkers();
void   RebuildH4LiquidityPivotLevels();
bool   TryDetectH4BosCrossOnBar(const int h4BarShift, int &outDirection,
                                 double &outBrokenLevel, datetime &outBarOpenTime,
                                 datetime &outLegEndTime);
void   ProcessH4BosOnH4Close(const int h4BarShift);
void   ClearH4BosPendingConfirm();
bool   H4BosCloseHoldsBeyondLevel(const int direction, const int h4BarShift, const double brokenLevel);
void   TryConfirmH4BosPendingOnBarClose(const int h4BarShift);
void   RecordH4BosBreak(const int direction, const datetime barOpenTime, const datetime legEndTime,
                         const double brokenLevel);
bool   H4BosAlreadyRecordedForLeg(const int direction, const datetime legEndTime);
void   ResetH4BosBiasState();
double ReferenceChartHeightForM2BarCount(const int barCount);
double ReferenceChartHeightForM2BarCountFromShift(const int newestBarShift, const int barCount);
double ReferenceChartHeightForH4BarCount(const int barCount);
double ReferenceChartHeightForH4BreachBuffer();
void   H4BreachBufferBandForUpLegHigh(const double legHigh, double &outBandLow, double &outBandHigh);
void   H4BreachBufferBandForDownLegLow(const double legLow, double &outBandLow, double &outBandHigh);
bool   H4BreachImpulseCancelZonePrices(const bool expectBullishFvgHunt, const double breachLevel,
                                        double &outZoneLow, double &outZoneHigh,
                                        double &outCancelLimitPrice);
bool   M2WickCrossesIntoH4UpBreachBuffer(const double bandLow, const double bandHigh,
                                           const double barHigh, const double prevHigh,
                                           const double pointSize);
bool   M2WickCrossesIntoH4DownBreachBuffer(const double bandLow, const double bandHigh,
                                              const double barLow, const double prevLow,
                                              const double pointSize);
int    GetH4TradeDirectionBias(); // 1 bull, -1 bear, 0 undefined/mixed/disabled-filter
void   LogH4TradeDirectionBiasIfChanged();
bool   FvgTradeAllowedByH4BosBias(const bool isBullishFairValueGap, string &outBlockReason);
void   RefreshH4BosBiasHud();
bool   M2WickCrossesAboveLevel(const double level, const double barHigh, const double prevHigh,
                               const double pointSize);
bool   M2WickCrossesBelowLevel(const double level, const double barLow, const double prevLow,
                               const double pointSize);
bool   TryAcceptH4BreachForHunt(const bool h4HighBreached, const double breachLevel,
                                const datetime legEnd, double &outLevel, bool &outHighBreached,
                                datetime &outLegEndTime);
bool   TryDetectM2BreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap, double &outBosLegLevelPrice);
void   V2InitHuntSlot(const int huntIndex);
void   V2InitAllHuntSlots();
int    V2CountActiveHunts();
int    V2AllocHuntSlot();
int    V2FindActiveHuntByH4Leg(const datetime legEndTime, const bool h4HighBreached);
int    V2FindActiveHuntByBreachPolarity(const bool h4HighBreached);
void   V2AbortHuntSessionForRestart(const int huntIndex);
int    V2FindHuntSlotBySessionId(const datetime sessionId);
string V2HuntObjectSuffix(const datetime sessionId);
string V2HuntTradeCommentPrefix(const datetime sessionId);
void   V2LogHuntEvent(const int huntIndex, const string eventName, const string detail = "");
bool   V2PushHuntFvgMemory(const int huntIndex, const bool isBullishFairValueGap,
                           const double zoneLowPrice, const double zoneHighPrice,
                           const datetime fairValueGapBarOpenTime);
void   V2DrawHuntFairValueGapZone(const int huntIndex, const bool isBullishFairValueGap,
                                  const double zoneLowPrice, const double zoneHighPrice,
                                  const datetime leftBarTime, const datetime rightBarTime);
void   ProcessBosOppositeFairValueGapWindow();
void   V2ProcessOneActiveHuntOnM2Bar(const int huntIndex, const double pointSize,
                                     const double barClose, const double barHigh, const double barLow,
                                     const double prevHigh, const double prevLow);
int    V2OppositeM2LegDirectionForHunt(const int huntIndex);
bool   V2HuntExpectsBullishFvg(const int huntIndex);
bool   V2FvgPolarityMatchesHunt(const int huntIndex, const bool isBullishFairValueGap);
void   V2ResetHuntSlotSessionCounters(const int huntIndex);
double V2TouchLevelFromLegExtreme(const int oppositeM2LegDirection, const double legLowPrice,
                                   const double legHighPrice);
bool   V2TryGetLastCompletedM2Leg(const int legDirection, double &outLegLow, double &outLegHigh,
                                   datetime &outLegStartTime, datetime &outLegEndTime);
bool   M2FindImpulseBaseBar(const datetime legStartTime, const datetime legEndTime, const int legDirection,
                             int &outBarShift);
bool   V2TryGetOppositeM2LegExtentsForTouch(const int huntIndex, double &outLegLow, double &outLegHigh,
                                               datetime &outLegStartTime, datetime &outLegEndTime);
bool   V2TryGetOppositeM2LegExtentsForTouchRecalc(const int huntIndex, double &outLegLow, double &outLegHigh,
                                                     datetime &outLegStartTime, datetime &outLegEndTime);
bool   V2GetSameDirExtremeWhileHuntOn(const int huntIndex, double &outExtreme);
void   V2ApplyTouchLevelFromM2Leg(const int huntIndex, const double legLow, const double legHigh,
                                   const string logContext, const bool allowRecalc);
void   V2ApplyTouchLevelFromOppositeLegWindow(const int huntIndex, const datetime legStartTime,
                                               const datetime legEndTime, const double legLow,
                                               const double legHigh, const string logContext,
                                               const bool allowRecalc);
void   V2TryLockTouchLevelFromM2Leg(const int huntIndex, const double legLow, const double legHigh,
                                     const string logContext);
void   V2TryRecalcTouchOnHuntSameDirProgress(const int huntIndex, const double barHigh,
                                              const double barLow, const double barClose,
                                              const bool forceBufferRecalc = false,
                                              const string forcedTriggerTag = "",
                                              const double huntExtremeAtBarStart = 0.0);
bool   V2DetectTouchRecalcBufferHit(const int huntIndex, const double barHigh, const double barLow,
                                     const double barClose, bool &outNearHuntExtreme,
                                     bool &outNearOppositeBuffer,
                                     const double huntExtremeAtBarStart = 0.0);
bool   V2TouchSideBlocksBufferRecalc(const int huntIndex, const double barHigh, const double barLow,
                                       const double pointSize);
void   V2TryTouchRecalcAfterBufferEvent(const int huntIndex, const double barHigh,
                                         const double barLow, const double barClose,
                                         const string bufferTriggerTag);
void   V2UpdateTouchLevelFromM2Swing(const int huntIndex);
void   V2DrawTouchPointLine(const int huntIndex);
void   V2ClearTouchPointLine(const int huntIndex);
void   V2RemoveHuntSessionFvgPlots(const int huntIndex);
void   V2TryClearHuntFvgsOnSameDirectionBosWhileHuntOn(const int huntIndex);
bool   V2TryDetectOppositeDirBosForHunt(const int huntIndex, string &outBosDetail);
bool   V2TryDetectTouchOfStoredLevel(const int huntIndex, const double barHigh, const double barLow,
                                      const double pointSize);
bool   V2ValidateTouchHitOppositeM2LegVolume(const int huntIndex, const int lastClosedBarShift,
                                              long &outVolumes[], int &outVolumeCount,
                                              datetime &outWindowStartOpen, datetime &outWindowEndOpen);
void   V2InvalidateTouchHitVolumeFailed(const int huntIndex, const double barClose,
                                         const long &volumes[], const int volumeCount,
                                         const datetime windowStartOpen, const datetime windowEndOpen);
void   V2HandleTouchHitConfirmed(const int huntIndex, const double barHigh, const double barLow,
                                  const double barClose, const long &volumes[], const int volumeCount,
                                  const datetime windowStartOpen, const datetime windowEndOpen);
void   V2StorePendingTradeFvg(const int huntIndex, const bool isBullishFairValueGap,
                              const double zoneLowPrice, const double zoneHighPrice,
                              const datetime formationTime);
int    V2SelectTradeFvgMemIndexForHunt(const int huntIndex);
bool   V2TryGetEarliestHuntFvgFormationBarOpenTime(const int huntIndex, datetime &outFormationBarOpen);
bool   V2TryGetEarliestHuntFvgFirstPatternBarOpen(const int huntIndex, datetime &outFirstBarOpen,
                                                   datetime &outFormationBarOpen);
bool   V2TrySelectTouchVolEntryBarFromFvgPattern(const datetime firstBarOpen,
                                                   const datetime formationBarOpen,
                                                   datetime &outEntryBarOpen, long &outEntryBarVol);
bool   V2ResolveTradeFvgForHunt(const int huntIndex, bool &outIsBullishFvg, double &outZoneLow,
                                double &outZoneHigh, datetime &outFormationTime);
void   V2TryPlacePendingFvgTradesAfterHuntOff(const int huntIndex);
void   V2TryPlaceFvgAndEndHuntAfterRecalcSkip(const int huntIndex, const bool isBullishFairValueGap,
                                                const double zoneLowPrice, const double zoneHighPrice,
                                                const datetime formationTime);
void   OnM2SwingLegDirectionChange(const int closingLegDirection, const int nextLegDirection);
void   V2OnM2LegChangeForHunt(const int huntIndex, const int closingLegDirection,
                              const int nextLegDirection);
void   V2ClearImpulseBufferZone(const int huntIndex);
void   V2UpdateImpulseBufferZone(const int huntIndex);
void   V2UpdateAllImpulseBufferZones();
void   V2ClearTouchRecalcBufferZone(const int huntIndex);
bool   V2TryGetTouchRecalcBufferAnchorExtreme(const int huntIndex, double &outAnchor);
void   V2InitTouchRecalcBufferAnchor(const int huntIndex);
void   V2BeginTouchRecalcBufferActiveLegTrack(const int huntIndex);
void   V2SyncTouchRecalcBufferAnchorFromActiveLeg(const int huntIndex);
void   V2StopTouchRecalcBufferActiveLegTrack(const int huntIndex);
double V2TouchRecalcBufferBandHalfWidth();
bool   V2DetectTouchRecalcBufferCrossOrTouch(const int huntIndex, const double barHigh,
                                               const double barLow, const double barClose);
void   V2TryArmTouchRecalcBufferResumeOnCross(const int huntIndex, const double barHigh,
                                                 const double barLow, const double barClose);
void   V2OnTouchRecalcBufferLegChange(const int huntIndex, const int closingLegDirection,
                                       const int nextLegDirection);
void   V2UpdateTouchRecalcBufferZone(const int huntIndex);
void   V2UpdateAllTouchRecalcBufferZones();
bool   TryDetectH4WickLiquidityBreachForLeg(const int swingDirection, const double breachLevel,
                                              const datetime huntLegKey, const double barHigh,
                                              const double barLow, const double prevHigh,
                                              const double prevLow, const double pointSize,
                                              double &outLevel, bool &outHighBreached,
                                              datetime &outLegEndTime);
bool   TryDetectH4WickLiquidityBreach(const double barHigh, const double barLow,
                                       const double prevHigh, const double prevLow,
                                       const double pointSize, double &outLevel,
                                       bool &outHighBreached, datetime &outLegEndTime);
int    V2ArmOppositeFvgHuntAfterH4Breach(const double h4Level, const bool h4HighBreached,
                                            const datetime breachedLegEndTime,
                                            const double barClose, const double barLow,
                                            const double barHigh);
void   V2EndOppositeFvgHuntSession(const int huntIndex, const string offReason,
                                    const bool tryPlaceTradeAfterOff = false);
void   V2OnH4LegClosedForHunts(const int closedLegDirection, const datetime closedLegEndTime);
int    V2OppositeH4LegDirectionForHunt(const int huntIndex);

void   ApplyTradeFillingModeFromSymbol();
double M2FvgStopBufferPrice();
double M2TouchVolSlBufferPrice(const int barShift);
double M2TouchVolEntryOffsetPrice(const int barShift);
double M2TouchVolLimitEntryPrice(const bool isBuy, const int barShift,
                                  const double barLow, const double barHigh);
int    TouchVolEffectiveMinSlPoints();
bool   ApplyTouchVolMinimumSlDistance(const bool isBuy, const double entryPrice,
                                       double &inOutStopLossPrice);
bool   M2TouchVolSlReferenceExtreme(const bool isBuy, const int entryBarShift,
                                     const datetime windowStartInclusive,
                                     const double legExtremeFloor,
                                     double &outRefExtreme, int &outRefBarShift);
double LossPerLotFromTickSpec(const double entryPrice, const double stopLossPrice);
double CalculateVolumeForFixedUsdRisk(const bool isBuy, const double entryPrice,
                                        const double stopLossPrice, const double riskAccountCurrency);
bool   StopsDistanceAllowed(const bool isBuy, const double entryPrice, const double stopLossPrice,
                            const double takeProfitPrice);
bool   HasOurTradeForFormation(const datetime formationTime);
string HuntTradeOrderCommentPrefix(const datetime huntSessionId = 0);
bool   OrderCommentBelongsToActiveHunt(const string orderComment);
bool   V2IsHuntSessionStillActive(const datetime huntSessionId);
bool   HasOurHuntOpenPosition();
bool   HasOurHuntPendingOrders();
void   ResetHuntTradeState();
void   ResetHuntTradePlacementGateOnly();
bool   HasOurHuntTradePendingOrders();
void   CancelOurHuntPendingOrders(const datetime huntSessionId = 0);
bool   IsConsecutiveM2FvgBarAfter(const datetime priorFvgFormationTime, const datetime newFvgFormationTime);
bool   ResolveHuntFvgOrderPlacementGate(const datetime formationTime, const datetime huntSessionId,
                                        bool &outReplacePendingOnly);
void   RegisterHuntTradeAfterSuccessfulPlace(const bool isBuy, const double entryPrice,
                                               const double takeProfitTp1Price,
                                               const double preEntryCancelTpLevel,
                                               const datetime fvgFormationTime,
                                               const datetime huntSessionId);
void   CheckHuntPreEntryTp3CancelOnTick();
void   CheckHuntFvgBeyondChartRangeCancelOnTick();
bool   IsOurHuntPendingOrderTicket(const ulong orderTicket);
bool   TryParseFormationTimeFromHuntOrderComment(const string orderComment, datetime &outFormationTime);
bool   FvgFormationBarBeyondChartRange(const datetime formationTime, int &outBarShift);
void   V2ClearHuntTradeOrdersActiveForSession(const datetime huntSessionId);
void   V2ClearHuntPreEntryWatchForHunt(const int huntIndex);
bool   ParseHuntSessionIdFromTradeComment(const string orderComment, datetime &outSessionId);
bool   V2CollectUniquePendingHuntSessionIds(datetime &outSessionIds[], const int maxSessions);
bool   V2TrySyncPreEntryWatchForSession(const datetime sessionId, const int huntIndex,
                                       int &outPendingCount, bool &outIsBuy,
                                       double &outTp3Level, double &outEntryPrice);
bool   V2TrySyncPreEntryWatchForHunt(const int huntIndex, int &outPendingCount);
void   V2RefreshGlobalHuntTradeWatchFromSessions();
bool   TrySyncHuntPreEntryWatchFromPendingOrders(int &outPendingCount);
bool   HuntMarketReachedTakeProfitLevel(const bool isBuy, const double takeProfitLevel);
bool   SameDirectionM2BosBetweenEntryAndTp3Since(const bool isBuy, const double entryPrice,
                                                  const double tp3Level, const datetime sinceTime);
bool   ResolveFvgEntryPrice(const bool isBullishFairValueGap, const double zoneLowPrice,
                            const double zoneHighPrice, bool &outUseMarketOrder, double &outEntryPrice);
bool   ComputeAbsorptionLegTakeProfits(const bool isBullishFairValueGap, const double entryPrice,
                                       const double legRange, double &outTakeProfitPrices[]);
int    V4TradeLegDirectionForFvg(const bool isBullishFairValueGap);
bool   V4ResolveH4SameDirLegRangeForTp(const bool isBullishFairValueGap, double &outLegRange,
                                        datetime &outLegEndTime);
bool   M2FindMaxVolumeBarOpenTimeExcludingOldest(const long &volumes[], const int count,
                                                  const datetime windowStartOpen,
                                                  const datetime windowEndOpen,
                                                  datetime &outBarOpenTime, long &outMaxVolume);
bool   ResolveTouchLegVolumeBarEntryAndSl(const bool isBuy, const int barShift,
                                           const datetime slWindowStartOpen, const int huntIndex,
                                           bool &outUseMarketOrder, double &outEntryPrice,
                                           double &outStopLossPrice, string &outFailReason);
bool   TryPlaceTouchVolumeBarTradeSetup(const int huntIndex, const bool isBuy,
                                         const datetime maxVolBarOpenTime, const long maxVolume,
                                         const datetime slWindowStartOpen,
                                         const datetime huntSessionId);
bool   TryPlaceOppositeFvgTradeSetup(const bool isBullishFairValueGap, const double zoneLowPrice,
                                       const double zoneHighPrice, const datetime formationTime,
                                       const datetime huntSessionId, const double h4LegRange);
bool   IsFvgAutomatedTradingAllowed(string &outBlockReason);
bool   TryFallbackLimitEntryToMarket(const bool isBullishFairValueGap, const double zoneLowPrice,
                                     const double zoneHighPrice, bool &inOutUseMarketOrder,
                                     double &inOutEntryPrice);
bool   TryPromoteFvgLimitToMarketIfFormationCloseMatchesEntry(const bool isBullishFairValueGap,
                                                               const double zoneLowPrice,
                                                               const double zoneHighPrice,
                                                               const double limitEntryPrice,
                                                               bool &inOutUseMarketOrder,
                                                               double &inOutEntryPrice);
bool   FvgFormationBarMeetsMinTickVolume(const int formationBarShift);
bool   TryNthM2CompletedSwingLeg(const int swingDirection, const int nFromLatest,
                                 double &outLegHigh, double &outLegLow, datetime &outLegEndTime);
bool   TryDetectM2PriceBreakAboveLatestUpLegHigh(double &outBrokenLevel);
bool   TryDetectM2PriceBreakBelowLatestDownLegLow(double &outBrokenLevel);
bool   StopLossModifyAllowed(const bool isBuy, const double newStopLoss, const double takeProfitPrice);
bool   HuntTradeCommentIsOurs(const string orderComment);
bool   HuntTradeCommentMatchesSession(const string orderComment);
void   EnsureHuntTradeSessionCommentPrefixFromOrdersOrPositions();
bool   HasOurHuntTradeOpenPosition();
void   ManageHuntOpenPositionsOnM2BarClose();
void   TrailHuntTradeStopOnSameDirectionM2Bos(const bool isBuy, const double bosBrokenLevel);
bool   TryGetHuntTradeSlAndTp1(double &outStopLossPrice, double &outTp1Price);
bool   BosBreakInsideSlTp1Zone(const bool isBuy, const double stopLossPrice, const double tp1Price,
                               const double bosBrokenLevel);
bool   HuntTradeCommentIsOvTpIndex(const string orderComment, const int tpIndex);
void   ApplyHuntTradeFirstOppositeM2BosMgmt(const bool isBuy, const double bosBrokenLevel);

//+------------------------------------------------------------------+
int OnInit()
{
   if(InputSwitchChartToH4 && !InputFastTesterMode)
   {
      ChartSetSymbolPeriod(0, _Symbol, InputH4NarrativeTimeframe);
      ChartRedraw(0);
   }

   ObjectsDeleteAll(0, ChartObjectNamePrefixH4SwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4SwingLabelText, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_ANCHOR, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_RECT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_LBL, -1, -1);
   ObjectDelete(0, LQ_OBJ_HUNT_HUD);
   ObjectsDeleteAll(0, LQ_OBJ_IMPULSE_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_RECALC_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_POINT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_RECT_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_LINE_PREFIX, -1, -1);

   ZeroMemory(g_h4Swing);
   ZeroMemory(g_h4BosSwing);
   ZeroMemory(g_m2Swing);
   g_liquidityPoolCount = 0;

   V2InitAllHuntSlots();
   g_h4LegLiquidityBreachCount       = 0;
   g_h4LegVolumeBreachCount          = 0;
   H4ResetActiveLegVolumeBreachTrack();
   ResetH4BosBiasState();
   ResetHuntTradeState();

   WarmupH4SwingFromHistory();
   WarmupM2SwingFromHistory();
   ResetH4BosBiasState();
   H4ClearVolumeBreachMemoryAndChart();
   RebuildH4LiquidityPivotLevels();
   UpdateH4LegLiquidityBreachMemoryOnM2Bar();
   g_h4LastLoggedEffectiveBias = GetH4TradeDirectionBias();
   g_h4EffectiveBiasLogReady   = true;

   g_lastH4BarOpen = iTime(_Symbol, InputH4NarrativeTimeframe, 0);
   g_lastM2BarOpen  = iTime(_Symbol, InputM2NarrativeTimeframe, 0);

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();

   if(H4LqLoggingEnabled())
   {
      PrintFormat("%s v%s | primary=%s secondary=%s fastTester=%s",
                  H4_LQ_LOG_PREFIX, H4_LQ_V2_VERSION,
                  EnumToString(InputH4NarrativeTimeframe),
                  EnumToString(InputM2NarrativeTimeframe),
                  InputFastTesterMode ? "Y" : "N");
   }

   if(H4LqChartDrawEnabled())
   {
      RefreshLiquidityHuntHud();
      RefreshH4BosBiasHud();
      ChartRedraw(0);
   }
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4SwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4SwingLabelText, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_ANCHOR, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_RECT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_LBL, -1, -1);
   ObjectDelete(0, LQ_OBJ_HUNT_HUD);
   ObjectDelete(0, LQ_OBJ_H4_BIAS_HUD);
   ObjectsDeleteAll(0, LQ_OBJ_IMPULSE_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_RECALC_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_POINT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_RECT_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_LINE_PREFIX, -1, -1);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   CheckHuntFvgBeyondChartRangeCancelOnTick();
   CheckHuntPreEntryTp3CancelOnTick();
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckHuntFvgBeyondChartRangeCancelOnTick();
   CheckHuntPreEntryTp3CancelOnTick();
   if(H4LqChartDrawEnabled())
   {
      UpdateM2SwingAnchorVisualRealtime(g_m2Swing);
      UpdateM2LiveSwingLegVisualOnTick();
   }

   const datetime tH4 = iTime(_Symbol, InputH4NarrativeTimeframe, 0);
   if(tH4 != g_lastH4BarOpen)
   {
      g_lastH4BarOpen = tH4;
      ProcessH4SwingStep(1);
      ProcessH4BosSwingStep(1);
      RebuildH4LiquidityPivotLevels();
      ProcessH4BosOnH4Close(1);
      if(H4LqChartDrawEnabled(InputDrawH4SwingLegVisuals))
         RebuildAllH4VolumeBreachMarkers();
      if(InputEnableH4BosTradeDirectionBias)
         LogH4TradeDirectionBiasIfChanged();
      if(H4LqChartDrawEnabled(InputShowH4BosBiasHud))
         RefreshH4BosBiasHud();
   }

   const datetime tM2 = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(tM2 != g_lastM2BarOpen)
   {
      g_lastM2BarOpen = tM2;
      if(InputEnableOppositeFvgHuntAfterH4Breach)
         ProcessBosOppositeFairValueGapWindow();
      UpdateH4LegLiquidityBreachMemoryOnM2Bar();
      if(H4LqChartDrawEnabled(InputDrawH4SwingLegVisuals))
         RebuildAllH4VolumeBreachMarkers();
      ProcessM2SwingStep();
      ManageHuntOpenPositionsOnM2BarClose();
      if(H4LqChartDrawEnabled(InputShowLiquidityHuntHud))
         RefreshLiquidityHuntHud();
   }
}

//+------------------------------------------------------------------+
void WarmupH4SwingFromHistory()
{
   if(InputWarmupBars <= 0)
      return;
   const int bars = iBars(_Symbol, InputH4NarrativeTimeframe);
   const int n = (int)MathMin(bars - 2, InputWarmupBars);
   if(n < 1)
      return;
   for(int k = n; k >= 1; k--)
   {
      ProcessH4SwingStep(k);
      ProcessH4BosSwingStep(k);
      RebuildH4LiquidityPivotLevels();
      ProcessH4BosOnH4Close(k);
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
// plot_swing_h1_m5_copy SwingClose — M2 only (no H1 keyLevelId).
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
//| Realtime segment at priceAnchorLevel — close cross vs this flips the M2 leg. |
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
   // Anchor tolerance: M2 = body vs 0.2× prior avg; H4 = wick AND body vs 0.5× prior avg.
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

   const double anchorDecentMovementMultiplier =
      (timeframe == InputH4NarrativeTimeframe) ? 0.5 : 0.2;
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

      if(timeframe == InputM2NarrativeTimeframe && !replayOnly)
         OnM2SwingLegDirectionChange(closingLegDirection, nextSwingDirection);

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

   if(H4LqChartDrawEnabled(InputDrawH4SwingLegVisuals))
   {
      const string chartObjectName =
         ChartObjectNamePrefixH4SwingTrendLine + IntegerToString((long)swingState.currentSwingLeg.legEndTime);

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

      datetime tRightDraw = swingState.currentSwingLeg.legEndTime;
      if(tRightDraw <= swingState.currentSwingLeg.legStartTime)
         tRightDraw = swingState.currentSwingLeg.legStartTime + (datetime)PeriodSeconds(timeframe);

      if(ObjectCreate(0, chartObjectName, OBJ_TREND, 0, swingState.currentSwingLeg.legStartTime,
                      trendLineStartPrice, tRightDraw, trendLineEndPrice))
      {
         ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, InputH4SwingTrendLineColor);
         ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, chartObjectName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      }

      const bool isUplegSwingDirection = (swingState.currentSwingLeg.swingDirection == 1);
      DrawSwingLegLabel(ChartObjectNamePrefixH4SwingLabelText, swingState.currentSwingLeg.legEndTime,
                        trendLineEndPrice, isUplegSwingDirection, 0);
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
void SwingCloseH4ToHistory(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                            const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

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
void ProcessH4SwingStepCore(SwingState &swingState, const int lastClosedBarShift,
                             const double anchorMultiplier, const bool useWickAndBodyForDecent,
                             const bool withBreachSideEffects)
{
   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
   const int         sh            = lastClosedBarShift;

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
      if(withBreachSideEffects)
         H4OnH4ActiveLegStarted(swingState, sh);
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
      if(withBreachSideEffects)
      {
         if(g_h4ActiveLegVolumeTrack.legStartTime != swingState.currentSwingLeg.legStartTime)
            H4OnH4ActiveLegStarted(swingState, sh);
         else
            H4OnH4ActiveLegBarClosed(swingState, sh);
      }
      return;
   }

   SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

   if(withBreachSideEffects)
      H4OnH4ActiveLegBarClosed(swingState, sh);

   if(withBreachSideEffects)
      SwingCloseH4Context(swingState, timeframe, sh);
   else
      SwingCloseH4ToHistory(swingState, timeframe, sh);

   Swing closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
   if(withBreachSideEffects)
   {
      H4FinalizeActiveLegVolumeBreach(closedSwingLeg);
      V2OnH4LegClosedForHunts(closedSwingLeg.swingDirection, closedSwingLeg.legEndTime);
   }

   double newSwingLegHigh = lastClosedBarHigh;
   double newSwingLegLow  = lastClosedBarLow;
   if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
      newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
   else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
      newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

   SwingStartNew(swingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow, sh);
   swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
   if(withBreachSideEffects)
      H4OnH4ActiveLegStarted(swingState, sh);
}

//+------------------------------------------------------------------+
//| H4 breach/hunt swing legs: anchor 0.5 (wick + body vs prior 5-bar avg). |
//+------------------------------------------------------------------+
void ProcessH4SwingStep(const int lastClosedBarShift = 1)
{
   ProcessH4SwingStepCore(g_h4Swing, lastClosedBarShift, H4_BREACH_ANCHOR_MULTIPLIER, true, true);
}

//+------------------------------------------------------------------+
//| H4 BOS swing legs: anchor 1.0 (full range vs prior 5-bar avg), memory only. |
//+------------------------------------------------------------------+
void ProcessH4BosSwingStep(const int lastClosedBarShift = 1)
{
   ProcessH4SwingStepCore(g_h4BosSwing, lastClosedBarShift, H4_BOS_ANCHOR_MULTIPLIER, false, false);
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
   const int activeCount = V2CountActiveHunts();
   const bool highOn = (V2FindActiveHuntByBreachPolarity(true) >= 0);
   const bool lowOn  = (V2FindActiveHuntByBreachPolarity(false) >= 0);
   string txt = "v2 hunts: none";
   if(activeCount > 0)
   {
      if(highOn && lowOn)
         txt = "v2 hunts: high+low";
      else if(highOn)
         txt = "v2 hunts: high";
      else if(lowOn)
         txt = "v2 hunts: low";
      else
         txt = StringFormat("v2 hunts: %d active", activeCount);
   }
   ObjectSetString(0, LQ_OBJ_HUNT_HUD, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_COLOR, activeCount > 0 ? clrLime : clrSilver);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
//| H4 BOS cross: close cross vs latest same-dir leg on g_h4BosSwing (anchor 1.0). |
//+------------------------------------------------------------------+
bool TryDetectH4BosCrossOnBar(const int h4BarShift, int &outDirection,
                               double &outBrokenLevel, datetime &outBarOpenTime,
                               datetime &outLegEndTime)
{
   outDirection   = 0;
   outBrokenLevel = 0.0;
   outBarOpenTime = 0;
   outLegEndTime  = 0;

   if(h4BarShift < 0 || g_h4BosSwing.swingHistoryCount < 1)
      return false;

   const ENUM_TIMEFRAMES tf = InputH4NarrativeTimeframe;
   const double closePrice  = iClose(_Symbol, tf, h4BarShift);
   const double prevClose   = iClose(_Symbol, tf, h4BarShift + 1);
   const double pointSize   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   outBarOpenTime = iTime(_Symbol, tf, h4BarShift);
   if(outBarOpenTime == 0)
      return false;

   for(int historyIndex = g_h4BosSwing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_h4BosSwing.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double legHigh = g_h4BosSwing.swingHistory[historyIndex].legHighPrice;
      if(closePrice > legHigh + pointSize && prevClose <= legHigh + pointSize)
      {
         outDirection   = 1;
         outBrokenLevel = legHigh;
         outLegEndTime  = g_h4BosSwing.swingHistory[historyIndex].legEndTime;
         return true;
      }
      break;
   }

   for(int historyIndex = g_h4BosSwing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_h4BosSwing.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double legLow = g_h4BosSwing.swingHistory[historyIndex].legLowPrice;
      if(closePrice < legLow - pointSize && prevClose >= legLow - pointSize)
      {
         outDirection   = -1;
         outBrokenLevel = legLow;
         outLegEndTime  = g_h4BosSwing.swingHistory[historyIndex].legEndTime;
         return true;
      }
      break;
   }

   return false;
}

//+------------------------------------------------------------------+
void ClearH4BosPendingConfirm()
{
   ZeroMemory(g_h4BosPendingConfirm);
}

//+------------------------------------------------------------------+
bool H4BosCloseHoldsBeyondLevel(const int direction, const int h4BarShift, const double brokenLevel)
{
   if(direction != 1 && direction != -1)
      return false;

   const double closePrice = iClose(_Symbol, InputH4NarrativeTimeframe, h4BarShift);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps        = (pointSize > 0.0 ? pointSize : 0.00001);

   if(direction == 1)
      return (closePrice > brokenLevel + eps);
   return (closePrice < brokenLevel - eps);
}

//+------------------------------------------------------------------+
void ResetH4BosBiasState()
{
   ZeroMemory(g_h4LastBosRecord);
   g_h4LastBosRecordValid    = false;
   g_h4BosRecordedLegCount   = 0;
   ClearH4BosPendingConfirm();
}

//+------------------------------------------------------------------+
void RememberH4BosRecordedLeg(const int direction, const datetime legEndTime)
{
   if(direction == 0 || legEndTime == 0)
      return;

   if(g_h4BosRecordedLegCount >= H4_BOS_RECORDED_LEG_CAPACITY)
   {
      for(int shiftIndex = 1; shiftIndex < H4_BOS_RECORDED_LEG_CAPACITY; shiftIndex++)
         g_h4BosRecordedLegs[shiftIndex - 1] = g_h4BosRecordedLegs[shiftIndex];
      g_h4BosRecordedLegCount = H4_BOS_RECORDED_LEG_CAPACITY - 1;
   }

   const int index = g_h4BosRecordedLegCount;
   g_h4BosRecordedLegs[index].direction  = direction;
   g_h4BosRecordedLegs[index].legEndTime   = legEndTime;
   g_h4BosRecordedLegCount++;
}

//+------------------------------------------------------------------+
bool H4BosAlreadyRecordedForLeg(const int direction, const datetime legEndTime)
{
   if(legEndTime == 0)
      return false;

   for(int i = 0; i < g_h4BosRecordedLegCount; i++)
   {
      if(g_h4BosRecordedLegs[i].direction == direction &&
         g_h4BosRecordedLegs[i].legEndTime == legEndTime)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Confirm pending BOS after 1 closed H4 candle (reject fake breakout). |
//+------------------------------------------------------------------+
void TryConfirmH4BosPendingOnBarClose(const int h4BarShift)
{
   if(!g_h4BosPendingConfirm.active)
      return;

   const int      direction       = g_h4BosPendingConfirm.direction;
   const double   brokenLevel     = g_h4BosPendingConfirm.brokenLevel;
   const datetime legEndTime      = g_h4BosPendingConfirm.legEndTime;
   const datetime breakBarOpenTime = g_h4BosPendingConfirm.breakBarOpenTime;
   const datetime confirmBarOpenTime = iTime(_Symbol, InputH4NarrativeTimeframe, h4BarShift);

   ClearH4BosPendingConfirm();

   if(confirmBarOpenTime == 0)
      return;

   if(H4BosCloseHoldsBeyondLevel(direction, h4BarShift, brokenLevel))
   {
      RecordH4BosBreak(direction, confirmBarOpenTime, legEndTime, brokenLevel);
      if(H4LqLoggingEnabled())
      {
         LogHuntEvent("H4_BOS",
                      StringFormat("%s BOS confirmed confirmBar=%s breakBar=%s legEnd=%s lvl=%.5f",
                                   direction == 1 ? "bull" : "bear",
                                   TimeToString(confirmBarOpenTime, TIME_DATE | TIME_MINUTES),
                                   TimeToString(breakBarOpenTime, TIME_DATE | TIME_MINUTES),
                                   TimeToString(legEndTime, TIME_DATE | TIME_MINUTES),
                                   brokenLevel));
      }
      return;
   }

   if(H4LqLoggingEnabled())
   {
      LogHuntEvent("H4_BOS_REJECT",
                   StringFormat("%s fake breakout breakBar=%s confirmBar=%s close=%.5f lvl=%.5f",
                                direction == 1 ? "bull" : "bear",
                                TimeToString(breakBarOpenTime, TIME_DATE | TIME_MINUTES),
                                TimeToString(confirmBarOpenTime, TIME_DATE | TIME_MINUTES),
                                iClose(_Symbol, InputH4NarrativeTimeframe, h4BarShift),
                                brokenLevel));
   }
}

//+------------------------------------------------------------------+
//| H4 BOS: cross → pending; next H4 close must hold beyond level.   |
//+------------------------------------------------------------------+
void ProcessH4BosOnH4Close(const int h4BarShift)
{
   if(h4BarShift < 1 || g_h4BosSwing.swingHistoryCount < 1)
      return;

   TryConfirmH4BosPendingOnBarClose(h4BarShift);

   int      bosDirection = 0;
   double   brokenLevel  = 0.0;
   datetime barOpenTime  = 0;
   datetime legEndTime   = 0;
   if(!TryDetectH4BosCrossOnBar(h4BarShift, bosDirection, brokenLevel, barOpenTime, legEndTime))
      return;

   if(legEndTime == 0 || barOpenTime == 0)
      return;

   if(H4BosAlreadyRecordedForLeg(bosDirection, legEndTime))
      return;

   g_h4BosPendingConfirm.active           = true;
   g_h4BosPendingConfirm.direction        = bosDirection;
   g_h4BosPendingConfirm.brokenLevel      = brokenLevel;
   g_h4BosPendingConfirm.legEndTime       = legEndTime;
   g_h4BosPendingConfirm.breakBarOpenTime = barOpenTime;

   if(H4LqLoggingEnabled())
   {
      LogHuntEvent("H4_BOS_PENDING",
                   StringFormat("%s cross breakBar=%s legEnd=%s lvl=%.5f — await 1 H4 close",
                                bosDirection == 1 ? "bull" : "bear",
                                TimeToString(barOpenTime, TIME_DATE | TIME_MINUTES),
                                TimeToString(legEndTime, TIME_DATE | TIME_MINUTES),
                                brokenLevel));
   }
}

//+------------------------------------------------------------------+
void RecordH4BosBreak(const int direction, const datetime barOpenTime, const datetime legEndTime,
                       const double brokenLevel)
{
   if(direction == 0 || barOpenTime == 0 || legEndTime == 0)
      return;

   if(H4BosAlreadyRecordedForLeg(direction, legEndTime))
      return;

   RememberH4BosRecordedLeg(direction, legEndTime);

   g_h4LastBosRecord.direction   = direction;
   g_h4LastBosRecord.barOpenTime = barOpenTime;
   g_h4LastBosRecord.legEndTime  = legEndTime;
   g_h4LastBosRecord.brokenLevel = brokenLevel;
   g_h4LastBosRecordValid        = true;
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

   LogHuntEvent("H4_BIAS",
                StringFormat("%s → %s (lastBreak=%s bar=%s)",
                             H4TradeDirectionBiasText(g_h4LastLoggedEffectiveBias),
                             H4TradeDirectionBiasText(bias),
                             g_h4LastBosRecordValid
                                ? (g_h4LastBosRecord.direction == 1 ? "bull" : "bear")
                                : "none",
                             g_h4LastBosRecordValid
                                ? TimeToString(g_h4LastBosRecord.barOpenTime, TIME_DATE | TIME_MINUTES)
                                : "—"));
   g_h4LastLoggedEffectiveBias = bias;
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForM2BarCount(const int barCount)
{
   if(barCount < 1)
      return 0.0;

   const int totalBars = iBars(_Symbol, InputM2NarrativeTimeframe);
   if(totalBars < 4)
      return 0.0;

   const int useBarCount = (int)MathMin((double)barCount, (double)(totalBars - 1));
   if(useBarCount < 1)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = 1; barShiftIndex <= useBarCount; barShiftIndex++)
   {
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, InputM2NarrativeTimeframe, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, InputM2NarrativeTimeframe, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForH4BarCount(const int barCount)
{
   if(barCount < 1)
      return 0.0;

   const int totalBars = iBars(_Symbol, InputH4NarrativeTimeframe);
   if(totalBars < 4)
      return 0.0;

   const int useBarCount = (int)MathMin((double)barCount, (double)(totalBars - 1));
   if(useBarCount < 1)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = 1; barShiftIndex <= useBarCount; barShiftIndex++)
   {
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, InputH4NarrativeTimeframe, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, InputH4NarrativeTimeframe, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
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
//| Same M2 swing legs already drawn on chart (PFX_M2_TREND) — optional supplement when draw is on. |
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
//| Group swing extremes → qualifying line TPs (min R:R) + optional chart zones. |
//+------------------------------------------------------------------+
bool BuildTradeSwingGroupTakeProfits(const bool isBullishTrade, const datetime formationTime,
                                     const double entryPrice, const double stopLossPrice,
                                     double &outTakeProfitPrices[], int &outTakeProfitCount)
{
   outTakeProfitCount = 0;
   ArrayResize(outTakeProfitPrices, 0);

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

   if(outTakeProfitCount < 1)
   {
      LogHuntEvent("TRADE_SWGRP_SKIP",
                   StringFormat("%s no TP lines met min R:R %.2f (skipped=%d)",
                                isBullishTrade ? "bull" : "bear",
                                InputTradeSwingTpMinRewardToRisk, groupsSkipped));
      return false;
   }

   SortTakeProfitLevelsNearestFirst(isBuy, outTakeProfitPrices, outTakeProfitCount);

   if(outTakeProfitCount > LQ_TP_COUNT)
      outTakeProfitCount = LQ_TP_COUNT;

   LogHuntEvent("TRADE_SWGRP_TP",
                StringFormat("%s tps=%d drawn=%d skippedRR=%d nearest=%.5f farthest=%.5f",
                             isBullishTrade ? "bull" : "bear", outTakeProfitCount, groupSeq,
                             groupsSkipped, outTakeProfitPrices[0],
                             outTakeProfitPrices[outTakeProfitCount - 1]));

   if(H4LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
      ChartRedraw(0);

   return true;
}

//+------------------------------------------------------------------+
int GetH4TradeDirectionBias()
{
   if(!InputEnableH4BosTradeDirectionBias || !g_h4LastBosRecordValid)
      return 0;

   return g_h4LastBosRecord.direction;
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
void RefreshH4BosBiasHud()
{
   if(!H4LqChartDrawEnabled(InputShowH4BosBiasHud))
   {
      ObjectDelete(0, LQ_OBJ_H4_BIAS_HUD);
      return;
   }

   if(ObjectFind(0, LQ_OBJ_H4_BIAS_HUD) < 0)
   {
      if(!ObjectCreate(0, LQ_OBJ_H4_BIAS_HUD, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_YDISTANCE, 18);
      ObjectSetString(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_HIDDEN, true);
   }

   int          bias  = 0;
   if(g_h4LastBosRecordValid)
      bias = g_h4LastBosRecord.direction;
   string       arrow = "—";
   color        col   = clrSilver;
   if(bias == 1)
   {
      arrow = "↑";
      col   = clrLime;
   }
   else if(bias == -1)
   {
      arrow = "↓";
      col   = clrTomato;
   }

   ObjectSetString(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_TEXT, "H4 " + arrow);
   ObjectSetInteger(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_COLOR, col);
   ObjectSetInteger(0, LQ_OBJ_H4_BIAS_HUD, OBJPROP_FONTSIZE, 14);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForFairValueGapFilterM2()
{
   return ReferenceChartHeightForM2BarCount(InputChartRangeBarCount);
}

//+------------------------------------------------------------------+
bool FairValueGapGapMeetsMinimumPercentOfRangeM2(const double zoneLowPrice, const double zoneHighPrice,
                                                double &outGapSize, double &outChartHeight,
                                                double &outMinGapRequired)
{
   outGapSize        = 0.0;
   outChartHeight    = 0.0;
   outMinGapRequired = 0.0;

   outGapSize = MathAbs(zoneHighPrice - zoneLowPrice);
   if(outGapSize <= 0.0)
      return false;

   if(InputFairValueGapMinimumPercentOfChartRange <= 0.0)
      return true;

   outChartHeight = ReferenceChartHeightForFairValueGapFilterM2();
   if(outChartHeight <= 0.0)
      return true;

   outMinGapRequired = outChartHeight * (InputFairValueGapMinimumPercentOfChartRange / 100.0);
   return (outGapSize >= outMinGapRequired);
}

//+------------------------------------------------------------------+
bool TryDetectFairValueGapPatternOnLastClosedBarM2(bool &isBullishFairValueGap,
                                                   double &fairValueGapZoneLowPrice,
                                                   double &fairValueGapZoneHighPrice)
{
   isBullishFairValueGap     = false;
   fairValueGapZoneLowPrice  = 0.0;
   fairValueGapZoneHighPrice = 0.0;

   if(iBars(_Symbol, InputM2NarrativeTimeframe) < 4)
      return false;

   const double newestBarHigh = iHigh(_Symbol, InputM2NarrativeTimeframe, 1);
   const double newestBarLow  = iLow(_Symbol, InputM2NarrativeTimeframe, 1);
   const double oldestBarHigh = iHigh(_Symbol, InputM2NarrativeTimeframe, 3);
   const double oldestBarLow  = iLow(_Symbol, InputM2NarrativeTimeframe, 3);

   if(newestBarLow > oldestBarHigh)
   {
      isBullishFairValueGap     = true;
      fairValueGapZoneLowPrice  = oldestBarHigh;
      fairValueGapZoneHighPrice = newestBarLow;
      return true;
   }

   if(newestBarHigh < oldestBarLow)
   {
      isBullishFairValueGap     = false;
      fairValueGapZoneLowPrice  = newestBarHigh;
      fairValueGapZoneHighPrice = oldestBarLow;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
bool DetectFairValueGapOnLastClosedBarM2(bool &isBullishFairValueGap, double &fairValueGapZoneLowPrice,
                                        double &fairValueGapZoneHighPrice)
{
   if(!TryDetectFairValueGapPatternOnLastClosedBarM2(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                                     fairValueGapZoneHighPrice))
      return false;

   double gapSize = 0.0;
   double chartHeight = 0.0;
   double minGap = 0.0;
   return FairValueGapGapMeetsMinimumPercentOfRangeM2(fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                                                    gapSize, chartHeight, minGap);
}

//+------------------------------------------------------------------+
bool TryLatestH4CompletedUpLegHigh(double &outHigh)
{
   for(int i = g_h4Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_h4Swing.swingHistory[i].swingDirection == 1)
      {
         outHigh = g_h4Swing.swingHistory[i].legHighPrice;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryLatestH4CompletedDownLegLow(double &outLow)
{
   for(int i = g_h4Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_h4Swing.swingHistory[i].swingDirection == -1)
      {
         outLow = g_h4Swing.swingHistory[i].legLowPrice;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TrySecondLastH4CompletedUpLegHigh(double &outHigh)
{
   int upLegsFound = 0;
   for(int i = g_h4Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_h4Swing.swingHistory[i].swingDirection != 1)
         continue;
      upLegsFound++;
      if(upLegsFound == 2)
      {
         outHigh = g_h4Swing.swingHistory[i].legHighPrice;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TrySecondLastH4CompletedDownLegLow(double &outLow)
{
   int downLegsFound = 0;
   for(int i = g_h4Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_h4Swing.swingHistory[i].swingDirection != -1)
         continue;
      downLegsFound++;
      if(downLegsFound == 2)
      {
         outLow = g_h4Swing.swingHistory[i].legLowPrice;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryNthH4CompletedSwingLeg(const int swingDirection, const int nFromLatest,
                              double &outLegHigh, double &outLegLow, datetime &outLegEndTime)
{
   outLegEndTime = 0;
   if(swingDirection == 0 || nFromLatest < 1)
      return false;

   int legsFound = 0;
   for(int i = g_h4Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_h4Swing.swingHistory[i].swingDirection != swingDirection)
         continue;
      legsFound++;
      if(legsFound == nFromLatest)
      {
         outLegHigh    = g_h4Swing.swingHistory[i].legHighPrice;
         outLegLow     = g_h4Swing.swingHistory[i].legLowPrice;
         outLegEndTime = g_h4Swing.swingHistory[i].legEndTime;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryGetH4LegBarOpenTimeFromEnd(const datetime legStartTime, const datetime legEndTime,
                                    const int nFromEnd, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legEndTime == 0 || nFromEnd < 1)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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
      return iLow(_Symbol, InputH4NarrativeTimeframe, h4BarShift);
   if(swingDirection == -1)
      return iHigh(_Symbol, InputH4NarrativeTimeframe, h4BarShift);
   return 0.0;
}

//+------------------------------------------------------------------+
bool H4BarHasDecentMovementForLegDirection(const int barShift, const int legSwingDirection)
{
   if(barShift < 0 || legSwingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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

//+------------------------------------------------------------------+
bool M2FindMaxVolumeBarOpenTimeExcludingOldest(const long &volumes[], const int count,
                                                const datetime windowStartOpen,
                                                const datetime windowEndOpen,
                                                datetime &outBarOpenTime, long &outMaxVolume)
{
   outBarOpenTime = 0;
   outMaxVolume   = -1;
   if(count < 2 || windowStartOpen == 0 || windowEndOpen == 0)
      return false;

   int  maxVolIndex = -1;
   long maxVol      = -1;
   for(int i = 1; i < count; i++)
   {
      if(volumes[i] > maxVol)
      {
         maxVol      = volumes[i];
         maxVolIndex = i;
      }
      else if(volumes[i] == maxVol)
         maxVolIndex = i;
   }

   int  leapIndex = -1;
   long bestLeap  = 0;
   for(int i = 1; i < count; i++)
   {
      const long leap = volumes[i] - volumes[i - 1];
      if(leap < LQ_TOUCH_VOL_MASSIVE_LEAP_MIN)
         continue;
      if(leap > bestLeap || (leap == bestLeap && i > leapIndex))
      {
         bestLeap  = leap;
         leapIndex = i;
      }
   }

   const int bestIndex = (leapIndex >= 0) ? leapIndex : maxVolIndex;
   if(bestIndex < 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartOpen, true);
   if(shiftStartOlder < 0)
      return false;

   const int barShift = shiftStartOlder - bestIndex;
   if(barShift < 0)
      return false;

   outBarOpenTime = iTime(_Symbol, timeframe, barShift);
   outMaxVolume   = volumes[bestIndex];
   return outBarOpenTime > 0;
}

//+------------------------------------------------------------------+
bool M2TouchVolSlReferenceExtreme(const bool isBuy, const int entryBarShift,
                                   const datetime windowStartInclusive,
                                   const double legExtremeFloor,
                                   double &outRefExtreme, int &outRefBarShift)
{
   outRefExtreme  = 0.0;
   outRefBarShift = entryBarShift;
   if(entryBarShift < 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int totalBars = iBars(_Symbol, timeframe);
   if(entryBarShift >= totalBars)
      return false;

   const datetime entryBarOpen = iTime(_Symbol, timeframe, entryBarShift);
   if(entryBarOpen == 0)
      return false;

   int shiftStartOlder = -1;
   int shiftEndNewer   = entryBarShift;
   if(windowStartInclusive > 0 &&
      M2VolumeWindowShiftRangeValid(windowStartInclusive, entryBarOpen))
   {
      shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartInclusive, true);
      shiftEndNewer   = entryBarShift;
   }

   if(shiftStartOlder < 0 || shiftStartOlder < shiftEndNewer)
   {
      shiftStartOlder = entryBarShift + LQ_TOUCH_VOL_SL_OLDER_BAR_LOOKBACK;
      shiftEndNewer   = entryBarShift;
   }

   if(shiftStartOlder >= totalBars)
      shiftStartOlder = totalBars - 1;

   for(int barShift = shiftStartOlder; barShift >= shiftEndNewer; barShift--)
   {
      if(barShift < 0 || barShift >= totalBars)
         continue;

      if(isBuy)
      {
         const double barLow = iLow(_Symbol, timeframe, barShift);
         if(outRefExtreme <= 0.0 || barLow < outRefExtreme)
         {
            outRefExtreme  = barLow;
            outRefBarShift = barShift;
         }
      }
      else
      {
         const double barHigh = iHigh(_Symbol, timeframe, barShift);
         if(outRefExtreme <= 0.0 || barHigh > outRefExtreme)
         {
            outRefExtreme  = barHigh;
            outRefBarShift = barShift;
         }
      }
   }

   if(legExtremeFloor > 0.0)
   {
      if(isBuy)
      {
         if(outRefExtreme <= 0.0 || legExtremeFloor < outRefExtreme)
         {
            outRefExtreme  = legExtremeFloor;
            outRefBarShift = entryBarShift;
         }
      }
      else
      {
         if(outRefExtreme <= 0.0 || legExtremeFloor > outRefExtreme)
         {
            outRefExtreme  = legExtremeFloor;
            outRefBarShift = entryBarShift;
         }
      }
   }

   return outRefExtreme > 0.0;
}

//+------------------------------------------------------------------+
bool ResolveTouchLegVolumeBarEntryAndSl(const bool isBuy, const int barShift,
                                         const datetime slWindowStartOpen, const int huntIndex,
                                         bool &outUseMarketOrder, double &outEntryPrice,
                                         double &outStopLossPrice, string &outFailReason)
{
   outUseMarketOrder  = false;
   outEntryPrice      = 0.0;
   outStopLossPrice   = 0.0;
   outFailReason      = "";

   if(barShift < 0)
   {
      outFailReason = "barShift invalid";
      return false;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const double barLow     = iLow(_Symbol, timeframe, barShift);
   const double barHigh    = iHigh(_Symbol, timeframe, barShift);
   if(barHigh <= barLow)
   {
      outFailReason = "vol bar range invalid";
      return false;
   }

   if(InputTouchVolEntryOffsetPercentChart < 0.0)
   {
      outFailReason = "InputTouchVolEntryOffsetPercentChart invalid";
      return false;
   }

   if(InputTouchVolSlBufferPercentChart < 0.0)
   {
      outFailReason = "InputTouchVolSlBufferPercentChart invalid";
      return false;
   }

   const double bufferPrice = M2TouchVolSlBufferPrice(barShift);
   if(InputTouchVolSlBufferPercentChart > 0.0 && bufferPrice <= 0.0)
   {
      outFailReason = "SL chart height invalid for positive buffer %";
      return false;
   }

   datetime slScanStartOpen = slWindowStartOpen;
   double   legExtremeFloor = 0.0;
   if(huntIndex >= 0 && huntIndex < V2_MAX_HUNT_SESSIONS)
   {
      double   legLow  = 0.0;
      double   legHigh = 0.0;
      datetime legStartTime = 0;
      datetime legEndTime   = 0;
      if(V2TryGetOppositeM2LegExtentsForTouch(huntIndex, legLow, legHigh, legStartTime, legEndTime))
      {
         legExtremeFloor = isBuy ? legLow : legHigh;
         if(legStartTime > 0 && (slScanStartOpen == 0 || legStartTime < slScanStartOpen))
            slScanStartOpen = legStartTime;
      }
   }

   double slRefExtreme = 0.0;
   int    slRefBarShift = barShift;
   if(!M2TouchVolSlReferenceExtreme(isBuy, barShift, slScanStartOpen, legExtremeFloor,
                                    slRefExtreme, slRefBarShift))
   {
      outFailReason = "SL reference extreme invalid";
      return false;
   }

   const double limitLevel = M2TouchVolLimitEntryPrice(isBuy, barShift, barLow, barHigh);
   if(limitLevel <= 0.0)
   {
      outFailReason = "limit entry invalid (check entry offset % and chart range)";
      return false;
   }

   if(isBuy)
      outStopLossPrice = NormalizeDouble(slRefExtreme - bufferPrice, _Digits);
   else
      outStopLossPrice = NormalizeDouble(slRefExtreme + bufferPrice, _Digits);

   outUseMarketOrder = false;
   outEntryPrice     = limitLevel;

   if(!ApplyTouchVolMinimumSlDistance(isBuy, outEntryPrice, outStopLossPrice))
   {
      outFailReason = StringFormat("entry/SL side invalid after minPts=%d entry=%.5f sl=%.5f",
                                   TouchVolEffectiveMinSlPoints(), outEntryPrice, outStopLossPrice);
      return false;
   }

   if(isBuy && outEntryPrice <= outStopLossPrice)
   {
      outFailReason = StringFormat("buy entry<=SL entry=%.5f sl=%.5f", outEntryPrice, outStopLossPrice);
      return false;
   }
   if(!isBuy && outEntryPrice >= outStopLossPrice)
   {
      outFailReason = StringFormat("sell entry>=SL entry=%.5f sl=%.5f", outEntryPrice, outStopLossPrice);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
bool H4TryGetLegLastDecentMovementBarOpen(const datetime legStartTime, const datetime legProgressEnd,
                                           const int swingDirection, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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

   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
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
         g_h4LegVolumeBreaches[i].swingDirection    = swingDirection;
         g_h4LegVolumeBreaches[i].breachLevelPrice    = breachLevel;
         g_h4LegVolumeBreaches[i].volumeBarOpenTime = volumeBarOpenTime;
         return;
      }
      if(g_h4LegVolumeBreaches[i].legStartTime == legStartTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection)
      {
         if(legEndTime > 0)
            g_h4LegVolumeBreaches[i].legEndTime = legEndTime;
         g_h4LegVolumeBreaches[i].breachLevelPrice    = breachLevel;
         g_h4LegVolumeBreaches[i].volumeBarOpenTime = volumeBarOpenTime;
         return;
      }
      if(legEndTime > 0 && g_h4LegVolumeBreaches[i].legEndTime == legEndTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection)
      {
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
      g_h4LegVolumeBreachCount++;
      return;
   }

   for(int shiftIndex = 1; shiftIndex < H4_LEG_VOLUME_BREACH_CAPACITY; shiftIndex++)
      g_h4LegVolumeBreaches[shiftIndex - 1] = g_h4LegVolumeBreaches[shiftIndex];

   const int lastIndex = H4_LEG_VOLUME_BREACH_CAPACITY - 1;
   g_h4LegVolumeBreaches[lastIndex].legStartTime        = legStartTime;
   g_h4LegVolumeBreaches[lastIndex].legEndTime          = legEndTime;
   g_h4LegVolumeBreaches[lastIndex].swingDirection       = swingDirection;
   g_h4LegVolumeBreaches[lastIndex].breachLevelPrice     = breachLevel;
   g_h4LegVolumeBreaches[lastIndex].volumeBarOpenTime  = volumeBarOpenTime;
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

   const datetime lastClosedOpen = iTime(_Symbol, InputH4NarrativeTimeframe, lastClosedBarShift);
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
      const bool hasPrevLeg = (g_h4Swing.swingHistoryCount > 1);
      if(hasPrevLeg)
         prevLeg = g_h4Swing.swingHistory[g_h4Swing.swingHistoryCount - 2];

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
   if(g_h4Swing.currentSwingLeg.swingDirection == 0 || g_h4Swing.currentSwingLeg.legStartTime == 0)
   {
      H4ResetActiveLegVolumeBreachTrack();
      return;
   }
   H4OnH4ActiveLegStarted(g_h4Swing);
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

   const int barShift = iBarShift(_Symbol, InputH4NarrativeTimeframe, barOpenTime, false);
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

   for(int legIndex = 0; legIndex < g_h4Swing.swingHistoryCount; legIndex++)
   {
      const Swing lastLeg = g_h4Swing.swingHistory[legIndex];
      Swing       prevLeg;
      ZeroMemory(prevLeg);
      const bool hasPrevLeg = (legIndex > 0);

      if(hasPrevLeg)
         prevLeg = g_h4Swing.swingHistory[legIndex - 1];

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
   if(!H4LqChartDrawEnabled(InputDrawH4SwingLegVisuals) || legStartTime == 0 || swingDirection == 0 ||
      volumeBarOpenTime == 0 || breachLevel <= 0.0)
      return;

   const color rayColor = (swingDirection == 1)
                          ? H4_VOLUME_BREACH_RAY_COLOR_UP
                          : H4_VOLUME_BREACH_RAY_COLOR_DOWN;

   const string objName =
      ChartObjectNamePrefixH4VolumeBreachRay + IntegerToString((long)legStartTime);

   const int h4PeriodSec = (int)PeriodSeconds(InputH4NarrativeTimeframe);
   if(h4PeriodSec < 1)
      return;

   const datetime timeEnd = volumeBarOpenTime + (datetime)h4PeriodSec;

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
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);
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
   if(!H4LqChartDrawEnabled(InputDrawH4SwingLegVisuals))
   {
      ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);
      return;
   }

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      const H4LegVolumeBreachRecord rec = g_h4LegVolumeBreaches[i];
      if(rec.legStartTime == 0 || rec.swingDirection == 0 || rec.breachLevelPrice <= 0.0)
         continue;

      if(rec.legEndTime == 0 &&
         (g_h4Swing.currentSwingLeg.legStartTime != rec.legStartTime ||
          g_h4Swing.currentSwingLeg.swingDirection != rec.swingDirection))
      {
         DeleteH4VolumeBreachLevelRay(rec.legStartTime);
         continue;
      }

      if(IsH4VolumeBreachLevelAlreadyBreached(rec.swingDirection, rec.breachLevelPrice))
      {
         DeleteH4VolumeBreachLevelRay(rec.legStartTime);
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
bool IsH4VolumeBreachLevelAlreadyBreached(const int swingDirection, const double breachLevel)
{
   if(swingDirection == 0 || breachLevel <= 0.0)
      return false;

   for(int i = 0; i < g_h4LegLiquidityBreachCount; i++)
   {
      if(g_h4LegLiquidityBreaches[i].swingDirection == swingDirection &&
         H4VolumeBreachLevelsMatch(g_h4LegLiquidityBreaches[i].breachLevelPrice, breachLevel))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void RememberH4VolumeBreachLevelSwept(const datetime legEndTime, const int swingDirection,
                                       const double breachLevel)
{
   if(legEndTime == 0 || swingDirection == 0 || breachLevel <= 0.0)
      return;

   if(IsH4VolumeBreachLevelAlreadyBreached(swingDirection, breachLevel))
      return;

   if(g_h4LegLiquidityBreachCount < H4LegLiquidityBreachMemoryCapacity)
   {
      const int index = g_h4LegLiquidityBreachCount;
      g_h4LegLiquidityBreaches[index].legEndTime        = legEndTime;
      g_h4LegLiquidityBreaches[index].swingDirection   = swingDirection;
      g_h4LegLiquidityBreaches[index].breachLevelPrice = breachLevel;
      g_h4LegLiquidityBreachCount++;
      return;
   }

   for(int shiftIndex = 1; shiftIndex < H4LegLiquidityBreachMemoryCapacity; shiftIndex++)
      g_h4LegLiquidityBreaches[shiftIndex - 1] = g_h4LegLiquidityBreaches[shiftIndex];

   const int lastIndex = H4LegLiquidityBreachMemoryCapacity - 1;
   g_h4LegLiquidityBreaches[lastIndex].legEndTime        = legEndTime;
   g_h4LegLiquidityBreaches[lastIndex].swingDirection   = swingDirection;
   g_h4LegLiquidityBreaches[lastIndex].breachLevelPrice = breachLevel;
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
      iBarShift(_Symbol, InputH4NarrativeTimeframe, levelFormedOpenTime, false);
   if(formationShift < 0)
      return false;

   for(int barShift = formationShift - 1; barShift >= 1; barShift--)
   {
      if(swingDirection == 1)
      {
         const double barLow = iLow(_Symbol, InputH4NarrativeTimeframe, barShift);
         if(barLow > 0.0 && barLow < breachLevel - eps)
            return true;
      }
      else if(swingDirection == -1)
      {
         const double barHigh = iHigh(_Symbol, InputH4NarrativeTimeframe, barShift);
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
      const H4LegVolumeBreachRecord rec = g_h4LegVolumeBreaches[i];
      if(rec.swingDirection == 0 || rec.breachLevelPrice <= 0.0)
         continue;

      const bool isActiveLeg = (rec.legEndTime == 0);
      if(isActiveLeg)
         continue;

      if(!IsH4LegVolumeBreachActiveInBufferWindow(rec.legEndTime, rec.swingDirection))
         continue;

      if(IsH4VolumeBreachLevelAlreadyBreached(rec.swingDirection, rec.breachLevelPrice))
         continue;

      datetime scanFromOpenTime = rec.volumeBarOpenTime;
      if(scanFromOpenTime == 0)
         scanFromOpenTime = rec.legEndTime;

      if(!WasH4VolumeBreachLevelViolatedSinceFormation(rec.swingDirection, rec.breachLevelPrice,
                                                        scanFromOpenTime, pointSize))
         continue;

      RememberH4VolumeBreachLevelSwept(rec.legEndTime, rec.swingDirection, rec.breachLevelPrice);
      if(H4LqLoggingEnabled())
      {
         LogHuntEvent("BREACH_SWEPT",
                      StringFormat("H4 %s closed leg %s level=%.5f volBar=%s price %s level — skip hunt",
                                   rec.swingDirection == 1 ? "up" : "down",
                                   TimeToString(rec.legEndTime, TIME_DATE | TIME_MINUTES),
                                   rec.breachLevelPrice,
                                   TimeToString(scanFromOpenTime, TIME_DATE | TIME_MINUTES),
                                   rec.swingDirection == 1 ? "below" : "above"));
      }
   }
}

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
//| Replay one closed H4 bar into swingState; append completed legs (no hunt side effects). |
//+------------------------------------------------------------------+
void ProcessH4SwingStepReplay(SwingState &swingState, const int lastClosedBarShift,
                               H4ReplayLeg &replayLegs[], int &replayLegCount,
                               const double anchorMultiplier, const bool useWickAndBodyForDecent)
{
   const ENUM_TIMEFRAMES timeframe = InputH4NarrativeTimeframe;
   const int         sh            = lastClosedBarShift;

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
   closedSwingLeg.legEndTime = iTime(_Symbol, timeframe, sh);
   TryPushH4ReplayLeg(replayLegs, replayLegCount, closedSwingLeg);

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
//| Completed H4 swing legs in lookback: up-leg high / down-leg low pivots only.   |
//| Pivot up high: legHigh beats every newer up-leg high; pivot down low: vice versa. |
//+------------------------------------------------------------------+
void RebuildH4LiquidityPivotLevels()
{
   g_h4DescHighPivotCount = 0;
   g_h4AscLowPivotCount   = 0;

   if(InputH4LiquidityPivotLookbackBars < 2)
      return;

   const int barsTotal = iBars(_Symbol, InputH4NarrativeTimeframe);
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
      ProcessH4SwingStepReplay(replaySwing, shift, replayLegs, replayLegCount,
                                H4_BREACH_ANCHOR_MULTIPLIER, true);

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
bool H4BreachImpulseCancelZonePrices(const bool expectBullishFvgHunt, const double breachLevel,
                                       double &outZoneLow, double &outZoneHigh,
                                       double &outCancelLimitPrice)
{
   outZoneLow = 0.0;
   outZoneHigh = 0.0;
   outCancelLimitPrice = 0.0;

   if(H4_BREACH_BUFFER_PERCENT_FAR <= 0.0 || breachLevel <= 0.0)
      return false;

   const double referenceHeight = ReferenceChartHeightForH4BreachBuffer();
   if(referenceHeight <= 0.0)
      return false;

   const double farOffset = referenceHeight * (H4_BREACH_BUFFER_PERCENT_FAR / 100.0);
   if(expectBullishFvgHunt)
   {
      outZoneHigh         = breachLevel;
      outZoneLow          = breachLevel - farOffset;
      outCancelLimitPrice = outZoneLow;
   }
   else
   {
      outZoneLow          = breachLevel;
      outZoneHigh         = breachLevel + farOffset;
      outCancelLimitPrice = outZoneHigh;
   }
   return true;
}

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

//+------------------------------------------------------------------+
bool TryDetectM2BreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap,
                                                 double &outBosLegLevelPrice)
{
   outExpectsBullishFairValueGap = false;
   outBosLegLevelPrice = 0.0;
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
         outExpectsBullishFairValueGap = false;
         outBosLegLevelPrice           = swingLegHighPrice;
         return true;
      }
      break;
   }

   for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m2Swing.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double swingLegLowPrice = g_m2Swing.swingHistory[historyIndex].legLowPrice;
      if(closePrice < swingLegLowPrice - pointSize && prevClose >= swingLegLowPrice - pointSize)
      {
         outExpectsBullishFairValueGap = true;
         outBosLegLevelPrice           = swingLegLowPrice;
         return true;
      }
      break;
   }
   return false;
}

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
double M2FvgStopBufferPrice()
{
   const double chartHeight = ReferenceChartHeightForFairValueGapFilterM2();
   if(chartHeight <= 0.0)
      return 0.0;
   return chartHeight * (LQ_STOP_BUFFER_PERCENT_CHART / 100.0);
}

//+------------------------------------------------------------------+
double M2TouchVolSlBufferPrice(const int barShift)
{
   if(InputTouchVolSlBufferPercentChart <= 0.0)
      return 0.0;

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(barShift, InputChartRangeBarCount);
   if(chartHeight <= 0.0)
      return 0.0;
   return chartHeight * (InputTouchVolSlBufferPercentChart / 100.0);
}

//+------------------------------------------------------------------+
double M2TouchVolEntryOffsetPrice(const int barShift)
{
   if(InputTouchVolEntryOffsetPercentChart <= 0.0)
      return 0.0;

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(barShift, InputChartRangeBarCount);
   if(chartHeight <= 0.0)
      return 0.0;
   return chartHeight * (InputTouchVolEntryOffsetPercentChart / 100.0);
}

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
//| Buy hunt: vol bar low + N% chart height. Sell hunt: vol bar high − N%. |
//+------------------------------------------------------------------+
double M2TouchVolLimitEntryPrice(const bool isBuy, const int barShift,
                                  const double barLow, const double barHigh)
{
   if(barShift < 0 || barHigh <= barLow)
      return 0.0;

   const double entryOffset = M2TouchVolEntryOffsetPrice(barShift);
   const double limitRaw = isBuy ? barLow + entryOffset : barHigh - entryOffset;
   return NormalizeDouble(limitRaw, _Digits);
}

//+------------------------------------------------------------------+
//| Scan opposite M2 leg backward for most recent decent impulse; return origin bar shift. |
//+------------------------------------------------------------------+
bool M2FindImpulseBaseBar(const datetime legStartTime, const datetime legEndTime, const int legDirection,
                           int &outBarShift)
{
   outBarShift = -1;
   if(legStartTime == 0 || legDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   int shiftStart = iBarShift(_Symbol, timeframe, legStartTime, true);
   int shiftEnd   = (legEndTime == 0) ? 1 : iBarShift(_Symbol, timeframe, legEndTime, true);

   if(shiftEnd < 1)
      shiftEnd = 1;
   if(shiftStart < 0)
      return false;

   if(shiftStart < shiftEnd)
   {
      int tmp = shiftStart;
      shiftStart = shiftEnd;
      shiftEnd = tmp;
   }

   int decentShift = -1;
   for(int i = shiftEnd; i <= shiftStart; i++)
   {
      if(M2BarHasDecentMovementForLegDirection(i, legDirection))
      {
         decentShift = i;
         break;
      }
   }

   if(decentShift == -1)
      return false;

   int originShift = decentShift;
   for(int i = decentShift + 1; i <= shiftStart; i++)
   {
      const double open  = iOpen(_Symbol, timeframe, i);
      const double close = iClose(_Symbol, timeframe, i);
      const int candleDir = (close > open) ? 1 : ((close < open) ? -1 : 0);

      if(candleDir == -legDirection)
         break;

      originShift = i;
   }

   outBarShift = originShift;
   return true;
}

//+------------------------------------------------------------------+
//| 61.8% OTE on full opposite M2 leg range (down leg: from low; up leg: from high). |
//+------------------------------------------------------------------+
double V2TouchLevelFromLegExtreme(const int oppositeM2LegDirection, const double legLowPrice,
                                   const double legHighPrice)
{
   if(legLowPrice <= 0.0 || legHighPrice <= 0.0 || legHighPrice <= legLowPrice)
      return 0.0;

   const double legRange = legHighPrice - legLowPrice;
   double fibLevel = 0.0;

   if(oppositeM2LegDirection == -1)
   {
      // Opposite down leg: 61.8% up from structural leg low → touch near leg high
      fibLevel = legLowPrice + (legRange * 0.9);
   }
   else if(oppositeM2LegDirection == 1)
   {
      // Opposite up leg: 61.8% down from structural leg high → touch near leg low
      fibLevel = legHighPrice - (legRange * 0.9);
   }
   else
      return 0.0;

   return NormalizeDouble(fibLevel, _Digits);
}

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

//+------------------------------------------------------------------+
void V2ApplyTouchLevelFromM2Leg(const int huntIndex, const double legLow, const double legHigh,
                                 const string logContext, const bool allowRecalc)
{
   if(!g_v2Hunts[huntIndex].active)
      return;
   if(!allowRecalc && g_v2Hunts[huntIndex].touchLevelReady)
      return;

   const double newLevel =
      V2TouchLevelFromLegExtreme(V2OppositeM2LegDirectionForHunt(huntIndex), legLow, legHigh);
   if(newLevel <= 0.0)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize * 2.0 : 0.00002);
   const double oldLevel  = g_v2Hunts[huntIndex].touchLevel;
   const bool hadTouch    = g_v2Hunts[huntIndex].touchLevelReady;

   if(hadTouch && MathAbs(newLevel - oldLevel) <= eps)
      return;

   if(hadTouch && allowRecalc)
   {
      const double currentPrice = iClose(_Symbol, InputM2NarrativeTimeframe, 1);
      if(currentPrice > 0.0)
      {
         const bool bullishHunt = V2HuntExpectsBullishFvg(huntIndex);
         if(bullishHunt && newLevel < currentPrice - eps)
         {
            g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime =
               iTime(_Symbol, InputM2NarrativeTimeframe, 1);
            V2LogHuntEvent(huntIndex, "TOUCH_RECALC_SKIP",
                           StringFormat("keep lvl=%.5f new=%.5f < close=%.5f (bull hunt) bar=%s",
                                        oldLevel, newLevel, currentPrice,
                                        TimeToString(g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime,
                                                     TIME_DATE | TIME_MINUTES)));
            return;
         }
         if(!bullishHunt && newLevel > currentPrice + eps)
         {
            g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime =
               iTime(_Symbol, InputM2NarrativeTimeframe, 1);
            V2LogHuntEvent(huntIndex, "TOUCH_RECALC_SKIP",
                           StringFormat("keep lvl=%.5f new=%.5f > close=%.5f (bear hunt) bar=%s",
                                        oldLevel, newLevel, currentPrice,
                                        TimeToString(g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime,
                                                     TIME_DATE | TIME_MINUTES)));
            return;
         }
      }
   }

   g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime = 0;
   g_v2Hunts[huntIndex].touchHitVolumeRejectLatch    = false;
   g_v2Hunts[huntIndex].touchLevel      = newLevel;
   g_v2Hunts[huntIndex].touchLevelReady = true;
   V2DrawTouchPointLine(huntIndex);

   const string eventName = (hadTouch ? "V2_TOUCH_RECALC" : "V2_STORE_TOUCH");
   V2LogHuntEvent(huntIndex, eventName,
                  StringFormat("lvl=%.5f%s legL=%.5f legH=%.5f buf2%%rng=%.5f (%s)",
                               newLevel,
                               hadTouch ? StringFormat(" was=%.5f", oldLevel) : "",
                               legLow, legHigh, M2FvgStopBufferPrice(), logContext));
}

//+------------------------------------------------------------------+
void V2ApplyTouchLevelFromOppositeLegWindow(const int huntIndex, const datetime legStartTime,
                                             const datetime legEndTime, const double legLow,
                                             const double legHigh, const string logContext,
                                             const bool allowRecalc)
{
   V2ApplyTouchLevelFromM2Leg(huntIndex, legLow, legHigh, logContext, allowRecalc);
}

//+------------------------------------------------------------------+
void V2TryLockTouchLevelFromM2Leg(const int huntIndex, const double legLow, const double legHigh,
                                    const string logContext)
{
   V2ApplyTouchLevelFromM2Leg(huntIndex, legLow, legHigh, logContext, false);
}

//+------------------------------------------------------------------+
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
bool HasOurTradeForFormation(const datetime formationTime)
{
   const string tag = IntegerToString((long)formationTime);

   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), tag) >= 0)
         return true;
   }

   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), tag) >= 0)
         return true;
   }
   return false;
}

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
//| Buy: bull M2 BOS (close cross above up-leg high) with level strictly between entry and TP3. |
//| Sell: bear M2 BOS (close cross below down-leg low) with level strictly between TP3 and entry. |
//+------------------------------------------------------------------+
bool SameDirectionM2BosBetweenEntryAndTp3Since(const bool isBuy, const double entryPrice,
                                                const double tp3Level, const datetime sinceTime)
{
   if(entryPrice <= 0.0 || tp3Level <= 0.0 || sinceTime == 0)
      return false;
   if(g_m2Swing.swingHistoryCount < 1)
      return false;

   const double zoneLow  = MathMin(entryPrice, tp3Level);
   const double zoneHigh = MathMax(entryPrice, tp3Level);
   if(zoneHigh - zoneLow <= 0.0)
      return false;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double tolerance = (pointSize > 0.0 ? pointSize : 0.00001);

   for(int historyIndex = 0; historyIndex < g_m2Swing.swingHistoryCount; historyIndex++)
   {
      const int legDirection = g_m2Swing.swingHistory[historyIndex].swingDirection;
      double brokenLevel     = 0.0;

      if(isBuy)
      {
         if(legDirection != 1)
            continue;
         brokenLevel = g_m2Swing.swingHistory[historyIndex].legHighPrice;
         if(brokenLevel <= zoneLow + tolerance || brokenLevel >= zoneHigh - tolerance)
            continue;
      }
      else
      {
         if(legDirection != -1)
            continue;
         brokenLevel = g_m2Swing.swingHistory[historyIndex].legLowPrice;
         if(brokenLevel <= zoneLow + tolerance || brokenLevel >= zoneHigh - tolerance)
            continue;
      }

      datetime scanFromTime = g_m2Swing.swingHistory[historyIndex].legEndTime;
      if(scanFromTime < sinceTime)
         scanFromTime = sinceTime;

      int barShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, scanFromTime, true);
      if(barShift < 1)
         barShift = 1;

      const int maxShift = iBars(_Symbol, InputM2NarrativeTimeframe) - 2;
      if(maxShift < 1)
         continue;

      for(int shift = barShift; shift >= 1; shift--)
      {
         if(shift + 1 > maxShift)
            continue;

         const double closePrice = iClose(_Symbol, InputM2NarrativeTimeframe, shift);
         const double prevClose  = iClose(_Symbol, InputM2NarrativeTimeframe, shift + 1);

         if(isBuy)
         {
            if(closePrice > brokenLevel + tolerance && prevClose <= brokenLevel + tolerance)
               return true;
         }
         else if(closePrice < brokenLevel - tolerance && prevClose >= brokenLevel - tolerance)
            return true;
      }
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

//+------------------------------------------------------------------+
bool V2IsHuntSessionStillActive(const datetime huntSessionId)
{
   const int huntIndex = V2FindHuntSlotBySessionId(huntSessionId);
   return (huntIndex >= 0 && g_v2Hunts[huntIndex].active);
}

//+------------------------------------------------------------------+
bool OrderCommentBelongsToActiveHunt(const string orderComment)
{
   for(int huntIndex = 0; huntIndex < V2_MAX_HUNT_SESSIONS; huntIndex++)
   {
      if(!g_v2Hunts[huntIndex].active)
         continue;
      if(StringFind(orderComment, V2HuntTradeCommentPrefix(g_v2Hunts[huntIndex].sessionId)) == 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
bool FvgFormationBarBeyondChartRange(const datetime formationTime, int &outBarShift)
{
   outBarShift = -1;
   if(formationTime == 0)
      return false;

   outBarShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, true);
   if(outBarShift < 0)
      return true;

   const int maxShift = InputChartRangeBarCount;
   if(maxShift <= 0)
      return false;

   return (outBarShift > maxShift);
}

//+------------------------------------------------------------------+
void V2ClearHuntPreEntryWatchForHunt(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;

   g_v2Hunts[huntIndex].tradeOrdersActive      = false;
   g_v2Hunts[huntIndex].ordersFvgFormationTime = 0;
   g_v2Hunts[huntIndex].tradeIsBuy             = false;
   g_v2Hunts[huntIndex].tradeEntryPrice        = 0.0;
   g_v2Hunts[huntIndex].tradeTp1Price          = 0.0;
   g_v2Hunts[huntIndex].preEntryCancelTpLevel  = 0.0;
   g_v2Hunts[huntIndex].firstOppBosMgmtDone    = false;
}

//+------------------------------------------------------------------+
void V2ClearHuntTradeOrdersActiveForSession(const datetime huntSessionId)
{
   const int huntIndex = V2FindHuntSlotBySessionId(huntSessionId);
   if(huntIndex < 0)
      return;

   V2ClearHuntPreEntryWatchForHunt(huntIndex);
}

//+------------------------------------------------------------------+
bool V2CollectUniquePendingHuntSessionIds(datetime &outSessionIds[], const int maxSessions)
{
   ArrayResize(outSessionIds, 0);
   if(maxSessions <= 0)
      return false;

   int count = 0;
   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(!IsOurHuntPendingOrderTicket(ticket))
         continue;

      datetime sessionId = 0;
      if(!ParseHuntSessionIdFromTradeComment(OrderGetString(ORDER_COMMENT), sessionId))
         continue;

      bool alreadyListed = false;
      for(int i = 0; i < count; i++)
      {
         if(outSessionIds[i] == sessionId)
         {
            alreadyListed = true;
            break;
         }
      }
      if(alreadyListed)
         continue;

      if(count >= maxSessions)
         break;

      ArrayResize(outSessionIds, count + 1);
      outSessionIds[count++] = sessionId;
   }

   return (count > 0);
}

//+------------------------------------------------------------------+
bool V2TrySyncPreEntryWatchForSession(const datetime sessionId, const int huntIndex,
                                      int &outPendingCount, bool &outIsBuy,
                                      double &outTp3Level, double &outEntryPrice)
{
   outPendingCount = 0;
   outIsBuy        = false;
   outTp3Level     = 0.0;
   outEntryPrice   = 0.0;
   if(sessionId == 0)
      return false;

   const string prefix = V2HuntTradeCommentPrefix(sessionId);
   double storedTp3    = 0.0;
   if(huntIndex >= 0 && huntIndex < V2_MAX_HUNT_SESSIONS)
      storedTp3 = g_v2Hunts[huntIndex].preEntryCancelTpLevel;
   bool   isBuy      = (huntIndex >= 0 ? g_v2Hunts[huntIndex].tradeIsBuy : false);
   double entryPrice = (huntIndex >= 0 ? g_v2Hunts[huntIndex].tradeEntryPrice : 0.0);
   bool   haveSide   = false;

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
      if(StringFind(comment, prefix) != 0)
         continue;

      outPendingCount++;
      const double orderTp    = OrderGetDouble(ORDER_TP);
      const double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      const bool orderIsBuy   = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP ||
                                 orderType == ORDER_TYPE_BUY_STOP_LIMIT);

      if(!haveSide)
      {
         isBuy       = orderIsBuy;
         entryPrice  = orderPrice;
         haveSide    = true;
      }

      if(StringFind(comment, "_TP3_") >= 0 && orderTp > 0.0)
         storedTp3 = orderTp;
      else if(orderTp > 0.0)
      {
         if(orderIsBuy)
            storedTp3 = (storedTp3 <= 0.0 ? orderTp : MathMax(storedTp3, orderTp));
         else
            storedTp3 = (storedTp3 <= 0.0 ? orderTp : MathMin(storedTp3, orderTp));
      }
   }

   if(outPendingCount <= 0)
      return false;

   outIsBuy      = isBuy;
   outEntryPrice = entryPrice;
   outTp3Level   = storedTp3;

   if(huntIndex >= 0 && huntIndex < V2_MAX_HUNT_SESSIONS)
   {
      g_v2Hunts[huntIndex].tradeIsBuy      = isBuy;
      g_v2Hunts[huntIndex].tradeEntryPrice = entryPrice;
      if(storedTp3 > 0.0)
         g_v2Hunts[huntIndex].preEntryCancelTpLevel = storedTp3;
   }

   return (storedTp3 > 0.0);
}

//+------------------------------------------------------------------+
bool V2TrySyncPreEntryWatchForHunt(const int huntIndex, int &outPendingCount)
{
   outPendingCount = 0;
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return false;

   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   if(sessionId == 0)
      return false;

   bool   isBuy      = false;
   double tp3Level   = 0.0;
   double entryPrice = 0.0;
   return V2TrySyncPreEntryWatchForSession(sessionId, huntIndex, outPendingCount,
                                           isBuy, tp3Level, entryPrice);
}

//+------------------------------------------------------------------+
void V2RefreshGlobalHuntTradeWatchFromSessions()
{
   bool refreshed = false;
   for(int huntIndex = 0; huntIndex < V2_MAX_HUNT_SESSIONS; huntIndex++)
   {
      int pendingCount = 0;
      if(!V2TrySyncPreEntryWatchForHunt(huntIndex, pendingCount) || pendingCount <= 0)
         continue;

      g_huntTradeOrdersActive           = true;
      g_huntOrdersFvgFormationTime      = g_v2Hunts[huntIndex].ordersFvgFormationTime;
      g_huntTradeIsBuy                  = g_v2Hunts[huntIndex].tradeIsBuy;
      g_huntTradeEntryPrice             = g_v2Hunts[huntIndex].tradeEntryPrice;
      g_huntPreEntryCancelTpLevel       = g_v2Hunts[huntIndex].preEntryCancelTpLevel;
      g_huntTradeSessionCommentPrefix   = V2HuntTradeCommentPrefix(g_v2Hunts[huntIndex].sessionId);
      refreshed                         = true;
      break;
   }

   if(!refreshed && !HasOurHuntTradeOpenPosition())
      ResetHuntTradeState();
}

//+------------------------------------------------------------------+
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
bool TrySyncHuntPreEntryWatchFromPendingOrders(int &outPendingCount)
{
   outPendingCount = 0;
   for(int huntIndex = 0; huntIndex < V2_MAX_HUNT_SESSIONS; huntIndex++)
   {
      int sessionPending = 0;
      if(V2TrySyncPreEntryWatchForHunt(huntIndex, sessionPending))
         outPendingCount += sessionPending;
   }

   if(outPendingCount <= 0)
      return false;

   V2RefreshGlobalHuntTradeWatchFromSessions();
   return (g_huntPreEntryCancelTpLevel > 0.0);
}

//+------------------------------------------------------------------+
bool HuntMarketReachedTakeProfitLevel(const bool isBuy, const double takeProfitLevel)
{
   if(takeProfitLevel <= 0.0)
      return false;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double tolerance = (pointSize > 0.0 ? pointSize : 0.00001);

   const double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double highM1 = iHigh(_Symbol, PERIOD_M1, 0);
   const double lowM1  = iLow(_Symbol, PERIOD_M1, 0);
   const double highM2 = iHigh(_Symbol, InputM2NarrativeTimeframe, 0);
   const double lowM2  = iLow(_Symbol, InputM2NarrativeTimeframe, 0);

   if(isBuy)
   {
      if(ask >= takeProfitLevel - tolerance)
         return true;
      if(bid >= takeProfitLevel - tolerance)
         return true;
      if(highM1 >= takeProfitLevel - tolerance)
         return true;
      if(highM2 >= takeProfitLevel - tolerance)
         return true;
      return false;
   }

   if(bid <= takeProfitLevel + tolerance)
      return true;
   if(ask <= takeProfitLevel + tolerance)
      return true;
   if(lowM1 <= takeProfitLevel + tolerance)
      return true;
   if(lowM2 <= takeProfitLevel + tolerance)
      return true;
   return false;
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
bool TryGetHuntTradeSlAndTp1(double &outStopLossPrice, double &outTp1Price)
{
   outStopLossPrice = 0.0;
   outTp1Price      = 0.0;

   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(!IsOurHuntPendingOrderTicket(ticket))
         continue;
      const string comment = OrderGetString(ORDER_COMMENT);
      if(!HuntTradeCommentIsOvTpIndex(comment, 1))
         continue;
      outStopLossPrice = OrderGetDouble(ORDER_SL);
      outTp1Price      = OrderGetDouble(ORDER_TP);
      break;
   }

   if(outTp1Price <= 0.0)
   {
      for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
      {
         if(PositionGetSymbol(positionIndex) != _Symbol)
            continue;
         const ulong ticket = PositionGetTicket(positionIndex);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         if(!HuntTradeCommentIsOurs(PositionGetString(POSITION_COMMENT)))
            continue;
         const string comment = PositionGetString(POSITION_COMMENT);
         if(!HuntTradeCommentIsOvTpIndex(comment, 1))
            continue;
         outStopLossPrice = PositionGetDouble(POSITION_SL);
         outTp1Price      = PositionGetDouble(POSITION_TP);
         break;
      }
   }

   return (outStopLossPrice > 0.0 && outTp1Price > 0.0);
}

//+------------------------------------------------------------------+
bool BosBreakInsideSlTp1Zone(const bool isBuy, const double stopLossPrice, const double tp1Price,
                             const double bosBrokenLevel)
{
   if(stopLossPrice <= 0.0 || tp1Price <= 0.0 || bosBrokenLevel <= 0.0)
      return false;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double tolerance = (pointSize > 0.0 ? pointSize : 0.00001);
   const double zoneLow   = MathMin(stopLossPrice, tp1Price);
   const double zoneHigh  = MathMax(stopLossPrice, tp1Price);

   if(bosBrokenLevel < zoneLow - tolerance || bosBrokenLevel > zoneHigh + tolerance)
      return false;

   if(isBuy)
      return (bosBrokenLevel > stopLossPrice + tolerance && bosBrokenLevel < tp1Price - tolerance);
   return (bosBrokenLevel > tp1Price + tolerance && bosBrokenLevel < stopLossPrice - tolerance);
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
void TrailHuntTradeStopOnSameDirectionM2Bos(const bool isBuy, const double bosBrokenLevel)
{
   if(!InputEnableBosMoveSlAndTp)
      return;

   if(g_m2Swing.currentSwingLeg.swingDirection == 0)
      return;

   double stopLossPrice = 0.0;
   double tp1Price      = 0.0;
   if(TryGetHuntTradeSlAndTp1(stopLossPrice, tp1Price) &&
      BosBreakInsideSlTp1Zone(isBuy, stopLossPrice, tp1Price, bosBrokenLevel))
   {
      LogHuntEvent("TRADE_SL_TRAIL",
                   StringFormat("skip — same-dir BOS lvl=%.5f inside SL–TP1 (sl=%.5f tp1=%.5f)",
                                bosBrokenLevel, stopLossPrice, tp1Price));
      return;
   }

   const double bufferPrice = M2FvgStopBufferPrice();
   if(bufferPrice <= 0.0)
      return;

   double newStopLoss = 0.0;
   if(isBuy)
      newStopLoss = NormalizeDouble(g_m2Swing.currentSwingLeg.legLowPrice - bufferPrice, _Digits);
   else
      newStopLoss = NormalizeDouble(g_m2Swing.currentSwingLeg.legHighPrice + bufferPrice, _Digits);

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();

   int modifiedCount = 0;
   int skippedCount  = 0;
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
      if(!HuntTradeCommentIsOurs(comment))
         continue;

      const double currentSl = PositionGetDouble(POSITION_SL);
      const double currentTp = PositionGetDouble(POSITION_TP);
      const bool   posIsBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      if(posIsBuy != isBuy)
         continue;

      if(isBuy)
      {
         if(currentSl > 0.0 && newStopLoss <= currentSl)
         {
            skippedCount++;
            continue;
         }
      }
      else
      {
         if(currentSl > 0.0 && newStopLoss >= currentSl)
         {
            skippedCount++;
            continue;
         }
      }

      if(!StopLossModifyAllowed(posIsBuy, newStopLoss, currentTp))
      {
         skippedCount++;
         continue;
      }

      if(g_trade.PositionModify(ticket, newStopLoss, currentTp))
         modifiedCount++;
      else
         skippedCount++;
   }

   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      const string comment = OrderGetString(ORDER_COMMENT);
      if(!HuntTradeCommentIsOurs(comment))
         continue;

      const double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      const double currentSl  = OrderGetDouble(ORDER_SL);
      const double currentTp  = OrderGetDouble(ORDER_TP);
      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      const bool orderIsBuy = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP ||
                               orderType == ORDER_TYPE_BUY_STOP_LIMIT);

      if(orderIsBuy != isBuy)
         continue;

      if(isBuy)
      {
         if(currentSl > 0.0 && newStopLoss <= currentSl)
         {
            skippedCount++;
            continue;
         }
      }
      else
      {
         if(currentSl > 0.0 && newStopLoss >= currentSl)
         {
            skippedCount++;
            continue;
         }
      }

      if(!StopLossModifyAllowed(orderIsBuy, newStopLoss, currentTp))
      {
         skippedCount++;
         continue;
      }

      if(g_trade.OrderModify(ticket, orderPrice, newStopLoss, currentTp, ORDER_TIME_GTC, 0))
         modifiedCount++;
      else
         skippedCount++;
   }

   if(modifiedCount > 0 || skippedCount > 0)
      LogHuntEvent("TRADE_SL_TRAIL",
                   StringFormat("%s activeM2Leg=%d high=%.5f low=%.5f newSL=%.5f mod=%d skip=%d",
                                isBuy ? "bull" : "bear", g_m2Swing.currentSwingLeg.swingDirection,
                                g_m2Swing.currentSwingLeg.legHighPrice, g_m2Swing.currentSwingLeg.legLowPrice,
                                newStopLoss, modifiedCount, skippedCount));
}

//+------------------------------------------------------------------+
void ApplyHuntTradeFirstOppositeM2BosMgmt(const bool isBuy, const double bosBrokenLevel)
{
   if(!InputEnableBosMoveSlAndTp)
      return;

   if(g_huntFirstOppBosMgmtDone)
      return;

   double stopLossPrice = 0.0;
   double tp1Price      = 0.0;
   TryGetHuntTradeSlAndTp1(stopLossPrice, tp1Price);

   if(BosBreakInsideSlTp1Zone(isBuy, stopLossPrice, tp1Price, bosBrokenLevel))
   {
      g_huntFirstOppBosMgmtDone = true;
      LogHuntEvent("TRADE_OPP_BOS_MGMT",
                     StringFormat("skip — opp BOS lvl=%.5f inside SL–TP1 (sl=%.5f tp1=%.5f)",
                                  bosBrokenLevel, stopLossPrice, tp1Price));
      return;
   }

   const int oppositeLegDirection = isBuy ? -1 : 1;
   double    legHigh              = 0.0;
   double    legLow               = 0.0;
   datetime  legEndIgnored        = 0;
   if(!TryNthM2CompletedSwingLeg(oppositeLegDirection, 1, legHigh, legLow, legEndIgnored))
   {
      LogHuntEvent("TRADE_OPP_BOS_MGMT", "skip — no completed opposite M2 leg for OV TP");
      return;
   }

   const double bufferPrice = M2FvgStopBufferPrice();
   if(bufferPrice <= 0.0)
   {
      LogHuntEvent("TRADE_OPP_BOS_MGMT", "skip — chart buffer invalid for OV TP");
      return;
   }

   const double midPoint      = (legHigh + legLow) * 0.5;
   const double newTakeProfit = isBuy
      ? NormalizeDouble(midPoint - bufferPrice, _Digits)
      : NormalizeDouble(midPoint + bufferPrice, _Digits);
   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();

   int modifiedOvCount = 0;
   int skippedOvCount  = 0;
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
      if(!HuntTradeCommentIsOurs(comment) || !HuntTradeCommentIsOverall(comment))
         continue;
      if(!HuntTradeCommentIsOvTpIndex(comment, 2) && !HuntTradeCommentIsOvTpIndex(comment, 3))
         continue;

      const double currentSl = PositionGetDouble(POSITION_SL);
      const bool   posIsBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      if(posIsBuy != isBuy)
         continue;

      if(!StopLossModifyAllowed(posIsBuy, currentSl, newTakeProfit))
      {
         skippedOvCount++;
         continue;
      }

      if(g_trade.PositionModify(ticket, currentSl, newTakeProfit))
         modifiedOvCount++;
      else
         skippedOvCount++;
   }

   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      const string comment = OrderGetString(ORDER_COMMENT);
      if(!HuntTradeCommentIsOurs(comment) || !HuntTradeCommentIsOverall(comment))
         continue;
      if(!HuntTradeCommentIsOvTpIndex(comment, 2) && !HuntTradeCommentIsOvTpIndex(comment, 3))
         continue;

      const double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      const double currentSl  = OrderGetDouble(ORDER_SL);
      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      const bool orderIsBuy = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP ||
                               orderType == ORDER_TYPE_BUY_STOP_LIMIT);

      if(orderIsBuy != isBuy)
         continue;

      if(!StopLossModifyAllowed(orderIsBuy, currentSl, newTakeProfit))
      {
         skippedOvCount++;
         continue;
      }

      if(g_trade.OrderModify(ticket, orderPrice, currentSl, newTakeProfit, ORDER_TIME_GTC, 0))
         modifiedOvCount++;
      else
         skippedOvCount++;
   }

   g_huntFirstOppBosMgmtDone = true;
   LogHuntEvent("TRADE_OPP_BOS_MGMT",
                StringFormat("%s first opp M2 BOS outside SL–TP1: bos=%.5f sl=%.5f tp1=%.5f → TP2/TP3=%.5f mid=%.5f buf=%.5f legH=%.5f legL=%.5f mod=%d skip=%d",
                             isBuy ? "bull" : "bear", bosBrokenLevel, stopLossPrice, tp1Price, newTakeProfit,
                             midPoint, bufferPrice, legHigh, legLow, modifiedOvCount, skippedOvCount));
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

   double bullBrokenLevel = 0.0;
   double bearBrokenLevel = 0.0;
   const bool priceBullBos = TryDetectM2PriceBreakAboveLatestUpLegHigh(bullBrokenLevel);
   const bool priceBearBos = TryDetectM2PriceBreakBelowLatestDownLegLow(bearBrokenLevel);

   if(!priceBullBos && !priceBearBos)
      return;

   if(isBuy)
   {
      if(priceBullBos)
         TrailHuntTradeStopOnSameDirectionM2Bos(true, bullBrokenLevel);
      if(priceBearBos && !g_huntFirstOppBosMgmtDone)
         ApplyHuntTradeFirstOppositeM2BosMgmt(true, bearBrokenLevel);
   }
   else
   {
      if(priceBearBos)
         TrailHuntTradeStopOnSameDirectionM2Bos(false, bearBrokenLevel);
      if(priceBullBos && !g_huntFirstOppBosMgmtDone)
         ApplyHuntTradeFirstOppositeM2BosMgmt(false, bullBrokenLevel);
   }

   LogHuntEvent("TRADE_MGMT_BOS",
                StringFormat("%s bullBOS=%s bearBOS=%s lvl=%.5f oppDone=%s prefix=%s",
                             isBuy ? "buy" : "sell", priceBullBos ? "Y" : "N", priceBearBos ? "Y" : "N",
                             priceBullBos ? bullBrokenLevel : bearBrokenLevel,
                             g_huntFirstOppBosMgmtDone ? "Y" : "N",
                             g_huntTradeSessionCommentPrefix));
}

//+------------------------------------------------------------------+
// Formation bar tick volume must be >= percent of average tick volume on
// the next InputFvgTradeTickVolumeAvgM2BarCount older M2 bars (excludes formation).
// InputFvgTradeMinTickVolumePercentOfM2Avg <= 0 disables the filter.
bool FvgFormationBarMeetsMinTickVolume(const int formationBarShift)
{
   if(InputFvgTradeMinTickVolumePercentOfM2Avg <= 0.0)
      return true;
   if(formationBarShift < 0)
      return false;

   const int avgBarCount = MathMax(1, InputFvgTradeTickVolumeAvgM2BarCount);
   const long formationVol = iTickVolume(_Symbol, InputM2NarrativeTimeframe, formationBarShift);
   if(formationVol <= 0)
      return false;

   long volSum = 0;
   int  counted = 0;
   for(int shift = formationBarShift + 1; shift <= formationBarShift + avgBarCount; shift++)
   {
      const long barVol = iTickVolume(_Symbol, InputM2NarrativeTimeframe, shift);
      if(barVol < 0)
         continue;
      volSum += barVol;
      counted++;
   }
   if(counted == 0)
      return false;

   const double avgVol = (double)volSum / (double)counted;
   const double requiredVol = avgVol * (InputFvgTradeMinTickVolumePercentOfM2Avg / 100.0);
   if((double)formationVol < requiredVol)
   {
      LogHuntEvent("TRADE_SKIP", StringFormat(
         "tick vol low formation=%I64d need>=%.0f (%.0f%% of avg=%.0f over %d M2 bars)",
         formationVol, requiredVol, InputFvgTradeMinTickVolumePercentOfM2Avg, avgVol, counted));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool HasOurHuntOpenPosition()
{
   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(OrderCommentBelongsToActiveHunt(PositionGetString(POSITION_COMMENT)))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool HasOurHuntPendingOrders()
{
   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(OrderCommentBelongsToActiveHunt(OrderGetString(ORDER_COMMENT)))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool HasOurHuntTradePendingOrders()
{
   for(int huntIndex = 0; huntIndex < V2_MAX_HUNT_SESSIONS; huntIndex++)
   {
      if(g_v2Hunts[huntIndex].sessionId == 0)
         continue;
      if(V2HuntHasPendingOrdersForSession(g_v2Hunts[huntIndex].sessionId))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
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
bool IsConsecutiveM2FvgBarAfter(const datetime priorFvgFormationTime,
                                const datetime newFvgFormationTime)
{
   if(priorFvgFormationTime == 0 || newFvgFormationTime == 0)
      return false;
   if(newFvgFormationTime <= priorFvgFormationTime)
      return false;

   const int priorBarShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, priorFvgFormationTime, true);
   return (priorBarShift == 2);
}

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
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt position open — one trade setup per hunt");
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
void CheckHuntFvgBeyondChartRangeCancelOnTick()
{
   datetime sessionIds[];
   if(!V2CollectUniquePendingHuntSessionIds(sessionIds, 8))
      return;

   const int maxShift = InputChartRangeBarCount;

   for(int sessionIndex = 0; sessionIndex < ArraySize(sessionIds); sessionIndex++)
   {
      const datetime sessionId = sessionIds[sessionIndex];
      if(V2HuntHasOpenPositionForSession(sessionId))
         continue;

      const int huntIndex = V2FindHuntSlotBySessionId(sessionId);
      int pendingCount = 0;
      bool isBuy = false;
      double tp3Level = 0.0;
      double entryPrice = 0.0;
      if(!V2TrySyncPreEntryWatchForSession(sessionId, huntIndex, pendingCount,
                                           isBuy, tp3Level, entryPrice))
         continue;

      datetime formationTime = 0;
      if(huntIndex >= 0)
         formationTime = g_v2Hunts[huntIndex].ordersFvgFormationTime;

      if(formationTime == 0)
      {
         const string prefix = V2HuntTradeCommentPrefix(sessionId);
         for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
         {
            const ulong ticket = OrderGetTicket(orderIndex);
            if(ticket == 0 || !OrderSelect(ticket))
               continue;
            const string comment = OrderGetString(ORDER_COMMENT);
            if(StringFind(comment, prefix) != 0)
               continue;
            if(TryParseFormationTimeFromHuntOrderComment(comment, formationTime))
               break;
         }
      }

      if(formationTime == 0)
         continue;

      int barShift = 0;
      if(!FvgFormationBarBeyondChartRange(formationTime, barShift))
         continue;

      CancelOurHuntPendingOrders(sessionId);
      V2ClearHuntTradeOrdersActiveForSession(sessionId);
      if(huntIndex >= 0)
         V2LogHuntEvent(huntIndex, "HUNT_FVG_CHART_RANGE_CANCEL",
                        StringFormat("FVG %s beyond chart range: shift=%d max=%d pend=%d",
                                     IntegerToString((long)formationTime), barShift, maxShift,
                                     pendingCount));
      else
         LogHuntEvent("HUNT_FVG_CHART_RANGE_CANCEL",
                      StringFormat("HS%lld FVG %s beyond chart range: shift=%d max=%d pend=%d",
                                   (long)sessionId, IntegerToString((long)formationTime),
                                   barShift, maxShift, pendingCount));
   }

   V2RefreshGlobalHuntTradeWatchFromSessions();
}

//+------------------------------------------------------------------+
void CheckHuntPreEntryTp3CancelOnTick()
{
   datetime sessionIds[];
   if(!V2CollectUniquePendingHuntSessionIds(sessionIds, 8))
      return;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int sessionIndex = 0; sessionIndex < ArraySize(sessionIds); sessionIndex++)
   {
      const datetime sessionId = sessionIds[sessionIndex];
      if(V2HuntHasOpenPositionForSession(sessionId))
         continue;

      const int huntIndex = V2FindHuntSlotBySessionId(sessionId);
      int pendingCount = 0;
      bool isBuy = false;
      double tp3Level = 0.0;
      double entryPrice = 0.0;
      if(!V2TrySyncPreEntryWatchForSession(sessionId, huntIndex, pendingCount,
                                           isBuy, tp3Level, entryPrice))
         continue;

      if(!HuntMarketReachedTakeProfitLevel(isBuy, tp3Level))
         continue;

      datetime sinceTime = 0;
      if(huntIndex >= 0)
         sinceTime = g_v2Hunts[huntIndex].ordersFvgFormationTime;
      if(sinceTime == 0)
      {
         const string prefix = V2HuntTradeCommentPrefix(sessionId);
         for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
         {
            const ulong ticket = OrderGetTicket(orderIndex);
            if(ticket == 0 || !OrderSelect(ticket))
               continue;
            const string comment = OrderGetString(ORDER_COMMENT);
            if(StringFind(comment, prefix) != 0)
               continue;
            if(TryParseFormationTimeFromHuntOrderComment(comment, sinceTime))
               break;
         }
      }

      if(SameDirectionM2BosBetweenEntryAndTp3Since(isBuy, entryPrice, tp3Level, sinceTime))
      {
         if(huntIndex >= 0)
            V2LogHuntEvent(huntIndex, "HUNT_TP3_PREENTRY_BOS_KEEP",
                           StringFormat("TP3=%.5f touched — same-dir M2 BOS between entry=%.5f and TP3 since %s",
                                        tp3Level, entryPrice,
                                        TimeToString(sinceTime, TIME_DATE | TIME_MINUTES)));
         else
            LogHuntEvent("HUNT_TP3_PREENTRY_BOS_KEEP",
                         StringFormat("HS%lld TP3=%.5f touched — same-dir M2 BOS between entry=%.5f and TP3",
                                      (long)sessionId, tp3Level, entryPrice));
         continue;
      }

      CancelOurHuntPendingOrders(sessionId);

      int remainingForSession = 0;
      bool dummyBuy = false;
      double dummyTp3 = 0.0;
      double dummyEntry = 0.0;
      V2TrySyncPreEntryWatchForSession(sessionId, huntIndex, remainingForSession,
                                       dummyBuy, dummyTp3, dummyEntry);

      if(remainingForSession > 0)
      {
         if(huntIndex >= 0)
            V2LogHuntEvent(huntIndex, "HUNT_TP3_PREENTRY_FAIL",
                           StringFormat("TP3=%.5f hit but %d pendings remain (bid=%.5f ask=%.5f)",
                                        tp3Level, remainingForSession, bid, ask));
         else
            LogHuntEvent("HUNT_TP3_PREENTRY_FAIL",
                         StringFormat("HS%lld TP3=%.5f hit but %d pendings remain (bid=%.5f ask=%.5f)",
                                      (long)sessionId, tp3Level, remainingForSession, bid, ask));
         continue;
      }

      if(huntIndex >= 0)
      {
         V2ClearHuntPreEntryWatchForHunt(huntIndex);
         V2LogHuntEvent(huntIndex, "HUNT_TP3_PREENTRY_CANCEL",
                        StringFormat("pending removed: TP3=%.5f entry=%.5f %s pend=%d bid=%.5f ask=%.5f hiM2=%.5f loM2=%.5f",
                                     tp3Level, entryPrice, isBuy ? "buy" : "sell", pendingCount, bid, ask,
                                     iHigh(_Symbol, InputM2NarrativeTimeframe, 0), iLow(_Symbol, InputM2NarrativeTimeframe, 0)));
      }
      else
         LogHuntEvent("HUNT_TP3_PREENTRY_CANCEL",
                      StringFormat("HS%lld pending removed: TP3=%.5f entry=%.5f %s pend=%d bid=%.5f ask=%.5f",
                                   (long)sessionId, tp3Level, entryPrice, isBuy ? "buy" : "sell",
                                   pendingCount, bid, ask));
   }

   V2RefreshGlobalHuntTradeWatchFromSessions();
}

//+------------------------------------------------------------------+
//| Bull: bid > top+1% M2 chart rng → BuyLimit @ top+1%; else market buy.          |
//| Bear: ask < low−1% M2 chart rng → SellLimit @ low−1%; else market sell.         |
//+------------------------------------------------------------------+
bool ResolveFvgEntryPrice(const bool isBullishFairValueGap, const double zoneLowPrice,
                          const double zoneHighPrice, bool &outUseMarketOrder, double &outEntryPrice)
{
   outUseMarketOrder = false;
   outEntryPrice     = 0.0;

   const double gapHigh    = MathMax(zoneLowPrice, zoneHighPrice);
   const double gapLow     = MathMin(zoneLowPrice, zoneHighPrice);
   const double chartOffset = M2FvgStopBufferPrice();
   const double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps        = (pointSize > 0.0 ? pointSize : 0.00001);

   if(chartOffset <= 0.0)
      return false;

   if(isBullishFairValueGap)
   {
      const double limitLevel = gapHigh + chartOffset;
      if(currentBid > limitLevel + eps)
      {
         outUseMarketOrder = false;
         outEntryPrice     = NormalizeDouble(limitLevel, _Digits);
      }
      else
      {
         outUseMarketOrder = true;
         outEntryPrice     = currentAsk;
      }
   }
   else
   {
      const double limitLevel = gapLow - chartOffset;
      if(currentAsk < limitLevel - eps)
      {
         outUseMarketOrder = false;
         outEntryPrice     = NormalizeDouble(limitLevel, _Digits);
      }
      else
      {
         outUseMarketOrder = true;
         outEntryPrice     = currentBid;
      }
   }

   return (outEntryPrice > 0.0);
}

//+------------------------------------------------------------------+
// Latest completed H4 same-dir leg (g_h4Swing 0.5). TP = 0.9x / 1.4x / 1.9x from entry.
//+------------------------------------------------------------------+
int V4TradeLegDirectionForFvg(const bool isBullishFairValueGap)
{
   return isBullishFairValueGap ? 1 : -1;
}

//+------------------------------------------------------------------+
bool ComputeAbsorptionLegTakeProfits(const bool isBullishFairValueGap, const double entryPrice,
                                     const double legRange, double &outTakeProfitPrices[])
{
   ArrayResize(outTakeProfitPrices, LQ_TP_COUNT);

   const double minDistance = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(legRange <= minDistance)
      return false;

   const double tpMultipliers[3] = {0.9, 1.4, 1.9};

   if(isBullishFairValueGap)
   {
      for(int tpIndex = 0; tpIndex < LQ_TP_COUNT; tpIndex++)
      {
         const double tpDistance = tpMultipliers[tpIndex] * legRange;
         if(tpDistance <= minDistance)
            return false;
         outTakeProfitPrices[tpIndex] = NormalizeDouble(entryPrice + tpDistance, _Digits);
      }
      return (outTakeProfitPrices[0] > entryPrice);
   }

   for(int tpIndex = 0; tpIndex < LQ_TP_COUNT; tpIndex++)
   {
      const double tpDistance = tpMultipliers[tpIndex] * legRange;
      if(tpDistance <= minDistance)
         return false;
      outTakeProfitPrices[tpIndex] = NormalizeDouble(entryPrice - tpDistance, _Digits);
   }
   return (outTakeProfitPrices[0] < entryPrice);
}

//+------------------------------------------------------------------+
bool V4ResolveH4SameDirLegRangeForTp(const bool isBullishFairValueGap, double &outLegRange,
                                      datetime &outLegEndTime)
{
   outLegRange   = 0.0;
   outLegEndTime = 0;

   const int tradeLegDir = V4TradeLegDirectionForFvg(isBullishFairValueGap);

   double legHigh = 0.0;
   double legLow  = 0.0;
   if(!TryNthH4CompletedSwingLeg(tradeLegDir, 1, legHigh, legLow, outLegEndTime))
      return false;

   outLegRange = legHigh - legLow;
   return (outLegRange > SymbolInfoDouble(_Symbol, SYMBOL_POINT));
}

//+------------------------------------------------------------------+
bool PlaceOneFvgTradeOrder(const bool isBullishFairValueGap, const bool useMarketOrder,
                           const double entryPrice, const double stopLossPrice, const double takeProfitPrice,
                           const double volume, const string comment)
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
   if(useMarketOrder)
   {
      if(isBullishFairValueGap)
         ok = g_trade.Buy(volume, _Symbol, 0.0, stopLossPrice, takeProfitPrice, comment);
      else
         ok = g_trade.Sell(volume, _Symbol, 0.0, stopLossPrice, takeProfitPrice, comment);
   }
   else if(isBullishFairValueGap)
      ok = g_trade.BuyLimit(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                            ORDER_TIME_GTC, 0, comment);
   else
      ok = g_trade.SellLimit(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                             ORDER_TIME_GTC, 0, comment);

   if(!ok)
      LogHuntEvent("TRADE_ORDER_FAIL",
                   StringFormat("%s ret=%d %s", comment,
                                (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
   return ok;
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

//+------------------------------------------------------------------+
bool TryFallbackLimitEntryToMarket(const bool isBullishFairValueGap, const double zoneLowPrice,
                                   const double zoneHighPrice, bool &inOutUseMarketOrder,
                                   double &inOutEntryPrice)
{
   if(inOutUseMarketOrder)
      return true;

   const double higherEnd = MathMax(zoneLowPrice, zoneHighPrice);
   const double lowerEnd  = MathMin(zoneLowPrice, zoneHighPrice);
   const double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBullishFairValueGap)
   {
      if(inOutEntryPrice >= ask && bid >= lowerEnd && bid <= higherEnd)
      {
         inOutUseMarketOrder = true;
         inOutEntryPrice     = ask;
         LogHuntEvent("TRADE_ENTRY_FALLBACK", "BuyLimit→market (bid inside FVG)");
         return true;
      }
      if(inOutEntryPrice >= ask && lowerEnd < ask)
      {
         inOutEntryPrice = NormalizeDouble(lowerEnd, _Digits);
         LogHuntEvent("TRADE_ENTRY_FALLBACK",
                      StringFormat("BuyLimit repriced to zone low %.5f", inOutEntryPrice));
         return (inOutEntryPrice < ask);
      }
   }
   else
   {
      if(inOutEntryPrice <= bid && ask >= lowerEnd && ask <= higherEnd)
      {
         inOutUseMarketOrder = true;
         inOutEntryPrice     = bid;
         LogHuntEvent("TRADE_ENTRY_FALLBACK", "SellLimit→market (ask inside FVG)");
         return true;
      }
      if(inOutEntryPrice <= bid && higherEnd > bid)
      {
         inOutEntryPrice = NormalizeDouble(higherEnd, _Digits);
         LogHuntEvent("TRADE_ENTRY_FALLBACK",
                      StringFormat("SellLimit repriced to zone high %.5f", inOutEntryPrice));
         return (inOutEntryPrice > bid);
      }
   }
   return false;
}

//+------------------------------------------------------------------+
// FVG 3rd candle = newest closed M2 bar (shift 1). If its close matches the limit entry
// (or bull: close/bar-low at gap lower edge; bear: close/bar-high at gap upper edge),
// promote to market; SL/TP unchanged downstream.
bool TryPromoteFvgLimitToMarketIfFormationCloseMatchesEntry(const bool isBullishFairValueGap,
                                                            const double zoneLowPrice,
                                                            const double zoneHighPrice,
                                                            const double limitEntryPrice,
                                                            bool &inOutUseMarketOrder,
                                                            double &inOutEntryPrice)
{
   if(inOutUseMarketOrder || limitEntryPrice <= 0.0)
      return false;

   const double formationClose = NormalizeDouble(iClose(_Symbol, InputM2NarrativeTimeframe, 1), _Digits);
   const double limitNorm      = NormalizeDouble(limitEntryPrice, _Digits);
   const double gapLow         = MathMin(zoneLowPrice, zoneHighPrice);
   const double gapHigh        = MathMax(zoneLowPrice, zoneHighPrice);
   const double pointSize      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pointSize <= 0.0)
      return false;

   const double tolerance = pointSize;

   bool closeMatchesEntry = (MathAbs(formationClose - limitNorm) <= tolerance);

   if(!closeMatchesEntry && isBullishFairValueGap)
   {
      const double formationLow = NormalizeDouble(iLow(_Symbol, InputM2NarrativeTimeframe, 1), _Digits);
      const double gapLowerNorm = NormalizeDouble(gapLow, _Digits);
      if(MathAbs(limitNorm - gapLowerNorm) <= tolerance)
         closeMatchesEntry =
            (MathAbs(formationClose - gapLowerNorm) <= tolerance) ||
            (MathAbs(formationClose - formationLow) <= tolerance &&
             MathAbs(formationLow - gapLowerNorm) <= tolerance);
   }
   else if(!closeMatchesEntry && !isBullishFairValueGap)
   {
      const double formationHigh = NormalizeDouble(iHigh(_Symbol, InputM2NarrativeTimeframe, 1), _Digits);
      const double gapUpperNorm  = NormalizeDouble(gapHigh, _Digits);
      if(MathAbs(limitNorm - gapUpperNorm) <= tolerance)
         closeMatchesEntry =
            (MathAbs(formationClose - gapUpperNorm) <= tolerance) ||
            (MathAbs(formationClose - formationHigh) <= tolerance &&
             MathAbs(formationHigh - gapUpperNorm) <= tolerance);
   }

   if(!closeMatchesEntry)
      return false;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return false;

   inOutUseMarketOrder = true;
   if(isBullishFairValueGap)
      inOutEntryPrice = ask;
   else
      inOutEntryPrice = bid;

   LogHuntEvent("TRADE_ENTRY_FORMATION_CLOSE",
                StringFormat("%s FVG bar1 close=%.5f limit=%.5f gap=%.5f-%.5f → market @ %.5f",
                             isBullishFairValueGap ? "bull" : "bear",
                             formationClose, limitNorm, gapLow, gapHigh, inOutEntryPrice));
   return true;
}

//+------------------------------------------------------------------+
bool TryPlaceTouchVolumeBarTradeSetup(const int huntIndex, const bool isBuy,
                                       const datetime maxVolBarOpenTime, const long maxVolume,
                                       const datetime slWindowStartOpen,
                                       const datetime huntSessionId)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || maxVolBarOpenTime == 0)
   {
      if(huntIndex >= 0 && huntIndex < V2_MAX_HUNT_SESSIONS)
         V2LogHuntEvent(huntIndex, "TRADE_SKIP", "touch vol bar entry — maxVolBarOpenTime=0");
      return false;
   }

   if(V2IsHuntSessionStillActive(huntSessionId))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt still ON — orders after touch");
      return false;
   }

   string bosBiasBlockReason = "";
   if(!FvgTradeAllowedByH4BosBias(isBuy, bosBiasBlockReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", bosBiasBlockReason);
      return false;
   }

   bool replacePendingOnly = false;
   if(!ResolveHuntFvgOrderPlacementGate(maxVolBarOpenTime, huntSessionId, replacePendingOnly))
      return false;

   const int barShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, maxVolBarOpenTime, true);
   if(barShift < 0 || barShift > LQ_FVG_TRADE_MAX_M2_BAR_SHIFT)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("touch vol bar too old shift=%d max=%d", barShift,
                                  LQ_FVG_TRADE_MAX_M2_BAR_SHIFT));
      return false;
   }

   if(barShift < 0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "touch vol bar shift invalid");
      return false;
   }

   bool   useMarketOrder = false;
   double entryPrice     = 0.0;
   double stopLossOverall = 0.0;
   string entryFailReason = "";
   if(!ResolveTouchLegVolumeBarEntryAndSl(isBuy, barShift, slWindowStartOpen, huntIndex,
                                          useMarketOrder, entryPrice, stopLossOverall,
                                          entryFailReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("touch vol bar entry/SL invalid sh=%d entry=%.5f sl=%.5f buy=%s — %s",
                                  barShift, entryPrice, stopLossOverall, isBuy ? "Y" : "N",
                                  entryFailReason));
      return false;
   }

   double normalizedEntry = NormalizeDouble(entryPrice, _Digits);

   const datetime formationTime = maxVolBarOpenTime;
   double takeProfitPrices[];
   int    takeProfitCount = 0;
   if(!BuildTradeSwingGroupTakeProfits(isBuy, formationTime, normalizedEntry,
                                       stopLossOverall, takeProfitPrices, takeProfitCount))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("no swing-group TP with min R:R %.2f entry=%.5f sl=%.5f",
                                  InputTradeSwingTpMinRewardToRisk, normalizedEntry, stopLossOverall));
      return false;
   }

   for(int tpIndex = 0; tpIndex < takeProfitCount; tpIndex++)
   {
      if(!StopsDistanceAllowed(isBuy, normalizedEntry, stopLossOverall, takeProfitPrices[tpIndex]))
      {
         V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                          StringFormat("broker stops level tp=%d", tpIndex + 1));
         return false;
      }
   }

   if(LQ_RISK_USD_PER_TRADE <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "LQ_RISK_USD_PER_TRADE invalid");
      return false;
   }

   const double tpRiskWeights[3] = {3.0, 1.0, 1.0};
   const double riskTotalParts  = tpRiskWeights[0] + tpRiskWeights[1] + tpRiskWeights[2];

   const string huntCommentPrefix = V2HuntTradeCommentPrefix(huntSessionId);
   const string formationTag      = IntegerToString((long)formationTime);
   int          placedCount       = 0;
   int          zeroVolumeCount   = 0;

   string tpLog = StringFormat("%.5f", takeProfitPrices[0]);
   for(int tpLogIndex = 1; tpLogIndex < takeProfitCount; tpLogIndex++)
      tpLog += StringFormat("/%.5f", takeProfitPrices[tpLogIndex]);

   double slRefExtreme  = 0.0;
   int    slRefBarShift = barShift;
   double   slLegLow  = 0.0;
   double   slLegHigh = 0.0;
   datetime slLegStart = 0;
   datetime slLegEnd   = 0;
   if(V2TryGetOppositeM2LegExtentsForTouch(huntIndex, slLegLow, slLegHigh, slLegStart, slLegEnd))
   {
      datetime slScanStart = slWindowStartOpen;
      if(slLegStart > 0 && (slScanStart == 0 || slLegStart < slScanStart))
         slScanStart = slLegStart;
      const double legFloor = isBuy ? slLegLow : slLegHigh;
      M2TouchVolSlReferenceExtreme(isBuy, barShift, slScanStart, legFloor, slRefExtreme, slRefBarShift);
   }
   else
      M2TouchVolSlReferenceExtreme(isBuy, barShift, slWindowStartOpen, 0.0, slRefExtreme, slRefBarShift);
   const double volBarLow  = iLow(_Symbol, InputM2NarrativeTimeframe, barShift);
   const double volBarHigh = iHigh(_Symbol, InputM2NarrativeTimeframe, barShift);
   const double entryOff   = M2TouchVolEntryOffsetPrice(barShift);
   const double bufferPrice = M2TouchVolSlBufferPrice(barShift);
   const double limitRef   = M2TouchVolLimitEntryPrice(isBuy, barShift, volBarLow, volBarHigh);
   const string logDetail = StringFormat(
      "%s entry=%.5f sl=%.5f (volBar sh=%d vol=%lld barL=%.5f barH=%.5f limitRef=%.5f off=%.5f anchor=%s slWin=%s slRef sh=%d %s=%.5f buf=%.5f) swingTP=%s count=%d limit=Y",
      isBuy ? "buyHunt" : "sellHunt", normalizedEntry, stopLossOverall, barShift, (long)maxVolume,
      volBarLow, volBarHigh, limitRef, entryOff, isBuy ? "low+N%rng" : "high-N%rng",
      TimeToString(slWindowStartOpen, TIME_DATE | TIME_MINUTES), slRefBarShift,
      isBuy ? "low" : "high", slRefExtreme, bufferPrice,
      tpLog, takeProfitCount);

   string tradeBlockReason = "";
   if(!IsFvgAutomatedTradingAllowed(tradeBlockReason))
   {
      LogHuntEvent("TRADE_PLAN", logDetail + " | " + tradeBlockReason);
      return false;
   }

   for(int tpIndex = 0; tpIndex < takeProfitCount; tpIndex++)
   {
      const string commentOv =
         StringFormat("%sOV_TP%d_%s", huntCommentPrefix, tpIndex + 1, formationTag);
      const double riskPerTpOrder =
         LQ_RISK_USD_PER_TRADE * tpRiskWeights[tpIndex] / riskTotalParts;
      const double volumeOv =
         CalculateVolumeForFixedUsdRisk(isBuy, normalizedEntry, stopLossOverall,
                                      riskPerTpOrder);
      if(volumeOv <= 0.0)
         zeroVolumeCount++;
      else if(PlaceOneFvgTradeOrder(isBuy, useMarketOrder, normalizedEntry,
                                    stopLossOverall, takeProfitPrices[tpIndex], volumeOv, commentOv))
         placedCount++;
   }

   if(placedCount > 0)
   {
      const double farthestTp = takeProfitPrices[takeProfitCount - 1];
      RegisterHuntTradeAfterSuccessfulPlace(isBuy, normalizedEntry, takeProfitPrices[0],
                                            farthestTp, formationTime, huntSessionId);
      LogHuntEvent("TRADE_PLACE",
                   StringFormat("%s touchVol placed=%d/%d replace=%s %s", formationTag, placedCount,
                                takeProfitCount, replacePendingOnly ? "Y" : "N", logDetail));
      return true;
   }

   V2LogHuntEvent(huntIndex, "TRADE_FAIL",
                  StringFormat("%s touchVol zeroVol=%d %s", formationTag, zeroVolumeCount, logDetail));
   return false;
}

//+------------------------------------------------------------------+
bool TryPlaceOppositeFvgTradeSetup(const bool isBullishFairValueGap, const double zoneLowPrice,
                                    const double zoneHighPrice, const datetime formationTime,
                                    const datetime huntSessionId, const double h4LegRange)
{
   const int huntIndex = V2FindHuntSlotBySessionId(huntSessionId);
   if(formationTime == 0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "formationTime=0");
      return false;
   }

   if(V2IsHuntSessionStillActive(huntSessionId))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt still ON — orders after touch");
      return false;
   }

   string bosBiasBlockReason = "";
   if(!FvgTradeAllowedByH4BosBias(isBullishFairValueGap, bosBiasBlockReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", bosBiasBlockReason);
      return false;
   }

   bool replacePendingOnly = false;
   if(!ResolveHuntFvgOrderPlacementGate(formationTime, huntSessionId, replacePendingOnly))
      return false;

   const int barShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, true);
   if(barShift < 0 || barShift > LQ_FVG_TRADE_MAX_M2_BAR_SHIFT)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("FVG too old shift=%d max=%d", barShift,
                                  LQ_FVG_TRADE_MAX_M2_BAR_SHIFT));
      return false;
   }

   if(!FvgFormationBarMeetsMinTickVolume(barShift))
      return false;

   const double bufferPrice = M2FvgStopBufferPrice();
   if(bufferPrice <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "chart height/buffer invalid");
      return false;
   }

   bool   useMarketOrder = false;
   double entryPrice     = 0.0;
   if(!ResolveFvgEntryPrice(isBullishFairValueGap, zoneLowPrice, zoneHighPrice,
                            useMarketOrder, entryPrice))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "entry resolve failed");
      return false;
   }

   TryPromoteFvgLimitToMarketIfFormationCloseMatchesEntry(isBullishFairValueGap, zoneLowPrice,
                                                          zoneHighPrice, entryPrice,
                                                          useMarketOrder, entryPrice);

   const double higherEndOfFairValueGap = MathMax(zoneLowPrice, zoneHighPrice);
   const double lowerEndOfFairValueGap  = MathMin(zoneLowPrice, zoneHighPrice);

   // SL ref = 2nd M2 candle before FVG formation bar (formation=barShift; ref=barShift+2).
   const int slRefBarShift = barShift + 2;
   if(slRefBarShift >= iBars(_Symbol, InputM2NarrativeTimeframe))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("no 2nd-prev M2 bar before FVG formation shift=%d need>=%d",
                                  barShift, slRefBarShift));
      return false;
   }

   double stopLossOverall = 0.0;
   if(isBullishFairValueGap)
   {
      const double secondPrevCandleLow = iLow(_Symbol, InputM2NarrativeTimeframe, slRefBarShift);
      stopLossOverall = NormalizeDouble(secondPrevCandleLow - bufferPrice, _Digits);
      if(entryPrice <= stopLossOverall)
      {
         V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                        StringFormat("buy entry not above SL (2nd-prev low sh=%d %.5f buf=%.5f)",
                                     slRefBarShift, secondPrevCandleLow, bufferPrice));
         return false;
      }
   }
   else
   {
      const double secondPrevCandleHigh = iHigh(_Symbol, InputM2NarrativeTimeframe, slRefBarShift);
      stopLossOverall = NormalizeDouble(secondPrevCandleHigh + bufferPrice, _Digits);
      if(entryPrice >= stopLossOverall)
      {
         V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                        StringFormat("sell entry not below SL (2nd-prev high sh=%d %.5f buf=%.5f)",
                                     slRefBarShift, secondPrevCandleHigh, bufferPrice));
         return false;
      }
   }

   double normalizedEntry = NormalizeDouble(entryPrice, _Digits);
   const bool isBuy       = isBullishFairValueGap;

   if(isBuy && !useMarketOrder)
   {
      const double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(normalizedEntry >= currentAsk)
      {
         bool useMarketAfterFallback = false;
         double entryAfterFallback   = entryPrice;
         if(!TryFallbackLimitEntryToMarket(isBullishFairValueGap, zoneLowPrice, zoneHighPrice,
                                           useMarketAfterFallback, entryAfterFallback))
         {
            V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                           StringFormat("buy limit entry invalid entry=%.5f bid=%.5f ask=%.5f",
                                        normalizedEntry, currentBid, currentAsk));
            return false;
         }
         useMarketOrder  = useMarketAfterFallback;
         entryPrice      = entryAfterFallback;
         normalizedEntry = NormalizeDouble(entryPrice, _Digits);

         if(normalizedEntry <= stopLossOverall)
         {
            V2LogHuntEvent(huntIndex, "TRADE_SKIP", "buy entry not above SL after fallback");
            return false;
         }
      }
   }
   else if(!isBuy && !useMarketOrder)
   {
      const double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(normalizedEntry <= currentBid)
      {
         bool useMarketAfterFallback = false;
         double entryAfterFallback   = entryPrice;
         if(!TryFallbackLimitEntryToMarket(isBullishFairValueGap, zoneLowPrice, zoneHighPrice,
                                           useMarketAfterFallback, entryAfterFallback))
         {
            V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                           StringFormat("sell limit entry invalid entry=%.5f bid=%.5f ask=%.5f",
                                        normalizedEntry, currentBid, currentAsk));
            return false;
         }
         useMarketOrder  = useMarketAfterFallback;
         entryPrice      = entryAfterFallback;
         normalizedEntry = NormalizeDouble(entryPrice, _Digits);

         if(normalizedEntry >= stopLossOverall)
         {
            V2LogHuntEvent(huntIndex, "TRADE_SKIP", "sell entry not below SL after fallback");
            return false;
         }
      }
   }

   double takeProfitPrices[];
   int    takeProfitCount = 0;
   if(!BuildTradeSwingGroupTakeProfits(isBullishFairValueGap, formationTime, normalizedEntry,
                                       stopLossOverall, takeProfitPrices, takeProfitCount))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("no swing-group TP with min R:R %.2f entry=%.5f sl=%.5f",
                                  InputTradeSwingTpMinRewardToRisk, normalizedEntry, stopLossOverall));
      return false;
   }

   for(int tpIndex = 0; tpIndex < takeProfitCount; tpIndex++)
   {
      if(!StopsDistanceAllowed(isBuy, normalizedEntry, stopLossOverall, takeProfitPrices[tpIndex]))
      {
         V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                          StringFormat("broker stops level tp=%d", tpIndex + 1));
         return false;
      }
   }

   if(LQ_RISK_USD_PER_TRADE <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "LQ_RISK_USD_PER_TRADE invalid");
      return false;
   }

   // Weight TP1:TP2:TP3 = 3:1:1 (total 5 parts). We express this as USD risk per OV order.
   const double tpRiskWeights[3] = {3.0, 1.0, 1.0};
   const double riskTotalParts  = tpRiskWeights[0] + tpRiskWeights[1] + tpRiskWeights[2]; // = 5.0

   const string huntCommentPrefix = V2HuntTradeCommentPrefix(huntSessionId);
   const string formationTag      = IntegerToString((long)formationTime);
   int          placedCount       = 0;
   int          zeroVolumeCount   = 0;

   string tpLog = StringFormat("%.5f", takeProfitPrices[0]);
   for(int tpLogIndex = 1; tpLogIndex < takeProfitCount; tpLogIndex++)
      tpLog += StringFormat("/%.5f", takeProfitPrices[tpLogIndex]);

   const string logDetail = StringFormat(
      "%s entry=%.5f sl=%.5f (2nd-prev M2 sh=%d %s buf2%%rng=%.5f) swingTP=%s count=%d market=%s",
      isBullishFairValueGap ? "bull" : "bear", normalizedEntry, stopLossOverall, slRefBarShift,
      isBullishFairValueGap ? "low" : "high", bufferPrice,
      tpLog, takeProfitCount, useMarketOrder ? "Y" : "N");

   string tradeBlockReason = "";
   if(!IsFvgAutomatedTradingAllowed(tradeBlockReason))
   {
      LogHuntEvent("TRADE_PLAN", logDetail + " | " + tradeBlockReason);
      return false;
   }

   for(int tpIndex = 0; tpIndex < takeProfitCount; tpIndex++)
   {
      const string commentOv =
         StringFormat("%sOV_TP%d_%s", huntCommentPrefix, tpIndex + 1, formationTag);
      const double riskPerTpOrder =
         LQ_RISK_USD_PER_TRADE * tpRiskWeights[tpIndex] / riskTotalParts;
      const double volumeOv =
         CalculateVolumeForFixedUsdRisk(isBuy, normalizedEntry, stopLossOverall,
                                      riskPerTpOrder);
      if(volumeOv <= 0.0)
         zeroVolumeCount++;
      else if(PlaceOneFvgTradeOrder(isBullishFairValueGap, useMarketOrder, normalizedEntry,
                                    stopLossOverall, takeProfitPrices[tpIndex], volumeOv, commentOv))
         placedCount++;
   }

   if(placedCount > 0)
   {
      const double farthestTp = takeProfitPrices[takeProfitCount - 1];
      RegisterHuntTradeAfterSuccessfulPlace(isBuy, normalizedEntry, takeProfitPrices[0],
                                            farthestTp, formationTime, huntSessionId);
      LogHuntEvent("TRADE_PLACE",
                   StringFormat("%s placed=%d/%d replace=%s %s", formationTag, placedCount,
                                takeProfitCount, replacePendingOnly ? "Y" : "N", logDetail));
      return true;
   }

   V2LogHuntEvent(huntIndex, "TRADE_FAIL",
                  StringFormat("%s zeroVol=%d %s", formationTag, zeroVolumeCount, logDetail));
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
   g_v2Hunts[huntIndex].sameDirExtremeAtLastTouchRecalc     = 0.0;
   g_v2Hunts[huntIndex].touchRecalcBufferAnchor             = 0.0;
   g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg = false;
   g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross   = false;
   g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach = 0.0;
   g_v2Hunts[huntIndex].sessionId                      = 0;
   g_v2Hunts[huntIndex].oppositeFvgFoundCount          = 0;
   g_v2Hunts[huntIndex].touchLevel                     = 0.0;
   g_v2Hunts[huntIndex].touchLevelReady                = false;
   g_v2Hunts[huntIndex].postTouchFvgGateOpen         = true;
   g_v2Hunts[huntIndex].touchHitVolumeRejectLatch    = false;
   g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime = 0;
   g_v2Hunts[huntIndex].pendingTradeFvgValid           = false;
   g_v2Hunts[huntIndex].fvgMemCount                    = 0;
   g_v2Hunts[huntIndex].fvgRectSequence                = 0;
   g_v2Hunts[huntIndex].tradeOrdersActive              = false;
   g_v2Hunts[huntIndex].ordersFvgFormationTime         = 0;
   g_v2Hunts[huntIndex].tradeIsBuy                     = false;
   g_v2Hunts[huntIndex].tradeEntryPrice                = 0.0;
   g_v2Hunts[huntIndex].tradeTp1Price                  = 0.0;
   g_v2Hunts[huntIndex].preEntryCancelTpLevel          = 0.0;
   g_v2Hunts[huntIndex].firstOppBosMgmtDone            = false;
}

//+------------------------------------------------------------------+
void V2InitAllHuntSlots()
{
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
      V2InitHuntSlot(i);
}

//+------------------------------------------------------------------+
int V2CountActiveHunts()
{
   int count = 0;
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
      if(g_v2Hunts[i].active)
         count++;
   return count;
}

//+------------------------------------------------------------------+
int V2AllocHuntSlot()
{
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
   {
      if(g_v2Hunts[i].active)
         continue;
      if(g_v2Hunts[i].sessionId != 0 &&
         V2HuntHasPendingOrdersForSession(g_v2Hunts[i].sessionId))
         continue;
      return i;
   }

   LogHuntEvent("HUNT_ARRAY_FULL",
                StringFormat("max=%d slots; all reserved (active, deferred M2 leg, or pending orders)",
                             V2_MAX_HUNT_SESSIONS));
   return -1;
}

//+------------------------------------------------------------------+
int V2FindActiveHuntByH4Leg(const datetime legEndTime, const bool h4HighBreached)
{
   if(legEndTime == 0)
      return -1;
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
   {
      if(!g_v2Hunts[i].active)
         continue;
      if(g_v2Hunts[i].h4BreachedLegEndTime == legEndTime &&
         g_v2Hunts[i].h4HighWasBreached == h4HighBreached)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
int V2FindActiveHuntByBreachPolarity(const bool h4HighBreached)
{
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
   {
      if(g_v2Hunts[i].active && g_v2Hunts[i].h4HighWasBreached == h4HighBreached)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
void V2AbortHuntSessionForRestart(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   if(sessionId != 0 && g_huntTradeSessionCommentPrefix == V2HuntTradeCommentPrefix(sessionId))
      ResetHuntTradeState();

   V2ClearTouchPointLine(huntIndex);
   V2ClearImpulseBufferZone(huntIndex);
   V2ClearTouchRecalcBufferZone(huntIndex);
   V2RemoveHuntSessionFvgPlots(huntIndex);
   V2InitHuntSlot(huntIndex);
}

//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
string V2FvgRectPrefixForSession(const datetime sessionId)
{
   return LQ_OBJ_PREFIX_FVG_RECT + V2HuntObjectSuffix(sessionId);
}

//+------------------------------------------------------------------+
string V2TouchObjectName(const datetime sessionId)
{
   return LQ_OBJ_TOUCH_POINT + V2HuntObjectSuffix(sessionId);
}

//+------------------------------------------------------------------+
string V2ImpulseObjectName(const datetime sessionId)
{
   return LQ_OBJ_IMPULSE_PREFIX + V2HuntObjectSuffix(sessionId);
}

//+------------------------------------------------------------------+
string V2TouchRecalcBufferObjectName(const datetime sessionId)
{
   return LQ_OBJ_TOUCH_RECALC_PREFIX + V2HuntObjectSuffix(sessionId);
}

//+------------------------------------------------------------------+
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
int V2OppositeM2LegDirectionForHunt(const int huntIndex)
{
   return g_v2Hunts[huntIndex].h4HighWasBreached ? -1 : 1;
}

//+------------------------------------------------------------------+
//| H4 up-leg breach → bull FVG; H4 down-leg breach → bear FVG.       |
//+------------------------------------------------------------------+
bool V2HuntExpectsBullishFvg(const int huntIndex)
{
   return g_v2Hunts[huntIndex].h4HighWasBreached;
}

//+------------------------------------------------------------------+
bool V2FvgPolarityMatchesHunt(const int huntIndex, const bool isBullishFairValueGap)
{
   return isBullishFairValueGap == V2HuntExpectsBullishFvg(huntIndex);
}

//+------------------------------------------------------------------+
bool V2TryGetOppositeM2LegExtentsForTouch(const int huntIndex, double &outLegLow, double &outLegHigh,
                                           datetime &outLegStartTime, datetime &outLegEndTime)
{
   outLegLow  = 0.0;
   outLegHigh = 0.0;
   outLegStartTime = 0;
   outLegEndTime   = 0;

   const int oppositeDir = V2OppositeM2LegDirectionForHunt(huntIndex);
   datetime compStart = 0;
   datetime compEnd   = 0;
   double compLow  = 0.0;
   double compHigh = 0.0;
   const bool haveCompleted =
      V2TryGetLastCompletedM2Leg(oppositeDir, compLow, compHigh, compStart, compEnd);

   if(g_m2Swing.currentSwingLeg.swingDirection == oppositeDir)
   {
      outLegStartTime = g_m2Swing.currentSwingLeg.legStartTime;
      outLegEndTime   = 0;
      if(!haveCompleted)
      {
         outLegLow  = g_m2Swing.currentSwingLeg.legLowPrice;
         outLegHigh = g_m2Swing.currentSwingLeg.legHighPrice;
         return (outLegLow > 0.0 && outLegHigh > 0.0);
      }
      outLegLow  = MathMin(compLow, g_m2Swing.currentSwingLeg.legLowPrice);
      outLegHigh = MathMax(compHigh, g_m2Swing.currentSwingLeg.legHighPrice);
      if(compStart > 0 && (outLegStartTime == 0 || compStart < outLegStartTime))
         outLegStartTime = compStart;
      return true;
   }

   if(haveCompleted)
   {
      outLegLow         = compLow;
      outLegHigh        = compHigh;
      outLegStartTime   = compStart;
      outLegEndTime     = compEnd;
   }
   return haveCompleted;
}

//+------------------------------------------------------------------+
//| Touch recalc: active opposite M2 leg while open; else last completed opposite. |
//+------------------------------------------------------------------+
bool V2TryGetOppositeM2LegExtentsForTouchRecalc(const int huntIndex, double &outLegLow, double &outLegHigh,
                                                 datetime &outLegStartTime, datetime &outLegEndTime)
{
   outLegLow  = 0.0;
   outLegHigh = 0.0;
   outLegStartTime = 0;
   outLegEndTime   = 0;

   const int oppositeDir = V2OppositeM2LegDirectionForHunt(huntIndex);
   if(g_m2Swing.currentSwingLeg.swingDirection == oppositeDir)
   {
      outLegLow         = g_m2Swing.currentSwingLeg.legLowPrice;
      outLegHigh        = g_m2Swing.currentSwingLeg.legHighPrice;
      outLegStartTime   = g_m2Swing.currentSwingLeg.legStartTime;
      outLegEndTime     = 0;
      return (outLegLow > 0.0 && outLegHigh > 0.0);
   }

   return V2TryGetLastCompletedM2Leg(oppositeDir, outLegLow, outLegHigh, outLegStartTime, outLegEndTime);
}

//+------------------------------------------------------------------+
//| Same-dir extreme tracked while hunt is ON (path max high / min low). |
//+------------------------------------------------------------------+
bool V2GetSameDirExtremeWhileHuntOn(const int huntIndex, double &outExtreme)
{
   outExtreme = 0.0;
   if(!g_v2Hunts[huntIndex].active)
      return false;

   if(g_v2Hunts[huntIndex].h4HighWasBreached)
   {
      outExtreme = g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach;
      return (outExtreme > 0.0);
   }

   outExtreme = g_v2Hunts[huntIndex].pathMinLowSinceH4Breach;
   return (outExtreme > 0.0);
}

//+------------------------------------------------------------------+
bool V2TryGetTouchRecalcBufferAnchorExtreme(const int huntIndex, double &outAnchor)
{
   outAnchor = 0.0;
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return false;
   if(g_v2Hunts[huntIndex].touchRecalcBufferAnchor <= 0.0)
      return false;
   outAnchor = g_v2Hunts[huntIndex].touchRecalcBufferAnchor;
   return true;
}

//+------------------------------------------------------------------+
//| Bull FVG hunt: buffer tracks active down-leg low until leg completes; resumes on enter/cross below buffer.  |
//| Bear FVG hunt: buffer tracks active up-leg high until leg completes; resumes on enter/cross above buffer. |
//+------------------------------------------------------------------+
void V2InitTouchRecalcBufferAnchor(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;

   g_v2Hunts[huntIndex].touchRecalcBufferAnchor          = 0.0;
   g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg  = false;
   g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross  = false;
   V2BeginTouchRecalcBufferActiveLegTrack(huntIndex);
}

//+------------------------------------------------------------------+
void V2BeginTouchRecalcBufferActiveLegTrack(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   const int trackDir = V2OppositeM2LegDirectionForHunt(huntIndex);
   if(g_m2Swing.currentSwingLeg.swingDirection != trackDir)
      return;

   g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg = true;
   g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross = false;
   V2SyncTouchRecalcBufferAnchorFromActiveLeg(huntIndex);

   if(g_v2Hunts[huntIndex].touchRecalcBufferAnchor > 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRECALC_BUF_TRACK",
                     StringFormat("track active %s leg anchor=%.5f",
                                  trackDir == 1 ? "up" : "down",
                                  g_v2Hunts[huntIndex].touchRecalcBufferAnchor));
   }
}

//+------------------------------------------------------------------+
void V2SyncTouchRecalcBufferAnchorFromActiveLeg(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;
   if(!g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg)
      return;

   const int trackDir = V2OppositeM2LegDirectionForHunt(huntIndex);
   if(g_m2Swing.currentSwingLeg.swingDirection != trackDir)
      return;

   const double liveExtreme = (trackDir == 1)
                              ? g_m2Swing.currentSwingLeg.legHighPrice
                              : g_m2Swing.currentSwingLeg.legLowPrice;
   if(liveExtreme <= 0.0)
      return;

   if(V2HuntExpectsBullishFvg(huntIndex))
   {
      if(g_v2Hunts[huntIndex].touchRecalcBufferAnchor <= 0.0)
         g_v2Hunts[huntIndex].touchRecalcBufferAnchor = liveExtreme;
      else
         g_v2Hunts[huntIndex].touchRecalcBufferAnchor =
            MathMin(g_v2Hunts[huntIndex].touchRecalcBufferAnchor, liveExtreme);
   }
   else
   {
      if(g_v2Hunts[huntIndex].touchRecalcBufferAnchor <= 0.0)
         g_v2Hunts[huntIndex].touchRecalcBufferAnchor = liveExtreme;
      else
         g_v2Hunts[huntIndex].touchRecalcBufferAnchor =
            MathMax(g_v2Hunts[huntIndex].touchRecalcBufferAnchor, liveExtreme);
   }
}

//+------------------------------------------------------------------+
void V2StopTouchRecalcBufferActiveLegTrack(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg = false;
}

//+------------------------------------------------------------------+
bool V2DetectTouchRecalcBufferCrossOrTouch(const int huntIndex, const double barHigh,
                                             const double barLow, const double barClose)
{
   bool nearHuntExtreme    = false;
   bool nearOppositeBuffer = false;
   return V2DetectTouchRecalcBufferHit(huntIndex, barHigh, barLow, barClose,
                                        nearHuntExtreme, nearOppositeBuffer, 0.0) &&
          nearOppositeBuffer;
}

//+------------------------------------------------------------------+
void V2TryArmTouchRecalcBufferResumeOnCross(const int huntIndex, const double barHigh,
                                              const double barLow, const double barClose)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(!g_v2Hunts[huntIndex].postTouchFvgGateOpen &&
      !V2TouchSideBlocksBufferRecalc(huntIndex, barHigh, barLow, pointSize))
   {
      bool nearHuntExtreme    = false;
      bool nearOppositeBuffer = false;
      if(V2DetectTouchRecalcBufferHit(huntIndex, barHigh, barLow, barClose,
                                       nearHuntExtreme, nearOppositeBuffer, 0.0))
      {
         double anchor = 0.0;
         if(!V2TryGetTouchRecalcBufferAnchorExtreme(huntIndex, anchor))
         {
            double huntExtreme = 0.0;
            if(V2GetSameDirExtremeWhileHuntOn(huntIndex, huntExtreme))
               anchor = huntExtreme;
         }
         V2TryTouchRecalcAfterBufferEvent(huntIndex, barHigh, barLow, barClose,
                                          StringFormat("%.1f%% recalc buffer hit anchor=%.5f",
                                                       InputHuntTouchRecalcPercentBeforeSameDirExtreme,
                                                       anchor));
         return;
      }
   }

   if(g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg)
      return;
   if(g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross)
      return;
   if(!V2DetectTouchRecalcBufferCrossOrTouch(huntIndex, barHigh, barLow, barClose))
      return;

   g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross = true;
   V2LogHuntEvent(huntIndex, "TRECALC_BUF_ARM",
                  StringFormat("buffer enter/cross anchor=%.5f — resume active leg track",
                               g_v2Hunts[huntIndex].touchRecalcBufferAnchor));
   V2BeginTouchRecalcBufferActiveLegTrack(huntIndex);
   V2TryTouchRecalcAfterBufferEvent(huntIndex, barHigh, barLow, barClose,
                                    StringFormat("%.1f%% opposite buffer enter/cross anchor=%.5f",
                                                 InputHuntTouchRecalcPercentBeforeSameDirExtreme,
                                                 g_v2Hunts[huntIndex].touchRecalcBufferAnchor));
}

//+------------------------------------------------------------------+
void V2OnTouchRecalcBufferLegChange(const int huntIndex, const int closingLegDirection,
                                     const int nextLegDirection)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   const int trackDir = V2OppositeM2LegDirectionForHunt(huntIndex);

   if(g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross &&
      nextLegDirection == trackDir)
      V2BeginTouchRecalcBufferActiveLegTrack(huntIndex);

   if(!g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg)
      return;

   if(closingLegDirection == trackDir && g_m2Swing.swingHistoryCount > 0)
   {
      const Swing closedLeg = g_m2Swing.swingHistory[g_m2Swing.swingHistoryCount - 1];
      if(closedLeg.swingDirection == trackDir)
      {
         const double finalAnchor = (trackDir == 1)
                                    ? closedLeg.legHighPrice
                                    : closedLeg.legLowPrice;
         if(finalAnchor > 0.0)
         {
            if(V2HuntExpectsBullishFvg(huntIndex))
               g_v2Hunts[huntIndex].touchRecalcBufferAnchor =
                  MathMin(g_v2Hunts[huntIndex].touchRecalcBufferAnchor, finalAnchor);
            else
               g_v2Hunts[huntIndex].touchRecalcBufferAnchor =
                  MathMax(g_v2Hunts[huntIndex].touchRecalcBufferAnchor, finalAnchor);
         }
      }
      V2StopTouchRecalcBufferActiveLegTrack(huntIndex);
      g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross = false;
      V2LogHuntEvent(huntIndex, "TRECALC_BUF_FREEZE",
                     StringFormat("%s leg closed anchor=%.5f",
                                  trackDir == 1 ? "up" : "down",
                                  g_v2Hunts[huntIndex].touchRecalcBufferAnchor));
      const double freezeBarHigh  = iHigh(_Symbol, InputM2NarrativeTimeframe, 1);
      const double freezeBarLow   = iLow(_Symbol, InputM2NarrativeTimeframe, 1);
      const double freezeBarClose = iClose(_Symbol, InputM2NarrativeTimeframe, 1);
      bool nearHuntExtreme    = false;
      bool nearOppositeBuffer = false;
      if(V2DetectTouchRecalcBufferHit(huntIndex, freezeBarHigh, freezeBarLow, freezeBarClose,
                                        nearHuntExtreme, nearOppositeBuffer, 0.0))
      {
         V2TryTouchRecalcAfterBufferEvent(huntIndex, freezeBarHigh, freezeBarLow, freezeBarClose,
                                          StringFormat("opposite %s leg closed at buffer anchor=%.5f",
                                                       trackDir == 1 ? "up" : "down",
                                                       g_v2Hunts[huntIndex].touchRecalcBufferAnchor));
      }
   }
}

//+------------------------------------------------------------------+
double V2TouchRecalcBufferBandHalfWidth()
{
   const double pct = InputHuntTouchRecalcPercentBeforeSameDirExtreme;
   if(pct <= 0.0)
      return 0.0;
   const double chartHeight = ReferenceChartHeightForFairValueGapFilterM2();
   if(chartHeight <= 0.0)
      return 0.0;
   return chartHeight * (pct / 100.0);
}

//+------------------------------------------------------------------+
bool V2BarOverlapsPriceZone(const double barHigh, const double barLow,
                             const double zoneLow, const double zoneHigh, const double eps)
{
   return (barHigh >= zoneLow - eps && barLow <= zoneHigh + eps);
}

//+------------------------------------------------------------------+
bool V2DetectTouchRecalcBufferHit(const int huntIndex, const double barHigh, const double barLow,
                                   const double barClose, bool &outNearHuntExtreme,
                                   bool &outNearOppositeBuffer,
                                   const double huntExtremeAtBarStart)
{
   outNearHuntExtreme     = false;
   outNearOppositeBuffer  = false;
   if(!g_v2Hunts[huntIndex].active)
      return false;

   const double band = V2TouchRecalcBufferBandHalfWidth();
   if(band <= 0.0)
      return false;

   double huntExtreme = 0.0;
   if(huntExtremeAtBarStart > 0.0)
      huntExtreme = huntExtremeAtBarStart;
   else if(!V2GetSameDirExtremeWhileHuntOn(huntIndex, huntExtreme))
      return false;

   double anchor = huntExtreme;
   if(V2TryGetTouchRecalcBufferAnchorExtreme(huntIndex, anchor))
      outNearOppositeBuffer = true;
   else
      outNearHuntExtreme = true;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   double zoneLow  = 0.0;
   double zoneHigh = 0.0;
   if(V2HuntExpectsBullishFvg(huntIndex))
   {
      zoneLow  = anchor;
      zoneHigh = anchor + band;
   }
   else
   {
      zoneLow  = anchor - band;
      zoneHigh = anchor;
   }

   return V2BarOverlapsPriceZone(barHigh, barLow, zoneLow, zoneHigh, eps);
}

//+------------------------------------------------------------------+
bool V2TouchSideBlocksBufferRecalc(const int huntIndex, const double barHigh, const double barLow,
                                    const double pointSize)
{
   return g_v2Hunts[huntIndex].touchLevelReady &&
          V2TryDetectTouchOfStoredLevel(huntIndex, barHigh, barLow, pointSize);
}

//+------------------------------------------------------------------+
void V2TryTouchRecalcAfterBufferEvent(const int huntIndex, const double barHigh,
                                       const double barLow, const double barClose,
                                       const string bufferTriggerTag)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   bool nearHuntExtreme    = false;
   bool nearOppositeBuffer = false;
   if(!V2DetectTouchRecalcBufferHit(huntIndex, barHigh, barLow, barClose,
                                     nearHuntExtreme, nearOppositeBuffer, 0.0))
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(V2TouchSideBlocksBufferRecalc(huntIndex, barHigh, barLow, pointSize))
      return;

   g_v2Hunts[huntIndex].touchHitVolumeRejectLatch = false;

   if(!g_v2Hunts[huntIndex].postTouchFvgGateOpen)
   {
      g_v2Hunts[huntIndex].postTouchFvgGateOpen         = true;
      V2LogHuntEvent(huntIndex, "TOUCH_GATE_ON", bufferTriggerTag);
      V2DrawTouchPointLine(huntIndex);
   }

   V2TryRecalcTouchOnHuntSameDirProgress(huntIndex, barHigh, barLow, barClose,
                                          true, bufferTriggerTag);
}

//+------------------------------------------------------------------+
//| Touch recalc only when price enters the hunt / opposite-leg recalc buffer band. |
//+------------------------------------------------------------------+
void V2TryRecalcTouchOnHuntSameDirProgress(const int huntIndex, const double barHigh,
                                           const double barLow, const double barClose,
                                           const bool forceBufferRecalc,
                                           const string forcedTriggerTag,
                                           const double huntExtremeAtBarStart)
{
   if(!g_v2Hunts[huntIndex].active)
      return;

   bool nearHuntExtreme = false;
   bool nearOppositeBuffer = false;
   if(!forceBufferRecalc)
   {
      if(!V2DetectTouchRecalcBufferHit(huntIndex, barHigh, barLow, barClose,
                                        nearHuntExtreme, nearOppositeBuffer, huntExtremeAtBarStart))
         return;
   }

   double huntExtreme = 0.0;
   if(!V2GetSameDirExtremeWhileHuntOn(huntIndex, huntExtreme))
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   const double lastSnap  = g_v2Hunts[huntIndex].sameDirExtremeAtLastTouchRecalc;
   const double pct       = InputHuntTouchRecalcPercentBeforeSameDirExtreme;

   if(!forceBufferRecalc && lastSnap > 0.0 && MathAbs(huntExtreme - lastSnap) <= eps)
      return;

   string triggerTag = forcedTriggerTag;
   if(StringLen(triggerTag) == 0)
   {
      triggerTag = nearOppositeBuffer
                   ? (g_v2Hunts[huntIndex].h4HighWasBreached
                      ? StringFormat("within %.1f%% M2 chart of opposite up leg buffer", pct)
                      : StringFormat("within %.1f%% M2 chart of opposite down leg buffer", pct))
                   : StringFormat("within %.1f%% M2 chart of recalc buffer", pct);
   }

   const double oldTouch = g_v2Hunts[huntIndex].touchLevel;
   const bool   hadTouch = g_v2Hunts[huntIndex].touchLevelReady;
   double legLow  = 0.0;
   double legHigh = 0.0;
   datetime legStartTime = 0;
   datetime legEndTime   = 0;
   if(!V2TryGetOppositeM2LegExtentsForTouchRecalc(huntIndex, legLow, legHigh, legStartTime, legEndTime))
      return;

   const bool fromActiveLeg = (g_m2Swing.currentSwingLeg.swingDirection ==
                               V2OppositeM2LegDirectionForHunt(huntIndex));
   V2ApplyTouchLevelFromM2Leg(huntIndex, legLow, legHigh,
                              StringFormat("%s huntExtreme=%.5f (%s opposite leg)",
                                           triggerTag, huntExtreme,
                                           fromActiveLeg ? "active" : "completed"),
                              true);

   if(!g_v2Hunts[huntIndex].touchLevelReady)
      return;

   const double touchEps = (pointSize > 0.0 ? pointSize * 2.0 : 0.00002);
   if(!hadTouch || MathAbs(g_v2Hunts[huntIndex].touchLevel - oldTouch) > touchEps)
      g_v2Hunts[huntIndex].sameDirExtremeAtLastTouchRecalc = huntExtreme;
}

//+------------------------------------------------------------------+
int V2OppositeH4LegDirectionForHunt(const int huntIndex)
{
   return V2OppositeM2LegDirectionForHunt(huntIndex);
}

//+------------------------------------------------------------------+
void V2OnH4LegClosedForHunts(const int closedLegDirection, const datetime closedLegEndTime)
{
   if(!InputEndHuntOnOppositeH4LegBeforeTouch || closedLegDirection == 0 || closedLegEndTime == 0)
      return;

   for(int huntIndex = 0; huntIndex < V2_MAX_HUNT_SESSIONS; huntIndex++)
   {
      if(!g_v2Hunts[huntIndex].active || !g_v2Hunts[huntIndex].touchLevelReady)
         continue;
      if(closedLegDirection != V2OppositeH4LegDirectionForHunt(huntIndex))
         continue;
      if(g_v2Hunts[huntIndex].sessionId != 0 && closedLegEndTime <= g_v2Hunts[huntIndex].sessionId)
         continue;

      V2EndOppositeFvgHuntSession(huntIndex,
                                  StringFormat("opposite H4 leg closed %s, touch lvl=%.5f never hit",
                                               TimeToString(closedLegEndTime, TIME_DATE | TIME_MINUTES),
                                               g_v2Hunts[huntIndex].touchLevel),
                                  false);
   }
}

//+------------------------------------------------------------------+
int V2SameSideM2LegDirectionForHunt(const int huntIndex)
{
   return g_v2Hunts[huntIndex].h4HighWasBreached ? 1 : -1;
}

//+------------------------------------------------------------------+
void V2ResetHuntSlotSessionCounters(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   g_v2Hunts[huntIndex].oppositeFvgFoundCount = 0;
   g_v2Hunts[huntIndex].touchLevel            = 0.0;
   g_v2Hunts[huntIndex].touchLevelReady       = false;
   g_v2Hunts[huntIndex].postTouchFvgGateOpen    = true;
   g_v2Hunts[huntIndex].touchHitVolumeRejectLatch = false;
   g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime = 0;
   g_v2Hunts[huntIndex].sameDirExtremeAtLastTouchRecalc = 0.0;
   g_v2Hunts[huntIndex].touchRecalcBufferAnchor         = 0.0;
   g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg = false;
   g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross = false;
   g_v2Hunts[huntIndex].pendingTradeFvgValid  = false;
   g_v2Hunts[huntIndex].fvgMemCount           = 0;
   g_v2Hunts[huntIndex].fvgRectSequence       = 0;
   g_v2Hunts[huntIndex].tradeOrdersActive     = false;
   g_v2Hunts[huntIndex].ordersFvgFormationTime = 0;
   g_v2Hunts[huntIndex].tradeIsBuy            = false;
   g_v2Hunts[huntIndex].tradeEntryPrice       = 0.0;
   g_v2Hunts[huntIndex].tradeTp1Price         = 0.0;
   g_v2Hunts[huntIndex].preEntryCancelTpLevel = 0.0;
   g_v2Hunts[huntIndex].firstOppBosMgmtDone     = false;
   V2ClearTouchPointLine(huntIndex);
}

//+------------------------------------------------------------------+
bool V2PushHuntFvgMemory(const int huntIndex, const bool isBullishFairValueGap,
                         const double zoneLowPrice, const double zoneHighPrice,
                         const datetime fairValueGapBarOpenTime)
{
   for(int i = 0; i < g_v2Hunts[huntIndex].fvgMemCount; i++)
   {
      if(g_v2Hunts[huntIndex].fvgMem[i].fairValueGapBarOpenTime == fairValueGapBarOpenTime)
         return false;
   }
   if(g_v2Hunts[huntIndex].fvgMemCount < V2_HUNT_FVG_MEM_CAPACITY)
   {
      const int index = g_v2Hunts[huntIndex].fvgMemCount;
      g_v2Hunts[huntIndex].fvgMem[index].isBullishFairValueGap   = isBullishFairValueGap;
      g_v2Hunts[huntIndex].fvgMem[index].fairValueGapZoneLowPrice  = zoneLowPrice;
      g_v2Hunts[huntIndex].fvgMem[index].fairValueGapZoneHighPrice = zoneHighPrice;
      g_v2Hunts[huntIndex].fvgMem[index].fairValueGapBarOpenTime  = fairValueGapBarOpenTime;
      g_v2Hunts[huntIndex].fvgMemCount++;
      return true;
   }
   for(int shiftIndex = 1; shiftIndex < V2_HUNT_FVG_MEM_CAPACITY; shiftIndex++)
      g_v2Hunts[huntIndex].fvgMem[shiftIndex - 1] = g_v2Hunts[huntIndex].fvgMem[shiftIndex];
   const int lastIndex = V2_HUNT_FVG_MEM_CAPACITY - 1;
   g_v2Hunts[huntIndex].fvgMem[lastIndex].isBullishFairValueGap   = isBullishFairValueGap;
   g_v2Hunts[huntIndex].fvgMem[lastIndex].fairValueGapZoneLowPrice  = zoneLowPrice;
   g_v2Hunts[huntIndex].fvgMem[lastIndex].fairValueGapZoneHighPrice = zoneHighPrice;
   g_v2Hunts[huntIndex].fvgMem[lastIndex].fairValueGapBarOpenTime  = fairValueGapBarOpenTime;
   return true;
}

//+------------------------------------------------------------------+
void V2DrawHuntFairValueGapZone(const int huntIndex, const bool isBullishFairValueGap,
                                const double zoneLowPrice, const double zoneHighPrice,
                                const datetime leftBarTime, const datetime rightBarTime)
{
   if(!H4LqChartDrawEnabled(InputDrawBosOppositeFairValueGapZones))
      return;

   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   g_v2Hunts[huntIndex].fvgRectSequence++;
   const string sequenceString = IntegerToString(g_v2Hunts[huntIndex].fvgRectSequence);
   const string chartObjectName = V2FvgRectPrefixForSession(sessionId) + sequenceString;
   const string typeLabelName   = LQ_OBJ_PREFIX_FVG_LBL + V2HuntObjectSuffix(sessionId) + sequenceString;

   if(g_v2Hunts[huntIndex].fvgRectSequence > InputMaximumFairValueGapRectangles)
   {
      const string oldSequenceString =
         IntegerToString(g_v2Hunts[huntIndex].fvgRectSequence - InputMaximumFairValueGapRectangles);
      ObjectDelete(0, V2FvgRectPrefixForSession(sessionId) + oldSequenceString);
      ObjectDelete(0, LQ_OBJ_PREFIX_FVG_LBL + V2HuntObjectSuffix(sessionId) + oldSequenceString);
   }

   const datetime rectangleTimeLeft  = (leftBarTime <= rightBarTime) ? leftBarTime : rightBarTime;
   const datetime rectangleTimeRight = (leftBarTime <= rightBarTime) ? rightBarTime : leftBarTime;
   const double rectanglePriceLow    = MathMin(zoneLowPrice, zoneHighPrice);
   const double rectanglePriceHigh   = MathMax(zoneLowPrice, zoneHighPrice);

   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);
   if(ObjectFind(0, typeLabelName) >= 0)
      ObjectDelete(0, typeLabelName);

   if(!ObjectCreate(0, chartObjectName, OBJ_RECTANGLE, 0, rectangleTimeLeft, rectanglePriceHigh,
                    rectangleTimeRight, rectanglePriceLow))
      return;

   const color zoneColor = isBullishFairValueGap ? clrDodgerBlue : clrFuchsia;
   ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, chartObjectName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, chartObjectName, OBJPROP_BACK, true);
   ObjectSetInteger(0, chartObjectName, OBJPROP_FILL, true);
   ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

   const double symbolPointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double labelPrice      = rectanglePriceHigh + symbolPointSize * 14.0;
   if(ObjectCreate(0, typeLabelName, OBJ_TEXT, 0, rectangleTimeRight, labelPrice))
   {
      ObjectSetString(0, typeLabelName, OBJPROP_TEXT, isBullishFairValueGap ? "bull" : "bear");
      ObjectSetInteger(0, typeLabelName, OBJPROP_COLOR,
                       isBullishFairValueGap ? clrDodgerBlue : clrFuchsia);
      ObjectSetInteger(0, typeLabelName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, typeLabelName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, typeLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, typeLabelName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, typeLabelName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, typeLabelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   }
}

//+------------------------------------------------------------------+
void V2UpdateTouchLevelFromM2Swing(const int huntIndex)
{
   if(!g_v2Hunts[huntIndex].active || g_v2Hunts[huntIndex].touchLevelReady)
      return;

   double legLow  = 0.0;
   double legHigh = 0.0;
   datetime legStartTime = 0;
   datetime legEndTime   = 0;
   if(!V2TryGetOppositeM2LegExtentsForTouch(huntIndex, legLow, legHigh, legStartTime, legEndTime))
      return;

   V2TryLockTouchLevelFromM2Leg(huntIndex, legLow, legHigh, "last completed opposite M2 leg");
}

//+------------------------------------------------------------------+
void V2OnM2LegChangeForHunt(const int huntIndex, const int closingLegDirection,
                            const int nextLegDirection)
{
   if(!g_v2Hunts[huntIndex].active)
      return;

   if(g_v2Hunts[huntIndex].touchLevelReady)
      return;

   const int oppositeDir = V2OppositeM2LegDirectionForHunt(huntIndex);
   if(closingLegDirection != oppositeDir)
      return;

   const datetime legStartTime = g_m2Swing.currentSwingLeg.legStartTime;
   const datetime legEndTime   = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   V2ApplyTouchLevelFromOppositeLegWindow(huntIndex, legStartTime, legEndTime,
                                          g_m2Swing.currentSwingLeg.legLowPrice,
                                          g_m2Swing.currentSwingLeg.legHighPrice,
                                          "opposite M2 leg just closed", false);
}

//+------------------------------------------------------------------+
void V2DrawTouchPointLine(const int huntIndex)
{
   if(!H4LqChartDrawEnabled())
      return;

   if(!g_v2Hunts[huntIndex].postTouchFvgGateOpen ||
      !g_v2Hunts[huntIndex].touchLevelReady || g_v2Hunts[huntIndex].touchLevel <= 0.0)
   {
      V2ClearTouchPointLine(huntIndex);
      return;
   }
   datetime tRight = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   if(tRight == 0)
      return;
   const int m2PeriodSec = (int)PeriodSeconds(InputM2NarrativeTimeframe);
   datetime tLeft = tRight - (datetime)(3 * m2PeriodSec);
   if(tLeft <= 0)
      tLeft = tRight;
   const string objName = V2TouchObjectName(g_v2Hunts[huntIndex].sessionId);
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
   if(!ObjectCreate(0, objName, OBJ_TREND, 0, tLeft, g_v2Hunts[huntIndex].touchLevel,
                    tRight, g_v2Hunts[huntIndex].touchLevel))
      return;
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void V2ClearTouchPointLine(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   if(g_v2Hunts[huntIndex].sessionId != 0)
      ObjectDelete(0, V2TouchObjectName(g_v2Hunts[huntIndex].sessionId));
}

//+------------------------------------------------------------------+
void V2RemoveHuntSessionFvgPlots(const int huntIndex)
{
   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   const string rectPrefix = V2FvgRectPrefixForSession(sessionId);
   const string lblPrefix  = LQ_OBJ_PREFIX_FVG_LBL + V2HuntObjectSuffix(sessionId);
   for(int s = 1; s <= g_v2Hunts[huntIndex].fvgRectSequence; s++)
   {
      ObjectDelete(0, rectPrefix + IntegerToString(s));
      ObjectDelete(0, lblPrefix + IntegerToString(s));
   }
   g_v2Hunts[huntIndex].fvgMemCount           = 0;
   g_v2Hunts[huntIndex].fvgRectSequence       = 0;
   g_v2Hunts[huntIndex].oppositeFvgFoundCount = 0;
   g_v2Hunts[huntIndex].pendingTradeFvgValid  = false;
}

//+------------------------------------------------------------------+
bool V2TryDetectOppositeDirBosForHunt(const int huntIndex, string &outBosDetail)
{
   outBosDetail = "";
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return false;

   double brokenLevel = 0.0;
   const bool bullBos = TryDetectM2PriceBreakAboveLatestUpLegHigh(brokenLevel);
   double bearBrokenLevel = 0.0;
   const bool bearBos = TryDetectM2PriceBreakBelowLatestDownLegLow(bearBrokenLevel);

   if(g_v2Hunts[huntIndex].h4HighWasBreached && bearBos)
   {
      outBosDetail = StringFormat("bear BOS lvl=%.5f (H4 up leg breach)", bearBrokenLevel);
      return true;
   }
   if(!g_v2Hunts[huntIndex].h4HighWasBreached && bullBos)
   {
      outBosDetail = StringFormat("bull BOS lvl=%.5f (H4 down leg breach)", brokenLevel);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Hunt ON only. Opposite M2 BOS clears marked same-dir FVGs.       |
//+------------------------------------------------------------------+
void V2TryClearHuntFvgsOnSameDirectionBosWhileHuntOn(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;
   if(!g_v2Hunts[huntIndex].postTouchFvgGateOpen)
      return;

   string bosDetail = "";
   if(!V2TryDetectOppositeDirBosForHunt(huntIndex, bosDetail))
      return;

   if(g_v2Hunts[huntIndex].fvgMemCount <= 0 && !g_v2Hunts[huntIndex].pendingTradeFvgValid)
      return;

   V2RemoveHuntSessionFvgPlots(huntIndex);
   V2LogHuntEvent(huntIndex, "FVG_CLEAR_SAME_DIR_BOS", bosDetail);
}

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
bool V2TryGetM2TouchLegVolumeWindowBounds(const int huntIndex, const int lastClosedBarShift,
                                           datetime &outWindowStartOpen, datetime &outWindowEndOpen)
{
   outWindowStartOpen = 0;
   outWindowEndOpen   = 0;

   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || lastClosedBarShift < 1)
      return false;

   const datetime touchBarOpen = iTime(_Symbol, InputM2NarrativeTimeframe, lastClosedBarShift);
   if(touchBarOpen == 0)
      return false;

   if(g_m2Swing.swingHistoryCount < 1)
      return false;

   const Swing lastCompletedLeg = g_m2Swing.swingHistory[g_m2Swing.swingHistoryCount - 1];
   if(lastCompletedLeg.legEndTime == 0 || lastCompletedLeg.legStartTime == 0)
      return false;

   if(!M2TryGetLegBarOpenFromEnd(lastCompletedLeg.legStartTime, lastCompletedLeg.legEndTime,
                                  3, outWindowStartOpen))
      return false;

   outWindowEndOpen = touchBarOpen;
   return M2VolumeWindowShiftRangeValid(outWindowStartOpen, outWindowEndOpen);
}

//+------------------------------------------------------------------+
bool V2ValidateTouchHitOppositeM2LegVolume(const int huntIndex, const int lastClosedBarShift,
                                            long &outVolumes[], int &outVolumeCount,
                                            datetime &outWindowStartOpen, datetime &outWindowEndOpen)
{
   outVolumeCount = 0;
   ArrayResize(outVolumes, 0);
   outWindowStartOpen = 0;
   outWindowEndOpen   = 0;

   if(!V2TryGetM2TouchLegVolumeWindowBounds(huntIndex, lastClosedBarShift,
                                             outWindowStartOpen, outWindowEndOpen))
      return false;

   if(!M2CollectTickVolumesInOpenTimeWindow(outWindowStartOpen, outWindowEndOpen,
                                             outVolumes, outVolumeCount))
      return false;

   if(outVolumeCount < 2)
      return false;

   if(InputTouchVolRequireAscendingVolume &&
      !M2ValidateTouchLegVolumeIncreasePattern(outVolumes, outVolumeCount))
      return false;

   return true;
}

//+------------------------------------------------------------------+
void V2InvalidateTouchHitVolumeFailed(const int huntIndex, const double barClose,
                                       const long &volumes[], const int volumeCount,
                                       const datetime windowStartOpen, const datetime windowEndOpen)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   g_v2Hunts[huntIndex].postTouchFvgGateOpen     = false;
   g_v2Hunts[huntIndex].touchHitVolumeRejectLatch = true;

   V2ClearTouchPointLine(huntIndex);
   V2LogHuntEvent(huntIndex, "TOUCH_GATE_OFF",
                  StringFormat("touch vol not ascending lvl=%.5f close=%.5f — %s",
                               g_v2Hunts[huntIndex].touchLevel, barClose,
                               M2FormatTickVolumeArrayLog(volumes, volumeCount,
                                                           windowStartOpen, windowEndOpen)));
}

//+------------------------------------------------------------------+
//| TOUCH_HIT: bar range straddles touch (low < lvl < high).                         |
//+------------------------------------------------------------------+
bool V2TryDetectTouchOfStoredLevel(const int huntIndex, const double barHigh, const double barLow,
                                    const double pointSize)
{
   if(!g_v2Hunts[huntIndex].touchLevelReady || g_v2Hunts[huntIndex].touchLevel <= 0.0)
      return false;

   const double touchLevel = g_v2Hunts[huntIndex].touchLevel;
   const double eps        = (pointSize > 0.0 ? pointSize : 0.00001);

   return (barLow < touchLevel - eps && barHigh > touchLevel + eps);
}

//+------------------------------------------------------------------+
void V2HandleTouchHitConfirmed(const int huntIndex, const double barHigh, const double barLow,
                                const double barClose, const long &volumes[], const int volumeCount,
                                const datetime windowStartOpen, const datetime windowEndOpen)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   g_v2Hunts[huntIndex].touchHitVolumeRejectLatch = false;

   datetime maxVolBarOpen = 0;
   long     maxVolume     = -1;
   if(!M2FindMaxVolumeBarOpenTimeExcludingOldest(volumes, volumeCount, windowStartOpen,
                                                  windowEndOpen, maxVolBarOpen, maxVolume))
   {
      g_v2Hunts[huntIndex].postTouchFvgGateOpen = false;
      V2ClearTouchPointLine(huntIndex);
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("touch vol — no max-vol bar after excluding oldest %s",
                                  M2FormatTickVolumeArrayLog(volumes, volumeCount,
                                                              windowStartOpen, windowEndOpen)));
      V2LogHuntEvent(huntIndex, "TOUCH_GATE_OFF",
                      StringFormat("touch lvl=%.5f — max-vol bar unavailable",
                                   g_v2Hunts[huntIndex].touchLevel));
      return;
   }

   const int maxVolBarShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, maxVolBarOpen, true);
   V2LogHuntEvent(huntIndex, "TOUCH_HIT",
                  StringFormat("lvl=%.5f barH=%.5f barL=%.5f — maxVol bar sh=%d vol=%lld open=%s",
                               g_v2Hunts[huntIndex].touchLevel, barHigh, barLow, maxVolBarShift,
                               (long)maxVolume,
                               TimeToString(maxVolBarOpen, TIME_DATE | TIME_MINUTES)));

   datetime entryBarOpen = maxVolBarOpen;
   long     entryBarVol  = maxVolume;
   datetime firstFvgPatternBarOpen = 0;
   datetime fvgFormationBarOpen    = 0;
   if(V2TryGetEarliestHuntFvgFirstPatternBarOpen(huntIndex, firstFvgPatternBarOpen,
                                                  fvgFormationBarOpen) &&
      firstFvgPatternBarOpen > 0 && maxVolBarOpen < firstFvgPatternBarOpen)
   {
      datetime fvgPatternEntryBarOpen = 0;
      long     fvgPatternEntryBarVol  = -1;
      if(V2TrySelectTouchVolEntryBarFromFvgPattern(firstFvgPatternBarOpen, fvgFormationBarOpen,
                                                   fvgPatternEntryBarOpen, fvgPatternEntryBarVol))
      {
         entryBarOpen = fvgPatternEntryBarOpen;
         entryBarVol  = fvgPatternEntryBarVol;
         V2LogHuntEvent(huntIndex, "TOUCH_VOL_ENTRY_BAR",
                        StringFormat("maxVol %s before 1st FVG bar %s → FVG-pattern bar %s vol=%lld",
                                     TimeToString(maxVolBarOpen, TIME_DATE | TIME_MINUTES),
                                     TimeToString(firstFvgPatternBarOpen, TIME_DATE | TIME_MINUTES),
                                     TimeToString(entryBarOpen, TIME_DATE | TIME_MINUTES),
                                     (long)entryBarVol));
      }
      else
      {
         V2LogHuntEvent(huntIndex, "TOUCH_VOL_ENTRY_BAR",
                        StringFormat("maxVol %s before 1st FVG bar %s — FVG-pattern pick failed, keep maxVol",
                                     TimeToString(maxVolBarOpen, TIME_DATE | TIME_MINUTES),
                                     TimeToString(firstFvgPatternBarOpen, TIME_DATE | TIME_MINUTES)));
      }
   }
   else
   {
      V2LogHuntEvent(huntIndex, "TOUCH_VOL_ENTRY_BAR",
                     StringFormat("excl oldest %s → entry bar vol=%lld",
                                  TimeToString(windowStartOpen, TIME_DATE | TIME_MINUTES),
                                  (long)entryBarVol));
   }

   g_v2Hunts[huntIndex].postTouchFvgGateOpen = false;
   V2ClearTouchPointLine(huntIndex);

   if(g_v2Hunts[huntIndex].oppositeFvgFoundCount <= 0 &&
      g_v2Hunts[huntIndex].fvgMemCount <= 0)
   {
      g_v2Hunts[huntIndex].touchHitVolumeRejectLatch = true;
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     "touch vol hit but no FVG in session — no order, hunt stays ON");
      V2LogHuntEvent(huntIndex, "TOUCH_GATE_OFF",
                     StringFormat("touch lvl=%.5f vol ok — no FVG, gate closed (hunt ON)",
                                  g_v2Hunts[huntIndex].touchLevel));
      return;
   }

   V2LogHuntEvent(huntIndex, "TOUCH_GATE_OFF",
                  StringFormat("touch lvl=%.5f vol entry — hunt OFF + place",
                               g_v2Hunts[huntIndex].touchLevel));

   const bool     isBuy     = V2HuntExpectsBullishFvg(huntIndex);
   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   V2EndOppositeFvgHuntSession(huntIndex,
                               StringFormat("touch vol entry lvl=%.5f entryBar=%s vol=%lld",
                                            g_v2Hunts[huntIndex].touchLevel,
                                            TimeToString(entryBarOpen, TIME_DATE | TIME_MINUTES),
                                            (long)entryBarVol),
                               false);
   TryPlaceTouchVolumeBarTradeSetup(huntIndex, isBuy, entryBarOpen, entryBarVol,
                                    windowStartOpen, sessionId);
   g_v2Hunts[huntIndex].pendingTradeFvgValid = false;
}

//+------------------------------------------------------------------+
void V2StorePendingTradeFvg(const int huntIndex, const bool isBullishFairValueGap,
                            const double zoneLowPrice, const double zoneHighPrice,
                            const datetime formationTime)
{
   g_v2Hunts[huntIndex].pendingTradeFvgValid      = true;
   g_v2Hunts[huntIndex].pendingTradeIsBullishFvg  = isBullishFairValueGap;
   g_v2Hunts[huntIndex].pendingTradeZoneLow       = zoneLowPrice;
   g_v2Hunts[huntIndex].pendingTradeZoneHigh      = zoneHighPrice;
   g_v2Hunts[huntIndex].pendingTradeFormationTime = formationTime;
}

//+------------------------------------------------------------------+
double V2FairValueGapZoneSize(const double zoneLowPrice, const double zoneHighPrice)
{
   return MathAbs(zoneHighPrice - zoneLowPrice);
}

//+------------------------------------------------------------------+
//| Earliest hunt-session FVG formation bar (newest / 3rd candle of 3-bar pattern). |
//+------------------------------------------------------------------+
bool V2TryGetEarliestHuntFvgFormationBarOpenTime(const int huntIndex, datetime &outFormationBarOpen)
{
   outFormationBarOpen = 0;
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return false;

   datetime earliest = 0;
   for(int i = 0; i < g_v2Hunts[huntIndex].fvgMemCount; i++)
   {
      const datetime barOpen = g_v2Hunts[huntIndex].fvgMem[i].fairValueGapBarOpenTime;
      if(barOpen == 0)
         continue;
      if(!V2FvgPolarityMatchesHunt(huntIndex, g_v2Hunts[huntIndex].fvgMem[i].isBullishFairValueGap))
         continue;
      if(earliest == 0 || barOpen < earliest)
         earliest = barOpen;
   }

   if(earliest == 0)
      return false;

   outFormationBarOpen = earliest;
   return true;
}

//+------------------------------------------------------------------+
//| 1st bar of earliest FVG pattern = oldest of 3 candles (shift+2 from formation). |
//+------------------------------------------------------------------+
bool V2TryGetEarliestHuntFvgFirstPatternBarOpen(const int huntIndex, datetime &outFirstBarOpen,
                                                 datetime &outFormationBarOpen)
{
   outFirstBarOpen     = 0;
   outFormationBarOpen = 0;
   if(!V2TryGetEarliestHuntFvgFormationBarOpenTime(huntIndex, outFormationBarOpen))
      return false;

   const int formationShift =
      iBarShift(_Symbol, InputM2NarrativeTimeframe, outFormationBarOpen, true);
   if(formationShift < 0)
      return false;

   const int firstShift = formationShift + 2;
   if(firstShift >= iBars(_Symbol, InputM2NarrativeTimeframe))
      return false;

   outFirstBarOpen = iTime(_Symbol, InputM2NarrativeTimeframe, firstShift);
   return outFirstBarOpen > 0;
}

//+------------------------------------------------------------------+
//| Same max-vol / leap pick as touch window, on FVG 3-bar pattern (excl oldest).   |
//+------------------------------------------------------------------+
bool V2TrySelectTouchVolEntryBarFromFvgPattern(const datetime firstBarOpen,
                                                const datetime formationBarOpen,
                                                datetime &outEntryBarOpen, long &outEntryBarVol)
{
   outEntryBarOpen = 0;
   outEntryBarVol  = -1;

   long volumes[];
   int  volumeCount = 0;
   if(!M2CollectTickVolumesInOpenTimeWindow(firstBarOpen, formationBarOpen, volumes, volumeCount))
      return false;

   return M2FindMaxVolumeBarOpenTimeExcludingOldest(volumes, volumeCount, firstBarOpen,
                                                     formationBarOpen, outEntryBarOpen,
                                                     outEntryBarVol);
}

//+------------------------------------------------------------------+
//| Default: 2nd FVG when >=2; use 1st if its gap > 2× the 2nd FVG gap. |
//+------------------------------------------------------------------+
int V2SelectTradeFvgMemIndexForHunt(const int huntIndex)
{
   const int count = g_v2Hunts[huntIndex].fvgMemCount;
   if(count <= 0)
      return -1;
   if(count == 1)
      return 0;

   const double firstGapSize =
      V2FairValueGapZoneSize(g_v2Hunts[huntIndex].fvgMem[0].fairValueGapZoneLowPrice,
                             g_v2Hunts[huntIndex].fvgMem[0].fairValueGapZoneHighPrice);
   const double secondGapSize =
      V2FairValueGapZoneSize(g_v2Hunts[huntIndex].fvgMem[1].fairValueGapZoneLowPrice,
                             g_v2Hunts[huntIndex].fvgMem[1].fairValueGapZoneHighPrice);

   if(secondGapSize > 0.0 && firstGapSize > 2.0 * secondGapSize)
      return 0;

   return 1;
}

//+------------------------------------------------------------------+
bool V2ResolveTradeFvgForHunt(const int huntIndex, bool &outIsBullishFvg, double &outZoneLow,
                              double &outZoneHigh, datetime &outFormationTime)
{
   outIsBullishFvg    = false;
   outZoneLow         = 0.0;
   outZoneHigh        = 0.0;
   outFormationTime   = 0;

   if(g_v2Hunts[huntIndex].fvgMemCount >= 1)
   {
      const int memIndex = V2SelectTradeFvgMemIndexForHunt(huntIndex);
      if(memIndex < 0)
         return false;

      outIsBullishFvg  = g_v2Hunts[huntIndex].fvgMem[memIndex].isBullishFairValueGap;
      outZoneLow       = g_v2Hunts[huntIndex].fvgMem[memIndex].fairValueGapZoneLowPrice;
      outZoneHigh      = g_v2Hunts[huntIndex].fvgMem[memIndex].fairValueGapZoneHighPrice;
      outFormationTime = g_v2Hunts[huntIndex].fvgMem[memIndex].fairValueGapBarOpenTime;
      return (outFormationTime != 0);
   }

   if(g_v2Hunts[huntIndex].pendingTradeFvgValid && g_v2Hunts[huntIndex].pendingTradeFormationTime != 0)
   {
      outIsBullishFvg  = g_v2Hunts[huntIndex].pendingTradeIsBullishFvg;
      outZoneLow       = g_v2Hunts[huntIndex].pendingTradeZoneLow;
      outZoneHigh      = g_v2Hunts[huntIndex].pendingTradeZoneHigh;
      outFormationTime = g_v2Hunts[huntIndex].pendingTradeFormationTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void V2TryPlacePendingFvgTradesAfterHuntOff(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;

   bool     tradeIsBullishFvg  = false;
   double   tradeZoneLow       = 0.0;
   double   tradeZoneHigh      = 0.0;
   datetime tradeFormationTime = 0;
   if(!V2ResolveTradeFvgForHunt(huntIndex, tradeIsBullishFvg, tradeZoneLow, tradeZoneHigh,
                                tradeFormationTime))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt OFF — no FVG for trade");
      return;
   }

   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   const int      fvgCount  = g_v2Hunts[huntIndex].fvgMemCount;
   const int      memIndex  = V2SelectTradeFvgMemIndexForHunt(huntIndex);
   const int      tradeIdx  = (memIndex >= 0 ? memIndex + 1 : 1);
   string         pickNote  = "";
   if(fvgCount >= 2 && memIndex == 0)
   {
      const double g1 = V2FairValueGapZoneSize(g_v2Hunts[huntIndex].fvgMem[0].fairValueGapZoneLowPrice,
                                               g_v2Hunts[huntIndex].fvgMem[0].fairValueGapZoneHighPrice);
      const double g2 = V2FairValueGapZoneSize(g_v2Hunts[huntIndex].fvgMem[1].fairValueGapZoneLowPrice,
                                               g_v2Hunts[huntIndex].fvgMem[1].fairValueGapZoneHighPrice);
      pickNote = StringFormat(" (1st gap %.5f > 2×2nd %.5f)", g1, g2);
   }
   V2LogHuntEvent(huntIndex, "TRADE_AFTER_HUNT_OFF",
                  StringFormat("trade FVG #%d of %d %s %s%s",
                               tradeIdx, MathMax(fvgCount, 1),
                               IntegerToString((long)tradeFormationTime),
                               tradeIsBullishFvg ? "bull" : "bear", pickNote));

   double   h4LegRange = 0.0;
   datetime h4LegEnd   = 0;
   if(!V4ResolveH4SameDirLegRangeForTp(tradeIsBullishFvg, h4LegRange, h4LegEnd))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("no completed H4 %s leg for TP",
                                  tradeIsBullishFvg ? "up" : "down"));
      g_v2Hunts[huntIndex].pendingTradeFvgValid = false;
      return;
   }

   V2LogHuntEvent(huntIndex, "TRADE_H4_LEG_TP",
                  StringFormat("%s leg H-L=%.5f end=%s",
                               tradeIsBullishFvg ? "up" : "down", h4LegRange,
                               TimeToString(h4LegEnd, TIME_DATE | TIME_MINUTES)));

   TryPlaceOppositeFvgTradeSetup(tradeIsBullishFvg, tradeZoneLow, tradeZoneHigh,
                                 tradeFormationTime, sessionId, h4LegRange);
   g_v2Hunts[huntIndex].pendingTradeFvgValid = false;
}

//+------------------------------------------------------------------+
void V2TryPlaceFvgAndEndHuntAfterRecalcSkip(const int huntIndex, const bool isBullishFairValueGap,
                                             const double zoneLowPrice, const double zoneHighPrice,
                                             const datetime formationTime)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;
   if(g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime == 0 || formationTime == 0)
      return;

   const datetime prevBarOpen = iTime(_Symbol, InputM2NarrativeTimeframe, 2);
   if(prevBarOpen != g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime)
      return;

   if(!V2FvgPolarityMatchesHunt(huntIndex, isBullishFairValueGap))
      return;

   V2LogHuntEvent(huntIndex, "FVG_AFTER_TOUCH_RECALC_SKIP",
                  StringFormat("%s zone=%.5f-%.5f skipBar=%s fvgBar=%s",
                               isBullishFairValueGap ? "bull" : "bear",
                               zoneLowPrice, zoneHighPrice,
                               TimeToString(g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime,
                                            TIME_DATE | TIME_MINUTES),
                               TimeToString(formationTime, TIME_DATE | TIME_MINUTES)));

   double   h4LegRange = 0.0;
   datetime h4LegEnd   = 0;
   if(!V4ResolveH4SameDirLegRangeForTp(isBullishFairValueGap, h4LegRange, h4LegEnd))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("FVG after recalc skip — no completed H4 %s leg for TP",
                                  isBullishFairValueGap ? "up" : "down"));
      g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime = 0;
      V2EndOppositeFvgHuntSession(huntIndex,
                                  StringFormat("FVG after recalc skip — no H4 %s leg for TP",
                                               isBullishFairValueGap ? "up" : "down"),
                                  false);
      return;
   }

   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime = 0;
   V2EndOppositeFvgHuntSession(huntIndex,
                               StringFormat("FVG after touch recalc skip bar=%s fvgBar=%s",
                                            TimeToString(prevBarOpen, TIME_DATE | TIME_MINUTES),
                                            TimeToString(formationTime, TIME_DATE | TIME_MINUTES)),
                               false);
   TryPlaceOppositeFvgTradeSetup(isBullishFairValueGap, zoneLowPrice, zoneHighPrice,
                                 formationTime, sessionId, h4LegRange);
}

//+------------------------------------------------------------------+
void V2EndOppositeFvgHuntSession(const int huntIndex, const string offReason,
                                  const bool tryPlaceTradeAfterOff)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   const string reason = (StringLen(offReason) > 0 ? offReason : "unspecified");
   V2LogHuntEvent(huntIndex, "HUNT_OFF",
                  StringFormat("%s | HS%lld hunt=%s touchLvl=%.5f fvgs=%d gate=%s",
                               reason,
                               (long)g_v2Hunts[huntIndex].sessionId,
                               g_v2Hunts[huntIndex].h4HighWasBreached ? "bull/buy" : "bear/sell",
                               g_v2Hunts[huntIndex].touchLevel,
                               g_v2Hunts[huntIndex].oppositeFvgFoundCount,
                               g_v2Hunts[huntIndex].postTouchFvgGateOpen ? "open" : "closed"));

   g_v2Hunts[huntIndex].active = false;
   V2ClearTouchPointLine(huntIndex);
   V2ClearImpulseBufferZone(huntIndex);
   V2ClearTouchRecalcBufferZone(huntIndex);
   if(tryPlaceTradeAfterOff)
      V2TryPlacePendingFvgTradesAfterHuntOff(huntIndex);
}

//+------------------------------------------------------------------+
void V2ClearImpulseBufferZone(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   if(g_v2Hunts[huntIndex].sessionId != 0)
      ObjectDelete(0, V2ImpulseObjectName(g_v2Hunts[huntIndex].sessionId));
}

//+------------------------------------------------------------------+
void V2UpdateImpulseBufferZone(const int huntIndex)
{
   if(!H4LqChartDrawEnabled(InputDrawImpulseCancelBufferZone) || !g_v2Hunts[huntIndex].active)
   {
      V2ClearImpulseBufferZone(huntIndex);
      return;
   }

   double zoneLow = 0.0;
   double zoneHigh = 0.0;
   double cancelLimitPrice = 0.0;
   if(!H4BreachImpulseCancelZonePrices(V2HuntExpectsBullishFvg(huntIndex),
                                        g_v2Hunts[huntIndex].h4BreachedLegLevelPrice,
                                        zoneLow, zoneHigh, cancelLimitPrice) ||
      g_v2Hunts[huntIndex].sessionId == 0)
   {
      V2ClearImpulseBufferZone(huntIndex);
      return;
   }

   datetime timeRight = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(timeRight <= g_v2Hunts[huntIndex].sessionId)
      timeRight = g_v2Hunts[huntIndex].sessionId + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);
   const datetime timeLeft = g_v2Hunts[huntIndex].sessionId;
   const string objName = V2ImpulseObjectName(g_v2Hunts[huntIndex].sessionId);
   if(ObjectFind(0, objName) < 0)
   {
      if(!ObjectCreate(0, objName, OBJ_RECTANGLE, 0, timeLeft, zoneHigh, timeRight, zoneLow))
         return;
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, timeLeft);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, zoneHigh);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeRight);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, zoneLow);
   }
   ObjectSetInteger(0, objName, OBJPROP_COLOR, InputImpulseCancelBufferColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, objName, OBJPROP_FILL, false);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void V2UpdateAllImpulseBufferZones()
{
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
   {
      if(g_v2Hunts[i].active)
         V2UpdateImpulseBufferZone(i);
      else
         V2ClearImpulseBufferZone(i);
   }
}

//+------------------------------------------------------------------+
void V2ClearTouchRecalcBufferZone(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   if(g_v2Hunts[huntIndex].sessionId != 0)
      ObjectDelete(0, V2TouchRecalcBufferObjectName(g_v2Hunts[huntIndex].sessionId));
}

//+------------------------------------------------------------------+
//| Hollow band: N% M2 chart height at same-dir leg extreme (fallback: hunt path extreme). |
//+------------------------------------------------------------------+
void V2UpdateTouchRecalcBufferZone(const int huntIndex)
{
   if(!H4LqChartDrawEnabled(InputDrawHuntTouchRecalcBufferZone) ||
      InputHuntTouchRecalcPercentBeforeSameDirExtreme <= 0.0 ||
      !g_v2Hunts[huntIndex].active)
   {
      V2ClearTouchRecalcBufferZone(huntIndex);
      return;
   }

   double huntExtreme = 0.0;
   if(!V2GetSameDirExtremeWhileHuntOn(huntIndex, huntExtreme) ||
      g_v2Hunts[huntIndex].sessionId == 0)
   {
      V2ClearTouchRecalcBufferZone(huntIndex);
      return;
   }

   const double referenceHeight = ReferenceChartHeightForFairValueGapFilterM2();
   if(referenceHeight <= 0.0)
   {
      V2ClearTouchRecalcBufferZone(huntIndex);
      return;
   }

   double anchorExtreme = 0.0;
   if(!V2TryGetTouchRecalcBufferAnchorExtreme(huntIndex, anchorExtreme))
      anchorExtreme = huntExtreme;

   const double band =
      referenceHeight * (InputHuntTouchRecalcPercentBeforeSameDirExtreme / 100.0);

   datetime timeRight = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(timeRight <= g_v2Hunts[huntIndex].sessionId)
      timeRight = g_v2Hunts[huntIndex].sessionId + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);

   double zoneLow  = 0.0;
   double zoneHigh = 0.0;
   if(V2HuntExpectsBullishFvg(huntIndex))
   {
      zoneHigh = anchorExtreme + band;
      zoneLow  = anchorExtreme;
   }
   else
   {
      zoneLow  = anchorExtreme - band;
      zoneHigh = anchorExtreme;
   }

   const datetime timeLeft = g_v2Hunts[huntIndex].sessionId;
   const string objName = V2TouchRecalcBufferObjectName(g_v2Hunts[huntIndex].sessionId);
   if(ObjectFind(0, objName) < 0)
   {
      if(!ObjectCreate(0, objName, OBJ_RECTANGLE, 0, timeLeft, zoneHigh, timeRight, zoneLow))
         return;
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, timeLeft);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, zoneHigh);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeRight);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, zoneLow);
   }
   ObjectSetInteger(0, objName, OBJPROP_COLOR, InputHuntTouchRecalcBufferColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, objName, OBJPROP_FILL, false);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void V2UpdateAllTouchRecalcBufferZones()
{
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
   {
      if(g_v2Hunts[i].active)
         V2UpdateTouchRecalcBufferZone(i);
      else
         V2ClearTouchRecalcBufferZone(i);
   }
}

//+------------------------------------------------------------------+
int V2ArmOppositeFvgHuntAfterH4Breach(const double h4Level, const bool h4HighBreached,
                                         const datetime breachedLegEndTime,
                                         const double barClose, const double barLow,
                                         const double barHigh)
{
   const int existing = V2FindActiveHuntByH4Leg(breachedLegEndTime, h4HighBreached);
   if(existing >= 0)
      return existing;

   const int huntIndex = V2AllocHuntSlot();
   if(huntIndex < 0)
      return -1;

   RememberH4VolumeBreachLevelSwept(breachedLegEndTime, h4HighBreached ? 1 : -1, h4Level);

   g_v2Hunts[huntIndex].active                         = true;
   g_v2Hunts[huntIndex].h4HighWasBreached             = h4HighBreached;
   g_v2Hunts[huntIndex].h4BreachedLegLevelPrice       = h4Level;
   g_v2Hunts[huntIndex].h4BreachedLegEndTime          = breachedLegEndTime;
   g_v2Hunts[huntIndex].closeWhenH4LiquidityBreached  = barClose;
   g_v2Hunts[huntIndex].pathMinLowSinceH4Breach       = barLow;
   g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach      = barHigh;
   g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach = barClose;
   g_v2Hunts[huntIndex].sessionId                      = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   V2ResetHuntSlotSessionCounters(huntIndex);
   V2InitTouchRecalcBufferAnchor(huntIndex);
   V2UpdateTouchLevelFromM2Swing(huntIndex);

   if(h4HighBreached)
   {
      double bandLow = 0.0;
      double bandHigh = 0.0;
      H4BreachBufferBandForUpLegHigh(h4Level, bandLow, bandHigh);
      V2LogHuntEvent(huntIndex, "HUNT_ON",
                     StringFormat("H4 up leg=%.5f wick band %.5f..%.5f leg=%s → bullish FVG",
                                  h4Level, bandLow, bandHigh,
                                  TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES)));
   }
   else
   {
      double bandLow = 0.0;
      double bandHigh = 0.0;
      H4BreachBufferBandForDownLegLow(h4Level, bandLow, bandHigh);
      V2LogHuntEvent(huntIndex, "HUNT_ON",
                     StringFormat("H4 down leg=%.5f wick band %.5f..%.5f leg=%s → bearish FVG",
                                  h4Level, bandLow, bandHigh,
                                  TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES)));
   }
   return huntIndex;
}

//+------------------------------------------------------------------+
void V2ProcessOneActiveHuntOnM2Bar(const int huntIndex, const double pointSize,
                                    const double barClose, const double barHigh,
                                    const double barLow, const double prevHigh,
                                    const double prevLow)
{
   if(!g_v2Hunts[huntIndex].active)
      return;

   const double pathMinBeforeBar = g_v2Hunts[huntIndex].pathMinLowSinceH4Breach;
   const double pathMaxBeforeBar = g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach;
   g_v2Hunts[huntIndex].pathMinLowSinceH4Breach  =
      MathMin(g_v2Hunts[huntIndex].pathMinLowSinceH4Breach, barLow);
   g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach =
      MathMax(g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach, barHigh);
   const double huntExtremeAtBarStart = g_v2Hunts[huntIndex].h4HighWasBreached
                                        ? pathMaxBeforeBar : pathMinBeforeBar;

   V2TryArmTouchRecalcBufferResumeOnCross(huntIndex, barHigh, barLow, barClose);
   if(g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross &&
      !g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg)
      V2BeginTouchRecalcBufferActiveLegTrack(huntIndex);
   if(!g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg &&
      g_m2Swing.currentSwingLeg.swingDirection == V2OppositeM2LegDirectionForHunt(huntIndex))
      V2BeginTouchRecalcBufferActiveLegTrack(huntIndex);
   V2SyncTouchRecalcBufferAnchorFromActiveLeg(huntIndex);

   double impulseZoneLow = 0.0;
   double impulseZoneHigh = 0.0;
   double impulseCancelLimitPrice = 0.0;
   if(H4BreachImpulseCancelZonePrices(V2HuntExpectsBullishFvg(huntIndex),
                                       g_v2Hunts[huntIndex].h4BreachedLegLevelPrice,
                                       impulseZoneLow, impulseZoneHigh, impulseCancelLimitPrice))
   {
      bool cancelHunt = false;
      if(V2HuntExpectsBullishFvg(huntIndex))
      {
         g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach =
            MathMin(g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach, barClose);
         if(g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach < impulseCancelLimitPrice)
            cancelHunt = true;
      }
      else
      {
         g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach =
            MathMax(g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach, barClose);
         if(g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach > impulseCancelLimitPrice)
            cancelHunt = true;
      }
      if(cancelHunt)
      {
         V2EndOppositeFvgHuntSession(huntIndex,
                                     StringFormat("impulse cancel close=%.5f limit=%.5f (H4 FAR %.1f%%)",
                                                  barClose, impulseCancelLimitPrice,
                                                  H4_BREACH_BUFFER_PERCENT_FAR),
                                     false);
         return;
      }
   }

   const bool touchSideBlocksBuffer = V2TouchSideBlocksBufferRecalc(huntIndex, barHigh, barLow, pointSize);
   const bool touchPointHitThisBar =
      touchSideBlocksBuffer && !g_v2Hunts[huntIndex].touchHitVolumeRejectLatch;

   if(g_v2Hunts[huntIndex].postTouchFvgGateOpen)
   {
      if(!touchSideBlocksBuffer)
         V2TryRecalcTouchOnHuntSameDirProgress(huntIndex, barHigh, barLow, barClose,
                                                false, "", huntExtremeAtBarStart);
      V2TryClearHuntFvgsOnSameDirectionBosWhileHuntOn(huntIndex);

      bool isBullishFairValueGap = false;
      double fairValueGapZoneLowPrice  = 0.0;
      double fairValueGapZoneHighPrice = 0.0;
      if(TryDetectFairValueGapPatternOnLastClosedBarM2(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                                       fairValueGapZoneHighPrice))
      {
         double gapSize = 0.0;
         double chartHeight = 0.0;
         double minGapRequired = 0.0;
         const bool gapMeetsMinSize =
            FairValueGapGapMeetsMinimumPercentOfRangeM2(fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                                                        gapSize, chartHeight, minGapRequired);

         const bool polarityMatchesHunt =
            V2FvgPolarityMatchesHunt(huntIndex, isBullishFairValueGap);

         if(polarityMatchesHunt && !gapMeetsMinSize)
         {
            const double gapPct = (chartHeight > 0.0 ? 100.0 * gapSize / chartHeight : 0.0);
            V2LogHuntEvent(huntIndex, "FVG_SKIP",
                           StringFormat("%s gap=%.5f (%.2f%% rng) need>=%.5f (%.1f%% of %.5f rng)",
                                        isBullishFairValueGap ? "bull" : "bear", gapSize, gapPct,
                                        minGapRequired, InputFairValueGapMinimumPercentOfChartRange, chartHeight));
         }
         else if(polarityMatchesHunt && gapMeetsMinSize)
         {
            const datetime newestBarOpenTime = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
            const datetime oldestBarOpenTime = iTime(_Symbol, InputM2NarrativeTimeframe, 3);
            if(newestBarOpenTime != 0 && oldestBarOpenTime != 0)
            {
               bool alreadyStored = false;
               for(int memoryIndex = 0; memoryIndex < g_v2Hunts[huntIndex].fvgMemCount; memoryIndex++)
               {
                  if(g_v2Hunts[huntIndex].fvgMem[memoryIndex].fairValueGapBarOpenTime == newestBarOpenTime)
                  {
                     alreadyStored = true;
                     break;
                  }
               }
               if(!alreadyStored &&
                  V2PushHuntFvgMemory(huntIndex, isBullishFairValueGap, fairValueGapZoneLowPrice,
                                      fairValueGapZoneHighPrice, newestBarOpenTime))
               {
                  V2DrawHuntFairValueGapZone(huntIndex, isBullishFairValueGap, fairValueGapZoneLowPrice,
                                             fairValueGapZoneHighPrice, oldestBarOpenTime, newestBarOpenTime);
                  g_v2Hunts[huntIndex].oppositeFvgFoundCount++;
                  const double markedGapPct = (chartHeight > 0.0 ? 100.0 * gapSize / chartHeight : 0.0);
                  V2LogHuntEvent(huntIndex, "FVG_MARKED",
                                 StringFormat("%s fvgs=%d zone=%.5f-%.5f gap=%.2f%%rng",
                                              isBullishFairValueGap ? "bull" : "bear",
                                              g_v2Hunts[huntIndex].oppositeFvgFoundCount,
                                              fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                                              markedGapPct));
                  V2StorePendingTradeFvg(huntIndex, isBullishFairValueGap, fairValueGapZoneLowPrice,
                                         fairValueGapZoneHighPrice, newestBarOpenTime);
                  V2TryPlaceFvgAndEndHuntAfterRecalcSkip(huntIndex, isBullishFairValueGap,
                                                         fairValueGapZoneLowPrice,
                                                         fairValueGapZoneHighPrice,
                                                         newestBarOpenTime);
               }
            }
         }
      }

      if(!g_v2Hunts[huntIndex].active)
         return;

      V2UpdateTouchLevelFromM2Swing(huntIndex);
      if(touchPointHitThisBar)
      {
         long     touchLegVolumes[];
         int      touchLegVolumeCount = 0;
         datetime touchVolWindowStart = 0;
         datetime touchVolWindowEnd   = 0;
         if(V2ValidateTouchHitOppositeM2LegVolume(huntIndex, 1, touchLegVolumes, touchLegVolumeCount,
                                                   touchVolWindowStart, touchVolWindowEnd))
         {
            V2LogHuntEvent(huntIndex, "TOUCH_HIT_VOL",
                           M2FormatTickVolumeArrayLog(touchLegVolumes, touchLegVolumeCount,
                                                       touchVolWindowStart, touchVolWindowEnd) + " ok");
            V2HandleTouchHitConfirmed(huntIndex, barHigh, barLow, barClose, touchLegVolumes,
                                       touchLegVolumeCount, touchVolWindowStart, touchVolWindowEnd);
         }
         else
            V2InvalidateTouchHitVolumeFailed(huntIndex, barClose, touchLegVolumes, touchLegVolumeCount,
                                              touchVolWindowStart, touchVolWindowEnd);
      }
   }

}

//+------------------------------------------------------------------+
void OnM2SwingLegDirectionChange(const int closingLegDirection, const int nextLegDirection)
{
   for(int huntIndex = 0; huntIndex < V2_MAX_HUNT_SESSIONS; huntIndex++)
   {
      V2OnTouchRecalcBufferLegChange(huntIndex, closingLegDirection, nextLegDirection);
      V2OnM2LegChangeForHunt(huntIndex, closingLegDirection, nextLegDirection);
   }
}

//+------------------------------------------------------------------+
bool TryDetectH4WickLiquidityBreachForLeg(const int swingDirection, const double breachLevel,
                                            const datetime huntLegKey, const double barHigh,
                                            const double barLow, const double prevHigh,
                                            const double prevLow, const double pointSize,
                                            double &outLevel, bool &outHighBreached,
                                            datetime &outLegEndTime)
{
   if(swingDirection == 0 || breachLevel <= 0.0 || huntLegKey == 0)
      return false;

   if(IsH4VolumeBreachLevelAlreadyBreached(swingDirection, breachLevel))
      return false;

   if(swingDirection == 1)
   {
      double bandLow = 0.0;
      double bandHigh = 0.0;
      H4BreachBufferBandForUpLegHigh(breachLevel, bandLow, bandHigh);
      const bool bufferCross =
         M2WickCrossesIntoH4UpBreachBuffer(bandLow, bandHigh, barHigh, prevHigh, pointSize);
      const bool levelCross =
         M2WickCrossesBelowLevel(breachLevel, barLow, prevLow, pointSize);
      if(!bufferCross && !levelCross)
         return false;

      return TryAcceptH4BreachForHunt(true, breachLevel, huntLegKey,
                                      outLevel, outHighBreached, outLegEndTime);
   }

   if(swingDirection == -1)
   {
      double bandLow = 0.0;
      double bandHigh = 0.0;
      H4BreachBufferBandForDownLegLow(breachLevel, bandLow, bandHigh);
      const bool bufferCross =
         M2WickCrossesIntoH4DownBreachBuffer(bandLow, bandHigh, barLow, prevLow, pointSize);
      const bool levelCross =
         M2WickCrossesAboveLevel(breachLevel, barHigh, prevHigh, pointSize);
      if(!bufferCross && !levelCross)
         return false;

      return TryAcceptH4BreachForHunt(false, breachLevel, huntLegKey,
                                      outLevel, outHighBreached, outLegEndTime);
   }

   return false;
}

//+------------------------------------------------------------------+
bool TryGetActiveH4LegVolumeBreachLevel(double &outBreachLevel, datetime &outVolumeBarOpenTime)
{
   outBreachLevel       = 0.0;
   outVolumeBarOpenTime = 0;

   const Swing activeLeg = g_h4Swing.currentSwingLeg;
   if(activeLeg.swingDirection == 0 || activeLeg.legStartTime == 0)
      return false;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(g_h4LegVolumeBreaches[i].legStartTime == activeLeg.legStartTime &&
         g_h4LegVolumeBreaches[i].swingDirection == activeLeg.swingDirection &&
         g_h4LegVolumeBreaches[i].legEndTime == 0 &&
         g_h4LegVolumeBreaches[i].breachLevelPrice > 0.0)
      {
         outBreachLevel       = g_h4LegVolumeBreaches[i].breachLevelPrice;
         outVolumeBarOpenTime = g_h4LegVolumeBreaches[i].volumeBarOpenTime;
         return outVolumeBarOpenTime > 0;
      }
   }

   if(g_h4ActiveLegVolumeTrack.legStartTime == activeLeg.legStartTime &&
      g_h4ActiveLegVolumeTrack.breachLevelPrice > 0.0 &&
      g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime > 0)
   {
      outBreachLevel       = g_h4ActiveLegVolumeTrack.breachLevelPrice;
      outVolumeBarOpenTime = g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
bool TryDetectH4WickLiquidityBreach(const double barHigh, const double barLow,
                                     const double prevHigh, const double prevLow,
                                     const double pointSize, double &outLevel,
                                     bool &outHighBreached, datetime &outLegEndTime)
{
   outLevel        = 0.0;
   outHighBreached = false;
   outLegEndTime   = 0;

   if(InputH4BreachBufferChartBarCount < 1)
      return false;

   const Swing activeLeg = g_h4Swing.currentSwingLeg;
   if(activeLeg.swingDirection != 0 && activeLeg.legStartTime != 0)
   {
      double breachLevel = 0.0;
      datetime volumeBarOpenTime = 0;
      if(TryGetActiveH4LegVolumeBreachLevel(breachLevel, volumeBarOpenTime) &&
         IsH4BarWithinBreachBufferChartWindow(volumeBarOpenTime))
      {
         if(TryDetectH4WickLiquidityBreachForLeg(activeLeg.swingDirection, breachLevel,
                                                  activeLeg.legStartTime, barHigh, barLow,
                                                  prevHigh, prevLow, pointSize,
                                                  outLevel, outHighBreached, outLegEndTime))
            return true;
      }
   }

   for(int legIndex = g_h4Swing.swingHistoryCount - 1; legIndex >= 0; legIndex--)
   {
      const Swing leg = g_h4Swing.swingHistory[legIndex];
      if(leg.swingDirection != 1 || leg.legEndTime == 0)
         continue;

      if(!IsH4LegVolumeBreachActiveInBufferWindow(leg.legEndTime, 1))
         continue;

      double breachLevel = 0.0;
      datetime volumeBarOpenTime = 0;
      if(!TryResolveH4LegVolumeBreachLevel(leg.legStartTime, leg.legEndTime, 1,
                                            breachLevel, volumeBarOpenTime))
         continue;

      if(TryDetectH4WickLiquidityBreachForLeg(1, breachLevel, leg.legEndTime, barHigh, barLow,
                                               prevHigh, prevLow, pointSize,
                                               outLevel, outHighBreached, outLegEndTime))
         return true;
   }

   for(int legIndex = g_h4Swing.swingHistoryCount - 1; legIndex >= 0; legIndex--)
   {
      const Swing leg = g_h4Swing.swingHistory[legIndex];
      if(leg.swingDirection != -1 || leg.legEndTime == 0)
         continue;

      if(!IsH4LegVolumeBreachActiveInBufferWindow(leg.legEndTime, -1))
         continue;

      double breachLevel = 0.0;
      datetime volumeBarOpenTime = 0;
      if(!TryResolveH4LegVolumeBreachLevel(leg.legStartTime, leg.legEndTime, -1,
                                            breachLevel, volumeBarOpenTime))
         continue;

      if(TryDetectH4WickLiquidityBreachForLeg(-1, breachLevel, leg.legEndTime, barHigh, barLow,
                                               prevHigh, prevLow, pointSize,
                                               outLevel, outHighBreached, outLegEndTime))
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
void ProcessBosOppositeFairValueGapWindow()
{
   if(!InputEnableOppositeFvgHuntAfterH4Breach)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double barClose  = iClose(_Symbol, InputM2NarrativeTimeframe, 1);
   const double barHigh   = iHigh(_Symbol, InputM2NarrativeTimeframe, 1);
   const double barLow    = iLow(_Symbol, InputM2NarrativeTimeframe, 1);
   const double prevHigh  = iHigh(_Symbol, InputM2NarrativeTimeframe, 2);
   const double prevLow   = iLow(_Symbol, InputM2NarrativeTimeframe, 2);

   for(int huntIndex = 0; huntIndex < V2_MAX_HUNT_SESSIONS; huntIndex++)
   {
      if(g_v2Hunts[huntIndex].active)
         V2ProcessOneActiveHuntOnM2Bar(huntIndex, pointSize, barClose, barHigh, barLow,
                                       prevHigh, prevLow);
   }

   double h4Level = 0.0;
   bool h4HighBreached = false;
   datetime breachedLegEndTime = 0;
   if(TryDetectH4WickLiquidityBreach(barHigh, barLow, prevHigh, prevLow, pointSize,
                                      h4Level, h4HighBreached, breachedLegEndTime))
   {
      const int sameLegHunt = V2FindActiveHuntByH4Leg(breachedLegEndTime, h4HighBreached);
      if(sameLegHunt < 0)
      {
         const int samePolarityHunt = V2FindActiveHuntByBreachPolarity(h4HighBreached);
         if(samePolarityHunt >= 0)
         {
            V2LogHuntEvent(samePolarityHunt, "HUNT_RESTART",
                           StringFormat("%s breach new leg=%s (replaces prior %s hunt)",
                                        h4HighBreached ? "H4 high" : "H4 low",
                                        TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES),
                                        h4HighBreached ? "high" : "low"));
            V2AbortHuntSessionForRestart(samePolarityHunt);
         }
         V2ArmOppositeFvgHuntAfterH4Breach(h4Level, h4HighBreached, breachedLegEndTime,
                                            barClose, barLow, barHigh);
      }
   }

   V2UpdateAllImpulseBufferZones();
   V2UpdateAllTouchRecalcBufferZones();
}

//+------------------------------------------------------------------+
