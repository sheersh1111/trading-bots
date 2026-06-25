//+------------------------------------------------------------------+
//| scalping_v2.mq5                                                  |
//| M15 swing legs + volume breach between consecutive decent bars.  |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "2.13"
#property description "scalping_v2 — expired breach rays removed from chart."

const ENUM_TIMEFRAMES ChartTf = PERIOD_M15;
const ENUM_TIMEFRAMES SweepCheckTf = PERIOD_M2;

input bool   InputSwitchChartToM15         = true;
input int    InputWarmupBars               = 500;
input bool   InputDrawSwingLegVisuals      = true;
input color  InputSwingTrendLineColor      = clrYellow;
input double InputAnchorTolerance          = 0.5; // × prior 5-bar avg range (wick AND body)
input bool   InputDrawVolumeBreachLevels   = true;
input int    InputBreachRayBarCount        = 24;  // horizontal ray width from vol bar
input int    InputBreachExpiryM15BarCount    = 147; // active for N M15 bars from formation bar
input double InputInternalBreachMinBodyPctOfRange = 70.0; // body >= N% of bar range (high-low)

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

enum ENUM_M15_BREACH_TYPE
{
   M15_BREACH_EXTERNAL = 0, // cross-leg vol breach (current logic)
   M15_BREACH_INTERNAL = 1  // same-leg decent bar (body >= threshold)
};

struct M15LegVolumeBreachRecord
{
   datetime             legStartTime;
   datetime             legEndTime;
   int                  swingDirection;
   double               breachLevelPrice;
   datetime             volumeBarOpenTime;
   bool                 swept;
   bool                 expired;
   ENUM_M15_BREACH_TYPE breachType;
};

struct M15ActiveLegVolumeBreachTrack
{
   datetime legStartTime;
   int      swingDirection;
   bool     breachSet;
   bool     firstDecentOnLegSeen;
   long     maxTickVolume;
   datetime maxVolumeBarOpenTime;
   double   breachLevelPrice;
};

const string PFX_M15_TREND      = "SCALP_V2_M15_TR_";
const string PFX_M15_LBL        = "SCALP_V2_M15_LB_";
const string PFX_M15_VOL_BREACH = "SCALP_V2_M15_VB_";

const color M15_BREACH_COLOR_BULLISH = clrGreen;    // up leg after down leg closed
const color M15_BREACH_COLOR_BEARISH = clrDeepPink; // down leg after up leg closed

#define M15_LEG_VOLUME_BREACH_CAPACITY 20

SwingState                   g_m15Swing;
datetime                     g_lastM15BarOpen = 0;
datetime                     g_lastM2BarOpen = 0;
datetime                     g_m15PrevLegLastDecentBarOpen = 0;
int                          g_m15PrevClosedLegDirection = 0;
bool                         g_m15AwaitingOppositeFirstDecentBreach = false;
M15ActiveLegVolumeBreachTrack g_m15ActiveVolTrack;
M15LegVolumeBreachRecord     g_m15LegVolumeBreaches[M15_LEG_VOLUME_BREACH_CAPACITY];
int                          g_m15LegVolumeBreachCount = 0;

//+------------------------------------------------------------------+
bool M15BarHasDecentMovementForLegDirection(const int barShift, const int legSwingDirection)
{
   if(barShift < 0 || legSwingDirection == 0)
      return false;

   const double barOpen  = iOpen(_Symbol, ChartTf, barShift);
   const double barClose = iClose(_Symbol, ChartTf, barShift);
   const double barHigh  = iHigh(_Symbol, ChartTf, barShift);
   const double barLow   = iLow(_Symbol, ChartTf, barShift);

   const int candleDirection =
      (barClose > barOpen) ? 1 : ((barClose < barOpen) ? -1 : 0);
   if(candleDirection != legSwingDirection)
      return false;

   const double bodyRange = MathAbs(barClose - barOpen);
   const double wickRange = barHigh - barLow;

   const int barsTotal = iBars(_Symbol, ChartTf);
   double sumRangeFivePriorBars = 0.0;
   int    rangeBarCount = 0;
   for(int priorShift = barShift + 1; priorShift <= barShift + 5; priorShift++)
   {
      if(priorShift >= barsTotal)
         break;
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, ChartTf, priorShift) - iLow(_Symbol, ChartTf, priorShift));
      rangeBarCount++;
   }

   const double averageRangeFiveBars =
      (rangeBarCount > 0) ? sumRangeFivePriorBars / (double)rangeBarCount : 0.0;
   const double minDecentRange = averageRangeFiveBars * InputAnchorTolerance;

   return wickRange > minDecentRange && bodyRange > minDecentRange;
}

