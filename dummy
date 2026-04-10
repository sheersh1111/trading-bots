//+------------------------------------------------------------------+
//| plot_swing_m2.mq5                                                |
//| M2 swings + BOS opposite FVG (countdown) + optional trade         |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.14"

#include <Trade\Trade.mqh>

CTrade tradeLayer;

const ENUM_TIMEFRAMES SwingTimeframe = PERIOD_M2;

input bool InputSwitchChartToMinuteTwo = true;   // Set chart period to M2 on attach
input bool InputDrawSwingLegVisuals = false;      // Swing leg OBJ_TREND + High/Low labels (off)

input group "BOS opposite FVG (M2: bar 1 vs bar 3)"
input bool InputDrawBosOppositeFairValueGapZones = true; // Rectangles for BOS-qualified FVG only
input double InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg = 15.0; // Cancel FVG watch if close exceeds this % of chart height past broken leg (0 = off)
input int  InputChartRangeBarCount = 147;        // Bars for chart height (FVG min-gap filter)
input double InputFairValueGapMinimumPercentOfChartRange = 2.0; // Min gap as % of height (0 = off)
input int  InputMaximumFairValueGapRectangles = 120;

input group "FVG trade (M2)"
input bool   InputEnableAutomatedTrading = false;  // Send market/limit orders (false = log only)
input ulong  InputExpertMagicNumber = 940031;
input double InputRiskUsdPerPosition = 50.0;       // USD risk each for 2R and 3R position

// --- swing structs (detect_swing logic) ---
struct Swing
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection; // 1 = up, -1 = down, 0 = unset
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
   bool   isSupplyPool; // true = resistance / supply, false = demand
};

#define LiquidityPoolCapacity 32

struct BosOppositeFairValueGapMemory
{
   bool     isBullishFairValueGap;
   double   fairValueGapZoneLowPrice;
   double   fairValueGapZoneHighPrice;
   datetime fairValueGapBarOpenTime;
};

#define BosOppositeFairValueGapMemoryCapacity 32

struct BosOppositeFvgWatch
{
   int      counter;
   bool     expectsBullishFairValueGap; // true = expect bullish FVG (after bearish BOS)
   bool     skipDecrementOnce;          // no countdown tick on the bar where BOS was detected
   double   bosLegLevelPrice;           // broken swing high (bull BOS) or low (bear BOS)
   double   maxCloseSinceBos;           // bull BOS: running max close vs leg high (impulse filter)
   double   minCloseSinceBos;         // bear BOS: running min close vs leg low (impulse filter)
};

#define BosOppositeFvgWatchCapacity 32

SwingState     globalSwingState;
LiquidityPool  globalLiquidityPools[LiquidityPoolCapacity];
int            globalLiquidityPoolCount = 0;

datetime globalLastSwingTimeframeBarOpenTime = 0;
int      globalBosMarkedFairValueGapRectangleSequence = 0;
datetime globalLastProcessedFairValueGapTradeBarTime = 0;

BosOppositeFvgWatch globalBosOppositeFvgWatchList[BosOppositeFvgWatchCapacity];
int                   globalBosOppositeFvgWatchCount = 0;

BosOppositeFairValueGapMemory globalBosOppositeFairValueGapMemory[BosOppositeFairValueGapMemoryCapacity];
int                           globalBosOppositeFairValueGapMemoryCount = 0;

const string ChartObjectNamePrefixSwingTrendLine = "M2_Swing_";
const string ChartObjectNamePrefixSwingLabelText = "M2_SWLBL_";
const string ChartObjectNamePrefixBosMarkedFairValueGap = "M2_FVG_BOS_";

void   ProcessSwingStep(SwingState &swingState, const ENUM_TIMEFRAMES timeframe);
void   SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                     const double highPrice, const double lowPrice);
void   SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice);
void   SwingClose(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                  const string chartObjectNamePrefix);
void   DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                         const double labelPrice, const bool isUplegSwingDirection);

void   PushLiquidityPoolFromClosedSwing(const double poolLowPrice, const double poolHighPrice,
                                        const bool isSupplyPool);

double ReferenceChartHeightForFairValueGapFilter(const ENUM_TIMEFRAMES timeframe);
bool   FairValueGapGapMeetsMinimumPercentOfRange(const ENUM_TIMEFRAMES timeframe,
                                                 const double zoneLowPrice, const double zoneHighPrice);
bool   DetectFairValueGapOnLastClosedBar(bool &isBullishFairValueGap, double &fairValueGapZoneLowPrice,
                                       double &fairValueGapZoneHighPrice);
bool   TryDetectBreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap,
                                               double &outBosLegLevelPrice);
