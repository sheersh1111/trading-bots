//+------------------------------------------------------------------+
//| h4_lq.mq5                                                         |
//| H4 primary narrative + configurable secondary TF — liquidity hunt |
//| v1.27: bull limit @ top+1%rng when bid>top+1%rng; bear limit @ low−1%rng mirrored      |
//+------------------------------------------------------------------+
#define H4_LQ_VERSION "1.27"
#property copyright ""
#property version   H4_LQ_VERSION
#property description "h4_lq — configurable narrative TFs, M15-style breach hunt + opposite FVG"

#include <Trade\Trade.mqh>

input group "Narrative timeframes"
input ENUM_TIMEFRAMES InputM15NarrativeTimeframe = PERIOD_M15; // primary: breach legs, BOS, liquidity pivots
input ENUM_TIMEFRAMES InputM2NarrativeTimeframe  = PERIOD_M2;  // secondary: FVG, hunt, entry management

input bool   InputSwitchChartToM15       = true;
input int    InputWarmupBars             = 500;  // 0 = off: replay closed M15 bars on attach
input bool   InputDrawM15SwingLegVisuals = true;
input color  InputM15SwingTrendLineColor = clrGold;

input bool   InputDrawM2SwingLegs        = false;
input color  InputM2SwingLineColor       = clrMediumPurple;
input int    InputM2SwingWarmupBars      = 500; // 0 = off: replay M2 on attach (plot_swing_h1_m5_copy)

input group "M15 breach → opposite M2 FVG (plot_swing_m2_copy)"
input bool   InputEnableOppositeFvgHuntAfterM15Breach = true;
input bool   InputEndHuntOnOppositeM15LegBeforeTouch = true; // on: hunt OFF if touch line set but price never hit it when opposite M15 leg closes (no orders)
input bool   InputDrawBosOppositeFairValueGapZones   = true;
input double InputM15BreachAnticipationPercentBelowUpHigh = 2.0;  // 0=exact leg high; wick cross (high − N% M2 range) arms hunt
input double InputM15BreachAnticipationPercentAboveDownLow = 2.0; // 0=exact leg low; wick cross (low + N% M2 range) arms hunt
input int    InputM15LiquidityPivotLookbackBars = 1166; // M15 swing legs: up-leg highs / down-leg lows dominant vs newer same-dir legs
input double InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg = 20.0; // 0=off; % of M2 chart range from breach level
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

input group "M15 BOS trade direction bias"
input bool   InputEnableM15BosTradeDirectionBias = true;  // trade with last M15 close-cross BOS (bull/bear)
input bool   InputShowM15BosBiasHud              = true;  // top-right ↑ green / ↓ red (plot_swing_m2 style)

const double M15_BREACH_ANCHOR_MULTIPLIER = 0.5; // wick+body vs prior 5-bar avg — breaches / hunt / liquidity pivots
const double M15_BOS_ANCHOR_MULTIPLIER    = 1.0; // full bar range vs prior 5-bar avg — BOS only (plot_swing_m15)

input group "FVG trade (M2 opposite FVG)"
input bool   InputEnableAutomatedTrading = true;   // false = log trade plan only (no orders)
input double InputFvgTradeMinTickVolumePercentOfM2Avg = 50.0; // 0=off; formation bar tick vol vs prior M2 bars
input int    InputFvgTradeTickVolumeAvgM2BarCount     = 30;   // bars after formation (older) for average
input bool   InputDrawTradeSwingProximityZones = true; // on order: group M2 swing highs/lows + hollow buffer rects
input int    InputTradeSwingLookbackM2Bars     = 292;  // M2 bars scanned for swing highs (bull) / lows (bear)
input double InputTradeSwingProximityPercentOfChartRange = 10.0; // cluster + buffer band = N% of M2 chart height
input color  InputTradeSwingProximityRectColorBull = clrLimeGreen;
input color  InputTradeSwingProximityLineColorBull = clrLimeGreen;
input color  InputTradeSwingProximityRectColorBear = clrCrimson;
input color  InputTradeSwingProximityLineColorBear = clrCrimson;
input double InputTradeSwingTpMinRewardToRisk = 2.0; // skip line/TP when reward:risk below this (1:2 = 2.0)

input group "BOS SL/TP management"
input bool   InputEnableBosMoveSlAndTp = false; // disable trailing/moving SL & TP on BOS for now

const string H4_LQ_LOG_PREFIX = "h4_lq";

// --- hard-coded trade sizing (per FVG setup = 3 OV orders) ---
const double   LQ_RISK_USD_PER_TRADE              = 50.0;
const ulong    LQ_EXPERT_MAGIC                    = 940029;
const double   LQ_STOP_BUFFER_PERCENT_CHART       = 1.0;
const int      LQ_FVG_TRADE_MAX_M2_BAR_SHIFT      = 24;
const int      LQ_TP_COUNT                        = 3;
const int      LQ_TOUCH_GRACE_M2_BARS             = 2;

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

const string ChartObjectNamePrefixM15SwingTrendLine = "LQ2_M15_Swing_";
const string ChartObjectNamePrefixM15SwingLabelText = "LQ2_M15_SWLBL_";
const string PFX_M2_TREND = "LQ2_M2_TR_";
const string PFX_M2_LBL   = "LQ2_M2_LB_";
const string LQ_OBJ_PREFIX_FVG_RECT = "LQ2_M2_FVG_";
const string LQ_OBJ_PREFIX_FVG_LBL  = "LQ2_M2_FVGT_";
const string LQ_OBJ_HUNT_HUD        = "LQ2_HUNT_HUD";
const string LQ_OBJ_M15_BIAS_HUD    = "LQ4_M15_BIAS";
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
   bool     m15HighWasBreached;
   double   m15BreachedLegLevelPrice;
   datetime m15BreachedLegEndTime;
   double   closeWhenM15LiquidityBreached;
   double   pathMinLowSinceM15Breach;
   double   pathMaxHighSinceM15Breach;
   double   sameDirExtremeAtLastTouchRecalc; // path high/low snapshot at last V2_TOUCH_RECALC
   double   touchRecalcBufferAnchor;         // tracks active same-dir M2 leg extreme while leg is open
   bool     touchRecalcBufferTrackActiveLeg;
   bool     touchRecalcBufferResumeAfterCross; // armed when price enters/crosses frozen buffer; resume on next same-dir leg
   double   impulseCloseExtremeSinceM15Breach;
   datetime sessionId;
   int      oppositeFvgFoundCount;
   double   touchLevel;
   bool     touchLevelReady;
   bool     touchPointTouched;
   datetime touchHitM2BarOpenTime; // M2 bar open when TOUCH_HIT confirmed
   int      touchGraceBarsRemaining; // post-touch: wait up to N closed M2 bars for FVG
   bool     postTouchFvgGateOpen;  // false after touch wait ends with no FVG; reopens on same-dir BOS
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
#define M15LegLiquidityBreachMemoryCapacity   24

struct M15LegLiquidityBreachRecord
{
   datetime legEndTime;
   bool     isUpLegHighBreach;
};

#define M15_LIQUIDITY_PIVOT_CAPACITY 600
#define M15_REPLAY_LEG_CAPACITY      512

struct M15LiquidityPivot
{
   double   levelPrice;
   datetime legEndTime;
   double   legHighPrice;
   double   legLowPrice;
   int      swingDirection; // 1 = up leg (high liquidity), -1 = down leg (low liquidity)
};

struct M15ReplayLeg
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legEndTime;
   int      swingDirection;
};

SwingState     g_m15Swing;     // anchor 0.5 — breaches, chart legs, liquidity pivots
SwingState     g_m15BosSwing;  // anchor 1.0 — BOS close-cross levels only (no visuals)
SwingState     g_m2Swing;
LiquidityPool  g_liquidityPools[LiquidityPoolCapacity];
int            g_liquidityPoolCount = 0;

datetime g_lastM15BarOpen = 0;
datetime g_lastM2BarOpen  = 0;

V2HuntSession g_v2Hunts[V2_MAX_HUNT_SESSIONS];

M15LegLiquidityBreachRecord g_m15LegLiquidityBreaches[M15LegLiquidityBreachMemoryCapacity];
int                         g_m15LegLiquidityBreachCount = 0;

M15LiquidityPivot g_m15DescHighPivots[M15_LIQUIDITY_PIVOT_CAPACITY];
int               g_m15DescHighPivotCount = 0;
M15LiquidityPivot g_m15AscLowPivots[M15_LIQUIDITY_PIVOT_CAPACITY];
int               g_m15AscLowPivotCount = 0;

#define M15_BOS_RECORDED_LEG_CAPACITY 32

struct M15BosRecord
{
   int      direction;   // 1 = bull BOS, -1 = bear BOS
   datetime barOpenTime;
   datetime legEndTime;  // completed M15 leg that was broken (dedupe key)
   double   brokenLevel;
};

struct M15BosRecordedLeg
{
   int      direction;
   datetime legEndTime;
};

struct M15BosPendingConfirm
{
   bool     active;
   int      direction;        // 1 bull / -1 bear
   double   brokenLevel;
   datetime legEndTime;
   datetime breakBarOpenTime; // M15 bar that closed through the level (await 1 more close)
};

M15BosPendingConfirm g_m15BosPendingConfirm;
M15BosRecord        g_m15LastBosRecord;
bool                g_m15LastBosRecordValid     = false;
M15BosRecordedLeg   g_m15BosRecordedLegs[M15_BOS_RECORDED_LEG_CAPACITY];
int                 g_m15BosRecordedLegCount    = 0;
int                 g_m15LastLoggedEffectiveBias    = 0;
bool                g_m15EffectiveBiasLogReady      = false;
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
void   SwingCloseM15Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                            const int lastClosedBarShift = 1);
void   ProcessM15SwingStep(const int lastClosedBarShift = 1);
void   ProcessM15BosSwingStep(const int lastClosedBarShift = 1);
void   SwingCloseM15ToHistory(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                              const int lastClosedBarShift = 1);
void   WarmupM15SwingFromHistory();

void   SwingCloseM2Leg(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                       const string chartObjectNamePrefix, const string labelPrefix, const bool drawVisuals,
                       const int lastClosedBarShift = 1);
void   UpdateM2LiveSwingLegVisualIf(const SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                                    const bool drawVisuals);
void   ProcessSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int sh,
                               const color swingLineColor, const string trendPrefix, const string labelPrefix,
                               const bool drawVisuals, const bool replayOnly = false);
bool   CollectM2SwingExtremesBackwardFromFormation(const datetime formationTime, const int lookbackBars,
                                                    const int legDirection,
                                                    M2SwingExtremePoint &outPoints[], int &outPointCount);
bool   BuildTradeSwingGroupTakeProfits(const bool isBullishTrade, const datetime formationTime,
                                       const double entryPrice, const double stopLossPrice,
                                       double &outTakeProfitPrices[], int &outTakeProfitCount,
                                       const bool drawVisuals);
void   ProcessM2SwingStep();
void   WarmupM2SwingFromHistory();

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
bool   TryLatestM15CompletedUpLegHigh(double &outHigh);
bool   TryLatestM15CompletedDownLegLow(double &outLow);
bool   TrySecondLastM15CompletedUpLegHigh(double &outHigh);
bool   TrySecondLastM15CompletedDownLegLow(double &outLow);
bool   TryNthM15CompletedSwingLeg(const int swingDirection, const int nFromLatest,
                                  double &outLegHigh, double &outLegLow, datetime &outLegEndTime);
bool   IsM15LegLiquidityAlreadyBreached(const datetime legEndTime, const bool isUpLegHighBreach);
void   RememberM15LegLiquidityBreach(const datetime legEndTime, const bool isUpLegHighBreach);
void   RebuildM15LiquidityPivotLevels();
bool   TryDetectM15BosCrossOnBar(const int m15BarShift, int &outDirection,
                                 double &outBrokenLevel, datetime &outBarOpenTime,
                                 datetime &outLegEndTime);
void   ProcessM15BosOnM15Close(const int m15BarShift);
void   ClearM15BosPendingConfirm();
bool   M15BosCloseHoldsBeyondLevel(const int direction, const int m15BarShift, const double brokenLevel);
void   TryConfirmM15BosPendingOnBarClose(const int m15BarShift);
void   RecordM15BosBreak(const int direction, const datetime barOpenTime, const datetime legEndTime,
                         const double brokenLevel);
bool   M15BosAlreadyRecordedForLeg(const int direction, const datetime legEndTime);
void   ResetM15BosBiasState();
double ReferenceChartHeightForM2BarCount(const int barCount);
double ReferenceChartHeightForM2BarCountFromShift(const int newestBarShift, const int barCount);
int    GetM15TradeDirectionBias(); // 1 bull, -1 bear, 0 undefined/mixed/disabled-filter
void   LogM15TradeDirectionBiasIfChanged();
bool   FvgTradeAllowedByM15BosBias(const bool isBullishFairValueGap, string &outBlockReason);
void   RefreshM15BosBiasHud();
bool   M2WickCrossesAboveLevel(const double level, const double barHigh, const double prevHigh,
                               const double pointSize);
bool   M2WickCrossesBelowLevel(const double level, const double barLow, const double prevLow,
                               const double pointSize);
double M15BreachWickLevelForUpLegHigh(const double legHighPrice);
double M15BreachWickLevelForDownLegLow(const double legLowPrice);
bool   M15BreachLegIsWithinM2ChartRange(const datetime legEndTime, const bool m15HighBreached,
                                         const double legHigh, const double legLow);
bool   TryAcceptM15BreachForHunt(const bool m15HighBreached, const double legHigh, const double legLow,
                                const datetime legEnd, double &outLevel, bool &outHighBreached,
                                datetime &outLegEndTime);
bool   TryDetectM2BreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap, double &outBosLegLevelPrice);
void   V2InitHuntSlot(const int huntIndex);
void   V2InitAllHuntSlots();
int    V2CountActiveHunts();
int    V2AllocHuntSlot();
int    V2FindActiveHuntByM15Leg(const datetime legEndTime, const bool m15HighBreached);
int    V2FindActiveHuntByBreachPolarity(const bool m15HighBreached);
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
void   V2ResetHuntSlotSessionCounters(const int huntIndex);
double V2TouchLevelFromLegExtreme(const bool m15HighWasBreached, const double legLowPrice,
                                   const double legHighPrice);