//+------------------------------------------------------------------+
double M15BreachLevelFromVolumeBar(const int swingDirection, const int barShift)
{
   if(barShift < 0 || swingDirection == 0)
      return 0.0;

   const double barOpen  = iOpen(_Symbol, ChartTf, barShift);
   const double barClose = iClose(_Symbol, ChartTf, barShift);
   if(swingDirection == 1)
      return MathMin(barOpen, barClose); // bullish green
   if(swingDirection == -1)
      return MathMax(barOpen, barClose); // bearish pink
   return 0.0;
}

//+------------------------------------------------------------------+
bool M15VolumeWindowShiftRangeValid(const datetime windowStartInclusive,
                                    const datetime windowEndInclusive)
{
   if(windowStartInclusive == 0 || windowEndInclusive == 0)
      return false;

   const int shiftStartOlder = iBarShift(_Symbol, ChartTf, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, ChartTf, windowEndInclusive, true);
   if(shiftStartOlder < 0 || shiftEndNewer < 0)
      return false;

   return shiftEndNewer <= shiftStartOlder;
}

//+------------------------------------------------------------------+
bool M15TryGetLegLastDecentMovementBarOpen(const datetime legStartTime, const datetime legEndTime,
                                           const int swingDirection, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legEndTime == 0 || swingDirection == 0)
      return false;

   int shiftNewer = iBarShift(_Symbol, ChartTf, legEndTime, true);
   int shiftOlder = iBarShift(_Symbol, ChartTf, legStartTime, true);
   if(shiftNewer < 0 || shiftOlder < 0)
      return false;

   if(shiftOlder < shiftNewer)
   {
      const int tmp = shiftOlder;
      shiftOlder    = shiftNewer;
      shiftNewer    = tmp;
   }

   for(int barShift = shiftNewer; barShift <= shiftOlder; barShift++)
   {
      if(!M15BarHasDecentMovementForLegDirection(barShift, swingDirection))
         continue;

      outBarOpenTime = iTime(_Symbol, ChartTf, barShift);
      return outBarOpenTime > 0;
   }

   return false;
}

//+------------------------------------------------------------------+
bool M15FindMaxVolumeBarInOpenTimeWindow(const datetime windowStartInclusive,
                                         const datetime windowEndInclusive,
                                         const int swingDirection,
                                         long &outMaxVolume,
                                         datetime &outMaxBarOpenTime,
                                         double &outBreachLevel)
{
   outMaxVolume      = -1;
   outMaxBarOpenTime = 0;
   outBreachLevel    = 0.0;

   if(swingDirection == 0 || !M15VolumeWindowShiftRangeValid(windowStartInclusive, windowEndInclusive))
      return false;

   const int shiftStartOlder = iBarShift(_Symbol, ChartTf, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, ChartTf, windowEndInclusive, true);

   for(int barShift = shiftEndNewer; barShift <= shiftStartOlder; barShift++)
   {
      const long barVol = iTickVolume(_Symbol, ChartTf, barShift);
      if(barVol < 0 || barVol <= outMaxVolume)
         continue;

      outMaxVolume      = barVol;
      outMaxBarOpenTime = iTime(_Symbol, ChartTf, barShift);
      outBreachLevel    = M15BreachLevelFromVolumeBar(swingDirection, barShift);
   }

   return outMaxBarOpenTime > 0 && outBreachLevel > 0.0;
}

