#include <Trade\Trade.mqh>
CTrade trade;

// --- timeframes & FVG size (ref = HH−LL over InpChartRangeBars on each TF) ---
// HTF = M15 (swing context + risk %); LTF = M2 (sweep + FVG + entries)
const ENUM_TIMEFRAMES InpHTF = PERIOD_M15;
input ENUM_TIMEFRAMES InpLTF = PERIOD_M2;  // Must be lower period than InpHTF
input int    InpChartRangeBars   = 147;    // Bar count for chart-height range (HTF & LTF FVG %)
input double InpFvgMinPctOfRange = 2.0;    // Min FVG gap as % of that range (0 = off)

input int InpLtfReactionLookback = 48;     // LTF bars to scan for pool touch / sweep before signal

input group "LTF → HTF risk (LTF: sweep + FVG first; HTF sets risk % of balance)"
input bool   InpEnableHtfLtfPlan  = true;   // Send pending orders (false = logs only, no orders)
input double InpEntryLotsFallback = 0.01;    // Lot size if risk sizing fails (1:2 and 1:3 each)
input ulong  InpMagicPlan         = 940021; // Magic number for plan orders
input double InpSlPctOfLtfChartHeight = 2.5; // SL distance = this % of LTF 147-bar range, from far edge of LTF FVG (P1 & P2)
input double InpLtfNearPatternMaxPctOfGap = 25.0; // LTF FVG: entry pattern uses gap edges (see ClassifyLtfFvgPattern)
input bool   InpPlanRequireSwingStructure = false; // If true: need prior swing opposite to current leg (stricter)
input int    InpLtfFvgEntryLookback       = 24;    // Scan LTF 3-bar FVG windows: bar[sh] vs bar[sh+2], sh=1..N (not only sh=1)
input double InpRiskPctHtfAligned  = 1.0;   // Risk %% of balance when LTF trade aligns with HTF swing direction
input double InpRiskPctHtfCounter = 0.5;   // Risk %% when LTF trade is counter to HTF swing
input double InpRiskPctHtfNeutral = 0.75; // Risk %% when HTF swing direction is unset

input group "Chart objects (HTF context + LTF execution)"
input bool InpSwitchChartToLtf    = true;    // Open/set chart to InpLTF (LTF-first workflow)
input bool InpHtfDrawSwingLines   = true;  // Trend lines for each closed HTF swing leg
input bool InpHtfDrawSwingLabels  = true;  // H/L markers at swing extreme when leg closes
input bool InpHtfDrawFvgZones     = true;  // Rectangles for HTF FVG zones (bar 3 vs bar 1 gap)
input int  InpHtfMaxFvgRectangles = 120;    // Oldest HTF FVG rectangles removed when over this count
input bool InpLtfDrawSwingLines   = true;  // LTF swing legs (same logic as HTF) for liquidity / sweeps
input bool InpLtfDrawSwingLabels  = true;  // H/L on LTF at swing close
input bool InpDrawLtfFvgWhileHunting = true; // Draw LTF FVG rectangles when setup aligns (sweep + FVG)
input int  InpLtfMaxPersistFvgRects   = 120; // Max LTF_FVG_* rectangles; oldest removed
input bool InpLogWhyNoTrade           = true; // Experts: why no order when setup visible (once/bar)

// --- types ---
struct Swing
{
   double   high;
   double   low;
   datetime startTime;
   datetime endTime;
   int      direction; // 1 = up, -1 = down, 0 = unset
};

struct SwingState
{
   Swing    current;
   Swing    swings[20];
   int      swingCount;
   double   anchor;
};

struct LiquidityPool
{
   double lo;
   double hi;
   bool   isSupply; // true = resistance / supply, false = support / demand
};

// --- globals: duplicate signal guard ---
datetime lastBullishSignalTime = 0;
datetime lastBearishSignalTime = 0;

SwingState m15State; // HTF swing state (naming legacy: m15 = HTF)
SwingState ltfState;

datetime g_lastHtfBarTime = 0;
datetime g_lastLtfBarTime = 0;

int g_m15FvgPlotSeq = 0; // FIFO prune for HTF FVG rectangle names

#define HTF_POOL_CAP 32
#define LTF_POOL_CAP 32
LiquidityPool g_m15Pools[HTF_POOL_CAP];
int           g_m15PoolCount = 0;
LiquidityPool g_ltfPools[LTF_POOL_CAP];
int           g_ltfPoolCount = 0;

// LTF-first UI: last bar we placed a plan (avoid duplicates)
datetime g_lastPlanLtfBarTime = 0;
// Hunt arrow / debug: which LTF direction has sweep + FVG this bar (0 = none)
int      g_ltfHuntDir          = 0;

int      g_ltfFvgPersistSeq      = 0;    // monotonic id for LTF_FVG_* rectangles
datetime g_ltfFvgDbgBarProcessed = 0;    // last LTF bar time we drew a persist FVG (one per bar)

// --- forward declarations ---
void   ProcessSwingStep(SwingState &st, const ENUM_TIMEFRAMES tf);
void   SwingStartNew(SwingState &st, const ENUM_TIMEFRAMES tf, const int dir, const double h, const double l);
void   SwingExtend(SwingState &st, const double h, const double l);
void   SwingClose(SwingState &st, const ENUM_TIMEFRAMES tf, const color col, const string prefix);
void   PushM15Pool(const double lo, const double hi, const bool isSupply);
void   PushLtfPool(const double lo, const double hi, const bool isSupply);
void   TryAddM15FvgFromLastClosedBar();
void   DrawM15FvgZone(const bool isBullish, const double zoneLo, const double zoneHi,
                      const datetime tLeft, const datetime tRight);
