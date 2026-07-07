//+------------------------------------------------------------------+
//| scalping.mq5                                                      |
//| M15 primary narrative + M2 engulfing volume absorption (from h4_lq_v3) |
//| v1.00: M15 primary narrative (breach hunt + M2 engulf) |
//+------------------------------------------------------------------+
#define SCALPING_VERSION "1.01"
#property copyright ""
#property version   SCALPING_VERSION
#property description "scalping â€” M15 breach hunt + M2 engulfing volume absorption"

#include <Trade\Trade.mqh>

input group "Tester performance"
input bool   InputFastTesterMode = false; // true: no hunt logs, no chart objects/HUDs (faster backtest)

input group "Narrative timeframes"
input ENUM_TIMEFRAMES InputM15NarrativeTimeframe = PERIOD_M15; // primary: breach legs, BOS, liquidity pivots
input ENUM_TIMEFRAMES InputM2NarrativeTimeframe  = PERIOD_M2;  // secondary: engulf hunt, entry management

input bool   InputSwitchChartToM15       = true;
input int    InputWarmupBars             = 500;  // 0 = off: replay closed primary narrative bars on attach
input bool   InputDrawM15SwingLegVisuals = true;
input color  InputM15SwingTrendLineColor = clrGold;

input bool   InputDrawM2SwingLegs        = false; // chart trend lines/labels only; does not disable M2 swing or hunt logic
input color  InputM2SwingLineColor       = clrMediumPurple;
input bool   InputDrawM2SwingAnchorLevel = true;  // realtime horizontal line at M2 leg flip anchor (priceAnchorLevel)
input color  InputM2SwingAnchorColor     = clrYellow;
input int    InputM2SwingWarmupBars      = 500; // 0 = off: replay M2 on attach (plot_swing_h1_m5_copy)

input group "M15 breach -> M2 engulfing absorption"
input bool   InputEnableEngulfHuntAfterM15Breach = true;
input int    InputM15BreachBufferChartBarCount = 74; // primary-TF bars: buffer reference height + active volume breach records
input int    InputM15LiquidityPivotLookbackBars = 1166; // primary-TF replay lookback for liquidity pivot rebuild
input bool   InputDrawImpulseCancelBufferZone = true;  // hollow rect while hunt ON
input color  InputImpulseCancelBufferColor    = clrDarkOrange;
input int    InputChartRangeBarCount     = 147;
input bool   InputShowLiquidityHuntHud   = true;
input bool   InputLogHuntEvents          = true;  // Experts tab: hunt / engulf / BOS

input group "Primary BOS trade direction bias"
input bool   InputEnableM15BosTradeDirectionBias = true;  // trade with last primary-TF close-cross BOS (bull/bear)
input bool   InputShowM15BosBiasHud              = true;  // top-right bias HUD

const double M15_BREACH_ANCHOR_MULTIPLIER = 0.2; // wick+body vs prior 5-bar avg Ã¢â‚¬â€ breaches / hunt / liquidity pivots
const double M2_SWING_ANCHOR_MULTIPLIER  = 1.0; // M2 body vs prior 5-bar avg (plot_swing_h1_m5_copy)
const double M2_TOUCH_VOLUME_MIN_EXPAND_RATIO = 3.0; // touch window: max & touch bar vs window min tick vol
const int    M2_TOUCH_VOLUME_MIN_INCREASE_EVENTS = 2; // bar-over-bar vol increases required when window >= 4 bars
const double M15_BOS_ANCHOR_MULTIPLIER    = 1.0; // full bar range vs prior 5-bar avg Ã¢â‚¬â€ BOS only (plot_swing_h4)
const double M15_BREACH_BUFFER_PERCENT_NEAR = 0.0;  // below high / above low
const double M15_BREACH_BUFFER_PERCENT_FAR  = 2.5; // above high / below low

input group "Engulfing absorption trade"
input bool   InputEnableAutomatedTrading = true;   // false = log trade plan only (no orders)
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
input int    InputEngulfMinSlPoints           = 0;     // min entryÃ¢â‚¬â€œSL pts; 0=broker stops level only when widening SL
input int    InputPendingStopEntryOffsetPoints = 2;    // buy stop above / sell stop below reference entry (points)
input int    InputEngulfVolMaxBaselineBars    = 30;  // max M2 bars to average between H4 breach time (T1) and Engulf pair (T2)
input double InputEngulfVolBufferPercentChart = 2.0; // spike buffer: 0..N% chart height above pair low / below pair high
input bool   InputDrawEngulfVolSpikeBufferZone  = true;  // hollow rect: lookback window + pair spike zone
input color  InputEngulfVolSpikeBufferColorBull = clrDodgerBlue;
input color  InputEngulfVolSpikeBufferColorBear = clrMediumOrchid;
input color  InputEngulfVolSpikeArrivalColor    = clrGold;

#define InputTouchVolSlBufferPercentChart    InputEngulfSlBufferPercentChart
#define InputTouchVolMinSlPoints             InputEngulfMinSlPoints
#define InputTouchVolEntryOffsetPercentChart 0.0
#define InputTouchVolRequireAscendingVolume  false
#define InputEnableOppositeFvgHuntAfterM15Breach InputEnableEngulfHuntAfterM15Breach
#define InputFairValueGapMinimumPercentOfChartRange 0.0
#define InputDrawBosOppositeFairValueGapZones     false
#define InputMaximumFairValueGapRectangles        0
#define InputHuntTouchRecalcPercentBeforeSameDirExtreme 0.0
#define InputDrawHuntTouchRecalcBufferZone        false
#define InputFvgTradeMinTickVolumePercentOfM2Avg  0.0
#define InputFvgTradeTickVolumeAvgM2BarCount      30

input group "BOS SL/TP management"
input bool   InputEnableBosMoveSlAndTp = false; // disable trailing/moving SL & TP on BOS for now

const string M15_LQ_LOG_PREFIX = "scalping";

//+------------------------------------------------------------------+
bool M15LqLoggingEnabled()
{
   return (!InputFastTesterMode && InputLogHuntEvents);
}

//+------------------------------------------------------------------+
bool M15LqChartDrawEnabled(const bool featureFlag = true)
{
   return (!InputFastTesterMode && featureFlag);
}

// --- hard-coded trade sizing (single 1:1.5 R:R TP order) ---
const double   LQ_RISK_USD_PER_TRADE              = 50.0;
const double   LQ_REWARD_RISK_RATIO               = 1.5;
const ulong    LQ_EXPERT_MAGIC                    = 940029;
const double   LQ_STOP_BUFFER_PERCENT_CHART       = 1.0;
const long     LQ_TOUCH_VOL_MASSIVE_LEAP_MIN          = 45;
const int      LQ_TOUCH_VOL_SL_OLDER_BAR_LOOKBACK     = 2;
const int      LQ_FVG_TRADE_MAX_M2_BAR_SHIFT      = 24;
const int      LQ_TP_COUNT                        = 1;

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
const string ChartObjectNamePrefixM15VolumeBreachRay = "LQ2_M15_VOL_BREACH_";
const color  M15_VOLUME_BREACH_RAY_COLOR_UP   = clrGreen;
const color  M15_VOLUME_BREACH_RAY_COLOR_DOWN = clrDeepPink;
const int    M15_VOLUME_BREACH_RAY_ZORDER     = 128;
const string PFX_M2_TREND  = "LQ2_M2_TR_";
const string PFX_M2_LBL    = "LQ2_M2_LB_";
const string PFX_M2_ANCHOR = "LQ2_M2_AN_";
const string LQ_OBJ_PREFIX_FVG_RECT = "LQ2_M2_FVG_";
const string LQ_OBJ_PREFIX_FVG_LBL  = "LQ2_M2_FVGT_";
const string LQ_OBJ_HUNT_HUD        = "LQ2_HUNT_HUD";
const string LQ_OBJ_M15_BIAS_HUD    = "LQ4_H4_BIAS";
const string LQ_OBJ_IMPULSE_BUFFER  = "LQ2_IMPULSE_BUF";
const string LQ_OBJ_TOUCH_POINT     = "LQ2_TOUCH_PT";
const string LQ_OBJ_IMPULSE_PREFIX      = "LQ2_IMPULSE_BUF_";
const string LQ_OBJ_TOUCH_RECALC_PREFIX = "LQ2_TRECALC_BUF_";
const string LQ_OBJ_ENGULF_VOL_SPIKE_PREFIX   = "LQ2_ENG_VOL_";
const string LQ_OBJ_ENGULF_VOL_ARRIVAL_PREFIX = "LQ2_ENG_VOL_A_";
const string LQ_OBJ_TRADE_SWGRP_RECT_PREFIX = "LQ2_TRD_SWG_R_";
const string LQ_OBJ_TRADE_SWGRP_LINE_PREFIX = "LQ2_TRD_SWG_L_";

#define V2_MAX_HUNT_SESSIONS              2   // at most one high-breach + one low-breach hunt

enum ENUM_LIQUIDITY_TYPE
{
   LQ_EXTERNAL_TOP,
   LQ_EXTERNAL_BOTTOM,
   LQ_INTERNAL_BULL,
   LQ_INTERNAL_BEAR
};

struct V2HuntSession
{
   bool     active;
   bool     h4HighWasBreached;
   double   h4BreachedLegLevelPrice;
   datetime h4BreachedLegEndTime;
   datetime h4BreachVolumeBarOpenTime; // T1: narrative vol bar that originated breach level
   int      h4BreachSwingDirection;
   ENUM_LIQUIDITY_TYPE h4BreachLqType;
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

#define BosOppositeFairValueGapMemoryCapacity 32

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
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection;
};

#define M15_LEG_VOLUME_BREACH_CAPACITY 128

struct M15LegVolumeBreachRecord
{
   datetime            legStartTime;
   datetime            legEndTime;
   int                 swingDirection;
   ENUM_LIQUIDITY_TYPE lqType;
   double              breachLevelPrice;
   datetime            volumeBarOpenTime;
   bool                swept;     // price violated breach level (chart memory)
   bool                huntArmed; // hunt triggered for this breach record
};

struct M15ActiveLegVolumeBreachTrack
{
   datetime legStartTime;
   int      swingDirection;
   datetime windowStartOpenTime;
   long     maxTickVolume;
   datetime maxVolumeBarOpenTime;
   double   breachLevelPrice;
};

M15LegVolumeBreachRecord      g_m15LegVolumeBreaches[M15_LEG_VOLUME_BREACH_CAPACITY];
int                          g_m15LegVolumeBreachCount = 0;
M15ActiveLegVolumeBreachTrack g_m15ActiveLegVolumeTrack;

SwingState     g_m15Swing;     // anchor 0.5 Ã¢â‚¬â€ breaches, chart legs, liquidity pivots
SwingState     g_m15BosSwing;  // anchor 1.0 Ã¢â‚¬â€ BOS close-cross levels only (no visuals)
SwingState     g_m2Swing;
LiquidityPool  g_liquidityPools[LiquidityPoolCapacity];
int            g_liquidityPoolCount = 0;

datetime g_lastM15BarOpen = 0;
datetime g_lastM2BarOpen  = 0;

V2HuntSession g_v2Hunts[V2_MAX_HUNT_SESSIONS];

M15LiquidityPivot g_m15DescHighPivots[M15_LIQUIDITY_PIVOT_CAPACITY];
int               g_m15DescHighPivotCount = 0;
M15LiquidityPivot g_m15AscLowPivots[M15_LIQUIDITY_PIVOT_CAPACITY];
int               g_m15AscLowPivotCount = 0;

#define M15_BOS_RECORDED_LEG_CAPACITY 32