//+------------------------------------------------------------------+
string M15VolumeBreachRayObjectName(const datetime legStartTime, const datetime formationBarOpen,
                                    const ENUM_M15_BREACH_TYPE breachType)
{
   if(breachType == M15_BREACH_INTERNAL)
      return PFX_M15_VOL_BREACH + "I_" + IntegerToString((long)legStartTime) + "_"
             + IntegerToString((long)formationBarOpen);
   return PFX_M15_VOL_BREACH + IntegerToString((long)legStartTime);
}

//+------------------------------------------------------------------+
bool M15BarBodyMeetsInternalBreachThreshold(const int barShift, const double minBodyPctOfRange)
{
   if(barShift < 0 || minBodyPctOfRange <= 0.0)
      return false;

   const double barOpen  = iOpen(_Symbol, ChartTf, barShift);
   const double barClose = iClose(_Symbol, ChartTf, barShift);
   const double barHigh  = iHigh(_Symbol, ChartTf, barShift);
   const double barLow   = iLow(_Symbol, ChartTf, barShift);
   const double barRange = barHigh - barLow;
   if(barRange <= 0.0)
      return false;

   const double bodyRange = MathAbs(barClose - barOpen);
   return bodyRange >= barRange * (minBodyPctOfRange / 100.0);
}

//+------------------------------------------------------------------+
int M15BarCandleDirection(const int barShift)
{
   const double barOpen  = iOpen(_Symbol, ChartTf, barShift);
   const double barClose = iClose(_Symbol, ChartTf, barShift);
   if(barClose > barOpen)
      return 1;
   if(barClose < barOpen)
      return -1;
   return 0;
}

//+------------------------------------------------------------------+
bool M15IsBreachRecordExpired(const datetime formationBarOpenTime, const int expiryM15BarCount)
{
   if(formationBarOpenTime == 0 || expiryM15BarCount < 1)
      return false;

   const int shiftFormation = iBarShift(_Symbol, ChartTf, formationBarOpenTime, true);
   if(shiftFormation < 0)
      return true;

   const int closedBarsSinceFormation = shiftFormation - 1;
   return closedBarsSinceFormation >= expiryM15BarCount;
}

//+------------------------------------------------------------------+
bool M15ShouldDisplayBreachRay(const datetime volumeBarOpenTime)
{
   if(volumeBarOpenTime == 0)
      return false;

   if(InputBreachExpiryM15BarCount >= 1 &&
      M15IsBreachRecordExpired(volumeBarOpenTime, InputBreachExpiryM15BarCount))
      return false;

   return true;
}

//+------------------------------------------------------------------+
bool M15DeleteVolumeBreachRayByName(const string objName)
{
   if(objName == "" || ObjectFind(0, objName) < 0)
      return false;

   ObjectDelete(0, objName);
   return true;
}

//+------------------------------------------------------------------+
void M15DrawVolumeBreachRay(const string objName, const int swingDirection,
                            const datetime volumeBarOpenTime, const double breachLevel)
{
   if(!InputDrawVolumeBreachLevels || swingDirection == 0 ||
      volumeBarOpenTime == 0 || breachLevel <= 0.0 ||
      !M15ShouldDisplayBreachRay(volumeBarOpenTime))
      return;

   const color rayColor = (swingDirection == 1) ? M15_BREACH_COLOR_BULLISH : M15_BREACH_COLOR_BEARISH;
   const int   periodSec = (int)PeriodSeconds(ChartTf);
   if(periodSec < 1)
      return;

   const int bufferBars = MathMax(1, InputBreachRayBarCount);
   const datetime timeEnd =
      volumeBarOpenTime + (datetime)((long)bufferBars * (long)periodSec);

   if(ObjectFind(0, objName) < 0)
   {
      if(!ObjectCreate(0, objName, OBJ_TREND, 0, volumeBarOpenTime, breachLevel, timeEnd, breachLevel))
         return;
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, rayColor);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, volumeBarOpenTime);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, breachLevel);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeEnd);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, breachLevel);
   }
}

