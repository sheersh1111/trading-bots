//+------------------------------------------------------------------+
//| H4VolumeBreach.mqh
//| H4 volume breach ifdef
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_H4VOLUMEBREACH
#define H4_LQ_V3_H4VOLUMEBREACH

bool TryGetH4LegBarOpenTimeFromEnd(const datetime legStartTime, const datetime legEndTime,
                                    const int nFromEnd, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legEndTime == 0 || nFromEnd < 1)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   int shiftEnd   = iBarShift(_Symbol, timeframe, legEndTime, false);
   int shiftStart = iBarShift(_Symbol, timeframe, legStartTime, false);
   if(shiftEnd < 0 || shiftStart < 0)
      return false;

   if(shiftStart < shiftEnd)
   {
      const int tmp = shiftStart;
      shiftStart    = shiftEnd;
      shiftEnd      = tmp;
   }

   const int barCount = shiftStart - shiftEnd + 1;
   int indexFromEnd = nFromEnd;
   if(indexFromEnd > barCount)
      indexFromEnd = barCount;

   const int targetShift = shiftEnd + (barCount - indexFromEnd);
   outBarOpenTime = iTime(_Symbol, timeframe, targetShift);
   return outBarOpenTime > 0;
}

//+------------------------------------------------------------------+
double H4BreachLevelPriceFromVolumeBar(const int swingDirection, const int h4BarShift)
{
   if(h4BarShift < 0)
      return 0.0;
   if(swingDirection == 1)
      return iLow(_Symbol, PERIOD_H4, h4BarShift);
   if(swingDirection == -1)
      return iHigh(_Symbol, PERIOD_H4, h4BarShift);
   return 0.0;
}

//+------------------------------------------------------------------+
bool H4BarHasDecentMovementForLegDirection(const int barShift, const int legSwingDirection)
{
   if(barShift < 0 || legSwingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const double barOpen  = iOpen(_Symbol, timeframe, barShift);
   const double barClose = iClose(_Symbol, timeframe, barShift);
   const double barHigh  = iHigh(_Symbol, timeframe, barShift);
   const double barLow   = iLow(_Symbol, timeframe, barShift);

   const int candleDirection =
      (barClose > barOpen) ? 1 : ((barClose < barOpen) ? -1 : 0);
   if(candleDirection != legSwingDirection)
      return false;

   const double bodyRange = MathAbs(barClose - barOpen);
   const double wickRange = barHigh - barLow;

   const int barsTotal = iBars(_Symbol, timeframe);
   double sumRangeFivePriorBars = 0.0;
   int    rangeBarCount = 0;
   for(int priorShift = barShift + 1; priorShift <= barShift + 5; priorShift++)
   {
      if(priorShift >= barsTotal)
         break;
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, priorShift) - iLow(_Symbol, timeframe, priorShift));
      rangeBarCount++;
   }

   const double averageRangeFiveBars =
      (rangeBarCount > 0) ? sumRangeFivePriorBars / (double)rangeBarCount : 0.0;
   const double minDecentRange = averageRangeFiveBars * H4_BREACH_ANCHOR_MULTIPLIER;

   return wickRange > minDecentRange && bodyRange > minDecentRange;
}

//+------------------------------------------------------------------+
bool M2BarHasDecentMovementForLegDirection(const int barShift, const int legSwingDirection)
{
   if(barShift < 0 || legSwingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const double barOpen  = iOpen(_Symbol, timeframe, barShift);
   const double barClose = iClose(_Symbol, timeframe, barShift);
   const double barHigh  = iHigh(_Symbol, timeframe, barShift);
   const double barLow   = iLow(_Symbol, timeframe, barShift);

   const int candleDirection =
      (barClose > barOpen) ? 1 : ((barClose < barOpen) ? -1 : 0);
   if(candleDirection != legSwingDirection)
      return false;

   const double bodyRange = MathAbs(barClose - barOpen);

   const int barsTotal = iBars(_Symbol, timeframe);
   double sumRangeFivePriorBars = 0.0;
   int    rangeBarCount = 0;
   for(int priorShift = barShift + 1; priorShift <= barShift + 5; priorShift++)
   {
      if(priorShift >= barsTotal)
         break;
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, priorShift) - iLow(_Symbol, timeframe, priorShift));
      rangeBarCount++;
   }

   const double averageRangeFiveBars =
      (rangeBarCount > 0) ? sumRangeFivePriorBars / (double)rangeBarCount : 0.0;
   const double minDecentRange = averageRangeFiveBars * M2_SWING_ANCHOR_MULTIPLIER;

   return bodyRange > minDecentRange;
}

//+------------------------------------------------------------------+
bool M2TryGetLegLastDecentMovementBarOpen(const datetime legStartTime, const datetime legProgressEnd,
                                            const int swingDirection, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   int shiftNewer = iBarShift(_Symbol, timeframe, legProgressEnd, true);
   int shiftOlder = iBarShift(_Symbol, timeframe, legStartTime, true);
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
      if(!M2BarHasDecentMovementForLegDirection(barShift, swingDirection))
         continue;

      outBarOpenTime = iTime(_Symbol, timeframe, barShift);
      return outBarOpenTime > 0;
   }

   return false;
}

//+------------------------------------------------------------------+
datetime M2ProgressEndOpenForDecentLookup(const datetime legProgressEndOpen)
{
   if(legProgressEndOpen == 0)
      return 0;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int shiftNewer = iBarShift(_Symbol, timeframe, legProgressEndOpen, true);
   if(shiftNewer < 0)
      return legProgressEndOpen;

   const int shiftOlder = shiftNewer + 1;
   if(shiftOlder >= iBars(_Symbol, timeframe))
      return legProgressEndOpen;

   const datetime olderOpen = iTime(_Symbol, timeframe, shiftOlder);
   return (olderOpen > 0) ? olderOpen : legProgressEndOpen;
}

//+------------------------------------------------------------------+
bool M2TryGetVolumeWindowBoundFromLastDecent(const datetime legStartTime, const datetime legProgressEnd,
                                              const int swingDirection, datetime &outBoundInclusiveOpen)
{
   outBoundInclusiveOpen = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0)
      return false;

   const datetime decentLookupEnd = M2ProgressEndOpenForDecentLookup(legProgressEnd);

   datetime lastDecentOpen = 0;
   if(!M2TryGetLegLastDecentMovementBarOpen(legStartTime, decentLookupEnd, swingDirection,
                                              lastDecentOpen))
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int shiftDecent = iBarShift(_Symbol, timeframe, lastDecentOpen, true);
   if(shiftDecent < 0)
      return false;

   const int shiftBoundInclusive = shiftDecent + 2;
   if(shiftBoundInclusive >= iBars(_Symbol, timeframe))
      return false;

   outBoundInclusiveOpen = iTime(_Symbol, timeframe, shiftBoundInclusive);
   return outBoundInclusiveOpen > 0;
}