struct M15BosRecord
{
   int      direction;   // 1 = bull BOS, -1 = bear BOS
   datetime barOpenTime;
   datetime legEndTime;  // completed H4 leg that was broken (dedupe key)
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
   datetime breakBarOpenTime; // H4 bar that closed through the level (await 1 more close)
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
bool   TryGetM15LegBarOpenTimeFromEnd(const datetime legStartTime, const datetime legEndTime,
                                      const int nFromEnd, datetime &outBarOpenTime);
ENUM_LIQUIDITY_TYPE M15ExternalLqTypeForSwingDirection(const int swingDirection);
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
double ReferenceChartHeightForM15BarCount(const int barCount);
double ReferenceChartHeightForM15BreachBuffer();
void   M15BreachBufferBandForUpLegHigh(const double legHigh, double &outBandLow, double &outBandHigh);
void   M15BreachBufferBandForDownLegLow(const double legLow, double &outBandLow, double &outBandHigh);
bool   M15BreachImpulseCancelZonePrices(const bool expectBullishFvgHunt, const double breachLevel,
                                        double &outZoneLow, double &outZoneHigh,
                                        double &outCancelLimitPrice);
int    GetM15TradeDirectionBias(); // 1 bull, -1 bear, 0 undefined/mixed/disabled-filter
void   LogM15TradeDirectionBiasIfChanged();
bool   FvgTradeAllowedByM15BosBias(const bool isBullishFairValueGap, string &outBlockReason);
void   RefreshM15BosBiasHud();
bool   TryDetectM2BreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap, double &outBosLegLevelPrice);
void   V2InitHuntSlot(const int huntIndex);
void   V2InitAllHuntSlots();
int    V2CountActiveHunts();
int    V2AllocHuntSlot();
int    V2FindActiveHuntByM15Leg(const datetime legEndTime, const bool h4HighBreached);
int    V2FindActiveHuntByBreachPolarity(const bool h4HighBreached);
void   V2AbortHuntSessionForRestart(const int huntIndex);
int    V2FindHuntSlotBySessionId(const datetime sessionId);
string V2HuntObjectSuffix(const datetime sessionId);
string V2HuntTradeCommentPrefix(const datetime sessionId);
void   V2LogHuntEvent(const int huntIndex, const string eventName, const string detail = "");
void   ProcessHuntEngulfingOnM2BarClose();
void   V2ProcessOneActiveHuntOnM2Bar(const int huntIndex, const double pointSize,
                                     const double barClose, const double barHigh, const double barLow,
                                     const double prevHigh, const double prevLow);
int    V2OppositeM2LegDirectionForHunt(const int huntIndex);
bool   V2HuntExpectsBullishFvg(const int huntIndex);
bool   V2FvgPolarityMatchesHunt(const int huntIndex, const bool isBullishFairValueGap);
void   V2ResetHuntSlotSessionCounters(const int huntIndex);
bool   V2TryGetLastCompletedM2Leg(const int legDirection, double &outLegLow, double &outLegHigh,
                                   datetime &outLegStartTime, datetime &outLegEndTime);
bool   M2FindImpulseBaseBar(const datetime legStartTime, const datetime legEndTime, const int legDirection,
                             int &outBarShift);
bool   V2TryGetOppositeM2LegExtentsForTouch(const int huntIndex, double &outLegLow, double &outLegHigh,
                                               datetime &outLegStartTime, datetime &outLegEndTime);
bool   V2GetSameDirExtremeWhileHuntOn(const int huntIndex, double &outExtreme);
bool   V2TryDetectOppositeDirBosForHunt(const int huntIndex, string &outBosDetail);
void   OnM2SwingLegDirectionChange(const int closingLegDirection, const int nextLegDirection);
void   V2ClearImpulseBufferZone(const int huntIndex);
void   V3ClearEngulfVolSpikeBufferDraw(const int huntIndex);
void   V3RefreshEngulfVolSpikeBufferDraw(const int huntIndex, const bool isBuy,
                                          const int candle1Shift, const int candle2Shift);
void   V2UpdateImpulseBufferZone(const int huntIndex);
void   V2UpdateAllImpulseBufferZones();
int    V2ArmOppositeFvgHuntAfterM15Breach(const double h4Level, const bool h4HighBreached,
                                            const datetime breachedLegEndTime,
                                            const int swingDirection, const ENUM_LIQUIDITY_TYPE lqType,
                                            const datetime breachedVolumeBarOpenTime,
                                            const double barClose, const double barLow,
                                            const double barHigh);
void   V2EndOppositeFvgHuntSession(const int huntIndex, const string offReason,
                                    const bool tryPlaceTradeAfterOff = false);
void   V2OnM15LegClosedForHunts(const int closedLegDirection, const datetime closedLegEndTime);
int    V2OppositeM15LegDirectionForHunt(const int huntIndex);

void   ApplyTradeFillingModeFromSymbol();
double M2TouchVolSlBufferPrice(const int barShift);
double M2TouchVolEntryOffsetPrice(const int barShift);
double M2TouchVolLimitEntryPrice(const bool isBuy, const int barShift,
                                  const double barLow, const double barHigh);
double M2PendingStopEntryPrice(const bool isBuy, const double referenceEntryPrice);
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
void   CheckHuntPreEntrySlCancelOnTick();
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
void   ManageHuntTradeTieredStopLoss(const bool isBuy);
bool   HuntTradeCommentIsOvTpIndex(const string orderComment, const int tpIndex);