void   RemoveBosOppositeFvgWatchAt(const int removeIndex);
void   PushBosOppositeFvgWatch(const bool expectsBullishFairValueGap, const double bosLegLevelPrice);
bool   HasAnyActiveBosOppositeFvgWatch();
int    FindFirstMatchingBosFvgWatchIndex(const bool isBullishFairValueGap);
void   ProcessBosOppositeFvgWatchDecrements();
void   ProcessBosOppositeFvgWatchImpulseInvalidation();
void   ProcessBosOppositeFairValueGapWindow();
void   PushBosOppositeFairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                        const double zoneHighPrice, const datetime fairValueGapBarOpenTime);
void   DrawBosMarkedFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                     const double zoneHighPrice, const datetime leftBarTime,
                                     const datetime rightBarTime);
bool   GetBosOppositeFairValueGapFromMemoryForBarOpenTime(const datetime barOpenTime,
                                                        bool &outIsBullishFairValueGap,
                                                        double &outZoneLowPrice,
                                                        double &outZoneHighPrice);

double CalculateVolumeForFixedUsdRisk(const ENUM_ORDER_TYPE orderType, const double entryPrice,
                                        const double stopLossPrice, const double riskUsd);
void   ApplyTradeFillingModeFromSymbol();
bool   StopsDistanceAllowed(const bool isBuy, const double entryPrice, const double stopLossPrice,
                            const double takeProfitPrice);

void   TryExecuteFairValueGapTradePlan();

//+------------------------------------------------------------------+
int OnInit()
{
   tradeLayer.SetExpertMagicNumber(InputExpertMagicNumber);

   if(InputSwitchChartToMinuteTwo)
   {
      ChartSetSymbolPeriod(0, _Symbol, SwingTimeframe);
      ChartRedraw(0);
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("plot_swing_m2: enable AutoTrading in terminal to send orders.");
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      Print("plot_swing_m2: trading not allowed for this EA (Common / account).");

   ObjectsDeleteAll(0, "M2_SWEEP_", -1, -1);
   ObjectsDeleteAll(0, "M2_FVG_", -1, -1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int deinitializationReason)
{
   ObjectsDeleteAll(0, ChartObjectNamePrefixSwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixSwingLabelText, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixBosMarkedFairValueGap, -1, -1);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnTick()
{
   const datetime currentBarOpenTime = iTime(_Symbol, SwingTimeframe, 0);
   if(currentBarOpenTime == globalLastSwingTimeframeBarOpenTime)
      return;

   globalLastSwingTimeframeBarOpenTime = currentBarOpenTime;
   ProcessSwingStep(globalSwingState, SwingTimeframe);
   ProcessBosOppositeFairValueGapWindow();
   TryExecuteFairValueGapTradePlan();
}

//+------------------------------------------------------------------+
void PushLiquidityPoolFromClosedSwing(const double poolLowPrice, const double poolHighPrice,
                                      const bool isSupplyPool)
{
   if(poolLowPrice >= poolHighPrice)
      return;

   if(globalLiquidityPoolCount < LiquidityPoolCapacity)
   {
      globalLiquidityPools[globalLiquidityPoolCount].poolLowPrice  = poolLowPrice;
      globalLiquidityPools[globalLiquidityPoolCount].poolHighPrice = poolHighPrice;
      globalLiquidityPools[globalLiquidityPoolCount].isSupplyPool   = isSupplyPool;
      globalLiquidityPoolCount++;
   }
   else
   {
      for(int poolShiftIndex = 1; poolShiftIndex < LiquidityPoolCapacity; poolShiftIndex++)
         globalLiquidityPools[poolShiftIndex - 1] = globalLiquidityPools[poolShiftIndex];
      globalLiquidityPools[LiquidityPoolCapacity - 1].poolLowPrice  = poolLowPrice;
      globalLiquidityPools[LiquidityPoolCapacity - 1].poolHighPrice = poolHighPrice;
      globalLiquidityPools[LiquidityPoolCapacity - 1].isSupplyPool  = isSupplyPool;
   }
}

//+------------------------------------------------------------------+
void ProcessSwingStep(SwingState &swingState, const ENUM_TIMEFRAMES timeframe)
{
   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, 1);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, 1);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, 1);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, 1);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);
   const double lastClosedBarRange = lastClosedBarHigh - lastClosedBarLow;

   if(swingState.currentSwingLeg.swingDirection == 0)
   {
      SwingStartNew(swingState, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      return;
   }

   double sumRangeTenPriorBars = 0.0;
   for(int barShiftIndex = 2; barShiftIndex <= 11; barShiftIndex++)
      sumRangeTenPriorBars +=
         (iHigh(_Symbol, timeframe, barShiftIndex) - iLow(_Symbol, timeframe, barShiftIndex));
   const double averageRangeTenBars = sumRangeTenPriorBars / 10.0;

   const bool isDecentMovement = (lastClosedBarRange > (averageRangeTenBars * 1.0));
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
   }
   else
   {
      const color  swingLineColor = clrYellow;
      const string chartObjectNamePrefix = ChartObjectNamePrefixSwingTrendLine;
      SwingClose(swingState, timeframe, swingLineColor, chartObjectNamePrefix);

      Swing closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
      double newSwingLegHigh = lastClosedBarHigh;
      double newSwingLegLow  = lastClosedBarLow;
      if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
         newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
      else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
         newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

      SwingStartNew(swingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
   }
}

