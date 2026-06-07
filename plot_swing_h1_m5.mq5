//+------------------------------------------------------------------+
//| plot_swing_h1_m5.mq5                                             |
//| Swing leg storage + OBJ_TREND / labels; optional Scenario A FVG   |
//| pending trades (1% risk, 3 partials @ 1R/2R/3R).                 |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.12"
#property description "H1/M5 swings; H1 BOS HUD; Scenario A FVG + optional split limit orders (1R/2R/3R)."

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

input bool   InputDrawM2FvgsAfterM5BosAlignedH1 = true;
input int    InputM2FvgMaxScanShift             = 64; // after M2 leg-BOS: scan FVG ending shifts 1..this
input double InputM2FvgMinGapPctOfRange         = 0.0; // 0 = off; gap vs recent M2 range height
input int    InputM2FvgRangeBars                = 200;
input color  InputColorM2LegFvgBull             = clrPaleGreen;
input color  InputColorM2LegFvgBear             = clrThistle;

input bool     InputTradeScenarioAFvg              = true; // pending limits at FVG edge; 1% risk → 3 × TP 1R/2R/3R
input double   InputTradeRiskPercentTotal          = 1.0;   // % of balance, total across 3 orders
input double   InputTradeSlPctOfM2ChartHeight      = 2.0;   // SL buffer = this % × M2 range height (see bars below)
input int      InputTradeM2ChartHeightBars         = 200;  // M2 bars for range high−low (chart height)
input ulong    InputTradeMagicNumber               = 9100511;
input int      InputTradeSlippagePoints            = 20;
input string   InputTradeCommentPrefix             = "PS_A";

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
const string PFX_M2_LEG_FVG = "PS_M2LEG_FVG_";
const string GV_TRADE_FVG   = "PS_FVG_TRD_";

#include <Trade\Trade.mqh>
CTrade g_trade;

SwingState g_h1;
SwingState g_m5;

datetime g_lastH1BarOpen = 0;
datetime g_lastM5BarOpen = 0;
datetime g_lastM2BarOpen = 0;

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
      // Include this bar's wicks in the leg before close (reversal was decided using close vs anchor).
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
double M2RangeHeightForFvgFilter(const int barCount)
{
   if(barCount < 1 || iBars(_Symbol, PERIOD_M2) < barCount + 1)
      return 0.0;
   double hi = -1.0e100;
   double lo = 1.0e100;
   for(int i = 1; i <= barCount; i++)
   {
      hi = MathMax(hi, iHigh(_Symbol, PERIOD_M2, i));
      lo = MathMin(lo, iLow(_Symbol, PERIOD_M2, i));
   }
   return hi - lo;
}

//+------------------------------------------------------------------+
bool M2FvgGapPassesMinSize(const double zLo, const double zHi)
{
   if(InputM2FvgMinGapPctOfRange <= 0.0)
      return true;
   const double gap = MathAbs(zHi - zLo);
   if(gap <= 0.0)
      return false;
   const double rh = M2RangeHeightForFvgFilter(InputM2FvgRangeBars);
   if(rh <= 0.0)
      return true;
   return gap >= rh * (InputM2FvgMinGapPctOfRange / 100.0);
}

//+------------------------------------------------------------------+
// M2: newest bar of the 3-candle pattern = shift s; oldest = s+2.
// Bull: low[s] > high[s+2]. Bear: high[s] < low[s+2].
//+------------------------------------------------------------------+
bool TryM2FairValueGapAtShift(const int s, bool &outBull, double &outZlo, double &outZhi)
{
   outBull = false;
   outZlo = outZhi = 0.0;
   if(s < 1 || iBars(_Symbol, PERIOD_M2) < s + 3)
      return false;

   const double l1 = iLow(_Symbol, PERIOD_M2, s);
   const double h1 = iHigh(_Symbol, PERIOD_M2, s);
   const double h3 = iHigh(_Symbol, PERIOD_M2, s + 2);
   const double l3 = iLow(_Symbol, PERIOD_M2, s + 2);

   if(l1 > h3)
   {
      outBull = true;
      outZlo = h3;
      outZhi = l1;
      return M2FvgGapPassesMinSize(outZlo, outZhi);
   }
   if(h1 < l3)
   {
      outBull = false;
      outZlo = h1;
      outZhi = l3;
      return M2FvgGapPassesMinSize(outZlo, outZhi);
   }
   return false;
}

