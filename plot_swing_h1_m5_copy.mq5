//+------------------------------------------------------------------+
//| plot_swing_h1_m5_copy.mq5                                        |
//| H1/M5/M2 swing legs + OBJ_TREND / labels; H1 BOS HUD.            |
//| (Working copy — add strategy logic here.)                        |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "2.13"
#property description "H1/M5/M2 sandbox copy: H1 + M2 swing legs (live + warmup); M5 logic runs; M5 drawing off in code."

input bool   InputSwitchChartToM5       = true;
input int    InputWarmupBarsPerTf       = 500;  // 0 = off
input bool   InputDrawH1SwingLegs       = true;
input color  InputH1SwingLineColor      = clrDodgerBlue;
input bool   InputDrawM2SwingLegs       = true;
input color  InputM2SwingLineColor      = clrMediumPurple;
input int    InputM2SwingWarmupBars     = 500; // 0=off: replay M2 swings on attach (independent of InputWarmupBarsPerTf)
input color  InputM5SwingLineColor      = clrGold; // reserved if M5 swing drawing is re-enabled in code

input bool   InputDrawH1BosHud          = true;
input color  InputColorH1BosLabelBull   = clrLime;
input color  InputColorH1BosLabelBear   = clrTomato;
input color  InputColorH1BosLabelNone   = clrSilver;
input int    InputH1BosLabelFontSize    = 11;

input bool   InputDrawM5BosNearH1       = true;
input double InputM5BosNearH1MaxDistPctOfM2ChartHeight = 10.0; // |M5 BOS level − H1 key pivot| ≤ this % × M2 range
input int    InputM2ChartHeightBars    = 200;   // closed M2 bars: high−low = M2 chart height
input int    InputM5BosNearH1MemoryMax  = 50;   // stored events (oldest dropped)

input color  InputColorM5BosNearH1Bull  = clrLime;
input color  InputColorM5BosNearH1Bear  = clrOrangeRed;

// --- copied from plot_swing_m2.mq5 (detect_swing-style structs) ---
struct Swing
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection; // 1 = up, -1 = down, 0 = unset
   int      keyLevelId;     // H1 only: sequential id for High/Low key label (0 = none / M5)
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
// Copy-only prefixes so we never clash with plot_swing_h1_m5.mq5 (PS_M5_*).
const string PFX_M5_TREND = "PSC5_M5_TR_";
const string PFX_M5_LBL   = "PSC5_M5_LB_";
const string PFX_M2_TREND = "PSC5_M2_TR_";
const string PFX_M2_LBL   = "PSC5_M2_LB_";

const string OBJ_H1_BOS_UI = "PS_UI_H1BOS";
const string PFX_M5_BOS_H1 = "PSC5_M5_BH_";

// M5 swing OBJ_TREND / labels: permanently off in this copy (logic still runs).
const bool M5_SWING_DRAW_VISUALS = false;

// M5 BOS ↔ H1 key reference: only newest this many completed H1 legs (highs/lows per direction logic).
const int M5_BOS_H1_REF_LEG_COUNT = 6;

struct M5BosNearH1Event
{
   datetime bosM5BarTime;
   int      direction;      // 1 = bull M5 BOS, -1 = bear
   double   m5BosLevel;     // M5 structural level crossed
   double   nearestH1Price; // closest H1 key pivot (up-leg high or down-leg low)
   int      h1LegIndex;     // index in g_h1.swingHistory
   bool     nearestIsHigh;  // true if nearest extreme was legHighPrice
   double   distanceAbs;
   int      refH1KeyLevelId; // H1 key # from matched swing (same as High#/Low# label)
};

SwingState g_h1;
SwingState g_m5;
SwingState g_m2;

datetime g_lastH1BarOpen = 0;
datetime g_lastM5BarOpen = 0;
datetime g_lastM2BarOpen = 0;

// Latest H1 BOS (1 = bull, -1 = bear, 0 = none stored yet); bar time of BOS candle
int      g_h1BosDirection = 0;
datetime g_h1BosBarTime   = 0;

M5BosNearH1Event g_m5BosNearH1Events[];
int              g_m5BosNearH1Count = 0;