void   DrawSwingLegLabel(const string prefix, const datetime t, const double price, const bool isUpLeg);
bool   RangeOverlaps(const double aLo, const double aHi, const double bLo, const double bHi);
bool   IsM15PoolInverted(const bool isSupply, const double poolLo, const double poolHi);
bool   LtfPoolTouch(const double poolLo, const double poolHi, const int lookback);
bool   LtfSweepBearishThroughPool(const double poolLo, const double poolHi, const int lookback);
bool   LtfSweepBullishThroughPool(const double poolLo, const double poolHi, const int lookback);
bool   LtfReactedToPool(const bool isSupply, const double poolLo, const double poolHi, const int lookback);
bool   PassesLtfLiquidityFilter(const int tradeDirection);
bool   IsLtfPoolInverted(const bool isSupply, const double poolLo, const double poolHi);
double GetHtfRiskPercentForDirection(const int ltfTradeDirection);
double CalcLotsForRiskPercent(const int direction, const double riskPct, const double entry, const double sl);
double FvgReferenceChartHeight(const ENUM_TIMEFRAMES tf);
bool   FvgGapMeetsMinPct(const ENUM_TIMEFRAMES tf, const double zoneLo, const double zoneHi);
void   ProcessHtfNewCandle();
void   ProcessLtfNewCandle();
bool   FindLtfThreeBarFvgForPlan(const int wantDir, double &outGapLo, double &outGapHi, int &outAnchorShift);
int    ClassifyLtfFvgPattern(const bool bullish, const double ltfGapLo, const double ltfGapHi);
bool   ExecutePlanOrders(const int direction, const double entry, const double sl,
                         const int patternId, const double lotsEach);
bool   StopsLevelOk(const int direction, const double entry, const double sl, const double tp);
void   ApplyTradeFillingFromSymbol();
void   UpdateLtfHuntDirectionArrow();
void   UpdateLtfFvgHuntDebugDraw();
void   DiagnoseWhyNoLtfTradeIfApplicable();

#define OBJ_LTF_HUNT_ARROW "EA_LTF_HUNT_ARROW"
#define PREFIX_LTF_FVG_RECT "LTF_FVG_"

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicPlan);
   ApplyTradeFillingFromSymbol();

   if(InpSwitchChartToLtf)
   {
      ChartSetSymbolPeriod(0, _Symbol, InpLTF);
      ChartRedraw(0);
   }

   if((long)PeriodSeconds(InpLTF) >= (long)PeriodSeconds(InpHTF))
   {
      Print("detect_swing: InpLTF must be lower than InpHTF (e.g. M2 vs M15). Fix inputs.");
      return(INIT_FAILED);
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("detect_swing: AutoTrading is OFF in terminal — enable the AutoTrading button to place orders.");
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      Print("detect_swing: Trading not allowed for this EA — check Common tab / account permissions.");
   if(!InpEnableHtfLtfPlan)
      Print("detect_swing: InpEnableHtfLtfPlan=false — no live orders when setup triggers.");
   Print("detect_swing: LTF-first — (1) LTF liquidity sweep vs LTF swing pools (2) LTF FVG (min gap) ",
         "(3) HTF swing sets risk % (aligned/counter/neutral). SL = ", InpSlPctOfLtfChartHeight,
         "% of LTF ", InpChartRangeBars, "-bar range. InpPlanRequireSwingStructure=", InpPlanRequireSwingStructure, ".");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "M15_Swing_", -1, -1);
   ObjectsDeleteAll(0, "LTF_Swing_", -1, -1);
   ObjectsDeleteAll(0, "M15_FVG_", -1, -1);
   ObjectsDeleteAll(0, "M15_SWLBL_", -1, -1);
   ObjectsDeleteAll(0, "LTF_SWLBL_", -1, -1);
   ObjectDelete(0, OBJ_LTF_HUNT_ARROW);
   ObjectsDeleteAll(0, PREFIX_LTF_FVG_RECT, -1, -1);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnTick()
{
   const datetime htfOpen = iTime(_Symbol, InpHTF, 0);
   if(htfOpen != g_lastHtfBarTime)
   {
      g_lastHtfBarTime = htfOpen;
      ProcessHtfNewCandle();
   }

   const datetime ltfOpen = iTime(_Symbol, InpLTF, 0);
   if(ltfOpen != g_lastLtfBarTime)
   {
      g_lastLtfBarTime = ltfOpen;
      ProcessLtfNewCandle();
   }

   UpdateLtfHuntDirectionArrow();
   UpdateLtfFvgHuntDebugDraw();
}