//+------------------------------------------------------------------+
// Newest completed M5 swing matching BOS direction: bull → up-leg high, bear → down-leg low.
// Same newest-first walk as TryDetectBosOnLastClosedBar uses on swingHistory.
//+------------------------------------------------------------------+
bool TryGetM5PriorCompletedSwingExtremeForBos(const bool wantBullishBos, double &outLevel)
{
   outLevel = 0.0;
   if(g_m5.swingHistoryCount < 1)
      return false;
   const int wantDir = wantBullishBos ? 1 : -1;
   for(int i = g_m5.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_m5.swingHistory[i].swingDirection != wantDir)
         continue;
      outLevel = wantBullishBos ? g_m5.swingHistory[i].legHighPrice
                                : g_m5.swingHistory[i].legLowPrice;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// Scenario A: strict 3-M2-bar BOS vs prior completed M5 swing extreme (history), not the in-progress leg.
// Bull: level = last completed up-leg high — o3<=lvl+pt and c1>lvl+pt.
// Bear: level = last completed down-leg low — o3>=lvl-pt and c1<lvl-pt.
//+------------------------------------------------------------------+
bool TryM2CloseBosVsM5CurrentLeg(const bool wantBullishBos)
{
   if(iBars(_Symbol, PERIOD_M2) < 4)
      return false;

   double lvl;
   if(!TryGetM5PriorCompletedSwingExtremeForBos(wantBullishBos, lvl))
      return false;

   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double o3 = iOpen(_Symbol, PERIOD_M2, 3);
   const double c1 = iClose(_Symbol, PERIOD_M2, 1);

   if(wantBullishBos)
      return (o3 <= lvl + pt && c1 > lvl + pt);
   return (o3 >= lvl - pt && c1 < lvl - pt);
}

//+------------------------------------------------------------------+
void DrawM2LegFvgRectOnce(const string name, const datetime tL, const datetime tR,
                          const double p0, const double p1, const color clr)
{
   if(ObjectFind(0, name) >= 0)
      return;
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, tL, p0, tR, p1))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
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
double NormalizePriceToTick(const double price)
{
   const double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

//+------------------------------------------------------------------+
double CalculateVolumeForFixedRisk(const ENUM_ORDER_TYPE orderTypeForCalc, const double entryPrice,
                                   const double stopLossPrice, const double riskMoney)
{
   double profitAtStop = 0.0;
   if(!OrderCalcProfit(orderTypeForCalc, _Symbol, 1.0, entryPrice, stopLossPrice, profitAtStop))
      return 0.0;

   const double lossPerLot = (profitAtStop < 0.0) ? -profitAtStop : profitAtStop;
   if(lossPerLot <= 0.0)
      return 0.0;

   double volume = riskMoney / lossPerLot;
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
bool StopsDistanceOk(const bool isBuy, const double entryPrice, const double stopLossPrice,
                     const double takeProfitPrice)
{
   const int    stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double pointSize        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minDistance      = (double)stopsLevelPoints * pointSize;
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
bool HasScenarioAFvgTradeOrPending(const string &planKey)
{
   if(GlobalVariableCheck(GV_TRADE_FVG + planKey))
      return true;

   const string needle = InputTradeCommentPrefix + "|" + planKey;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InputTradeMagicNumber)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), needle) >= 0)
         return true;
   }

   for(int j = PositionsTotal() - 1; j >= 0; j--)
   {
      const ulong pticket = PositionGetTicket(j);
      if(pticket == 0)
         continue;
      if(!PositionSelectByTicket(pticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InputTradeMagicNumber)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), needle) >= 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
