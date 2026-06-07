//+------------------------------------------------------------------+
//| m30_swing_legs_only.mq5                                          |
//| M30 (30-minute) swing legs + optional liquidity rectangles.      |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.02"
#property description "M30 swing legs + optional transparent liquidity rectangles above/below each leg."

input bool   InputSwitchChartToM30 = true;
input int    InputWarmupBarsPerTf  = 500;
input bool   InputDrawM30SwingLegs = true;
input color  InputM30SwingLineColor = clrDodgerBlue;

input bool   InputDrawLiquidityZones           = true;
input double InputLiquidityZonePctOfLegRange   = 5.0;
input color  InputLiquidityZoneAboveColor      = C'100,149,237';
input color  InputLiquidityZoneBelowColor      = C'255,165,100';
input uchar  InputLiquidityZoneTransparency    = 55;

const ENUM_TIMEFRAMES SWING_TF = PERIOD_M30;

struct Swing
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection;
   int      keyLevelId;
};

struct SwingState
{
   Swing    currentSwingLeg;
   Swing    swingHistory[20];
   int      swingHistoryCount;
   double   priceAnchorLevel;
};

const string PFX_M30_TREND = "M30ONLY_TR_";
const string PFX_M30_LBL = "M30ONLY_LB_";
const string PFX_M30_LIQ = "M30ONLY_LQ_";

SwingState g_sw;
datetime   g_lastSwingBarOpen = 0;
int        g_nextKeyLevelId = 1;

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

void SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice)
{
   if(highPrice > swingState.currentSwingLeg.legHighPrice)
      swingState.currentSwingLeg.legHighPrice = highPrice;
   if(lowPrice < swingState.currentSwingLeg.legLowPrice)
      swingState.currentSwingLeg.legLowPrice = lowPrice;
}

void DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                       const double labelPrice, const bool isUplegSwingDirection,
                       const int keyLevelIdForLabel)
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
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Above leg high and below leg low: height = pct × (legHigh−legLow).|
//+------------------------------------------------------------------+
void DrawClosedLegLiquidityZones(const datetime tLeft, const datetime tRight,
                                 const double legHigh, const double legLow)
{
   if(!InputDrawLiquidityZones || InputLiquidityZonePctOfLegRange <= 0.0)
      return;
   if(tLeft <= 0 || tRight <= 0 || tLeft > tRight)
      return;

   const double legRange = MathMax(0.0, legHigh - legLow);
   const double pt       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double dz       = MathMax(legRange * (InputLiquidityZonePctOfLegRange / 100.0), pt * 5.0);

   const string base = PFX_M30_LIQ + IntegerToString((long)tRight);
   const string nmUp = base + "_U";
   const string nmDn = base + "_D";

   const uint argbUp = ColorToARGB(InputLiquidityZoneAboveColor, InputLiquidityZoneTransparency);
   const uint argbDn = ColorToARGB(InputLiquidityZoneBelowColor, InputLiquidityZoneTransparency);

   if(ObjectFind(0, nmUp) >= 0)
      ObjectDelete(0, nmUp);
   if(ObjectFind(0, nmDn) >= 0)
      ObjectDelete(0, nmDn);

   if(!ObjectCreate(0, nmUp, OBJ_RECTANGLE, 0, tLeft, legHigh + dz, tRight, legHigh))
      return;
   ObjectSetInteger(0, nmUp, OBJPROP_COLOR, argbUp);
   ObjectSetInteger(0, nmUp, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nmUp, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nmUp, OBJPROP_BACK, true);
   ObjectSetInteger(0, nmUp, OBJPROP_FILL, true);
   ObjectSetInteger(0, nmUp, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nmUp, OBJPROP_HIDDEN, true);

   if(!ObjectCreate(0, nmDn, OBJ_RECTANGLE, 0, tLeft, legLow, tRight, legLow - dz))
      return;
   ObjectSetInteger(0, nmDn, OBJPROP_COLOR, argbDn);
   ObjectSetInteger(0, nmDn, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nmDn, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nmDn, OBJPROP_BACK, true);
   ObjectSetInteger(0, nmDn, OBJPROP_FILL, true);
   ObjectSetInteger(0, nmDn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nmDn, OBJPROP_HIDDEN, true);
}

void SwingClose(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                const string chartObjectNamePrefix, const string labelPrefix, const bool drawVisuals,
                const int lastClosedBarShift = 1)
{
   if(timeframe == SWING_TF)
      swingState.currentSwingLeg.keyLevelId = g_nextKeyLevelId++;
   else
      swingState.currentSwingLeg.keyLevelId = 0;

   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   if(timeframe == SWING_TF)
      DrawClosedLegLiquidityZones(swingState.currentSwingLeg.legStartTime,
                                  swingState.currentSwingLeg.legEndTime,
                                  swingState.currentSwingLeg.legHighPrice,
                                  swingState.currentSwingLeg.legLowPrice);

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
      if(ObjectCreate(0, chartObjectName, OBJ_TREND, 0, swingState.currentSwingLeg.legStartTime,
                      trendLineStartPrice, swingState.currentSwingLeg.legEndTime, trendLineEndPrice))
      {
         ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, swingLineColor);
         ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, chartObjectName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, true);
      }

      const bool isUplegSwingDirection = (swingState.currentSwingLeg.swingDirection == 1);
      DrawSwingLegLabel(labelPrefix, swingState.currentSwingLeg.legEndTime,
                        trendLineEndPrice, isUplegSwingDirection, swingState.currentSwingLeg.keyLevelId);
   }

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int i = 1; i < 20; i++)
         swingState.swingHistory[i - 1] = swingState.swingHistory[i];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

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
   }
   else
   {
      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);
      SwingClose(swingState, timeframe, swingLineColor, trendPrefix, labelPrefix, drawVisuals, sh);

      Swing closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
      double newSwingLegHigh = lastClosedBarHigh;
      double newSwingLegLow  = lastClosedBarLow;
      if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
         newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
      else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
         newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

      SwingStartNew(swingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow, sh);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
   }
}

void WarmupSwingState(SwingState &st, const ENUM_TIMEFRAMES tf, const color clr,
                      const string trendPfx, const string lblPfx, const bool draw)
{
   if(InputWarmupBarsPerTf <= 0)
      return;
   const int n = (int)MathMin(iBars(_Symbol, tf) - 2, InputWarmupBarsPerTf);
   for(int k = n; k >= 1; k--)
      ProcessSwingStepAtShift(st, tf, k, clr, trendPfx, lblPfx, draw);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InputSwitchChartToM30)
   {
      ChartSetSymbolPeriod(0, _Symbol, SWING_TF);
      ChartRedraw(0);
   }

   ObjectsDeleteAll(0, PFX_M30_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M30_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M30_LIQ, -1, -1);

   ZeroMemory(g_sw);
   g_nextKeyLevelId = 1;
   WarmupSwingState(g_sw, SWING_TF, InputM30SwingLineColor, PFX_M30_TREND, PFX_M30_LBL, InputDrawM30SwingLegs);

   g_lastSwingBarOpen = iTime(_Symbol, SWING_TF, 0);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX_M30_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M30_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M30_LIQ, -1, -1);
}

void OnTick()
{
   const datetime t = iTime(_Symbol, SWING_TF, 0);
   if(t != g_lastSwingBarOpen)
   {
      g_lastSwingBarOpen = t;
      ProcessSwingStepAtShift(g_sw, SWING_TF, 1, InputM30SwingLineColor, PFX_M30_TREND, PFX_M30_LBL,
                              InputDrawM30SwingLegs);
   }
}

//+------------------------------------------------------------------+
