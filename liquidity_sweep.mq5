//+------------------------------------------------------------------+
//| liquidity_sweep.mq5                                             |
//| M15 swing legs + pool (from plot_swing_m2_copy); M2 swing legs   |
//| (ProcessSwingStepAtShift, live leg, SwingClose) from             |
//| plot_swing_h1_m5_copy.mq5.                                       |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.52"

#include <Trade\Trade.mqh>

input bool   InputSwitchChartToM15       = true;
input int    InputWarmupBars             = 500;  // 0 = off: replay closed M15 bars on attach
input bool   InputDrawM15SwingLegVisuals = true;
input color  InputM15SwingTrendLineColor = clrGold;

input bool   InputDrawM2SwingLegs        = true;
input color  InputM2SwingLineColor       = clrMediumPurple;
input int    InputM2SwingWarmupBars      = 500; // 0 = off: replay M2 on attach (plot_swing_h1_m5_copy)

input group "M15 breach → opposite M2 FVG (plot_swing_m2_copy)"
input bool   InputEnableOppositeFvgHuntAfterM15Breach = true;
input bool   InputDrawBosOppositeFairValueGapZones   = true;
input double InputM15BreachAnticipationPercentBelowUpHigh = 5.0;  // 0=exact leg high; wick cross (high − N% M2 range) arms hunt
input double InputM15BreachAnticipationPercentAboveDownLow = 5.0; // 0=exact leg low; wick cross (low + N% M2 range) arms hunt
input double InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg = 20.0; // 0=off; % of M2 chart range from breach level
input bool   InputDrawImpulseCancelBufferZone = true;  // hollow rect while hunt ON
input color  InputImpulseCancelBufferColor    = clrDarkOrange;
input int    InputChartRangeBarCount     = 147;
input double InputFairValueGapMinimumPercentOfChartRange = 2.0;
input int    InputMaximumFairValueGapRectangles = 120;
input bool   InputShowLiquidityHuntHud   = true;
input bool   InputLogHuntEvents          = true;  // Experts tab: hunt / FVG / BOS / weakPullback

input group "FVG trade (M2 opposite FVG)"
input bool   InputEnableAutomatedTrading = true;   // false = log trade plan only (no orders)
input double InputFvgTradeMinTickVolumePercentOfM2Avg = 50.0; // 0=off; formation bar tick vol vs prior M2 bars
input int    InputFvgTradeTickVolumeAvgM2BarCount     = 30;   // bars after formation (older) for average

// --- hard-coded trade sizing (per FVG setup = 6 orders) ---
const double   LQ_RISK_USD_PER_TRADE              = 100.0; // total $ risk per FVG setup (all 6 orders)
const ulong    LQ_EXPERT_MAGIC                    = 940028;
const double   LQ_STOP_BUFFER_PERCENT_CHART       = 2.0;
const double   LQ_RISK_FRACTION_CLOSE_QUARTER   = 0.5;
const double   LQ_RISK_FRACTION_OVERALL         = 0.5;
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

#define LiquidityPoolCapacity 32

const string ChartObjectNamePrefixM15SwingTrendLine = "M15_Swing_";
const string ChartObjectNamePrefixM15SwingLabelText = "M15_SWLBL_";
// Same prefixes as plot_swing_h1_m5_copy.mq5 (avoid clash with plot_swing_h1_m5.mq5 PS_M5_*).
const string PFX_M2_TREND = "PSC5_M2_TR_";
const string PFX_M2_LBL   = "PSC5_M2_LB_";
const string LQ_OBJ_PREFIX_FVG_RECT = "LQ_M2_FVG_";
const string LQ_OBJ_PREFIX_FVG_LBL  = "LQ_M2_FVGT_";
const string LQ_OBJ_HUNT_HUD        = "LQ_HUNT_HUD";
const string LQ_OBJ_IMPULSE_BUFFER  = "LQ_IMPULSE_BUF";

struct BosOppositeFairValueGapMemory
{
   bool     isBullishFairValueGap;
   double   fairValueGapZoneLowPrice;
   double   fairValueGapZoneHighPrice;
   datetime fairValueGapBarOpenTime;
   double   bosBarClosePrice;
   double   pathMinLowSinceBos;
   double   pathMaxHighSinceBos;
};

#define BosOppositeFairValueGapMemoryCapacity 32
#define M15LegLiquidityBreachMemoryCapacity   24

struct M15LegLiquidityBreachRecord
{
   datetime legEndTime;
   bool     isUpLegHighBreach;
};

SwingState     g_m15Swing;
SwingState     g_m2Swing;
LiquidityPool  g_liquidityPools[LiquidityPoolCapacity];
int            g_liquidityPoolCount = 0;

datetime g_lastM15BarOpen = 0;
datetime g_lastM2BarOpen  = 0;

bool     g_detectOppositeM2FvgHunt            = false;
bool     g_m15HighWasBreached                 = false;
double   g_m15BreachedLegLevelPrice           = 0.0;
double   g_closeWhenM15LiquidityBreached    = 0.0;
double   g_pathMinLowSinceM15Breach         = 0.0;
double   g_pathMaxHighSinceM15Breach        = 0.0;
double   g_impulseCloseExtremeSinceM15Breach = 0.0;
datetime g_m15BreachM2BarOpenTime            = 0;
int      g_oppositeFvgFoundDuringHuntCount  = 0;
bool     g_deferHuntEndUntilNextOppositeBos = false;
int      g_weakPullback                     = 0;
int      g_oppositeM2BosCountDuringHunt     = 0;
bool     g_sawOppositeBosDuringOppositeM2Phase = false;

BosOppositeFairValueGapMemory g_bosOppFvgMem[BosOppositeFairValueGapMemoryCapacity];
int                           g_bosOppFvgMemCount = 0;
int                           g_lqBosMarkedFvgRectangleSequence = 0;

M15LegLiquidityBreachRecord g_m15LegLiquidityBreaches[M15LegLiquidityBreachMemoryCapacity];
int                         g_m15LegLiquidityBreachCount = 0;

// Per-hunt trade session (keyed by g_m15BreachM2BarOpenTime in order comments).
bool     g_huntTradeOrdersActive         = false;
datetime g_huntOrdersFvgFormationTime    = 0;
bool     g_huntTradeIsBuy                = false;
double   g_huntTradeEntryPrice           = 0.0;
double   g_huntTp19Price                 = 0.0;
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
void   WarmupM15SwingFromHistory();

void   SwingCloseM2Leg(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                       const string chartObjectNamePrefix, const string labelPrefix, const bool drawVisuals,
                       const int lastClosedBarShift = 1);
void   UpdateM2LiveSwingLegVisualIf(const SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                                    const bool drawVisuals);
void   ProcessSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int sh,
                               const color swingLineColor, const string trendPrefix, const string labelPrefix,
                               const bool drawVisuals);
void   ProcessM2SwingStep();
void   WarmupM2SwingFromHistory();

void   RefreshLiquidityHuntHud();
double ReferenceChartHeightForFairValueGapFilterM2();
bool   FairValueGapGapMeetsMinimumPercentOfRangeM2(const double zoneLowPrice, const double zoneHighPrice);
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
bool   M15AllowsBearishHuntWhenSecondLastUpHighBreached(const double pointSize);
bool   M15AllowsBullishHuntWhenSecondLastDownLowBreached(const double pointSize);
bool   M2WickCrossesAboveLevel(const double level, const double barHigh, const double prevHigh,
                               const double pointSize);
bool   M2WickCrossesBelowLevel(const double level, const double barLow, const double prevLow,
                               const double pointSize);
double M15BreachWickLevelForUpLegHigh(const double legHighPrice);
double M15BreachWickLevelForDownLegLow(const double legLowPrice);
bool   TryDetectM2BreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap, double &outBosLegLevelPrice);
bool   PushBosOppositeFairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                         const double zoneHighPrice, const datetime fairValueGapBarOpenTime,
                                         const double bosBarClosePrice, const double pathMinLowSinceBos,
                                         const double pathMaxHighSinceBos);
void   DrawBosMarkedFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                     const double zoneHighPrice, const datetime leftBarTime,
                                     const datetime rightBarTime);
void   ProcessBosOppositeFairValueGapWindow();
int    OppositeM2LegDirectionForHunt();
bool   IsCurrentM2LegOppositeToHunt();
void   ResetWeakPullbackState();
bool   TryM2WickBreachesSameDirectionLevelForHuntReset();
void   ApplySameDirectionBosHuntResets();
void   LogHuntEvent(const string eventName, const string detail = "");
void   OnM2SwingLegDirectionChange(const int closingLegDirection, const int nextLegDirection);
void   ClearImpulseCancelBufferZone();
void   UpdateImpulseCancelBufferZone();
void   ResetCurrentOppositeFvgHuntSession();
bool   TryDetectM15WickLiquidityBreach(const double barHigh, const double barLow,
                                       const double prevHigh, const double prevLow,
                                       const double pointSize, double &outLevel,
                                       bool &outHighBreached, datetime &outLegEndTime);
bool   IsDistinctM15BreachFromActiveHunt(const double m15Level, const bool m15HighBreached,
                                         const double pointSize);
void   ArmOppositeFvgHuntAfterM15Breach(const double m15Level, const bool m15HighBreached,
                                          const datetime breachedLegEndTime,
                                          const double barClose, const double barLow,
                                          const double barHigh, const bool isRestart);