//+------------------------------------------------------------------+
//| Top-right ▲/▼ while hunting same-direction LTF FVG (post-absorb)   |
//+------------------------------------------------------------------+
void UpdateLtfHuntDirectionArrow()
{
   const bool hunting = (g_ltfHuntDir != 0);

   if(!hunting)
   {
      if(ObjectFind(0, OBJ_LTF_HUNT_ARROW) >= 0)
         ObjectDelete(0, OBJ_LTF_HUNT_ARROW);
      return;
   }

   if(ObjectFind(0, OBJ_LTF_HUNT_ARROW) < 0)
   {
      if(!ObjectCreate(0, OBJ_LTF_HUNT_ARROW, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, OBJ_LTF_HUNT_ARROW, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, OBJ_LTF_HUNT_ARROW, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, OBJ_LTF_HUNT_ARROW, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, OBJ_LTF_HUNT_ARROW, OBJPROP_HIDDEN, true);
      ObjectSetString(0, OBJ_LTF_HUNT_ARROW, OBJPROP_FONT, "Arial Bold");
   }

   ObjectSetInteger(0, OBJ_LTF_HUNT_ARROW, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, OBJ_LTF_HUNT_ARROW, OBJPROP_YDISTANCE, 22);
   ObjectSetInteger(0, OBJ_LTF_HUNT_ARROW, OBJPROP_FONTSIZE, 28);
   const bool isBull = (g_ltfHuntDir == 1);
   ObjectSetInteger(0, OBJ_LTF_HUNT_ARROW, OBJPROP_COLOR, isBull ? clrLime : clrTomato);
   ObjectSetString(0, OBJ_LTF_HUNT_ARROW, OBJPROP_TEXT,
                     isBull ? CharToString(0x25B2) : CharToString(0x25BC));
}

//+------------------------------------------------------------------+
//| One persistent OBJ_RECTANGLE per LTF bar (hunt): FVG at t3–t1 price |
//+------------------------------------------------------------------+
void UpdateLtfFvgHuntDebugDraw()
{
   if(!InpDrawLtfFvgWhileHunting)
      return;

   const bool hunting = (g_ltfHuntDir != 0);
   if(!hunting)
   {
      g_ltfFvgDbgBarProcessed = 0;
      return;
   }

   const datetime t1 = iTime(_Symbol, InpLTF, 1);
   if(t1 == g_ltfFvgDbgBarProcessed)
      return;

   const int wantDir = g_ltfHuntDir;
   double gLo, gHi;
   int fvgSh;
   if(!FindLtfThreeBarFvgForPlan(wantDir, gLo, gHi, fvgSh))
   {
      g_ltfFvgDbgBarProcessed = t1;
      return;
   }

   const bool ltfIsBull = (wantDir == 1);
   const double h1 = iHigh(_Symbol, InpLTF, fvgSh);
   const double l1 = iLow(_Symbol, InpLTF, fvgSh);
   const double h3 = iHigh(_Symbol, InpLTF, fvgSh + 2);
   const double l3 = iLow(_Symbol, InpLTF, fvgSh + 2);
   const datetime t3 = iTime(_Symbol, InpLTF, fvgSh + 2);
   const datetime t1f = iTime(_Symbol, InpLTF, fvgSh);

   const bool sigOk = FvgGapMeetsMinPct(InpLTF, gLo, gHi);
   const bool dirMatch = (ltfIsBull == (wantDir == 1));

   bool swingStructOk = false;
   if(ltfState.swingCount >= 1)
   {
      const Swing lastSwing = ltfState.swings[ltfState.swingCount - 1];
      if(ltfIsBull)
         swingStructOk = (lastSwing.direction == -1 && ltfState.current.direction == 1 && l1 > h3);
      else
         swingStructOk = (lastSwing.direction == 1 && ltfState.current.direction == -1 && h1 < l3);
   }

   const datetime tA = (t3 <= t1f) ? t3 : t1f;
   const datetime tB = (t3 <= t1f) ? t1f : t3;
   const double pLo = MathMin(gLo, gHi);
   const double pHi = MathMax(gLo, gHi);

   const int newSeq = g_ltfFvgPersistSeq + 1;
   if(newSeq > InpLtfMaxPersistFvgRects)
   {
      const int oldId = newSeq - InpLtfMaxPersistFvgRects;
      ObjectDelete(0, PREFIX_LTF_FVG_RECT + IntegerToString(oldId));
   }

   const string name = PREFIX_LTF_FVG_RECT + IntegerToString(newSeq);
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, tA, pHi, tB, pLo))
      return;

   g_ltfFvgPersistSeq = newSeq;
   g_ltfFvgDbgBarProcessed = t1;

   color fillCol = clrDarkSlateGray;
   if(dirMatch && sigOk && swingStructOk)
      fillCol = ltfIsBull ? clrDodgerBlue : clrDarkOrange;
   else if(dirMatch)
      fillCol = ltfIsBull ? clrSteelBlue : clrCoral;
   else
      fillCol = clrDimGray;

   ObjectSetInteger(0, name, OBJPROP_COLOR, fillCol);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP,
                   StringFormat("LTF %s | minSz:%s dir:%s swing:%s",
                                ltfIsBull ? "bull" : "bear",
                                sigOk ? "ok" : "no",
                                dirMatch ? "ok" : "bad",
                                swingStructOk ? "ok" : "no"));
}

//+------------------------------------------------------------------+
//| HTF: bias + pools (swing legs + FVG)                              |
//+------------------------------------------------------------------+
void ProcessHtfNewCandle()
{
   ProcessSwingStep(m15State, InpHTF);
   TryAddM15FvgFromLastClosedBar();
}

//+------------------------------------------------------------------+
//| One closed-bar step of swing logic (same rules as original EA)    |
//+------------------------------------------------------------------+
void ProcessSwingStep(SwingState &st, const ENUM_TIMEFRAMES tf)
{
   const double open_t  = iOpen(_Symbol, tf, 1);
   const double close_t = iClose(_Symbol, tf, 1);
   const double high_t  = iHigh(_Symbol, tf, 1);
   const double low_t   = iLow(_Symbol, tf, 1);

   const int    candleDir = (close_t > open_t) ? 1 : ((close_t < open_t) ? -1 : 0);
   const double range_t   = high_t - low_t;

   if(st.current.direction == 0)
   {
      SwingStartNew(st, tf, candleDir, high_t, low_t);
      st.anchor = (high_t + low_t) / 2.0;
      return;
   }

   double totalRange = 0.0;
   for(int i = 2; i <= 11; i++)
      totalRange += (iHigh(_Symbol, tf, i) - iLow(_Symbol, tf, i));
   const double avgRange = totalRange / 10.0;

   const bool isDecentMovement = (range_t > (avgRange * 1.0));
   if(isDecentMovement && candleDir == st.current.direction)
      st.anchor = (high_t + low_t) / 2.0;

   int nextSwingDir = st.current.direction;
   if(st.current.direction == 1 && close_t < st.anchor)
      nextSwingDir = -1;
   else if(st.current.direction == -1 && close_t > st.anchor)
      nextSwingDir = 1;

   if(nextSwingDir == st.current.direction)
   {
      SwingExtend(st, high_t, low_t);
   }
   else
   {
      const color  swingCol = (tf == InpHTF) ? clrDodgerBlue : clrYellow;
      const string swingPrefix = (tf == InpHTF) ? "M15_Swing_" : "LTF_Swing_";
      SwingClose(st, tf, swingCol, swingPrefix);

      Swing closed = st.swings[st.swingCount - 1];
      double nh = high_t;
      double nl = low_t;
      if(closed.direction == 1 && nextSwingDir == -1)
         nh = MathMax(high_t, closed.high);
      else if(closed.direction == -1 && nextSwingDir == 1)
         nl = MathMin(low_t, closed.low);

      SwingStartNew(st, tf, nextSwingDir, nh, nl);
      st.anchor = (high_t + low_t) / 2.0;
   }
}

//+------------------------------------------------------------------+
void SwingStartNew(SwingState &st, const ENUM_TIMEFRAMES tf, const int dir, const double h, const double l)
{
   st.current.direction  = dir;
   st.current.high       = h;
   st.current.low        = l;
   st.current.startTime  = iTime(_Symbol, tf, 1);
}

//+------------------------------------------------------------------+
void SwingExtend(SwingState &st, const double h, const double l)
{
   if(h > st.current.high) st.current.high = h;
   if(l < st.current.low)  st.current.low  = l;
}

