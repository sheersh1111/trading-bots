//+------------------------------------------------------------------+
//| plot_swing_m15.mq5                                               |
//| M15 swing leg memory (20 completed legs) + optional OBJ_TREND /  |
//| High–Low labels + M15 FVG memory & rectangles (bar 1 vs bar 3).  |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.04"

const ENUM_TIMEFRAMES ChartTf = PERIOD_M15;

input bool   InputSwitchChartToM15      = true;   // Set chart period to M15 on attach
input bool   InputDrawSwingLegVisuals   = true;   // Leg trend lines + High/Low labels
input color  InputSwingTrendLineColor   = clrYellow;

input group "M15 FVG (bar 1 vs bar 3)"
input bool   InputDrawM15FairValueGapZones = true; // Filled rectangles for detected FVG
input int    InputChartRangeBarCount = 147;        // Bars for chart height (min-gap filter)
input double InputFairValueGapMinimumPercentOfChartRange = 2.0; // Min gap as % of height (0 = off)
input int    InputMaximumFairValueGapRectangles = 120;

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

SwingState globalSwingState;
datetime   globalLastChartBarOpenTime = 0;

struct M15FairValueGapMemory
{
   bool     isBullishFairValueGap;
   double   fairValueGapZoneLowPrice;
   double   fairValueGapZoneHighPrice;
   datetime formationBarOpenTime;
};

#define M15FairValueGapMemoryCapacity 32

M15FairValueGapMemory globalM15FairValueGapMemory[M15FairValueGapMemoryCapacity];
int                   globalM15FairValueGapMemoryCount = 0;
int                   globalM15FairValueGapRectangleSequence = 0;

const string ChartObjectNamePrefixSwingTrendLine = "M15_Swing_";
const string ChartObjectNamePrefixSwingLabelText = "M15_SWLBL_";
const string ChartObjectNamePrefixM15FairValueGap = "M15_FVG_";

void ProcessSwingStep(SwingState &swingState, const ENUM_TIMEFRAMES timeframe);
void SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                   const double highPrice, const double lowPrice);
void SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice);
void SwingClose(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                const string chartObjectNamePrefix);
void DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                       const double labelPrice, const bool isUplegSwingDirection);

double ReferenceChartHeightForFairValueGapFilter(const ENUM_TIMEFRAMES timeframe);
bool   FairValueGapGapMeetsMinimumPercentOfRange(const ENUM_TIMEFRAMES timeframe,
                                                 const double zoneLowPrice, const double zoneHighPrice);
bool   DetectFairValueGapOnLastClosedBar(bool &isBullishFairValueGap, double &fairValueGapZoneLowPrice,
                                        double &fairValueGapZoneHighPrice);
void   PushM15FairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                 const double zoneHighPrice, const datetime formationBarOpenTime);
void   DrawM15FairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                               const double zoneHighPrice, const datetime leftBarTime,
                               const datetime rightBarTime);
void   ProcessM15FairValueGapOnNewBar();

//+------------------------------------------------------------------+
int OnInit()
{
   if(InputSwitchChartToM15)
   {
      ChartSetSymbolPeriod(0, _Symbol, ChartTf);
      ChartRedraw(0);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int deinitializationReason)
{
   ObjectsDeleteAll(0, ChartObjectNamePrefixSwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixSwingLabelText, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15FairValueGap, -1, -1);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnTick()
{
   const datetime currentBarOpenTime = iTime(_Symbol, ChartTf, 0);
   if(currentBarOpenTime == globalLastChartBarOpenTime)
      return;

   globalLastChartBarOpenTime = currentBarOpenTime;
   ProcessSwingStep(globalSwingState, ChartTf);
   ProcessM15FairValueGapOnNewBar();
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

   double sumRangeFivePriorBars = 0.0;
   for(int barShiftIndex = 2; barShiftIndex <= 6; barShiftIndex++)
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, barShiftIndex) - iLow(_Symbol, timeframe, barShiftIndex));
   const double averageRangeFiveBars = sumRangeFivePriorBars / 5.0;

   const bool isDecentMovement = (lastClosedBarRange > (averageRangeFiveBars * 1.0));
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
      SwingClose(swingState, timeframe, InputSwingTrendLineColor, ChartObjectNamePrefixSwingTrendLine);

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

   const double lastClosedBarHigh = iHigh(_Symbol, ChartTf, 1);
   const double lastClosedBarLow  = iLow(_Symbol, ChartTf, 1);
   const double thirdBarHigh      = iHigh(_Symbol, ChartTf, 3);
   const double thirdBarLow       = iLow(_Symbol, ChartTf, 3);

   if(lastClosedBarLow > thirdBarHigh)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfRange(ChartTf, thirdBarHigh, lastClosedBarLow))
         return false;
      isBullishFairValueGap = true;
      fairValueGapZoneLowPrice  = thirdBarHigh;
      fairValueGapZoneHighPrice = lastClosedBarLow;
      return true;
   }

   if(lastClosedBarHigh < thirdBarLow)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfRange(ChartTf, lastClosedBarHigh, thirdBarLow))
         return false;
      isBullishFairValueGap = false;
      fairValueGapZoneLowPrice  = lastClosedBarHigh;
      fairValueGapZoneHighPrice = thirdBarLow;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