bool   V2TryGetLastCompletedM2Leg(const int legDirection, double &outLegLow, double &outLegHigh);
bool   V2TryGetOppositeM2LegExtentsForTouch(const int huntIndex, double &outLegLow, double &outLegHigh);
bool   V2GetSameDirExtremeWhileHuntOn(const int huntIndex, double &outExtreme);
void   V2ApplyTouchLevelFromM2Leg(const int huntIndex, const double legLow, const double legHigh,
                                   const string logContext, const bool allowRecalc);
void   V2TryLockTouchLevelFromM2Leg(const int huntIndex, const double legLow, const double legHigh,
                                     const string logContext);
void   V2TryRecalcTouchOnHuntSameDirProgress(const int huntIndex, const double barHigh,
                                              const double barLow, const double barClose,
                                              const bool huntExtremeMovedThisBar,
                                              const bool forceBufferRecalc = false);
bool   V2DetectTouchRecalcBufferHit(const int huntIndex, const double barHigh, const double barLow,
                                     const double barClose, bool &outNearHuntExtreme,
                                     bool &outNearSameDirLegExtreme);
void   V2TryReopenPostTouchFvgGateOnBufferHit(const int huntIndex, const double barHigh,
                                               const double barLow, const double barClose,
                                               const bool huntExtremeMovedThisBar);
void   V2UpdateTouchLevelFromM2Swing(const int huntIndex);
void   V2DrawTouchPointLine(const int huntIndex);
void   V2ClearTouchPointLine(const int huntIndex);
void   V2RemoveHuntSessionFvgPlots(const int huntIndex);
void   V2TryClearHuntFvgsOnSameDirectionBosWhileHuntOn(const int huntIndex);
bool   V2TryDetectSameDirBosForHunt(const int huntIndex, string &outBosDetail);
void   V2TryReopenPostTouchFvgGateOnSameDirBos(const int huntIndex);
bool   V2TryDetectTouchOfStoredLevel(const int huntIndex, const double barClose, const double pointSize);
void   V2HandleTouchHitConfirmed(const int huntIndex, const double barClose);
void   V2TryPlacePreTouchFvgAndEndHuntOnTouchHit(const int huntIndex, const double barClose);
void   V2StorePendingTradeFvg(const int huntIndex, const bool isBullishFairValueGap,
                              const double zoneLowPrice, const double zoneHighPrice,
                              const datetime formationTime);
int    V2SelectTradeFvgMemIndexForHunt(const int huntIndex);
bool   V2IsFvgFormedDuringTouchGrace(const int huntIndex, const datetime formationTime);
bool   V2HuntHasPreTouchFvgBeforeBar(const int huntIndex, const datetime touchBarOpenTime);
int    V2SelectGracePeriodFvgMemIndexForHunt(const int huntIndex);
bool   V2ResolveGracePeriodTradeFvgForHunt(const int huntIndex, bool &outIsBullishFvg,
                                            double &outZoneLow, double &outZoneHigh,
                                            datetime &outFormationTime);
bool   V2ResolveTradeFvgForHunt(const int huntIndex, bool &outIsBullishFvg, double &outZoneLow,
                                double &outZoneHigh, datetime &outFormationTime);
void   V2TryPlacePendingFvgTradesAfterHuntOff(const int huntIndex, const bool fromGrace = false);
void   V2TryPlaceFvgAndEndHuntAfterRecalcSkip(const int huntIndex, const bool isBullishFairValueGap,
                                                const double zoneLowPrice, const double zoneHighPrice,
                                                const datetime formationTime);
void   V2TryPlaceFvgAndEndHuntOnTouchGrace(const int huntIndex, const bool isBullishFairValueGap,
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
bool   TryDetectM15WickLiquidityBreach(const double barHigh, const double barLow,
                                       const double prevHigh, const double prevLow,
                                       const double pointSize, double &outLevel,
                                       bool &outHighBreached, datetime &outLegEndTime);
int    V2ArmOppositeFvgHuntAfterM15Breach(const double m15Level, const bool m15HighBreached,
                                            const datetime breachedLegEndTime,
                                            const double barClose, const double barLow,
                                            const double barHigh);
void   V2EndOppositeFvgHuntSession(const int huntIndex, const bool tryPlaceTradeAfterOff = true,
                                     const bool fromGrace = false);
void   V2OnM15LegClosedForHunts(const int closedLegDirection, const datetime closedLegEndTime);
int    V2OppositeM15LegDirectionForHunt(const int huntIndex);

void   ApplyTradeFillingModeFromSymbol();
double M2FvgStopBufferPrice();
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
bool   V4ResolveM15SameDirLegRangeForTp(const bool isBullishFairValueGap, double &outLegRange,
                                        datetime &outLegEndTime);
bool   TryPlaceOppositeFvgTradeSetup(const bool isBullishFairValueGap, const double zoneLowPrice,
                                       const double zoneHighPrice, const datetime formationTime,
                                       const datetime huntSessionId, const double m15LegRange,
                                       const bool fromGrace = false);
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
   if(InputSwitchChartToM15)
   {
      ChartSetSymbolPeriod(0, _Symbol, InputM15NarrativeTimeframe);
      ChartRedraw(0);
   }

   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingLabelText, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_RECT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_LBL, -1, -1);
   ObjectDelete(0, LQ_OBJ_HUNT_HUD);
   ObjectsDeleteAll(0, LQ_OBJ_IMPULSE_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_RECALC_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_POINT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_RECT_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_LINE_PREFIX, -1, -1);

   ZeroMemory(g_m15Swing);
   ZeroMemory(g_m15BosSwing);
   ZeroMemory(g_m2Swing);
   g_liquidityPoolCount = 0;

   V2InitAllHuntSlots();
   g_m15LegLiquidityBreachCount       = 0;
   ResetM15BosBiasState();
   ResetHuntTradeState();

   WarmupM15SwingFromHistory();
   WarmupM2SwingFromHistory();
   ResetM15BosBiasState();
   RebuildM15LiquidityPivotLevels();
   g_m15LastLoggedEffectiveBias = GetM15TradeDirectionBias();
   g_m15EffectiveBiasLogReady   = true;

   g_lastM15BarOpen = iTime(_Symbol, InputM15NarrativeTimeframe, 0);
   g_lastM2BarOpen  = iTime(_Symbol, InputM2NarrativeTimeframe, 0);

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();

   PrintFormat("%s v%s | primary=%s secondary=%s",
               H4_LQ_LOG_PREFIX, H4_LQ_VERSION,
               EnumToString(InputM15NarrativeTimeframe),
               EnumToString(InputM2NarrativeTimeframe));

   RefreshLiquidityHuntHud();
   RefreshM15BosBiasHud();

   ChartRedraw(0);
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingLabelText, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_RECT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_LBL, -1, -1);
   ObjectDelete(0, LQ_OBJ_HUNT_HUD);
   ObjectDelete(0, LQ_OBJ_M15_BIAS_HUD);
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

   const datetime tM15 = iTime(_Symbol, InputM15NarrativeTimeframe, 0);
   if(tM15 != g_lastM15BarOpen)
   {
      g_lastM15BarOpen = tM15;
      ProcessM15SwingStep(1);
      ProcessM15BosSwingStep(1);
      RebuildM15LiquidityPivotLevels();
      ProcessM15BosOnM15Close(1);
      if(InputEnableM15BosTradeDirectionBias)
         LogM15TradeDirectionBiasIfChanged();
      RefreshM15BosBiasHud();
   }

   const datetime tM2 = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(tM2 != g_lastM2BarOpen)
   {
      g_lastM2BarOpen = tM2;
      if(InputEnableOppositeFvgHuntAfterM15Breach)
         ProcessBosOppositeFairValueGapWindow();
      ProcessM2SwingStep();
      ManageHuntOpenPositionsOnM2BarClose();
      RefreshLiquidityHuntHud();
   }
}

//+------------------------------------------------------------------+
void WarmupM15SwingFromHistory()
{
   if(InputWarmupBars <= 0)
      return;
   const int bars = iBars(_Symbol, InputM15NarrativeTimeframe);
   const int n = (int)MathMin(bars - 2, InputWarmupBars);
   if(n < 1)
      return;
   for(int k = n; k >= 1; k--)
   {
      ProcessM15SwingStep(k);
      ProcessM15BosSwingStep(k);
      RebuildM15LiquidityPivotLevels();
      ProcessM15BosOnM15Close(k);
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
                              InputDrawM2SwingLegs);
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
// plot_swing_h1_m5_copy SwingClose — M2 only (no H1 keyLevelId).
//+------------------------------------------------------------------+
void SwingCloseM2Leg(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                     const string chartObjectNamePrefix, const string labelPrefix, const bool drawVisuals,
                     const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.keyLevelId = 0;

   if(timeframe == InputM2NarrativeTimeframe && InputDrawM2SwingLegs)
      ObjectDelete(0, PFX_M2_TREND + "LIVE");

   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   const string chartObjectName =
      chartObjectNamePrefix + IntegerToString((long)swingState.currentSwingLeg.legEndTime);

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

   if(InputDrawM2SwingLegs)
   {
      datetime tRightDraw = swingState.currentSwingLeg.legEndTime;
      if(tRightDraw <= swingState.currentSwingLeg.legStartTime)
         tRightDraw = swingState.currentSwingLeg.legStartTime + (datetime)PeriodSeconds(timeframe);

      if(ObjectCreate(0, chartObjectName, OBJ_TREND, 0, swingState.currentSwingLeg.legStartTime,
                      trendLineStartPrice, tRightDraw, trendLineEndPrice))
      {
         ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, swingLineColor);
         ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, chartObjectName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      }

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
void UpdateM2LiveSwingLegVisualIf(const SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                                  const bool drawVisuals)
{
   if(timeframe != InputM2NarrativeTimeframe || !InputDrawM2SwingLegs)
      return;
   if(swingState.currentSwingLeg.swingDirection == 0)
      return;

   const string liveName = PFX_M2_TREND + "LIVE";
   datetime     tEnd     = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(tEnd <= swingState.currentSwingLeg.legStartTime)
      tEnd = swingState.currentSwingLeg.legStartTime + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);

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

   if(ObjectFind(0, liveName) >= 0)
      ObjectDelete(0, liveName);

   if(!ObjectCreate(0, liveName, OBJ_TREND, 0, swingState.currentSwingLeg.legStartTime, trendLineStartPrice,
                    tEnd, trendLineEndPrice))
      return;

   ObjectSetInteger(0, liveName, OBJPROP_COLOR, InputM2SwingLineColor);
   ObjectSetInteger(0, liveName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, liveName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, liveName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, liveName, OBJPROP_BACK, false);
   ObjectSetInteger(0, liveName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, liveName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
// plot_swing_h1_m5_copy ProcessSwingStepAtShift (M2 timeframe).
//+------------------------------------------------------------------+
void ProcessSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int sh,
                             const color swingLineColor, const string trendPrefix, const string labelPrefix,
                             const bool drawVisuals, const bool replayOnly)
{
   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, sh);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, sh);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, sh);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, sh);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);
   // Anchor tolerance: M2 = body vs 0.2× prior avg; M15 = wick AND body vs 0.5× prior avg.
   const double lastClosedBarBodyRange = MathAbs(lastClosedBarClose - lastClosedBarOpen);
   const double lastClosedBarWickRange  = lastClosedBarHigh - lastClosedBarLow;

   if(swingState.currentSwingLeg.swingDirection == 0)
   {
      if(candleDirection == 0)
         return;
      SwingStartNew(swingState, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow, sh);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      if(!replayOnly)
         UpdateM2LiveSwingLegVisualIf(swingState, timeframe, drawVisuals);
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
      (timeframe == InputM15NarrativeTimeframe) ? 0.5 : 0.2;
   const double minDecentRange = averageRangeFiveBars * anchorDecentMovementMultiplier;
   const bool isDecentMovement =
      (timeframe == InputM2NarrativeTimeframe)
      ? (lastClosedBarBodyRange > minDecentRange)
      : (lastClosedBarWickRange > minDecentRange && lastClosedBarBodyRange > minDecentRange);
   if(isDecentMovement && candleDirection == swingState.currentSwingLeg.swingDirection)
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

   int nextSwingDirection = swingState.currentSwingLeg.swingDirection;
   if(swingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < swingState.priceAnchorLevel)
      nextSwingDirection = -1;
   else if(swingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > swingState.priceAnchorLevel)
      nextSwingDirection = 1;

   if(nextSwingDirection == swingState.currentSwingLeg.swingDirection)
   {
      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);
      if(!replayOnly)
         UpdateM2LiveSwingLegVisualIf(swingState, timeframe, drawVisuals);
   }
   else
   {
      const int closingLegDirection = swingState.currentSwingLeg.swingDirection;

      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

      if(timeframe == InputM2NarrativeTimeframe && !replayOnly)
         OnM2SwingLegDirectionChange(closingLegDirection, nextSwingDirection);

      SwingCloseM2Leg(swingState, timeframe, swingLineColor, trendPrefix, labelPrefix, drawVisuals, sh);

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
         UpdateM2LiveSwingLegVisualIf(swingState, timeframe, drawVisuals);
   }
}

//+------------------------------------------------------------------+
void ProcessM2SwingStep()
{
   ProcessSwingStepAtShift(g_m2Swing, InputM2NarrativeTimeframe, 1, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL,
                           InputDrawM2SwingLegs);
}