//+------------------------------------------------------------------+
void M15DrawVolumeBreachRayForRecord(const M15LegVolumeBreachRecord &rec)
{
   const string objName =
      M15VolumeBreachRayObjectName(rec.legStartTime, rec.volumeBarOpenTime, rec.breachType);
   M15DrawVolumeBreachRay(objName, rec.swingDirection, rec.volumeBarOpenTime, rec.breachLevelPrice);
}

//+------------------------------------------------------------------+
bool M15DeleteVolumeBreachRayForRecord(const M15LegVolumeBreachRecord &rec)
{
   const string objName =
      M15VolumeBreachRayObjectName(rec.legStartTime, rec.volumeBarOpenTime, rec.breachType);
   return M15DeleteVolumeBreachRayByName(objName);
}

//+------------------------------------------------------------------+
bool M15IsBreachRecordActiveOnChart(const M15LegVolumeBreachRecord &rec)
{
   if(rec.swept || rec.expired || rec.volumeBarOpenTime == 0 || rec.breachLevelPrice <= 0.0)
      return false;

   return M15ShouldDisplayBreachRay(rec.volumeBarOpenTime);
}

//+------------------------------------------------------------------+
bool M15ChartBreachRayMatchesActiveRecord(const string objName)
{
   for(int i = 0; i < g_m15LegVolumeBreachCount; i++)
   {
      if(!M15IsBreachRecordActiveOnChart(g_m15LegVolumeBreaches[i]))
         continue;

      const string activeName =
         M15VolumeBreachRayObjectName(g_m15LegVolumeBreaches[i].legStartTime,
                                      g_m15LegVolumeBreaches[i].volumeBarOpenTime,
                                      g_m15LegVolumeBreaches[i].breachType);
      if(activeName == objName)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
bool M15PurgeOrphanBreachRaysFromChart()
{
   bool changed = false;

   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      const string objName = ObjectName(0, i, 0, -1);
      if(StringFind(objName, PFX_M15_VOL_BREACH) != 0)
         continue;

      if(M15ChartBreachRayMatchesActiveRecord(objName))
         continue;

      if(M15DeleteVolumeBreachRayByName(objName))
         changed = true;
   }

   return changed;
}

//+------------------------------------------------------------------+
void M15DeleteVolumeBreachRay(const datetime legStartTime)
{
   if(legStartTime == 0)
      return;

   const string objName = M15VolumeBreachRayObjectName(legStartTime, 0, M15_BREACH_EXTERNAL);
   if(ObjectFind(0, objName) >= 0)
      ObjectDelete(0, objName);
}

//+------------------------------------------------------------------+
//| Bullish (up): M2 low at/below level. Bearish (down): high at/above.|
//+------------------------------------------------------------------+
bool M15IsBreachWickTouchedOnBar(const int swingDirection, const double breachLevel,
                                  const double barHigh, const double barLow, const double pointSize)
{
   if(swingDirection == 0 || breachLevel <= 0.0)
      return false;

   const double eps = (pointSize > 0.0 ? pointSize : 0.00001);

   if(swingDirection == 1)
      return barLow > 0.0 && barLow <= breachLevel + eps;

   if(swingDirection == -1)
      return barHigh > 0.0 && barHigh >= breachLevel - eps;

   return false;
}

//+------------------------------------------------------------------+
void ProcessM15BreachExpiryOnM15Close()
{
   bool chartChanged = false;

   if(InputBreachExpiryM15BarCount >= 1)
   {
      for(int i = 0; i < g_m15LegVolumeBreachCount; i++)
      {
         if(g_m15LegVolumeBreaches[i].swept || g_m15LegVolumeBreaches[i].expired)
         {
            if(M15DeleteVolumeBreachRayForRecord(g_m15LegVolumeBreaches[i]))
               chartChanged = true;
            continue;
         }

         if(!M15IsBreachRecordExpired(g_m15LegVolumeBreaches[i].volumeBarOpenTime,
                                       InputBreachExpiryM15BarCount))
            continue;

         g_m15LegVolumeBreaches[i].expired = true;
         if(M15DeleteVolumeBreachRayForRecord(g_m15LegVolumeBreaches[i]))
            chartChanged = true;
      }
   }

   if(M15PurgeOrphanBreachRaysFromChart())
      chartChanged = true;

   if(chartChanged)
      ChartRedraw(0);
}

//+------------------------------------------------------------------+
void ProcessM15BreachSweepOnM2Close()
{
   const datetime closedBarOpenTime = iTime(_Symbol, SweepCheckTf, 1);
   if(closedBarOpenTime == 0)
      return;

   const double barHigh    = iHigh(_Symbol, SweepCheckTf, 1);
   const double barLow     = iLow(_Symbol, SweepCheckTf, 1);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = 0; i < g_m15LegVolumeBreachCount; i++)
   {
      if(g_m15LegVolumeBreaches[i].swept || g_m15LegVolumeBreaches[i].expired)
         continue;

      const double breachLevel = g_m15LegVolumeBreaches[i].breachLevelPrice;
      if(breachLevel <= 0.0 || g_m15LegVolumeBreaches[i].swingDirection == 0)
         continue;

      if(g_m15LegVolumeBreaches[i].volumeBarOpenTime > 0 &&
         closedBarOpenTime < g_m15LegVolumeBreaches[i].volumeBarOpenTime)
         continue;

      if(!M15IsBreachWickTouchedOnBar(g_m15LegVolumeBreaches[i].swingDirection, breachLevel,
                                      barHigh, barLow, pointSize))
         continue;

      g_m15LegVolumeBreaches[i].swept = true;
      if(M15DeleteVolumeBreachRayForRecord(g_m15LegVolumeBreaches[i]))
         ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
void M15ResetActiveLegVolumeTrack(const datetime legStartTime, const int swingDirection)
{
   g_m15ActiveVolTrack.legStartTime         = legStartTime;
   g_m15ActiveVolTrack.swingDirection     = swingDirection;
   g_m15ActiveVolTrack.breachSet          = false;
   g_m15ActiveVolTrack.firstDecentOnLegSeen = false;
   g_m15ActiveVolTrack.maxTickVolume      = -1;
   g_m15ActiveVolTrack.maxVolumeBarOpenTime = 0;
   g_m15ActiveVolTrack.breachLevelPrice   = 0.0;
}

//+------------------------------------------------------------------+
void M15InitLegVolumeBreachRecord(M15LegVolumeBreachRecord &rec,
                                  const datetime legStartTime, const datetime legEndTime,
                                  const int swingDirection, const double breachLevel,
                                  const datetime volumeBarOpenTime,
                                  const ENUM_M15_BREACH_TYPE breachType = M15_BREACH_EXTERNAL)
{
   rec.legStartTime        = legStartTime;
   rec.legEndTime          = legEndTime;
   rec.swingDirection      = swingDirection;
   rec.breachLevelPrice    = breachLevel;
   rec.volumeBarOpenTime = volumeBarOpenTime;
   rec.swept              = false;
   rec.expired            = false;
   rec.breachType         = breachType;
}

//+------------------------------------------------------------------+
void M15RememberLegVolumeBreachRecord(const datetime legStartTime, const datetime legEndTime,
                                      const int swingDirection, const double breachLevel,
                                      const datetime volumeBarOpenTime,
                                      const ENUM_M15_BREACH_TYPE breachType = M15_BREACH_EXTERNAL)
{
   if(legStartTime == 0 || swingDirection == 0 || breachLevel <= 0.0 || volumeBarOpenTime == 0)
      return;

   for(int i = 0; i < g_m15LegVolumeBreachCount; i++)
   {
      const M15LegVolumeBreachRecord existing = g_m15LegVolumeBreaches[i];
      if(existing.breachType != breachType || existing.legStartTime != legStartTime)
         continue;

      if(breachType == M15_BREACH_INTERNAL)
      {
         if(existing.volumeBarOpenTime != volumeBarOpenTime)
            continue;
      }
      else if(existing.legEndTime != legEndTime)
         continue;

      const bool wasSwept   = g_m15LegVolumeBreaches[i].swept;
      const bool wasExpired = g_m15LegVolumeBreaches[i].expired;
      M15InitLegVolumeBreachRecord(g_m15LegVolumeBreaches[i], legStartTime, legEndTime,
                                   swingDirection, breachLevel, volumeBarOpenTime, breachType);
      g_m15LegVolumeBreaches[i].swept   = wasSwept;
      g_m15LegVolumeBreaches[i].expired = wasExpired;
      if(g_m15LegVolumeBreaches[i].swept || g_m15LegVolumeBreaches[i].expired ||
         !M15ShouldDisplayBreachRay(volumeBarOpenTime))
         M15DeleteVolumeBreachRayForRecord(g_m15LegVolumeBreaches[i]);
      return;
   }

   if(g_m15LegVolumeBreachCount < M15_LEG_VOLUME_BREACH_CAPACITY)
   {
      M15InitLegVolumeBreachRecord(g_m15LegVolumeBreaches[g_m15LegVolumeBreachCount],
                                   legStartTime, legEndTime, swingDirection, breachLevel,
                                   volumeBarOpenTime, breachType);
      g_m15LegVolumeBreachCount++;
      return;
   }

   M15DeleteVolumeBreachRayForRecord(g_m15LegVolumeBreaches[0]);

   for(int i = 1; i < M15_LEG_VOLUME_BREACH_CAPACITY; i++)
      g_m15LegVolumeBreaches[i - 1] = g_m15LegVolumeBreaches[i];

   M15InitLegVolumeBreachRecord(g_m15LegVolumeBreaches[M15_LEG_VOLUME_BREACH_CAPACITY - 1],
                                legStartTime, legEndTime, swingDirection, breachLevel,
                                volumeBarOpenTime, breachType);
}

//+------------------------------------------------------------------+
void M15UpdateLegVolumeBreachEndTime(const datetime legStartTime, const datetime legEndTime)
{
   for(int i = 0; i < g_m15LegVolumeBreachCount; i++)
   {
      if(g_m15LegVolumeBreaches[i].legStartTime == legStartTime &&
         g_m15LegVolumeBreaches[i].legEndTime == 0 &&
         g_m15LegVolumeBreaches[i].breachType == M15_BREACH_EXTERNAL)
      {
         g_m15LegVolumeBreaches[i].legEndTime = legEndTime;
         return;
      }
   }
}

//+------------------------------------------------------------------+
void M15CapturePrevLegLastDecentOnClose(const Swing &closedLeg)
{
   g_m15PrevLegLastDecentBarOpen = 0;
   if(closedLeg.legStartTime == 0 || closedLeg.legEndTime == 0 || closedLeg.swingDirection == 0)
      return;

   if(!M15TryGetLegLastDecentMovementBarOpen(closedLeg.legStartTime, closedLeg.legEndTime,
                                             closedLeg.swingDirection, g_m15PrevLegLastDecentBarOpen))
      g_m15PrevLegLastDecentBarOpen = closedLeg.legEndTime;
}

void M15ArmBreachAfterLegClose(const Swing &closedLeg)
{
   g_m15PrevClosedLegDirection = closedLeg.swingDirection;
   g_m15AwaitingOppositeFirstDecentBreach = (closedLeg.swingDirection != 0);
   M15CapturePrevLegLastDecentOnClose(closedLeg);
}

//+------------------------------------------------------------------+
//| After flip only: 1st decent on opposite leg → static breach.       |
//| Up leg closed → down leg 1st decent = pink bear (max O/C on vol). |
//| Down leg closed → up leg 1st decent = green bull (min O/C on vol).|
//+------------------------------------------------------------------+
void M15TrySetStaticBreachOnFirstDecent(const SwingState &swingState, const int barShift)
{
   if(!g_m15AwaitingOppositeFirstDecentBreach)
      return;

   if(swingState.currentSwingLeg.swingDirection == 0 ||
      swingState.currentSwingLeg.legStartTime == 0)
      return;

   if(g_m15PrevClosedLegDirection == 0 ||
      g_m15PrevClosedLegDirection == swingState.currentSwingLeg.swingDirection)
      return;

   if(g_m15ActiveVolTrack.legStartTime != swingState.currentSwingLeg.legStartTime)
      M15ResetActiveLegVolumeTrack(swingState.currentSwingLeg.legStartTime,
                                   swingState.currentSwingLeg.swingDirection);

   if(g_m15ActiveVolTrack.breachSet)
      return;

   if(!M15BarHasDecentMovementForLegDirection(barShift, swingState.currentSwingLeg.swingDirection))
      return;

   const datetime nowDecentOpen = iTime(_Symbol, ChartTf, barShift);
   if(nowDecentOpen == 0 || g_m15PrevLegLastDecentBarOpen == 0)
      return;

   long     maxVol = -1;
   datetime maxBar = 0;
   double   breach = 0.0;
   if(!M15FindMaxVolumeBarInOpenTimeWindow(g_m15PrevLegLastDecentBarOpen, nowDecentOpen,
                                           swingState.currentSwingLeg.swingDirection,
                                           maxVol, maxBar, breach))
      return;

   g_m15ActiveVolTrack.breachSet            = true;
   g_m15ActiveVolTrack.maxTickVolume        = maxVol;
   g_m15ActiveVolTrack.maxVolumeBarOpenTime = maxBar;
   g_m15ActiveVolTrack.breachLevelPrice     = breach;
   g_m15AwaitingOppositeFirstDecentBreach   = false;

   M15RememberLegVolumeBreachRecord(swingState.currentSwingLeg.legStartTime, 0,
                                    swingState.currentSwingLeg.swingDirection,
                                    breach, maxBar, M15_BREACH_EXTERNAL);

   const string objName =
      M15VolumeBreachRayObjectName(swingState.currentSwingLeg.legStartTime, maxBar, M15_BREACH_EXTERNAL);
   M15DrawVolumeBreachRay(objName, swingState.currentSwingLeg.swingDirection, maxBar, breach);
}

//+------------------------------------------------------------------+
//| 2nd+ same-leg decent: body >= threshold → internal breach record.  |
//+------------------------------------------------------------------+
void M15TryAddInternalBreachFromDecentBar(const SwingState &swingState, const int barShift)
{
   if(swingState.currentSwingLeg.legStartTime == 0)
      return;

   if(!M15BarBodyMeetsInternalBreachThreshold(barShift, InputInternalBreachMinBodyPctOfRange))
      return;

   const int barDirection = M15BarCandleDirection(barShift);
   if(barDirection == 0)
      return;

   const datetime barOpenTime = iTime(_Symbol, ChartTf, barShift);
   if(barOpenTime == 0)
      return;

   const double breachLevel = M15BreachLevelFromVolumeBar(barDirection, barShift);
   if(breachLevel <= 0.0)
      return;

   M15RememberLegVolumeBreachRecord(swingState.currentSwingLeg.legStartTime, barOpenTime,
                                    barDirection, breachLevel, barOpenTime, M15_BREACH_INTERNAL);

   const string objName =
      M15VolumeBreachRayObjectName(swingState.currentSwingLeg.legStartTime, barOpenTime,
                                   M15_BREACH_INTERNAL);
   M15DrawVolumeBreachRay(objName, barDirection, barOpenTime, breachLevel);
}

//+------------------------------------------------------------------+
void M15OnActiveLegDecentBar(const SwingState &swingState, const int barShift)
{
   if(swingState.currentSwingLeg.swingDirection == 0 ||
      swingState.currentSwingLeg.legStartTime == 0)
      return;

   if(!M15BarHasDecentMovementForLegDirection(barShift, swingState.currentSwingLeg.swingDirection))
      return;

   if(g_m15ActiveVolTrack.legStartTime != swingState.currentSwingLeg.legStartTime)
      M15ResetActiveLegVolumeTrack(swingState.currentSwingLeg.legStartTime,
                                   swingState.currentSwingLeg.swingDirection);

   if(!g_m15ActiveVolTrack.firstDecentOnLegSeen)
   {
      g_m15ActiveVolTrack.firstDecentOnLegSeen = true;
      M15TrySetStaticBreachOnFirstDecent(swingState, barShift);
      return;
   }

   M15TryAddInternalBreachFromDecentBar(swingState, barShift);
}

//+------------------------------------------------------------------+
void SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                   const double highPrice, const double lowPrice, const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.swingDirection = swingDirection;
   swingState.currentSwingLeg.legHighPrice   = highPrice;
   swingState.currentSwingLeg.legLowPrice    = lowPrice;
   swingState.currentSwingLeg.legStartTime   = iTime(_Symbol, timeframe, lastClosedBarShift);

   M15ResetActiveLegVolumeTrack(swingState.currentSwingLeg.legStartTime, swingDirection);
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

   if(g_m15ActiveVolTrack.breachSet &&
      g_m15ActiveVolTrack.legStartTime == swingState.currentSwingLeg.legStartTime)
      M15UpdateLegVolumeBreachEndTime(swingState.currentSwingLeg.legStartTime,
                                      swingState.currentSwingLeg.legEndTime);

   M15ArmBreachAfterLegClose(swingState.currentSwingLeg);

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

   const double lastClosedBarBodyRange = MathAbs(lastClosedBarClose - lastClosedBarOpen);
   const double lastClosedBarWickRange  = lastClosedBarHigh - lastClosedBarLow;

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
   const double minDecentRange       = averageRangeFiveBars * InputAnchorTolerance;
   const bool isDecentMovement =
      (lastClosedBarWickRange > minDecentRange && lastClosedBarBodyRange > minDecentRange);

   if(isDecentMovement && candleDirection == swingState.currentSwingLeg.swingDirection)
   {
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      M15OnActiveLegDecentBar(swingState, sh);
   }

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
      if(M15BarHasDecentMovementForLegDirection(sh, nextSwingDirection))
         M15OnActiveLegDecentBar(swingState, sh);
   }
}