//+------------------------------------------------------------------+
bool M2VolumeWindowShiftRangeValid(const datetime windowStartInclusive, const datetime windowEndInclusive)
{
   if(windowStartInclusive == 0 || windowEndInclusive == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, timeframe, windowEndInclusive, true);
   if(shiftStartOlder < 0 || shiftEndNewer < 0)
      return false;

   return shiftEndNewer <= shiftStartOlder;
}

//+------------------------------------------------------------------+
bool M2TryResolveLegVolumeWindowEnd(const datetime legStartTime, const datetime legProgressEnd,
                                     const int swingDirection, const datetime windowStartInclusive,
                                     const int lastClosedBarShift, datetime &outWindowEndInclusiveOpen)
{
   outWindowEndInclusiveOpen = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0 || lastClosedBarShift < 1)
      return false;

   datetime decentBoundOpen = 0;
   if(M2TryGetVolumeWindowBoundFromLastDecent(legStartTime, legProgressEnd, swingDirection,
                                               decentBoundOpen) &&
      M2VolumeWindowShiftRangeValid(windowStartInclusive, decentBoundOpen))
   {
      outWindowEndInclusiveOpen = decentBoundOpen;
      return true;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   for(int shiftBound = lastClosedBarShift + 2; shiftBound >= lastClosedBarShift; shiftBound--)
   {
      if(shiftBound >= barsTotal)
         continue;

      const datetime boundOpen = iTime(_Symbol, timeframe, shiftBound);
      if(boundOpen == 0)
         continue;
      if(!M2VolumeWindowShiftRangeValid(windowStartInclusive, boundOpen))
         continue;

      outWindowEndInclusiveOpen = boundOpen;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
bool M2TryGetTouchLegVolumeWindowStart(const int touchLegDirection, datetime &outWindowStartOpen)
{
   outWindowStartOpen = 0;
   if(touchLegDirection == 0 || g_m2Swing.swingHistoryCount < 1)
      return false;

   const Swing prevLeg = g_m2Swing.swingHistory[g_m2Swing.swingHistoryCount - 1];
   if(prevLeg.legEndTime == 0 || prevLeg.legStartTime == 0 || prevLeg.swingDirection == 0)
      return false;

   if(M2TryGetVolumeWindowBoundFromLastDecent(prevLeg.legStartTime, prevLeg.legEndTime,
                                               prevLeg.swingDirection, outWindowStartOpen))
      return true;

   outWindowStartOpen = prevLeg.legStartTime;
   return outWindowStartOpen > 0;
}

//+------------------------------------------------------------------+
bool M2CollectTickVolumesInOpenTimeWindow(const datetime windowStartInclusive,
                                           const datetime windowEndInclusive,
                                           long &outVolumes[], int &outCount)
{
   outCount = 0;
   ArrayResize(outVolumes, 0);
   if(windowStartInclusive == 0 || windowEndInclusive == 0)
      return false;
   if(!M2VolumeWindowShiftRangeValid(windowStartInclusive, windowEndInclusive))
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, timeframe, windowEndInclusive, true);

   const int barCount = shiftStartOlder - shiftEndNewer + 1;
   if(barCount < 1)
      return false;

   ArrayResize(outVolumes, barCount);
   int writeIndex = 0;
   for(int barShift = shiftStartOlder; barShift >= shiftEndNewer; barShift--)
   {
      const long barVol = iTickVolume(_Symbol, timeframe, barShift);
      if(barVol < 0)
         return false;
      outVolumes[writeIndex++] = barVol;
   }

   outCount = writeIndex;
   return outCount >= 1;
}

//+------------------------------------------------------------------+
bool M2TouchLegVolumeIsAscendingPattern(const long &volumes[], const int count)
{
   if(count < 2)
      return false;

   int increaseEvents = 0;
   int decreaseEvents = 0;
   for(int i = 1; i < count; i++)
   {
      if(volumes[i] > volumes[i - 1])
         increaseEvents++;
      else if(volumes[i] < volumes[i - 1])
         decreaseEvents++;
   }

   if(volumes[count - 1] <= volumes[0])
      return false;

   return increaseEvents > decreaseEvents;
}

//+------------------------------------------------------------------+
bool M2ValidateTouchLegVolumeIncreasePattern(const long &volumes[], const int count)
{
   if(count < 2)
      return false;

   return M2TouchLegVolumeIsAscendingPattern(volumes, count);
}

//+------------------------------------------------------------------+
string M2FormatTickVolumeArrayLog(const long &volumes[], const int count,
                                   const datetime windowStartOpen, const datetime windowEndOpen)
{
   string text = "vols=[";
   if(count > 0)
   {
      for(int i = 0; i < count; i++)
      {
         if(i > 0)
            text += ",";
         text += IntegerToString(volumes[i]);
      }
   }
   text += "]";
   if(windowStartOpen != 0 && windowEndOpen != 0)
   {
      text += StringFormat(" n=%d lastLeg3rdLast=%s touchBar=%s",
                           count,
                           TimeToString(windowStartOpen, TIME_DATE | TIME_MINUTES),
                           TimeToString(windowEndOpen, TIME_DATE | TIME_MINUTES));
   }
   else if(count <= 0)
      text += " (window empty or unavailable)";
   return text;
}

bool H4TryGetLegLastDecentMovementBarOpen(const datetime legStartTime, const datetime legProgressEnd,
                                           const int swingDirection, datetime &outBarOpenTime)
{
   outBarOpenTime = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   int shiftNewer = iBarShift(_Symbol, timeframe, legProgressEnd, true);
   int shiftOlder = iBarShift(_Symbol, timeframe, legStartTime, true);
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
      if(!H4BarHasDecentMovementForLegDirection(barShift, swingDirection))
         continue;

      outBarOpenTime = iTime(_Symbol, timeframe, barShift);
      return outBarOpenTime > 0;
   }

   return false;
}

