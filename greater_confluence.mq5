//+------------------------------------------------------------------+
//| greater_confluence.mq5                                           |
//| Close-only swings (no open / no wick) → H1 BOS → aligned M5 BOS → M5 zone |
//| → M2 retrace into zone → M2 FVG or M2 BOS leg-start entry marks   |
//| No order placement (visual verification only).                   |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.06"

#property description "H1/M5/M2 confluence: body swings, BOS alignment, FVG/leg markers."

//--- inputs
input bool   InputSwitchChartToM2         = true;
input int    InputWarmupBarsPerTf         = 500;   // 0 = off: replay closed bars on init
input double InputFvgMinPercentOfRange    = 0.5;    // min FVG size vs chart range (0 = off)
input int    InputChartRangeBars          = 120;    // bars for range height (FVG filter)

input bool   InputDrawH1BodySwings       = true;
input bool   InputDrawM5BodySwings       = true;
input bool   InputDrawM2BodySwings       = true;

input color  InputColorH1Swing           = clrDodgerBlue;
input color  InputColorM5Swing           = clrGold;
input color  InputColorM2Swing           = clrSilver;

input bool   InputDrawM5Zone             = true;   // FVG rect or leg-start marker
input bool   InputDrawM2EntryMarks         = true;
input color  InputColorM5ZoneFvg         = clrPaleGreen;
input color  InputColorM5ZoneLegStart    = clrOrange;
input color  InputColorM2FvgEntry        = clrLime;
input color  InputColorM2LegStartEntry  = clrMagenta;

input color  InputColorH1BosLabelBull  = clrLime;
input color  InputColorH1BosLabelBear  = clrTomato;
input color  InputColorH1BosLabelNone  = clrSilver;
input int    InputH1BosLabelFontSize    = 11;

input bool   InputDrawM5AlignedBosMarkers = true;  // vline + tag when M5 BOS matches H1 direction
input color  InputColorM5AlignedBosBull   = clrAqua;
input color  InputColorM5AlignedBosBear   = clrDeepPink;

//--- prefixes (chart objects)
const string PFX_H1  = "GC_H1_";
const string PFX_M5  = "GC_M5_";
const string PFX_M2  = "GC_M2_";
const string PFX_M5AL = "GC_M5AL_"; // M5 BOS aligned with H1 (verification markers)
const string PFX_Z5  = "GC_Z5_";
const string PFX_E2  = "GC_E2_";
const string OBJ_H1_BOS_UI = "GC_UI_H1BOS";

#define SWING_HIST 32

struct SwingLeg
{
   double   legHighPrice;   // max(close) over the leg
   double   legLowPrice;    // min(close) over the leg
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection; // 1 up, -1 down, 0 unset
};

struct BodySwingState
{
   SwingLeg currentSwingLeg;
   SwingLeg swingHistory[SWING_HIST];
   int      swingHistoryCount;
   double   priceAnchorLevel;
};

BodySwingState g_h1;
BodySwingState g_m5;
BodySwingState g_m2;

datetime g_lastH1BarOpen = 0;
datetime g_lastM5BarOpen = 0;
datetime g_lastM2BarOpen = 0;

// H1 BOS: 1 bull, -1 bear, 0 none this session
int      g_h1BosDirection = 0;
datetime g_h1BosBarTime   = 0;

// M5 aligned BOS with H1
bool     g_m5BosAligned     = false;
datetime g_m5BosBarTime     = 0;
int      g_m5BosDirection   = 0; // 1 bull, -1 bear
datetime g_m5LegStartAtBos  = 0; // current leg start when M5 BOS fired

// M5 marked zone (FVG rectangle or leg-start line)
bool     g_m5HasMarkedZone = false;
bool     g_m5MarkIsFvg     = false;
double   g_m5ZoneLow       = 0;
double   g_m5ZoneHigh      = 0;
datetime g_m5ZoneTimeLeft  = 0;
datetime g_m5ZoneTimeRight = 0;

// Waiting for retrace into M5 zone, then M2 signal
bool     g_waitingRetraceToM5Zone = false;
bool     g_retraceSeen            = false;
bool     g_m2EntryMarked          = false;