// Nearest FVG edge to bid; SL = middle candle extreme ± (pct × M2 chart height). Three pending limits, equal volume, TP 1R/2R/3R.
//+------------------------------------------------------------------+
void TryPlaceScenarioAFvgSplitPending(const int patternShiftS, const bool bullGap,
                                      const double zL, const double zH,
                                      const datetime tOld, const datetime tNew)
{
   if(!InputTradeScenarioAFvg)
      return;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;
   if((ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return;

   const string planKey = IntegerToString((long)tOld) + "_" + IntegerToString((long)tNew);
   if(HasScenarioAFvgTradeOrPending(planKey))
      return;

   if(patternShiftS < 1 || iBars(_Symbol, PERIOD_M2) < patternShiftS + 3)
      return;

   const int    midSh   = patternShiftS + 1;
   const double midHigh = iHigh(_Symbol, PERIOD_M2, midSh);
   const double midLow  = iLow(_Symbol, PERIOD_M2, midSh);

   const double chartH = M2RangeHeightForFvgFilter(InputTradeM2ChartHeightBars);
   if(chartH <= 0.0)
      return;

   const double buf = chartH * (InputTradeSlPctOfM2ChartHeight / 100.0);
   if(buf <= 0.0)
      return;

   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double entryRaw =
      (MathAbs(bid - zL) <= MathAbs(bid - zH)) ? zL : zH;
   const double entry = NormalizePriceToTick(entryRaw);

   double sl;
   if(bullGap)
   {
      sl = NormalizePriceToTick(midLow - buf);
      if(sl >= entry || entry >= ask)
         return;
   }
   else
   {
      sl = NormalizePriceToTick(midHigh + buf);
      if(sl <= entry || entry <= bid)
         return;
   }

   const double rDist = MathAbs(entry - sl);
   if(rDist <= SymbolInfoDouble(_Symbol, SYMBOL_POINT))
      return;

   const ENUM_ORDER_TYPE calcType = bullGap ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   const double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   const double riskMoney = balance * (InputTradeRiskPercentTotal / 100.0);
   if(riskMoney <= 0.0)
      return;

   double totalVol = CalculateVolumeForFixedRisk(calcType, entry, sl, riskMoney);
   if(totalVol <= 0.0)
      return;

   const double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double vMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vEach = totalVol / 3.0;
   if(vStep > 0.0)
      vEach = MathFloor(vEach / vStep) * vStep;
   if(vEach < vMin)
      return;

   double tp1, tp2, tp3;
   if(bullGap)
   {
      tp1 = NormalizePriceToTick(entry + rDist);
      tp2 = NormalizePriceToTick(entry + 2.0 * rDist);
      tp3 = NormalizePriceToTick(entry + 3.0 * rDist);
   }
   else
   {
      tp1 = NormalizePriceToTick(entry - rDist);
      tp2 = NormalizePriceToTick(entry - 2.0 * rDist);
      tp3 = NormalizePriceToTick(entry - 3.0 * rDist);
   }

   if(!StopsDistanceOk(bullGap, entry, sl, tp1) ||
      !StopsDistanceOk(bullGap, entry, sl, tp2) ||
      !StopsDistanceOk(bullGap, entry, sl, tp3))
      return;

   g_trade.SetExpertMagicNumber(InputTradeMagicNumber);
   g_trade.SetDeviationInPoints(InputTradeSlippagePoints);

   const string c1 = InputTradeCommentPrefix + "|" + planKey + "|1R";
   const string c2 = InputTradeCommentPrefix + "|" + planKey + "|2R";
   const string c3 = InputTradeCommentPrefix + "|" + planKey + "|3R";

   bool o1 = false, o2 = false, o3 = false;
   if(bullGap)
   {
      o1 = g_trade.BuyLimit(vEach, entry, _Symbol, sl, tp1, ORDER_TIME_GTC, 0, c1);
      o2 = g_trade.BuyLimit(vEach, entry, _Symbol, sl, tp2, ORDER_TIME_GTC, 0, c2);
      o3 = g_trade.BuyLimit(vEach, entry, _Symbol, sl, tp3, ORDER_TIME_GTC, 0, c3);
   }
   else
   {
      o1 = g_trade.SellLimit(vEach, entry, _Symbol, sl, tp1, ORDER_TIME_GTC, 0, c1);
      o2 = g_trade.SellLimit(vEach, entry, _Symbol, sl, tp2, ORDER_TIME_GTC, 0, c2);
      o3 = g_trade.SellLimit(vEach, entry, _Symbol, sl, tp3, ORDER_TIME_GTC, 0, c3);
   }

   if(o1 && o2 && o3)
      GlobalVariableSet(GV_TRADE_FVG + planKey, (double)TimeCurrent());
   else
   {
      const string partialTag = InputTradeCommentPrefix + "|" + planKey;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         const ulong ticket = OrderGetTicket(i);
         if(ticket == 0 || !OrderSelect(ticket))
            continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol)
            continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != InputTradeMagicNumber)
            continue;
         if(StringFind(OrderGetString(ORDER_COMMENT), partialTag) >= 0)
            g_trade.OrderDelete(ticket);
      }
   }
}