//+------------------------------------------------------------------+
datetime H4ProgressEndOpenForDecentLookup(const datetime legProgressEndOpen)
{
   if(legProgressEndOpen == 0)
      return 0;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftNewer = iBarShift(_Symbol, timeframe, legProgressEndOpen, true);
   if(shiftNewer < 0)
      return legProgressEndOpen;

   const int shiftOlder = shiftNewer + 1;
   if(shiftOlder >= iBars(_Symbol, timeframe))
      return legProgressEndOpen;

   const datetime olderOpen = iTime(_Symbol, timeframe, shiftOlder);
   return (olderOpen > 0) ? olderOpen : legProgressEndOpen;
}

//+------------------------------------------------------------------+
bool H4TryGetVolumeBreachWindowBoundFromLastDecent(const datetime legStartTime,
                                                    const datetime legProgressEnd,
                                                    const int swingDirection,
                                                    datetime &outBoundInclusiveOpen)
{
   outBoundInclusiveOpen = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0)
      return false;

   const datetime decentLookupEnd = H4ProgressEndOpenForDecentLookup(legProgressEnd);

   datetime lastDecentOpen = 0;
   if(!H4TryGetLegLastDecentMovementBarOpen(legStartTime, decentLookupEnd, swingDirection,
                                              lastDecentOpen))
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftDecent = iBarShift(_Symbol, timeframe, lastDecentOpen, true);
   if(shiftDecent < 0)
      return false;

   const int shiftBoundInclusive = shiftDecent + 2;
   if(shiftBoundInclusive >= iBars(_Symbol, timeframe))
      return false;

   outBoundInclusiveOpen = iTime(_Symbol, timeframe, shiftBoundInclusive);
   return outBoundInclusiveOpen > 0;
}

//+------------------------------------------------------------------+
bool H4TryGetLegVolumeBreachWindowStartForScan(const datetime legStartTime,
                                               const datetime legProgressEnd,
                                               const int swingDirection,
                                               datetime &outWindowStartInclusiveOpen)
{
   return H4TryGetVolumeBreachWindowBoundFromLastDecent(legStartTime, legProgressEnd, swingDirection,
                                                           outWindowStartInclusiveOpen);
}

//+------------------------------------------------------------------+
bool H4TryGetLegVolumeBreachWindowEndForScan(const datetime legStartTime,
                                             const datetime legProgressEnd,
                                             const int swingDirection,
                                             datetime &outWindowEndInclusiveOpen)
{
   return H4TryGetVolumeBreachWindowBoundFromLastDecent(legStartTime, legProgressEnd, swingDirection,
                                                         outWindowEndInclusiveOpen);
}

//+------------------------------------------------------------------+
bool H4VolumeBreachWindowShiftRangeValid(const datetime windowStartInclusive,
                                         const datetime windowEndInclusive)
{
   if(windowStartInclusive == 0 || windowEndInclusive == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, timeframe, windowEndInclusive, true);
   if(shiftStartOlder < 0 || shiftEndNewer < 0)
      return false;

   return shiftEndNewer <= shiftStartOlder;
}