int g_h1NextKeyLevelId = 1;

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
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
// Storage + plot closed leg (plot_swing_m2 SwingClose; liquidity pool omitted).
void SwingClose(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                 const string chartObjectNamePrefix, const string labelPrefix, const bool drawVisuals,
                 const int lastClosedBarShift = 1)
{
   if(timeframe == PERIOD_H1)
      swingState.currentSwingLeg.keyLevelId = g_h1NextKeyLevelId++;
   else
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
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
//| In-progress M2 leg (OBJ_TREND) — completed legs use SwingClose only. |
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
      UpdateM2LiveSwingLegVisualIf(swingState, timeframe, drawVisuals);
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
//| M5 BOS on last closed bar; returns level crossed (M5 swing history). |
//+------------------------------------------------------------------+
bool TryGetM5BosLevelOnLastClosedBar(bool &outBullishBos, double &outLevel)
{
   outBullishBos = false;
   outLevel = 0.0;
   if(g_m5.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, PERIOD_M5, 1);
   const double prevClose  = iClose(_Symbol, PERIOD_M5, 2);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int hi = g_m5.swingHistoryCount - 1; hi >= 0; hi--)
   {
      if(g_m5.swingHistory[hi].swingDirection != 1)
         continue;
      const double lvl = g_m5.swingHistory[hi].legHighPrice;
      if(closePrice > lvl + pointSize && prevClose <= lvl + pointSize)
      {
         outBullishBos = true;
         outLevel = lvl;
         return true;
      }
      break;
   }
   for(int hi = g_m5.swingHistoryCount - 1; hi >= 0; hi--)
   {
      if(g_m5.swingHistory[hi].swingDirection != -1)
         continue;
      const double lvl = g_m5.swingHistory[hi].legLowPrice;
      if(closePrice < lvl - pointSize && prevClose >= lvl - pointSize)
      {
         outBullishBos = false;
         outLevel = lvl;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Recent closed M2 bars: range high − low (M2 chart height).         |
//+------------------------------------------------------------------+
double M2ChartRangeHeight(const int barCount)
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
//| Nearest H1 *key* pivot to bosLevel: bull M5 BOS → H1 up-leg highs only; |
//| bear M5 BOS → H1 down-leg lows only. Scan newest M5_BOS_H1_REF_LEG_COUNT legs only. |
//+------------------------------------------------------------------+
bool TryFindNearestH1KeyPivotForM5Bos(const double bosLevel, const bool bullM5Bos,
                                      double &outNearest, int &outLegIdx, bool &outNearestIsHighPivot,
                                      double &outDistAbs, int &outKeyLevelId)
{
   outNearest = 0.0;
   outLegIdx = -1;
   outNearestIsHighPivot = bullM5Bos;
   outDistAbs = 1.0e100;
   outKeyLevelId = 0;

   if(g_h1.swingHistoryCount < 1)
      return false;

   const int startIdx = MathMax(0, g_h1.swingHistoryCount - M5_BOS_H1_REF_LEG_COUNT);

   for(int i = startIdx; i < g_h1.swingHistoryCount; i++)
   {
      const Swing lg = g_h1.swingHistory[i];
      if(bullM5Bos)
      {
         if(lg.swingDirection != 1)
            continue;
         const double d = MathAbs(bosLevel - lg.legHighPrice);
         if(d < outDistAbs)
         {
            outDistAbs = d;
            outNearest = lg.legHighPrice;
            outLegIdx = i;
            outNearestIsHighPivot = true;
            outKeyLevelId = lg.keyLevelId;
         }
      }
      else
      {
         if(lg.swingDirection != -1)
            continue;
         const double d = MathAbs(bosLevel - lg.legLowPrice);
         if(d < outDistAbs)
         {
            outDistAbs = d;
            outNearest = lg.legLowPrice;
            outLegIdx = i;
            outNearestIsHighPivot = false;
            outKeyLevelId = lg.keyLevelId;
         }
      }
   }

   if(outDistAbs >= 1.0e99)
      return false;
   return true;
}

//+------------------------------------------------------------------+
bool M5BosNearH1EventAlreadyStored(const datetime tBar)
{
   for(int i = 0; i < g_m5BosNearH1Count; i++)
   {
      if(g_m5BosNearH1Events[i].bosM5BarTime == tBar)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void PushM5BosNearH1Event(const M5BosNearH1Event &ev)
{
   const int cap = (InputM5BosNearH1MemoryMax < 1) ? 1 : InputM5BosNearH1MemoryMax;
   if(g_m5BosNearH1Count < cap)
   {
      ArrayResize(g_m5BosNearH1Events, g_m5BosNearH1Count + 1);
      g_m5BosNearH1Events[g_m5BosNearH1Count] = ev;
      g_m5BosNearH1Count++;
      return;
   }
   for(int k = 1; k < cap; k++)
      g_m5BosNearH1Events[k - 1] = g_m5BosNearH1Events[k];
   g_m5BosNearH1Events[cap - 1] = ev;
}

//+------------------------------------------------------------------+
void DrawM5BosNearH1Marker(const M5BosNearH1Event &ev)
{
   const string tag = PFX_M5_BOS_H1 + IntegerToString((long)ev.bosM5BarTime);
   const color   clr = (ev.direction == 1) ? InputColorM5BosNearH1Bull : InputColorM5BosNearH1Bear;

   if(ObjectFind(0, tag + "_V") >= 0)
      return;

   if(ObjectCreate(0, tag + "_V", OBJ_VLINE, 0, ev.bosM5BarTime, 0))
   {
      ObjectSetInteger(0, tag + "_V", OBJPROP_COLOR, clr);
      ObjectSetInteger(0, tag + "_V", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, tag + "_V", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, tag + "_V", OBJPROP_BACK, false);
      ObjectSetInteger(0, tag + "_V", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tag + "_V", OBJPROP_HIDDEN, true);
   }

   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double txtY = ev.m5BosLevel + (ev.direction == 1 ? pt * 12 : -pt * 12);
   if(ObjectCreate(0, tag + "_T", OBJ_TEXT, 0, ev.bosM5BarTime, txtY))
   {
      const string hiLo = ev.nearestIsHigh ? "H1↑" : "H1↓";
      string refTxt = "";
      if(ev.refH1KeyLevelId > 0)
         refTxt = StringFormat(" KL%d", ev.refH1KeyLevelId);
      ObjectSetString(0, tag + "_T", OBJPROP_TEXT,
                      StringFormat("%s M5 BOS≈%s%s Δ%.1fpt",
                                   (ev.direction == 1 ? "↑" : "↓"),
                                   hiLo,
                                   refTxt,
                                   ev.distanceAbs / pt));
      ObjectSetInteger(0, tag + "_T", OBJPROP_COLOR, clr);
      ObjectSetInteger(0, tag + "_T", OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, tag + "_T", OBJPROP_FONT, "Tahoma");
      ObjectSetInteger(0, tag + "_T", OBJPROP_ANCHOR,
                       ev.direction == 1 ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, tag + "_T", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tag + "_T", OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
void OnM5BarCompleted_TryM5BosNearH1Leg()
{
   if(!InputDrawM5BosNearH1)
      return;
   if(g_h1.swingHistoryCount < 1)
      return;

   bool   bull = false;
   double bosLvl = 0.0;
   if(!TryGetM5BosLevelOnLastClosedBar(bull, bosLvl))
      return;

   const datetime bosT = iTime(_Symbol, PERIOD_M5, 1);
   if(M5BosNearH1EventAlreadyStored(bosT))
      return;

   double nearest = 0.0;
   int    legIx = -1;
   bool   isHigh = false;
   double distAbs = 0.0;
   int    refKid = 0;
   if(!TryFindNearestH1KeyPivotForM5Bos(bosLvl, bull, nearest, legIx, isHigh, distAbs, refKid))
      return;

   const double m2H = M2ChartRangeHeight(InputM2ChartHeightBars);
   if(m2H <= 0.0)
      return;

   const double maxD = m2H * (InputM5BosNearH1MaxDistPctOfM2ChartHeight / 100.0);
   if(distAbs > maxD)
      return;

   M5BosNearH1Event ev;
   ev.bosM5BarTime = bosT;
   ev.direction = bull ? 1 : -1;
   ev.m5BosLevel = bosLvl;
   ev.nearestH1Price = nearest;
   ev.h1LegIndex = legIx;
   ev.nearestIsHigh = isHigh;
   ev.distanceAbs = distAbs;
   ev.refH1KeyLevelId = refKid;

   PushM5BosNearH1Event(ev);
   DrawM5BosNearH1Marker(ev);
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
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M5_BOS_H1, -1, -1);
   ObjectsDeleteAll(0, "PS_M5_SW_", -1, -1);
   ObjectsDeleteAll(0, "PS_M5_LB_", -1, -1);
   ObjectsDeleteAll(0, "PS_M5BOS_H1_", -1, -1);

   ZeroMemory(g_h1);
   ZeroMemory(g_m5);
   ZeroMemory(g_m2);

   g_h1NextKeyLevelId = 1;

   WarmupSwingState(g_h1, PERIOD_H1, InputH1SwingLineColor, PFX_H1_TREND, PFX_H1_LBL, InputDrawH1SwingLegs);
   WarmupSwingState(g_m5, PERIOD_M5, InputM5SwingLineColor, PFX_M5_TREND, PFX_M5_LBL, M5_SWING_DRAW_VISUALS);

   if(InputM2SwingWarmupBars > 0)
   {
      const int barsM2 = iBars(_Symbol, PERIOD_M2);
      if(barsM2 < 8)
         Print("plot_swing_h1_m5_copy: very few M2 bars (", barsM2, ") — confirm symbol has PERIOD_M2 data.");
      const int n2 = (int)MathMin(barsM2 - 2, InputM2SwingWarmupBars);
      if(n2 >= 1)
      {
         for(int k = n2; k >= 1; k--)
            ProcessSwingStepAtShift(g_m2, PERIOD_M2, k, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL,
                                    InputDrawM2SwingLegs);
      }
   }
   else if(InputWarmupBarsPerTf > 0)
      WarmupSwingState(g_m2, PERIOD_M2, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL, InputDrawM2SwingLegs);

   g_h1BosDirection = 0;
   g_h1BosBarTime   = 0;
   TryInitH1BosFromLastClosedBar();
   RefreshH1BosCornerLabel();

   ArrayResize(g_m5BosNearH1Events, 0);
   g_m5BosNearH1Count = 0;

   g_lastH1BarOpen = iTime(_Symbol, PERIOD_H1, 0);
   g_lastM5BarOpen = iTime(_Symbol, PERIOD_M5, 0);
   g_lastM2BarOpen = iTime(_Symbol, PERIOD_M2, 0);
   if(g_lastM2BarOpen == 0)
      Print("plot_swing_h1_m5_copy: PERIOD_M2 bar time is 0 — broker/symbol may not provide M2; M2 swings will not advance.");

   ChartRedraw(0);

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
   ObjectsDeleteAll(0, PFX_M2_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M2_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M5_BOS_H1, -1, -1);
   ObjectsDeleteAll(0, "PS_M5_SW_", -1, -1);
   ObjectsDeleteAll(0, "PS_M5_LB_", -1, -1);
   ObjectsDeleteAll(0, "PS_M5BOS_H1_", -1, -1);
}

//+------------------------------------------------------------------+
void OnTick()
{
   const datetime tH1 = iTime(_Symbol, PERIOD_H1, 0);
   const datetime tM5 = iTime(_Symbol, PERIOD_M5, 0);
   const datetime tM2 = iTime(_Symbol, PERIOD_M2, 0);

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
                              M5_SWING_DRAW_VISUALS);
      OnM5BarCompleted_UpdateH1BosHud();
      OnM5BarCompleted_TryM5BosNearH1Leg();
   }

   if(tM2 != g_lastM2BarOpen)
   {
      g_lastM2BarOpen = tM2;
      ProcessSwingStepAtShift(g_m2, PERIOD_M2, 1, InputM2SwingLineColor, PFX_M2_TREND, PFX_M2_LBL,
                              InputDrawM2SwingLegs);
   }
}

//+------------------------------------------------------------------+