//+------------------------------------------------------------------+
// Each M2 close: H1 bias + M5 leg same dir; strict 3-bar open[3]/close[1] BOS vs prior M5 swing hi/lo; then mark completed
// M2 FVGs (same bias) whose 3-bar pattern includes the BOS M2 bar; oldest bar not before leg start.
//+------------------------------------------------------------------+
void OnM2BarCompleted_ScenarioA_M5LegBosCloseAndFvg()
{
   if(!InputDrawM2FvgsAfterM5BosAlignedH1 || g_h1BosDirection == 0)
      return;
   if(iBars(_Symbol, PERIOD_M2) < 4)
      return;

   if(g_m5.currentSwingLeg.swingDirection == 0)
      return;
   if(g_m5.currentSwingLeg.swingDirection != g_h1BosDirection)
      return;

   const bool wantBull = (g_h1BosDirection == 1);
   if(!TryM2CloseBosVsM5CurrentLeg(wantBull))
      return;

   const datetime bosM2BarOpen = iTime(_Symbol, PERIOD_M2, 1);
   const datetime legStart   = g_m5.currentSwingLeg.legStartTime;

   const int maxS = (int)MathMin(InputM2FvgMaxScanShift, iBars(_Symbol, PERIOD_M2) - 3);
   if(maxS < 1)
      return;

   for(int s = 1; s <= maxS; s++)
   {
      bool   bullGap;
      double zL, zH;
      if(!TryM2FairValueGapAtShift(s, bullGap, zL, zH))
         continue;
      if(bullGap != wantBull)
         continue;

      const datetime tNew = iTime(_Symbol, PERIOD_M2, s);
      const datetime tMid = iTime(_Symbol, PERIOD_M2, s + 1);
      const datetime tOld = iTime(_Symbol, PERIOD_M2, s + 2);
      if(tOld < legStart)
         continue;
      if(bosM2BarOpen != tNew && bosM2BarOpen != tMid && bosM2BarOpen != tOld)
         continue;

      const color clr = bullGap ? InputColorM2LegFvgBull : InputColorM2LegFvgBear;
      const string nm =
         PFX_M2_LEG_FVG + "A_" + IntegerToString((long)tOld) + "_" + IntegerToString((long)tNew);

      DrawM2LegFvgRectOnce(nm, tOld, tNew, zL, zH, clr);

      TryPlaceScenarioAFvgSplitPending(s, wantBull, zL, zH, tOld, tNew);
   }
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
   ObjectsDeleteAll(0, PFX_M2_LEG_FVG, -1, -1);

   ZeroMemory(g_h1);
   ZeroMemory(g_m5);

   WarmupSwingState(g_h1, PERIOD_H1, InputH1SwingLineColor, PFX_H1_TREND, PFX_H1_LBL, false);
   WarmupSwingState(g_m5, PERIOD_M5, InputM5SwingLineColor, PFX_M5_TREND, PFX_M5_LBL, false);

   g_h1BosDirection = 0;
   g_h1BosBarTime   = 0;
   TryInitH1BosFromLastClosedBar();
   RefreshH1BosCornerLabel();

   g_trade.SetExpertMagicNumber(InputTradeMagicNumber);
   ApplyTradeFillingModeFromSymbol();

   g_lastH1BarOpen = iTime(_Symbol, PERIOD_H1, 0);
   g_lastM5BarOpen = iTime(_Symbol, PERIOD_M5, 0);
   g_lastM2BarOpen = iTime(_Symbol, PERIOD_M2, 0);

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
   ObjectsDeleteAll(0, PFX_M2_LEG_FVG, -1, -1);
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

   const datetime tM2 = iTime(_Symbol, PERIOD_M2, 0);
   if(tM2 != g_lastM2BarOpen)
   {
      g_lastM2BarOpen = tM2;
      OnM2BarCompleted_ScenarioA_M5LegBosCloseAndFvg();
   }
}

//+------------------------------------------------------------------+
