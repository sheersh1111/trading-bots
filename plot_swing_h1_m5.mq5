//+------------------------------------------------------------------+
//| plot_swing_h1_m5.mq5                                             |
//| Swing leg storage + OBJ_TREND / labels (logic from plot_swing_m2) |
//| — H1 and M5 only. No trading.                                    |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.01"
#property description "H1 + M5 swing legs (plot_swing_m2 engine). H1 BOS HUD on M5 bar close."

input bool   InputSwitchChartToM5       = true;
input int    InputWarmupBarsPerTf       = 500;  // 0 = off
input bool   InputDrawH1SwingLegs       = true;
input bool   InputDrawM5SwingLegs       = true;
input color  InputH1SwingLineColor      = clrDodgerBlue;
input color  InputM5SwingLineColor      = clrGold;

input bool   InputDrawH1BosHud          = true;
input color  InputColorH1BosLabelBull   = clrLime;
input color  InputColorH1BosLabelBear   = clrTomato;
input color  InputColorH1BosLabelNone   = clrSilver;
input int    InputH1BosLabelFontSize    = 11;

// --- copied from plot_swing_m2.mq5 (detect_swing-style structs) ---
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

const string PFX_H1_TREND = "PS_H1_SW_";
const string PFX_H1_LBL   = "PS_H1_LB_";
const string PFX_M5_TREND = "PS_M5_SW_";
const string PFX_M5_LBL   = "PS_M5_LB_";

const string OBJ_H1_BOS_UI = "PS_UI_H1BOS";

SwingState g_h1;
SwingState g_m5;

datetime g_lastH1BarOpen = 0;
datetime g_lastM5BarOpen = 0;

