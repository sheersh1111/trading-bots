double OnTester()
{
   double profit = TesterStatistics(STAT_PROFIT);
   double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);

   if(drawdown == 0)
      return profit;
   return profit / drawdown;
}
//+------------------------------------------------------------------+
//| scalping_v3.mq5                                                  |
//| M15 swing legs (visual) + M1 swing legs (anchor tolerance 0.5).  |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "3.02"
#property description "scalping_v3 — M15 + M1 swing legs, shared anchor tolerance."

const ENUM_TIMEFRAMES ChartTf      = PERIOD_M15;
const ENUM_TIMEFRAMES SwingLegM1Tf = PERIOD_M1;

input bool   InputSwitchChartToM15    = true;
input int    InputWarmupBars          = 500;
input bool   InputDrawSwingLegVisuals = true;
input color  InputSwingTrendLineColor = clrYellow;
input bool   InputDrawM1SwingLegVisuals = true;
input color  InputM1SwingTrendLineColor = clrAqua;
input double InputAnchorTolerance     = 0.5; // Anchor tolerance for M15 + M1 swing leg function

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

const string PFX_M15_TREND = "SCALP_V3_M15_TR_";
const string PFX_M15_LBL   = "SCALP_V3_M15_LB_";
const string PFX_M1_TREND  = "SCALP_V3_M1_TR_";
const string PFX_M1_LBL    = "SCALP_V3_M1_LB_";

SwingState g_m15Swing;
SwingState g_m1Swing;
datetime   g_lastM15BarOpen = 0;
datetime   g_lastM1BarOpen  = 0;

//+------------------------------------------------------------------+
void SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                   const double highPrice, const double lowPrice, const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.swingDirection = swingDirection;
   swingState.currentSwingLeg.legHighPrice   = highPrice;
   swingState.currentSwingLeg.legLowPrice    = lowPrice;
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
void SwingClose(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                const string chartObjectNamePrefix, const string labelPrefix, const bool drawVisuals,
                const int lastClosedBarShift = 1)
{
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
                        trendLineEndPrice, isUplegSwingDirection);
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

//+------------------------------------------------------------------+
void ProcessSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int sh,
                             const double anchorTolerance, const color swingLineColor,
                             const string trendPrefix, const string labelPrefix, const bool drawVisuals)
{
   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, sh);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, sh);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, sh);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, sh);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);

   const double lastClosedBarBodyRange = MathAbs(lastClosedBarClose - lastClosedBarOpen);
   const double lastClosedBarWickRange = lastClosedBarHigh - lastClosedBarLow;

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
   const double minDecentRange       = averageRangeFiveBars * anchorTolerance;
   const bool isDecentMovement =
      (lastClosedBarWickRange > minDecentRange && lastClosedBarBodyRange > minDecentRange);

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

//+------------------------------------------------------------------+
void WarmupM1SwingState(SwingState &st)
{
   if(InputWarmupBars <= 0)
      return;

   const int m1WarmupBars = InputWarmupBars * 15;
   const int n = (int)MathMin(iBars(_Symbol, SwingLegM1Tf) - 2, m1WarmupBars);
   for(int k = n; k >= 1; k--)
      ProcessSwingStepAtShift(st, SwingLegM1Tf, k, InputAnchorTolerance, InputM1SwingTrendLineColor,
                              PFX_M1_TREND, PFX_M1_LBL, InputDrawM1SwingLegVisuals);
}

//+------------------------------------------------------------------+
void WarmupSwingState(SwingState &st, const ENUM_TIMEFRAMES tf, const color clr,
                      const string trendPfx, const string lblPfx, const bool draw)
{
   if(InputWarmupBars <= 0)
      return;
   const int n = (int)MathMin(iBars(_Symbol, tf) - 2, InputWarmupBars);
   for(int k = n; k >= 1; k--)
      ProcessSwingStepAtShift(st, tf, k, InputAnchorTolerance, clr, trendPfx, lblPfx, draw);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InputSwitchChartToM15)
   {
      ChartSetSymbolPeriod(0, _Symbol, ChartTf);
      ChartRedraw(0);
   }

   ObjectsDeleteAll(0, PFX_M15_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M15_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M1_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M1_LBL, -1, -1);

   ZeroMemory(g_m15Swing);
   ZeroMemory(g_m1Swing);

   WarmupSwingState(g_m15Swing, ChartTf, InputSwingTrendLineColor, PFX_M15_TREND, PFX_M15_LBL,
                    InputDrawSwingLegVisuals);
   WarmupM1SwingState(g_m1Swing);

   g_lastM15BarOpen = iTime(_Symbol, ChartTf, 0);
   g_lastM1BarOpen  = iTime(_Symbol, SwingLegM1Tf, 0);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX_M15_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M15_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M1_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M1_LBL, -1, -1);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnTick()
{
   const datetime currentM1BarOpenTime = iTime(_Symbol, SwingLegM1Tf, 0);
   if(currentM1BarOpenTime != g_lastM1BarOpen)
   {
      g_lastM1BarOpen = currentM1BarOpenTime;
      ProcessSwingStepAtShift(g_m1Swing, SwingLegM1Tf, 1, InputAnchorTolerance, InputM1SwingTrendLineColor,
                              PFX_M1_TREND, PFX_M1_LBL, InputDrawM1SwingLegVisuals);
   }

   const datetime currentM15BarOpenTime = iTime(_Symbol, ChartTf, 0);
   if(currentM15BarOpenTime == g_lastM15BarOpen)
      return;

   g_lastM15BarOpen = currentM15BarOpenTime;
   ProcessSwingStepAtShift(g_m15Swing, ChartTf, 1, InputAnchorTolerance, InputSwingTrendLineColor,
                           PFX_M15_TREND, PFX_M15_LBL, InputDrawSwingLegVisuals);
}

//+------------------------------------------------------------------+