//+------------------------------------------------------------------+
void SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                   const double highPrice, const double lowPrice)
{
   swingState.currentSwingLeg.swingDirection = swingDirection;
   swingState.currentSwingLeg.legHighPrice   = highPrice;
   swingState.currentSwingLeg.legLowPrice    = lowPrice;
   swingState.currentSwingLeg.legStartTime   = iTime(_Symbol, timeframe, 1);
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
void SwingClose(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                const string chartObjectNamePrefix)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, 1);

   const double poolLowPrice  = swingState.currentSwingLeg.legLowPrice;
   const double poolHighPrice = swingState.currentSwingLeg.legHighPrice;
   const bool   isSupplyPool  = (swingState.currentSwingLeg.swingDirection == 1);
   PushLiquidityPoolFromClosedSwing(poolLowPrice, poolHighPrice, isSupplyPool);

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

   if(InputDrawSwingLegVisuals)
   {
      if(ObjectCreate(0, chartObjectName, OBJ_TREND, 0, swingState.currentSwingLeg.legStartTime,
                      trendLineStartPrice, swingState.currentSwingLeg.legEndTime, trendLineEndPrice))
      {
         ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, swingLineColor);
         ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, chartObjectName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
      }

      const bool isUplegSwingDirection = (swingState.currentSwingLeg.swingDirection == 1);
      DrawSwingLegLabel(ChartObjectNamePrefixSwingLabelText, swingState.currentSwingLeg.legEndTime,
                        trendLineEndPrice, isUplegSwingDirection);
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
void DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                       const double labelPrice, const bool isUplegSwingDirection)
{
   const string chartObjectName = chartObjectNamePrefix + IntegerToString((long)labelBarTime);
   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);

   const double symbolPointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double labelVerticalOffset =
      isUplegSwingDirection ? (labelPrice + symbolPointSize * 8.0) : (labelPrice - symbolPointSize * 8.0);

   if(!ObjectCreate(0, chartObjectName, OBJ_TEXT, 0, labelBarTime, labelVerticalOffset))
      return;

   ObjectSetString(0, chartObjectName, OBJPROP_TEXT, isUplegSwingDirection ? "High" : "Low");
   ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, isUplegSwingDirection ? clrDodgerBlue : clrOrange);
   ObjectSetInteger(0, chartObjectName, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, chartObjectName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, chartObjectName, OBJPROP_ANCHOR,
                    isUplegSwingDirection ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForFairValueGapFilter(const ENUM_TIMEFRAMES timeframe)
{
   const int barCount = InputChartRangeBarCount;
   if(barCount < 1)
      return 0.0;

   const int totalBars = iBars(_Symbol, timeframe);
   if(totalBars < barCount + 1)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = 1; barShiftIndex <= barCount; barShiftIndex++)
   {
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, timeframe, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, timeframe, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

//+------------------------------------------------------------------+
bool FairValueGapGapMeetsMinimumPercentOfRange(const ENUM_TIMEFRAMES timeframe,
                                               const double zoneLowPrice, const double zoneHighPrice)
{
   if(InputFairValueGapMinimumPercentOfChartRange <= 0.0)
      return true;

   const double gapSize = MathAbs(zoneHighPrice - zoneLowPrice);
   if(gapSize <= 0.0)
      return false;

   const double referenceHeight = ReferenceChartHeightForFairValueGapFilter(timeframe);
   if(referenceHeight <= 0.0)
      return true;

   return (gapSize >= referenceHeight * (InputFairValueGapMinimumPercentOfChartRange / 100.0));
}

//+------------------------------------------------------------------+
bool DetectFairValueGapOnLastClosedBar(bool &isBullishFairValueGap, double &fairValueGapZoneLowPrice,
                                       double &fairValueGapZoneHighPrice)
{
   isBullishFairValueGap = false;
   fairValueGapZoneLowPrice  = 0.0;
   fairValueGapZoneHighPrice = 0.0;

   const double lastClosedBarHigh = iHigh(_Symbol, SwingTimeframe, 1);
   const double lastClosedBarLow  = iLow(_Symbol, SwingTimeframe, 1);
   const double thirdBarHigh      = iHigh(_Symbol, SwingTimeframe, 3);
   const double thirdBarLow       = iLow(_Symbol, SwingTimeframe, 3);

   if(lastClosedBarLow > thirdBarHigh)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfRange(SwingTimeframe, thirdBarHigh, lastClosedBarLow))
         return false;
      isBullishFairValueGap = true;
      fairValueGapZoneLowPrice  = thirdBarHigh;
      fairValueGapZoneHighPrice = lastClosedBarLow;
      return true;
   }

   if(lastClosedBarHigh < thirdBarLow)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfRange(SwingTimeframe, lastClosedBarHigh, thirdBarLow))
         return false;
      isBullishFairValueGap = false;
      fairValueGapZoneLowPrice  = lastClosedBarHigh;
      fairValueGapZoneHighPrice = thirdBarLow;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Bullish BOS: wick (high) crosses above the latest completed up-leg high only.|