//+------------------------------------------------------------------+
bool H4TryResolveLegVolumeBreachWindowEnd(const datetime legStartTime,
                                          const datetime legProgressEnd,
                                          const int swingDirection,
                                          const datetime windowStartInclusive,
                                          const int lastClosedBarShift,
                                          datetime &outWindowEndInclusiveOpen)
{
   outWindowEndInclusiveOpen = 0;
   if(legStartTime == 0 || legProgressEnd == 0 || swingDirection == 0 || lastClosedBarShift < 1)
      return false;

   datetime decentBoundOpen = 0;
   if(H4TryGetLegVolumeBreachWindowEndForScan(legStartTime, legProgressEnd, swingDirection,
                                               decentBoundOpen) &&
      H4VolumeBreachWindowShiftRangeValid(windowStartInclusive, decentBoundOpen))
   {
      outWindowEndInclusiveOpen = decentBoundOpen;
      return true;
   }

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int barsTotal = iBars(_Symbol, timeframe);
   for(int shiftBound = lastClosedBarShift + 2; shiftBound >= lastClosedBarShift; shiftBound--)
   {
      if(shiftBound >= barsTotal)
         continue;

      const datetime boundOpen = iTime(_Symbol, timeframe, shiftBound);
      if(boundOpen == 0)
         continue;
      if(!H4VolumeBreachWindowShiftRangeValid(windowStartInclusive, boundOpen))
         continue;

      outWindowEndInclusiveOpen = boundOpen;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
bool FindMaxVolumeH4BarBetweenOpenTimes(const datetime rangeStartOpen, const datetime rangeEndOpen,
                                         datetime &outBarOpenTime, long &outMaxVolume)
{
   outBarOpenTime = 0;
   outMaxVolume   = -1;
   if(rangeStartOpen == 0 || rangeEndOpen == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   datetime rangeLo = rangeStartOpen;
   datetime rangeHi = rangeEndOpen;
   if(rangeLo > rangeHi)
   {
      const datetime tmp = rangeLo;
      rangeLo = rangeHi;
      rangeHi = tmp;
   }

   int shiftNewer = iBarShift(_Symbol, timeframe, rangeHi, false);
   int shiftOlder = iBarShift(_Symbol, timeframe, rangeLo, false);
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
      const long barVol = iTickVolume(_Symbol, timeframe, barShift);
      if(barVol < 0)
         continue;
      if(barVol > outMaxVolume)
      {
         outMaxVolume   = barVol;
         outBarOpenTime = iTime(_Symbol, timeframe, barShift);
      }
   }
   return outBarOpenTime > 0 && outMaxVolume >= 0;
}

//+------------------------------------------------------------------+
void H4ScanVolumeWindowMonotonic(const int swingDirection, const datetime windowStartInclusive,
                                  const datetime windowEndInclusive, long &inOutMaxVolume,
                                  datetime &inOutMaxBarOpenTime, double &inOutBreachLevel)
{
   if(swingDirection == 0 || windowStartInclusive == 0 || windowEndInclusive == 0)
      return;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftStartOlder = iBarShift(_Symbol, timeframe, windowStartInclusive, true);
   const int shiftEndNewer   = iBarShift(_Symbol, timeframe, windowEndInclusive, true);
   if(shiftStartOlder < 0 || shiftEndNewer < 0)
      return;

   if(shiftEndNewer > shiftStartOlder)
      return;

   for(int barShift = shiftEndNewer; barShift <= shiftStartOlder; barShift++)
   {
      const long barVol = iTickVolume(_Symbol, timeframe, barShift);
      if(barVol < 0 || barVol <= inOutMaxVolume)
         continue;

      inOutMaxVolume      = barVol;
      inOutMaxBarOpenTime = iTime(_Symbol, timeframe, barShift);
      inOutBreachLevel    = H4BreachLevelPriceFromVolumeBar(swingDirection, barShift);
   }
}

//+------------------------------------------------------------------+
bool ComputeH4LegVolumeBreachLevel(const Swing &lastLeg, const Swing &prevLeg, const bool hasPrevLeg,
                                    double &outBreachLevel, datetime &outVolumeBarOpenTime)
{
   outBreachLevel       = 0.0;
   outVolumeBarOpenTime = 0;

   if(lastLeg.swingDirection == 0 || lastLeg.legEndTime == 0 || lastLeg.legStartTime == 0)
      return false;

   datetime windowStartOpen = lastLeg.legStartTime;
   if(hasPrevLeg && prevLeg.legEndTime != 0)
   {
      if(!H4TryGetLegVolumeBreachWindowStartForScan(prevLeg.legStartTime, prevLeg.legEndTime,
                                                     prevLeg.swingDirection, windowStartOpen))
         windowStartOpen = prevLeg.legStartTime;
   }

   long     maxVol        = -1;
   datetime maxVolBarOpen = 0;
   double   breachLevel   = 0.0;

   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int shiftLegEnd   = iBarShift(_Symbol, timeframe, lastLeg.legEndTime, true);
   const int shiftLegStart = iBarShift(_Symbol, timeframe, lastLeg.legStartTime, true);
   if(shiftLegEnd < 0 || shiftLegStart < 0)
      return false;

   for(int barShift = shiftLegStart; barShift >= shiftLegEnd; barShift--)
   {
      const datetime progressEndOpen = iTime(_Symbol, timeframe, barShift);
      if(progressEndOpen == 0)
         continue;

      datetime windowEndInclusive = 0;
      if(!H4TryGetLegVolumeBreachWindowEndForScan(lastLeg.legStartTime, progressEndOpen,
                                                   lastLeg.swingDirection, windowEndInclusive))
         continue;

      H4ScanVolumeWindowMonotonic(lastLeg.swingDirection, windowStartOpen, windowEndInclusive,
                                   maxVol, maxVolBarOpen, breachLevel);
   }

   datetime finalWindowEndInclusive = 0;
   if(H4TryGetLegVolumeBreachWindowEndForScan(lastLeg.legStartTime, lastLeg.legEndTime,
                                               lastLeg.swingDirection, finalWindowEndInclusive))
      H4ScanVolumeWindowMonotonic(lastLeg.swingDirection, windowStartOpen, finalWindowEndInclusive,
                                   maxVol, maxVolBarOpen, breachLevel);

   if(maxVolBarOpen == 0 || breachLevel <= 0.0)
   {
      if(lastLeg.swingDirection == 1)
         outBreachLevel = lastLeg.legHighPrice;
      else
         outBreachLevel = lastLeg.legLowPrice;
      outVolumeBarOpenTime = lastLeg.legEndTime;
      return outBreachLevel > 0.0;
   }

   outBreachLevel       = breachLevel;
   outVolumeBarOpenTime = maxVolBarOpen;
   return true;
}

#ifdef H4_LQ_VOLUME_BREACH_ENABLED
// --- H4 volume breach record array, push, sweep, chart rays (disabled v3.04) ---

//+------------------------------------------------------------------+
void H4ResetActiveLegVolumeBreachTrack()
{
   ZeroMemory(g_h4ActiveLegVolumeTrack);
   g_h4ActiveLegVolumeTrack.maxTickVolume = -1;
}

//+------------------------------------------------------------------+
void RememberH4LegVolumeBreachRecord(const datetime legStartTime, const datetime legEndTime,
                                      const int swingDirection, const double breachLevel,
                                      const datetime volumeBarOpenTime)
{
   if(legStartTime == 0 || swingDirection == 0 || breachLevel <= 0.0)
      return;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(legEndTime == 0 && g_h4LegVolumeBreaches[i].legEndTime == 0 &&
         g_h4LegVolumeBreaches[i].legStartTime == legStartTime)
      {
         if(!H4VolumeBreachLevelsMatch(g_h4LegVolumeBreaches[i].breachLevelPrice, breachLevel))
            g_h4LegVolumeBreaches[i].swept = false;
         g_h4LegVolumeBreaches[i].swingDirection    = swingDirection;
         g_h4LegVolumeBreaches[i].breachLevelPrice    = breachLevel;
         g_h4LegVolumeBreaches[i].volumeBarOpenTime = volumeBarOpenTime;
         return;
      }
      if(g_h4LegVolumeBreaches[i].legStartTime == legStartTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection)
      {
         if(!H4VolumeBreachLevelsMatch(g_h4LegVolumeBreaches[i].breachLevelPrice, breachLevel))
            g_h4LegVolumeBreaches[i].swept = false;
         if(legEndTime > 0)
            g_h4LegVolumeBreaches[i].legEndTime = legEndTime;
         g_h4LegVolumeBreaches[i].breachLevelPrice    = breachLevel;
         g_h4LegVolumeBreaches[i].volumeBarOpenTime = volumeBarOpenTime;
         return;
      }
      if(legEndTime > 0 && g_h4LegVolumeBreaches[i].legEndTime == legEndTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection)
      {
         if(!H4VolumeBreachLevelsMatch(g_h4LegVolumeBreaches[i].breachLevelPrice, breachLevel))
            g_h4LegVolumeBreaches[i].swept = false;
         g_h4LegVolumeBreaches[i].legStartTime        = legStartTime;
         g_h4LegVolumeBreaches[i].breachLevelPrice    = breachLevel;
         g_h4LegVolumeBreaches[i].volumeBarOpenTime = volumeBarOpenTime;
         return;
      }
   }

   if(g_h4LegVolumeBreachCount < H4_LEG_VOLUME_BREACH_CAPACITY)
   {
      const int index = g_h4LegVolumeBreachCount;
      g_h4LegVolumeBreaches[index].legStartTime        = legStartTime;
      g_h4LegVolumeBreaches[index].legEndTime          = legEndTime;
      g_h4LegVolumeBreaches[index].swingDirection       = swingDirection;
      g_h4LegVolumeBreaches[index].breachLevelPrice     = breachLevel;
      g_h4LegVolumeBreaches[index].volumeBarOpenTime  = volumeBarOpenTime;
      g_h4LegVolumeBreaches[index].swept              = false;
      g_h4LegVolumeBreachCount++;
      return;
   }

   DeleteH4VolumeBreachLevelRay(g_h4LegVolumeBreaches[0].legStartTime);
   for(int shiftIndex = 1; shiftIndex < H4_LEG_VOLUME_BREACH_CAPACITY; shiftIndex++)
      g_h4LegVolumeBreaches[shiftIndex - 1] = g_h4LegVolumeBreaches[shiftIndex];

   const int lastIndex = H4_LEG_VOLUME_BREACH_CAPACITY - 1;
   g_h4LegVolumeBreaches[lastIndex].legStartTime        = legStartTime;
   g_h4LegVolumeBreaches[lastIndex].legEndTime          = legEndTime;
   g_h4LegVolumeBreaches[lastIndex].swingDirection       = swingDirection;
   g_h4LegVolumeBreaches[lastIndex].breachLevelPrice     = breachLevel;
   g_h4LegVolumeBreaches[lastIndex].volumeBarOpenTime  = volumeBarOpenTime;
   g_h4LegVolumeBreaches[lastIndex].swept              = false;
}

//+------------------------------------------------------------------+
bool TryGetH4VolumeBreachWindowStartFromLastCompletedLeg(const SwingState &swingState,
                                                          datetime &outWindowStartOpen)
{
   outWindowStartOpen = 0;
   if(swingState.swingHistoryCount < 1)
      return false;

   const Swing leg = swingState.swingHistory[swingState.swingHistoryCount - 1];
   if(leg.legEndTime == 0 || leg.legStartTime == 0 || leg.swingDirection == 0)
      return false;

   if(H4TryGetLegVolumeBreachWindowStartForScan(leg.legStartTime, leg.legEndTime, leg.swingDirection,
                                                 outWindowStartOpen))
      return true;

   outWindowStartOpen = leg.legStartTime;
   return outWindowStartOpen > 0;
}

//+------------------------------------------------------------------+
void H4OnH4ActiveLegStarted(SwingState &swingState, const int lastClosedBarShift)
{
   H4ResetActiveLegVolumeBreachTrack();

   if(swingState.currentSwingLeg.swingDirection == 0 || swingState.currentSwingLeg.legStartTime == 0)
      return;

   g_h4ActiveLegVolumeTrack.legStartTime         = swingState.currentSwingLeg.legStartTime;
   g_h4ActiveLegVolumeTrack.swingDirection      = swingState.currentSwingLeg.swingDirection;
   g_h4ActiveLegVolumeTrack.windowStartOpenTime = swingState.currentSwingLeg.legStartTime;

   if(!TryGetH4VolumeBreachWindowStartFromLastCompletedLeg(swingState,
                                                           g_h4ActiveLegVolumeTrack.windowStartOpenTime))
      g_h4ActiveLegVolumeTrack.windowStartOpenTime = swingState.currentSwingLeg.legStartTime;

   H4PurgeStaleActiveLegVolumeBreachRecords(swingState.currentSwingLeg.legStartTime);
   H4OnH4ActiveLegBarClosed(swingState, lastClosedBarShift);
}

//+------------------------------------------------------------------+
void H4OnH4ActiveLegBarClosed(SwingState &swingState, const int lastClosedBarShift)
{
   if(swingState.currentSwingLeg.swingDirection == 0 || swingState.currentSwingLeg.legStartTime == 0)
      return;
   if(g_h4ActiveLegVolumeTrack.legStartTime != swingState.currentSwingLeg.legStartTime)
      return;

   g_h4ActiveLegVolumeTrack.swingDirection = swingState.currentSwingLeg.swingDirection;

   if(lastClosedBarShift < 1)
      return;

   const datetime lastClosedOpen = iTime(_Symbol, PERIOD_H4, lastClosedBarShift);
   if(lastClosedOpen == 0)
      return;

   datetime windowEndInclusive = 0;
   if(!H4TryResolveLegVolumeBreachWindowEnd(swingState.currentSwingLeg.legStartTime,
                                             lastClosedOpen,
                                             swingState.currentSwingLeg.swingDirection,
                                             g_h4ActiveLegVolumeTrack.windowStartOpenTime,
                                             lastClosedBarShift,
                                             windowEndInclusive))
      return;

   H4ScanVolumeWindowMonotonic(g_h4ActiveLegVolumeTrack.swingDirection,
                                g_h4ActiveLegVolumeTrack.windowStartOpenTime,
                                windowEndInclusive,
                                g_h4ActiveLegVolumeTrack.maxTickVolume,
                                g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime,
                                g_h4ActiveLegVolumeTrack.breachLevelPrice);

   if(g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime == 0 ||
      g_h4ActiveLegVolumeTrack.breachLevelPrice <= 0.0)
      return;

   RememberH4LegVolumeBreachRecord(swingState.currentSwingLeg.legStartTime, 0,
                                    g_h4ActiveLegVolumeTrack.swingDirection,
                                    g_h4ActiveLegVolumeTrack.breachLevelPrice,
                                    g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime);
}

//+------------------------------------------------------------------+
void H4PurgeStaleActiveLegVolumeBreachRecords(const datetime keepLegStartTime)
{
   int writeIndex = 0;
   for(int readIndex = 0; readIndex < g_h4LegVolumeBreachCount; readIndex++)
   {
      const H4LegVolumeBreachRecord rec = g_h4LegVolumeBreaches[readIndex];
      if(rec.legEndTime == 0 && rec.legStartTime != keepLegStartTime)
      {
         DeleteH4VolumeBreachLevelRay(rec.legStartTime);
         continue;
      }

      if(writeIndex != readIndex)
         g_h4LegVolumeBreaches[writeIndex] = rec;
      writeIndex++;
   }
   g_h4LegVolumeBreachCount = writeIndex;
}

//+------------------------------------------------------------------+
void H4FinalizeActiveLegVolumeBreach(const Swing &closedLeg)
{
   if(closedLeg.legStartTime == 0 || closedLeg.legEndTime == 0 || closedLeg.swingDirection == 0)
      return;

   double breachLevel = 0.0;
   datetime volumeBarOpenTime = 0;
   bool     resolvedFromTrack = false;

   if(g_h4ActiveLegVolumeTrack.legStartTime == closedLeg.legStartTime &&
      g_h4ActiveLegVolumeTrack.swingDirection == closedLeg.swingDirection)
   {
      datetime finalizeWindowEndInclusive = 0;
      if(closedLeg.legEndTime > 0 &&
         H4TryGetLegVolumeBreachWindowEndForScan(closedLeg.legStartTime, closedLeg.legEndTime,
                                                   closedLeg.swingDirection, finalizeWindowEndInclusive))
      {
         H4ScanVolumeWindowMonotonic(closedLeg.swingDirection,
                                      g_h4ActiveLegVolumeTrack.windowStartOpenTime,
                                      finalizeWindowEndInclusive,
                                      g_h4ActiveLegVolumeTrack.maxTickVolume,
                                      g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime,
                                      g_h4ActiveLegVolumeTrack.breachLevelPrice);
      }

      if(g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime > 0 &&
         g_h4ActiveLegVolumeTrack.breachLevelPrice > 0.0)
      {
         breachLevel       = g_h4ActiveLegVolumeTrack.breachLevelPrice;
         volumeBarOpenTime = g_h4ActiveLegVolumeTrack.maxVolumeBarOpenTime;
         resolvedFromTrack = true;
      }
   }

   if(!resolvedFromTrack)
   {
      Swing prevLeg;
      ZeroMemory(prevLeg);
      const bool hasPrevLeg = (g_mtfSwingH4.swing.swingHistoryCount > 1);
      if(hasPrevLeg)
         prevLeg = g_mtfSwingH4.swing.swingHistory[g_mtfSwingH4.swing.swingHistoryCount - 2];

      if(!ComputeH4LegVolumeBreachLevel(closedLeg, prevLeg, hasPrevLeg, breachLevel, volumeBarOpenTime))
         return;
   }

   RememberH4LegVolumeBreachRecord(closedLeg.legStartTime, closedLeg.legEndTime,
                                    closedLeg.swingDirection, breachLevel, volumeBarOpenTime);
   H4PurgeStaleActiveLegVolumeBreachRecords(0);
   H4ResetActiveLegVolumeBreachTrack();
}

//+------------------------------------------------------------------+
void H4RestoreActiveLegVolumeBreachTrackFromSwing()
{
   if(g_mtfSwingH4.swing.currentSwingLeg.swingDirection == 0 || g_mtfSwingH4.swing.currentSwingLeg.legStartTime == 0)
   {
      H4ResetActiveLegVolumeBreachTrack();
      return;
   }
   H4OnH4ActiveLegStarted(g_mtfSwingH4.swing);
}

//+------------------------------------------------------------------+
bool TryGetH4LegVolumeBreachLevel(const datetime legEndTime, const int swingDirection,
                                   double &outBreachLevel, datetime &outVolumeBarOpenTime)
{
   outBreachLevel       = 0.0;
   outVolumeBarOpenTime = 0;
   if(legEndTime == 0)
      return false;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(g_h4LegVolumeBreaches[i].legEndTime == legEndTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection)
      {
         outBreachLevel       = g_h4LegVolumeBreaches[i].breachLevelPrice;
         outVolumeBarOpenTime = g_h4LegVolumeBreaches[i].volumeBarOpenTime;
         return outBreachLevel > 0.0;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryResolveH4LegVolumeBreachLevel(const datetime legStartTime, const datetime legEndTime,
                                       const int swingDirection, double &outBreachLevel,
                                       datetime &outVolumeBarOpenTime)
{
   outBreachLevel       = 0.0;
   outVolumeBarOpenTime = 0;
   if(legStartTime == 0 || swingDirection == 0)
      return false;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(g_h4LegVolumeBreaches[i].legStartTime == legStartTime &&
         g_h4LegVolumeBreaches[i].swingDirection == swingDirection &&
         g_h4LegVolumeBreaches[i].breachLevelPrice > 0.0)
      {
         outBreachLevel       = g_h4LegVolumeBreaches[i].breachLevelPrice;
         outVolumeBarOpenTime = g_h4LegVolumeBreaches[i].volumeBarOpenTime;
         return outVolumeBarOpenTime > 0;
      }
   }

   if(legEndTime > 0)
      return TryGetH4LegVolumeBreachLevel(legEndTime, swingDirection, outBreachLevel,
                                            outVolumeBarOpenTime);

   return false;
}

//+------------------------------------------------------------------+
bool IsH4BarWithinBreachBufferChartWindow(const datetime barOpenTime)
{
   const int barCount = InputH4BreachBufferChartBarCount;
   if(barCount < 1 || barOpenTime <= 0)
      return false;

   const int barShift = iBarShift(_Symbol, PERIOD_H4, barOpenTime, false);
   if(barShift < 0)
      return false;

   return barShift >= 1 && barShift <= barCount;
}

//+------------------------------------------------------------------+
bool IsH4LegVolumeBreachActiveInBufferWindow(const datetime legEndTime, const int swingDirection)
{
   if(legEndTime == 0 || swingDirection == 0)
      return false;

   double breachLevel = 0.0;
   datetime volumeBarOpenTime = 0;
   if(TryGetH4LegVolumeBreachLevel(legEndTime, swingDirection, breachLevel, volumeBarOpenTime))
   {
      if(volumeBarOpenTime > 0 && IsH4BarWithinBreachBufferChartWindow(volumeBarOpenTime))
         return true;
   }

   return IsH4BarWithinBreachBufferChartWindow(legEndTime);
}

//+------------------------------------------------------------------+
void H4ClearVolumeBreachMemoryAndChart()
{
   g_h4LegVolumeBreachCount = 0;
   H4ResetActiveLegVolumeBreachTrack();
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);
}

//+------------------------------------------------------------------+
void RebuildH4LegVolumeBreachLevelsFromSwingHistory()
{
   g_h4LegVolumeBreachCount = 0;

   for(int legIndex = 0; legIndex < g_mtfSwingH4.swing.swingHistoryCount; legIndex++)
   {
      const Swing lastLeg = g_mtfSwingH4.swing.swingHistory[legIndex];
      Swing       prevLeg;
      ZeroMemory(prevLeg);
      const bool hasPrevLeg = (legIndex > 0);

      if(hasPrevLeg)
         prevLeg = g_mtfSwingH4.swing.swingHistory[legIndex - 1];

      double breachLevel = 0.0;
      datetime volumeBarOpenTime = 0;
      if(!ComputeH4LegVolumeBreachLevel(lastLeg, prevLeg, hasPrevLeg, breachLevel, volumeBarOpenTime))
         continue;

      RememberH4LegVolumeBreachRecord(lastLeg.legStartTime, lastLeg.legEndTime,
                                       lastLeg.swingDirection, breachLevel, volumeBarOpenTime);
   }
}

//+------------------------------------------------------------------+
void DeleteH4VolumeBreachLevelRay(const datetime legStartTime)
{
   if(legStartTime == 0)
      return;

   const string objName =
      ChartObjectNamePrefixH4VolumeBreachRay + IntegerToString((long)legStartTime);
   ObjectDelete(0, objName);
}

//+------------------------------------------------------------------+
void DrawH4VolumeBreachLevelRay(const datetime legStartTime, const datetime legEndTime,
                                 const int swingDirection, const datetime volumeBarOpenTime,
                                 const double breachLevel)
{
   if(!H4LqChartDrawEnabled(InputDrawMtfSwingLegsH4) || legStartTime == 0 || swingDirection == 0 ||
      volumeBarOpenTime == 0 || breachLevel <= 0.0)
      return;

   const color rayColor = (swingDirection == 1)
                          ? H4_VOLUME_BREACH_RAY_COLOR_UP
                          : H4_VOLUME_BREACH_RAY_COLOR_DOWN;

   const string objName =
      ChartObjectNamePrefixH4VolumeBreachRay + IntegerToString((long)legStartTime);

   const int h4PeriodSec = (int)PeriodSeconds(PERIOD_H4);
   if(h4PeriodSec < 1)
      return;

   const int bufferBars = InputH4BreachBufferChartBarCount;
   if(bufferBars < 1)
      return;

   const datetime timeEnd =
      volumeBarOpenTime + (datetime)((long)bufferBars * (long)h4PeriodSec);

   if(ObjectFind(0, objName) < 0)
   {
      if(!ObjectCreate(0, objName, OBJ_TREND, 0, volumeBarOpenTime, breachLevel, timeEnd, breachLevel))
         return;
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_TIME, 0, volumeBarOpenTime);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, breachLevel);
      ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeEnd);
      ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, breachLevel);
   }

   ObjectSetInteger(0, objName, OBJPROP_COLOR, rayColor);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_ZORDER, H4_VOLUME_BREACH_RAY_ZORDER);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
