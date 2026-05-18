//+------------------------------------------------------------------+
//| liquidity_sweep.mq5                                             |
//| M15 swing legs + pool (from plot_swing_m2_copy); M2 swing legs   |
//| (ProcessSwingStepAtShift, live leg, SwingClose) from             |
//| plot_swing_h1_m5_copy.mq5.                                       |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.08"

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
input double InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg = 15.0; // 0=off; % of M2 chart range from breach level
input bool   InputDrawImpulseCancelBufferZone = true;  // hollow rect while hunt ON
input color  InputImpulseCancelBufferColor    = clrDarkOrange;
input int    InputChartRangeBarCount     = 147;
input double InputFairValueGapMinimumPercentOfChartRange = 2.0;
input int    InputMaximumFairValueGapRectangles = 120;
input bool   InputShowLiquidityHuntHud   = true;

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

BosOppositeFairValueGapMemory g_bosOppFvgMem[BosOppositeFairValueGapMemoryCapacity];
int                           g_bosOppFvgMemCount = 0;
int                           g_lqBosMarkedFvgRectangleSequence = 0;

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
                                  double &outLegHigh, double &outLegLow);
bool   M15AllowsBearishHuntWhenSecondLastUpHighBreached(const double pointSize);
bool   M15AllowsBullishHuntWhenSecondLastDownLowBreached(const double pointSize);
bool   M2WickCrossesAboveLevel(const double level, const double barHigh, const double prevHigh,
                               const double pointSize);
bool   M2WickCrossesBelowLevel(const double level, const double barLow, const double prevLow,
                               const double pointSize);
bool   TryDetectM2BreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap, double &outBosLegLevelPrice);
bool   PushBosOppositeFairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                         const double zoneHighPrice, const datetime fairValueGapBarOpenTime,
                                         const double bosBarClosePrice, const double pathMinLowSinceBos,
                                         const double pathMaxHighSinceBos);
void   DrawBosMarkedFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                     const double zoneHighPrice, const datetime leftBarTime,
                                     const datetime rightBarTime);
void   ProcessBosOppositeFairValueGapWindow();
void   ClearImpulseCancelBufferZone();
void   UpdateImpulseCancelBufferZone();

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
   g_bosOppFvgMemCount                = 0;
   g_lqBosMarkedFvgRectangleSequence  = 0;

   WarmupM15SwingFromHistory();
   WarmupM2SwingFromHistory();

   g_lastM15BarOpen = iTime(_Symbol, PERIOD_M15, 0);
   g_lastM2BarOpen  = iTime(_Symbol, PERIOD_M2, 0);
   if(g_lastM2BarOpen == 0)
      Print("liquidity_sweep: PERIOD_M2 iTime(0)==0 — symbol may not provide M2 bars.");

   RefreshLiquidityHuntHud();

   ChartRedraw(0);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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