// Latest H1 BOS (1 = bull, -1 = bear, 0 = none stored yet); bar time of BOS candle
int      g_h1BosDirection = 0;
datetime g_h1BosBarTime   = 0;

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
// Storage + plot closed leg (plot_swing_m2 SwingClose; liquidity pool omitted).
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
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
// Core step from plot_swing_m2 ProcessSwingStep (bar at shift `sh`).
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
//| Bullish BOS: last closed bar close crosses above latest completed up-leg high. |
//| Bearish BOS: last closed bar close crosses below latest completed down-leg low. |
//+------------------------------------------------------------------+
bool TryDetectBosOnLastClosedBar(SwingState &st, const ENUM_TIMEFRAMES tf, bool &outBullishBos)
{
   outBullishBos = false;
   if(st.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, tf, 1);
   const double prevClose  = iClose(_Symbol, tf, 2);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int hi = st.swingHistoryCount - 1; hi >= 0; hi--)
   {
      if(st.swingHistory[hi].swingDirection != 1)
         continue;
      const double lvl = st.swingHistory[hi].legHighPrice;
      if(closePrice > lvl + pointSize && prevClose <= lvl + pointSize)
      {
         outBullishBos = true;
         return true;
      }
      break;
   }
   for(int hi = st.swingHistoryCount - 1; hi >= 0; hi--)
   {
      if(st.swingHistory[hi].swingDirection != -1)
         continue;
      const double lvl = st.swingHistory[hi].legLowPrice;
      if(closePrice < lvl - pointSize && prevClose >= lvl - pointSize)
      {
         outBullishBos = false;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
void EnsureH1BosCornerLabel()
{
   if(ObjectFind(0, OBJ_H1_BOS_UI) >= 0)
      return;
   if(!ObjectCreate(0, OBJ_H1_BOS_UI, OBJ_LABEL, 0, 0, 0))
      return;
   ObjectSetInteger(0, OBJ_H1_BOS_UI, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, OBJ_H1_BOS_UI, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, OBJ_H1_BOS_UI, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, OBJ_H1_BOS_UI, OBJPROP_YDISTANCE, 16);
   ObjectSetString(0, OBJ_H1_BOS_UI, OBJPROP_FONT, "Tahoma");
   ObjectSetInteger(0, OBJ_H1_BOS_UI, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, OBJ_H1_BOS_UI, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void RefreshH1BosCornerLabel()
{
   if(!InputDrawH1BosHud)
   {
      ObjectDelete(0, OBJ_H1_BOS_UI);
      return;
   }
   EnsureH1BosCornerLabel();
   const string up = CharToString((ushort)0x2191);
   const string dn = CharToString((ushort)0x2193);
   string line;
   color  clr = InputColorH1BosLabelNone;
   if(g_h1BosDirection == 0 || g_h1BosBarTime == 0)
   {
      line = "H1 BOS  --";
      clr = InputColorH1BosLabelNone;
   }
   else if(g_h1BosDirection == 1)
   {
      line = StringFormat("%s  H1 BOS  %s", up,
                          TimeToString(g_h1BosBarTime, TIME_DATE | TIME_MINUTES));
      clr = InputColorH1BosLabelBull;
   }
   else
   {
      line = StringFormat("%s  H1 BOS  %s", dn,
                          TimeToString(g_h1BosBarTime, TIME_DATE | TIME_MINUTES));
      clr = InputColorH1BosLabelBear;
   }
   ObjectSetString(0, OBJ_H1_BOS_UI, OBJPROP_TEXT, line);
   ObjectSetInteger(0, OBJ_H1_BOS_UI, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, OBJ_H1_BOS_UI, OBJPROP_FONTSIZE, InputH1BosLabelFontSize);
}

//+------------------------------------------------------------------+
//| If last closed H1 printed a BOS vs swing history, update globals. |
//+------------------------------------------------------------------+
void TryUpdateStoredH1BosFromSwingHistory()
{
   bool bull = false;
   if(TryDetectBosOnLastClosedBar(g_h1, PERIOD_H1, bull))
   {
      g_h1BosDirection = bull ? 1 : -1;
      g_h1BosBarTime   = iTime(_Symbol, PERIOD_H1, 1);
   }
}

//+------------------------------------------------------------------+
//| Runs after each completed M5 bar: refresh latest H1 BOS + HUD.   |
//+------------------------------------------------------------------+
void OnM5BarCompleted_UpdateH1BosHud()
{
   TryUpdateStoredH1BosFromSwingHistory();
   RefreshH1BosCornerLabel();
}

//+------------------------------------------------------------------+
void TryInitH1BosFromLastClosedBar()
{
   TryUpdateStoredH1BosFromSwingHistory();
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InputSwitchChartToM5)
   {
      ChartSetSymbolPeriod(0, _Symbol, PERIOD_M5);
      ChartRedraw(0);
   }

   ObjectsDeleteAll(0, PFX_H1_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_H1_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M5_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M5_LBL, -1, -1);

   ZeroMemory(g_h1);
   ZeroMemory(g_m5);

   WarmupSwingState(g_h1, PERIOD_H1, InputH1SwingLineColor, PFX_H1_TREND, PFX_H1_LBL, false);
   WarmupSwingState(g_m5, PERIOD_M5, InputM5SwingLineColor, PFX_M5_TREND, PFX_M5_LBL, false);

   g_h1BosDirection = 0;
   g_h1BosBarTime   = 0;
   TryInitH1BosFromLastClosedBar();
   RefreshH1BosCornerLabel();

   g_lastH1BarOpen = iTime(_Symbol, PERIOD_H1, 0);
   g_lastM5BarOpen = iTime(_Symbol, PERIOD_M5, 0);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, OBJ_H1_BOS_UI);
   ObjectsDeleteAll(0, PFX_H1_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_H1_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M5_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M5_LBL, -1, -1);
}

//+------------------------------------------------------------------+
void OnTick()
{
   const datetime tH1 = iTime(_Symbol, PERIOD_H1, 0);
   const datetime tM5 = iTime(_Symbol, PERIOD_M5, 0);

   if(tH1 != g_lastH1BarOpen)
   {
      g_lastH1BarOpen = tH1;
      ProcessSwingStepAtShift(g_h1, PERIOD_H1, 1, InputH1SwingLineColor, PFX_H1_TREND, PFX_H1_LBL,
                              InputDrawH1SwingLegs);
      TryUpdateStoredH1BosFromSwingHistory();
      RefreshH1BosCornerLabel();
   }

   if(tM5 != g_lastM5BarOpen)
   {
      g_lastM5BarOpen = tM5;
      ProcessSwingStepAtShift(g_m5, PERIOD_M5, 1, InputM5SwingLineColor, PFX_M5_TREND, PFX_M5_LBL,
                              InputDrawM5SwingLegs);
      OnM5BarCompleted_UpdateH1BosHud();
   }
}

//+------------------------------------------------------------------+