void   ApplyTradeFillingModeFromSymbol();
double M2FvgStopBufferPrice();
double LossPerLotFromTickSpec(const double entryPrice, const double stopLossPrice);
double CalculateVolumeForFixedUsdRisk(const bool isBuy, const double entryPrice,
                                        const double stopLossPrice, const double riskAccountCurrency);
bool   StopsDistanceAllowed(const bool isBuy, const double entryPrice, const double stopLossPrice,
                            const double takeProfitPrice);
bool   HasOurTradeForFormation(const datetime formationTime);
string HuntTradeOrderCommentPrefix();
bool   OrderCommentBelongsToActiveHunt(const string orderComment);
bool   HasOurHuntOpenPosition();
bool   HasOurHuntPendingOrders();
void   ResetHuntTradeState();
void   ResetHuntTradePlacementGateOnly();
bool   HasOurHuntTradePendingOrders();
void   CancelOurHuntTradePendingOrders();
bool   IsConsecutiveM2FvgBarAfter(const datetime priorFvgFormationTime, const datetime newFvgFormationTime);
bool   ResolveHuntFvgOrderPlacementGate(const datetime formationTime, bool &outReplacePendingOnly);
void   RegisterHuntTradeAfterSuccessfulPlace(const bool isBuy, const double entryPrice,
                                               const double tp19Price, const datetime fvgFormationTime);
void   CheckHuntPreEntryTp19CancelOnTick();
bool   IsOurHuntPendingOrderTicket(const ulong orderTicket);
bool   TrySyncHuntPreEntryWatchFromPendingOrders(int &outPendingCount);
bool   HuntMarketReachedTakeProfitLevel(const bool isBuy, const double takeProfitLevel);
void   EndOppositeFvgHuntSession();
bool   ResolveFvgEntryPrice(const bool isBullishFairValueGap, const double zoneLowPrice,
                            const double zoneHighPrice, bool &outUseMarketOrder, double &outEntryPrice);
bool   ComputeM15LegTraceRemainingTakeProfits(const bool isBullishFairValueGap, const double entryPrice,
                                               double &outK, double &outPreviousLegRange,
                                               double &outTakeProfitPrices[]);
void   TryPlaceOppositeFvgTradeSetup(const bool isBullishFairValueGap, const double zoneLowPrice,
                                       const double zoneHighPrice, const datetime formationTime);
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
void   TrailHuntTradeStopOnSameDirectionM2Bos(const bool isBuy);
void   ApplyHuntTradeFirstOppositeM2BosMgmt(const bool isBuy);

//+------------------------------------------------------------------+
int OnInit()
{
   if(InputSwitchChartToM15)
   {
      ChartSetSymbolPeriod(0, _Symbol, PERIOD_M15);
      ChartRedraw(0);
   }

   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingLabelText, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_RECT, -1, -1);
   ObjectsDeleteAll(0, LQ_OBJ_PREFIX_FVG_LBL, -1, -1);
   ObjectDelete(0, LQ_OBJ_HUNT_HUD);
   ObjectDelete(0, LQ_OBJ_IMPULSE_BUFFER);

   ZeroMemory(g_m15Swing);
   ZeroMemory(g_m2Swing);
   g_liquidityPoolCount = 0;

   g_detectOppositeM2FvgHunt            = false;
   g_m15HighWasBreached                 = false;
   g_m15BreachedLegLevelPrice           = 0.0;
   g_closeWhenM15LiquidityBreached    = 0.0;
   g_pathMinLowSinceM15Breach         = 0.0;
   g_pathMaxHighSinceM15Breach        = 0.0;
   g_impulseCloseExtremeSinceM15Breach = 0.0;
   g_m15BreachM2BarOpenTime            = 0;
   g_oppositeFvgFoundDuringHuntCount  = 0;
   g_deferHuntEndUntilNextOppositeBos = false;
   ResetWeakPullbackState();
   g_bosOppFvgMemCount                = 0;
   g_lqBosMarkedFvgRectangleSequence  = 0;
   g_m15LegLiquidityBreachCount       = 0;
   ResetHuntTradeState();

   WarmupM15SwingFromHistory();
   WarmupM2SwingFromHistory();

   g_lastM15BarOpen = iTime(_Symbol, PERIOD_M15, 0);
   g_lastM2BarOpen  = iTime(_Symbol, PERIOD_M2, 0);
   if(g_lastM2BarOpen == 0)
      Print("liquidity_sweep: PERIOD_M2 iTime(0)==0 — symbol may not provide M2 bars.");

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();
   string tradeBlockReason = "";
   if(!IsFvgAutomatedTradingAllowed(tradeBlockReason))
      Print("liquidity_sweep: FVG orders blocked — ", tradeBlockReason);

   RefreshLiquidityHuntHud();

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
   ObjectDelete(0, LQ_OBJ_IMPULSE_BUFFER);
}

//+------------------------------------------------------------------+
void ClearImpulseCancelBufferZone()
{
   ObjectDelete(0, LQ_OBJ_IMPULSE_BUFFER);
}

//+------------------------------------------------------------------+
//| Hollow box: breach level → ± InputBosMaxImpulse% of M2 chart range. |
//| High breach: box above level; low breach: box below level.         |
//+------------------------------------------------------------------+
void UpdateImpulseCancelBufferZone()
{
   if(!InputDrawImpulseCancelBufferZone ||
      InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg <= 0.0 ||
      !g_detectOppositeM2FvgHunt)
   {
      ClearImpulseCancelBufferZone();
      return;
   }

   const double referenceHeight = ReferenceChartHeightForFairValueGapFilterM2();
   if(referenceHeight <= 0.0 || g_m15BreachedLegLevelPrice <= 0.0 || g_m15BreachM2BarOpenTime == 0)
   {
      ClearImpulseCancelBufferZone();
      return;
   }

   const double limitPrice =
      referenceHeight * (InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg / 100.0);

   datetime timeRight = iTime(_Symbol, PERIOD_M2, 0);
   if(timeRight <= g_m15BreachM2BarOpenTime)
      timeRight = g_m15BreachM2BarOpenTime + (datetime)PeriodSeconds(PERIOD_M2);

   double zoneLow  = 0.0;
   double zoneHigh = 0.0;
   if(g_m15HighWasBreached)
   {
      zoneLow  = g_m15BreachedLegLevelPrice;
      zoneHigh = g_m15BreachedLegLevelPrice + limitPrice;
   }
   else
   {
      zoneHigh = g_m15BreachedLegLevelPrice;
      zoneLow  = g_m15BreachedLegLevelPrice - limitPrice;
   }

   const datetime timeLeft = g_m15BreachM2BarOpenTime;

   if(ObjectFind(0, LQ_OBJ_IMPULSE_BUFFER) < 0)
   {
      if(!ObjectCreate(0, LQ_OBJ_IMPULSE_BUFFER, OBJ_RECTANGLE, 0, timeLeft, zoneHigh, timeRight, zoneLow))
         return;
   }
   else
   {
      ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_TIME, 0, timeLeft);
      ObjectSetDouble(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_PRICE, 0, zoneHigh);
      ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_TIME, 1, timeRight);
      ObjectSetDouble(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_PRICE, 1, zoneLow);
   }

   ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_COLOR, InputImpulseCancelBufferColor);
   ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_FILL, false);
   ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_BACK, true);
   ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, LQ_OBJ_IMPULSE_BUFFER, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   CheckHuntPreEntryTp19CancelOnTick();
}

//+------------------------------------------------------------------+
void OnTick()
{
   CheckHuntPreEntryTp19CancelOnTick();

   const datetime tM15 = iTime(_Symbol, PERIOD_M15, 0);
   if(tM15 != g_lastM15BarOpen)
   {
      g_lastM15BarOpen = tM15;
      ProcessM15SwingStep(1);
   }

   const datetime tM2 = iTime(_Symbol, PERIOD_M2, 0);
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
   const int bars = iBars(_Symbol, PERIOD_M15);
   const int n = (int)MathMin(bars - 2, InputWarmupBars);
   if(n < 1)
      return;
   for(int k = n; k >= 1; k--)
      ProcessM15SwingStep(k);
}

//+------------------------------------------------------------------+
void WarmupM2SwingFromHistory()
{
   if(InputM2SwingWarmupBars <= 0)
      return;
   const int bars = iBars(_Symbol, PERIOD_M2);
   const int minNeed = 8;
   if(bars < minNeed)
   {
      Print("liquidity_sweep: M2 warmup skipped (need ", minNeed, " M2 bars; have ", bars, ")");
      return;
   }
   const int n = (int)MathMin(bars - 2, InputM2SwingWarmupBars);
   if(n < 1)
      return;
   for(int k = n; k >= 1; k--)
      ProcessSwingStepAtShift(g_m2Swing, PERIOD_M2, k, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL,
                              InputDrawM2SwingLegs);
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

   if(timeframe == PERIOD_M2 && drawVisuals)
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

   if(drawVisuals)
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
   if(timeframe != PERIOD_M2 || !drawVisuals)
      return;
   if(swingState.currentSwingLeg.swingDirection == 0)
      return;

   const string liveName = PFX_M2_TREND + "LIVE";
   datetime     tEnd     = iTime(_Symbol, PERIOD_M2, 0);
   if(tEnd <= swingState.currentSwingLeg.legStartTime)
      tEnd = swingState.currentSwingLeg.legStartTime + (datetime)PeriodSeconds(PERIOD_M2);

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
                             const bool drawVisuals)
{
   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, sh);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, sh);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, sh);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, sh);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);
   const double lastClosedBarRange =
      (timeframe == PERIOD_M2)
      ? MathAbs(lastClosedBarClose - lastClosedBarOpen)
      : (lastClosedBarHigh - lastClosedBarLow);

   if(swingState.currentSwingLeg.swingDirection == 0)
   {
      if(candleDirection == 0)
         return;
      SwingStartNew(swingState, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow, sh);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
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

   const bool isDecentMovement = (lastClosedBarRange > (averageRangeFiveBars * 0.6));
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
      UpdateM2LiveSwingLegVisualIf(swingState, timeframe, drawVisuals);
   }
   else
   {
      const int closingLegDirection = swingState.currentSwingLeg.swingDirection;

      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

      if(timeframe == PERIOD_M2)
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
      UpdateM2LiveSwingLegVisualIf(swingState, timeframe, drawVisuals);
   }
}