void PushM15FairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                               const double zoneHighPrice, const datetime formationBarOpenTime)
{
   for(int memoryIndex = 0; memoryIndex < globalM15FairValueGapMemoryCount; memoryIndex++)
   {
      if(globalM15FairValueGapMemory[memoryIndex].formationBarOpenTime == formationBarOpenTime)
         return;
   }

   if(globalM15FairValueGapMemoryCount < M15FairValueGapMemoryCapacity)
   {
      const int index = globalM15FairValueGapMemoryCount;
      globalM15FairValueGapMemory[index].isBullishFairValueGap   = isBullishFairValueGap;
      globalM15FairValueGapMemory[index].fairValueGapZoneLowPrice  = zoneLowPrice;
      globalM15FairValueGapMemory[index].fairValueGapZoneHighPrice = zoneHighPrice;
      globalM15FairValueGapMemory[index].formationBarOpenTime  = formationBarOpenTime;
      globalM15FairValueGapMemoryCount++;
      return;
   }

   for(int shiftIndex = 1; shiftIndex < M15FairValueGapMemoryCapacity; shiftIndex++)
      globalM15FairValueGapMemory[shiftIndex - 1] = globalM15FairValueGapMemory[shiftIndex];

   const int lastIndex = M15FairValueGapMemoryCapacity - 1;
   globalM15FairValueGapMemory[lastIndex].isBullishFairValueGap   = isBullishFairValueGap;
   globalM15FairValueGapMemory[lastIndex].fairValueGapZoneLowPrice  = zoneLowPrice;
   globalM15FairValueGapMemory[lastIndex].fairValueGapZoneHighPrice = zoneHighPrice;
   globalM15FairValueGapMemory[lastIndex].formationBarOpenTime  = formationBarOpenTime;
}

//+------------------------------------------------------------------+
void DrawM15FairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                             const double zoneHighPrice, const datetime leftBarTime,
                             const datetime rightBarTime)
{
   if(!InputDrawM15FairValueGapZones)
      return;

   globalM15FairValueGapRectangleSequence++;
   const string chartObjectName =
      ChartObjectNamePrefixM15FairValueGap +
      IntegerToString(globalM15FairValueGapRectangleSequence);
   if(globalM15FairValueGapRectangleSequence > InputMaximumFairValueGapRectangles)
   {
      const string oldRectangleName =
         ChartObjectNamePrefixM15FairValueGap +
         IntegerToString(globalM15FairValueGapRectangleSequence - InputMaximumFairValueGapRectangles);
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
void ProcessM15FairValueGapOnNewBar()
{
   bool isBullishFairValueGap;
   double fairValueGapZoneLowPrice;
   double fairValueGapZoneHighPrice;
   if(!DetectFairValueGapOnLastClosedBar(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                         fairValueGapZoneHighPrice))
      return;

   const datetime formationBarOpenTime = iTime(_Symbol, ChartTf, 1);
   const datetime thirdBarOpenTime     = iTime(_Symbol, ChartTf, 3);

   PushM15FairValueGapMemory(isBullishFairValueGap, fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                             formationBarOpenTime);
   DrawM15FairValueGapZone(isBullishFairValueGap, fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                           thirdBarOpenTime, formationBarOpenTime);
}

//+------------------------------------------------------------------+