void RebuildAllH4VolumeBreachMarkers()
{
   if(!H4LqChartDrawEnabled(InputDrawMtfSwingLegsH4))
   {
      ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);
      return;
   }

   ObjectsDeleteAll(0, ChartObjectNamePrefixH4VolumeBreachRay, -1, -1);

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      const H4LegVolumeBreachRecord rec = g_h4LegVolumeBreaches[i];
      if(rec.legStartTime == 0 || rec.swingDirection == 0 || rec.breachLevelPrice <= 0.0)
         continue;

      if(rec.legEndTime == 0 &&
         (g_mtfSwingH4.swing.currentSwingLeg.legStartTime != rec.legStartTime ||
          g_mtfSwingH4.swing.currentSwingLeg.swingDirection != rec.swingDirection))
         continue;

      if(rec.swept)
         continue;

      if(!IsH4LegVolumeBreachActiveInBufferWindow(rec.legEndTime == 0 ? rec.legStartTime : rec.legEndTime,
                                                   rec.swingDirection) &&
         rec.legEndTime != 0)
         continue;

      if(rec.legEndTime == 0)
      {
         datetime volumeBarOpenTime = rec.volumeBarOpenTime;
         if(volumeBarOpenTime == 0)
            volumeBarOpenTime = rec.legStartTime;
         if(!IsH4BarWithinBreachBufferChartWindow(volumeBarOpenTime))
            continue;
      }

      DrawH4VolumeBreachLevelRay(rec.legStartTime, rec.legEndTime, rec.swingDirection,
                                  rec.volumeBarOpenTime, rec.breachLevelPrice);
   }
}