//+------------------------------------------------------------------+
void ProcessM2SwingStep()
{
   ProcessSwingStepAtShift(g_m2Swing, PERIOD_M2, 1, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL,
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
void ProcessM15SwingStep(const int lastClosedBarShift = 1)
{
   const ENUM_TIMEFRAMES timeframe = PERIOD_M15;
   const int         sh            = lastClosedBarShift;

   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, sh);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, sh);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, sh);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, sh);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);
   const double lastClosedBarRange = lastClosedBarHigh - lastClosedBarLow;

   if(g_m15Swing.currentSwingLeg.swingDirection == 0)
   {
      SwingStartNew(g_m15Swing, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow, sh);
      g_m15Swing.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      return;
   }

   double sumRangeFivePriorBars = 0.0;
   for(int k = 1; k <= 5; k++)
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, sh + k) - iLow(_Symbol, timeframe, sh + k));
   const double averageRangeFiveBars = sumRangeFivePriorBars / 5.0;

   const bool isDecentMovement = (lastClosedBarRange > (averageRangeFiveBars * 1.0));
   if(isDecentMovement && candleDirection == g_m15Swing.currentSwingLeg.swingDirection)
      g_m15Swing.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

   int nextSwingDirection = g_m15Swing.currentSwingLeg.swingDirection;
   if(g_m15Swing.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < g_m15Swing.priceAnchorLevel)
      nextSwingDirection = -1;
   else if(g_m15Swing.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > g_m15Swing.priceAnchorLevel)
      nextSwingDirection = 1;

   if(nextSwingDirection == g_m15Swing.currentSwingLeg.swingDirection)
   {
      SwingExtend(g_m15Swing, lastClosedBarHigh, lastClosedBarLow);
   }
   else
   {
      SwingExtend(g_m15Swing, lastClosedBarHigh, lastClosedBarLow);

      SwingCloseM15Context(g_m15Swing, timeframe, sh);

      Swing closedSwingLeg = g_m15Swing.swingHistory[g_m15Swing.swingHistoryCount - 1];
      double newSwingLegHigh = lastClosedBarHigh;
      double newSwingLegLow  = lastClosedBarLow;
      if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
         newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
      else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
         newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

      SwingStartNew(g_m15Swing, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow, sh);
      g_m15Swing.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
   }
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
   const string txt =
      g_detectOppositeM2FvgHunt
      ? StringFormat("M15 breach → opp.M2 FVG hunt: ON  (fvgs=%d oppBOS=%d defer=%s weak=%d)",
                     g_oppositeFvgFoundDuringHuntCount, g_oppositeM2BosCountDuringHunt,
                     g_deferHuntEndUntilNextOppositeBos ? "Y" : "N", g_weakPullback)
      : "M15 breach → opp.M2 FVG hunt: OFF";
   ObjectSetString(0, LQ_OBJ_HUNT_HUD, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_COLOR, g_detectOppositeM2FvgHunt ? clrLime : clrSilver);
   ObjectSetInteger(0, LQ_OBJ_HUNT_HUD, OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForFairValueGapFilterM2()
{
   const int barCount = InputChartRangeBarCount;
   if(barCount < 1)
      return 0.0;

   const int totalBars = iBars(_Symbol, PERIOD_M2);
   if(totalBars < barCount + 1)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = 1; barShiftIndex <= barCount; barShiftIndex++)
   {
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, PERIOD_M2, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, PERIOD_M2, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

//+------------------------------------------------------------------+
bool FairValueGapGapMeetsMinimumPercentOfRangeM2(const double zoneLowPrice, const double zoneHighPrice)
{
   if(InputFairValueGapMinimumPercentOfChartRange <= 0.0)
      return true;

   const double gapSize = MathAbs(zoneHighPrice - zoneLowPrice);
   if(gapSize <= 0.0)
      return false;

   const double referenceHeight = ReferenceChartHeightForFairValueGapFilterM2();
   if(referenceHeight <= 0.0)
      return true;

   return (gapSize >= referenceHeight * (InputFairValueGapMinimumPercentOfChartRange / 100.0));
}

//+------------------------------------------------------------------+
bool DetectFairValueGapOnLastClosedBarM2(bool &isBullishFairValueGap, double &fairValueGapZoneLowPrice,
                                        double &fairValueGapZoneHighPrice)
{
   isBullishFairValueGap = false;
   fairValueGapZoneLowPrice  = 0.0;
   fairValueGapZoneHighPrice = 0.0;

   if(iBars(_Symbol, PERIOD_M2) < 4)
      return false;

   const double newestBarHigh = iHigh(_Symbol, PERIOD_M2, 1);
   const double newestBarLow  = iLow(_Symbol, PERIOD_M2, 1);
   const double oldestBarHigh = iHigh(_Symbol, PERIOD_M2, 3);
   const double oldestBarLow  = iLow(_Symbol, PERIOD_M2, 3);

   if(newestBarLow > oldestBarHigh)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfRangeM2(oldestBarHigh, newestBarLow))
         return false;
      isBullishFairValueGap = true;
      fairValueGapZoneLowPrice  = oldestBarHigh;
      fairValueGapZoneHighPrice = newestBarLow;
      return true;
   }

   if(newestBarHigh < oldestBarLow)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfRangeM2(newestBarHigh, oldestBarLow))
         return false;
      isBullishFairValueGap = false;
      fairValueGapZoneLowPrice  = newestBarHigh;
      fairValueGapZoneHighPrice = oldestBarLow;
      return true;
   }

   return false;
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
//| 2nd-last up high breach → hunt only if 2nd-last up high > latest up high. |
//+------------------------------------------------------------------+
bool M15AllowsBearishHuntWhenSecondLastUpHighBreached(const double pointSize)
{
   double latestUpHigh      = 0.0;
   double latestUpLow       = 0.0;
   double secondLastUpHigh  = 0.0;
   double secondLastUpLow   = 0.0;
   datetime legEndIgnored   = 0;
   if(!TryNthM15CompletedSwingLeg(1, 1, latestUpHigh, latestUpLow, legEndIgnored))
      return false;
   if(!TryNthM15CompletedSwingLeg(1, 2, secondLastUpHigh, secondLastUpLow, legEndIgnored))
      return false;
   return (secondLastUpHigh > latestUpHigh + pointSize);
}

//+------------------------------------------------------------------+
//| 2nd-last down low breach → hunt only if 2nd-last down low < latest down low. |
//+------------------------------------------------------------------+
bool M15AllowsBullishHuntWhenSecondLastDownLowBreached(const double pointSize)
{
   double latestDownHigh     = 0.0;
   double latestDownLow      = 0.0;
   double secondLastDownHigh = 0.0;
   double secondLastDownLow  = 0.0;
   datetime legEndIgnored    = 0;
   if(!TryNthM15CompletedSwingLeg(-1, 1, latestDownHigh, latestDownLow, legEndIgnored))
      return false;
   if(!TryNthM15CompletedSwingLeg(-1, 2, secondLastDownHigh, secondLastDownLow, legEndIgnored))
      return false;
   return (secondLastDownLow < latestDownLow - pointSize);
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
bool TryDetectM2BreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap,
                                                 double &outBosLegLevelPrice)
{
   outExpectsBullishFairValueGap = false;
   outBosLegLevelPrice = 0.0;
   if(g_m2Swing.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, PERIOD_M2, 1);
   const double prevClose  = iClose(_Symbol, PERIOD_M2, 2);
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
bool PushBosOppositeFairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                      const double zoneHighPrice, const datetime fairValueGapBarOpenTime,
                                      const double bosBarClosePrice, const double pathMinLowSinceBos,
                                      const double pathMaxHighSinceBos)
{
   for(int memoryIndex = 0; memoryIndex < g_bosOppFvgMemCount; memoryIndex++)
   {
      if(g_bosOppFvgMem[memoryIndex].fairValueGapBarOpenTime == fairValueGapBarOpenTime)
         return false;
   }

   if(g_bosOppFvgMemCount < BosOppositeFairValueGapMemoryCapacity)
   {
      const int index = g_bosOppFvgMemCount;
      g_bosOppFvgMem[index].isBullishFairValueGap   = isBullishFairValueGap;
      g_bosOppFvgMem[index].fairValueGapZoneLowPrice  = zoneLowPrice;
      g_bosOppFvgMem[index].fairValueGapZoneHighPrice = zoneHighPrice;
      g_bosOppFvgMem[index].fairValueGapBarOpenTime  = fairValueGapBarOpenTime;
      g_bosOppFvgMem[index].bosBarClosePrice       = bosBarClosePrice;
      g_bosOppFvgMem[index].pathMinLowSinceBos     = pathMinLowSinceBos;
      g_bosOppFvgMem[index].pathMaxHighSinceBos  = pathMaxHighSinceBos;
      g_bosOppFvgMemCount++;
      return true;
   }

   for(int shiftIndex = 1; shiftIndex < BosOppositeFairValueGapMemoryCapacity; shiftIndex++)
      g_bosOppFvgMem[shiftIndex - 1] = g_bosOppFvgMem[shiftIndex];

   const int lastIndex = BosOppositeFairValueGapMemoryCapacity - 1;
   g_bosOppFvgMem[lastIndex].isBullishFairValueGap   = isBullishFairValueGap;
   g_bosOppFvgMem[lastIndex].fairValueGapZoneLowPrice  = zoneLowPrice;
   g_bosOppFvgMem[lastIndex].fairValueGapZoneHighPrice = zoneHighPrice;
   g_bosOppFvgMem[lastIndex].fairValueGapBarOpenTime  = fairValueGapBarOpenTime;
   g_bosOppFvgMem[lastIndex].bosBarClosePrice       = bosBarClosePrice;
   g_bosOppFvgMem[lastIndex].pathMinLowSinceBos     = pathMinLowSinceBos;
   g_bosOppFvgMem[lastIndex].pathMaxHighSinceBos  = pathMaxHighSinceBos;
   return true;
}