//+------------------------------------------------------------------+
double ReferenceRangeHeight(const ENUM_TIMEFRAMES tf, const int barCount)
{
   if(barCount < 1)
      return 0.0;
   if(iBars(_Symbol, tf) < barCount + 1)
      return 0.0;
   double hi = -1.0e100;
   double lo = 1.0e100;
   for(int i = 1; i <= barCount; i++)
   {
      hi = MathMax(hi, iHigh(_Symbol, tf, i));
      lo = MathMin(lo, iLow(_Symbol, tf, i));
   }
   return hi - lo;
}

//+------------------------------------------------------------------+
bool FvgMinSizeOk(const ENUM_TIMEFRAMES tf, const double zLo, const double zHi)
{
   if(InputFvgMinPercentOfRange <= 0.0)
      return true;
   const double gap = MathAbs(zHi - zLo);
   if(gap <= 0.0)
      return false;
   const double rh = ReferenceRangeHeight(tf, InputChartRangeBars);
   if(rh <= 0.0)
      return true;
   return gap >= rh * (InputFvgMinPercentOfRange / 100.0);
}

//+------------------------------------------------------------------+
// FVG: pattern ending at shift `s` (newest of 3 = bar s), older = s+1, s+2
// Bull: low[s] > high[s+2]; Bear: high[s] < low[s+2]
bool DetectFvgPatternAtEndingShift(const ENUM_TIMEFRAMES tf, const int s,
                                   bool &outBull, double &outZL, double &outZH)
{
   outBull = false;
   outZL = outZH = 0.0;
   if(s < 1 || iBars(_Symbol, tf) < s + 3)
      return false;

   const double l1 = iLow(_Symbol, tf, s);
   const double h1 = iHigh(_Symbol, tf, s);
   const double h3 = iHigh(_Symbol, tf, s + 2);
   const double l3 = iLow(_Symbol, tf, s + 2);

   if(l1 > h3)
   {
      outBull = true;
      outZL = h3;
      outZH = l1;
      if(!FvgMinSizeOk(tf, outZL, outZH))
         return false;
      return true;
   }
   if(h1 < l3)
   {
      outBull = false;
      outZL = h1;
      outZH = l3;
      if(!FvgMinSizeOk(tf, outZL, outZH))
         return false;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void SwingHistoryPush(BodySwingState &st, const SwingLeg &leg)
{
   if(st.swingHistoryCount < SWING_HIST)
   {
      st.swingHistory[st.swingHistoryCount++] = leg;
      return;
   }
   for(int i = 1; i < SWING_HIST; i++)
      st.swingHistory[i - 1] = st.swingHistory[i];
   st.swingHistory[SWING_HIST - 1] = leg;
}

//+------------------------------------------------------------------+
void ProcessBodySwingStep(BodySwingState &st, const ENUM_TIMEFRAMES tf,
                          const string objPrefix, const color swingColor, const bool drawLegs)
{
   const double c = iClose(_Symbol, tf, 1);
   const double prevC = iClose(_Symbol, tf, 2);
   const int    dir   = (c > prevC) ? 1 : ((c < prevC) ? -1 : 0);

   double sumR = 0.0;
   for(int k = 2; k <= 6; k++)
      sumR += (iHigh(_Symbol, tf, k) - iLow(_Symbol, tf, k));
   const double avgR = sumR / 5.0;
   const double barRange = iHigh(_Symbol, tf, 1) - iLow(_Symbol, tf, 1);
   const bool   decent   = (barRange > avgR * .50);

   if(st.currentSwingLeg.swingDirection == 0)
   {
      if(dir == 0)
         return;
      st.currentSwingLeg.swingDirection = dir;
      st.currentSwingLeg.legHighPrice   = c;
      st.currentSwingLeg.legLowPrice    = c;
      st.currentSwingLeg.legStartTime   = iTime(_Symbol, tf, 1);
      st.currentSwingLeg.legEndTime     = iTime(_Symbol, tf, 1);
      st.priceAnchorLevel = c;
      return;
   }

   if(decent && dir == st.currentSwingLeg.swingDirection)
      st.priceAnchorLevel = c;

   int nextDir = st.currentSwingLeg.swingDirection;
   if(st.currentSwingLeg.swingDirection == 1 && c < st.priceAnchorLevel)
      nextDir = -1;
   else if(st.currentSwingLeg.swingDirection == -1 && c > st.priceAnchorLevel)
      nextDir = 1;

   if(nextDir == st.currentSwingLeg.swingDirection)
   {
      if(c > st.currentSwingLeg.legHighPrice)
         st.currentSwingLeg.legHighPrice = c;
      if(c < st.currentSwingLeg.legLowPrice)
         st.currentSwingLeg.legLowPrice = c;
      st.currentSwingLeg.legEndTime = iTime(_Symbol, tf, 1);
   }
   else
   {
      // Include reversal bar in closed leg; next leg seeds from same pivot time/price.
      if(c > st.currentSwingLeg.legHighPrice)
         st.currentSwingLeg.legHighPrice = c;
      if(c < st.currentSwingLeg.legLowPrice)
         st.currentSwingLeg.legLowPrice = c;
      st.currentSwingLeg.legEndTime = iTime(_Symbol, tf, 1);

      SwingLeg closed = st.currentSwingLeg;
      SwingHistoryPush(st, closed);

      if(drawLegs)
      {
         const string name = objPrefix + IntegerToString((long)closed.legEndTime);
         double p0, p1;
         if(closed.swingDirection == 1)
         {
            p0 = closed.legLowPrice;
            p1 = closed.legHighPrice;
         }
         else
         {
            p0 = closed.legHighPrice;
            p1 = closed.legLowPrice;
         }
         if(ObjectFind(0, name) >= 0)
            ObjectDelete(0, name);
         if(ObjectCreate(0, name, OBJ_TREND, 0, closed.legStartTime, p0, closed.legEndTime, p1))
         {
            ObjectSetInteger(0, name, OBJPROP_COLOR, swingColor);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         }
      }

      int nd = dir;
      if(nd == 0)
         nd = nextDir;

      const datetime pivotTime = closed.legEndTime;
      st.currentSwingLeg.swingDirection = nd;
      st.currentSwingLeg.legStartTime     = pivotTime;
      st.currentSwingLeg.legEndTime       = pivotTime;

      if(nd == 1)
      {
         st.currentSwingLeg.legLowPrice  = closed.legLowPrice;
         st.currentSwingLeg.legHighPrice = c;
      }
      else
      {
         st.currentSwingLeg.legHighPrice = closed.legHighPrice;
         st.currentSwingLeg.legLowPrice  = c;
      }
      st.priceAnchorLevel = c;
   }
}

//+------------------------------------------------------------------+
bool TryDetectBosOnLastClosedBar(BodySwingState &st, const ENUM_TIMEFRAMES tf,
                                 bool &outBullishBos)
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
// After warmup, evaluate last closed H1 bar for BOS (same as first live H1 step).
void TryInitH1BosFromLastClosedBar()
{
   bool bull = false;
   if(!TryDetectBosOnLastClosedBar(g_h1, PERIOD_H1, bull))
      return;
   g_h1BosDirection = bull ? 1 : -1;
   g_h1BosBarTime   = iTime(_Symbol, PERIOD_H1, 1);
   ResetConfluenceAfterH1Change();
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
   EnsureH1BosCornerLabel();
   const string up = CharToString((ushort)0x2191); // Unicode UPWARDS ARROW
   const string dn = CharToString((ushort)0x2193); // Unicode DOWNWARDS ARROW
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
// Earliest FVG in time after legStart (scan oldest→newest: high shift s down to 3)
bool FindFirstM5FvgFromLegStart(const datetime legStartTime, const bool wantBullFvg,
                              bool &outBull, double &outZL, double &outZH,
                              datetime &outTLeft, datetime &outTRight)
{
   outBull = false;
   outZL = outZH = 0.0;
   outTLeft = outTRight = 0;
   const int maxS = (int)MathMin(iBars(_Symbol, PERIOD_M5) - 3, InputWarmupBarsPerTf + 200);
   if(maxS < 3)
      return false;

   for(int s = maxS; s >= 3; s--)
   {
      if(iTime(_Symbol, PERIOD_M5, s + 2) < legStartTime)
         continue;

      bool bull;
      double zl, zh;
      if(!DetectFvgPatternAtEndingShift(PERIOD_M5, s, bull, zl, zh))
         continue;
      if(bull != wantBullFvg)
         continue;

      outBull = bull;
      outZL = zl;
      outZH = zh;
      outTLeft  = iTime(_Symbol, PERIOD_M5, s + 2);
      outTRight = iTime(_Symbol, PERIOD_M5, s);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void ClearM5ZoneObjects()
{
   ObjectsDeleteAll(0, PFX_Z5, -1, -1);
}

//+------------------------------------------------------------------+
// Mark last closed M5 bar where BOS direction matched H1 (for verification).
void DrawAlignedM5BosMarker(const datetime bosBarTime, const bool bull)
{
   if(!InputDrawM5AlignedBosMarkers || bosBarTime <= 0)
      return;

   const string base = PFX_M5AL + IntegerToString((long)bosBarTime);
   const color  clr  = bull ? InputColorM5AlignedBosBull : InputColorM5AlignedBosBear;

   const string vname = base + "V";
   if(ObjectFind(0, vname) < 0)
   {
      if(ObjectCreate(0, vname, OBJ_VLINE, 0, bosBarTime, 0))
      {
         ObjectSetInteger(0, vname, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, vname, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, vname, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, vname, OBJPROP_BACK, false);
         ObjectSetInteger(0, vname, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, vname, OBJPROP_HIDDEN, true);
      }
   }

   const double h = iHigh(_Symbol, PERIOD_M5, 1);
   const double l = iLow(_Symbol, PERIOD_M5, 1);
   const double labelPrice = bull ? h + (h - l) * 0.05 : l - (h - l) * 0.05;

   const string tname = base + "T";
   if(ObjectFind(0, tname) < 0)
   {
      if(ObjectCreate(0, tname, OBJ_TEXT, 0, bosBarTime, labelPrice))
      {
         ObjectSetString(0, tname, OBJPROP_TEXT, bull ? "M5 BOS bull = H1" : "M5 BOS bear = H1");
         ObjectSetInteger(0, tname, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, tname, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, tname, OBJPROP_ANCHOR, bull ? ANCHOR_LOWER : ANCHOR_UPPER);
         ObjectSetInteger(0, tname, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, tname, OBJPROP_HIDDEN, true);
      }
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void ClearM2EntryObjects()
{
   ObjectsDeleteAll(0, PFX_E2, -1, -1);
}

//+------------------------------------------------------------------+
void DrawM5ZoneFromFvg(const bool bull, const double zl, const double zh,
                       const datetime tL, const datetime tR)
{
   ClearM5ZoneObjects();
   const string name = PFX_Z5 + "RECT";
   const double lo = MathMin(zl, zh);
   const double hi = MathMax(zl, zh);
   datetime L = (tL <= tR) ? tL : tR;
   datetime R = (tL <= tR) ? tR : tL;
   if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, L, hi, R, lo))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, InputColorM5ZoneFvg);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
void DrawM5LegStartMarker(const datetime t, const double price)
{
   ClearM5ZoneObjects();
   const string name = PFX_Z5 + "START";
   if(ObjectCreate(0, name, OBJ_VLINE, 0, t, 0))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, InputColorM5ZoneLegStart);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   const string txt = PFX_Z5 + "LBL";
   if(ObjectCreate(0, txt, OBJ_TEXT, 0, t, price))
   {
      ObjectSetString(0, txt, OBJPROP_TEXT, "M5 leg");
      ObjectSetInteger(0, txt, OBJPROP_COLOR, InputColorM5ZoneLegStart);
      ObjectSetInteger(0, txt, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, txt, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, txt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, txt, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
bool PriceInsideZone(const double bid, const double ask, const double zLo, const double zHi)
{
   const double lo = MathMin(zLo, zHi);
   const double hi = MathMax(zLo, zHi);
   return (bid <= hi && bid >= lo) || (ask <= hi && ask >= lo) ||
          (bid <= hi && ask >= lo) || (ask >= lo && bid <= hi);
}

//+------------------------------------------------------------------+
void TryMarkM2EntryFvgOrLeg(const int h1Dir, const datetime m2LegStartBeforeBar)
{
   if(!InputDrawM2EntryMarks || g_m2EntryMarked)
      return;
   if(!g_retraceSeen || !g_m5HasMarkedZone)
      return;

   const bool wantBull = (h1Dir == 1);

   bool bullFvg;
   double zl, zh;
   if(DetectFvgPatternAtEndingShift(PERIOD_M2, 1, bullFvg, zl, zh))
   {
      if((wantBull && bullFvg) || (!wantBull && !bullFvg))
      {
         const string name = PFX_E2 + "FVG";
         const double lo = MathMin(zl, zh);
         const double hi = MathMax(zl, zh);
         const datetime L = iTime(_Symbol, PERIOD_M2, 3);
         const datetime R = iTime(_Symbol, PERIOD_M2, 1);
         if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, L, hi, R, lo))
         {
            ObjectSetInteger(0, name, OBJPROP_COLOR, InputColorM2FvgEntry);
            ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, name, OBJPROP_BACK, true);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         }
         g_m2EntryMarked = true;
         return;
      }
   }

   bool m2BullBos = false;
   if(TryDetectBosOnLastClosedBar(g_m2, PERIOD_M2, m2BullBos))
      {
         if((wantBull && m2BullBos) || (!wantBull && !m2BullBos))
         {
         const double c = iClose(_Symbol, PERIOD_M2, 1);
         const double px = c;
         const datetime t = (m2LegStartBeforeBar > 0) ? m2LegStartBeforeBar : g_m2.currentSwingLeg.legStartTime;
         const string name = PFX_E2 + "LEG";
         if(ObjectCreate(0, name, OBJ_ARROW, 0, t, px))
         {
            ObjectSetInteger(0, name, OBJPROP_COLOR, InputColorM2LegStartEntry);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, wantBull ? ANCHOR_TOP : ANCHOR_BOTTOM);
            ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         }
         g_m2EntryMarked = true;
      }
   }
}

//+------------------------------------------------------------------+
void ResetConfluenceAfterH1Change()
{
   g_m5BosAligned       = false;
   g_m5BosBarTime       = 0;
   g_m5BosDirection     = 0;
   g_m5LegStartAtBos     = 0;
   g_m5HasMarkedZone    = false;
   g_m5MarkIsFvg        = false;
   g_waitingRetraceToM5Zone = false;
   g_retraceSeen        = false;
   g_m2EntryMarked      = false;
   ClearM5ZoneObjects();
   ClearM2EntryObjects();
}

//+------------------------------------------------------------------+
// Replay closed bars oldest→newest so swingHistory/current leg match live ProcessBodySwingStep.
// Must use the same "decent" rule as ProcessBodySwingStep (barRange > avgR * 0.50), or state diverges.
void WarmupTf(BodySwingState &st, const ENUM_TIMEFRAMES tf, const string pfx, const color clr, const bool draw)
{
   if(InputWarmupBarsPerTf <= 0)
      return;
   const int n = (int)MathMin(iBars(_Symbol, tf) - 2, InputWarmupBarsPerTf);
   for(int k = n; k >= 1; k--)
   {
      const double c = iClose(_Symbol, tf, k);
      const double prevC = iClose(_Symbol, tf, k + 1);
      const int    dir   = (c > prevC) ? 1 : ((c < prevC) ? -1 : 0);

      if(st.currentSwingLeg.swingDirection == 0)
      {
         if(dir == 0)
            continue;
         st.currentSwingLeg.swingDirection = dir;
         st.currentSwingLeg.legHighPrice   = c;
         st.currentSwingLeg.legLowPrice    = c;
         st.currentSwingLeg.legStartTime   = iTime(_Symbol, tf, k);
         st.currentSwingLeg.legEndTime     = iTime(_Symbol, tf, k);
         st.priceAnchorLevel = c;
         continue;
      }

      double sumR = 0.0;
      for(int j = k + 1; j <= k + 5 && j < iBars(_Symbol, tf); j++)
         sumR += (iHigh(_Symbol, tf, j) - iLow(_Symbol, tf, j));
      const double avgR = sumR / 5.0;
      const double barRange = iHigh(_Symbol, tf, k) - iLow(_Symbol, tf, k);
      const bool   decent   = (barRange > avgR * 0.50); // align with ProcessBodySwingStep
      if(decent && dir == st.currentSwingLeg.swingDirection)
         st.priceAnchorLevel = c;

      int nextDir = st.currentSwingLeg.swingDirection;
      if(st.currentSwingLeg.swingDirection == 1 && c < st.priceAnchorLevel)
         nextDir = -1;
      else if(st.currentSwingLeg.swingDirection == -1 && c > st.priceAnchorLevel)
         nextDir = 1;

      if(nextDir == st.currentSwingLeg.swingDirection)
      {
         if(c > st.currentSwingLeg.legHighPrice)
            st.currentSwingLeg.legHighPrice = c;
         if(c < st.currentSwingLeg.legLowPrice)
            st.currentSwingLeg.legLowPrice = c;
         st.currentSwingLeg.legEndTime = iTime(_Symbol, tf, k);
      }
      else
      {
         if(c > st.currentSwingLeg.legHighPrice)
            st.currentSwingLeg.legHighPrice = c;
         if(c < st.currentSwingLeg.legLowPrice)
            st.currentSwingLeg.legLowPrice = c;
         st.currentSwingLeg.legEndTime = iTime(_Symbol, tf, k);

         SwingLeg closed = st.currentSwingLeg;
         SwingHistoryPush(st, closed);

         int nd = dir;
         if(nd == 0)
            nd = nextDir;

         const datetime pivotTime = closed.legEndTime;
         st.currentSwingLeg.swingDirection = nd;
         st.currentSwingLeg.legStartTime   = pivotTime;
         st.currentSwingLeg.legEndTime     = pivotTime;

         if(nd == 1)
         {
            st.currentSwingLeg.legLowPrice  = closed.legLowPrice;
            st.currentSwingLeg.legHighPrice = c;
         }
         else
         {
            st.currentSwingLeg.legHighPrice = closed.legHighPrice;
            st.currentSwingLeg.legLowPrice  = c;
         }
         st.priceAnchorLevel = c;
      }
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(InputSwitchChartToM2)
   {
      ChartSetSymbolPeriod(0, _Symbol, PERIOD_M2);
      ChartRedraw(0);
   }

   ObjectsDeleteAll(0, PFX_H1, -1, -1);
   ObjectsDeleteAll(0, PFX_M5, -1, -1);
   ObjectsDeleteAll(0, PFX_M5AL, -1, -1);
   ObjectsDeleteAll(0, PFX_M2, -1, -1);
   ClearM5ZoneObjects();
   ClearM2EntryObjects();

   WarmupTf(g_h1, PERIOD_H1, PFX_H1, InputColorH1Swing, false);
   WarmupTf(g_m5, PERIOD_M5, PFX_M5, InputColorM5Swing, false);
   WarmupTf(g_m2, PERIOD_M2, PFX_M2, InputColorM2Swing, false);

   g_lastH1BarOpen = iTime(_Symbol, PERIOD_H1, 0);
   g_lastM5BarOpen = iTime(_Symbol, PERIOD_M5, 0);
   g_lastM2BarOpen = iTime(_Symbol, PERIOD_M2, 0);

   TryInitH1BosFromLastClosedBar();
   RefreshH1BosCornerLabel();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, OBJ_H1_BOS_UI);
   ObjectsDeleteAll(0, PFX_H1, -1, -1);
   ObjectsDeleteAll(0, PFX_M5, -1, -1);
   ObjectsDeleteAll(0, PFX_M5AL, -1, -1);
   ObjectsDeleteAll(0, PFX_M2, -1, -1);
   ClearM5ZoneObjects();
   ClearM2EntryObjects();
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
      ProcessBodySwingStep(g_h1, PERIOD_H1, PFX_H1, InputColorH1Swing, InputDrawH1BodySwings);

      bool h1Bull = false;
      if(TryDetectBosOnLastClosedBar(g_h1, PERIOD_H1, h1Bull))
      {
         g_h1BosDirection = h1Bull ? 1 : -1;
         g_h1BosBarTime   = iTime(_Symbol, PERIOD_H1, 1);
         ResetConfluenceAfterH1Change();
      }
      RefreshH1BosCornerLabel();
   }

   if(tM5 != g_lastM5BarOpen)
   {
      g_lastM5BarOpen = tM5;
      const datetime m5LegStartBefore = g_m5.currentSwingLeg.legStartTime;
      ProcessBodySwingStep(g_m5, PERIOD_M5, PFX_M5, InputColorM5Swing, InputDrawM5BodySwings);

      if(g_h1BosDirection != 0)
      {
         bool m5Bull = false;
         if(TryDetectBosOnLastClosedBar(g_m5, PERIOD_M5, m5Bull))
         {
            const bool aligned = ((g_h1BosDirection == 1 && m5Bull) || (g_h1BosDirection == -1 && !m5Bull));
            if(aligned)
            {
               g_m5BosAligned   = true;
               g_m5BosBarTime   = iTime(_Symbol, PERIOD_M5, 1);
               g_m5BosDirection = m5Bull ? 1 : -1;
               g_m5LegStartAtBos = m5LegStartBefore;

               DrawAlignedM5BosMarker(g_m5BosBarTime, m5Bull);

               bool    hasFvg;
               bool    fvgBull;
               double  zL, zH;
               datetime tL, tR;
               hasFvg = FindFirstM5FvgFromLegStart(g_m5LegStartAtBos, m5Bull, fvgBull, zL, zH, tL, tR);

               if(InputDrawM5Zone)
               {
                  if(hasFvg)
                  {
                     g_m5HasMarkedZone = true;
                     g_m5MarkIsFvg     = true;
                     g_m5ZoneLow       = zL;
                     g_m5ZoneHigh      = zH;
                     g_m5ZoneTimeLeft  = tL;
                     g_m5ZoneTimeRight = tR;
                     DrawM5ZoneFromFvg(fvgBull, zL, zH, tL, tR);
                  }
                  else
                  {
                     g_m5HasMarkedZone = true;
                     g_m5MarkIsFvg     = false;
                     const double c = iClose(_Symbol, PERIOD_M5, 1);
                     const double px = c;
                     g_m5ZoneLow  = px;
                     g_m5ZoneHigh = px;
                     g_m5ZoneTimeLeft  = g_m5LegStartAtBos;
                     g_m5ZoneTimeRight = iTime(_Symbol, PERIOD_M5, 1);
                     DrawM5LegStartMarker(g_m5LegStartAtBos, px);
                  }
               }
               g_waitingRetraceToM5Zone = g_m5HasMarkedZone;
               g_retraceSeen            = false;
               g_m2EntryMarked          = false;
               ClearM2EntryObjects();
            }
         }
      }
   }

   if(tM2 != g_lastM2BarOpen)
   {
      g_lastM2BarOpen = tM2;
      const datetime m2LegStartBefore = g_m2.currentSwingLeg.legStartTime;
      ProcessBodySwingStep(g_m2, PERIOD_M2, PFX_M2, InputColorM2Swing, InputDrawM2BodySwings);

      if(g_waitingRetraceToM5Zone && g_m5HasMarkedZone && g_h1BosDirection != 0)
      {
         const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(g_m5MarkIsFvg)
         {
            if(PriceInsideZone(bid, ask, g_m5ZoneLow, g_m5ZoneHigh))
               g_retraceSeen = true;
         }
         else if(PriceInsideZone(bid, ask, g_m5ZoneLow, g_m5ZoneHigh))
            g_retraceSeen = true;

         if(g_retraceSeen)
            TryMarkM2EntryFvgOrLeg(g_h1BosDirection, m2LegStartBefore);
      }
   }
}

//+------------------------------------------------------------------+