//+------------------------------------------------------------------+
int OnInit()
{
   if(InputSwitchChartToM15 && !InputFastTesterMode)
   {
      ChartSetSymbolPeriod(0, _Symbol, InputM15NarrativeTimeframe);
      ChartRedraw(0);
   }

   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingLabelText, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15VolumeBreachRay, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_ANCHOR, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_RECT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_LBL, -1, -1);
   ObjectDelete(0, LQ_OBJ_HUNT_HUD);
   ObjectsDeleteAll(0, LQ_OBJ_IMPULSE_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_ENGULF_VOL_SPIKE_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_ENGULF_VOL_ARRIVAL_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_RECALC_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_POINT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_RECT_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_LINE_PREFIX, -1, -1);

   ZeroMemory(g_m15Swing);
   ZeroMemory(g_m15BosSwing);
   ZeroMemory(g_m2Swing);
   g_liquidityPoolCount = 0;

   V2InitAllHuntSlots();
   g_m15LegVolumeBreachCount          = 0;
   ZeroMemory(g_m15ActiveLegVolumeTrack);
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

   if(M15LqLoggingEnabled())
   {
      PrintFormat("%s v%s | primary=%s secondary=%s fastTester=%s",
                  M15_LQ_LOG_PREFIX, SCALPING_VERSION,
                  EnumToString(InputM15NarrativeTimeframe),
                  EnumToString(InputM2NarrativeTimeframe),
                  InputFastTesterMode ? "Y" : "N");
   }

   if(M15LqChartDrawEnabled())
   {
      RefreshLiquidityHuntHud();
      RefreshM15BosBiasHud();
      ChartRedraw(0);
   }
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingLabelText, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15VolumeBreachRay, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_ANCHOR, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_RECT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_LBL, -1, -1);
   ObjectDelete(0, LQ_OBJ_HUNT_HUD);
   ObjectDelete(0, LQ_OBJ_M15_BIAS_HUD);
   ObjectsDeleteAll(0, LQ_OBJ_IMPULSE_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_ENGULF_VOL_SPIKE_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_ENGULF_VOL_ARRIVAL_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_RECALC_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TOUCH_POINT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_RECT_PREFIX, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_TRADE_SWGRP_LINE_PREFIX, -1, -1);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   CheckHuntPreEntrySlCancelOnTick();
   CheckHuntPreEntryTp3CancelOnTick();
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckHuntPreEntrySlCancelOnTick();
   CheckHuntPreEntryTp3CancelOnTick();
   if(M15LqChartDrawEnabled())
   {
      UpdateM2SwingAnchorVisualRealtime(g_m2Swing);
      UpdateM2LiveSwingLegVisualOnTick();
   }

   const datetime tH4 = iTime(_Symbol, InputM15NarrativeTimeframe, 0);
   if(tH4 != g_lastM15BarOpen)
   {
      g_lastM15BarOpen = tH4;
      ProcessM15SwingStep(1);
      ProcessM15BosSwingStep(1);
      RebuildM15LiquidityPivotLevels();
      ProcessM15BosOnM15Close(1);
      if(InputEnableM15BosTradeDirectionBias)
         LogM15TradeDirectionBiasIfChanged();
      if(M15LqChartDrawEnabled(InputShowM15BosBiasHud))
         RefreshM15BosBiasHud();
   }

   const datetime tM2 = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(tM2 != g_lastM2BarOpen)
   {
      g_lastM2BarOpen = tM2;
      if(InputEnableEngulfHuntAfterM15Breach)
         ProcessHuntEngulfingOnM2BarClose();
      ProcessM2SwingStep();
      ManageHuntOpenPositionsOnM2BarClose();
      if(M15LqChartDrawEnabled(InputShowLiquidityHuntHud))
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
// plot_swing_h1_m5_copy SwingClose Ã¢â‚¬â€ M2 only (no H1 keyLevelId).
//+------------------------------------------------------------------+
void SwingCloseM2Leg(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                     const string chartObjectNamePrefix, const string labelPrefix,
                     const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.keyLevelId = 0;

   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   if(timeframe == InputM2NarrativeTimeframe && M15LqChartDrawEnabled(InputDrawM2SwingLegs))
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

   if(M15LqChartDrawEnabled(InputDrawM2SwingLegs))
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
   if(!M15LqChartDrawEnabled(InputDrawM2SwingLegs) || swingState.currentSwingLeg.swingDirection == 0)
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
//| Realtime segment at priceAnchorLevel Ã¢â‚¬â€ close cross vs this flips the M2 leg. |
//+------------------------------------------------------------------+
void UpdateM2SwingAnchorVisualRealtime(const SwingState &swingState)
{
   const string liveName = PFX_M2_ANCHOR + "LIVE";

   if(!M15LqChartDrawEnabled(InputDrawM2SwingAnchorLevel) ||
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
   // Anchor tolerance: M2 = body vs 0.2Ãƒâ€” prior avg; H4 = wick AND body vs 0.5Ãƒâ€” prior avg.
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
      (timeframe == InputM15NarrativeTimeframe) ? 0.5 : 0.2;
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
void SwingCloseM15Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                          const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   const double poolLowPrice  = swingState.currentSwingLeg.legLowPrice;
   const double poolHighPrice = swingState.currentSwingLeg.legHighPrice;
   const bool   isSupplyPool  = (swingState.currentSwingLeg.swingDirection == 1);
   PushLiquidityPoolFromClosedSwing(poolLowPrice, poolHighPrice, isSupplyPool);

   if(M15LqChartDrawEnabled(InputDrawM15SwingLegVisuals))
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
         ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 1);
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

   if(withBreachSideEffects)
      SwingCloseM15Context(swingState, timeframe, sh);
   else
      SwingCloseM15ToHistory(swingState, timeframe, sh);

   Swing closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
   if(withBreachSideEffects)
   {
      M15SyncExternalBreachFromSwingLeg(closedSwingLeg);
      V2OnM15LegClosedForHunts(closedSwingLeg.swingDirection, closedSwingLeg.legEndTime);
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
//| M15 breach/hunt swing legs: anchor 0.5 (wick + body vs prior 5-bar avg). |
//+------------------------------------------------------------------+
void ProcessM15SwingStep(const int lastClosedBarShift = 1)
{
   ProcessM15SwingStepCore(g_m15Swing, lastClosedBarShift, M15_BREACH_ANCHOR_MULTIPLIER, true, true);
}

//+------------------------------------------------------------------+
//| H4 BOS swing legs: anchor 1.0 (full range vs prior 5-bar avg), memory only. |
//+------------------------------------------------------------------+
void ProcessM15BosSwingStep(const int lastClosedBarShift = 1)
{
   ProcessM15SwingStepCore(g_m15BosSwing, lastClosedBarShift, M15_BOS_ANCHOR_MULTIPLIER, false, false);
}

//+------------------------------------------------------------------+
void RefreshLiquidityHuntHud()
{
   if(!M15LqChartDrawEnabled(InputShowLiquidityHuntHud))
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
   string txt = "v3 hunts: none";
   if(activeCount > 0)
   {
      if(highOn && lowOn)
         txt = "v3 hunts: high+low";
      else if(highOn)
         txt = "v3 hunts: high";
      else if(lowOn)
         txt = "v3 hunts: low";
      else
         txt = StringFormat("v3 hunts: %d active", activeCount);
   }
   ObjectSetString(0, LQ_OBJ_HUNT_HUD, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_COLOR, activeCount > 0 ? clrLime : clrSilver);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
//| H4 BOS cross: close cross vs latest same-dir leg on g_m15BosSwing (anchor 1.0). |
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
//| Confirm pending BOS after 1 closed H4 candle (reject fake breakout). |
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
      if(M15LqLoggingEnabled())
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

   if(M15LqLoggingEnabled())
   {
      LogHuntEvent("H4_BOS_REJECT",
                   StringFormat("%s fake breakout breakBar=%s confirmBar=%s close=%.5f lvl=%.5f",
                                direction == 1 ? "bull" : "bear",
                                TimeToString(breakBarOpenTime, TIME_DATE | TIME_MINUTES),
                                TimeToString(confirmBarOpenTime, TIME_DATE | TIME_MINUTES),
                                iClose(_Symbol, InputM15NarrativeTimeframe, m15BarShift),
                                brokenLevel));
   }
}

//+------------------------------------------------------------------+
//| H4 BOS: cross Ã¢â€ â€™ pending; next H4 close must hold beyond level.   |
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

   if(M15LqLoggingEnabled())
   {
      LogHuntEvent("H4_BOS_PENDING",
                   StringFormat("%s cross breakBar=%s legEnd=%s lvl=%.5f Ã¢â‚¬â€ await 1 H4 close",
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
   if(!M15LqLoggingEnabled() || !InputEnableM15BosTradeDirectionBias)
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

   LogHuntEvent("H4_BIAS",
                StringFormat("%s Ã¢â€ â€™ %s (lastBreak=%s bar=%s)",
                             M15TradeDirectionBiasText(g_m15LastLoggedEffectiveBias),
                             M15TradeDirectionBiasText(bias),
                             g_m15LastBosRecordValid
                                ? (g_m15LastBosRecord.direction == 1 ? "bull" : "bear")
                                : "none",
                             g_m15LastBosRecordValid
                                ? TimeToString(g_m15LastBosRecord.barOpenTime, TIME_DATE | TIME_MINUTES)
                                : "Ã¢â‚¬â€"));
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
double ReferenceChartHeightForM15BarCount(const int barCount)
{
   if(barCount < 1)
      return 0.0;

   const int totalBars = iBars(_Symbol, InputM15NarrativeTimeframe);
   if(totalBars < 4)
      return 0.0;

   const int useBarCount = (int)MathMin((double)barCount, (double)(totalBars - 1));
   if(useBarCount < 1)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = 1; barShiftIndex <= useBarCount; barShiftIndex++)
   {
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, InputM15NarrativeTimeframe, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, InputM15NarrativeTimeframe, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForM15BreachBuffer()
{
   return ReferenceChartHeightForM15BarCount(InputM15BreachBufferChartBarCount);
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
//| Same M2 swing legs already drawn on chart (PFX_M2_TREND) Ã¢â‚¬â€ optional supplement when draw is on. |
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

   if(M15LqChartDrawEnabled(InputDrawM2SwingLegs))
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
//| Group swing extremes Ã¢â€ â€™ qualifying line TPs (min R:R) + optional chart zones. |
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

      if(InputTradeSwingTpFrontRunPercentOfChartRange > 0.0)
      {
         const double frontRunOffset = chartHeight * (InputTradeSwingTpFrontRunPercentOfChartRange / 100.0);
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

      if(!M15LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
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

   if(M15LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
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
      outBlockReason = StringFormat("H4 BOS overall bias %s blocks %s FVG",
                                    bias == 1 ? "bull" : "bear",
                                    isBullishFairValueGap ? "bull" : "bear");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void RefreshM15BosBiasHud()
{
   if(!M15LqChartDrawEnabled(InputShowM15BosBiasHud))
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
   string       arrow = "Ã¢â‚¬â€";
   color        col   = clrSilver;
   if(bias == 1)
   {
      arrow = "Ã¢â€ â€˜";
      col   = clrLime;
   }
   else if(bias == -1)
   {
      arrow = "Ã¢â€ â€œ";
      col   = clrTomato;
   }

   ObjectSetString(0, LQ_OBJ_M15_BIAS_HUD, OBJPROP_TEXT, "H4 " + arrow);
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
bool TryGetM15LegBarOpenTimeFromEnd(const datetime legStartTime, const datetime legEndTime,
                                    const int nFromEnd, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legEndTime == 0 || nFromEnd < 1)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM15NarrativeTimeframe;
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
//| External breach ray: up-leg high / down-leg low at the vol bar.   |

//+------------------------------------------------------------------+
ENUM_LIQUIDITY_TYPE M15ExternalLqTypeForSwingDirection(const int swingDirection)
{
   if(swingDirection == 1)
      return LQ_EXTERNAL_TOP;
   if(swingDirection == -1)
      return LQ_EXTERNAL_BOTTOM;
   return LQ_EXTERNAL_TOP;
}
//+------------------------------------------------------------------+
//| Green breach ray -> bull hunt; pink breach ray -> bear hunt.       |
//+------------------------------------------------------------------+
bool M15LqTypeExpectsBullishHunt(const ENUM_LIQUIDITY_TYPE lqType)
{
   return lqType == LQ_EXTERNAL_BOTTOM || lqType == LQ_INTERNAL_BULL;
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



bool TryPushM15ReplayLeg(M15ReplayLeg &replayLegs[], int &replayLegCount, const Swing &closedLeg)
{
   if(closedLeg.swingDirection == 0 || closedLeg.legEndTime == 0)
      return false;
   if(replayLegCount >= M15_REPLAY_LEG_CAPACITY)
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

//+------------------------------------------------------------------+
bool M15BreachRecordActiveInBuffer(const M15LegVolumeBreachRecord &rec)
{
   if(rec.swept || rec.swingDirection == 0 || rec.breachLevelPrice <= 0.0)
      return false;

   if(InputM15BreachBufferChartBarCount < 1)
      return true;

   const datetime refOpenTime = (rec.volumeBarOpenTime > 0)
                                 ? rec.volumeBarOpenTime
                                 : ((rec.legEndTime > 0) ? rec.legEndTime : rec.legStartTime);
   if(refOpenTime <= 0)
      return false;

   const int barShift = iBarShift(_Symbol, InputM15NarrativeTimeframe, refOpenTime, false);
   if(barShift < 0)
      return false;

   return barShift >= 1 && barShift <= InputM15BreachBufferChartBarCount;
}

//+------------------------------------------------------------------+
void M15UpsertExternalLegVolumeBreachRecord(const datetime legStartTime, const datetime legEndTime,
                                             const int swingDirection, const double breachLevel,
                                             const datetime volumeBarOpenTime)
{
   if(swingDirection == 0 || legStartTime == 0 || breachLevel <= 0.0)
      return;

   const ENUM_LIQUIDITY_TYPE lqType = M15ExternalLqTypeForSwingDirection(swingDirection);
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   for(int i = 0; i < g_m15LegVolumeBreachCount; i++)
   {
      if(g_m15LegVolumeBreaches[i].legStartTime != legStartTime || g_m15LegVolumeBreaches[i].lqType != lqType)
         continue;
      if(MathAbs(g_m15LegVolumeBreaches[i].breachLevelPrice - breachLevel) > eps)
         continue;

      g_m15LegVolumeBreaches[i].swingDirection    = swingDirection;
      g_m15LegVolumeBreaches[i].breachLevelPrice  = breachLevel;
      g_m15LegVolumeBreaches[i].volumeBarOpenTime = volumeBarOpenTime;
      if(legEndTime > 0)
         g_m15LegVolumeBreaches[i].legEndTime = legEndTime;
      return;
   }

   if(g_m15LegVolumeBreachCount < M15_LEG_VOLUME_BREACH_CAPACITY)
   {
      const int index = g_m15LegVolumeBreachCount++;
      g_m15LegVolumeBreaches[index].legStartTime        = legStartTime;
      g_m15LegVolumeBreaches[index].legEndTime          = legEndTime;
      g_m15LegVolumeBreaches[index].swingDirection      = swingDirection;
      g_m15LegVolumeBreaches[index].lqType              = lqType;
      g_m15LegVolumeBreaches[index].breachLevelPrice    = breachLevel;
      g_m15LegVolumeBreaches[index].volumeBarOpenTime   = volumeBarOpenTime;
      g_m15LegVolumeBreaches[index].swept               = false;
      g_m15LegVolumeBreaches[index].huntArmed           = false;
      return;
   }

   for(int shiftIndex = 1; shiftIndex < M15_LEG_VOLUME_BREACH_CAPACITY; shiftIndex++)
      g_m15LegVolumeBreaches[shiftIndex - 1] = g_m15LegVolumeBreaches[shiftIndex];

   const int lastIndex = M15_LEG_VOLUME_BREACH_CAPACITY - 1;
   g_m15LegVolumeBreaches[lastIndex].legStartTime        = legStartTime;
   g_m15LegVolumeBreaches[lastIndex].legEndTime          = legEndTime;
   g_m15LegVolumeBreaches[lastIndex].swingDirection      = swingDirection;
   g_m15LegVolumeBreaches[lastIndex].lqType              = lqType;
   g_m15LegVolumeBreaches[lastIndex].breachLevelPrice    = breachLevel;
   g_m15LegVolumeBreaches[lastIndex].volumeBarOpenTime   = volumeBarOpenTime;
   g_m15LegVolumeBreaches[lastIndex].swept               = false;
   g_m15LegVolumeBreaches[lastIndex].huntArmed           = false;
}

//+------------------------------------------------------------------+
void M15SyncExternalBreachFromSwingLeg(const Swing &leg)
{
   if(leg.swingDirection == 0 || leg.legStartTime == 0)
      return;

   const double breachLevel = (leg.swingDirection == 1) ? leg.legHighPrice : leg.legLowPrice;
   if(breachLevel <= 0.0)
      return;

   const datetime volumeBarOpenTime = (leg.legEndTime > 0) ? leg.legEndTime : leg.legStartTime;
   M15UpsertExternalLegVolumeBreachRecord(leg.legStartTime, leg.legEndTime, leg.swingDirection,
                                           breachLevel, volumeBarOpenTime);
}

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
//| Completed H4 swing legs in lookback: up-leg high / down-leg low pivots only.   |
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

      double breachLevel = replayLegs[legIndex].legHighPrice;
      for(int breachIndex = 0; breachIndex < g_m15LegVolumeBreachCount; breachIndex++)
      {
         if(g_m15LegVolumeBreaches[breachIndex].legStartTime == replayLegs[legIndex].legStartTime &&
            g_m15LegVolumeBreaches[breachIndex].lqType == LQ_EXTERNAL_TOP)
         {
            breachLevel = g_m15LegVolumeBreaches[breachIndex].breachLevelPrice;
            break;
         }
      }

      const int outIndex = g_m15DescHighPivotCount;
      g_m15DescHighPivots[outIndex].levelPrice     = breachLevel;
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

      double breachLevel = replayLegs[legIndex].legLowPrice;
      for(int breachIndex = 0; breachIndex < g_m15LegVolumeBreachCount; breachIndex++)
      {
         if(g_m15LegVolumeBreaches[breachIndex].legStartTime == replayLegs[legIndex].legStartTime &&
            g_m15LegVolumeBreaches[breachIndex].lqType == LQ_EXTERNAL_BOTTOM)
         {
            breachLevel = g_m15LegVolumeBreaches[breachIndex].breachLevelPrice;
            break;
         }
      }

      const int outIndex = g_m15AscLowPivotCount;
      g_m15AscLowPivots[outIndex].levelPrice     = breachLevel;
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
//| Breach buffer band (% of H4 reference height): high 2% below..10% above; low 2% above..10% below. |
//+------------------------------------------------------------------+
void M15BreachBufferBandForUpLegHigh(const double breachLevel, double &outBandLow, double &outBandHigh)
{
   const double referenceHeight = ReferenceChartHeightForM15BreachBuffer();
   if(referenceHeight <= 0.0)
   {
      outBandLow  = breachLevel;
      outBandHigh = breachLevel;
      return;
   }

   outBandLow  = breachLevel - referenceHeight * (M15_BREACH_BUFFER_PERCENT_NEAR / 100.0);
   outBandHigh = breachLevel + referenceHeight * (M15_BREACH_BUFFER_PERCENT_FAR / 100.0);
}

//+------------------------------------------------------------------+
void M15BreachBufferBandForDownLegLow(const double breachLevel, double &outBandLow, double &outBandHigh)
{
   const double referenceHeight = ReferenceChartHeightForM15BreachBuffer();
   if(referenceHeight <= 0.0)
   {
      outBandLow  = breachLevel;
      outBandHigh = breachLevel;
      return;
   }

   outBandLow  = breachLevel - referenceHeight * (M15_BREACH_BUFFER_PERCENT_FAR / 100.0);
   outBandHigh = breachLevel + referenceHeight * (M15_BREACH_BUFFER_PERCENT_NEAR / 100.0);
}

//+------------------------------------------------------------------+
bool M15BreachImpulseCancelZonePrices(const bool expectBullishFvgHunt, const double breachLevel,
                                       double &outZoneLow, double &outZoneHigh,
                                       double &outCancelLimitPrice)
{
   outZoneLow = 0.0;
   outZoneHigh = 0.0;
   outCancelLimitPrice = 0.0;

   if(M15_BREACH_BUFFER_PERCENT_FAR <= 0.0 || breachLevel <= 0.0)
      return false;

   const double referenceHeight = ReferenceChartHeightForM15BreachBuffer();
   if(referenceHeight <= 0.0)
      return false;

   const double farOffset = referenceHeight * (M15_BREACH_BUFFER_PERCENT_FAR / 100.0);
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
bool M2WickCrossesIntoM15UpBreachBuffer(const double bandLow, const double bandHigh,
                                        const double barHigh, const double prevHigh,
                                        const double pointSize)
{
   if(prevHigh >= bandLow - pointSize)
      return false;
   return barHigh >= bandLow - pointSize;
}

//+------------------------------------------------------------------+
bool M2WickCrossesIntoM15DownBreachBuffer(const double bandLow, const double bandHigh,
                                          const double barLow, const double prevLow,
                                          const double pointSize)
{
   if(prevLow <= bandHigh + pointSize)
      return false;
   return barLow <= bandHigh + pointSize;
}

//+------------------------------------------------------------------+
bool TryAcceptM15BreachForHunt(const bool h4HighBreached, const double breachLevel,
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
   if(!M15LqLoggingEnabled())
      return;

   const datetime barTime = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   const string timeText  = (barTime != 0) ? TimeToString(barTime, TIME_DATE | TIME_MINUTES) : "no-bar";

   if(StringLen(detail) > 0)
      PrintFormat("%s [%s] %s | %s", M15_LQ_LOG_PREFIX, timeText, eventName, detail);
   else
      PrintFormat("%s [%s] %s", M15_LQ_LOG_PREFIX, timeText, eventName);
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
//| Buy hunt: vol bar low + N% chart height. Sell hunt: vol bar high Ã¢Ë†â€™ N%. |
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
//| Buy stop = reference + N pts; sell stop = reference - N pts.       |
//+------------------------------------------------------------------+
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
bool V2TrySyncPendingHuntSlWatchForSession(const datetime sessionId, const int huntIndex,
                                           int &outPendingCount, bool &outIsBuy,
                                           double &outEntryPrice, double &outStopLoss)
{
   outPendingCount = 0;
   outIsBuy        = false;
   outEntryPrice   = 0.0;
   outStopLoss     = 0.0;
   if(sessionId == 0)
      return false;

   const string prefix = V2HuntTradeCommentPrefix(sessionId);
   bool   isBuy      = (huntIndex >= 0 ? g_v2Hunts[huntIndex].tradeIsBuy : false);
   double entryPrice = (huntIndex >= 0 ? g_v2Hunts[huntIndex].tradeEntryPrice : 0.0);
   double stopLoss   = 0.0;
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
      const double orderSl    = OrderGetDouble(ORDER_SL);
      const double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      const bool orderIsBuy   = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP ||
                                 orderType == ORDER_TYPE_BUY_STOP_LIMIT);

      if(!haveSide)
      {
         isBuy       = orderIsBuy;
         entryPrice  = orderPrice;
         stopLoss    = orderSl;
         haveSide    = true;
      }
      else if(orderSl > 0.0)
      {
         if(stopLoss <= 0.0)
            stopLoss = orderSl;
         else if(isBuy)
            stopLoss = MathMin(stopLoss, orderSl);
         else
            stopLoss = MathMax(stopLoss, orderSl);
      }
   }

   if(outPendingCount <= 0 || stopLoss <= 0.0)
      return false;

   outIsBuy      = isBuy;
   outEntryPrice = entryPrice;
   outStopLoss   = stopLoss;
   return true;
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
bool HuntMarketReachedStopLossLevel(const bool isBuy, const double stopLossLevel)
{
   if(stopLossLevel <= 0.0)
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
      if(bid <= stopLossLevel + tolerance)
         return true;
      if(ask <= stopLossLevel + tolerance)
         return true;
      if(lowM1 <= stopLossLevel + tolerance)
         return true;
      if(lowM2 <= stopLossLevel + tolerance)
         return true;
      return false;
   }

   if(bid >= stopLossLevel - tolerance)
      return true;
   if(ask >= stopLossLevel - tolerance)
      return true;
   if(highM1 >= stopLossLevel - tolerance)
      return true;
   if(highM2 >= stopLossLevel - tolerance)
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
    if(M15LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
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
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt position open Ã¢â‚¬â€ one trade setup per hunt");
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
                           StringFormat("TP3=%.5f touched Ã¢â‚¬â€ same-dir M2 BOS between entry=%.5f and TP3 since %s",
                                        tp3Level, entryPrice,
                                        TimeToString(sinceTime, TIME_DATE | TIME_MINUTES)));
         else
            LogHuntEvent("HUNT_TP3_PREENTRY_BOS_KEEP",
                         StringFormat("HS%lld TP3=%.5f touched Ã¢â‚¬â€ same-dir M2 BOS between entry=%.5f and TP3",
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
void CheckHuntPreEntrySlCancelOnTick()
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
      double entryPrice = 0.0;
      double stopLoss = 0.0;
      if(!V2TrySyncPendingHuntSlWatchForSession(sessionId, huntIndex, pendingCount,
                                                isBuy, entryPrice, stopLoss))
         continue;

      if(!HuntMarketReachedStopLossLevel(isBuy, stopLoss))
         continue;

      CancelOurHuntPendingOrders(sessionId);

      int remainingForSession = 0;
      bool dummyBuy = false;
      double dummyEntry = 0.0;
      double dummySl = 0.0;
      V2TrySyncPendingHuntSlWatchForSession(sessionId, huntIndex, remainingForSession,
                                            dummyBuy, dummyEntry, dummySl);

      if(remainingForSession > 0)
      {
         if(huntIndex >= 0)
            V2LogHuntEvent(huntIndex, "HUNT_SL_PREENTRY_FAIL",
                           StringFormat("SL=%.5f hit but %d pendings remain (bid=%.5f ask=%.5f)",
                                        stopLoss, remainingForSession, bid, ask));
         else
            LogHuntEvent("HUNT_SL_PREENTRY_FAIL",
                         StringFormat("HS%lld SL=%.5f hit but %d pendings remain (bid=%.5f ask=%.5f)",
                                      (long)sessionId, stopLoss, remainingForSession, bid, ask));
         continue;
      }

      V2ClearHuntTradeOrdersActiveForSession(sessionId);
      if(huntIndex >= 0)
      {
         V2LogHuntEvent(huntIndex, "HUNT_SL_PREENTRY_CANCEL",
                        StringFormat("pending removed: SL=%.5f entry=%.5f %s pend=%d bid=%.5f ask=%.5f hiM2=%.5f loM2=%.5f",
                                     stopLoss, entryPrice, isBuy ? "buy" : "sell", pendingCount, bid, ask,
                                     iHigh(_Symbol, InputM2NarrativeTimeframe, 0),
                                     iLow(_Symbol, InputM2NarrativeTimeframe, 0)));
      }
      else
         LogHuntEvent("HUNT_SL_PREENTRY_CANCEL",
                      StringFormat("HS%lld pending removed: SL=%.5f entry=%.5f %s pend=%d bid=%.5f ask=%.5f",
                                   (long)sessionId, stopLoss, entryPrice, isBuy ? "buy" : "sell",
                                   pendingCount, bid, ask));
   }

   V2RefreshGlobalHuntTradeWatchFromSessions();
}

//+------------------------------------------------------------------+
//| Bull: bid > top+1% M2 chart rng Ã¢â€ â€™ BuyLimit @ top+1%; else market buy.          |
//| Bear: ask < lowÃ¢Ë†â€™1% M2 chart rng Ã¢â€ â€™ SellLimit @ lowÃ¢Ë†â€™1%; else market sell.         |
//+------------------------------------------------------------------+
// Latest completed H4 same-dir leg (g_m15Swing 0.5). TP = 0.9x / 1.4x / 1.9x from entry.
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
      ok = g_trade.BuyStop(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                           ORDER_TIME_GTC, 0, comment);
   else
      ok = g_trade.SellStop(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                            ORDER_TIME_GTC, 0, comment);

   if(!ok)
      LogHuntEvent("TRADE_ORDER_FAIL",
                   StringFormat("%s ret=%d %s", comment,
                                (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
   return ok;
}

//+------------------------------------------------------------------+
bool PlaceOneFvgTradeOrderStopThenMarket(const bool isBuy, const double entryPrice,
                                          const double stopLossPrice, const double takeProfitPrice,
                                          const double volume, const string comment)
{
   if(PlaceOneFvgTradeOrder(isBuy, false, entryPrice, stopLossPrice, takeProfitPrice, volume, comment))
      return true;

   LogHuntEvent("TRADE_STOP_FAIL",
                StringFormat("%s ret=%d %s â€” retry market",
                             comment, (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
   return PlaceOneFvgTradeOrder(isBuy, true, entryPrice, stopLossPrice, takeProfitPrice, volume, comment);
}

//+------------------------------------------------------------------+
double ComputeRewardRiskTakeProfitPrice(const bool isBuy, const double entryPrice,
                                         const double stopLossPrice)
{
   const double slDistance = MathAbs(entryPrice - stopLossPrice);
   if(slDistance <= 0.0)
      return 0.0;

   if(isBuy)
      return NormalizeDouble(entryPrice + LQ_REWARD_RISK_RATIO * slDistance, _Digits);
   return NormalizeDouble(entryPrice - LQ_REWARD_RISK_RATIO * slDistance, _Digits);
}

//+------------------------------------------------------------------+
bool TryPlaceSingleRewardRiskTradeOrder(const bool isBuy, const bool useMarketOrder,
                                         const double referenceEntryPrice, const double stopLossPrice,
                                         const string huntCommentPrefix, const string formationTag,
                                         const bool tryStopThenMarket,
                                         int &inOutPlacedCount, int &inOutZeroVolumeCount)
{
   const double entryPrice = useMarketOrder
                             ? referenceEntryPrice
                             : M2PendingStopEntryPrice(isBuy, referenceEntryPrice);
   if(entryPrice <= 0.0)
      return false;

   const double takeProfit =
      ComputeRewardRiskTakeProfitPrice(isBuy, entryPrice, stopLossPrice);
   if(takeProfit <= 0.0)
      return false;

   if(!StopsDistanceAllowed(isBuy, entryPrice, stopLossPrice, takeProfit))
      return false;

   const string comment = StringFormat("%sOV_TP1_%s", huntCommentPrefix, formationTag);
   const double volume =
      CalculateVolumeForFixedUsdRisk(isBuy, entryPrice, stopLossPrice, LQ_RISK_USD_PER_TRADE);
   if(volume <= 0.0)
   {
      inOutZeroVolumeCount++;
      return false;
   }

   bool placed = false;
   if(tryStopThenMarket)
      placed = PlaceOneFvgTradeOrderStopThenMarket(isBuy, entryPrice, stopLossPrice, takeProfit,
                                                   volume, comment);
   else
      placed = PlaceOneFvgTradeOrder(isBuy, useMarketOrder, entryPrice, stopLossPrice, takeProfit,
                                     volume, comment);

   if(placed)
      inOutPlacedCount++;
   return placed;
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
bool TryPlaceTouchVolumeBarTradeSetup(const int huntIndex, const bool isBuy,
                                       const datetime maxVolBarOpenTime, const long maxVolume,
                                       const datetime slWindowStartOpen,
                                       const datetime huntSessionId)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || maxVolBarOpenTime == 0)
   {
      if(huntIndex >= 0 && huntIndex < V2_MAX_HUNT_SESSIONS)
         V2LogHuntEvent(huntIndex, "TRADE_SKIP", "touch vol bar entry Ã¢â‚¬â€ maxVolBarOpenTime=0");
      return false;
   }

   if(V2IsHuntSessionStillActive(huntSessionId))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt still ON Ã¢â‚¬â€ orders after touch");
      return false;
   }

   string bosBiasBlockReason = "";
   if(!FvgTradeAllowedByM15BosBias(isBuy, bosBiasBlockReason))
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
                     StringFormat("touch vol bar entry/SL invalid sh=%d entry=%.5f sl=%.5f buy=%s Ã¢â‚¬â€ %s",
                                  barShift, entryPrice, stopLossOverall, isBuy ? "Y" : "N",
                                  entryFailReason));
      return false;
   }

   double normalizedEntry = NormalizeDouble(entryPrice, _Digits);
   const double stopEntry = useMarketOrder
                            ? normalizedEntry
                            : M2PendingStopEntryPrice(isBuy, normalizedEntry);
   if(stopEntry <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "stop entry invalid");
      return false;
   }

   if(isBuy && stopEntry <= stopLossOverall)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("buy stop entry<=SL entry=%.5f sl=%.5f", stopEntry, stopLossOverall));
      return false;
   }
   if(!isBuy && stopEntry >= stopLossOverall)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("sell stop entry>=SL entry=%.5f sl=%.5f", stopEntry, stopLossOverall));
      return false;
   }

   const datetime formationTime = maxVolBarOpenTime;
   const double takeProfit =
      ComputeRewardRiskTakeProfitPrice(isBuy, stopEntry, stopLossOverall);
   if(takeProfit <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("fixed R:R TP invalid entry=%.5f sl=%.5f", stopEntry,
                                  stopLossOverall));
      return false;
   }

   if(!StopsDistanceAllowed(isBuy, stopEntry, stopLossOverall, takeProfit))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "broker stops level tp");
      return false;
   }

   if(LQ_RISK_USD_PER_TRADE <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "LQ_RISK_USD_PER_TRADE invalid");
      return false;
   }

   const string huntCommentPrefix = V2HuntTradeCommentPrefix(huntSessionId);
   const string formationTag      = IntegerToString((long)formationTime);
   int          placedCount       = 0;
   int          zeroVolumeCount   = 0;

   const string tpLog = StringFormat("%.5f (1:%.1f)", takeProfit, LQ_REWARD_RISK_RATIO);

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
      "%s ref=%.5f stopEntry=%.5f sl=%.5f (volBar sh=%d vol=%lld barL=%.5f barH=%.5f limitRef=%.5f off=%.5f anchor=%s slWin=%s slRef sh=%d %s=%.5f buf=%.5f) tp=%s stop=+%dpt",
      isBuy ? "buyHunt" : "sellHunt", normalizedEntry, stopEntry, stopLossOverall, barShift,
      (long)maxVolume,
      volBarLow, volBarHigh, limitRef, entryOff, isBuy ? "low+N%rng" : "high-N%rng",
      TimeToString(slWindowStartOpen, TIME_DATE | TIME_MINUTES), slRefBarShift,
      isBuy ? "low" : "high", slRefExtreme, bufferPrice,
      tpLog, InputPendingStopEntryOffsetPoints);

   string tradeBlockReason = "";
   if(!IsFvgAutomatedTradingAllowed(tradeBlockReason))
   {
      LogHuntEvent("TRADE_PLAN", logDetail + " | " + tradeBlockReason);
      return false;
   }

   TryPlaceSingleRewardRiskTradeOrder(isBuy, useMarketOrder, normalizedEntry, stopLossOverall,
                                       huntCommentPrefix, formationTag, false,
                                       placedCount, zeroVolumeCount);

   const int orderTargetCount = 1;
   if(placedCount > 0)
   {
      RegisterHuntTradeAfterSuccessfulPlace(isBuy, stopEntry, takeProfit,
                                            takeProfit, formationTime, huntSessionId);
      LogHuntEvent("TRADE_PLACE",
                   StringFormat("%s touchVol placed=%d/%d replace=%s %s", formationTag, placedCount,
                                orderTargetCount, replacePendingOnly ? "Y" : "N", logDetail));
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
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt still ON Ã¢â‚¬â€ orders after touch");
      return false;
   }

   string bosBiasBlockReason = "";
   if(!FvgTradeAllowedByM15BosBias(isBullishFairValueGap, bosBiasBlockReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", bosBiasBlockReason);
      return false;
   }

   bool replacePendingOnly = false;
   if(!ResolveHuntFvgOrderPlacementGate(formationTime, huntSessionId, replacePendingOnly))
      return false;

   const int formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, true);
   if(formationShift < 0 || formationShift > LQ_FVG_TRADE_MAX_M2_BAR_SHIFT)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("FVG too old shift=%d max=%d", formationShift,
                                  LQ_FVG_TRADE_MAX_M2_BAR_SHIFT));
      return false;
   }

   if(!FvgFormationBarMeetsMinTickVolume(formationShift))
      return false;

   // Middle bar of the 3-bar FVG pattern (The displacement candle that created the gap)
   const int entryBarShift = formationShift + 1; 
   if(entryBarShift >= iBars(_Symbol, InputM2NarrativeTimeframe))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "FVG middle pattern bar unavailable");
      return false;
   }

   bool   useMarketOrder  = false;
   double entryPrice      = 0.0;
   double stopLossOverall = 0.0;
   string entryFailReason = "";

   // Rely entirely on the unified TouchVol offset logic (3.0% offset, 2.0% SL buffer)
   if(!ResolveTouchLegVolumeBarEntryAndSl(isBullishFairValueGap, entryBarShift, 0, huntIndex,
                                          useMarketOrder, entryPrice, stopLossOverall,
                                          entryFailReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("FVG entry/SL via TouchVol invalid sh=%d buy=%s Ã¢â‚¬â€ %s",
                                  entryBarShift, isBullishFairValueGap ? "Y" : "N",
                                  entryFailReason));
      return false;
   }

   double normalizedEntry = NormalizeDouble(entryPrice, _Digits);
   const bool isBuy       = isBullishFairValueGap;
   const double stopEntry = useMarketOrder
                            ? normalizedEntry
                            : M2PendingStopEntryPrice(isBuy, normalizedEntry);
   if(stopEntry <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "stop entry invalid");
      return false;
   }

   if(isBuy && stopEntry <= stopLossOverall)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("buy stop entry<=SL entry=%.5f sl=%.5f", stopEntry, stopLossOverall));
      return false;
   }
   if(!isBuy && stopEntry >= stopLossOverall)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("sell stop entry>=SL entry=%.5f sl=%.5f", stopEntry, stopLossOverall));
      return false;
   }

   const double takeProfit =
      ComputeRewardRiskTakeProfitPrice(isBuy, stopEntry, stopLossOverall);
   if(takeProfit <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("fixed R:R TP invalid entry=%.5f sl=%.5f", stopEntry,
                                  stopLossOverall));
      return false;
   }

   if(!StopsDistanceAllowed(isBuy, stopEntry, stopLossOverall, takeProfit))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "broker stops level tp");
      return false;
   }

   if(LQ_RISK_USD_PER_TRADE <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "LQ_RISK_USD_PER_TRADE invalid");
      return false;
   }

   const string huntCommentPrefix = V2HuntTradeCommentPrefix(huntSessionId);
   const string formationTag      = IntegerToString((long)formationTime);
   int          placedCount       = 0;
   int          zeroVolumeCount   = 0;

   const string tpLog = StringFormat("%.5f (1:%.1f)", takeProfit, LQ_REWARD_RISK_RATIO);

   const string logDetail = StringFormat(
      "%s ref=%.5f stopEntry=%.5f sl=%.5f (FVG 1st-bar sh=%d offset=%.1f%%) tp=%s stop=+%dpt",
      isBuy ? "bull" : "bear", normalizedEntry, stopEntry, stopLossOverall, entryBarShift,
      InputTouchVolEntryOffsetPercentChart, tpLog, InputPendingStopEntryOffsetPoints);

   string tradeBlockReason = "";
   if(!IsFvgAutomatedTradingAllowed(tradeBlockReason))
   {
      LogHuntEvent("TRADE_PLAN", logDetail + " | " + tradeBlockReason);
      return false;
   }

   TryPlaceSingleRewardRiskTradeOrder(isBuy, useMarketOrder, normalizedEntry, stopLossOverall,
                                       huntCommentPrefix, formationTag, false,
                                       placedCount, zeroVolumeCount);

   const int orderTargetCount = 1;
   if(placedCount > 0)
   {
      RegisterHuntTradeAfterSuccessfulPlace(isBuy, stopEntry, takeProfit,
                                            takeProfit, formationTime, huntSessionId);
      LogHuntEvent("TRADE_PLACE",
                   StringFormat("%s placed=%d/%d replace=%s %s", formationTag, placedCount,
                                orderTargetCount, replacePendingOnly ? "Y" : "N", logDetail));
      return true;
   }

   V2LogHuntEvent(huntIndex, "TRADE_FAIL",
                  StringFormat("%s zeroVol=%d %s", formationTag, zeroVolumeCount, logDetail));
   return false;
}