//+------------------------------------------------------------------+
void SwingClose(SwingState &st, const ENUM_TIMEFRAMES tf, const color col, const string prefix)
{
   st.current.endTime = iTime(_Symbol, tf, 1);

   if(tf == InpHTF)
   {
      const double lo = st.current.low;
      const double hi = st.current.high;
      const bool   supply = (st.current.direction == 1);
      PushM15Pool(lo, hi, supply);
   }
   else if(tf == InpLTF)
   {
      const double lo = st.current.low;
      const double hi = st.current.high;
      const bool   supply = (st.current.direction == 1);
      PushLtfPool(lo, hi, supply);
   }

   const string name = prefix + IntegerToString((long)st.current.endTime);

   double startPrice, endPrice;
   if(st.current.direction == 1)
   {
      startPrice = st.current.low;
      endPrice   = st.current.high;
   }
   else
   {
      startPrice = st.current.high;
      endPrice   = st.current.low;
   }

   if(tf == InpHTF && InpHtfDrawSwingLines)
   {
      if(ObjectCreate(0, name, OBJ_TREND, 0, st.current.startTime, startPrice, st.current.endTime, endPrice))
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, col);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
   }
   else if(tf == InpLTF && InpLtfDrawSwingLines)
   {
      if(ObjectCreate(0, name, OBJ_TREND, 0, st.current.startTime, startPrice, st.current.endTime, endPrice))
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, col);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
   }

   if(tf == InpHTF && InpHtfDrawSwingLabels)
   {
      const bool isUpLeg = (st.current.direction == 1);
      DrawSwingLegLabel("M15_SWLBL_", st.current.endTime, endPrice, isUpLeg);
   }
   else if(tf == InpLTF && InpLtfDrawSwingLabels)
   {
      const bool isUpLeg = (st.current.direction == 1);
      DrawSwingLegLabel("LTF_SWLBL_", st.current.endTime, endPrice, isUpLeg);
   }

   if(st.swingCount < 20)
   {
      st.swings[st.swingCount] = st.current;
      st.swingCount++;
   }
   else
   {
      for(int i = 1; i < 20; i++)
         st.swings[i - 1] = st.swings[i];
      st.swings[19] = st.current;
   }
}

//+------------------------------------------------------------------+
void PushM15Pool(const double lo, const double hi, const bool isSupply)
{
   if(lo >= hi)
      return;

   if(g_m15PoolCount < HTF_POOL_CAP)
   {
      g_m15Pools[g_m15PoolCount].lo = lo;
      g_m15Pools[g_m15PoolCount].hi = hi;
      g_m15Pools[g_m15PoolCount].isSupply = isSupply;
      g_m15PoolCount++;
   }
   else
   {
      for(int i = 1; i < HTF_POOL_CAP; i++)
         g_m15Pools[i - 1] = g_m15Pools[i];
      g_m15Pools[HTF_POOL_CAP - 1].lo = lo;
      g_m15Pools[HTF_POOL_CAP - 1].hi = hi;
      g_m15Pools[HTF_POOL_CAP - 1].isSupply = isSupply;
   }
}

//+------------------------------------------------------------------+
void PushLtfPool(const double lo, const double hi, const bool isSupply)
{
   if(lo >= hi)
      return;

   if(g_ltfPoolCount < LTF_POOL_CAP)
   {
      g_ltfPools[g_ltfPoolCount].lo = lo;
      g_ltfPools[g_ltfPoolCount].hi = hi;
      g_ltfPools[g_ltfPoolCount].isSupply = isSupply;
      g_ltfPoolCount++;
   }
   else
   {
      for(int i = 1; i < LTF_POOL_CAP; i++)
         g_ltfPools[i - 1] = g_ltfPools[i];
      g_ltfPools[LTF_POOL_CAP - 1].lo = lo;
      g_ltfPools[LTF_POOL_CAP - 1].hi = hi;
      g_ltfPools[LTF_POOL_CAP - 1].isSupply = isSupply;
   }
}

//+------------------------------------------------------------------+
//| Chart "height": highest high − lowest low over InpChartRangeBars   |
//+------------------------------------------------------------------+
double FvgReferenceChartHeight(const ENUM_TIMEFRAMES tf)
{
   const int n = InpChartRangeBars;
   if(n < 1)
      return 0.0;

   const int bars = iBars(_Symbol, tf);
   if(bars < n + 1)
      return 0.0;

   double hh = -1.0e100;
   double ll = 1.0e100;
   for(int i = 1; i <= n; i++)
   {
      hh = MathMax(hh, iHigh(_Symbol, tf, i));
      ll = MathMin(ll, iLow(_Symbol, tf, i));
   }
   return hh - ll;
}

//+------------------------------------------------------------------+
bool FvgGapMeetsMinPct(const ENUM_TIMEFRAMES tf, const double zoneLo, const double zoneHi)
{
   if(InpFvgMinPctOfRange <= 0.0)
      return true;

   const double gap = MathAbs(zoneHi - zoneLo);
   if(gap <= 0.0)
      return false;

   const double ref = FvgReferenceChartHeight(tf);
   if(ref <= 0.0)
      return true;

   return (gap >= ref * (InpFvgMinPctOfRange / 100.0));
}

//+------------------------------------------------------------------+
bool M15FvgGapIsSignificant(const double zoneLo, const double zoneHi)
{
   return FvgGapMeetsMinPct(InpHTF, zoneLo, zoneHi);
}