//+------------------------------------------------------------------+
void DrawBosMarkedFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                   const double zoneHighPrice, const datetime leftBarTime,
                                   const datetime rightBarTime)
{
   if(!InputDrawBosOppositeFairValueGapZones)
      return;

   g_lqBosMarkedFvgRectangleSequence++;
   const string sequenceString = IntegerToString(g_lqBosMarkedFvgRectangleSequence);
   const string chartObjectName = LQ_OBJ_PREFIX_FVG_RECT + sequenceString;
   const string typeLabelName   = LQ_OBJ_PREFIX_FVG_LBL + sequenceString;

   if(g_lqBosMarkedFvgRectangleSequence > InputMaximumFairValueGapRectangles)
   {
      const string oldSequenceString =
         IntegerToString(g_lqBosMarkedFvgRectangleSequence - InputMaximumFairValueGapRectangles);
      ObjectDelete(0, LQ_OBJ_PREFIX_FVG_RECT + oldSequenceString);
      ObjectDelete(0, LQ_OBJ_PREFIX_FVG_LBL + oldSequenceString);
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
void LogHuntEvent(const string eventName, const string detail = "")
{
   if(!InputLogHuntEvents)
      return;

   const datetime barTime = iTime(_Symbol, PERIOD_M2, 1);
   const string timeText  = (barTime != 0) ? TimeToString(barTime, TIME_DATE | TIME_MINUTES) : "no-bar";

   if(StringLen(detail) > 0)
      PrintFormat("liquidity_sweep [%s] %s | %s", timeText, eventName, detail);
   else
      PrintFormat("liquidity_sweep [%s] %s", timeText, eventName);
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

   const double closePrice = iClose(_Symbol, PERIOD_M2, 1);
   const double prevClose  = iClose(_Symbol, PERIOD_M2, 2);
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

   const double closePrice = iClose(_Symbol, PERIOD_M2, 1);
   const double prevClose  = iClose(_Symbol, PERIOD_M2, 2);
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
string HuntTradeOrderCommentPrefix()
{
   if(g_m15BreachM2BarOpenTime == 0)
      return "LQ_HS0_";
   return "LQ_HS" + IntegerToString((long)g_m15BreachM2BarOpenTime) + "_";
}

//+------------------------------------------------------------------+
bool OrderCommentBelongsToActiveHunt(const string orderComment)
{
   if(g_m15BreachM2BarOpenTime == 0)
      return false;
   return (StringFind(orderComment, HuntTradeOrderCommentPrefix()) == 0);
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
   return (StringFind(orderComment, "LQ_HS") == 0);
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
      if(StringFind(comment, "LQ_HS") != 0)
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
   EnsureHuntTradeSessionCommentPrefixFromOrdersOrPositions();

   double storedTp3  = g_huntTp19Price;
   bool   isBuy      = g_huntTradeIsBuy;
   double entryPrice = g_huntTradeEntryPrice;
   bool   haveSide   = false;

   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(!IsOurHuntPendingOrderTicket(ticket))
         continue;

      outPendingCount++;
      const string comment = OrderGetString(ORDER_COMMENT);
      const double orderTp = OrderGetDouble(ORDER_TP);
      const double orderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      const bool orderIsBuy = (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP ||
                               orderType == ORDER_TYPE_BUY_STOP_LIMIT);

      if(!haveSide)
      {
         isBuy      = orderIsBuy;
         entryPrice = orderPrice;
         haveSide   = true;
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

   g_huntTradeIsBuy      = isBuy;
   g_huntTradeEntryPrice = entryPrice;
   if(g_huntTp19Price <= 0.0 && storedTp3 > 0.0)
      g_huntTp19Price = storedTp3;
   else if(storedTp3 > 0.0)
      g_huntTp19Price = storedTp3;

   return (g_huntTp19Price > 0.0);
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
   const double highM2 = iHigh(_Symbol, PERIOD_M2, 0);
   const double lowM2  = iLow(_Symbol, PERIOD_M2, 0);

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
void ClearHuntTradeSessionIfNoOpenPositions()
{
   if(HasOurHuntTradeOpenPosition())
      return;
   g_huntTradeSessionCommentPrefix = "";
   g_huntFirstOppBosMgmtDone       = false;
   g_lastHuntPosMgmtM2BarTime      = 0;
}

//+------------------------------------------------------------------+
void TrailHuntTradeStopOnSameDirectionM2Bos(const bool isBuy)
{
   if(g_m2Swing.currentSwingLeg.swingDirection == 0)
      return;

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
void ApplyHuntTradeFirstOppositeM2BosMgmt(const bool isBuy)
{
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

   const double midPoint = (legHigh + legLow) * 0.5;
   const double newTakeProfit = isBuy
      ? NormalizeDouble(midPoint - bufferPrice, _Digits)
      : NormalizeDouble(midPoint + bufferPrice, _Digits);
   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();

   int closedCqCount = 0;
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
      if(!HuntTradeCommentIsOurs(comment) || !HuntTradeCommentIsCloseQuarter(comment))
         continue;
      if(g_trade.PositionClose(ticket))
         closedCqCount++;
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
      if(!HuntTradeCommentIsOurs(comment) || !HuntTradeCommentIsCloseQuarter(comment))
         continue;
      g_trade.OrderDelete(ticket);
   }

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
                StringFormat("%s first opp M2 BOS: CQ closed=%d OV tp=%.5f mid=%.5f buf=%.5f legH=%.5f legL=%.5f mod=%d skip=%d",
                             isBuy ? "bull" : "bear", closedCqCount, newTakeProfit, midPoint, bufferPrice,
                             legHigh, legLow, modifiedOvCount, skippedOvCount));
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

   const datetime closedM2BarTime = iTime(_Symbol, PERIOD_M2, 1);
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

   double brokenLevel       = 0.0;
   const bool priceBullBos  = TryDetectM2PriceBreakAboveLatestUpLegHigh(brokenLevel);
   const bool priceBearBos  = TryDetectM2PriceBreakBelowLatestDownLegLow(brokenLevel);

   if(!priceBullBos && !priceBearBos)
      return;

   if(isBuy)
   {
      if(priceBullBos)
         TrailHuntTradeStopOnSameDirectionM2Bos(true);
      if(priceBearBos && !g_huntFirstOppBosMgmtDone)
         ApplyHuntTradeFirstOppositeM2BosMgmt(true);
   }
   else
   {
      if(priceBearBos)
         TrailHuntTradeStopOnSameDirectionM2Bos(false);
      if(priceBullBos && !g_huntFirstOppBosMgmtDone)
         ApplyHuntTradeFirstOppositeM2BosMgmt(false);
   }

   LogHuntEvent("TRADE_MGMT_BOS",
                StringFormat("%s bullBOS=%s bearBOS=%s lvl=%.5f oppDone=%s prefix=%s",
                             isBuy ? "buy" : "sell", priceBullBos ? "Y" : "N", priceBearBos ? "Y" : "N",
                             brokenLevel, g_huntFirstOppBosMgmtDone ? "Y" : "N",
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
   const long formationVol = iTickVolume(_Symbol, PERIOD_M2, formationBarShift);
   if(formationVol <= 0)
      return false;

   long volSum = 0;
   int  counted = 0;
   for(int shift = formationBarShift + 1; shift <= formationBarShift + avgBarCount; shift++)
   {
      const long barVol = iTickVolume(_Symbol, PERIOD_M2, shift);
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
   int pendingCount = 0;
   return (TrySyncHuntPreEntryWatchFromPendingOrders(pendingCount) && pendingCount > 0);
}

//+------------------------------------------------------------------+
void CancelOurHuntPendingOrders()
{
   EnsureHuntTradeSessionCommentPrefixFromOrdersOrPositions();

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   int deletedCount = 0;
   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(!IsOurHuntPendingOrderTicket(ticket))
         continue;
      if(g_trade.OrderDelete(ticket))
         deletedCount++;
   }

   if(deletedCount > 0)
      LogHuntEvent("HUNT_PENDING_DELETE", StringFormat("deleted=%d", deletedCount));
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
   g_huntTp19Price              = 0.0;
   if(!HasOurHuntTradeOpenPosition())
   {
      g_huntTradeSessionCommentPrefix = "";
      g_huntFirstOppBosMgmtDone       = false;
      g_lastHuntPosMgmtM2BarTime      = 0;
   }
}

//+------------------------------------------------------------------+
void EndOppositeFvgHuntSession()
{
   g_detectOppositeM2FvgHunt            = false;
   g_m15BreachM2BarOpenTime            = 0;
   g_oppositeFvgFoundDuringHuntCount  = 0;
   g_deferHuntEndUntilNextOppositeBos = false;
   ResetWeakPullbackState();
   ClearImpulseCancelBufferZone();
   ResetHuntTradePlacementGateOnly();
}

//+------------------------------------------------------------------+
bool IsConsecutiveM2FvgBarAfter(const datetime priorFvgFormationTime,
                                const datetime newFvgFormationTime)
{
   if(priorFvgFormationTime == 0 || newFvgFormationTime == 0)
      return false;
   if(newFvgFormationTime <= priorFvgFormationTime)
      return false;

   const int priorBarShift = iBarShift(_Symbol, PERIOD_M2, priorFvgFormationTime, true);
   return (priorBarShift == 2);
}

//+------------------------------------------------------------------+
bool ResolveHuntFvgOrderPlacementGate(const datetime formationTime, bool &outReplacePendingOnly)
{
   outReplacePendingOnly = false;

   if(HasOurHuntOpenPosition())
   {
      LogHuntEvent("TRADE_SKIP", "hunt position open — one trade setup per hunt");
      return false;
   }

   if(!g_huntTradeOrdersActive)
      return true;

   if(HasOurHuntPendingOrders() &&
      IsConsecutiveM2FvgBarAfter(g_huntOrdersFvgFormationTime, formationTime))
   {
      outReplacePendingOnly = true;
      LogHuntEvent("TRADE_REPLACE", StringFormat("consecutive FVG %s → %s",
                                                 IntegerToString((long)g_huntOrdersFvgFormationTime),
                                                 IntegerToString((long)formationTime)));
      CancelOurHuntPendingOrders();
      ResetHuntTradeState();
      return true;
   }

   LogHuntEvent("TRADE_SKIP", StringFormat("hunt orders already active for FVG %s",
                                           IntegerToString((long)g_huntOrdersFvgFormationTime)));
   return false;
}

//+------------------------------------------------------------------+
void RegisterHuntTradeAfterSuccessfulPlace(const bool isBuy, const double entryPrice,
                                           const double tp19Price, const datetime fvgFormationTime)
{
   g_huntTradeOrdersActive           = true;
   g_huntOrdersFvgFormationTime      = fvgFormationTime;
   g_huntTradeIsBuy                  = isBuy;
   g_huntTradeEntryPrice             = entryPrice;
   g_huntTp19Price                   = tp19Price;
   g_huntTradeSessionCommentPrefix   = HuntTradeOrderCommentPrefix();
   g_huntFirstOppBosMgmtDone         = false;
}

//+------------------------------------------------------------------+
void CheckHuntPreEntryTp19CancelOnTick()
{
   int pendingCount = 0;
   if(!TrySyncHuntPreEntryWatchFromPendingOrders(pendingCount))
   {
      if(g_huntTp19Price > 0.0)
         ResetHuntTradeState();
      return;
   }

   if(HasOurHuntTradeOpenPosition())
      return;

   const double tp3Level = g_huntTp19Price;
   if(!HuntMarketReachedTakeProfitLevel(g_huntTradeIsBuy, tp3Level))
      return;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   CancelOurHuntPendingOrders();

   int remaining = 0;
   TrySyncHuntPreEntryWatchFromPendingOrders(remaining);

   if(remaining > 0)
   {
      LogHuntEvent("HUNT_TP3_PREENTRY_FAIL",
                   StringFormat("TP3=%.5f hit but %d pendings remain (bid=%.5f ask=%.5f)",
                                tp3Level, remaining, bid, ask));
      return;
   }

   ResetHuntTradeState();
   LogHuntEvent("HUNT_TP3_PREENTRY_CANCEL",
                StringFormat("pending removed: TP3=%.5f entry=%.5f %s pend=%d bid=%.5f ask=%.5f hiM2=%.5f loM2=%.5f",
                             tp3Level, g_huntTradeEntryPrice, g_huntTradeIsBuy ? "buy" : "sell",
                             pendingCount, bid, ask,
                             iHigh(_Symbol, PERIOD_M2, 0), iLow(_Symbol, PERIOD_M2, 0)));
}

//+------------------------------------------------------------------+
bool ResolveFvgEntryPrice(const bool isBullishFairValueGap, const double zoneLowPrice,
                          const double zoneHighPrice, bool &outUseMarketOrder, double &outEntryPrice)
{
   outUseMarketOrder = false;
   outEntryPrice     = 0.0;

   const double higherEndOfFairValueGap = MathMax(zoneLowPrice, zoneHighPrice);
   const double lowerEndOfFairValueGap  = MathMin(zoneLowPrice, zoneHighPrice);
   const double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBullishFairValueGap)
   {
      const bool bidInsideFairValueGap =
         (currentBid >= lowerEndOfFairValueGap && currentBid <= higherEndOfFairValueGap);
      if(bidInsideFairValueGap)
      {
         outUseMarketOrder = true;
         outEntryPrice     = currentAsk;
      }
      else if(currentBid > higherEndOfFairValueGap)
         outEntryPrice = NormalizeDouble(higherEndOfFairValueGap, _Digits);
      else
         outEntryPrice = NormalizeDouble(lowerEndOfFairValueGap, _Digits);
   }
   else
   {
      const bool askInsideFairValueGap =
         (currentAsk >= lowerEndOfFairValueGap && currentAsk <= higherEndOfFairValueGap);
      if(askInsideFairValueGap)
      {
         outUseMarketOrder = true;
         outEntryPrice     = currentBid;
      }
      else if(currentAsk < lowerEndOfFairValueGap)
         outEntryPrice = NormalizeDouble(lowerEndOfFairValueGap, _Digits);
      else
         outEntryPrice = NormalizeDouble(higherEndOfFairValueGap, _Digits);
   }

   return (outEntryPrice > 0.0);
}

//+------------------------------------------------------------------+
// k = price move from active M15 leg extreme (bear: leg high, bull: leg low) to entry.
// previousLegRange = latest completed M15 leg in trade direction (high - low).
// TP distance from entry = (multiplier * previousLegRange) - k  (1x, 1.5x, 2x).
bool ComputeM15LegTraceRemainingTakeProfits(const bool isBullishFairValueGap, const double entryPrice,
                                            double &outK, double &outPreviousLegRange,
                                            double &outTakeProfitPrices[])
{
   outK                 = 0.0;
   outPreviousLegRange  = 0.0;
   ArrayResize(outTakeProfitPrices, LQ_TP_COUNT);

   if(g_m15Swing.currentSwingLeg.swingDirection == 0)
      return false;

   const int    swingDirection = isBullishFairValueGap ? 1 : -1;
   double       prevLegHigh    = 0.0;
   double       prevLegLow     = 0.0;
   datetime     prevLegEndIgnored = 0;
   if(!TryNthM15CompletedSwingLeg(swingDirection, 1, prevLegHigh, prevLegLow, prevLegEndIgnored))
      return false;

   outPreviousLegRange = prevLegHigh - prevLegLow;
   const double minDistance = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(outPreviousLegRange <= minDistance)
      return false;

   const double activeLegHigh = g_m15Swing.currentSwingLeg.legHighPrice;
   const double activeLegLow  = g_m15Swing.currentSwingLeg.legLowPrice;
   const double tpMultipliers[3] = {1.0, 1.5, 2.0};

   if(isBullishFairValueGap)
   {
      outK = entryPrice - activeLegLow;
      if(outK < 0.0)
         outK = 0.0;
      for(int tpIndex = 0; tpIndex < LQ_TP_COUNT; tpIndex++)
      {
         const double tpDistance = tpMultipliers[tpIndex] * outPreviousLegRange - outK;
         if(tpDistance <= minDistance)
            return false;
         outTakeProfitPrices[tpIndex] = NormalizeDouble(entryPrice + tpDistance, _Digits);
      }
      return (outTakeProfitPrices[0] > entryPrice);
   }

   outK = activeLegHigh - entryPrice;
   if(outK < 0.0)
      outK = 0.0;
   for(int tpIndex = 0; tpIndex < LQ_TP_COUNT; tpIndex++)
   {
      const double tpDistance = tpMultipliers[tpIndex] * outPreviousLegRange - outK;
      if(tpDistance <= minDistance)
         return false;
      outTakeProfitPrices[tpIndex] = NormalizeDouble(entryPrice - tpDistance, _Digits);
   }
   return (outTakeProfitPrices[0] < entryPrice);
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

   const double formationClose = NormalizeDouble(iClose(_Symbol, PERIOD_M2, 1), _Digits);
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
      const double formationLow = NormalizeDouble(iLow(_Symbol, PERIOD_M2, 1), _Digits);
      const double gapLowerNorm = NormalizeDouble(gapLow, _Digits);
      if(MathAbs(limitNorm - gapLowerNorm) <= tolerance)
         closeMatchesEntry =
            (MathAbs(formationClose - gapLowerNorm) <= tolerance) ||
            (MathAbs(formationClose - formationLow) <= tolerance &&
             MathAbs(formationLow - gapLowerNorm) <= tolerance);
   }
   else if(!closeMatchesEntry && !isBullishFairValueGap)
   {
      const double formationHigh = NormalizeDouble(iHigh(_Symbol, PERIOD_M2, 1), _Digits);
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
void TryPlaceOppositeFvgTradeSetup(const bool isBullishFairValueGap, const double zoneLowPrice,
                                    const double zoneHighPrice, const datetime formationTime)
{
   if(formationTime == 0)
   {
      LogHuntEvent("TRADE_SKIP", "formationTime=0");
      return;
   }

   bool replacePendingOnly = false;
   if(!ResolveHuntFvgOrderPlacementGate(formationTime, replacePendingOnly))
      return;

   const int barShift = iBarShift(_Symbol, PERIOD_M2, formationTime, true);
   if(barShift < 0 || barShift > LQ_FVG_TRADE_MAX_M2_BAR_SHIFT)
   {
      LogHuntEvent("TRADE_SKIP", StringFormat("FVG too old shift=%d max=%d", barShift,
                                              LQ_FVG_TRADE_MAX_M2_BAR_SHIFT));
      return;
   }

   if(!FvgFormationBarMeetsMinTickVolume(barShift))
      return;

   const double bufferPrice = M2FvgStopBufferPrice();
   if(bufferPrice <= 0.0)
   {
      LogHuntEvent("TRADE_SKIP", "chart height/buffer invalid");
      return;
   }

   bool   useMarketOrder = false;
   double entryPrice     = 0.0;
   if(!ResolveFvgEntryPrice(isBullishFairValueGap, zoneLowPrice, zoneHighPrice,
                            useMarketOrder, entryPrice))
   {
      LogHuntEvent("TRADE_SKIP", "entry resolve failed");
      return;
   }

   TryPromoteFvgLimitToMarketIfFormationCloseMatchesEntry(isBullishFairValueGap, zoneLowPrice,
                                                          zoneHighPrice, entryPrice,
                                                          useMarketOrder, entryPrice);

   const double higherEndOfFairValueGap = MathMax(zoneLowPrice, zoneHighPrice);
   const double lowerEndOfFairValueGap  = MathMin(zoneLowPrice, zoneHighPrice);

   double stopLossCloseQuarter = 0.0;
   double stopLossOverall      = 0.0;
   if(isBullishFairValueGap)
   {
      stopLossCloseQuarter = NormalizeDouble(lowerEndOfFairValueGap - bufferPrice, _Digits);
      double minLow = iLow(_Symbol, PERIOD_M2, 1);
      for(int sh = 2; sh <= 3; sh++)
         minLow = MathMin(minLow, iLow(_Symbol, PERIOD_M2, sh));
      stopLossOverall = NormalizeDouble(minLow - bufferPrice, _Digits);
      if(entryPrice <= stopLossCloseQuarter || entryPrice <= stopLossOverall)
      {
         LogHuntEvent("TRADE_SKIP", "buy entry not above SL");
         return;
      }
   }
   else
   {
      stopLossCloseQuarter = NormalizeDouble(higherEndOfFairValueGap + bufferPrice, _Digits);
      double maxHigh = iHigh(_Symbol, PERIOD_M2, 1);
      for(int sh = 2; sh <= 3; sh++)
         maxHigh = MathMax(maxHigh, iHigh(_Symbol, PERIOD_M2, sh));
      stopLossOverall = NormalizeDouble(maxHigh + bufferPrice, _Digits);
      if(entryPrice >= stopLossCloseQuarter || entryPrice >= stopLossOverall)
      {
         LogHuntEvent("TRADE_SKIP", "sell entry not below SL");
         return;
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
            LogHuntEvent("TRADE_SKIP",
                         StringFormat("buy limit entry invalid entry=%.5f bid=%.5f ask=%.5f",
                                      normalizedEntry, currentBid, currentAsk));
            return;
         }
         useMarketOrder  = useMarketAfterFallback;
         entryPrice      = entryAfterFallback;
         normalizedEntry = NormalizeDouble(entryPrice, _Digits);

         if(normalizedEntry <= stopLossCloseQuarter || normalizedEntry <= stopLossOverall)
         {
            LogHuntEvent("TRADE_SKIP", "buy entry not above SL after fallback");
            return;
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
            LogHuntEvent("TRADE_SKIP",
                         StringFormat("sell limit entry invalid entry=%.5f bid=%.5f ask=%.5f",
                                      normalizedEntry, currentBid, currentAsk));
            return;
         }
         useMarketOrder  = useMarketAfterFallback;
         entryPrice      = entryAfterFallback;
         normalizedEntry = NormalizeDouble(entryPrice, _Digits);

         if(normalizedEntry >= stopLossCloseQuarter || normalizedEntry >= stopLossOverall)
         {
            LogHuntEvent("TRADE_SKIP", "sell entry not below SL after fallback");
            return;
         }
      }
   }

   double m15MoveK = 0.0;
   double m15PreviousLegRange = 0.0;
   double takeProfitPrices[];
   if(!ComputeM15LegTraceRemainingTakeProfits(isBullishFairValueGap, normalizedEntry, m15MoveK,
                                            m15PreviousLegRange, takeProfitPrices))
   {
      LogHuntEvent("TRADE_SKIP",
                   StringFormat("M15 k/range TP invalid entry=%.5f activeM15=%d k=%.5f prevRange=%.5f",
                                normalizedEntry, g_m15Swing.currentSwingLeg.swingDirection,
                                m15MoveK, m15PreviousLegRange));
      return;
   }

   for(int tpIndex = 0; tpIndex < LQ_TP_COUNT; tpIndex++)
   {
      if(!StopsDistanceAllowed(isBuy, normalizedEntry, stopLossCloseQuarter, takeProfitPrices[tpIndex]) ||
         !StopsDistanceAllowed(isBuy, normalizedEntry, stopLossOverall, takeProfitPrices[tpIndex]))
      {
         LogHuntEvent("TRADE_SKIP", StringFormat("broker stops level tp=%d", tpIndex + 1));
         return;
      }
   }

   if(LQ_RISK_USD_PER_TRADE <= 0.0)
   {
      LogHuntEvent("TRADE_SKIP", "LQ_RISK_USD_PER_TRADE invalid");
      return;
   }

   const double riskTotalAccount = LQ_RISK_USD_PER_TRADE;
   const double riskCloseQuarterTotal = riskTotalAccount * LQ_RISK_FRACTION_CLOSE_QUARTER;
   const double riskOverallTotal      = riskTotalAccount * LQ_RISK_FRACTION_OVERALL;
   const double riskPerCloseQuarterOrder = riskCloseQuarterTotal / (double)LQ_TP_COUNT;
   const double riskPerOverallOrder      = riskOverallTotal / (double)LQ_TP_COUNT;

   const string huntCommentPrefix = HuntTradeOrderCommentPrefix();
   const string formationTag      = IntegerToString((long)formationTime);
   int          placedCount       = 0;
   int          zeroVolumeCount   = 0;

   const string logDetail = StringFormat(
      "%s entry=%.5f slCQ=%.5f slOV=%.5f tp=%.5f/%.5f/%.5f k=%.5f prevM15Range=%.5f (1x/1.5x/2x-k) market=%s",
      isBullishFairValueGap ? "bull" : "bear", normalizedEntry,
      stopLossCloseQuarter, stopLossOverall,
      takeProfitPrices[0], takeProfitPrices[1], takeProfitPrices[2],
      m15MoveK, m15PreviousLegRange, useMarketOrder ? "Y" : "N");

   string tradeBlockReason = "";
   if(!IsFvgAutomatedTradingAllowed(tradeBlockReason))
   {
      LogHuntEvent("TRADE_PLAN", logDetail + " | " + tradeBlockReason);
      return;
   }

   for(int tpIndex = 0; tpIndex < LQ_TP_COUNT; tpIndex++)
   {
      const string commentCq =
         StringFormat("%sCQ_TP%d_%s", huntCommentPrefix, tpIndex + 1, formationTag);
      const double volumeCq =
         CalculateVolumeForFixedUsdRisk(isBuy, normalizedEntry, stopLossCloseQuarter,
                                      riskPerCloseQuarterOrder);
      if(volumeCq <= 0.0)
         zeroVolumeCount++;
      else if(PlaceOneFvgTradeOrder(isBullishFairValueGap, useMarketOrder, normalizedEntry,
                                    stopLossCloseQuarter, takeProfitPrices[tpIndex], volumeCq, commentCq))
         placedCount++;

      const string commentOv =
         StringFormat("%sOV_TP%d_%s", huntCommentPrefix, tpIndex + 1, formationTag);
      const double volumeOv =
         CalculateVolumeForFixedUsdRisk(isBuy, normalizedEntry, stopLossOverall,
                                      riskPerOverallOrder);
      if(volumeOv <= 0.0)
         zeroVolumeCount++;
      else if(PlaceOneFvgTradeOrder(isBullishFairValueGap, useMarketOrder, normalizedEntry,
                                    stopLossOverall, takeProfitPrices[tpIndex], volumeOv, commentOv))
         placedCount++;
   }

   if(placedCount > 0)
   {
      RegisterHuntTradeAfterSuccessfulPlace(isBuy, normalizedEntry, takeProfitPrices[2], formationTime);
      LogHuntEvent("TRADE_PLACE",
                   StringFormat("%s placed=%d/6 replace=%s %s", formationTag, placedCount,
                                replacePendingOnly ? "Y" : "N", logDetail));
   }
   else
      LogHuntEvent("TRADE_FAIL",
                   StringFormat("%s zeroVol=%d %s", formationTag, zeroVolumeCount, logDetail));
}

//+------------------------------------------------------------------+
int OppositeM2LegDirectionForHunt()
{
   return g_m15HighWasBreached ? -1 : 1;
}

//+------------------------------------------------------------------+
bool IsCurrentM2LegOppositeToHunt()
{
   if(!g_detectOppositeM2FvgHunt)
      return false;
   return (g_m2Swing.currentSwingLeg.swingDirection == OppositeM2LegDirectionForHunt());
}

//+------------------------------------------------------------------+
void ResetWeakPullbackState()
{
   g_weakPullback = 0;
   g_oppositeM2BosCountDuringHunt     = 0;
   g_deferHuntEndUntilNextOppositeBos = false;
   g_sawOppositeBosDuringOppositeM2Phase = false;
}

//+------------------------------------------------------------------+
//| Weak/defer/oppBOS reset only: same-dir swing level taken by wick.   |
//| Not M2 BOS (close break) — see TryDetectM2BreakOfStructureOnLastClosedBar. |
//+------------------------------------------------------------------+
bool TryM2WickBreachesSameDirectionLevelForHuntReset()
{
   if(!g_detectOppositeM2FvgHunt)
      return false;

   const double barHigh   = iHigh(_Symbol, PERIOD_M2, 1);
   const double barLow    = iLow(_Symbol, PERIOD_M2, 1);
   const double prevHigh  = iHigh(_Symbol, PERIOD_M2, 2);
   const double prevLow   = iLow(_Symbol, PERIOD_M2, 2);
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(g_m15HighWasBreached)
   {
      if(g_m2Swing.currentSwingLeg.swingDirection == 1)
      {
         if(M2WickCrossesAboveLevel(g_m2Swing.currentSwingLeg.legHighPrice, barHigh, prevHigh, pointSize))
            return true;
      }

      for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
      {
         if(g_m2Swing.swingHistory[historyIndex].swingDirection != 1)
            continue;
         if(M2WickCrossesAboveLevel(g_m2Swing.swingHistory[historyIndex].legHighPrice,
                                    barHigh, prevHigh, pointSize))
            return true;
      }
      return false;
   }

   if(g_m2Swing.currentSwingLeg.swingDirection == -1)
   {
      if(M2WickCrossesBelowLevel(g_m2Swing.currentSwingLeg.legLowPrice, barLow, prevLow, pointSize))
         return true;
   }

   for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m2Swing.swingHistory[historyIndex].swingDirection != -1)
         continue;
      if(M2WickCrossesBelowLevel(g_m2Swing.swingHistory[historyIndex].legLowPrice,
                                 barLow, prevLow, pointSize))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void ApplySameDirectionBosHuntResets()
{
   g_weakPullback                      = 0;
   g_oppositeM2BosCountDuringHunt      = 0;
   g_oppositeFvgFoundDuringHuntCount   = 0;
   g_deferHuntEndUntilNextOppositeBos  = false;
   LogHuntEvent("SAME_DIR_WICK_RESET", "weak=0 oppBOS=0 fvgs=0 defer=N");
}

//+------------------------------------------------------------------+
//| Opposite M2 leg closed with no opposite BOS in that phase → weak.  |
//+------------------------------------------------------------------+
void OnM2SwingLegDirectionChange(const int closingLegDirection, const int nextLegDirection)
{
   if(!g_detectOppositeM2FvgHunt)
      return;

   const int oppositeM2LegDirection = OppositeM2LegDirectionForHunt();

   if(closingLegDirection == oppositeM2LegDirection && !g_sawOppositeBosDuringOppositeM2Phase)
   {
      g_weakPullback = 1;
      LogHuntEvent("WEAK_PULLBACK_ON",
                    StringFormat("closed opp leg dir=%d (no opp BOS in phase)", closingLegDirection));
   }

   if(nextLegDirection == oppositeM2LegDirection)
   {
      g_sawOppositeBosDuringOppositeM2Phase = false;
      LogHuntEvent("OPPOSITE_PHASE_START", StringFormat("new opp leg dir=%d", nextLegDirection));
   }
}

//+------------------------------------------------------------------+
//| Hunt override / fresh arm: session counters only (keep FVG history).|
//+------------------------------------------------------------------+
void ResetCurrentOppositeFvgHuntSession()
{
   g_oppositeFvgFoundDuringHuntCount = 0;
   g_deferHuntEndUntilNextOppositeBos = false;
   ResetWeakPullbackState();
}

//+------------------------------------------------------------------+
//| Same rules as initial hunt arm: latest M15 leg, else 2nd-last.    |
//+------------------------------------------------------------------+
bool TryDetectM15WickLiquidityBreach(const double barHigh, const double barLow,
                                     const double prevHigh, const double prevLow,
                                     const double pointSize, double &outLevel,
                                     bool &outHighBreached, datetime &outLegEndTime)
{
   outLevel        = 0.0;
   outHighBreached = false;
   outLegEndTime   = 0;

   double legHigh = 0.0;
   double legLow  = 0.0;
   datetime legEnd = 0;

   if(TryNthM15CompletedSwingLeg(1, 1, legHigh, legLow, legEnd) &&
      !IsM15LegLiquidityAlreadyBreached(legEnd, true) &&
      M2WickCrossesAboveLevel(M15BreachWickLevelForUpLegHigh(legHigh), barHigh, prevHigh, pointSize))
   {
      outLevel          = legHigh;
      outLegEndTime     = legEnd;
      outHighBreached   = true;
      return true;
   }

   if(TryNthM15CompletedSwingLeg(1, 2, legHigh, legLow, legEnd) &&
      !IsM15LegLiquidityAlreadyBreached(legEnd, true) &&
      M2WickCrossesAboveLevel(M15BreachWickLevelForUpLegHigh(legHigh), barHigh, prevHigh, pointSize) &&
      M15AllowsBearishHuntWhenSecondLastUpHighBreached(pointSize))
   {
      outLevel          = legHigh;
      outLegEndTime     = legEnd;
      outHighBreached   = true;
      return true;
   }

   if(TryNthM15CompletedSwingLeg(-1, 1, legHigh, legLow, legEnd) &&
      !IsM15LegLiquidityAlreadyBreached(legEnd, false) &&
      M2WickCrossesBelowLevel(M15BreachWickLevelForDownLegLow(legLow), barLow, prevLow, pointSize))
   {
      outLevel          = legLow;
      outLegEndTime     = legEnd;
      outHighBreached   = false;
      return true;
   }

   if(TryNthM15CompletedSwingLeg(-1, 2, legHigh, legLow, legEnd) &&
      !IsM15LegLiquidityAlreadyBreached(legEnd, false) &&
      M2WickCrossesBelowLevel(M15BreachWickLevelForDownLegLow(legLow), barLow, prevLow, pointSize) &&
      M15AllowsBullishHuntWhenSecondLastDownLowBreached(pointSize))
   {
      outLevel          = legLow;
      outLegEndTime     = legEnd;
      outHighBreached   = false;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
bool IsDistinctM15BreachFromActiveHunt(const double m15Level, const bool m15HighBreached,
                                       const double pointSize)
{
   if(m15HighBreached != g_m15HighWasBreached)
      return true;
   return (MathAbs(m15Level - g_m15BreachedLegLevelPrice) > pointSize);
}

//+------------------------------------------------------------------+
void ArmOppositeFvgHuntAfterM15Breach(const double m15Level, const bool m15HighBreached,
                                      const datetime breachedLegEndTime,
                                      const double barClose, const double barLow,
                                      const double barHigh, const bool isRestart)
{
   RememberM15LegLiquidityBreach(breachedLegEndTime, m15HighBreached);

   if(isRestart)
   {
      LogHuntEvent("HUNT_RESTART",
                   StringFormat("new M15 %s breach level=%.5f leg=%s (was %s %.5f) → %s FVG hunt",
                                m15HighBreached ? "up high" : "down low", m15Level,
                                TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES),
                                g_m15HighWasBreached ? "high" : "low", g_m15BreachedLegLevelPrice,
                                m15HighBreached ? "bearish" : "bullish"));
      ResetHuntTradeState();
      ResetCurrentOppositeFvgHuntSession();
   }
   else if(m15HighBreached)
      LogHuntEvent("HUNT_ON",
                   StringFormat("M15 up high hunt leg=%.5f wick>=%.5f (−%.1f%% rng) leg=%s → bearish FVG",
                                m15Level, M15BreachWickLevelForUpLegHigh(m15Level),
                                InputM15BreachAnticipationPercentBelowUpHigh,
                                TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES)));
   else
      LogHuntEvent("HUNT_ON",
                   StringFormat("M15 down low hunt leg=%.5f wick<=%.5f (+%.1f%% rng) leg=%s → bullish FVG",
                                m15Level, M15BreachWickLevelForDownLegLow(m15Level),
                                InputM15BreachAnticipationPercentAboveDownLow,
                                TimeToString(breachedLegEndTime, TIME_DATE | TIME_MINUTES)));

   g_detectOppositeM2FvgHunt             = true;
   g_m15HighWasBreached                  = m15HighBreached;
   g_m15BreachedLegLevelPrice            = m15Level;
   g_closeWhenM15LiquidityBreached     = barClose;
   g_pathMinLowSinceM15Breach          = barLow;
   g_pathMaxHighSinceM15Breach         = barHigh;
   g_impulseCloseExtremeSinceM15Breach  = barClose;
   g_m15BreachM2BarOpenTime = iTime(_Symbol, PERIOD_M2, 1);

   if(!isRestart)
      ResetCurrentOppositeFvgHuntSession();
}

//+------------------------------------------------------------------+
//| M15 leg crossed by M2 wick on last closed bar → hunt ON; opposite  |
//| FVG; hunt OFF after opposite FVG + opposite BOS, or second opp.   |
//| BOS if no FVG yet, or opposite BOS then later opposite FVG.        |
//+------------------------------------------------------------------+
void ProcessBosOppositeFairValueGapWindow()
{
   if(!InputEnableOppositeFvgHuntAfterM15Breach)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double barClose  = iClose(_Symbol, PERIOD_M2, 1);
   const double barHigh   = iHigh(_Symbol, PERIOD_M2, 1);
   const double barLow    = iLow(_Symbol, PERIOD_M2, 1);
   const double prevHigh  = iHigh(_Symbol, PERIOD_M2, 2);
   const double prevLow   = iLow(_Symbol, PERIOD_M2, 2);

   if(g_detectOppositeM2FvgHunt)
   {
      double m15Level = 0.0;
      bool m15HighBreached = false;
      datetime breachedLegEndTime = 0;
      if(TryDetectM15WickLiquidityBreach(barHigh, barLow, prevHigh, prevLow, pointSize,
                                         m15Level, m15HighBreached, breachedLegEndTime) &&
         IsDistinctM15BreachFromActiveHunt(m15Level, m15HighBreached, pointSize))
      {
         ArmOppositeFvgHuntAfterM15Breach(m15Level, m15HighBreached, breachedLegEndTime,
                                          barClose, barLow, barHigh, true);
      }
      else
      {
         g_pathMinLowSinceM15Breach  = MathMin(g_pathMinLowSinceM15Breach, barLow);
         g_pathMaxHighSinceM15Breach = MathMax(g_pathMaxHighSinceM15Breach, barHigh);
      }

      if(InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg > 0.0)
      {
         const double referenceHeight = ReferenceChartHeightForFairValueGapFilterM2();
         if(referenceHeight > 0.0)
         {
            const double limitPrice =
               referenceHeight * (InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg / 100.0);
            bool cancelHunt = false;
            if(g_m15HighWasBreached)
            {
               g_impulseCloseExtremeSinceM15Breach =
                  MathMax(g_impulseCloseExtremeSinceM15Breach, barClose);
               if(g_impulseCloseExtremeSinceM15Breach - g_m15BreachedLegLevelPrice > limitPrice)
                  cancelHunt = true;
            }
            else
            {
               g_impulseCloseExtremeSinceM15Breach =
                  MathMin(g_impulseCloseExtremeSinceM15Breach, barClose);
               if(g_m15BreachedLegLevelPrice - g_impulseCloseExtremeSinceM15Breach > limitPrice)
                  cancelHunt = true;
            }
            if(cancelHunt)
            {
               LogHuntEvent("HUNT_OFF", StringFormat("impulse cancel close=%.5f limit=%.5f",
                                                     barClose, limitPrice));
               EndOppositeFvgHuntSession();
               return;
            }
         }
      }

      if(TryM2WickBreachesSameDirectionLevelForHuntReset())
         ApplySameDirectionBosHuntResets();

      bool bosExpectsBullishFairValueGap = false;
      double bosLegIgnored = 0.0;
      if(TryDetectM2BreakOfStructureOnLastClosedBar(bosExpectsBullishFairValueGap, bosLegIgnored))
      {
         const bool oppositeBosClearsHunt =
            (g_m15HighWasBreached && bosExpectsBullishFairValueGap) ||
            (!g_m15HighWasBreached && !bosExpectsBullishFairValueGap);

         if(oppositeBosClearsHunt)
         {
            if(IsCurrentM2LegOppositeToHunt())
            {
               g_sawOppositeBosDuringOppositeM2Phase = true;
               LogHuntEvent("OPP_BOS_IN_PHASE",
                            StringFormat("expectsBullFVG=%s leg=%.5f",
                                         bosExpectsBullishFairValueGap ? "Y" : "N", bosLegIgnored));
            }

            g_oppositeM2BosCountDuringHunt++;

            if(g_oppositeFvgFoundDuringHuntCount > 0)
            {
               LogHuntEvent("HUNT_OFF",
                            StringFormat("opposite BOS + FVG (oppBOS=%d fvgs=%d)",
                                         g_oppositeM2BosCountDuringHunt, g_oppositeFvgFoundDuringHuntCount));
               EndOppositeFvgHuntSession();
               return;
            }
            if(g_oppositeM2BosCountDuringHunt >= 2)
            {
               LogHuntEvent("HUNT_OFF",
                            StringFormat("2nd opposite BOS oppBOS=%d (no FVG)",
                                         g_oppositeM2BosCountDuringHunt));
               EndOppositeFvgHuntSession();
               return;
            }
            if(g_oppositeM2BosCountDuringHunt < 2)
            {
               g_deferHuntEndUntilNextOppositeBos = true;
               LogHuntEvent("OPP_BOS_DEFER",
                            StringFormat("oppBOS=%d defer=Y (no FVG yet)", g_oppositeM2BosCountDuringHunt));
            }
         }
         else
            LogHuntEvent("SAME_DIR_BOS_DETECT",
                         StringFormat("expectsBullFVG=%s (history BOS)", bosExpectsBullishFairValueGap ? "Y" : "N"));
      }

      bool isBullishFairValueGap = false;
      double fairValueGapZoneLowPrice  = 0.0;
      double fairValueGapZoneHighPrice = 0.0;
      if(DetectFairValueGapOnLastClosedBarM2(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                            fairValueGapZoneHighPrice))
      {
         const bool polarityMatchesHunt =
            (g_m15HighWasBreached && !isBullishFairValueGap) ||
            (!g_m15HighWasBreached && isBullishFairValueGap);
         if(polarityMatchesHunt && g_weakPullback != 0)
            LogHuntEvent("FVG_SKIP", StringFormat("weak=1 %s FVG",
                                                  isBullishFairValueGap ? "bull" : "bear"));
         else if(polarityMatchesHunt && g_weakPullback == 0)
         {
            const datetime newestBarOpenTime = iTime(_Symbol, PERIOD_M2, 1);
            const datetime oldestBarOpenTime = iTime(_Symbol, PERIOD_M2, 3);
            if(newestBarOpenTime != 0 && oldestBarOpenTime != 0)
            {
               bool alreadyStored = false;
               for(int memoryIndex = 0; memoryIndex < g_bosOppFvgMemCount; memoryIndex++)
               {
                  if(g_bosOppFvgMem[memoryIndex].fairValueGapBarOpenTime == newestBarOpenTime)
                  {
                     alreadyStored = true;
                     break;
                  }
               }
               if(!alreadyStored &&
                  PushBosOppositeFairValueGapMemory(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                                     fairValueGapZoneHighPrice, newestBarOpenTime,
                                                     g_closeWhenM15LiquidityBreached,
                                                     g_pathMinLowSinceM15Breach, g_pathMaxHighSinceM15Breach))
               {
                  DrawBosMarkedFairValueGapZone(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                               fairValueGapZoneHighPrice, oldestBarOpenTime, newestBarOpenTime);
                  g_oppositeFvgFoundDuringHuntCount++;
                  LogHuntEvent("FVG_MARKED",
                               StringFormat("%s fvgs=%d zone=%.5f-%.5f defer=%s",
                                            isBullishFairValueGap ? "bull" : "bear",
                                            g_oppositeFvgFoundDuringHuntCount,
                                            fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                                            g_deferHuntEndUntilNextOppositeBos ? "Y" : "N"));

                  TryPlaceOppositeFvgTradeSetup(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                                fairValueGapZoneHighPrice, newestBarOpenTime);

                  if(g_deferHuntEndUntilNextOppositeBos)
                  {
                     LogHuntEvent("HUNT_OFF", "opposite FVG after deferred opposite BOS");
                     EndOppositeFvgHuntSession();
                     return;
                  }
               }
            }
         }
      }

      UpdateImpulseCancelBufferZone();
      return;
   }

   double m15Level = 0.0;
   bool m15HighBreached = false;
   datetime breachedLegEndTime = 0;

   if(TryDetectM15WickLiquidityBreach(barHigh, barLow, prevHigh, prevLow, pointSize,
                                      m15Level, m15HighBreached, breachedLegEndTime))
   {
      ArmOppositeFvgHuntAfterM15Breach(m15Level, m15HighBreached, breachedLegEndTime,
                                       barClose, barLow, barHigh, false);
      UpdateImpulseCancelBufferZone();
   }
   else
      ClearImpulseCancelBufferZone();
}

//+------------------------------------------------------------------+