void OnTick()
{
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
      ProcessM2SwingStep();
      if(InputEnableOppositeFvgHuntAfterM15Breach)
         ProcessBosOppositeFairValueGapWindow();
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
   const double lastClosedBarRange = lastClosedBarHigh - lastClosedBarLow;

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
      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

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
      ? StringFormat("M15 breach → opp.M2 FVG hunt: ON  (fvgs=%d defer=%s)",
                     g_oppositeFvgFoundDuringHuntCount, g_deferHuntEndUntilNextOppositeBos ? "Y" : "N")
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
                              double &outLegHigh, double &outLegLow)
{
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
         outLegHigh = g_m15Swing.swingHistory[i].legHighPrice;
         outLegLow  = g_m15Swing.swingHistory[i].legLowPrice;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| 2nd-last up high breached → bearish hunt only if older down leg     |
//| high > latest down leg high (lower high on the more recent down).  |
//+------------------------------------------------------------------+
bool M15AllowsBearishHuntWhenSecondLastUpHighBreached(const double pointSize)
{
   double latestDownHigh     = 0.0;
   double latestDownLow      = 0.0;
   double secondLastDownHigh = 0.0;
   double secondLastDownLow  = 0.0;
   if(!TryNthM15CompletedSwingLeg(-1, 1, latestDownHigh, latestDownLow))
      return false;
   if(!TryNthM15CompletedSwingLeg(-1, 2, secondLastDownHigh, secondLastDownLow))
      return false;
   return (secondLastDownHigh > latestDownHigh + pointSize);
}

//+------------------------------------------------------------------+
//| 2nd-last down low breached → bullish hunt only if older up leg low  |
//| < latest up leg low (higher low on the more recent up).            |
//+------------------------------------------------------------------+
bool M15AllowsBullishHuntWhenSecondLastDownLowBreached(const double pointSize)
{
   double latestUpHigh     = 0.0;
   double latestUpLow      = 0.0;
   double secondLastUpHigh = 0.0;
   double secondLastUpLow  = 0.0;
   if(!TryNthM15CompletedSwingLeg(1, 1, latestUpHigh, latestUpLow))
      return false;
   if(!TryNthM15CompletedSwingLeg(1, 2, secondLastUpHigh, secondLastUpLow))
      return false;
   return (secondLastUpLow < latestUpLow - pointSize);
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
      g_pathMinLowSinceM15Breach  = MathMin(g_pathMinLowSinceM15Breach, barLow);
      g_pathMaxHighSinceM15Breach = MathMax(g_pathMaxHighSinceM15Breach, barHigh);

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
               g_detectOppositeM2FvgHunt            = false;
               g_m15BreachM2BarOpenTime            = 0;
               g_oppositeFvgFoundDuringHuntCount  = 0;
               g_deferHuntEndUntilNextOppositeBos = false;
               ClearImpulseCancelBufferZone();
               return;
            }
         }
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
         if(polarityMatchesHunt)
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

                  if(g_deferHuntEndUntilNextOppositeBos)
                  {
                     g_detectOppositeM2FvgHunt            = false;
                     g_m15BreachM2BarOpenTime            = 0;
                     g_oppositeFvgFoundDuringHuntCount  = 0;
                     g_deferHuntEndUntilNextOppositeBos = false;
                     ClearImpulseCancelBufferZone();
                     return;
                  }
               }
            }
         }
      }

      bool bosExpectsBullishFairValueGap = false;
      double bosLegIgnored = 0.0;
      if(TryDetectM2BreakOfStructureOnLastClosedBar(bosExpectsBullishFairValueGap, bosLegIgnored))
      {
         const bool oppositeBosClearsHunt =
            (g_m15HighWasBreached && bosExpectsBullishFairValueGap) ||
            (!g_m15HighWasBreached && !bosExpectsBullishFairValueGap);
         if(oppositeBosClearsHunt)
         {
            if(g_oppositeFvgFoundDuringHuntCount > 0)
            {
               g_detectOppositeM2FvgHunt            = false;
               g_m15BreachM2BarOpenTime            = 0;
               g_oppositeFvgFoundDuringHuntCount  = 0;
               g_deferHuntEndUntilNextOppositeBos = false;
               ClearImpulseCancelBufferZone();
               return;
            }
            if(!g_deferHuntEndUntilNextOppositeBos)
               g_deferHuntEndUntilNextOppositeBos = true;
            else
            {
               g_detectOppositeM2FvgHunt            = false;
               g_m15BreachM2BarOpenTime            = 0;
               g_oppositeFvgFoundDuringHuntCount  = 0;
               g_deferHuntEndUntilNextOppositeBos = false;
               ClearImpulseCancelBufferZone();
               return;
            }
         }
      }
      UpdateImpulseCancelBufferZone();
      return;
   }

   double m15Level = 0.0;
   bool m15HighBreached = false;

   if(TryLatestM15CompletedUpLegHigh(m15Level) &&
      M2WickCrossesAboveLevel(m15Level, barHigh, prevHigh, pointSize))
   {
      m15HighBreached = true;
   }
   else if(TrySecondLastM15CompletedUpLegHigh(m15Level) &&
           M2WickCrossesAboveLevel(m15Level, barHigh, prevHigh, pointSize) &&
           M15AllowsBearishHuntWhenSecondLastUpHighBreached(pointSize))
   {
      m15HighBreached = true;
   }

   if(m15HighBreached)
   {
      g_detectOppositeM2FvgHunt            = true;
      g_m15HighWasBreached                 = true;
      g_m15BreachedLegLevelPrice           = m15Level;
      g_closeWhenM15LiquidityBreached    = barClose;
      g_pathMinLowSinceM15Breach         = barLow;
      g_pathMaxHighSinceM15Breach        = barHigh;
      g_impulseCloseExtremeSinceM15Breach = barClose;
      g_m15BreachM2BarOpenTime            = iTime(_Symbol, PERIOD_M2, 1);
      g_oppositeFvgFoundDuringHuntCount  = 0;
      g_deferHuntEndUntilNextOppositeBos = false;
      UpdateImpulseCancelBufferZone();
      return;
   }

   bool m15LowBreached = false;

   if(TryLatestM15CompletedDownLegLow(m15Level) &&
      M2WickCrossesBelowLevel(m15Level, barLow, prevLow, pointSize))
   {
      m15LowBreached = true;
   }
   else if(TrySecondLastM15CompletedDownLegLow(m15Level) &&
           M2WickCrossesBelowLevel(m15Level, barLow, prevLow, pointSize) &&
           M15AllowsBullishHuntWhenSecondLastDownLowBreached(pointSize))
   {
      m15LowBreached = true;
   }

   if(m15LowBreached)
   {
      g_detectOppositeM2FvgHunt            = true;
      g_m15HighWasBreached                 = false;
      g_m15BreachedLegLevelPrice           = m15Level;
      g_closeWhenM15LiquidityBreached    = barClose;
      g_pathMinLowSinceM15Breach         = barLow;
      g_pathMaxHighSinceM15Breach        = barHigh;
      g_impulseCloseExtremeSinceM15Breach = barClose;
      g_m15BreachM2BarOpenTime            = iTime(_Symbol, PERIOD_M2, 1);
      g_oppositeFvgFoundDuringHuntCount  = 0;
      g_deferHuntEndUntilNextOppositeBos = false;
      UpdateImpulseCancelBufferZone();
   }
   else
      ClearImpulseCancelBufferZone();
}

//+------------------------------------------------------------------+