//+------------------------------------------------------------------+
//| HTF FVG on last closed bar vs bar 3 (same definition as LTF)       |
//+------------------------------------------------------------------+
void TryAddM15FvgFromLastClosedBar()
{
   const double h1 = iHigh(_Symbol, InpHTF, 1);
   const double l1 = iLow(_Symbol, InpHTF, 1);
   const double h3 = iHigh(_Symbol, InpHTF, 3);
   const double l3 = iLow(_Symbol, InpHTF, 3);

   if(l1 > h3)
   {
      if(!M15FvgGapIsSignificant(h3, l1))
         return;
      PushM15Pool(h3, l1, false);
      const datetime t1b = iTime(_Symbol, InpHTF, 1);
      if(InpHtfDrawFvgZones)
      {
         const datetime t3 = iTime(_Symbol, InpHTF, 3);
         const datetime t1 = t1b;
         DrawM15FvgZone(true, h3, l1, t3, t1);
      }
   }
   else if(h1 < l3)
   {
      if(!M15FvgGapIsSignificant(h1, l3))
         return;
      PushM15Pool(h1, l3, true);
      const datetime t1b = iTime(_Symbol, InpHTF, 1);
      if(InpHtfDrawFvgZones)
      {
         const datetime t3 = iTime(_Symbol, InpHTF, 3);
         const datetime t1 = t1b;
         DrawM15FvgZone(false, h1, l3, t3, t1);
      }
   }
}

//+------------------------------------------------------------------+
void DrawM15FvgZone(const bool isBullish, const double zoneLo, const double zoneHi,
                    const datetime tLeft, const datetime tRight)
{
   g_m15FvgPlotSeq++;
   const string name = "M15_FVG_" + IntegerToString(g_m15FvgPlotSeq);
   if(g_m15FvgPlotSeq > InpHtfMaxFvgRectangles)
   {
      const string oldName = "M15_FVG_" + IntegerToString(g_m15FvgPlotSeq - InpHtfMaxFvgRectangles);
      ObjectDelete(0, oldName);
   }

   const datetime tA = (tLeft <= tRight) ? tLeft : tRight;
   const datetime tB = (tLeft <= tRight) ? tRight : tLeft;
   const double pLo = MathMin(zoneLo, zoneHi);
   const double pHi = MathMax(zoneLo, zoneHi);

   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, tA, pHi, tB, pLo))
      return;

   const color c = isBullish ? clrLime : clrTomato;
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void DrawSwingLegLabel(const string prefix, const datetime t, const double price, const bool isUpLeg)
{
   const string name = prefix + IntegerToString((long)t);
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double y = isUpLeg ? (price + pt * 8.0) : (price - pt * 8.0);

   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, y))
      return;

   ObjectSetString(0, name, OBJPROP_TEXT, isUpLeg ? "H" : "L");
   ObjectSetInteger(0, name, OBJPROP_COLOR, isUpLeg ? clrDodgerBlue : clrOrange);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isUpLeg ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
bool RangeOverlaps(const double aLo, const double aHi, const double bLo, const double bHi)
{
   return (aLo <= bHi && aHi >= bLo);
}

//+------------------------------------------------------------------+
//| Inversion: last closed M15 bar fully on the wrong side of zone   |
//+------------------------------------------------------------------+
bool IsM15PoolInverted(const bool isSupply, const double poolLo, const double poolHi)
{
   const double m15Hi = iHigh(_Symbol, InpHTF, 1);
   const double m15Lo = iLow(_Symbol, InpHTF, 1);

   if(isSupply)
      return (m15Lo > poolHi);

   return (m15Hi < poolLo);
}