//+------------------------------------------------------------------+
bool H4VolumeBreachLevelsMatch(const double levelA, const double levelB)
{
   if(levelA <= 0.0 || levelB <= 0.0)
      return false;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   return MathAbs(levelA - levelB) <= eps;
}

//+------------------------------------------------------------------+
bool H4IsVolumeBreachRecordSwept(const datetime legKey, const int swingDirection,
                                  const double breachLevel)
{
   if(swingDirection == 0 || breachLevel <= 0.0)
      return false;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      const H4LegVolumeBreachRecord rec = g_h4LegVolumeBreaches[i];
      if(rec.swingDirection != swingDirection)
         continue;
      if(!H4VolumeBreachLevelsMatch(rec.breachLevelPrice, breachLevel))
         continue;
      if(legKey != 0 && legKey != rec.legStartTime && legKey != rec.legEndTime)
         continue;
      return rec.swept;
   }
   return false;
}

//+------------------------------------------------------------------+
void H4MarkVolumeBreachRecordSwept(const datetime legKey, const int swingDirection,
                                    const double breachLevel)
{
   if(swingDirection == 0 || breachLevel <= 0.0)
      return;

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(g_h4LegVolumeBreaches[i].swingDirection != swingDirection)
         continue;
      if(!H4VolumeBreachLevelsMatch(g_h4LegVolumeBreaches[i].breachLevelPrice, breachLevel))
         continue;
      if(legKey != 0 && legKey != g_h4LegVolumeBreaches[i].legStartTime &&
         legKey != g_h4LegVolumeBreaches[i].legEndTime)
         continue;

      g_h4LegVolumeBreaches[i].swept = true;
      DeleteH4VolumeBreachLevelRay(g_h4LegVolumeBreaches[i].legStartTime);
      return;
   }
}