//+------------------------------------------------------------------+
void SwingCloseM15Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                          const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   const double poolLowPrice  = swingState.currentSwingLeg.legLowPrice;
   const double poolHighPrice = swingState.currentSwingLeg.legHighPrice;
   const bool   isSupplyPool  = (swingState.currentSwingLeg.swingDirection == 1);
   PushLiquidityPoolFromClosedSwing(poolLowPrice, poolHighPrice, isSupplyPool);

   if(InputDrawM15SwingLegVisuals)
   {
      const string chartObjectName =
         ChartObjectNamePrefixM15SwingTrendLine + IntegerToString((long)swingState.currentSwingLeg.legEndTime);

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
         ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, InputM15SwingTrendLineColor);
         ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, chartObjectName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      }

      const bool isUplegSwingDirection = (swingState.currentSwingLeg.swingDirection == 1);
      DrawSwingLegLabel(ChartObjectNamePrefixM15SwingLabelText, swingState.currentSwingLeg.legEndTime,
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
void SwingCloseM15ToHistory(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
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
void ProcessM15SwingStepCore(SwingState &swingState, const int lastClosedBarShift,
                             const double anchorMultiplier, const bool useWickAndBodyForDecent,
                             const bool withBreachSideEffects)
{
   const ENUM_TIMEFRAMES timeframe = InputM15NarrativeTimeframe;
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
   if(isDecentMovement && candleDirection == swingState.currentSwingLeg.swingDirection)
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

   int nextSwingDirection = swingState.currentSwingLeg.swingDirection;
   if(swingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < swingState.priceAnchorLevel)
      nextSwingDirection = -1;
   else if(swingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > swingState.priceAnchorLevel)
      nextSwingDirection = 1;

   if(nextSwingDirection == swingState.currentSwingLeg.swingDirection)
   {
      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);
      return;
   }

   SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

   if(withBreachSideEffects)
      SwingCloseM15Context(swingState, timeframe, sh);
   else
      SwingCloseM15ToHistory(swingState, timeframe, sh);

   Swing closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
   if(withBreachSideEffects)
      V2OnM15LegClosedForHunts(closedSwingLeg.swingDirection, closedSwingLeg.legEndTime);

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
//| M15 breach/hunt swing legs: anchor 0.5 (wick + body vs prior 5-bar avg). |
//+------------------------------------------------------------------+
void ProcessM15SwingStep(const int lastClosedBarShift = 1)
{
   ProcessM15SwingStepCore(g_m15Swing, lastClosedBarShift, M15_BREACH_ANCHOR_MULTIPLIER, true, true);
}

//+------------------------------------------------------------------+
//| M15 BOS swing legs: anchor 1.0 (full range vs prior 5-bar avg), memory only. |
//+------------------------------------------------------------------+
void ProcessM15BosSwingStep(const int lastClosedBarShift = 1)
{
   ProcessM15SwingStepCore(g_m15BosSwing, lastClosedBarShift, M15_BOS_ANCHOR_MULTIPLIER, false, false);
}

//+------------------------------------------------------------------+
void RefreshLiquidityHuntHud()
{
   if(!InputShowLiquidityHuntHud)
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
//| M15 BOS cross: close cross vs latest same-dir leg on g_m15BosSwing (anchor 1.0). |
//+------------------------------------------------------------------+
bool TryDetectM15BosCrossOnBar(const int m15BarShift, int &outDirection,
                               double &outBrokenLevel, datetime &outBarOpenTime,
                               datetime &outLegEndTime)
{
   outDirection   = 0;
   outBrokenLevel = 0.0;
   outBarOpenTime = 0;
   outLegEndTime  = 0;

   if(m15BarShift < 0 || g_m15BosSwing.swingHistoryCount < 1)
      return false;

   const ENUM_TIMEFRAMES tf = InputM15NarrativeTimeframe;
   const double closePrice  = iClose(_Symbol, tf, m15BarShift);
   const double prevClose   = iClose(_Symbol, tf, m15BarShift + 1);
   const double pointSize   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   outBarOpenTime = iTime(_Symbol, tf, m15BarShift);
   if(outBarOpenTime == 0)
      return false;

   for(int historyIndex = g_m15BosSwing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m15BosSwing.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double legHigh = g_m15BosSwing.swingHistory[historyIndex].legHighPrice;
      if(closePrice > legHigh + pointSize && prevClose <= legHigh + pointSize)
      {
         outDirection   = 1;
         outBrokenLevel = legHigh;
         outLegEndTime  = g_m15BosSwing.swingHistory[historyIndex].legEndTime;
         return true;
      }
      break;
   }

   for(int historyIndex = g_m15BosSwing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m15BosSwing.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double legLow = g_m15BosSwing.swingHistory[historyIndex].legLowPrice;
      if(closePrice < legLow - pointSize && prevClose >= legLow - pointSize)
      {
         outDirection   = -1;
         outBrokenLevel = legLow;
         outLegEndTime  = g_m15BosSwing.swingHistory[historyIndex].legEndTime;
         return true;
      }
      break;
   }

   return false;
}

//+------------------------------------------------------------------+
void ClearM15BosPendingConfirm()
{
   ZeroMemory(g_m15BosPendingConfirm);
}

//+------------------------------------------------------------------+
bool M15BosCloseHoldsBeyondLevel(const int direction, const int m15BarShift, const double brokenLevel)
{
   if(direction != 1 && direction != -1)
      return false;

   const double closePrice = iClose(_Symbol, InputM15NarrativeTimeframe, m15BarShift);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps        = (pointSize > 0.0 ? pointSize : 0.00001);

   if(direction == 1)
      return (closePrice > brokenLevel + eps);
   return (closePrice < brokenLevel - eps);
}

//+------------------------------------------------------------------+
void ResetM15BosBiasState()
{
   ZeroMemory(g_m15LastBosRecord);
   g_m15LastBosRecordValid    = false;
   g_m15BosRecordedLegCount   = 0;
   ClearM15BosPendingConfirm();
}

//+------------------------------------------------------------------+
void RememberM15BosRecordedLeg(const int direction, const datetime legEndTime)
{
   if(direction == 0 || legEndTime == 0)
      return;

   if(g_m15BosRecordedLegCount >= M15_BOS_RECORDED_LEG_CAPACITY)
   {
      for(int shiftIndex = 1; shiftIndex < M15_BOS_RECORDED_LEG_CAPACITY; shiftIndex++)
         g_m15BosRecordedLegs[shiftIndex - 1] = g_m15BosRecordedLegs[shiftIndex];
      g_m15BosRecordedLegCount = M15_BOS_RECORDED_LEG_CAPACITY - 1;
   }

   const int index = g_m15BosRecordedLegCount;
   g_m15BosRecordedLegs[index].direction  = direction;
   g_m15BosRecordedLegs[index].legEndTime   = legEndTime;
   g_m15BosRecordedLegCount++;
}

//+------------------------------------------------------------------+
bool M15BosAlreadyRecordedForLeg(const int direction, const datetime legEndTime)
{
   if(legEndTime == 0)
      return false;

   for(int i = 0; i < g_m15BosRecordedLegCount; i++)
   {
      if(g_m15BosRecordedLegs[i].direction == direction &&
         g_m15BosRecordedLegs[i].legEndTime == legEndTime)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Confirm pending BOS after 1 closed M15 candle (reject fake breakout). |
//+------------------------------------------------------------------+
void TryConfirmM15BosPendingOnBarClose(const int m15BarShift)
{
   if(!g_m15BosPendingConfirm.active)
      return;

   const int      direction       = g_m15BosPendingConfirm.direction;
   const double   brokenLevel     = g_m15BosPendingConfirm.brokenLevel;
   const datetime legEndTime      = g_m15BosPendingConfirm.legEndTime;
   const datetime breakBarOpenTime = g_m15BosPendingConfirm.breakBarOpenTime;
   const datetime confirmBarOpenTime = iTime(_Symbol, InputM15NarrativeTimeframe, m15BarShift);

   ClearM15BosPendingConfirm();

   if(confirmBarOpenTime == 0)
      return;

   if(M15BosCloseHoldsBeyondLevel(direction, m15BarShift, brokenLevel))
   {
      RecordM15BosBreak(direction, confirmBarOpenTime, legEndTime, brokenLevel);
      if(InputLogHuntEvents)
      {
         LogHuntEvent("M15_BOS",
                      StringFormat("%s BOS confirmed confirmBar=%s breakBar=%s legEnd=%s lvl=%.5f",
                                   direction == 1 ? "bull" : "bear",
                                   TimeToString(confirmBarOpenTime, TIME_DATE | TIME_MINUTES),
                                   TimeToString(breakBarOpenTime, TIME_DATE | TIME_MINUTES),
                                   TimeToString(legEndTime, TIME_DATE | TIME_MINUTES),
                                   brokenLevel));
      }
      return;
   }

   if(InputLogHuntEvents)
   {
      LogHuntEvent("M15_BOS_REJECT",
                   StringFormat("%s fake breakout breakBar=%s confirmBar=%s close=%.5f lvl=%.5f",
                                direction == 1 ? "bull" : "bear",
                                TimeToString(breakBarOpenTime, TIME_DATE | TIME_MINUTES),
                                TimeToString(confirmBarOpenTime, TIME_DATE | TIME_MINUTES),
                                iClose(_Symbol, InputM15NarrativeTimeframe, m15BarShift),
                                brokenLevel));
   }
}

//+------------------------------------------------------------------+
//| M15 BOS: cross → pending; next M15 close must hold beyond level.   |
//+------------------------------------------------------------------+
void ProcessM15BosOnM15Close(const int m15BarShift)
{
   if(m15BarShift < 1 || g_m15BosSwing.swingHistoryCount < 1)
      return;

   TryConfirmM15BosPendingOnBarClose(m15BarShift);

   int      bosDirection = 0;
   double   brokenLevel  = 0.0;
   datetime barOpenTime  = 0;
   datetime legEndTime   = 0;
   if(!TryDetectM15BosCrossOnBar(m15BarShift, bosDirection, brokenLevel, barOpenTime, legEndTime))
      return;

   if(legEndTime == 0 || barOpenTime == 0)
      return;

   if(M15BosAlreadyRecordedForLeg(bosDirection, legEndTime))
      return;

   g_m15BosPendingConfirm.active           = true;
   g_m15BosPendingConfirm.direction        = bosDirection;
   g_m15BosPendingConfirm.brokenLevel      = brokenLevel;
   g_m15BosPendingConfirm.legEndTime       = legEndTime;
   g_m15BosPendingConfirm.breakBarOpenTime = barOpenTime;

   if(InputLogHuntEvents)
   {
      LogHuntEvent("M15_BOS_PENDING",
                   StringFormat("%s cross breakBar=%s legEnd=%s lvl=%.5f — await 1 M15 close",
                                bosDirection == 1 ? "bull" : "bear",
                                TimeToString(barOpenTime, TIME_DATE | TIME_MINUTES),
                                TimeToString(legEndTime, TIME_DATE | TIME_MINUTES),
                                brokenLevel));
   }
}

//+------------------------------------------------------------------+
void RecordM15BosBreak(const int direction, const datetime barOpenTime, const datetime legEndTime,
                       const double brokenLevel)
{
   if(direction == 0 || barOpenTime == 0 || legEndTime == 0)
      return;

   if(M15BosAlreadyRecordedForLeg(direction, legEndTime))
      return;

   RememberM15BosRecordedLeg(direction, legEndTime);

   g_m15LastBosRecord.direction   = direction;
   g_m15LastBosRecord.barOpenTime = barOpenTime;
   g_m15LastBosRecord.legEndTime  = legEndTime;
   g_m15LastBosRecord.brokenLevel = brokenLevel;
   g_m15LastBosRecordValid        = true;
}

//+------------------------------------------------------------------+
string M15TradeDirectionBiasText(const int bias)
{
   if(bias == 1)
      return "bull";
   if(bias == -1)
      return "bear";
   return "neutral";
}

//+------------------------------------------------------------------+
void LogM15TradeDirectionBiasIfChanged()
{
   if(!InputLogHuntEvents || !InputEnableM15BosTradeDirectionBias)
      return;

   const int bias = GetM15TradeDirectionBias();
   if(!g_m15EffectiveBiasLogReady)
   {
      g_m15LastLoggedEffectiveBias = bias;
      g_m15EffectiveBiasLogReady   = true;
      return;
   }

   if(bias == g_m15LastLoggedEffectiveBias)
      return;

   LogHuntEvent("M15_BIAS",
                StringFormat("%s → %s (lastBreak=%s bar=%s)",
                             M15TradeDirectionBiasText(g_m15LastLoggedEffectiveBias),
                             M15TradeDirectionBiasText(bias),
                             g_m15LastBosRecordValid
                                ? (g_m15LastBosRecord.direction == 1 ? "bull" : "bear")
                                : "none",
                             g_m15LastBosRecordValid
                                ? TimeToString(g_m15LastBosRecord.barOpenTime, TIME_DATE | TIME_MINUTES)
                                : "—"));
   g_m15LastLoggedEffectiveBias = bias;
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
//| Same M2 swing legs already drawn on chart (PFX_M2_TREND) — matches visible High/Low labels. |
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

   const int swingWarmupBars = 120;
   const int replayFromShift = (int)MathMin((double)(startReplayShift + swingWarmupBars),
                                            (double)(barsTotal - 2));

   SwingState replayState;
   ZeroMemory(replayState);

   for(int barShift = replayFromShift; barShift >= endReplayShift; barShift--)
   {
      const int histBefore = replayState.swingHistoryCount;
      ProcessSwingStepAtShift(replayState, InputM2NarrativeTimeframe, barShift,
                              InputM2SwingLineColor, "", "", false, true);
      if(barShift > startReplayShift)
         continue;
      if(replayState.swingHistoryCount <= histBefore)
         continue;

      const Swing closedLeg = replayState.swingHistory[replayState.swingHistoryCount - 1];
      if(closedLeg.swingDirection != legDirection)
         continue;

      const int legEndShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, closedLeg.legEndTime, true);
      if(legEndShift < 0 || legEndShift < windowNewestShift || legEndShift > windowOldestShift)
         continue;

      const double extremePrice = (legDirection == 1) ? closedLeg.legHighPrice : closedLeg.legLowPrice;
      AppendM2SwingExtremePoint(outPoints, outPointCount, extremePrice,
                                closedLeg.legStartTime, closedLeg.legEndTime);
   }

   CollectM2SwingExtremesFromDrawnTrendLines(formationShift, lookbackBars, legDirection,
                                             outPoints, outPointCount);

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
                                     double &outTakeProfitPrices[], int &outTakeProfitCount,
                                     const bool drawVisuals)
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

      if(!drawVisuals || !InputDrawTradeSwingProximityZones)
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

   if(drawVisuals && InputDrawTradeSwingProximityZones)
      ChartRedraw(0);

   return true;
}

//+------------------------------------------------------------------+
int GetM15TradeDirectionBias()
{
   if(!InputEnableM15BosTradeDirectionBias || !g_m15LastBosRecordValid)
      return 0;

   return g_m15LastBosRecord.direction;
}

//+------------------------------------------------------------------+
bool FvgTradeAllowedByM15BosBias(const bool isBullishFairValueGap, string &outBlockReason)
{
   outBlockReason = "";
   if(!InputEnableM15BosTradeDirectionBias)
      return true;

   const int bias = GetM15TradeDirectionBias();
   if(bias == 0)
      return true;

   const int tradeDir = isBullishFairValueGap ? 1 : -1;
   if(tradeDir != bias)
   {
      outBlockReason = StringFormat("M15 BOS overall bias %s blocks %s FVG",
                                    bias == 1 ? "bull" : "bear",
                                    isBullishFairValueGap ? "bull" : "bear");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void RefreshM15BosBiasHud()
{
   if(!InputShowM15BosBiasHud)
   {
      ObjectDelete(0, LQ_OBJ_M15_BIAS_HUD);
      return;
   }

   if(ObjectFind(0, LQ_OBJ_M15_BIAS_HUD) < 0)
   {
      if(!ObjectCreate(0, LQ_OBJ_M15_BIAS_HUD, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_YDISTANCE, 18);
      ObjectSetString(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_HIDDEN, true);
   }

   int          bias  = 0;
   if(g_m15LastBosRecordValid)
      bias = g_m15LastBosRecord.direction;
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

   ObjectSetString(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_TEXT, "M15 " + arrow);
   ObjectSetInteger(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_COLOR, col);
   ObjectSetInteger(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_FONTSIZE, 14);
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
bool TryLatestM15CompletedUpLegHigh(double &outHigh)
{
   for(int i = g_m15Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_m15Swing.swingHistory[i].swingDirection == 1)
      {
         outHigh = g_m15Swing.swingHistory[i].legHighPrice;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryLatestM15CompletedDownLegLow(double &outLow)
{
   for(int i = g_m15Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_m15Swing.swingHistory[i].swingDirection == -1)
      {
         outLow = g_m15Swing.swingHistory[i].legLowPrice;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TrySecondLastM15CompletedUpLegHigh(double &outHigh)
{
   int upLegsFound = 0;
   for(int i = g_m15Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_m15Swing.swingHistory[i].swingDirection != 1)
         continue;
      upLegsFound++;
      if(upLegsFound == 2)
      {
         outHigh = g_m15Swing.swingHistory[i].legHighPrice;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TrySecondLastM15CompletedDownLegLow(double &outLow)
{
   int downLegsFound = 0;
   for(int i = g_m15Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_m15Swing.swingHistory[i].swingDirection != -1)
         continue;
      downLegsFound++;
      if(downLegsFound == 2)
      {
         outLow = g_m15Swing.swingHistory[i].legLowPrice;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryNthM15CompletedSwingLeg(const int swingDirection, const int nFromLatest,
                              double &outLegHigh, double &outLegLow, datetime &outLegEndTime)
{
   outLegEndTime = 0;
   if(swingDirection == 0 || nFromLatest < 1)
      return false;

   int legsFound = 0;
   for(int i = g_m15Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_m15Swing.swingHistory[i].swingDirection != swingDirection)
         continue;
      legsFound++;
      if(legsFound == nFromLatest)
      {
         outLegHigh    = g_m15Swing.swingHistory[i].legHighPrice;
         outLegLow     = g_m15Swing.swingHistory[i].legLowPrice;
         outLegEndTime = g_m15Swing.swingHistory[i].legEndTime;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool IsM15LegLiquidityAlreadyBreached(const datetime legEndTime, const bool isUpLegHighBreach)
{
   if(legEndTime == 0)
      return false;

   for(int i = 0; i < g_m15LegLiquidityBreachCount; i++)
   {
      if(g_m15LegLiquidityBreaches[i].legEndTime == legEndTime &&
         g_m15LegLiquidityBreaches[i].isUpLegHighBreach == isUpLegHighBreach)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void RememberM15LegLiquidityBreach(const datetime legEndTime, const bool isUpLegHighBreach)
{
   if(legEndTime == 0)
      return;

   if(IsM15LegLiquidityAlreadyBreached(legEndTime, isUpLegHighBreach))
      return;

   if(g_m15LegLiquidityBreachCount < M15LegLiquidityBreachMemoryCapacity)
   {
      const int index = g_m15LegLiquidityBreachCount;
      g_m15LegLiquidityBreaches[index].legEndTime         = legEndTime;
      g_m15LegLiquidityBreaches[index].isUpLegHighBreach = isUpLegHighBreach;
      g_m15LegLiquidityBreachCount++;
      return;
   }

   for(int shiftIndex = 1; shiftIndex < M15LegLiquidityBreachMemoryCapacity; shiftIndex++)
      g_m15LegLiquidityBreaches[shiftIndex - 1] = g_m15LegLiquidityBreaches[shiftIndex];

   const int lastIndex = M15LegLiquidityBreachMemoryCapacity - 1;
   g_m15LegLiquidityBreaches[lastIndex].legEndTime         = legEndTime;
   g_m15LegLiquidityBreaches[lastIndex].isUpLegHighBreach = isUpLegHighBreach;
}

//+------------------------------------------------------------------+
bool TryPushM15ReplayLeg(M15ReplayLeg &replayLegs[], int &replayLegCount, const Swing &closedLeg)
{
   if(closedLeg.swingDirection == 0 || closedLeg.legEndTime == 0)
      return false;
   if(replayLegCount >= M15_REPLAY_LEG_CAPACITY)
      return false;

   replayLegs[replayLegCount].legHighPrice    = closedLeg.legHighPrice;
   replayLegs[replayLegCount].legLowPrice     = closedLeg.legLowPrice;
   replayLegs[replayLegCount].legEndTime      = closedLeg.legEndTime;
   replayLegs[replayLegCount].swingDirection = closedLeg.swingDirection;
   replayLegCount++;
   return true;
}

//+------------------------------------------------------------------+
//| Replay one closed M15 bar into swingState; append completed legs (no hunt side effects). |
//+------------------------------------------------------------------+
void ProcessM15SwingStepReplay(SwingState &swingState, const int lastClosedBarShift,
                               M15ReplayLeg &replayLegs[], int &replayLegCount,
                               const double anchorMultiplier, const bool useWickAndBodyForDecent)
{
   const ENUM_TIMEFRAMES timeframe = InputM15NarrativeTimeframe;
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
   if(isDecentMovement && candleDirection == swingState.currentSwingLeg.swingDirection)
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

   int nextSwingDirection = swingState.currentSwingLeg.swingDirection;
   if(swingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < swingState.priceAnchorLevel)
      nextSwingDirection = -1;
   else if(swingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > swingState.priceAnchorLevel)
      nextSwingDirection = 1;

   if(nextSwingDirection == swingState.currentSwingLeg.swingDirection)
   {
      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);
      return;
   }

   SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

   Swing closedSwingLeg = swingState.currentSwingLeg;
   closedSwingLeg.legEndTime = iTime(_Symbol, timeframe, sh);
   TryPushM15ReplayLeg(replayLegs, replayLegCount, closedSwingLeg);

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
//| Completed M15 swing legs in lookback: up-leg high / down-leg low pivots only.   |
//| Pivot up high: legHigh beats every newer up-leg high; pivot down low: vice versa. |
//+------------------------------------------------------------------+
void RebuildM15LiquidityPivotLevels()
{
   g_m15DescHighPivotCount = 0;
   g_m15AscLowPivotCount   = 0;

   if(InputM15LiquidityPivotLookbackBars < 2)
      return;

   const int barsTotal = iBars(_Symbol, InputM15NarrativeTimeframe);
   if(barsTotal < 3)
      return;

   const int maxShift =
      (int)MathMin((double)InputM15LiquidityPivotLookbackBars, (double)(barsTotal - 2));
   if(maxShift < 1)
      return;

   M15ReplayLeg replayLegs[M15_REPLAY_LEG_CAPACITY];
   int          replayLegCount = 0;
   SwingState   replaySwing;
   ZeroMemory(replaySwing);

   for(int shift = maxShift; shift >= 1; shift--)
      ProcessM15SwingStepReplay(replaySwing, shift, replayLegs, replayLegCount,
                                M15_BREACH_ANCHOR_MULTIPLIER, true);

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

      if(!isPivotHigh || g_m15DescHighPivotCount >= M15_LIQUIDITY_PIVOT_CAPACITY)
         continue;

      const int outIndex = g_m15DescHighPivotCount;
      g_m15DescHighPivots[outIndex].levelPrice     = replayLegs[legIndex].legHighPrice;
      g_m15DescHighPivots[outIndex].legEndTime      = replayLegs[legIndex].legEndTime;
      g_m15DescHighPivots[outIndex].legHighPrice    = replayLegs[legIndex].legHighPrice;
      g_m15DescHighPivots[outIndex].legLowPrice     = replayLegs[legIndex].legLowPrice;
      g_m15DescHighPivots[outIndex].swingDirection  = 1;
      g_m15DescHighPivotCount++;
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

      if(!isPivotLow || g_m15AscLowPivotCount >= M15_LIQUIDITY_PIVOT_CAPACITY)
         continue;

      const int outIndex = g_m15AscLowPivotCount;
      g_m15AscLowPivots[outIndex].levelPrice     = replayLegs[legIndex].legLowPrice;
      g_m15AscLowPivots[outIndex].legEndTime      = replayLegs[legIndex].legEndTime;
      g_m15AscLowPivots[outIndex].legHighPrice    = replayLegs[legIndex].legHighPrice;
      g_m15AscLowPivots[outIndex].legLowPrice     = replayLegs[legIndex].legLowPrice;
      g_m15AscLowPivots[outIndex].swingDirection  = -1;
      g_m15AscLowPivotCount++;
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
//| Anticipation: arm hunt before exact sweep — high − N% range, low + N% range. |
//+------------------------------------------------------------------+
double M15BreachWickLevelForUpLegHigh(const double legHighPrice)
{
   if(InputM15BreachAnticipationPercentBelowUpHigh <= 0.0)
      return legHighPrice;

   const double referenceHeight = ReferenceChartHeightForFairValueGapFilterM2();
   if(referenceHeight <= 0.0)
      return legHighPrice;

   return legHighPrice -
          referenceHeight * (InputM15BreachAnticipationPercentBelowUpHigh / 100.0);
}

//+------------------------------------------------------------------+
double M15BreachWickLevelForDownLegLow(const double legLowPrice)
{
   if(InputM15BreachAnticipationPercentAboveDownLow <= 0.0)
      return legLowPrice;

   const double referenceHeight = ReferenceChartHeightForFairValueGapFilterM2();
   if(referenceHeight <= 0.0)
      return legLowPrice;

   return legLowPrice +
          referenceHeight * (InputM15BreachAnticipationPercentAboveDownLow / 100.0);
}

//+------------------------------------------------------------------+
//| Breach leg must lie in M2 chart window (InputChartRangeBarCount bars). |
//+------------------------------------------------------------------+
bool M15BreachLegIsWithinM2ChartRange(const datetime legEndTime, const bool m15HighBreached,
                                     const double legHigh, const double legLow)
{
   if(legEndTime == 0)
      return false;

   const int maxShift = InputChartRangeBarCount * 120;
   if(maxShift <= 0)
      return true;

   const int legShiftM2 = iBarShift(_Symbol, InputM2NarrativeTimeframe, legEndTime, true);
   if(legShiftM2 < 0 || legShiftM2 > maxShift)
      return false;

   const double refPrice = m15HighBreached ? legHigh : legLow;
   if(refPrice <= 0.0)
      return false;

   const int totalM2 = iBars(_Symbol, InputM2NarrativeTimeframe);
   if(totalM2 < 2)
      return false;

   const int useBarCount = (int)MathMin((double)maxShift, (double)(totalM2 - 1));
   if(useBarCount < 1)
      return false;

   double chartHigh = -1.0e100;
   double chartLow  = 1.0e100;
   for(int barShift = 1; barShift <= useBarCount; barShift++)
   {
      chartHigh = MathMax(chartHigh, iHigh(_Symbol, InputM2NarrativeTimeframe, barShift));
      chartLow  = MathMin(chartLow, iLow(_Symbol, InputM2NarrativeTimeframe, barShift));
   }

   if(chartHigh <= chartLow)
      return false;

   return (refPrice >= chartLow && refPrice <= chartHigh);
}

//+------------------------------------------------------------------+
bool TryAcceptM15BreachForHunt(const bool m15HighBreached, const double legHigh, const double legLow,
                               const datetime legEnd, double &outLevel, bool &outHighBreached,
                               datetime &outLegEndTime)
{
   if(!M15BreachLegIsWithinM2ChartRange(legEnd, m15HighBreached, legHigh, legLow))
   {
      const int legShiftM2 = iBarShift(_Symbol, InputM2NarrativeTimeframe, legEnd, true);
      LogHuntEvent("HUNT_SKIP",
                   StringFormat("M15 %s breach leg %s ref=%.5f outside M2 chart (sh=%d max=%d)",
                                m15HighBreached ? "high" : "low",
                                TimeToString(legEnd, TIME_DATE | TIME_MINUTES),
                                m15HighBreached ? legHigh : legLow, legShiftM2,
                                InputChartRangeBarCount));
      return false;
   }

   outLevel        = m15HighBreached ? legHigh : legLow;
   outLegEndTime   = legEnd;
   outHighBreached = m15HighBreached;
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
   if(!InputLogHuntEvents)
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
//| Touch: leg low + 2% M2 chart range (high breach); leg high − 2% (low breach). |
//+------------------------------------------------------------------+
double V2TouchLevelFromLegExtreme(const bool m15HighWasBreached, const double legLowPrice,
                                   const double legHighPrice)
{
   const double bufferPrice = M2FvgStopBufferPrice();
   if(m15HighWasBreached)
   {
      if(legLowPrice <= 0.0)
         return 0.0;
      if(bufferPrice <= 0.0)
         return NormalizeDouble(legLowPrice, _Digits);
      return NormalizeDouble(legLowPrice + bufferPrice, _Digits);
   }

   if(legHighPrice <= 0.0)
      return 0.0;
   if(bufferPrice <= 0.0)
      return NormalizeDouble(legHighPrice, _Digits);
   return NormalizeDouble(legHighPrice - bufferPrice, _Digits);
}

//+------------------------------------------------------------------+
bool V2TryGetLastCompletedM2Leg(const int legDirection, double &outLegLow, double &outLegHigh)
{
   outLegLow  = 0.0;
   outLegHigh = 0.0;
   if(legDirection == 0 || g_m2Swing.swingHistoryCount < 1)
      return false;

   for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m2Swing.swingHistory[historyIndex].swingDirection != legDirection)
         continue;
      outLegLow  = g_m2Swing.swingHistory[historyIndex].legLowPrice;
      outLegHigh = g_m2Swing.swingHistory[historyIndex].legHighPrice;
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
      V2TouchLevelFromLegExtreme(g_v2Hunts[huntIndex].m15HighWasBreached, legLow, legHigh);
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
         const bool bullishHunt = !g_v2Hunts[huntIndex].m15HighWasBreached;
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
   g_v2Hunts[huntIndex].touchLevel      = newLevel;
   g_v2Hunts[huntIndex].touchLevelReady = true;
   if(!hadTouch)
   {
      g_v2Hunts[huntIndex].touchPointTouched         = false;
      g_v2Hunts[huntIndex].touchHitM2BarOpenTime    = 0;
      g_v2Hunts[huntIndex].touchGraceBarsRemaining = 0;
   }
   V2DrawTouchPointLine(huntIndex);

   const string eventName = (hadTouch ? "V2_TOUCH_RECALC" : "V2_STORE_TOUCH");
   V2LogHuntEvent(huntIndex, eventName,
                  StringFormat("lvl=%.5f%s legL=%.5f legH=%.5f buf2%%rng=%.5f (%s)",
                               newLevel,
                               hadTouch ? StringFormat(" was=%.5f", oldLevel) : "",
                               legLow, legHigh, M2FvgStopBufferPrice(), logContext));
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
// Latest completed M15 same-dir leg (g_m15Swing 0.5). TP = 0.9x / 1.4x / 1.9x from entry.
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
bool V4ResolveM15SameDirLegRangeForTp(const bool isBullishFairValueGap, double &outLegRange,
                                      datetime &outLegEndTime)
{
   outLegRange   = 0.0;
   outLegEndTime = 0;

   const int tradeLegDir = V4TradeLegDirectionForFvg(isBullishFairValueGap);

   double legHigh = 0.0;
   double legLow  = 0.0;
   if(!TryNthM15CompletedSwingLeg(tradeLegDir, 1, legHigh, legLow, outLegEndTime))
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
bool TryPlaceOppositeFvgTradeSetup(const bool isBullishFairValueGap, const double zoneLowPrice,
                                    const double zoneHighPrice, const datetime formationTime,
                                    const datetime huntSessionId, const double m15LegRange,
                                    const bool fromGrace)
{
   const int huntIndex = V2FindHuntSlotBySessionId(huntSessionId);
   if(formationTime == 0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "formationTime=0");
      return false;
   }

   if(!fromGrace && V2IsHuntSessionStillActive(huntSessionId))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt still ON — orders after touch");
      return false;
   }

   string bosBiasBlockReason = "";
   if(!fromGrace && !FvgTradeAllowedByM15BosBias(isBullishFairValueGap, bosBiasBlockReason))
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

   if(!fromGrace && !FvgFormationBarMeetsMinTickVolume(barShift))
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
                                       stopLossOverall, takeProfitPrices, takeProfitCount, true))
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
   g_v2Hunts[huntIndex].m15HighWasBreached             = false;
   g_v2Hunts[huntIndex].m15BreachedLegLevelPrice       = 0.0;
   g_v2Hunts[huntIndex].m15BreachedLegEndTime         = 0;
   g_v2Hunts[huntIndex].closeWhenM15LiquidityBreached  = 0.0;
   g_v2Hunts[huntIndex].pathMinLowSinceM15Breach            = 0.0;
   g_v2Hunts[huntIndex].pathMaxHighSinceM15Breach           = 0.0;
   g_v2Hunts[huntIndex].sameDirExtremeAtLastTouchRecalc     = 0.0;
   g_v2Hunts[huntIndex].touchRecalcBufferAnchor             = 0.0;
   g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg = false;
   g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross   = false;
   g_v2Hunts[huntIndex].impulseCloseExtremeSinceM15Breach = 0.0;
   g_v2Hunts[huntIndex].sessionId                      = 0;
   g_v2Hunts[huntIndex].oppositeFvgFoundCount          = 0;
   g_v2Hunts[huntIndex].touchLevel                     = 0.0;
   g_v2Hunts[huntIndex].touchLevelReady                = false;
   g_v2Hunts[huntIndex].touchPointTouched         = false;
   g_v2Hunts[huntIndex].touchHitM2BarOpenTime    = 0;
   g_v2Hunts[huntIndex].touchGraceBarsRemaining  = 0;
   g_v2Hunts[huntIndex].postTouchFvgGateOpen         = true;
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
int V2FindActiveHuntByM15Leg(const datetime legEndTime, const bool m15HighBreached)
{
   if(legEndTime == 0)
      return -1;
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
   {
      if(!g_v2Hunts[i].active)
         continue;
      if(g_v2Hunts[i].m15BreachedLegEndTime == legEndTime &&
         g_v2Hunts[i].m15HighWasBreached == m15HighBreached)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
int V2FindActiveHuntByBreachPolarity(const bool m15HighBreached)
{
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
   {
      if(g_v2Hunts[i].active && g_v2Hunts[i].m15HighWasBreached == m15HighBreached)
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
   if(!InputLogHuntEvents)
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
   return g_v2Hunts[huntIndex].m15HighWasBreached ? -1 : 1;
}

//+------------------------------------------------------------------+
bool V2TryGetOppositeM2LegExtentsForTouch(const int huntIndex, double &outLegLow, double &outLegHigh)
{
   outLegLow  = 0.0;
   outLegHigh = 0.0;

   const int oppositeDir = V2OppositeM2LegDirectionForHunt(huntIndex);
   const bool haveCompleted = V2TryGetLastCompletedM2Leg(oppositeDir, outLegLow, outLegHigh);

   if(g_m2Swing.currentSwingLeg.swingDirection == oppositeDir)
   {
      if(!haveCompleted)
      {
         outLegLow  = g_m2Swing.currentSwingLeg.legLowPrice;
         outLegHigh = g_m2Swing.currentSwingLeg.legHighPrice;
         return (outLegLow > 0.0 && outLegHigh > 0.0);
      }
      outLegLow  = MathMin(outLegLow, g_m2Swing.currentSwingLeg.legLowPrice);
      outLegHigh = MathMax(outLegHigh, g_m2Swing.currentSwingLeg.legHighPrice);
      return true;
   }

   return haveCompleted;
}

//+------------------------------------------------------------------+
//| Same-dir extreme tracked while hunt is ON (path max high / min low). |
//+------------------------------------------------------------------+
bool V2GetSameDirExtremeWhileHuntOn(const int huntIndex, double &outExtreme)
{
   outExtreme = 0.0;
   if(!g_v2Hunts[huntIndex].active)
      return false;

   if(g_v2Hunts[huntIndex].m15HighWasBreached)
   {
      outExtreme = g_v2Hunts[huntIndex].pathMaxHighSinceM15Breach;
      return (outExtreme > 0.0);
   }

   outExtreme = g_v2Hunts[huntIndex].pathMinLowSinceM15Breach;
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
//| Bear FVG hunt: buffer tracks active up-leg high until leg completes; resumes on enter/cross above buffer. |
//| Bull FVG hunt: buffer tracks active down-leg low until leg completes; resumes on enter/cross below buffer.  |
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

   const int sameDir = V2SameSideM2LegDirectionForHunt(huntIndex);
   if(g_m2Swing.currentSwingLeg.swingDirection != sameDir)
      return;

   g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg = true;
   g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross = false;
   V2SyncTouchRecalcBufferAnchorFromActiveLeg(huntIndex);

   if(g_v2Hunts[huntIndex].touchRecalcBufferAnchor > 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRECALC_BUF_TRACK",
                     StringFormat("track active %s leg anchor=%.5f",
                                  sameDir == 1 ? "up" : "down",
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

   const int sameDir = V2SameSideM2LegDirectionForHunt(huntIndex);
   if(g_m2Swing.currentSwingLeg.swingDirection != sameDir)
      return;

   const double liveExtreme = g_v2Hunts[huntIndex].m15HighWasBreached
                              ? g_m2Swing.currentSwingLeg.legHighPrice
                              : g_m2Swing.currentSwingLeg.legLowPrice;
   if(liveExtreme <= 0.0)
      return;

   g_v2Hunts[huntIndex].touchRecalcBufferAnchor = liveExtreme;
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
   double anchor = 0.0;
   if(!V2TryGetTouchRecalcBufferAnchorExtreme(huntIndex, anchor))
      return false;

   const double band = V2TouchRecalcBufferBandHalfWidth();
   if(band <= 0.0)
      return false;

   if(g_v2Hunts[huntIndex].m15HighWasBreached)
   {
      const double zoneLow = anchor - band;
      const bool touchesZone = (barHigh >= zoneLow && barLow <= anchor);
      const bool crossesAbove = (barHigh > anchor) || (barClose > anchor);
      return touchesZone || crossesAbove;
   }

   const double zoneHigh = anchor + band;
   const bool touchesZone = (barLow <= zoneHigh && barHigh >= anchor);
   const bool crossesBelow = (barLow < anchor) || (barClose < anchor);
   return touchesZone || crossesBelow;
}

//+------------------------------------------------------------------+
void V2TryArmTouchRecalcBufferResumeOnCross(const int huntIndex, const double barHigh,
                                              const double barLow, const double barClose)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;
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
}

//+------------------------------------------------------------------+
void V2OnTouchRecalcBufferLegChange(const int huntIndex, const int closingLegDirection,
                                     const int nextLegDirection)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   const int sameDir = V2SameSideM2LegDirectionForHunt(huntIndex);

   if(g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross &&
      nextLegDirection == sameDir)
      V2BeginTouchRecalcBufferActiveLegTrack(huntIndex);

   if(!g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg)
      return;

   if(closingLegDirection == sameDir && g_m2Swing.swingHistoryCount > 0)
   {
      const Swing closedLeg = g_m2Swing.swingHistory[g_m2Swing.swingHistoryCount - 1];
      if(closedLeg.swingDirection == sameDir)
      {
         const double finalAnchor = g_v2Hunts[huntIndex].m15HighWasBreached
                                    ? closedLeg.legHighPrice
                                    : closedLeg.legLowPrice;
         if(finalAnchor > 0.0)
            g_v2Hunts[huntIndex].touchRecalcBufferAnchor = finalAnchor;
      }
      V2StopTouchRecalcBufferActiveLegTrack(huntIndex);
      g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross = false;
      V2LogHuntEvent(huntIndex, "TRECALC_BUF_FREEZE",
                     StringFormat("%s leg closed anchor=%.5f",
                                  sameDir == 1 ? "up" : "down",
                                  g_v2Hunts[huntIndex].touchRecalcBufferAnchor));
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
bool V2DetectTouchRecalcBufferHit(const int huntIndex, const double barHigh, const double barLow,
                                   const double barClose, bool &outNearHuntExtreme,
                                   bool &outNearSameDirLegExtreme)
{
   outNearHuntExtreme      = false;
   outNearSameDirLegExtreme = false;
   if(!g_v2Hunts[huntIndex].active)
      return false;

   double huntExtreme = 0.0;
   if(!V2GetSameDirExtremeWhileHuntOn(huntIndex, huntExtreme))
      return false;

   const double pointSize   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps         = (pointSize > 0.0 ? pointSize : 0.00001);
   const double pct         = InputHuntTouchRecalcPercentBeforeSameDirExtreme;
   const double chartHeight = ReferenceChartHeightForFairValueGapFilterM2();
   const double band =
      (pct > 0.0 && chartHeight > 0.0) ? chartHeight * (pct / 100.0) : 0.0;
   if(band <= 0.0)
      return false;

   if(g_v2Hunts[huntIndex].m15HighWasBreached)
      outNearHuntExtreme =
         (barHigh >= huntExtreme - band && barHigh <= huntExtreme + eps) ||
         (barClose >= huntExtreme - band && barClose <= huntExtreme + eps);
   else
      outNearHuntExtreme =
         (barLow <= huntExtreme + band && barLow >= huntExtreme - eps) ||
         (barClose <= huntExtreme + band && barClose >= huntExtreme - eps);

   double bufferAnchor = 0.0;
   if(V2TryGetTouchRecalcBufferAnchorExtreme(huntIndex, bufferAnchor))
   {
      if(g_v2Hunts[huntIndex].m15HighWasBreached)
         outNearSameDirLegExtreme =
            (barHigh >= bufferAnchor - band && barHigh <= bufferAnchor + eps) ||
            (barClose >= bufferAnchor - band && barClose <= bufferAnchor + eps);
      else
         outNearSameDirLegExtreme =
            (barLow <= bufferAnchor + band && barLow >= bufferAnchor - eps) ||
            (barClose <= bufferAnchor + band && barClose >= bufferAnchor - eps);
   }

   return (outNearHuntExtreme || outNearSameDirLegExtreme);
}

//+------------------------------------------------------------------+
//| Touch recalc only from hunt path extreme (max high / min low since hunt ON). |
//| Does not use global M2 swing-leg BOS (avoids lower highs triggering recalc).   |
//+------------------------------------------------------------------+
void V2TryRecalcTouchOnHuntSameDirProgress(const int huntIndex, const double barHigh,
                                           const double barLow, const double barClose,
                                           const bool huntExtremeMovedThisBar,
                                           const bool forceBufferRecalc = false)
{
   if(!g_v2Hunts[huntIndex].active)
      return;

   double huntExtreme = 0.0;
   if(!V2GetSameDirExtremeWhileHuntOn(huntIndex, huntExtreme))
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   const double lastSnap  = g_v2Hunts[huntIndex].sameDirExtremeAtLastTouchRecalc;
   const double pct       = InputHuntTouchRecalcPercentBeforeSameDirExtreme;

   bool nearHuntExtreme = false;
   bool nearSameDirLegExtreme = false;
   if(!V2DetectTouchRecalcBufferHit(huntIndex, barHigh, barLow, barClose,
                                     nearHuntExtreme, nearSameDirLegExtreme))
   {
      if(!huntExtremeMovedThisBar)
         return;
   }

   if(!huntExtremeMovedThisBar && !nearHuntExtreme && !nearSameDirLegExtreme)
      return;

   if(!forceBufferRecalc && !huntExtremeMovedThisBar && !nearSameDirLegExtreme &&
      lastSnap > 0.0 && MathAbs(huntExtreme - lastSnap) <= eps)
      return;

   double sameDirLegLow  = 0.0;
   double sameDirLegHigh = 0.0;
   const int sameDir = V2SameSideM2LegDirectionForHunt(huntIndex);
   V2TryGetLastCompletedM2Leg(sameDir, sameDirLegLow, sameDirLegHigh);

   string triggerTag = "";
   if(huntExtremeMovedThisBar && (nearHuntExtreme || nearSameDirLegExtreme))
      triggerTag = "new hunt extreme + within buffer";
   else if(huntExtremeMovedThisBar)
      triggerTag = g_v2Hunts[huntIndex].m15HighWasBreached ? "new hunt high" : "new hunt low";
   else if(nearSameDirLegExtreme)
      triggerTag = g_v2Hunts[huntIndex].m15HighWasBreached
                   ? StringFormat("within %.1f%% M2 chart of same-dir up leg high %.5f", pct, sameDirLegHigh)
                   : StringFormat("within %.1f%% M2 chart of same-dir down leg low %.5f", pct, sameDirLegLow);
   else
      triggerTag = StringFormat("within %.1f%% M2 chart of hunt extreme", pct);

   const double oldTouch = g_v2Hunts[huntIndex].touchLevel;
   const bool   hadTouch = g_v2Hunts[huntIndex].touchLevelReady;
   double legLow  = 0.0;
   double legHigh = 0.0;
   if(!V2TryGetOppositeM2LegExtentsForTouch(huntIndex, legLow, legHigh))
      return;

   V2ApplyTouchLevelFromM2Leg(huntIndex, legLow, legHigh,
                              StringFormat("%s huntExtreme=%.5f", triggerTag, huntExtreme),
                              true);

   if(!g_v2Hunts[huntIndex].touchLevelReady)
      return;

   const double touchEps = (pointSize > 0.0 ? pointSize * 2.0 : 0.00002);
   if(!hadTouch || MathAbs(g_v2Hunts[huntIndex].touchLevel - oldTouch) > touchEps)
      g_v2Hunts[huntIndex].sameDirExtremeAtLastTouchRecalc = huntExtreme;
}

//+------------------------------------------------------------------+
int V2OppositeM15LegDirectionForHunt(const int huntIndex)
{
   return V2OppositeM2LegDirectionForHunt(huntIndex);
}

//+------------------------------------------------------------------+
void V2OnM15LegClosedForHunts(const int closedLegDirection, const datetime closedLegEndTime)
{
   if(!InputEndHuntOnOppositeM15LegBeforeTouch || closedLegDirection == 0 || closedLegEndTime == 0)
      return;

   for(int huntIndex = 0; huntIndex < V2_MAX_HUNT_SESSIONS; huntIndex++)
   {
      if(!g_v2Hunts[huntIndex].active || !g_v2Hunts[huntIndex].touchLevelReady)
         continue;
      if(g_v2Hunts[huntIndex].touchPointTouched)
         continue;
      if(closedLegDirection != V2OppositeM15LegDirectionForHunt(huntIndex))
         continue;
      if(g_v2Hunts[huntIndex].sessionId != 0 && closedLegEndTime <= g_v2Hunts[huntIndex].sessionId)
         continue;

      V2LogHuntEvent(huntIndex, "HUNT_OFF",
                     StringFormat("opposite M15 leg closed %s, touch lvl=%.5f never hit",
                                  TimeToString(closedLegEndTime, TIME_DATE | TIME_MINUTES),
                                  g_v2Hunts[huntIndex].touchLevel));
      V2EndOppositeFvgHuntSession(huntIndex, false);
   }
}

//+------------------------------------------------------------------+
int V2SameSideM2LegDirectionForHunt(const int huntIndex)
{
   return g_v2Hunts[huntIndex].m15HighWasBreached ? 1 : -1;
}

//+------------------------------------------------------------------+
void V2ResetHuntSlotSessionCounters(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   g_v2Hunts[huntIndex].oppositeFvgFoundCount = 0;
   g_v2Hunts[huntIndex].touchLevel            = 0.0;
   g_v2Hunts[huntIndex].touchLevelReady       = false;
   g_v2Hunts[huntIndex].touchPointTouched         = false;
   g_v2Hunts[huntIndex].touchHitM2BarOpenTime    = 0;
   g_v2Hunts[huntIndex].touchGraceBarsRemaining  = 0;
   g_v2Hunts[huntIndex].postTouchFvgGateOpen    = true;
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
   if(!InputDrawBosOppositeFairValueGapZones)
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
   if(!V2TryGetOppositeM2LegExtentsForTouch(huntIndex, legLow, legHigh))
      return;

   V2TryLockTouchLevelFromM2Leg(huntIndex, legLow, legHigh, "last completed opposite M2 leg");
}

//+------------------------------------------------------------------+
void V2OnM2LegChangeForHunt(const int huntIndex, const int closingLegDirection,
                            const int nextLegDirection)
{
   if(!g_v2Hunts[huntIndex].active || g_v2Hunts[huntIndex].touchLevelReady)
      return;

   const int oppositeDir = V2OppositeM2LegDirectionForHunt(huntIndex);
   if(closingLegDirection != oppositeDir)
      return;

   V2TryLockTouchLevelFromM2Leg(huntIndex,
                                g_m2Swing.currentSwingLeg.legLowPrice,
                                g_m2Swing.currentSwingLeg.legHighPrice,
                                "opposite M2 leg just closed");
}

//+------------------------------------------------------------------+
void V2DrawTouchPointLine(const int huntIndex)
{
   if(!g_v2Hunts[huntIndex].touchLevelReady || g_v2Hunts[huntIndex].touchLevel <= 0.0)
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
bool V2TryDetectSameDirBosForHunt(const int huntIndex, string &outBosDetail)
{
   outBosDetail = "";
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return false;

   double brokenLevel = 0.0;
   const bool bullBos = TryDetectM2PriceBreakAboveLatestUpLegHigh(brokenLevel);
   double bearBrokenLevel = 0.0;
   const bool bearBos = TryDetectM2PriceBreakBelowLatestDownLegLow(bearBrokenLevel);

   if(g_v2Hunts[huntIndex].m15HighWasBreached && bullBos)
   {
      outBosDetail = StringFormat("bull BOS lvl=%.5f (M15 high breach)", brokenLevel);
      return true;
   }
   if(!g_v2Hunts[huntIndex].m15HighWasBreached && bearBos)
   {
      outBosDetail = StringFormat("bear BOS lvl=%.5f (M15 low breach)", bearBrokenLevel);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Hunt ON only. M15 high breach → bull M2 BOS clears this hunt's FVGs; low → bear BOS. |
//| Does not cancel broker orders or touch other hunt sessions.                          |
//+------------------------------------------------------------------+
void V2TryClearHuntFvgsOnSameDirectionBosWhileHuntOn(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;
   if(!g_v2Hunts[huntIndex].postTouchFvgGateOpen)
      return;

   string bosDetail = "";
   if(!V2TryDetectSameDirBosForHunt(huntIndex, bosDetail))
      return;

   if(g_v2Hunts[huntIndex].fvgMemCount <= 0 && !g_v2Hunts[huntIndex].pendingTradeFvgValid)
      return;

   V2RemoveHuntSessionFvgPlots(huntIndex);
   V2LogHuntEvent(huntIndex, "FVG_CLEAR_SAME_DIR_BOS", bosDetail);
}

//+------------------------------------------------------------------+
void V2TryReopenPostTouchFvgGateOnSameDirBos(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;
   if(g_v2Hunts[huntIndex].postTouchFvgGateOpen)
      return;

   string bosDetail = "";
   if(!V2TryDetectSameDirBosForHunt(huntIndex, bosDetail))
      return;

   g_v2Hunts[huntIndex].postTouchFvgGateOpen  = true;
   g_v2Hunts[huntIndex].touchPointTouched         = false;
   g_v2Hunts[huntIndex].touchHitM2BarOpenTime    = 0;
   g_v2Hunts[huntIndex].touchGraceBarsRemaining  = 0;

   double legLow  = 0.0;
   double legHigh = 0.0;
   if(V2TryGetOppositeM2LegExtentsForTouch(huntIndex, legLow, legHigh))
      V2ApplyTouchLevelFromM2Leg(huntIndex, legLow, legHigh,
                                 StringFormat("same-dir BOS (%s)", bosDetail), true);
   else
      V2UpdateTouchLevelFromM2Swing(huntIndex);

   V2LogHuntEvent(huntIndex, "TOUCH_GATE_ON", bosDetail);
}

//+------------------------------------------------------------------+
void V2TryReopenPostTouchFvgGateOnBufferHit(const int huntIndex, const double barHigh,
                                             const double barLow, const double barClose,
                                             const bool huntExtremeMovedThisBar)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;
   if(g_v2Hunts[huntIndex].postTouchFvgGateOpen)
      return;

   bool nearHuntExtreme = false;
   bool nearSameDirLegExtreme = false;
   if(!V2DetectTouchRecalcBufferHit(huntIndex, barHigh, barLow, barClose,
                                     nearHuntExtreme, nearSameDirLegExtreme))
      return;

   g_v2Hunts[huntIndex].postTouchFvgGateOpen  = true;
   g_v2Hunts[huntIndex].touchPointTouched         = false;
   g_v2Hunts[huntIndex].touchHitM2BarOpenTime    = 0;
   g_v2Hunts[huntIndex].touchGraceBarsRemaining  = 0;

   const string reopenDetail = nearSameDirLegExtreme
      ? StringFormat("%.1f%% recalc buffer hit (same-dir leg)",
                     InputHuntTouchRecalcPercentBeforeSameDirExtreme)
      : StringFormat("%.1f%% recalc buffer hit (hunt extreme)",
                     InputHuntTouchRecalcPercentBeforeSameDirExtreme);
   V2LogHuntEvent(huntIndex, "TOUCH_GATE_ON", reopenDetail);

   V2TryRecalcTouchOnHuntSameDirProgress(huntIndex, barHigh, barLow, barClose,
                                         huntExtremeMovedThisBar, true);
}

//+------------------------------------------------------------------+
//| TOUCH_HIT: bull close above touch; bear close below touch.                      |
//+------------------------------------------------------------------+
bool V2TryDetectTouchOfStoredLevel(const int huntIndex, const double barClose, const double pointSize)
{
   if(!g_v2Hunts[huntIndex].touchLevelReady || g_v2Hunts[huntIndex].touchLevel <= 0.0)
      return false;

   const double touchLevel = g_v2Hunts[huntIndex].touchLevel;
   const double eps        = (pointSize > 0.0 ? pointSize : 0.00001);

   if(g_v2Hunts[huntIndex].m15HighWasBreached)
      return (barClose < touchLevel - eps);
   return (barClose > touchLevel + eps);
}

//+------------------------------------------------------------------+
void V2HandleTouchHitConfirmed(const int huntIndex, const double barClose)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   const datetime touchBarOpenTime = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   const bool     preTouchFvgExists =
      V2HuntHasPreTouchFvgBeforeBar(huntIndex, touchBarOpenTime);

   g_v2Hunts[huntIndex].touchPointTouched      = true;
   g_v2Hunts[huntIndex].touchHitM2BarOpenTime  = touchBarOpenTime;
   g_v2Hunts[huntIndex].touchGraceBarsRemaining =
      preTouchFvgExists ? 0 : LQ_TOUCH_GRACE_M2_BARS;

   if(preTouchFvgExists)
   {
      V2TryPlacePreTouchFvgAndEndHuntOnTouchHit(huntIndex, barClose);
      return;
   }

   V2LogHuntEvent(huntIndex, "TOUCH_HIT",
                  StringFormat("lvl=%.5f close=%.5f — grace %d M2 bars for FVG",
                               g_v2Hunts[huntIndex].touchLevel, barClose,
                               LQ_TOUCH_GRACE_M2_BARS));
}

//+------------------------------------------------------------------+
void V2TryPlacePreTouchFvgAndEndHuntOnTouchHit(const int huntIndex, const double barClose)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   V2LogHuntEvent(huntIndex, "TOUCH_HIT",
                  StringFormat("lvl=%.5f close=%.5f — pre-touch FVG (fvgs=%d) → hunt OFF + place",
                               g_v2Hunts[huntIndex].touchLevel, barClose,
                               g_v2Hunts[huntIndex].oppositeFvgFoundCount));

   bool     tradeIsBullishFvg  = false;
   double   tradeZoneLow       = 0.0;
   double   tradeZoneHigh      = 0.0;
   datetime tradeFormationTime = 0;
   if(!V2ResolveTradeFvgForHunt(huntIndex, tradeIsBullishFvg, tradeZoneLow, tradeZoneHigh,
                                tradeFormationTime))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "pre-touch TOUCH_HIT — no FVG for trade");
      V2EndOppositeFvgHuntSession(huntIndex, false);
      return;
   }

   const bool polarityMatchesHunt =
      (g_v2Hunts[huntIndex].m15HighWasBreached && !tradeIsBullishFvg) ||
      (!g_v2Hunts[huntIndex].m15HighWasBreached && tradeIsBullishFvg);
   if(!polarityMatchesHunt)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "pre-touch TOUCH_HIT — FVG polarity mismatch");
      V2EndOppositeFvgHuntSession(huntIndex, false);
      return;
   }

   V2LogHuntEvent(huntIndex, "FVG_ON_PRE_TOUCH",
                  StringFormat("%s zone=%.5f-%.5f formation=%s touch=%.5f",
                               tradeIsBullishFvg ? "bull" : "bear",
                               tradeZoneLow, tradeZoneHigh,
                               TimeToString(tradeFormationTime, TIME_DATE | TIME_MINUTES),
                               g_v2Hunts[huntIndex].touchLevel));

   double   m15LegRange = 0.0;
   datetime m15LegEnd   = 0;
   if(!V4ResolveM15SameDirLegRangeForTp(tradeIsBullishFvg, m15LegRange, m15LegEnd))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("pre-touch TOUCH_HIT — no completed M15 %s leg for TP",
                                  tradeIsBullishFvg ? "up" : "down"));
      V2EndOppositeFvgHuntSession(huntIndex, false);
      return;
   }

   V2LogHuntEvent(huntIndex, "TRADE_M15_LEG_TP",
                  StringFormat("%s leg H-L=%.5f end=%s",
                               tradeIsBullishFvg ? "up" : "down", m15LegRange,
                               TimeToString(m15LegEnd, TIME_DATE | TIME_MINUTES)));

   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   V2EndOppositeFvgHuntSession(huntIndex, false);
   TryPlaceOppositeFvgTradeSetup(tradeIsBullishFvg, tradeZoneLow, tradeZoneHigh,
                                tradeFormationTime, sessionId, m15LegRange, false);
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
bool V2IsFvgFormedDuringTouchGrace(const int huntIndex, const datetime formationTime)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || formationTime == 0)
      return false;
   if(!g_v2Hunts[huntIndex].touchPointTouched || g_v2Hunts[huntIndex].touchHitM2BarOpenTime == 0)
      return false;
   return (formationTime > g_v2Hunts[huntIndex].touchHitM2BarOpenTime);
}

//+------------------------------------------------------------------+
bool V2HuntHasPreTouchFvgBeforeBar(const int huntIndex, const datetime touchBarOpenTime)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || touchBarOpenTime == 0)
      return false;

   for(int i = 0; i < g_v2Hunts[huntIndex].fvgMemCount; i++)
   {
      const datetime formationTime = g_v2Hunts[huntIndex].fvgMem[i].fairValueGapBarOpenTime;
      if(formationTime != 0 && formationTime <= touchBarOpenTime)
         return true;
   }

   if(g_v2Hunts[huntIndex].pendingTradeFvgValid &&
      g_v2Hunts[huntIndex].pendingTradeFormationTime != 0 &&
      g_v2Hunts[huntIndex].pendingTradeFormationTime <= touchBarOpenTime)
      return true;

   return false;
}

//+------------------------------------------------------------------+
int V2SelectGracePeriodFvgMemIndexForHunt(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return -1;

   const datetime touchBar = g_v2Hunts[huntIndex].touchHitM2BarOpenTime;
   if(touchBar == 0)
      return -1;

   int graceIndices[];
   int graceCount = 0;
   for(int i = 0; i < g_v2Hunts[huntIndex].fvgMemCount; i++)
   {
      if(g_v2Hunts[huntIndex].fvgMem[i].fairValueGapBarOpenTime <= touchBar)
         continue;
      ArrayResize(graceIndices, graceCount + 1);
      graceIndices[graceCount++] = i;
   }

   if(graceCount <= 0)
      return -1;
   if(graceCount == 1)
      return graceIndices[0];

   int newestIndex = graceIndices[0];
   datetime newestTime = g_v2Hunts[huntIndex].fvgMem[newestIndex].fairValueGapBarOpenTime;
   for(int j = 1; j < graceCount; j++)
   {
      const int idx = graceIndices[j];
      const datetime ft = g_v2Hunts[huntIndex].fvgMem[idx].fairValueGapBarOpenTime;
      if(ft >= newestTime)
      {
         newestTime = ft;
         newestIndex = idx;
      }
   }
   return newestIndex;
}

//+------------------------------------------------------------------+
bool V2ResolveGracePeriodTradeFvgForHunt(const int huntIndex, bool &outIsBullishFvg,
                                         double &outZoneLow, double &outZoneHigh,
                                         datetime &outFormationTime)
{
   outIsBullishFvg  = false;
   outZoneLow         = 0.0;
   outZoneHigh        = 0.0;
   outFormationTime   = 0;

   const int memIndex = V2SelectGracePeriodFvgMemIndexForHunt(huntIndex);
   if(memIndex >= 0)
   {
      outIsBullishFvg  = g_v2Hunts[huntIndex].fvgMem[memIndex].isBullishFairValueGap;
      outZoneLow       = g_v2Hunts[huntIndex].fvgMem[memIndex].fairValueGapZoneLowPrice;
      outZoneHigh      = g_v2Hunts[huntIndex].fvgMem[memIndex].fairValueGapZoneHighPrice;
      outFormationTime = g_v2Hunts[huntIndex].fvgMem[memIndex].fairValueGapBarOpenTime;
      return (outFormationTime != 0);
   }

   if(g_v2Hunts[huntIndex].pendingTradeFvgValid &&
      V2IsFvgFormedDuringTouchGrace(huntIndex, g_v2Hunts[huntIndex].pendingTradeFormationTime))
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
void V2TryPlacePendingFvgTradesAfterHuntOff(const int huntIndex, const bool fromGrace)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;

   bool     tradeIsBullishFvg  = false;
   double   tradeZoneLow       = 0.0;
   double   tradeZoneHigh      = 0.0;
   datetime tradeFormationTime = 0;
   if(fromGrace)
   {
      if(!V2ResolveGracePeriodTradeFvgForHunt(huntIndex, tradeIsBullishFvg, tradeZoneLow,
                                              tradeZoneHigh, tradeFormationTime))
      {
         V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt OFF — no grace-period FVG for trade");
         return;
      }
   }
   else if(!V2ResolveTradeFvgForHunt(huntIndex, tradeIsBullishFvg, tradeZoneLow, tradeZoneHigh,
                                     tradeFormationTime))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt OFF — no FVG for trade");
      return;
   }

   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   const int      fvgCount  = g_v2Hunts[huntIndex].fvgMemCount;
   const int      memIndex  = (fromGrace
                               ? V2SelectGracePeriodFvgMemIndexForHunt(huntIndex)
                               : V2SelectTradeFvgMemIndexForHunt(huntIndex));
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

   double   m15LegRange = 0.0;
   datetime m15LegEnd   = 0;
   if(!V4ResolveM15SameDirLegRangeForTp(tradeIsBullishFvg, m15LegRange, m15LegEnd))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("no completed M15 %s leg for TP",
                                  tradeIsBullishFvg ? "up" : "down"));
      g_v2Hunts[huntIndex].pendingTradeFvgValid = false;
      return;
   }

   V2LogHuntEvent(huntIndex, "TRADE_M15_LEG_TP",
                  StringFormat("%s leg H-L=%.5f end=%s",
                               tradeIsBullishFvg ? "up" : "down", m15LegRange,
                               TimeToString(m15LegEnd, TIME_DATE | TIME_MINUTES)));

   TryPlaceOppositeFvgTradeSetup(tradeIsBullishFvg, tradeZoneLow, tradeZoneHigh,
                                 tradeFormationTime, sessionId, m15LegRange, fromGrace);
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

   const bool polarityMatchesHunt =
      (g_v2Hunts[huntIndex].m15HighWasBreached && !isBullishFairValueGap) ||
      (!g_v2Hunts[huntIndex].m15HighWasBreached && isBullishFairValueGap);
   if(!polarityMatchesHunt)
      return;

   V2LogHuntEvent(huntIndex, "FVG_AFTER_TOUCH_RECALC_SKIP",
                  StringFormat("%s zone=%.5f-%.5f skipBar=%s fvgBar=%s",
                               isBullishFairValueGap ? "bull" : "bear",
                               zoneLowPrice, zoneHighPrice,
                               TimeToString(g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime,
                                            TIME_DATE | TIME_MINUTES),
                               TimeToString(formationTime, TIME_DATE | TIME_MINUTES)));

   double   m15LegRange = 0.0;
   datetime m15LegEnd   = 0;
   if(!V4ResolveM15SameDirLegRangeForTp(isBullishFairValueGap, m15LegRange, m15LegEnd))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("FVG after recalc skip — no completed M15 %s leg for TP",
                                  isBullishFairValueGap ? "up" : "down"));
      g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime = 0;
      V2EndOppositeFvgHuntSession(huntIndex, false);
      return;
   }

   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   g_v2Hunts[huntIndex].touchRecalcSkippedBarOpenTime = 0;
   V2EndOppositeFvgHuntSession(huntIndex, false);
   TryPlaceOppositeFvgTradeSetup(isBullishFairValueGap, zoneLowPrice, zoneHighPrice,
                                 formationTime, sessionId, m15LegRange);
}

//+------------------------------------------------------------------+
void V2TryPlaceFvgAndEndHuntOnTouchGrace(const int huntIndex, const bool isBullishFairValueGap,
                                          const double zoneLowPrice, const double zoneHighPrice,
                                          const datetime formationTime)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   if(!g_v2Hunts[huntIndex].touchPointTouched || g_v2Hunts[huntIndex].touchGraceBarsRemaining <= 0)
      return;
   if(formationTime == 0 || g_v2Hunts[huntIndex].sessionId == 0)
      return;

   const bool polarityMatchesHunt =
      (g_v2Hunts[huntIndex].m15HighWasBreached && !isBullishFairValueGap) ||
      (!g_v2Hunts[huntIndex].m15HighWasBreached && isBullishFairValueGap);
   if(!polarityMatchesHunt)
   {
      V2LogHuntEvent(huntIndex, "GRACE_FVG_SKIP", "polarity mismatch");
      return;
   }

   if(!V2IsFvgFormedDuringTouchGrace(huntIndex, formationTime))
   {
      V2LogHuntEvent(huntIndex, "GRACE_FVG_SKIP",
                     StringFormat("pre-touch FVG formation=%s touchBar=%s",
                                  TimeToString(formationTime, TIME_DATE | TIME_MINUTES),
                                  TimeToString(g_v2Hunts[huntIndex].touchHitM2BarOpenTime,
                                               TIME_DATE | TIME_MINUTES)));
      return;
   }

   const datetime sessionId = g_v2Hunts[huntIndex].sessionId;
   if(g_v2Hunts[huntIndex].tradeOrdersActive &&
      (V2HuntHasOpenPositionForSession(sessionId) ||
       V2HuntHasPendingOrdersForSession(sessionId)))
   {
      g_v2Hunts[huntIndex].touchGraceBarsRemaining = 0;
      g_v2Hunts[huntIndex].touchHitM2BarOpenTime   = 0;
      if(g_v2Hunts[huntIndex].active)
         V2EndOppositeFvgHuntSession(huntIndex, false);
      V2LogHuntEvent(huntIndex, "GRACE_FVG_SKIP", "orders/position already active");
      return;
   }

   if(g_v2Hunts[huntIndex].tradeOrdersActive)
      g_v2Hunts[huntIndex].tradeOrdersActive = false;

   V2LogHuntEvent(huntIndex, "GRACE_TRADE_ATTEMPT",
                  StringFormat("%s zone=%.5f-%.5f graceBars=%d",
                               isBullishFairValueGap ? "bull" : "bear",
                               zoneLowPrice, zoneHighPrice,
                               g_v2Hunts[huntIndex].touchGraceBarsRemaining));

   V2LogHuntEvent(huntIndex, "FVG_ON_TOUCH_GRACE",
                  StringFormat("%s zone=%.5f-%.5f formation=%s touch=%.5f",
                               isBullishFairValueGap ? "bull" : "bear",
                               zoneLowPrice, zoneHighPrice,
                               TimeToString(formationTime, TIME_DATE | TIME_MINUTES),
                               g_v2Hunts[huntIndex].touchLevel));

   double   m15LegRange = 0.0;
   datetime m15LegEnd   = 0;
   if(!V4ResolveM15SameDirLegRangeForTp(isBullishFairValueGap, m15LegRange, m15LegEnd))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("FVG on touch grace — no completed M15 %s leg for TP",
                                  isBullishFairValueGap ? "up" : "down"));
      return;
   }

   V2LogHuntEvent(huntIndex, "TRADE_M15_LEG_TP",
                  StringFormat("%s leg H-L=%.5f end=%s",
                               isBullishFairValueGap ? "up" : "down", m15LegRange,
                               TimeToString(m15LegEnd, TIME_DATE | TIME_MINUTES)));

   V2StorePendingTradeFvg(huntIndex, isBullishFairValueGap, zoneLowPrice, zoneHighPrice,
                          formationTime);
   V2LogHuntEvent(huntIndex, "GRACE_CALL_PLACE", "TryPlaceOppositeFvgTradeSetup fromGrace");
   const bool placed = TryPlaceOppositeFvgTradeSetup(isBullishFairValueGap, zoneLowPrice,
                                                     zoneHighPrice, formationTime, sessionId,
                                                     m15LegRange, true);
   g_v2Hunts[huntIndex].touchGraceBarsRemaining = 0;
   g_v2Hunts[huntIndex].touchHitM2BarOpenTime   = 0;
   if(g_v2Hunts[huntIndex].active)
      V2EndOppositeFvgHuntSession(huntIndex, false);
   if(!placed && !g_v2Hunts[huntIndex].tradeOrdersActive)
   {
      V2StorePendingTradeFvg(huntIndex, isBullishFairValueGap, zoneLowPrice, zoneHighPrice,
                             formationTime);
      V2TryPlacePendingFvgTradesAfterHuntOff(huntIndex, true);
   }
   else if(placed)
      g_v2Hunts[huntIndex].pendingTradeFvgValid = false;
}

//+------------------------------------------------------------------+
void V2EndOppositeFvgHuntSession(const int huntIndex, const bool tryPlaceTradeAfterOff,
                                  const bool fromGrace)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;
   g_v2Hunts[huntIndex].active = false;
   V2ClearTouchPointLine(huntIndex);
   V2ClearImpulseBufferZone(huntIndex);
   V2ClearTouchRecalcBufferZone(huntIndex);
   if(tryPlaceTradeAfterOff)
      V2TryPlacePendingFvgTradesAfterHuntOff(huntIndex, fromGrace);
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
   if(!InputDrawImpulseCancelBufferZone ||
      InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg <= 0.0 ||
      !g_v2Hunts[huntIndex].active)
   {
      V2ClearImpulseBufferZone(huntIndex);
      return;
   }
   const double referenceHeight = ReferenceChartHeightForFairValueGapFilterM2();
   if(referenceHeight <= 0.0 || g_v2Hunts[huntIndex].m15BreachedLegLevelPrice <= 0.0 ||
      g_v2Hunts[huntIndex].sessionId == 0)
   {
      V2ClearImpulseBufferZone(huntIndex);
      return;
   }
   const double limitPrice =
      referenceHeight * (InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg / 100.0);
   datetime timeRight = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(timeRight <= g_v2Hunts[huntIndex].sessionId)
      timeRight = g_v2Hunts[huntIndex].sessionId + (datetime)PeriodSeconds(InputM2NarrativeTimeframe);
   double zoneLow  = 0.0;
   double zoneHigh = 0.0;
   if(g_v2Hunts[huntIndex].m15HighWasBreached)
   {
      zoneLow  = g_v2Hunts[huntIndex].m15BreachedLegLevelPrice;
      zoneHigh = g_v2Hunts[huntIndex].m15BreachedLegLevelPrice + limitPrice;
   }
   else
   {
      zoneHigh = g_v2Hunts[huntIndex].m15BreachedLegLevelPrice;
      zoneLow  = g_v2Hunts[huntIndex].m15BreachedLegLevelPrice - limitPrice;
   }
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
   if(!InputDrawHuntTouchRecalcBufferZone ||
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
   if(g_v2Hunts[huntIndex].m15HighWasBreached)
   {
      zoneHigh = anchorExtreme;
      zoneLow  = anchorExtreme - band;
   }
   else
   {
      zoneLow  = anchorExtreme;
      zoneHigh = anchorExtreme + band;
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
int V2ArmOppositeFvgHuntAfterM15Breach(const double m15Level, const bool m15HighBreached,
                                         const datetime breachedLegEndTime,
                                         const double barClose, const double barLow,
                                         const double barHigh)
{
   const int existing = V2FindActiveHuntByM15Leg(breachedLegEndTime, m15HighBreached);
   if(existing >= 0)
      return existing;

   const int huntIndex = V2AllocHuntSlot();
   if(huntIndex < 0)
      return -1;

   RememberM15LegLiquidityBreach(breachedLegEndTime, m15HighBreached);

   g_v2Hunts[huntIndex].active                         = true;
   g_v2Hunts[huntIndex].m15HighWasBreached             = m15HighBreached;
   g_v2Hunts[huntIndex].m15BreachedLegLevelPrice       = m15Level;
   g_v2Hunts[huntIndex].m15BreachedLegEndTime          = breachedLegEndTime;
   g_v2Hunts[huntIndex].closeWhenM15LiquidityBreached  = barClose;
   g_v2Hunts[huntIndex].pathMinLowSinceM15Breach       = barLow;
   g_v2Hunts[huntIndex].pathMaxHighSinceM15Breach      = barHigh;
   g_v2Hunts[huntIndex].impulseCloseExtremeSinceM15Breach = barClose;
   g_v2Hunts[huntIndex].sessionId                      = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   V2ResetHuntSlotSessionCounters(huntIndex);
   V2InitTouchRecalcBufferAnchor(huntIndex);
   V2UpdateTouchLevelFromM2Swing(huntIndex);

   if(m15HighBreached)
      V2LogHuntEvent(huntIndex, "HUNT_ON",
                     StringFormat("M15 up high leg=%.5f wick>=%.5f leg=%s → bearish FVG",
                                  m15Level, M15BreachWickLevelForUpLegHigh(m15Level),
                                  TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES)));
   else
      V2LogHuntEvent(huntIndex, "HUNT_ON",
                     StringFormat("M15 down low leg=%.5f wick<=%.5f leg=%s → bullish FVG",
                                  m15Level, M15BreachWickLevelForDownLegLow(m15Level),
                                  TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES)));
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

   const double pointSizePre = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double epsPre       = (pointSizePre > 0.0 ? pointSizePre : 0.00001);
   const double pathMaxBefore  = g_v2Hunts[huntIndex].pathMaxHighSinceM15Breach;
   const double pathMinBefore  = g_v2Hunts[huntIndex].pathMinLowSinceM15Breach;

   g_v2Hunts[huntIndex].pathMinLowSinceM15Breach  =
      MathMin(g_v2Hunts[huntIndex].pathMinLowSinceM15Breach, barLow);
   g_v2Hunts[huntIndex].pathMaxHighSinceM15Breach =
      MathMax(g_v2Hunts[huntIndex].pathMaxHighSinceM15Breach, barHigh);

   const bool huntExtremeMovedThisBar =
      (g_v2Hunts[huntIndex].m15HighWasBreached
       ? (g_v2Hunts[huntIndex].pathMaxHighSinceM15Breach > pathMaxBefore + epsPre)
       : (pathMinBefore <= 0.0 ||
          g_v2Hunts[huntIndex].pathMinLowSinceM15Breach < pathMinBefore - epsPre));

   V2TryArmTouchRecalcBufferResumeOnCross(huntIndex, barHigh, barLow, barClose);
   if(g_v2Hunts[huntIndex].touchRecalcBufferResumeAfterCross &&
      !g_v2Hunts[huntIndex].touchRecalcBufferTrackActiveLeg)
      V2BeginTouchRecalcBufferActiveLegTrack(huntIndex);
   V2SyncTouchRecalcBufferAnchorFromActiveLeg(huntIndex);

   if(InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg > 0.0)
   {
      const double referenceHeight = ReferenceChartHeightForFairValueGapFilterM2();
      if(referenceHeight > 0.0)
      {
         const double limitPrice =
            referenceHeight * (InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg / 100.0);
         bool cancelHunt = false;
         if(g_v2Hunts[huntIndex].m15HighWasBreached)
         {
            g_v2Hunts[huntIndex].impulseCloseExtremeSinceM15Breach =
               MathMax(g_v2Hunts[huntIndex].impulseCloseExtremeSinceM15Breach, barClose);
            if(g_v2Hunts[huntIndex].impulseCloseExtremeSinceM15Breach -
               g_v2Hunts[huntIndex].m15BreachedLegLevelPrice > limitPrice)
               cancelHunt = true;
         }
         else
         {
            g_v2Hunts[huntIndex].impulseCloseExtremeSinceM15Breach =
               MathMin(g_v2Hunts[huntIndex].impulseCloseExtremeSinceM15Breach, barClose);
            if(g_v2Hunts[huntIndex].m15BreachedLegLevelPrice -
               g_v2Hunts[huntIndex].impulseCloseExtremeSinceM15Breach > limitPrice)
               cancelHunt = true;
         }
         if(cancelHunt)
         {
            V2LogHuntEvent(huntIndex, "HUNT_OFF",
                           StringFormat("impulse cancel close=%.5f limit=%.5f", barClose, limitPrice));
            V2EndOppositeFvgHuntSession(huntIndex, false);
            return;
         }
      }
   }

   if(!g_v2Hunts[huntIndex].postTouchFvgGateOpen)
   {
      V2TryReopenPostTouchFvgGateOnSameDirBos(huntIndex);
      if(!g_v2Hunts[huntIndex].postTouchFvgGateOpen)
         V2TryReopenPostTouchFvgGateOnBufferHit(huntIndex, barHigh, barLow, barClose,
                                                huntExtremeMovedThisBar);
   }

   if(g_v2Hunts[huntIndex].postTouchFvgGateOpen)
   {
      V2TryRecalcTouchOnHuntSameDirProgress(huntIndex, barHigh, barLow, barClose,
                                            huntExtremeMovedThisBar);
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
            (g_v2Hunts[huntIndex].m15HighWasBreached && !isBullishFairValueGap) ||
            (!g_v2Hunts[huntIndex].m15HighWasBreached && isBullishFairValueGap);

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
                  if(g_v2Hunts[huntIndex].touchPointTouched &&
                     g_v2Hunts[huntIndex].touchGraceBarsRemaining > 0)
                     V2TryPlaceFvgAndEndHuntOnTouchGrace(huntIndex, isBullishFairValueGap,
                                                         fairValueGapZoneLowPrice,
                                                         fairValueGapZoneHighPrice,
                                                         newestBarOpenTime);
                  else if(g_v2Hunts[huntIndex].touchPointTouched)
                     V2LogHuntEvent(huntIndex, "GRACE_FVG_SKIP",
                                    StringFormat("graceBars=%d after FVG_MARKED",
                                                 g_v2Hunts[huntIndex].touchGraceBarsRemaining));
                  else
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
      if(g_v2Hunts[huntIndex].touchLevelReady &&
         !g_v2Hunts[huntIndex].touchPointTouched &&
         V2TryDetectTouchOfStoredLevel(huntIndex, barClose, pointSize))
      {
         V2HandleTouchHitConfirmed(huntIndex, barClose);
      }
   }

   if(!g_v2Hunts[huntIndex].active)
      return;

   if(g_v2Hunts[huntIndex].touchPointTouched && g_v2Hunts[huntIndex].touchGraceBarsRemaining > 0)
   {
      const datetime closedM2BarOpen = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
      if(closedM2BarOpen != 0 && closedM2BarOpen != g_v2Hunts[huntIndex].touchHitM2BarOpenTime)
      {
         g_v2Hunts[huntIndex].touchGraceBarsRemaining--;
         if(g_v2Hunts[huntIndex].touchGraceBarsRemaining <= 0)
         {
            bool     graceFvgAvailable = false;
            bool     graceIsBullishFvg = false;
            double   graceZoneLow      = 0.0;
            double   graceZoneHigh     = 0.0;
            datetime graceFormationTime = 0;
            if(V2ResolveGracePeriodTradeFvgForHunt(huntIndex, graceIsBullishFvg, graceZoneLow,
                                                   graceZoneHigh, graceFormationTime))
               graceFvgAvailable = true;

            g_v2Hunts[huntIndex].touchHitM2BarOpenTime = 0;
            if(g_v2Hunts[huntIndex].tradeOrdersActive)
               V2EndOppositeFvgHuntSession(huntIndex, false);
            else if(graceFvgAvailable)
            {
               V2LogHuntEvent(huntIndex, "TOUCH_GRACE_DONE",
                              StringFormat("grace expired lvl=%.5f graceFvg=%s",
                                           g_v2Hunts[huntIndex].touchLevel,
                                           TimeToString(graceFormationTime,
                                                        TIME_DATE | TIME_MINUTES)));
               V2EndOppositeFvgHuntSession(huntIndex, true, true);
            }
            else
            {
               g_v2Hunts[huntIndex].postTouchFvgGateOpen = false;
               V2LogHuntEvent(huntIndex, "TOUCH_GATE_OFF",
                              StringFormat("grace expired lvl=%.5f no grace FVG — awaiting same-dir BOS",
                                           g_v2Hunts[huntIndex].touchLevel));
            }
         }
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
bool TryDetectM15WickLiquidityBreach(const double barHigh, const double barLow,
                                     const double prevHigh, const double prevLow,
                                     const double pointSize, double &outLevel,
                                     bool &outHighBreached, datetime &outLegEndTime)
{
   outLevel        = 0.0;
   outHighBreached = false;
   outLegEndTime   = 0;

   // Bearish hunt: M15 up-leg high breach only (newest qualifying pivot first).
   for(int pivotIndex = 0; pivotIndex < g_m15DescHighPivotCount; pivotIndex++)
   {
      if(g_m15DescHighPivots[pivotIndex].swingDirection != 1)
         continue;

      const datetime legEndTime = g_m15DescHighPivots[pivotIndex].legEndTime;
      if(IsM15LegLiquidityAlreadyBreached(legEndTime, true))
         continue;

      const double wickLevel =
         M15BreachWickLevelForUpLegHigh(g_m15DescHighPivots[pivotIndex].levelPrice);
      if(!M2WickCrossesAboveLevel(wickLevel, barHigh, prevHigh, pointSize))
         continue;

      return TryAcceptM15BreachForHunt(true,
                                       g_m15DescHighPivots[pivotIndex].legHighPrice,
                                       g_m15DescHighPivots[pivotIndex].legLowPrice,
                                       legEndTime, outLevel, outHighBreached, outLegEndTime);
   }

   // Bullish hunt: M15 down-leg low breach only (newest qualifying pivot first).
   for(int pivotIndex = 0; pivotIndex < g_m15AscLowPivotCount; pivotIndex++)
   {
      if(g_m15AscLowPivots[pivotIndex].swingDirection != -1)
         continue;

      const datetime legEndTime = g_m15AscLowPivots[pivotIndex].legEndTime;
      if(IsM15LegLiquidityAlreadyBreached(legEndTime, false))
         continue;

      const double wickLevel =
         M15BreachWickLevelForDownLegLow(g_m15AscLowPivots[pivotIndex].levelPrice);
      if(!M2WickCrossesBelowLevel(wickLevel, barLow, prevLow, pointSize))
         continue;

      return TryAcceptM15BreachForHunt(false,
                                       g_m15AscLowPivots[pivotIndex].legHighPrice,
                                       g_m15AscLowPivots[pivotIndex].legLowPrice,
                                       legEndTime, outLevel, outHighBreached, outLegEndTime);
   }

   return false;
}

//+------------------------------------------------------------------+
void ProcessBosOppositeFairValueGapWindow()
{
   if(!InputEnableOppositeFvgHuntAfterM15Breach)
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

   double m15Level = 0.0;
   bool m15HighBreached = false;
   datetime breachedLegEndTime = 0;
   if(TryDetectM15WickLiquidityBreach(barHigh, barLow, prevHigh, prevLow, pointSize,
                                      m15Level, m15HighBreached, breachedLegEndTime))
   {
      const int sameLegHunt = V2FindActiveHuntByM15Leg(breachedLegEndTime, m15HighBreached);
      if(sameLegHunt < 0)
      {
         const int samePolarityHunt = V2FindActiveHuntByBreachPolarity(m15HighBreached);
         if(samePolarityHunt >= 0)
         {
            V2LogHuntEvent(samePolarityHunt, "HUNT_RESTART",
                           StringFormat("%s breach new leg=%s (replaces prior %s hunt)",
                                        m15HighBreached ? "M15 high" : "M15 low",
                                        TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES),
                                        m15HighBreached ? "high" : "low"));
            V2AbortHuntSessionForRestart(samePolarityHunt);
         }
         V2ArmOppositeFvgHuntAfterM15Breach(m15Level, m15HighBreached, breachedLegEndTime,
                                            barClose, barLow, barHigh);
      }
   }

   V2UpdateAllImpulseBufferZones();
   V2UpdateAllTouchRecalcBufferZones();
}

//+------------------------------------------------------------------+