//+------------------------------------------------------------------+
bool LtfPoolTouch(const double poolLo, const double poolHi, const int lookback)
{
   const int last = MathMin(lookback, iBars(_Symbol, InpLTF) - 2);
   if(last < 2)
      return false;

   for(int sh = 2; sh <= last; sh++)
   {
      const double hi = iHigh(_Symbol, InpLTF, sh);
      const double lo = iLow(_Symbol, InpLTF, sh);
      if(RangeOverlaps(lo, hi, poolLo, poolHi))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Resistance: wick above pool top, later wick below pool bottom     |
//+------------------------------------------------------------------+
bool LtfSweepBearishThroughPool(const double poolLo, const double poolHi, const int lookback)
{
   const int last = MathMin(lookback, iBars(_Symbol, InpLTF) - 2);
   if(last < 2)
      return false;

   bool seenAbovePoolTop = false;
   for(int sh = last; sh >= 2; sh--)
   {
      if(iHigh(_Symbol, InpLTF, sh) > poolHi)
         seenAbovePoolTop = true;
      if(seenAbovePoolTop && iLow(_Symbol, InpLTF, sh) < poolLo)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Support: wick below pool bottom, later wick above pool top        |
//+------------------------------------------------------------------+
bool LtfSweepBullishThroughPool(const double poolLo, const double poolHi, const int lookback)
{
   const int last = MathMin(lookback, iBars(_Symbol, InpLTF) - 2);
   if(last < 2)
      return false;

   bool seenBelowPoolBottom = false;
   for(int sh = last; sh >= 2; sh--)
   {
      if(iLow(_Symbol, InpLTF, sh) < poolLo)
         seenBelowPoolBottom = true;
      if(seenBelowPoolBottom && iHigh(_Symbol, InpLTF, sh) > poolHi)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool LtfReactedToPool(const bool isSupply, const double poolLo, const double poolHi, const int lookback)
{
   if(LtfPoolTouch(poolLo, poolHi, lookback))
      return true;

   if(isSupply)
      return LtfSweepBearishThroughPool(poolLo, poolHi, lookback);

   return LtfSweepBullishThroughPool(poolLo, poolHi, lookback);
}

//+------------------------------------------------------------------+
//| LTF pools: last closed LTF bar fully wrong side of zone           |
//+------------------------------------------------------------------+
bool IsLtfPoolInverted(const bool isSupply, const double poolLo, const double poolHi)
{
   const double hi1 = iHigh(_Symbol, InpLTF, 1);
   const double lo1 = iLow(_Symbol, InpLTF, 1);

   if(isSupply)
      return (lo1 > poolHi);

   return (hi1 < poolLo);
}

//+------------------------------------------------------------------+
//| LTF swing bias + LTF liquidity pools + LTF sweep / touch         |
//+------------------------------------------------------------------+
bool PassesLtfLiquidityFilter(const int tradeDirection)
{
   if(g_ltfPoolCount <= 0)
      return false;

   const int lb = InpLtfReactionLookback;

   if(tradeDirection == 1)
   {
      if(ltfState.current.direction != 1)
         return false;

      for(int p = 0; p < g_ltfPoolCount; p++)
      {
         if(g_ltfPools[p].isSupply)
            continue;

         const double lo = g_ltfPools[p].lo;
         const double hi = g_ltfPools[p].hi;

         if(IsLtfPoolInverted(false, lo, hi))
            continue;

         if(LtfReactedToPool(false, lo, hi, lb))
            return true;
      }
      return false;
   }

   if(tradeDirection == -1)
   {
      if(ltfState.current.direction != -1)
         return false;

      for(int p = 0; p < g_ltfPoolCount; p++)
      {
         if(!g_ltfPools[p].isSupply)
            continue;

         const double lo = g_ltfPools[p].lo;
         const double hi = g_ltfPools[p].hi;

         if(IsLtfPoolInverted(true, lo, hi))
            continue;

         if(LtfReactedToPool(true, lo, hi, lb))
            return true;
      }
      return false;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Most recent LTF 3-bar FVG (bar[sh] vs bar[sh+2]) meeting min gap.  |
//+------------------------------------------------------------------+
bool FindLtfThreeBarFvgForPlan(const int wantDir, double &outGapLo, double &outGapHi, int &outAnchorShift)
{
   outAnchorShift = -1;
   const int bars = iBars(_Symbol, InpLTF);
   if(bars < 4)
      return false;

   int maxSh = InpLtfFvgEntryLookback;
   if(maxSh < 1)
      maxSh = 1;
   const int cap = bars - 3;
   if(cap < 1)
      return false;
   if(maxSh > cap)
      maxSh = cap;

   for(int sh = 1; sh <= maxSh; sh++)
   {
      if(wantDir == 1)
      {
         const double l1 = iLow(_Symbol, InpLTF, sh);
         const double h3 = iHigh(_Symbol, InpLTF, sh + 2);
         if(l1 <= h3)
            continue;

         const double gLo = h3;
         const double gHi = l1;
         if(!FvgGapMeetsMinPct(InpLTF, gLo, gHi))
            continue;

         outGapLo = gLo;
         outGapHi = gHi;
         outAnchorShift = sh;
         return true;
      }

      const double h1 = iHigh(_Symbol, InpLTF, sh);
      const double l3 = iLow(_Symbol, InpLTF, sh + 2);
      if(h1 >= l3)
         continue;

      const double gLo = h1;
      const double gHi = l3;
      if(!FvgGapMeetsMinPct(InpLTF, gLo, gHi))
         continue;

      outGapLo = gLo;
      outGapHi = gHi;
      outAnchorShift = sh;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| SL: InpSlPctOfLtfChartHeight × LTF 147-bar range from far FVG edge |
//+------------------------------------------------------------------+
double SlFromFarLtfFvgEdge(const int direction, const double ltfGapLo, const double ltfGapHi)
{
   const double h = FvgReferenceChartHeight(InpLTF);
   if(h <= 0.0)
      return 0.0;

   const double d = h * (InpSlPctOfLtfChartHeight / 100.0);
   if(direction == 1)
   {
      const double far = MathMax(ltfGapLo, ltfGapHi);
      return far - d;
   }
   const double far = MathMin(ltfGapLo, ltfGapHi);
   return far + d;
}

//+------------------------------------------------------------------+
//| 1 = near edge of LTF gap, 2 = far edge (uses LTF chart height ref)|
//+------------------------------------------------------------------+
int ClassifyLtfFvgPattern(const bool bullish, const double ltfGapLo, const double ltfGapHi)
{
   const double gapR = ltfGapHi - ltfGapLo;
   if(gapR <= 0.0)
      return 2;

   const double ref = FvgReferenceChartHeight(InpLTF);
   const double th = (InpLtfNearPatternMaxPctOfGap / 100.0) * (ref > 0.0 ? ref : gapR);

   if(bullish)
      return (gapR <= th * 2.0) ? 1 : 2;

   return (gapR <= th * 2.0) ? 1 : 2;
}

//+------------------------------------------------------------------+
//| HTF swing vs LTF trade: aligned / counter / neutral risk %        |
//+------------------------------------------------------------------+
double GetHtfRiskPercentForDirection(const int ltfTradeDirection)
{
   if(m15State.current.direction == 0)
      return InpRiskPctHtfNeutral;

   if(ltfTradeDirection == m15State.current.direction)
      return InpRiskPctHtfAligned;

   return InpRiskPctHtfCounter;
}

//+------------------------------------------------------------------+
//| Position size from %% balance at SL (fallback InpEntryLotsFallback)|
//+------------------------------------------------------------------+
double CalcLotsForRiskPercent(const int direction, const double riskPct, const double entry, const double sl)
{
   if(riskPct <= 0.0)
      return InpEntryLotsFallback;

   double profit = 0.0;
   const ENUM_ORDER_TYPE t = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(t, _Symbol, 1.0, entry, sl, profit))
      return InpEntryLotsFallback;

   double lossPerLot = (profit <= 0.0) ? -profit : profit;
   if(lossPerLot <= 0.0)
      return InpEntryLotsFallback;

   const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   const double riskMoney = bal * (riskPct / 100.0);
   double lots = riskMoney / lossPerLot;

   const double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step > 0.0)
      lots = MathFloor(lots / step) * step;
   if(lots < vmin)
      lots = vmin;
   if(lots > vmax)
      lots = vmax;

   return lots;
}

//+------------------------------------------------------------------+
bool StopsLevelOk(const int direction, const double entry, const double sl, const double tp)
{
   const int stops = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minDist = (double)stops * pt;
   if(minDist <= 0.0)
      return true;

   if(direction == 1)
   {
      if(MathAbs(entry - sl) < minDist)
         return false;
      if(MathAbs(tp - entry) < minDist)
         return false;
   }
   else
   {
      if(MathAbs(sl - entry) < minDist)
         return false;
      if(MathAbs(entry - tp) < minDist)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void ApplyTradeFillingFromSymbol()
{
   const long fm = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(fm == 0)
      return;
   if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
bool ExecutePlanOrders(const int direction, const double entryRaw, const double slRaw, const int patternId,
                       const double lotsEach)
{
   const double entry = NormalizeDouble(entryRaw, _Digits);
   double       sl    = NormalizeDouble(slRaw, _Digits);

   const double risk = MathAbs(entry - sl);
   if(risk <= SymbolInfoDouble(_Symbol, SYMBOL_POINT))
   {
      Print("ExecutePlanOrders: risk too small");
      return false;
   }
   if(direction == 1 && sl >= entry)
   {
      Print("ExecutePlanOrders: invalid bull SL vs entry");
      return false;
   }
   if(direction == -1 && sl <= entry)
   {
      Print("ExecutePlanOrders: invalid bear SL vs entry");
      return false;
   }

   double tp2, tp3;
   if(direction == 1)
   {
      tp2 = NormalizeDouble(entry + 2.0 * risk, _Digits);
      tp3 = NormalizeDouble(entry + 3.0 * risk, _Digits);
   }
   else
   {
      tp2 = NormalizeDouble(entry - 2.0 * risk, _Digits);
      tp3 = NormalizeDouble(entry - 3.0 * risk, _Digits);
   }

   if(!StopsLevelOk(direction, entry, sl, tp2) || !StopsLevelOk(direction, entry, sl, tp3))
   {
      Print("ExecutePlanOrders: broker stops level — adjust SL buffer or entry. entry=", entry,
            " sl=", sl, " tp2=", tp2, " stopsPts=", SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
      return false;
   }

   if(!InpEnableHtfLtfPlan)
   {
      const double lotUse = MathMax(InpEntryLotsFallback, lotsEach);
      Print("Setup OK — orders skipped (InpEnableHtfLtfPlan=false). entry=", entry,
            " sl=", sl, " TP2=", tp2, " TP3=", tp3, " lots=", lotUse);
      return true;
   }

   trade.SetExpertMagicNumber(InpMagicPlan);
   trade.SetDeviationInPoints(30);
   ApplyTradeFillingFromSymbol();

   const double lotUse = MathMax(InpEntryLotsFallback, lotsEach);

   const string cmt = StringFormat("LTF-HTF p%d RR", patternId);
   bool ok1 = false, ok2 = false;

   if(direction == 1)
   {
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(entry > ask)
      {
         Print("ExecutePlanOrders: BuyLimit skipped — entry must be below ask (limit pullback). entry=",
               entry, " ask=", ask);
         return false;
      }
      ok1 = trade.BuyLimit(lotUse, entry, _Symbol, sl, tp2, ORDER_TIME_GTC, 0, cmt + " 1:2");
      if(!ok1)
         Print("BuyLimit 1:2 failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription(),
               " ext=", trade.ResultRetcodeExternal());
      ok2 = trade.BuyLimit(lotUse, entry, _Symbol, sl, tp3, ORDER_TIME_GTC, 0, cmt + " 1:3");
      if(!ok2)
         Print("BuyLimit 1:3 failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   else
   {
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(entry < bid)
      {
         Print("ExecutePlanOrders: SellLimit skipped — entry must be above bid. entry=", entry, " bid=", bid);
         return false;
      }
      ok1 = trade.SellLimit(lotUse, entry, _Symbol, sl, tp2, ORDER_TIME_GTC, 0, cmt + " 1:2");
      if(!ok1)
         Print("SellLimit 1:2 failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      ok2 = trade.SellLimit(lotUse, entry, _Symbol, sl, tp3, ORDER_TIME_GTC, 0, cmt + " 1:3");
      if(!ok2)
         Print("SellLimit 1:3 failed: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }

   if(ok1 || ok2)
   {
      Print("Plan orders sent: dir=", direction, " lots=", lotUse, " entry=", entry, " sl=", sl, " TP2=", tp2,
            " TP3=", tp3, " ok1=", ok1, " ok2=", ok2);
      return true;
   }

   Print("Plan orders: both sends failed — check Experts log above and trade permissions.");
   return false;
}

//+------------------------------------------------------------------+
//| LTF-first: LTF sweep + LTF FVG → HTF sets risk % → limits         |
//+------------------------------------------------------------------+
void ProcessLtfNewCandle()
{
   ProcessSwingStep(ltfState, InpLTF);

   const datetime tBar = iTime(_Symbol, InpLTF, 1);
   g_ltfHuntDir = 0;

   bool bullSwingOk = !InpPlanRequireSwingStructure;
   bool bearSwingOk = !InpPlanRequireSwingStructure;
   if(InpPlanRequireSwingStructure)
   {
      if(ltfState.swingCount < 1)
      {
         DiagnoseWhyNoLtfTradeIfApplicable();
         return;
      }
      const Swing lastSwing = ltfState.swings[ltfState.swingCount - 1];
      bullSwingOk = (lastSwing.direction == -1 && ltfState.current.direction == 1);
      bearSwingOk = (lastSwing.direction == 1 && ltfState.current.direction == -1);
   }

   double bullGapLo = 0.0, bullGapHi = 0.0;
   int    bullFvgSh = -1;
   bool   bullSetup = bullSwingOk && PassesLtfLiquidityFilter(1);
   if(bullSetup)
      bullSetup = FindLtfThreeBarFvgForPlan(1, bullGapLo, bullGapHi, bullFvgSh);

   double bearGapLo = 0.0, bearGapHi = 0.0;
   int    bearFvgSh = -1;
   bool   bearSetup = bearSwingOk && PassesLtfLiquidityFilter(-1);
   if(bearSetup)
      bearSetup = FindLtfThreeBarFvgForPlan(-1, bearGapLo, bearGapHi, bearFvgSh);

   if(bullSetup && bearSetup)
   {
      if(ltfState.current.direction == 1)
         bearSetup = false;
      else if(ltfState.current.direction == -1)
         bullSetup = false;
      else
         bullSetup = false;
   }

   if(bullSetup)
      g_ltfHuntDir = 1;
   else if(bearSetup)
      g_ltfHuntDir = -1;

   if(g_lastPlanLtfBarTime == tBar)
   {
      DiagnoseWhyNoLtfTradeIfApplicable();
      return;
   }

   if(!bullSetup && !bearSetup)
   {
      DiagnoseWhyNoLtfTradeIfApplicable();
      return;
   }

   if(bullSetup)
   {
      int pat = ClassifyLtfFvgPattern(true, bullGapLo, bullGapHi);
      double entry = (pat == 1) ? bullGapLo : bullGapHi;

      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(entry > ask && bullGapLo <= ask && bullGapLo < bullGapHi)
      {
         Print("Bull plan: pattern edge (p", pat, ") above ask — using near FVG edge. ask=", ask,
               " use=", bullGapLo);
         entry = bullGapLo;
         pat = 1;
      }
      if(entry > ask)
      {
         Print("Bull plan: BuyLimit skipped — whole FVG gap above ask. ask=", ask,
               " gap ", bullGapLo, "–", bullGapHi);
         DiagnoseWhyNoLtfTradeIfApplicable();
         return;
      }

      const double sl = SlFromFarLtfFvgEdge(1, bullGapLo, bullGapHi);
      if(sl <= 0.0 || sl >= entry)
      {
         Print("Bull plan: SL from far edge invalid. sl=", sl, " entry=", entry);
         DiagnoseWhyNoLtfTradeIfApplicable();
         return;
      }

      const double rp = GetHtfRiskPercentForDirection(1);
      const double lots = CalcLotsForRiskPercent(1, rp, entry, sl);
      Print("LTF bull setup: HTF risk%=", rp, " lots≈", lots, " HTF swingDir=", m15State.current.direction);

      if(ExecutePlanOrders(1, entry, sl, pat, lots))
      {
         g_lastPlanLtfBarTime = tBar;
         lastBullishSignalTime = ltfState.current.startTime;
      }
   }
   else if(bearSetup)
   {
      int pat = ClassifyLtfFvgPattern(false, bearGapLo, bearGapHi);
      double entry = (pat == 1) ? bearGapHi : bearGapLo;

      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(entry < bid && bearGapHi >= bid && bearGapLo < bearGapHi)
      {
         Print("Bear plan: pattern edge (p", pat, ") below bid — using far FVG edge. bid=", bid,
               " use=", bearGapHi);
         entry = bearGapHi;
         pat = 1;
      }
      if(entry < bid)
      {
         Print("Bear plan: SellLimit skipped — whole FVG gap below bid. bid=", bid,
               " gap ", bearGapLo, "–", bearGapHi);
         DiagnoseWhyNoLtfTradeIfApplicable();
         return;
      }

      const double sl = SlFromFarLtfFvgEdge(-1, bearGapLo, bearGapHi);
      if(sl <= 0.0 || sl <= entry)
      {
         Print("Bear plan: SL from far edge invalid. sl=", sl, " entry=", entry);
         DiagnoseWhyNoLtfTradeIfApplicable();
         return;
      }

      const double rp = GetHtfRiskPercentForDirection(-1);
      const double lots = CalcLotsForRiskPercent(-1, rp, entry, sl);
      Print("LTF bear setup: HTF risk%=", rp, " lots≈", lots, " HTF swingDir=", m15State.current.direction);

      if(ExecutePlanOrders(-1, entry, sl, pat, lots))
      {
         g_lastPlanLtfBarTime = tBar;
         lastBearishSignalTime = ltfState.current.startTime;
      }
   }

   DiagnoseWhyNoLtfTradeIfApplicable();
}

//+------------------------------------------------------------------+
//| One log per LTF bar: first reason plan did not fire (debug)        |
//+------------------------------------------------------------------+
void DiagnoseWhyNoLtfTradeIfApplicable()
{
   if(!InpLogWhyNoTrade)
      return;

   const datetime t1 = iTime(_Symbol, InpLTF, 1);

   static datetime s_lastDiagBar = 0;
   if(t1 == s_lastDiagBar)
      return;

   if(g_lastPlanLtfBarTime == t1)
   {
      s_lastDiagBar = t1;
      return;
   }

   if(g_ltfPoolCount <= 0)
   {
      s_lastDiagBar = t1;
      Print("detect_swing: no trade — no LTF swing pools yet (need LTF swing legs to build liquidity).");
      return;
   }

   if(InpPlanRequireSwingStructure && ltfState.swingCount < 1)
   {
      s_lastDiagBar = t1;
      Print("detect_swing: no trade — LTF swingCount<1 (InpPlanRequireSwingStructure=true).");
      return;
   }

   bool bullSwingOk = !InpPlanRequireSwingStructure;
   bool bearSwingOk = !InpPlanRequireSwingStructure;
   if(InpPlanRequireSwingStructure)
   {
      const Swing lastSwing = ltfState.swings[ltfState.swingCount - 1];
      bullSwingOk = (lastSwing.direction == -1 && ltfState.current.direction == 1);
      bearSwingOk = (lastSwing.direction == 1 && ltfState.current.direction == -1);
   }

   double ltfGapLo, ltfGapHi;
   int fvgSh;

   if(bullSwingOk && PassesLtfLiquidityFilter(1) && FindLtfThreeBarFvgForPlan(1, ltfGapLo, ltfGapHi, fvgSh))
   {
      s_lastDiagBar = t1;
      Print("detect_swing: bull path — LTF sweep+FVG ok; if no orders, check ask vs entry / StopsLevelOk / broker.");
      return;
   }
   if(bearSwingOk && PassesLtfLiquidityFilter(-1) && FindLtfThreeBarFvgForPlan(-1, ltfGapLo, ltfGapHi, fvgSh))
   {
      s_lastDiagBar = t1;
      Print("detect_swing: bear path — LTF sweep+FVG ok; if no orders, check bid vs entry / broker.");
      return;
   }

   if(!PassesLtfLiquidityFilter(1) && bullSwingOk)
   {
      s_lastDiagBar = t1;
      Print("detect_swing: no trade — LTF liquidity sweep/touch not detected for bull (demand pools, lookback=",
            InpLtfReactionLookback, ").");
      return;
   }
   if(!PassesLtfLiquidityFilter(-1) && bearSwingOk)
   {
      s_lastDiagBar = t1;
      Print("detect_swing: no trade — LTF liquidity sweep/touch not detected for bear (supply pools).");
      return;
   }

   if(!FindLtfThreeBarFvgForPlan(1, ltfGapLo, ltfGapHi, fvgSh))
   {
      s_lastDiagBar = t1;
      Print("detect_swing: no trade — no LTF bull 3-bar FVG (min gap %; sh=1..", InpLtfFvgEntryLookback, ").");
      return;
   }

   s_lastDiagBar = t1;
   Print("detect_swing: no trade — check LTF swing alignment vs sweep/FVG (see inputs).");
}

//+------------------------------------------------------------------+