//| Bearish BOS: wick (low) crosses below the latest completed down-leg low only.|
//| Each BOS queues its own opposite-FVG countdown (see PushBosOppositeFvgWatch). |
//+------------------------------------------------------------------+
bool TryDetectBreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap,
                                             double &outBosLegLevelPrice)
{
   outExpectsBullishFairValueGap = false;
   outBosLegLevelPrice = 0.0;
   if(globalSwingState.swingHistoryCount < 1)
      return false;

   const double highPrice  = iHigh(_Symbol, SwingTimeframe, 1);
   const double prevHigh   = iHigh(_Symbol, SwingTimeframe, 2);
   const double lowPrice   = iLow(_Symbol, SwingTimeframe, 1);
   const double prevLow    = iLow(_Symbol, SwingTimeframe, 2);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int historyIndex = globalSwingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(globalSwingState.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double swingLegHighPrice = globalSwingState.swingHistory[historyIndex].legHighPrice;
      if(highPrice > swingLegHighPrice + pointSize && prevHigh <= swingLegHighPrice + pointSize)
      {
         outExpectsBullishFairValueGap = false;
         outBosLegLevelPrice           = swingLegHighPrice;
         return true;
      }
      break;
   }

   for(int historyIndex = globalSwingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(globalSwingState.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double swingLegLowPrice = globalSwingState.swingHistory[historyIndex].legLowPrice;
      if(lowPrice < swingLegLowPrice - pointSize && prevLow >= swingLegLowPrice - pointSize)
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
void RemoveBosOppositeFvgWatchAt(const int removeIndex)
{
   if(removeIndex < 0 || removeIndex >= globalBosOppositeFvgWatchCount)
      return;
   for(int j = removeIndex + 1; j < globalBosOppositeFvgWatchCount; j++)
      globalBosOppositeFvgWatchList[j - 1] = globalBosOppositeFvgWatchList[j];
   globalBosOppositeFvgWatchCount--;
}

//+------------------------------------------------------------------+
void PushBosOppositeFvgWatch(const bool expectsBullishFairValueGap, const double bosLegLevelPrice)
{
   if(globalBosOppositeFvgWatchCount >= BosOppositeFvgWatchCapacity)
      RemoveBosOppositeFvgWatchAt(0);

   const double barClose = iClose(_Symbol, SwingTimeframe, 1);

   const int index = globalBosOppositeFvgWatchCount;
   globalBosOppositeFvgWatchList[index].counter                    = 4;
   globalBosOppositeFvgWatchList[index].expectsBullishFairValueGap = expectsBullishFairValueGap;
   globalBosOppositeFvgWatchList[index].skipDecrementOnce          = true;
   globalBosOppositeFvgWatchList[index].bosLegLevelPrice           = bosLegLevelPrice;
   if(expectsBullishFairValueGap)
   {
      globalBosOppositeFvgWatchList[index].minCloseSinceBos = barClose;
      globalBosOppositeFvgWatchList[index].maxCloseSinceBos = 0.0;
   }
   else
   {
      globalBosOppositeFvgWatchList[index].maxCloseSinceBos = barClose;
      globalBosOppositeFvgWatchList[index].minCloseSinceBos = 0.0;
   }
   globalBosOppositeFvgWatchCount++;
}

//+------------------------------------------------------------------+
bool HasAnyActiveBosOppositeFvgWatch()
{
   for(int i = 0; i < globalBosOppositeFvgWatchCount; i++)
   {
      if(globalBosOppositeFvgWatchList[i].counter > 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int FindFirstMatchingBosFvgWatchIndex(const bool isBullishFairValueGap)
{
   for(int i = 0; i < globalBosOppositeFvgWatchCount; i++)
   {
      if(globalBosOppositeFvgWatchList[i].counter <= 0)
         continue;
      const bool expectsBullish = globalBosOppositeFvgWatchList[i].expectsBullishFairValueGap;
      if((expectsBullish && isBullishFairValueGap) || (!expectsBullish && !isBullishFairValueGap))
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
void ProcessBosOppositeFvgWatchDecrements()
{
   for(int i = 0; i < globalBosOppositeFvgWatchCount; i++)
   {
      if(globalBosOppositeFvgWatchList[i].skipDecrementOnce)
      {
         globalBosOppositeFvgWatchList[i].skipDecrementOnce = false;
         continue;
      }
      if(globalBosOppositeFvgWatchList[i].counter > 0)
      {
         globalBosOppositeFvgWatchList[i].counter--;
         if(globalBosOppositeFvgWatchList[i].counter <= 0)
         {
            RemoveBosOppositeFvgWatchAt(i);
            i--;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Drop BOS–FVG watches if close moves more than X% of chart height past the broken leg.|
//| Bull BOS: invalidate when max(close) − legHigh > limit. Bear BOS: legLow − min(close) > limit.|
//+------------------------------------------------------------------+
void ProcessBosOppositeFvgWatchImpulseInvalidation()
{
   if(InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg <= 0.0)
      return;

   const double referenceHeight = ReferenceChartHeightForFairValueGapFilter(SwingTimeframe);
   if(referenceHeight <= 0.0)
      return;

   const double limitPrice =
      referenceHeight * (InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg / 100.0);
   const double barClose = iClose(_Symbol, SwingTimeframe, 1);

   for(int i = 0; i < globalBosOppositeFvgWatchCount; i++)
   {
      if(globalBosOppositeFvgWatchList[i].counter <= 0)
         continue;

      if(globalBosOppositeFvgWatchList[i].expectsBullishFairValueGap)
      {
         globalBosOppositeFvgWatchList[i].minCloseSinceBos =
            MathMin(globalBosOppositeFvgWatchList[i].minCloseSinceBos, barClose);
         const double impulse =
            globalBosOppositeFvgWatchList[i].bosLegLevelPrice - globalBosOppositeFvgWatchList[i].minCloseSinceBos;
         if(impulse > limitPrice)
         {
            RemoveBosOppositeFvgWatchAt(i);
            i--;
         }
      }
      else
      {
         globalBosOppositeFvgWatchList[i].maxCloseSinceBos =
            MathMax(globalBosOppositeFvgWatchList[i].maxCloseSinceBos, barClose);
         const double impulse =
            globalBosOppositeFvgWatchList[i].maxCloseSinceBos - globalBosOppositeFvgWatchList[i].bosLegLevelPrice;
         if(impulse > limitPrice)
         {
            RemoveBosOppositeFvgWatchAt(i);
            i--;
         }
      }
   }
}

//+------------------------------------------------------------------+
void PushBosOppositeFairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                     const double zoneHighPrice, const datetime fairValueGapBarOpenTime)
{
   for(int memoryIndex = 0; memoryIndex < globalBosOppositeFairValueGapMemoryCount; memoryIndex++)
   {
      if(globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapBarOpenTime == fairValueGapBarOpenTime)
         return;
   }

   if(globalBosOppositeFairValueGapMemoryCount < BosOppositeFairValueGapMemoryCapacity)
   {
      const int index = globalBosOppositeFairValueGapMemoryCount;
      globalBosOppositeFairValueGapMemory[index].isBullishFairValueGap   = isBullishFairValueGap;
      globalBosOppositeFairValueGapMemory[index].fairValueGapZoneLowPrice  = zoneLowPrice;
      globalBosOppositeFairValueGapMemory[index].fairValueGapZoneHighPrice = zoneHighPrice;
      globalBosOppositeFairValueGapMemory[index].fairValueGapBarOpenTime  = fairValueGapBarOpenTime;
      globalBosOppositeFairValueGapMemoryCount++;
      return;
   }

   for(int shiftIndex = 1; shiftIndex < BosOppositeFairValueGapMemoryCapacity; shiftIndex++)
      globalBosOppositeFairValueGapMemory[shiftIndex - 1] = globalBosOppositeFairValueGapMemory[shiftIndex];

   const int lastIndex = BosOppositeFairValueGapMemoryCapacity - 1;
   globalBosOppositeFairValueGapMemory[lastIndex].isBullishFairValueGap   = isBullishFairValueGap;
   globalBosOppositeFairValueGapMemory[lastIndex].fairValueGapZoneLowPrice  = zoneLowPrice;
   globalBosOppositeFairValueGapMemory[lastIndex].fairValueGapZoneHighPrice = zoneHighPrice;
   globalBosOppositeFairValueGapMemory[lastIndex].fairValueGapBarOpenTime  = fairValueGapBarOpenTime;
}

//+------------------------------------------------------------------+
void DrawBosMarkedFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                   const double zoneHighPrice, const datetime leftBarTime,
                                   const datetime rightBarTime)
{
   if(!InputDrawBosOppositeFairValueGapZones)
      return;

   globalBosMarkedFairValueGapRectangleSequence++;
   const string chartObjectName =
      ChartObjectNamePrefixBosMarkedFairValueGap +
      IntegerToString(globalBosMarkedFairValueGapRectangleSequence);
   if(globalBosMarkedFairValueGapRectangleSequence > InputMaximumFairValueGapRectangles)
   {
      const string oldRectangleName =
         ChartObjectNamePrefixBosMarkedFairValueGap +
         IntegerToString(globalBosMarkedFairValueGapRectangleSequence - InputMaximumFairValueGapRectangles);
      ObjectDelete(0, oldRectangleName);
   }

   const datetime rectangleTimeLeft  = (leftBarTime <= rightBarTime) ? leftBarTime : rightBarTime;
   const datetime rectangleTimeRight = (leftBarTime <= rightBarTime) ? rightBarTime : leftBarTime;
   const double rectanglePriceLow    = MathMin(zoneLowPrice, zoneHighPrice);
   const double rectanglePriceHigh   = MathMax(zoneLowPrice, zoneHighPrice);

   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);

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
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void ProcessBosOppositeFairValueGapWindow()
{
   bool   expectsBullishFairValueGapFromBreakOfStructure;
   double bosLegLevelPriceFromBreakOfStructure;
   if(TryDetectBreakOfStructureOnLastClosedBar(expectsBullishFairValueGapFromBreakOfStructure,
                                               bosLegLevelPriceFromBreakOfStructure))
      PushBosOppositeFvgWatch(expectsBullishFairValueGapFromBreakOfStructure,
                               bosLegLevelPriceFromBreakOfStructure);

   ProcessBosOppositeFvgWatchImpulseInvalidation();

   if(!HasAnyActiveBosOppositeFvgWatch())
      return;

   bool isBullishFairValueGap;
   double fairValueGapZoneLowPrice;
   double fairValueGapZoneHighPrice;
   if(DetectFairValueGapOnLastClosedBar(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                        fairValueGapZoneHighPrice))
   {
      const int matchingWatchIndex = FindFirstMatchingBosFvgWatchIndex(isBullishFairValueGap);
      if(matchingWatchIndex >= 0)
      {
         const datetime lastClosedBarOpenTime = iTime(_Symbol, SwingTimeframe, 1);
         const datetime thirdBarOpenTime      = iTime(_Symbol, SwingTimeframe, 3);

         PushBosOppositeFairValueGapMemory(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                           fairValueGapZoneHighPrice, lastClosedBarOpenTime);
         DrawBosMarkedFairValueGapZone(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                       fairValueGapZoneHighPrice, thirdBarOpenTime, lastClosedBarOpenTime);
         RemoveBosOppositeFvgWatchAt(matchingWatchIndex);
      }
   }

   ProcessBosOppositeFvgWatchDecrements();
}

//+------------------------------------------------------------------+
bool GetBosOppositeFairValueGapFromMemoryForBarOpenTime(const datetime barOpenTime,
                                                        bool &outIsBullishFairValueGap,
                                                        double &outZoneLowPrice,
                                                        double &outZoneHighPrice)
{
   for(int memoryIndex = globalBosOppositeFairValueGapMemoryCount - 1; memoryIndex >= 0; memoryIndex--)
   {
      if(globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapBarOpenTime != barOpenTime)
         continue;

      outIsBullishFairValueGap = globalBosOppositeFairValueGapMemory[memoryIndex].isBullishFairValueGap;
      outZoneLowPrice        = globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapZoneLowPrice;
      outZoneHighPrice       = globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapZoneHighPrice;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void ApplyTradeFillingModeFromSymbol()
{
   const long fillingMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(fillingMode == 0)
      return;
   if((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      tradeLayer.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      tradeLayer.SetTypeFilling(ORDER_FILLING_IOC);
   else
      tradeLayer.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
double CalculateVolumeForFixedUsdRisk(const ENUM_ORDER_TYPE orderType, const double entryPrice,
                                      const double stopLossPrice, const double riskUsd)
{
   double profitAtStop = 0.0;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entryPrice, stopLossPrice, profitAtStop))
      return 0.0;

   const double lossPerLot = (profitAtStop < 0.0) ? -profitAtStop : profitAtStop;
   if(lossPerLot <= 0.0)
      return 0.0;

   double volume = riskUsd / lossPerLot;
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
void TryExecuteFairValueGapTradePlan()
{
   const datetime fairValueGapBarOpenTime = iTime(_Symbol, SwingTimeframe, 1);
   if(fairValueGapBarOpenTime == globalLastProcessedFairValueGapTradeBarTime)
      return;

   bool isBullishFairValueGap;
   double fairValueGapZoneLowPrice;
   double fairValueGapZoneHighPrice;
   if(!GetBosOppositeFairValueGapFromMemoryForBarOpenTime(fairValueGapBarOpenTime, isBullishFairValueGap,
                                                          fairValueGapZoneLowPrice,
                                                          fairValueGapZoneHighPrice))
      return;

   const double higherEndOfFairValueGap =
      MathMax(fairValueGapZoneLowPrice, fairValueGapZoneHighPrice);
   const double lowerEndOfFairValueGap =
      MathMin(fairValueGapZoneLowPrice, fairValueGapZoneHighPrice);

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double       stopLossPrice;
   if(isBullishFairValueGap)
      stopLossPrice = lowerEndOfFairValueGap - pointSize;
   else
      stopLossPrice = higherEndOfFairValueGap + pointSize;

   const double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   bool   useMarketOrder = false;
   double entryPrice     = 0.0;

   // BOS opposite FVG only. Long: bid inside gap -> market @ ask. etc.
   if(isBullishFairValueGap)
   {
      const bool bidInsideFairValueGap =
         (currentBid >= lowerEndOfFairValueGap && currentBid <= higherEndOfFairValueGap);
      if(bidInsideFairValueGap)
      {
         useMarketOrder = true;
         entryPrice     = currentAsk;
      }
      else if(currentBid > higherEndOfFairValueGap)
      {
         useMarketOrder = false;
         entryPrice     = NormalizeDouble(higherEndOfFairValueGap, _Digits);
      }
      else
      {
         useMarketOrder = false;
         entryPrice     = NormalizeDouble(lowerEndOfFairValueGap, _Digits);
      }

      if(entryPrice <= stopLossPrice)
         return;
   }
   else
   {
      // Short: ask inside gap -> market @ bid. Ask below gap -> limit @ lower FVG edge. Ask above gap -> limit @ higher FVG edge.
      const bool askInsideFairValueGap =
         (currentAsk >= lowerEndOfFairValueGap && currentAsk <= higherEndOfFairValueGap);
      if(askInsideFairValueGap)
      {
         useMarketOrder = true;
         entryPrice     = currentBid;
      }
      else if(currentAsk < lowerEndOfFairValueGap)
      {
         useMarketOrder = false;
         entryPrice     = NormalizeDouble(lowerEndOfFairValueGap, _Digits);
      }
      else
      {
         useMarketOrder = false;
         entryPrice     = NormalizeDouble(higherEndOfFairValueGap, _Digits);
      }

      if(entryPrice >= stopLossPrice)
         return;
   }

   const double riskPerUnit = MathAbs(entryPrice - stopLossPrice);
   if(riskPerUnit <= SymbolInfoDouble(_Symbol, SYMBOL_POINT))
      return;

   double takeProfitTwoRewardMultiple = 0.0;
   double takeProfitThreeRewardMultiple = 0.0;
   if(isBullishFairValueGap)
   {
      takeProfitTwoRewardMultiple   = NormalizeDouble(entryPrice + 2.0 * riskPerUnit, _Digits);
      takeProfitThreeRewardMultiple = NormalizeDouble(entryPrice + 3.0 * riskPerUnit, _Digits);
   }
   else
   {
      takeProfitTwoRewardMultiple   = NormalizeDouble(entryPrice - 2.0 * riskPerUnit, _Digits);
      takeProfitThreeRewardMultiple = NormalizeDouble(entryPrice - 3.0 * riskPerUnit, _Digits);
   }

   const double normalizedStopLoss = NormalizeDouble(stopLossPrice, _Digits);
   const double normalizedEntry    = NormalizeDouble(entryPrice, _Digits);

   if(!StopsDistanceAllowed(isBullishFairValueGap, normalizedEntry, normalizedStopLoss,
                            takeProfitTwoRewardMultiple))
   {
      Print("plot_swing_m2: broker stops level too large for this entry/SL/TP.");
      return;
   }

   const ENUM_ORDER_TYPE marketOrderType =
      isBullishFairValueGap ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   const double volumeTwoR =
      CalculateVolumeForFixedUsdRisk(marketOrderType, normalizedEntry, normalizedStopLoss,
                                     InputRiskUsdPerPosition);
   const double volumeThreeR =
      CalculateVolumeForFixedUsdRisk(marketOrderType, normalizedEntry, normalizedStopLoss,
                                     InputRiskUsdPerPosition);
   if(volumeTwoR <= 0.0 || volumeThreeR <= 0.0)
   {
      Print("plot_swing_m2: volume from USD risk is zero — check symbol / contract size.");
      return;
   }

   if(!useMarketOrder)
   {
      if(isBullishFairValueGap && normalizedEntry >= currentAsk)
      {
         Print("plot_swing_m2: BuyLimit invalid — entry must be below ask. entry=", normalizedEntry,
               " ask=", currentAsk);
         return;
      }
      if(!isBullishFairValueGap && normalizedEntry <= currentBid)
      {
         Print("plot_swing_m2: SellLimit invalid — entry must be above bid. entry=", normalizedEntry,
               " bid=", currentBid);
         return;
      }
   }

   globalLastProcessedFairValueGapTradeBarTime = fairValueGapBarOpenTime;

   if(!InputEnableAutomatedTrading)
   {
      Print("plot_swing_m2: BOS opposite FVG setup OK (log only). bullishFvg=", isBullishFairValueGap,
            " market=", useMarketOrder, " entry=", normalizedEntry, " sl=", normalizedStopLoss,
            " tp2R=", takeProfitTwoRewardMultiple, " tp3R=", takeProfitThreeRewardMultiple,
            " vol2R=", volumeTwoR, " vol3R=", volumeThreeR);
      return;
   }

   tradeLayer.SetExpertMagicNumber(InputExpertMagicNumber);
   tradeLayer.SetDeviationInPoints(30);
   ApplyTradeFillingModeFromSymbol();

   const string commentTwoR   = "M2 BOS FVG 2R";
   const string commentThreeR = "M2 BOS FVG 3R";

   bool orderTwoResult   = false;
   bool orderThreeResult = false;

   if(useMarketOrder)
   {
      if(isBullishFairValueGap)
      {
         orderTwoResult =
            tradeLayer.Buy(volumeTwoR, _Symbol, 0.0, normalizedStopLoss, takeProfitTwoRewardMultiple,
                           commentTwoR);
         orderThreeResult =
            tradeLayer.Buy(volumeThreeR, _Symbol, 0.0, normalizedStopLoss, takeProfitThreeRewardMultiple,
                           commentThreeR);
      }
      else
      {
         orderTwoResult =
            tradeLayer.Sell(volumeTwoR, _Symbol, 0.0, normalizedStopLoss, takeProfitTwoRewardMultiple,
                            commentTwoR);
         orderThreeResult =
            tradeLayer.Sell(volumeThreeR, _Symbol, 0.0, normalizedStopLoss, takeProfitThreeRewardMultiple,
                            commentThreeR);
      }
   }
   else
   {
      if(isBullishFairValueGap)
      {
         orderTwoResult =
            tradeLayer.BuyLimit(volumeTwoR, normalizedEntry, _Symbol, normalizedStopLoss,
                                takeProfitTwoRewardMultiple, ORDER_TIME_GTC, 0, commentTwoR);
         orderThreeResult =
            tradeLayer.BuyLimit(volumeThreeR, normalizedEntry, _Symbol, normalizedStopLoss,
                                takeProfitThreeRewardMultiple, ORDER_TIME_GTC, 0, commentThreeR);
      }
      else
      {
         orderTwoResult =
            tradeLayer.SellLimit(volumeTwoR, normalizedEntry, _Symbol, normalizedStopLoss,
                                 takeProfitTwoRewardMultiple, ORDER_TIME_GTC, 0, commentTwoR);
         orderThreeResult =
            tradeLayer.SellLimit(volumeThreeR, normalizedEntry, _Symbol, normalizedStopLoss,
                                 takeProfitThreeRewardMultiple, ORDER_TIME_GTC, 0, commentThreeR);
      }
   }

   if(orderTwoResult || orderThreeResult)
      Print("plot_swing_m2: orders sent. twoR=", orderTwoResult, " threeR=", orderThreeResult);
   else
      Print("plot_swing_m2: order send failed. retcode=", tradeLayer.ResultRetcode(), " ",
            tradeLayer.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