//+------------------------------------------------------------------+
bool TryPlaceEngulfAbsorptionTradeSetup(const int huntIndex, const bool isBuy,
                                         const double entryPrice, const double stopLossPrice,
                                         const datetime signalBarOpenTime,
                                         const datetime huntSessionId)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || signalBarOpenTime == 0)
   {
      if(huntIndex >= 0)
         V2LogHuntEvent(huntIndex, "TRADE_SKIP", "signalBarOpenTime=0");
      return false;
   }

   if(V2IsHuntSessionStillActive(huntSessionId))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt still ON Ã¢â‚¬â€ orders after engulf signal");
      return false;
   }

   string bosBiasBlockReason = "";
   if(!FvgTradeAllowedByM15BosBias(isBuy, bosBiasBlockReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", bosBiasBlockReason);
      return false;
   }

   bool replacePendingOnly = false;
   if(!ResolveHuntFvgOrderPlacementGate(signalBarOpenTime, huntSessionId, replacePendingOnly))
      return false;

   const double normalizedEntry = NormalizeDouble(entryPrice, _Digits);
   double stopLoss = NormalizeDouble(stopLossPrice, _Digits);
   const double stopEntry = M2PendingStopEntryPrice(isBuy, normalizedEntry);
   if(stopEntry <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "stop entry invalid");
      return false;
   }

   if(!ApplyTouchVolMinimumSlDistance(isBuy, stopEntry, stopLoss))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "engulf SL distance invalid");
      return false;
   }

   if(isBuy && stopEntry <= stopLoss)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("buy stop entry<=SL entry=%.5f sl=%.5f", stopEntry, stopLoss));
      return false;
   }
   if(!isBuy && stopEntry >= stopLoss)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("sell stop entry>=SL entry=%.5f sl=%.5f", stopEntry, stopLoss));
      return false;
   }

   const double takeProfit =
      ComputeRewardRiskTakeProfitPrice(isBuy, stopEntry, stopLoss);
   if(takeProfit <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("fixed R:R TP invalid entry=%.5f sl=%.5f", stopEntry, stopLoss));
      return false;
   }

   if(!StopsDistanceAllowed(isBuy, stopEntry, stopLoss, takeProfit))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "broker stops level tp");
      return false;
   }

   if(LQ_RISK_USD_PER_TRADE <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "LQ_RISK_USD_PER_TRADE invalid");
      return false;
   }

   const string huntCommentPrefix = V2HuntTradeCommentPrefix(huntSessionId);
   const string formationTag      = TimeToString(signalBarOpenTime, TIME_DATE | TIME_MINUTES);
   const string logDetail =
      StringFormat("buy=%s ref=%.5f stopEntry=%.5f sl=%.5f tp=%.5f (1:%.1f) signal=%s stop=+%dpt",
                   isBuy ? "Y" : "N", normalizedEntry, stopEntry, stopLoss, takeProfit,
                   LQ_REWARD_RISK_RATIO, formationTag, InputPendingStopEntryOffsetPoints);

   string tradeBlockReason = "";
   if(!IsFvgAutomatedTradingAllowed(tradeBlockReason))
   {
      LogHuntEvent("TRADE_PLAN", logDetail + " | " + tradeBlockReason);
      return false;
   }

   int placedCount    = 0;
   int zeroVolumeCount = 0;

   TryPlaceSingleRewardRiskTradeOrder(isBuy, false, normalizedEntry, stopLoss,
                                       huntCommentPrefix, formationTag, true,
                                       placedCount, zeroVolumeCount);

   const int orderTargetCount = 1;
   if(placedCount > 0)
   {
      RegisterHuntTradeAfterSuccessfulPlace(isBuy, stopEntry, takeProfit,
                                            takeProfit, signalBarOpenTime, huntSessionId);
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
   g_v2Hunts[huntIndex].h4BreachVolumeBarOpenTime    = 0;
   g_v2Hunts[huntIndex].h4BreachSwingDirection       = 0;
   g_v2Hunts[huntIndex].h4BreachLqType              = LQ_EXTERNAL_TOP;
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
void V2ResetHuntSlotSessionCounters(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked = 0.0;
   g_v2Hunts[huntIndex].tradeOrdersActive     = false;
   g_v2Hunts[huntIndex].ordersFvgFormationTime = 0;
   g_v2Hunts[huntIndex].tradeIsBuy            = false;
   g_v2Hunts[huntIndex].tradeEntryPrice       = 0.0;
   g_v2Hunts[huntIndex].tradeTp1Price         = 0.0;
   g_v2Hunts[huntIndex].preEntryCancelTpLevel = 0.0;
   g_v2Hunts[huntIndex].firstOppBosMgmtDone     = false;
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
int V2FindActiveHuntByM15Leg(const datetime legEndTime, const bool h4HighBreached)
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

   V2ClearImpulseBufferZone(huntIndex);
   V3ClearEngulfVolSpikeBufferDraw(huntIndex);
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
string V2ImpulseObjectName(const datetime sessionId)
{
   return LQ_OBJ_IMPULSE_PREFIX + V2HuntObjectSuffix(sessionId);
}

//+------------------------------------------------------------------+
string V3EngulfVolSpikeRectObjectName(const datetime sessionId)
{
   return LQ_OBJ_ENGULF_VOL_SPIKE_PREFIX + V2HuntObjectSuffix(sessionId);
}

//+------------------------------------------------------------------+
string V3EngulfVolSpikeArrivalObjectName(const datetime sessionId)
{
   return LQ_OBJ_ENGULF_VOL_ARRIVAL_PREFIX + V2HuntObjectSuffix(sessionId);
}

//+------------------------------------------------------------------+
void V3ClearEngulfVolSpikeBufferDraw(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   if(g_v2Hunts[huntIndex].sessionId != 0)
   {
      ObjectDelete(0, V3EngulfVolSpikeRectObjectName(g_v2Hunts[huntIndex].sessionId));
      ObjectDelete(0, V3EngulfVolSpikeArrivalObjectName(g_v2Hunts[huntIndex].sessionId));
   }
}

//+------------------------------------------------------------------+
struct V3EngulfVolSpikeContext
{
   double   zoneLow;
   double   zoneHigh;
   datetime lookbackStartOpen;
   datetime windowEndOpen;
   datetime firstArrivalOpen;
   bool     hasZone;
   bool     hasLookback;
   bool     hasFirstArrival;
};

//+------------------------------------------------------------------+
void V2LogHuntEvent(const int huntIndex, const string eventName, const string detail = "")
{
   if(!M15LqLoggingEnabled())
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
//| Green breach -> bull hunt/engulf; pink breach -> bear hunt/engulf.  |
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
void V2EndOppositeFvgHuntSession(const int huntIndex, const string offReason,
                                  const bool tryPlaceTradeAfterOff)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   const string reason = (StringLen(offReason) > 0 ? offReason : "unspecified");
   V2LogHuntEvent(huntIndex, "HUNT_OFF",
                  StringFormat("%s | HS%lld hunt=%s",
                               reason,
                               (long)g_v2Hunts[huntIndex].sessionId,
                               g_v2Hunts[huntIndex].h4HighWasBreached ? "bull/buy" : "bear/sell"));

   g_v2Hunts[huntIndex].active = false;
   V2ClearImpulseBufferZone(huntIndex);
   V3ClearEngulfVolSpikeBufferDraw(huntIndex);
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
   if(!M15LqChartDrawEnabled(InputDrawImpulseCancelBufferZone) || !g_v2Hunts[huntIndex].active)
   {
      V2ClearImpulseBufferZone(huntIndex);
      return;
   }

   double zoneLow = 0.0;
   double zoneHigh = 0.0;
   double cancelLimitPrice = 0.0;
   if(!M15BreachImpulseCancelZonePrices(V2HuntExpectsBullishFvg(huntIndex),
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
int V2OppositeM15LegDirectionForHunt(const int huntIndex)
{
   return g_v2Hunts[huntIndex].h4HighWasBreached ? -1 : 1;
}

//+------------------------------------------------------------------+
void V2OnM15LegClosedForHunts(const int closedLegDirection, const datetime closedLegEndTime)
{
   // v3: no touch-level hunt cancel on opposite H4 leg close
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
//| v3 â€” Engulfing Volume Absorption model                             |
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
bool M2BarRangeOverlapsPriceZone(const int barShift, const double zoneLow, const double zoneHigh)
{
   if(barShift < 0 || zoneLow <= 0.0 || zoneHigh <= 0.0 || zoneHigh < zoneLow)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const double barLow  = iLow(_Symbol, timeframe, barShift);
   const double barHigh = iHigh(_Symbol, timeframe, barShift);
   if(barLow <= 0.0 || barHigh <= 0.0)
      return false;

   return barLow <= zoneHigh && barHigh >= zoneLow;
}

//+------------------------------------------------------------------+
double M2AvgTickVolumeBeforeBar(const int barShift, const int maxBarCount,
                                   const datetime limitOlderOpenTime = 0)
{
   if(barShift < 1 || maxBarCount < 1)
      return 0.0;

   long   totalVol = 0;
   int    validBars = 0;
   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);

   for(int shift = barShift + 1; shift <= barShift + maxBarCount; shift++)
   {
      if(shift >= barsTotal)
         break;

      const datetime barOpen = iTime(_Symbol, timeframe, shift);
      if(barOpen == 0)
         continue;

      if(limitOlderOpenTime > 0 && barOpen < limitOlderOpenTime)
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
datetime V3GetHuntBreachVolumeBarTime(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return 0;

   return g_v2Hunts[huntIndex].h4BreachVolumeBarOpenTime;
}

//+------------------------------------------------------------------+
bool V3TryBuildEngulfVolSpikeContext(const int huntIndex, const bool isBuy,
                                      const int candle1Shift, const int candle2Shift,
                                      V3EngulfVolSpikeContext &outCtx)
{
   outCtx.zoneLow             = 0.0;
   outCtx.zoneHigh            = 0.0;
   outCtx.lookbackStartOpen   = 0;
   outCtx.windowEndOpen       = 0;
   outCtx.firstArrivalOpen    = 0;
   outCtx.hasZone             = false;
   outCtx.hasLookback         = false;
   outCtx.hasFirstArrival     = false;

   if(candle1Shift < 1 || candle2Shift < 1)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(candle2Shift, InputChartRangeBarCount);
   if(chartHeight <= 0.0)
      return false;

   const double bufferPrice = chartHeight * (InputEngulfVolBufferPercentChart / 100.0);
   if(bufferPrice <= 0.0)
      return false;

   int anchorLegDir = 0;
   if(isBuy)
   {
      const double pairLow = MathMin(iLow(_Symbol, timeframe, candle1Shift),
                                     iLow(_Symbol, timeframe, candle2Shift));
      if(pairLow <= 0.0)
         return false;
      outCtx.zoneLow      = pairLow;
      outCtx.zoneHigh     = pairLow + bufferPrice;
      anchorLegDir        = -1;
   }
   else
   {
      const double pairHigh = MathMax(iHigh(_Symbol, timeframe, candle1Shift),
                                      iHigh(_Symbol, timeframe, candle2Shift));
      if(pairHigh <= 0.0)
         return false;
      outCtx.zoneHigh     = pairHigh;
      outCtx.zoneLow      = pairHigh - bufferPrice;
      anchorLegDir        = 1;
   }
   outCtx.hasZone       = true;
   outCtx.windowEndOpen = iTime(_Symbol, timeframe, candle2Shift);

   double legLow = 0.0;
   double legHigh = 0.0;
   datetime legStartTime = 0;
   datetime legEndTime = 0;
   if(!V2TryGetLastCompletedM2Leg(anchorLegDir, legLow, legHigh, legStartTime, legEndTime))
      return outCtx.hasZone;

   outCtx.lookbackStartOpen = legStartTime;
   outCtx.hasLookback       = (legStartTime > 0);

   int shiftOlder = iBarShift(_Symbol, timeframe, legStartTime, true);
   int shiftNewer = candle2Shift;
   if(shiftOlder < 0)
      return outCtx.hasZone;
   if(shiftNewer < 1)
      shiftNewer = 1;
   if(shiftOlder < shiftNewer)
   {
      const int tmp = shiftOlder;
      shiftOlder = shiftNewer;
      shiftNewer = tmp;
   }

   datetime arrivalMinOpen = 0;
   if(huntIndex >= 0 && huntIndex < V2_MAX_HUNT_SESSIONS)
   {
      const datetime timeT1 = V3GetHuntBreachVolumeBarTime(huntIndex);
      const int m2Sec = (int)PeriodSeconds(timeframe);
      if(timeT1 > 0 && m2Sec > 0)
         arrivalMinOpen = timeT1 + (datetime)(2 * m2Sec);
   }

   for(int shift = shiftOlder; shift >= shiftNewer; shift--)
   {
      const datetime barOpen = iTime(_Symbol, timeframe, shift);
      if(barOpen == 0)
         continue;
      if(arrivalMinOpen > 0 && barOpen < arrivalMinOpen)
         continue;

      if(!M2BarRangeOverlapsPriceZone(shift, outCtx.zoneLow, outCtx.zoneHigh))
         continue;
      outCtx.firstArrivalOpen = barOpen;
      outCtx.hasFirstArrival  = true;
      break;
   }

   return outCtx.hasZone;
}

//+------------------------------------------------------------------+
void V3UpdateEngulfVolSpikeBufferDraw(const int huntIndex, const bool isBuy,
                                       const V3EngulfVolSpikeContext &ctx)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;

   if(!M15LqChartDrawEnabled(InputDrawEngulfVolSpikeBufferZone) || !g_v2Hunts[huntIndex].active ||
      !ctx.hasZone || g_v2Hunts[huntIndex].sessionId == 0)
   {
      V3ClearEngulfVolSpikeBufferDraw(huntIndex);
      return;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   datetime timeLeft = ctx.hasLookback ? ctx.lookbackStartOpen : g_v2Hunts[huntIndex].sessionId;
   if(timeLeft == 0)
      timeLeft = g_v2Hunts[huntIndex].sessionId;

   datetime timeRight = iTime(_Symbol, timeframe, 0);
   if(timeRight == 0 && ctx.windowEndOpen > 0)
   {
      const int m2Sec = (int)PeriodSeconds(timeframe);
      if(m2Sec > 0)
         timeRight = ctx.windowEndOpen + (datetime)m2Sec;
   }
   if(timeRight <= timeLeft)
      timeRight = timeLeft + (datetime)PeriodSeconds(timeframe);

   const color zoneColor = isBuy ? InputEngulfVolSpikeBufferColorBull
                                 : InputEngulfVolSpikeBufferColorBear;
   const string rectName = V3EngulfVolSpikeRectObjectName(g_v2Hunts[huntIndex].sessionId);
   if(ObjectFind(0, rectName) < 0)
   {
      if(!ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, timeLeft, ctx.zoneHigh, timeRight, ctx.zoneLow))
         return;
   }
   else
   {
      ObjectSetInteger(0, rectName, OBJPROP_TIME, 0, timeLeft);
      ObjectSetDouble(0, rectName, OBJPROP_PRICE, 0, ctx.zoneHigh);
      ObjectSetInteger(0, rectName, OBJPROP_TIME, 1, timeRight);
      ObjectSetDouble(0, rectName, OBJPROP_PRICE, 1, ctx.zoneLow);
   }
   ObjectSetInteger(0, rectName, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, rectName, OBJPROP_BGCOLOR, (color)ColorToARGB(zoneColor, 48));
   ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
   ObjectSetInteger(0, rectName, OBJPROP_BACK, false);
   ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, rectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetInteger(0, rectName, OBJPROP_ZORDER, 64);

   const string arrivalName = V3EngulfVolSpikeArrivalObjectName(g_v2Hunts[huntIndex].sessionId);
   if(ctx.hasFirstArrival)
   {
      if(ObjectFind(0, arrivalName) < 0)
      {
         if(!ObjectCreate(0, arrivalName, OBJ_VLINE, 0, ctx.firstArrivalOpen, 0.0))
            return;
      }
      else
         ObjectSetInteger(0, arrivalName, OBJPROP_TIME, 0, ctx.firstArrivalOpen);

      ObjectSetInteger(0, arrivalName, OBJPROP_COLOR, InputEngulfVolSpikeArrivalColor);
      ObjectSetInteger(0, arrivalName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, arrivalName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, arrivalName, OBJPROP_BACK, false);
      ObjectSetInteger(0, arrivalName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, arrivalName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, arrivalName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      ObjectSetInteger(0, arrivalName, OBJPROP_ZORDER, 65);
   }
   else
      ObjectDelete(0, arrivalName);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void V3RefreshEngulfVolSpikeBufferDraw(const int huntIndex, const bool isBuy,
                                          const int candle1Shift, const int candle2Shift)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   V3EngulfVolSpikeContext ctx;
   if(!V3TryBuildEngulfVolSpikeContext(huntIndex, isBuy, candle1Shift, candle2Shift, ctx))
   {
      V3ClearEngulfVolSpikeBufferDraw(huntIndex);
      return;
   }

   V3UpdateEngulfVolSpikeBufferDraw(huntIndex, isBuy, ctx);
}

//+------------------------------------------------------------------+
bool V3EngulfVolumeSpikeValid(const int huntIndex, const bool isBuy, const int candle1Shift,
                               const int candle2Shift, string &outDetail)
{
   outDetail = "";
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
   {
      outDetail = "invalid hunt index for vol spike check";
      return false;
   }

   V3EngulfVolSpikeContext ctx;
   if(!V3TryBuildEngulfVolSpikeContext(huntIndex, isBuy, candle1Shift, candle2Shift, ctx))
   {
      outDetail = "spike context unavailable";
      return false;
   }

   if(!ctx.hasLookback)
   {
      outDetail = StringFormat("no completed %s leg for lookback",
                               isBuy ? "down" : "up");
      return false;
   }

   if(!ctx.hasFirstArrival)
   {
      const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
      const datetime timeT1 = V3GetHuntBreachVolumeBarTime(huntIndex);
      const int m2Sec = (int)PeriodSeconds(timeframe);
      const datetime searchFrom = (timeT1 > 0 && m2Sec > 0) ? timeT1 + (datetime)(2 * m2Sec) : 0;
      outDetail = StringFormat("no buffer touch zone=%.5f..%.5f legStart=%s",
                               ctx.zoneLow, ctx.zoneHigh,
                               TimeToString(ctx.lookbackStartOpen, TIME_DATE | TIME_MINUTES));
      V2LogHuntEvent(huntIndex, "ENGULF_ARRIVAL",
                     StringFormat("none zone=%.5f..%.5f searchFrom=%s T1=%s %s",
                                  ctx.zoneLow, ctx.zoneHigh,
                                  TimeToString(searchFrom, TIME_DATE | TIME_MINUTES),
                                  TimeToString(timeT1, TIME_DATE | TIME_MINUTES),
                                  outDetail));
      return false;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int arrivalShift = iBarShift(_Symbol, timeframe, ctx.firstArrivalOpen, true);
   if(arrivalShift < 0)
   {
      outDetail = "arrival bar unavailable";
      V2LogHuntEvent(huntIndex, "ENGULF_ARRIVAL",
                     StringFormat("open=%s shift lookup failed",
                                  TimeToString(ctx.firstArrivalOpen, TIME_DATE | TIME_MINUTES)));
      return false;
   }

   const long arrivalVol = iTickVolume(_Symbol, timeframe, arrivalShift);
   if(arrivalVol < 0)
   {
      outDetail = "arrival bar volume unavailable";
      V2LogHuntEvent(huntIndex, "ENGULF_ARRIVAL",
                     StringFormat("sh=%d open=%s vol unavailable",
                                  arrivalShift,
                                  TimeToString(ctx.firstArrivalOpen, TIME_DATE | TIME_MINUTES)));
      return false;
   }

   const datetime timeT1 = V3GetHuntBreachVolumeBarTime(huntIndex);
   const datetime timeT2 = iTime(_Symbol, timeframe, candle2Shift);
   const int m2Sec = (int)PeriodSeconds(timeframe);
   const datetime searchFrom = (timeT1 > 0 && m2Sec > 0) ? timeT1 + (datetime)(2 * m2Sec) : 0;
   const double arrivalOpen  = iOpen(_Symbol, timeframe, arrivalShift);
   const double arrivalHigh  = iHigh(_Symbol, timeframe, arrivalShift);
   const double arrivalLow   = iLow(_Symbol, timeframe, arrivalShift);
   const double arrivalClose = iClose(_Symbol, timeframe, arrivalShift);

   V2LogHuntEvent(huntIndex, "ENGULF_ARRIVAL",
                  StringFormat("sh=%d open=%s vol=%lld O=%.5f H=%.5f L=%.5f C=%.5f searchFrom=%s T1=%s",
                               arrivalShift,
                               TimeToString(ctx.firstArrivalOpen, TIME_DATE | TIME_MINUTES),
                               (long)arrivalVol, arrivalOpen, arrivalHigh, arrivalLow, arrivalClose,
                               TimeToString(searchFrom, TIME_DATE | TIME_MINUTES),
                               TimeToString(timeT1, TIME_DATE | TIME_MINUTES)));

   const double baselineAvg =
      M2AvgTickVolumeBeforeBar(arrivalShift, InputEngulfVolMaxBaselineBars, timeT1);
   if(baselineAvg <= 0.0)
   {
      outDetail = StringFormat("baseline unavailable arrivalSh=%d open=%s T1=%s T2=%s",
                               arrivalShift,
                               TimeToString(ctx.firstArrivalOpen, TIME_DATE | TIME_MINUTES),
                               TimeToString(timeT1, TIME_DATE | TIME_MINUTES),
                               TimeToString(timeT2, TIME_DATE | TIME_MINUTES));
      return false;
   }

   outDetail = StringFormat("arrivalSh=%d open=%s vol=%lld baseline=%.0f T1=%s T2=%s zone=%.5f..%.5f",
                            arrivalShift,
                            TimeToString(ctx.firstArrivalOpen, TIME_DATE | TIME_MINUTES),
                            (long)arrivalVol, baselineAvg,
                            TimeToString(timeT1, TIME_DATE | TIME_MINUTES),
                            TimeToString(timeT2, TIME_DATE | TIME_MINUTES),
                            ctx.zoneLow, ctx.zoneHigh);

   return (double)arrivalVol > baselineAvg;
}

//+------------------------------------------------------------------+
bool V3ComputeEngulfStopLoss(const bool isBuy, const int candle1Shift, const int candle2Shift,
                              double &outStopLoss)
{
   outStopLoss = 0.0;
   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const double bufferPrice = M2EngulfSlBufferPrice(candle2Shift);

   if(isBuy)
   {
      const double low1 = iLow(_Symbol, timeframe, candle1Shift);
      const double low2 = iLow(_Symbol, timeframe, candle2Shift);
      outStopLoss = MathMin(low1, low2) - bufferPrice;
   }
   else
   {
      const double high1 = iHigh(_Symbol, timeframe, candle1Shift);
      const double high2 = iHigh(_Symbol, timeframe, candle2Shift);
      outStopLoss = MathMax(high1, high2) + bufferPrice;
   }

   return outStopLoss > 0.0;
}

//+------------------------------------------------------------------+
//| Bull engulf: pair low must be the hunt-path low since HUNT_ON.     |
//| Bear engulf: pair high must be the hunt-path high since HUNT_ON.   |
//+------------------------------------------------------------------+
bool V3EngulfPairIsHuntPathExtreme(const int huntIndex, const bool isBuy, const double pairExtreme,
                                    string &outDetail)
{
   outDetail = "";
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || pairExtreme <= 0.0)
      return false;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps = (pointSize > 0.0 ? pointSize * 0.5 : 0.00001);

   if(isBuy)
   {
      const double pathMinLow = g_v2Hunts[huntIndex].pathMinLowSinceH4Breach;
      if(pathMinLow <= 0.0)
      {
         outDetail = "hunt path min low unavailable";
         return false;
      }
      if(pathMinLow < pairExtreme - eps)
      {
         outDetail = StringFormat("pair low %.5f not hunt low â€” pathMin=%.5f since HS%lld",
                                  pairExtreme, pathMinLow,
                                  (long)g_v2Hunts[huntIndex].sessionId);
         return false;
      }
      return true;
   }

   const double pathMaxHigh = g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach;
   if(pathMaxHigh <= 0.0)
   {
      outDetail = "hunt path max high unavailable";
      return false;
   }
   if(pathMaxHigh > pairExtreme + eps)
   {
      outDetail = StringFormat("pair high %.5f not hunt high â€” pathMax=%.5f since HS%lld",
                               pairExtreme, pathMaxHigh,
                               (long)g_v2Hunts[huntIndex].sessionId);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void V3TryScanEngulfAbsorptionOnM2Close(const int huntIndex, const double barClose)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS || !g_v2Hunts[huntIndex].active)
      return;

   const bool isBuy = V2HuntExpectsBullishFvg(huntIndex);
   const int  c1Shift = 2;
   const int  c2Shift = 1;

   V3RefreshEngulfVolSpikeBufferDraw(huntIndex, isBuy, c1Shift, c2Shift);

   const bool engulfOk = isBuy
                         ? V3DetectBullishEngulfFootprint(c1Shift, c2Shift)
                         : V3DetectBearishEngulfFootprint(c1Shift, c2Shift);
   if(!engulfOk)
   {
      const datetime closedBarOpen = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
      if(g_v2Hunts[huntIndex].sessionId == closedBarOpen)
      {
         const double c1Open = iOpen(_Symbol, InputM2NarrativeTimeframe, c1Shift);
         const double c2Close = iClose(_Symbol, InputM2NarrativeTimeframe, c2Shift);
         V2LogHuntEvent(huntIndex, "ENGULF_SCAN",
                        StringFormat("no %s footprint on HUNT_ON bar c1Open=%.5f c2Close=%.5f c1%s c2%s",
                                     isBuy ? "bull" : "bear", c1Open, c2Close,
                                     isBuy
                                        ? (M2BarIsBearishAtShift(c1Shift) ? "Bear" : "NotBear")
                                        : (M2BarIsBullishAtShift(c1Shift) ? "Bull" : "NotBull"),
                                     isBuy
                                        ? (M2BarIsBullishAtShift(c2Shift) ? "Bull" : "NotBull")
                                        : (M2BarIsBearishAtShift(c2Shift) ? "Bear" : "NotBear")));
      }
      return;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const double pairExtreme = isBuy
                              ? MathMin(iLow(_Symbol, timeframe, c1Shift), iLow(_Symbol, timeframe, c2Shift))
                              : MathMax(iHigh(_Symbol, timeframe, c1Shift), iHigh(_Symbol, timeframe, c2Shift));

   string pathExtremeDetail = "";
   if(!V3EngulfPairIsHuntPathExtreme(huntIndex, isBuy, pairExtreme, pathExtremeDetail))
   {
      V2LogHuntEvent(huntIndex, "ENGULF_SKIP", pathExtremeDetail);
      return;
   }

   if(g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked > 0.0)
   {
      if(isBuy && pairExtreme > g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked)
      {
         V2LogHuntEvent(huntIndex, "ENGULF_SKIP",
                        StringFormat("pair low %.5f > prev %.5f", pairExtreme,
                                     g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked));
         g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked = pairExtreme;
         return;
      }
      if(!isBuy && pairExtreme < g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked)
      {
         V2LogHuntEvent(huntIndex, "ENGULF_SKIP",
                        StringFormat("pair high %.5f < prev %.5f", pairExtreme,
                                     g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked));
         g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked = pairExtreme;
         return;
      }
   }
   g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked = pairExtreme;

   string volSpikeDetail = "";
   if(!V3EngulfVolumeSpikeValid(huntIndex, isBuy, c1Shift, c2Shift, volSpikeDetail))
   {
      V2LogHuntEvent(huntIndex, "ENGULF_SKIP",
                     StringFormat("vol spike fail â€” %s", volSpikeDetail));
      return;
   }

   double stopLoss = 0.0;
   if(!V3ComputeEngulfStopLoss(isBuy, c1Shift, c2Shift, stopLoss))
   {
      V2LogHuntEvent(huntIndex, "ENGULF_SKIP", "SL compute failed");
      return;
   }

   const datetime signalBarOpen = iTime(_Symbol, timeframe, c2Shift);
   const datetime sessionId     = g_v2Hunts[huntIndex].sessionId;
   const double   entryPrice    = barClose;

   V2LogHuntEvent(huntIndex, "ENGULF_SIGNAL",
                  StringFormat("%s entry=%.5f sl=%.5f bar=%s | %s",
                               isBuy ? "bull" : "bear", entryPrice, stopLoss,
                               TimeToString(signalBarOpen, TIME_DATE | TIME_MINUTES),
                               volSpikeDetail));

   V2EndOppositeFvgHuntSession(huntIndex,
                                 StringFormat("engulf absorption lvl=%.5f", pairExtreme),
                                 false);
   TryPlaceEngulfAbsorptionTradeSetup(huntIndex, isBuy, entryPrice, stopLoss,
                                       signalBarOpen, sessionId);
}

//+------------------------------------------------------------------+
int V2ArmOppositeFvgHuntAfterM15Breach(const double h4Level, const bool h4HighBreached,
                                         const datetime breachedLegEndTime,
                                         const int swingDirection, const ENUM_LIQUIDITY_TYPE lqType,
                                         const datetime breachedVolumeBarOpenTime,
                                         const double barClose, const double barLow,
                                         const double barHigh)
{
   const int existing = V2FindActiveHuntByM15Leg(breachedLegEndTime, h4HighBreached);
   if(existing >= 0)
      return existing;

   const int huntIndex = V2AllocHuntSlot();
   if(huntIndex < 0)
      return -1;

   {
      const double pointSizeMatch = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      const double epsMatch = (pointSizeMatch > 0.0 ? pointSizeMatch : 0.00001);
      for(int breachIndex = 0; breachIndex < g_m15LegVolumeBreachCount; breachIndex++)
      {
         if(g_m15LegVolumeBreaches[breachIndex].swingDirection != swingDirection ||
            g_m15LegVolumeBreaches[breachIndex].lqType != lqType)
            continue;
         if(breachedLegEndTime != 0 && breachedLegEndTime != g_m15LegVolumeBreaches[breachIndex].legStartTime &&
            breachedLegEndTime != g_m15LegVolumeBreaches[breachIndex].legEndTime)
            continue;
         if(MathAbs(g_m15LegVolumeBreaches[breachIndex].breachLevelPrice - h4Level) > epsMatch)
            continue;
         g_m15LegVolumeBreaches[breachIndex].huntArmed = true;
         g_m15LegVolumeBreaches[breachIndex].swept     = true;
      }
   }

   g_v2Hunts[huntIndex].active                         = true;
   g_v2Hunts[huntIndex].h4HighWasBreached             = M15LqTypeExpectsBullishHunt(lqType);
   g_v2Hunts[huntIndex].h4BreachedLegLevelPrice       = h4Level;
   g_v2Hunts[huntIndex].h4BreachedLegEndTime          = breachedLegEndTime;
   g_v2Hunts[huntIndex].h4BreachSwingDirection        = swingDirection;
   g_v2Hunts[huntIndex].h4BreachLqType               = lqType;
   g_v2Hunts[huntIndex].h4BreachVolumeBarOpenTime = breachedVolumeBarOpenTime;
   g_v2Hunts[huntIndex].closeWhenH4LiquidityBreached  = barClose;
   g_v2Hunts[huntIndex].pathMinLowSinceH4Breach       = barLow;
   g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach      = barHigh;
   const double huntOnPrevLow  = iLow(_Symbol, InputM2NarrativeTimeframe, 2);
   const double huntOnPrevHigh = iHigh(_Symbol, InputM2NarrativeTimeframe, 2);
   if(huntOnPrevLow > 0.0)
      g_v2Hunts[huntIndex].pathMinLowSinceH4Breach =
         MathMin(g_v2Hunts[huntIndex].pathMinLowSinceH4Breach, huntOnPrevLow);
   if(huntOnPrevHigh > 0.0)
      g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach =
         MathMax(g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach, huntOnPrevHigh);
   g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach = barClose;
   g_v2Hunts[huntIndex].sessionId                      = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   V2ResetHuntSlotSessionCounters(huntIndex);

   const bool huntIsBull = M15LqTypeExpectsBullishHunt(lqType);
   if(huntIsBull)
   {
      double bandLow = 0.0;
      double bandHigh = 0.0;
      M15BreachBufferBandForDownLegLow(h4Level, bandLow, bandHigh);
      V2LogHuntEvent(huntIndex, "HUNT_ON",
                     StringFormat("green lvl=%.5f band %.5f..%.5f leg=%s lq=%d T1=%s",
                                  h4Level, bandLow, bandHigh,
                                  TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES),
                                  (int)lqType,
                                  TimeToString(g_v2Hunts[huntIndex].h4BreachVolumeBarOpenTime,
                                               TIME_DATE | TIME_MINUTES)));
   }
   else
   {
      double bandLow = 0.0;
      double bandHigh = 0.0;
      M15BreachBufferBandForUpLegHigh(h4Level, bandLow, bandHigh);
      V2LogHuntEvent(huntIndex, "HUNT_ON",
                     StringFormat("pink lvl=%.5f band %.5f..%.5f leg=%s lq=%d T1=%s",
                                  h4Level, bandLow, bandHigh,
                                  TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES),
                                  (int)lqType,
                                  TimeToString(g_v2Hunts[huntIndex].h4BreachVolumeBarOpenTime,
                                               TIME_DATE | TIME_MINUTES)));
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

   g_v2Hunts[huntIndex].pathMinLowSinceH4Breach  =
      MathMin(g_v2Hunts[huntIndex].pathMinLowSinceH4Breach, barLow);
   g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach =
      MathMax(g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach, barHigh);

   const bool isBuy = V2HuntExpectsBullishFvg(huntIndex);
   double sameDirBosLevel = 0.0;
   if(isBuy)
   {
      if(TryDetectM2PriceBreakAboveLatestUpLegHigh(sameDirBosLevel))
      {
         LogHuntEvent("HUNT_CANCEL_BOS",
                      StringFormat("BOS_CANCEL_BULLISH lvl=%.5f session=%s",
                                   sameDirBosLevel,
                                   TimeToString(g_v2Hunts[huntIndex].sessionId, TIME_DATE | TIME_MINUTES)));
         V2EndOppositeFvgHuntSession(huntIndex, "BOS_CANCEL_BULLISH", false);
         return;
      }
   }
   else
   {
      if(TryDetectM2PriceBreakBelowLatestDownLegLow(sameDirBosLevel))
      {
         LogHuntEvent("HUNT_CANCEL_BOS",
                      StringFormat("BOS_CANCEL_BEARISH lvl=%.5f session=%s",
                                   sameDirBosLevel,
                                   TimeToString(g_v2Hunts[huntIndex].sessionId, TIME_DATE | TIME_MINUTES)));
         V2EndOppositeFvgHuntSession(huntIndex, "BOS_CANCEL_BEARISH", false);
         return;
      }
   }

   double impulseZoneLow = 0.0;
   double impulseZoneHigh = 0.0;
   double impulseCancelLimitPrice = 0.0;
   if(M15BreachImpulseCancelZonePrices(V2HuntExpectsBullishFvg(huntIndex),
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
                                                  M15_BREACH_BUFFER_PERCENT_FAR),
                                     false);
         return;
      }
   }

   V3TryScanEngulfAbsorptionOnM2Close(huntIndex, barClose);
}

//+------------------------------------------------------------------+
void OnM2SwingLegDirectionChange(const int closingLegDirection, const int nextLegDirection)
{
   // v3: no touch/recalc-buffer leg hooks
}

//+------------------------------------------------------------------+
bool TryDetectM15WickLiquidityBreachForLeg(const ENUM_LIQUIDITY_TYPE lqType,
                                            const int swingDirection, const double breachLevel,
                                            const datetime huntLegKey, const double barHigh,
                                            const double barLow, const double prevHigh,
                                            const double prevLow, const double pointSize,
                                            double &outLevel, bool &outHighBreached,
                                            datetime &outLegEndTime)
{
   if(swingDirection == 0 || breachLevel <= 0.0 || huntLegKey == 0)
      return false;

   // Hunt polarity follows breach ray color: green=bull, pink=bear.
   const bool huntExpectsBull = M15LqTypeExpectsBullishHunt(lqType);

   switch(lqType)
   {
      case LQ_EXTERNAL_TOP:
         if(!M2WickCrossesAboveLevel(breachLevel, barHigh, prevHigh, pointSize))
            return false;
         return TryAcceptM15BreachForHunt(huntExpectsBull, breachLevel, huntLegKey,
                                         outLevel, outHighBreached, outLegEndTime);

      case LQ_EXTERNAL_BOTTOM:
         if(!M2WickCrossesBelowLevel(breachLevel, barLow, prevLow, pointSize))
            return false;
         return TryAcceptM15BreachForHunt(huntExpectsBull, breachLevel, huntLegKey,
                                         outLevel, outHighBreached, outLegEndTime);

      case LQ_INTERNAL_BULL:
         if(!M2WickCrossesBelowLevel(breachLevel, barLow, prevLow, pointSize))
            return false;
         return TryAcceptM15BreachForHunt(huntExpectsBull, breachLevel, huntLegKey,
                                         outLevel, outHighBreached, outLegEndTime);

      case LQ_INTERNAL_BEAR:
         if(!M2WickCrossesAboveLevel(breachLevel, barHigh, prevHigh, pointSize))
            return false;
         return TryAcceptM15BreachForHunt(huntExpectsBull, breachLevel, huntLegKey,
                                         outLevel, outHighBreached, outLegEndTime);
   }

   return false;
}

//+------------------------------------------------------------------+
bool TryDetectM15WickLiquidityBreachFromRecords(const double barHigh, const double barLow,
                                                 const double prevHigh, const double prevLow,
                                                 const double pointSize, const bool externalOnly,
                                                 double &outLevel, bool &outHighBreached,
                                                 datetime &outLegEndTime,
                                                 ENUM_LIQUIDITY_TYPE &outLqType,
                                                 int &outSwingDirection,
                                                 datetime &outVolumeBarOpenTime)
{
   for(int i = g_m15LegVolumeBreachCount - 1; i >= 0; i--)
   {
      const M15LegVolumeBreachRecord rec = g_m15LegVolumeBreaches[i];
      if(rec.swingDirection == 0 || rec.breachLevelPrice <= 0.0 || rec.huntArmed)
         continue;

      const bool recIsExternal = (rec.lqType == LQ_EXTERNAL_TOP || rec.lqType == LQ_EXTERNAL_BOTTOM);
      if(externalOnly != recIsExternal)
         continue;

      if(rec.legEndTime == 0)
      {
         if(g_m15Swing.currentSwingLeg.legStartTime != rec.legStartTime ||
            g_m15Swing.currentSwingLeg.swingDirection != rec.swingDirection)
            continue;
      }

      if(!M15BreachRecordActiveInBuffer(rec))
         continue;

      const datetime huntLegKey = (rec.legEndTime > 0) ? rec.legEndTime : rec.legStartTime;
      if(TryDetectM15WickLiquidityBreachForLeg(rec.lqType, rec.swingDirection, rec.breachLevelPrice,
                                               huntLegKey, barHigh, barLow, prevHigh, prevLow,
                                               pointSize, outLevel, outHighBreached, outLegEndTime))
      {
         outLqType            = rec.lqType;
         outSwingDirection    = rec.swingDirection;
         outVolumeBarOpenTime = rec.volumeBarOpenTime;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
bool TryDetectM15WickLiquidityBreach(const double barHigh, const double barLow,
                                     const double prevHigh, const double prevLow,
                                     const double pointSize, double &outLevel,
                                     bool &outHighBreached, datetime &outLegEndTime,
                                     ENUM_LIQUIDITY_TYPE &outLqType, int &outSwingDirection,
                                     datetime &outVolumeBarOpenTime)
{
   outLevel              = 0.0;
   outHighBreached       = false;
   outLegEndTime         = 0;
   outLqType             = LQ_EXTERNAL_TOP;
   outSwingDirection     = 0;
   outVolumeBarOpenTime  = 0;

   if(InputM15BreachBufferChartBarCount < 1)
      return false;

   if(TryDetectM15WickLiquidityBreachFromRecords(barHigh, barLow, prevHigh, prevLow, pointSize, true,
                                                 outLevel, outHighBreached, outLegEndTime,
                                                 outLqType, outSwingDirection, outVolumeBarOpenTime))
      return true;

   return TryDetectM15WickLiquidityBreachFromRecords(barHigh, barLow, prevHigh, prevLow, pointSize,
                                                     false, outLevel, outHighBreached, outLegEndTime,
                                                     outLqType, outSwingDirection, outVolumeBarOpenTime);
}

//+------------------------------------------------------------------+
//| Wick-cross breach hunt arm â€” only on closed primary narrative bar. |
//+------------------------------------------------------------------+
void ProcessHuntBreachOnM15BarClose()
{
   if(!InputEnableEngulfHuntAfterM15Breach)
      return;

   const ENUM_TIMEFRAMES h4Tf = InputM15NarrativeTimeframe;
   const double pointSize     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double barClose      = iClose(_Symbol, h4Tf, 1);
   const double barHigh       = iHigh(_Symbol, h4Tf, 1);
   const double barLow        = iLow(_Symbol, h4Tf, 1);
   const double prevHigh      = iHigh(_Symbol, h4Tf, 2);
   const double prevLow       = iLow(_Symbol, h4Tf, 2);

   double h4Level = 0.0;
   bool h4HighBreached = false;
   datetime breachedLegEndTime = 0;
   ENUM_LIQUIDITY_TYPE breachedLqType = LQ_EXTERNAL_TOP;
   int breachedSwingDirection = 0;
   datetime breachedVolumeBarOpenTime = 0;
   if(!TryDetectM15WickLiquidityBreach(barHigh, barLow, prevHigh, prevLow, pointSize,
                                       h4Level, h4HighBreached, breachedLegEndTime,
                                       breachedLqType, breachedSwingDirection,
                                       breachedVolumeBarOpenTime))
      return;

   const int sameLegHunt = V2FindActiveHuntByM15Leg(breachedLegEndTime, h4HighBreached);
   if(sameLegHunt >= 0)
      return;

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

   V2ArmOppositeFvgHuntAfterM15Breach(h4Level, h4HighBreached, breachedLegEndTime,
                                        breachedSwingDirection, breachedLqType,
                                        breachedVolumeBarOpenTime,
                                        barClose, barLow, barHigh);
}

//+------------------------------------------------------------------+
void ProcessHuntEngulfingOnM2BarClose()
{
   if(!InputEnableEngulfHuntAfterM15Breach)
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

   V2UpdateAllImpulseBufferZones();
}

//+------------------------------------------------------------------+