//+------------------------------------------------------------------+
void WarmupSwingState(SwingState &st, const ENUM_TIMEFRAMES tf, const color clr,
                      const string trendPfx, const string lblPfx, const bool draw)
{
   if(InputWarmupBars <= 0)
      return;
   const int n = (int)MathMin(iBars(_Symbol, tf) - 2, InputWarmupBars);
   for(int k = n; k >= 1; k--)
      ProcessSwingStepAtShift(st, tf, k, clr, trendPfx, lblPfx, draw);
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
   ObjectsDeleteAll(0, PFX_M15_VOL_BREACH, -1, -1);

   ZeroMemory(g_m15Swing);
   g_m15LegVolumeBreachCount = 0;
   g_m15PrevLegLastDecentBarOpen = 0;
   g_m15PrevClosedLegDirection = 0;
   g_m15AwaitingOppositeFirstDecentBreach = false;
   M15ResetActiveLegVolumeTrack(0, 0);

   WarmupSwingState(g_m15Swing, ChartTf, InputSwingTrendLineColor, PFX_M15_TREND, PFX_M15_LBL,
                    InputDrawSwingLegVisuals);
   ProcessM15BreachExpiryOnM15Close();

   g_lastM15BarOpen = iTime(_Symbol, ChartTf, 0);
   g_lastM2BarOpen  = iTime(_Symbol, SweepCheckTf, 0);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PFX_M15_TREND, -1, -1);
   ObjectsDeleteAll(0, PFX_M15_LBL, -1, -1);
   ObjectsDeleteAll(0, PFX_M15_VOL_BREACH, -1, -1);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnTick()
{
   const datetime currentM2BarOpenTime = iTime(_Symbol, SweepCheckTf, 0);
   if(currentM2BarOpenTime != g_lastM2BarOpen)
   {
      g_lastM2BarOpen = currentM2BarOpenTime;
      ProcessM15BreachSweepOnM2Close();
   }

   const datetime currentBarOpenTime = iTime(_Symbol, ChartTf, 0);
   if(currentBarOpenTime == g_lastM15BarOpen)
      return;

   g_lastM15BarOpen = currentBarOpenTime;
   ProcessM15BreachExpiryOnM15Close();
   ProcessSwingStepAtShift(g_m15Swing, ChartTf, 1, InputSwingTrendLineColor, PFX_M15_TREND, PFX_M15_LBL,
                           InputDrawSwingLegVisuals);
}

//+------------------------------------------------------------------+