//+------------------------------------------------------------------+
//| Up-leg level (green): H4 low below level after vol bar. Down-leg (pink): H4 high above. |
//+------------------------------------------------------------------+
bool WasH4VolumeBreachLevelViolatedSinceFormation(const int swingDirection,
                                                    const double breachLevel,
                                                    const datetime levelFormedOpenTime,
                                                    const double pointSize)
{
   if(swingDirection == 0 || breachLevel <= 0.0 || levelFormedOpenTime == 0)
      return false;

   const double eps = (pointSize > 0.0 ? pointSize : 0.00001);
   const int formationShift =
      iBarShift(_Symbol, PERIOD_H4, levelFormedOpenTime, false);
   if(formationShift < 0)
      return false;

   for(int barShift = formationShift - 1; barShift >= 1; barShift--)
   {
      if(swingDirection == 1)
      {
         const double barLow = iLow(_Symbol, PERIOD_H4, barShift);
         if(barLow > 0.0 && barLow < breachLevel - eps)
            return true;
      }
      else if(swingDirection == -1)
      {
         const double barHigh = iHigh(_Symbol, PERIOD_H4, barShift);
         if(barHigh > 0.0 && barHigh > breachLevel + eps)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Mark volume breach levels swept (each M2 close + once on attach). |
//+------------------------------------------------------------------+
void UpdateH4LegLiquidityBreachMemoryOnM2Bar()
{
   if(InputH4BreachBufferChartBarCount < 1)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = 0; i < g_h4LegVolumeBreachCount; i++)
   {
      if(g_h4LegVolumeBreaches[i].swingDirection == 0 || g_h4LegVolumeBreaches[i].breachLevelPrice <= 0.0)
         continue;

      if(g_h4LegVolumeBreaches[i].swept)
         continue;

      const bool isActiveLeg = (g_h4LegVolumeBreaches[i].legEndTime == 0);
      if(isActiveLeg)
      {
         if(g_mtfSwingH4.swing.currentSwingLeg.legStartTime != g_h4LegVolumeBreaches[i].legStartTime ||
            g_mtfSwingH4.swing.currentSwingLeg.swingDirection != g_h4LegVolumeBreaches[i].swingDirection)
            continue;

         datetime volumeBarOpenTime = g_h4LegVolumeBreaches[i].volumeBarOpenTime;
         if(volumeBarOpenTime == 0)
            volumeBarOpenTime = g_h4LegVolumeBreaches[i].legStartTime;
         if(!IsH4BarWithinBreachBufferChartWindow(volumeBarOpenTime))
            continue;
      }
      else if(!IsH4LegVolumeBreachActiveInBufferWindow(g_h4LegVolumeBreaches[i].legEndTime,
                                                        g_h4LegVolumeBreaches[i].swingDirection))
      {
         continue;
      }

      datetime scanFromOpenTime = g_h4LegVolumeBreaches[i].volumeBarOpenTime;
      if(scanFromOpenTime == 0)
         scanFromOpenTime = (g_h4LegVolumeBreaches[i].legEndTime > 0)
                            ? g_h4LegVolumeBreaches[i].legEndTime
                            : g_h4LegVolumeBreaches[i].legStartTime;

      if(!WasH4VolumeBreachLevelViolatedSinceFormation(g_h4LegVolumeBreaches[i].swingDirection,
                                                        g_h4LegVolumeBreaches[i].breachLevelPrice,
                                                        scanFromOpenTime, pointSize))
         continue;

      g_h4LegVolumeBreaches[i].swept = true;
      DeleteH4VolumeBreachLevelRay(g_h4LegVolumeBreaches[i].legStartTime);
      if(H4LqLoggingEnabled())
      {
         const datetime legKey = (g_h4LegVolumeBreaches[i].legEndTime > 0)
                                 ? g_h4LegVolumeBreaches[i].legEndTime
                                 : g_h4LegVolumeBreaches[i].legStartTime;
         LogHuntEvent("BREACH_SWEPT",
                      StringFormat("H4 %s leg %s level=%.5f volBar=%s price %s level â€” skip hunt",
                                   g_h4LegVolumeBreaches[i].swingDirection == 1 ? "up" : "down",
                                   TimeToString(legKey, TIME_DATE | TIME_MINUTES),
                                   g_h4LegVolumeBreaches[i].breachLevelPrice,
                                   TimeToString(scanFromOpenTime, TIME_DATE | TIME_MINUTES),
                                   g_h4LegVolumeBreaches[i].swingDirection == 1 ? "below" : "above"));
      }
   }
}

#endif // H4_LQ_VOLUME_BREACH_ENABLED
#ifdef H4_LQ_VOLUME_BREACH_ENABLED
// --- M2 wick breach detect + hunt accept (disabled v3.04) ---

//+------------------------------------------------------------------+
bool M2WickCrossesAboveLevel(const double level, const double barHigh, const double prevHigh,
                             const double pointSize)
{
   return (barHigh > level + pointSize && prevHigh <= level + pointSize);
}

//+------------------------------------------------------------------+
bool M2WickCrossesBelowLevel(const double level, const double barLow, const double prevLow,
                             const double pointSize)
{
   return (barLow < level - pointSize && prevLow >= level - pointSize);
}

#endif // H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
//| Breach buffer band (% of H4 reference height): high 2% below..10% above; low 2% above..10% below. |
//+------------------------------------------------------------------+
void H4BreachBufferBandForUpLegHigh(const double breachLevel, double &outBandLow, double &outBandHigh)
{
   const double referenceHeight = ReferenceChartHeightForH4BreachBuffer();
   if(referenceHeight <= 0.0)
   {
      outBandLow  = breachLevel;
      outBandHigh = breachLevel;
      return;
   }

   outBandLow  = breachLevel - referenceHeight * (H4_BREACH_BUFFER_PERCENT_NEAR / 100.0);
   outBandHigh = breachLevel + referenceHeight * (H4_BREACH_BUFFER_PERCENT_FAR / 100.0);
}

//+------------------------------------------------------------------+
void H4BreachBufferBandForDownLegLow(const double breachLevel, double &outBandLow, double &outBandHigh)
{
   const double referenceHeight = ReferenceChartHeightForH4BreachBuffer();
   if(referenceHeight <= 0.0)
   {
      outBandLow  = breachLevel;
      outBandHigh = breachLevel;
      return;
   }

   outBandLow  = breachLevel - referenceHeight * (H4_BREACH_BUFFER_PERCENT_FAR / 100.0);
   outBandHigh = breachLevel + referenceHeight * (H4_BREACH_BUFFER_PERCENT_NEAR / 100.0);
}

//+------------------------------------------------------------------+
#ifdef H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
bool M2WickCrossesIntoH4UpBreachBuffer(const double bandLow, const double bandHigh,
                                        const double barHigh, const double prevHigh,
                                        const double pointSize)
{
   if(prevHigh >= bandLow - pointSize)
      return false;
   return barHigh >= bandLow - pointSize;
}

//+------------------------------------------------------------------+
bool M2WickCrossesIntoH4DownBreachBuffer(const double bandLow, const double bandHigh,
                                          const double barLow, const double prevLow,
                                          const double pointSize)
{
   if(prevLow <= bandHigh + pointSize)
      return false;
   return barLow <= bandHigh + pointSize;
}

//+------------------------------------------------------------------+
bool TryAcceptH4BreachForHunt(const bool h4HighBreached, const double breachLevel,
                               const datetime legEnd, double &outLevel, bool &outHighBreached,
                               datetime &outLegEndTime)
{
   if(breachLevel <= 0.0 || legEnd == 0)
      return false;

   outLevel        = breachLevel;
   outLegEndTime   = legEnd;
   outHighBreached = h4HighBreached;
   return true;
}

#endif // H4_LQ_VOLUME_BREACH_ENABLED

#endif // H4_LQ_V3_H4VOLUMEBREACH
