//+------------------------------------------------------------------+
//| EngulfSweepSetup.mqh
//| Engulf sweep setup and entry
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_ENGULFSWEEPSETUP
#define H4_LQ_V3_ENGULFSWEEPSETUP

bool M2TryGetLegBarOpenFromEnd(const datetime legStartTime, const datetime legEndTime,
                                const int barsFromEnd, datetime &outBarOpen)
{
   outBarOpen = 0;
   if(legStartTime == 0 || legEndTime == 0 || barsFromEnd < 1)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int endShift = iBarShift(_Symbol, timeframe, legEndTime, true);
   if(endShift < 0)
      return false;

   const int targetShift = endShift + (barsFromEnd - 1);
   if(targetShift >= iBars(_Symbol, timeframe))
      return false;

   const datetime targetOpen = iTime(_Symbol, timeframe, targetShift);
   if(targetOpen == 0 || targetOpen < legStartTime)
      return false;

   outBarOpen = targetOpen;
   return true;
}

//+------------------------------------------------------------------+
//| v3 — Engulfing Volume Absorption model                             |
//+------------------------------------------------------------------+
bool M2BarIsBullishAtShift(const int barShift)
{
   const double openPrice  = iOpen(_Symbol, InputM2NarrativeTimeframe, barShift);
   const double closePrice = iClose(_Symbol, InputM2NarrativeTimeframe, barShift);
   return closePrice > openPrice;
}

//+------------------------------------------------------------------+
bool M2BarIsBearishAtShift(const int barShift)
{
   const double openPrice  = iOpen(_Symbol, InputM2NarrativeTimeframe, barShift);
   const double closePrice = iClose(_Symbol, InputM2NarrativeTimeframe, barShift);
   return closePrice < openPrice;
}

//+------------------------------------------------------------------+
bool M2SwingLegMeetsExhaustionMinRange(const Swing &leg, const double chartHeight)
{
   if(InputEngulfExhaustionMinLegRangePercentChart <= 0.0)
      return true;
   if(chartHeight <= 0.0 || leg.legHighPrice <= 0.0 || leg.legLowPrice <= 0.0)
      return false;

   const double legRange = leg.legHighPrice - leg.legLowPrice;
   const double minRange = chartHeight * (InputEngulfExhaustionMinLegRangePercentChart / 100.0);
   return legRange >= minRange;
}

//+------------------------------------------------------------------+
bool M2SumLegTickVolumeFromPrevLegWindow(const Swing &prevLeg, const Swing &curLeg, long &outSum)
{
   outSum = 0;
   datetime winStart = 0;
   datetime winEnd   = 0;
   if(!M2TryGetLegBarOpenFromEnd(prevLeg.legStartTime, prevLeg.legEndTime, 2, winStart))
      return false;
   if(!M2TryGetLegBarOpenFromEnd(curLeg.legStartTime, curLeg.legEndTime, 2, winEnd))
      return false;

   long     vols[];
   int      count = 0;
   if(!M2CollectTickVolumesInOpenTimeWindow(winStart, winEnd, vols, count) || count < 1)
      return false;

   for(int i = 0; i < count; i++)
      outSum += vols[i];
   return true;
}

//+------------------------------------------------------------------+
double M2EngulfSlBufferPrice(const int barShift)
{
   if(InputEngulfSlBufferPercentChart <= 0.0)
      return 0.0;

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(barShift, InputChartRangeBarCount);
   if(chartHeight <= 0.0)
      return 0.0;
   return chartHeight * (InputEngulfSlBufferPercentChart / 100.0);
}

//+------------------------------------------------------------------+
double M2AvgTickVolumeLastBars(const int lastClosedBarShift, const int barCount)
{
   if(lastClosedBarShift < 1 || barCount < 1)
      return 0.0;

   long   totalVol = 0;
   int    validBars = 0;
   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);

   for(int shift = lastClosedBarShift; shift < lastClosedBarShift + barCount; shift++)
   {
      if(shift >= barsTotal)
         break;
      const long barVol = iTickVolume(_Symbol, timeframe, shift);
      if(barVol < 0)
         continue;
      totalVol += barVol;
      validBars++;
   }

   if(validBars < 1)
      return 0.0;
   return (double)totalVol / (double)validBars;
}

//+------------------------------------------------------------------+
bool V3DetectBearishEngulfFootprint(const int candle1Shift, const int candle2Shift)
{
   if(candle1Shift < 1 || candle2Shift < 1)
      return false;
   if(!M2BarIsBullishAtShift(candle1Shift))
      return false;
   if(!M2BarIsBearishAtShift(candle2Shift))
      return false;

   const double c1Open = iOpen(_Symbol, InputM2NarrativeTimeframe, candle1Shift);
   const double c2Close = iClose(_Symbol, InputM2NarrativeTimeframe, candle2Shift);
   return c2Close < c1Open;
}

//+------------------------------------------------------------------+
bool V3DetectBullishEngulfFootprint(const int candle1Shift, const int candle2Shift)
{
   if(candle1Shift < 1 || candle2Shift < 1)
      return false;
   if(!M2BarIsBearishAtShift(candle1Shift))
      return false;
   if(!M2BarIsBullishAtShift(candle2Shift))
      return false;

   const double c1Open = iOpen(_Symbol, InputM2NarrativeTimeframe, candle1Shift);
   const double c2Close = iClose(_Symbol, InputM2NarrativeTimeframe, candle2Shift);
   return c2Close > c1Open;
}

//+------------------------------------------------------------------+
struct V3SweepRefCandidate
{
   double   refLevel;
   datetime legEndTime;
   Swing    leg;
};

//+------------------------------------------------------------------+
bool V3M2PricesEqual(const double priceA, const double priceB, const double eps)
{
   return MathAbs(priceA - priceB) <= eps;
}

//+------------------------------------------------------------------+
int V3FindM2SwingLegHistoryIndex(const Swing &leg)
{
   for(int i = 0; i < g_m2Swing.swingHistoryCount; i++)
   {
      if(g_m2Swing.swingHistory[i].legStartTime == leg.legStartTime &&
         g_m2Swing.swingHistory[i].legEndTime == leg.legEndTime &&
         g_m2Swing.swingHistory[i].swingDirection == leg.swingDirection)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
bool V3TryGetM2LegAvgTickVolume(const Swing &leg, double &outLegAvg, int &outBarCount)
{
   outLegAvg   = 0.0;
   outBarCount = 0;
   if(leg.legStartTime == 0 || leg.legEndTime == 0)
      return false;

   long legVols[];
   int  legVolCount = 0;
   if(!M2CollectTickVolumesInOpenTimeWindow(leg.legStartTime, leg.legEndTime, legVols, legVolCount) ||
      legVolCount < 1)
      return false;

   long sumVol = 0;
   for(int i = 0; i < legVolCount; i++)
      sumVol += legVols[i];

   outLegAvg   = (double)sumVol / (double)legVolCount;
   outBarCount = legVolCount;
   return outLegAvg > 0.0;
}

//+------------------------------------------------------------------+
bool V3TryGetM2LegTransitionSpikeVolume(const Swing &leg, const int legHistoryIndex,
                                         long &outSpikeVol, datetime &outNextLegStartTime)
{
   outSpikeVol         = 0;
   outNextLegStartTime = 0;
   if(leg.legEndTime == 0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int lastBarShift = iBarShift(_Symbol, timeframe, leg.legEndTime, false);
   if(lastBarShift < 0)
      return false;

   const long volLastLegBar = iTickVolume(_Symbol, timeframe, lastBarShift);
   if(volLastLegBar < 0)
      return false;

   const int oppositeDir = -leg.swingDirection;
   Swing     nextLeg;
   ZeroMemory(nextLeg);
   bool haveNextLeg = false;

   if(legHistoryIndex >= 0 && legHistoryIndex + 1 < g_m2Swing.swingHistoryCount)
   {
      nextLeg = g_m2Swing.swingHistory[legHistoryIndex + 1];
      haveNextLeg = (nextLeg.swingDirection == oppositeDir && nextLeg.legStartTime > 0);
   }
   else if(g_m2Swing.currentSwingLeg.swingDirection == oppositeDir &&
           g_m2Swing.currentSwingLeg.legStartTime > 0)
   {
      nextLeg     = g_m2Swing.currentSwingLeg;
      haveNextLeg = true;
   }

   long spikeVol = volLastLegBar;
   if(haveNextLeg)
   {
      outNextLegStartTime = nextLeg.legStartTime;
      const int firstNextShift = iBarShift(_Symbol, timeframe, nextLeg.legStartTime, false);
      if(firstNextShift >= 0)
      {
         const long volFirstNextBar = iTickVolume(_Symbol, timeframe, firstNextShift);
         if(volFirstNextBar >= 0)
            spikeVol = MathMax(volLastLegBar, volFirstNextBar);
      }
   }

   outSpikeVol = spikeVol;
   return outSpikeVol > 0;
}

//+------------------------------------------------------------------+
bool V3SwingLegRefVolumeSpikeValid(const Swing &leg, string &outDetail)
{
   outDetail = "";
   if(leg.legEndTime == 0 || leg.legStartTime == 0)
   {
      outDetail = "leg times unavailable";
      return false;
   }

   double legAvg = 0.0;
   int    legBarCount = 0;
   if(!V3TryGetM2LegAvgTickVolume(leg, legAvg, legBarCount))
   {
      outDetail = "leg avg vol unavailable";
      return false;
   }

   const int legHistoryIndex = V3FindM2SwingLegHistoryIndex(leg);
   long      spikeVol        = 0;
   datetime  nextLegStart     = 0;
   if(!V3TryGetM2LegTransitionSpikeVolume(leg, legHistoryIndex, spikeVol, nextLegStart))
   {
      outDetail = "leg transition spike vol unavailable";
      return false;
   }

   outDetail = StringFormat("legVol spikeMax=%lld legAvg=%.0f bars=%d legEnd=%s nextLeg=%s",
                            (long)spikeVol, legAvg, legBarCount,
                            TimeToString(leg.legEndTime, TIME_DATE | TIME_MINUTES),
                            nextLegStart > 0
                               ? TimeToString(nextLegStart, TIME_DATE | TIME_MINUTES)
                               : "none");
   return (double)spikeVol > legAvg;
}

//+------------------------------------------------------------------+
//| Bear: (1) wick above ref somewhere in 1..countdown, (2) shift-1 close below ref with edge. |
//| Bull mirrored. Fires once on the rejecting close, not every bar the window still matches.   |
//+------------------------------------------------------------------+
bool V3CountdownTwoEventSweepSetup(const bool isBuy, const int countdown,
                                    const double refLevel, const double eps,
                                    double &outWindowSlExtreme, int &outTriggerShift)
{
   outWindowSlExtreme = isBuy ? 1.0e100 : -1.0e100;
   outTriggerShift    = 1;

   if(countdown < 1 || refLevel <= 0.0)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   if(barsTotal < countdown + 2)
      return false;

   const double close1 = iClose(_Symbol, timeframe, 1);
   const double close2 = iClose(_Symbol, timeframe, 2);

   bool wickSweepInWindow = false;

   for(int shift = 1; shift <= countdown; shift++)
   {
      const double barHigh = iHigh(_Symbol, timeframe, shift);
      const double barLow  = iLow(_Symbol, timeframe, shift);

      if(isBuy)
      {
         outWindowSlExtreme = MathMin(outWindowSlExtreme, barLow);
         if(barLow < refLevel - eps)
            wickSweepInWindow = true;
      }
      else
      {
         outWindowSlExtreme = MathMax(outWindowSlExtreme, barHigh);
         if(barHigh > refLevel + eps)
            wickSweepInWindow = true;
      }
   }

   if(!wickSweepInWindow)
      return false;

   if(isBuy)
   {
      if(close1 <= refLevel + eps)
         return false;
      if(close2 > refLevel + eps)
         return false;
   }
   else
   {
      if(close1 >= refLevel - eps)
         return false;
      if(close2 < refLevel - eps)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
int V3BuildSweptSwingRefCandidates(const bool isBuy, const int countdown, const double eps,
                                    V3SweepRefCandidate &outCandidates[])
{
   ArrayResize(outCandidates, 0);
   const int legDirection = isBuy ? -1 : 1;

   V3SweepRefCandidate crossed[];
   int crossedCount = 0;

   for(int legIndex = 0; legIndex < g_m2Swing.swingHistoryCount; legIndex++)
   {
      const Swing leg = g_m2Swing.swingHistory[legIndex];
      if(leg.swingDirection != legDirection || leg.legEndTime == 0)
         continue;

      const double refLevel = isBuy ? leg.legLowPrice : leg.legHighPrice;
      if(refLevel <= 0.0)
         continue;

      double windowSlExtreme = 0.0;
      int    triggerShift    = 0;
      if(!V3CountdownTwoEventSweepSetup(isBuy, countdown, refLevel, eps,
                                         windowSlExtreme, triggerShift))
         continue;

      ArrayResize(crossed, crossedCount + 1);
      crossed[crossedCount].refLevel   = refLevel;
      crossed[crossedCount].legEndTime = leg.legEndTime;
      crossed[crossedCount].leg        = leg;
      crossedCount++;
   }

   if(crossedCount < 1)
      return 0;

   // Equal highs/lows: keep earliest legEndTime per price.
   V3SweepRefCandidate unique[];
   int uniqueCount = 0;

   for(int i = 0; i < crossedCount; i++)
   {
      bool merged = false;
      for(int u = 0; u < uniqueCount; u++)
      {
         if(!V3M2PricesEqual(crossed[i].refLevel, unique[u].refLevel, eps))
            continue;
         if(crossed[i].legEndTime < unique[u].legEndTime)
            unique[u] = crossed[i];
         merged = true;
         break;
      }
      if(!merged)
      {
         ArrayResize(unique, uniqueCount + 1);
         unique[uniqueCount++] = crossed[i];
      }
   }

   // Priority: bear = highest swept high first; bull = lowest swept low first.
   for(int i = 0; i < uniqueCount - 1; i++)
   {
      for(int j = i + 1; j < uniqueCount; j++)
      {
         bool swapNeeded = false;
         if(isBuy)
            swapNeeded = (unique[j].refLevel < unique[i].refLevel);
         else
            swapNeeded = (unique[j].refLevel > unique[i].refLevel);

         if(swapNeeded)
         {
            const V3SweepRefCandidate tmp = unique[i];
            unique[i] = unique[j];
            unique[j] = tmp;
         }
      }
   }

   ArrayResize(outCandidates, uniqueCount);
   for(int i = 0; i < uniqueCount; i++)
      outCandidates[i] = unique[i];
   return uniqueCount;
}

//+------------------------------------------------------------------+
bool V3TryGetM2SwingLegRefLevel(const bool isBuy, double &outRefLevel)
{
   outRefLevel = 0.0;
   const int  legDirection = isBuy ? -1 : 1;
   double     legLow       = 0.0;
   double     legHigh      = 0.0;
   datetime   legStart     = 0;
   datetime   legEnd       = 0;
   if(!V2TryGetLastCompletedM2Leg(legDirection, legLow, legHigh, legStart, legEnd))
      return false;

   outRefLevel = isBuy ? legLow : legHigh;
   return outRefLevel > 0.0;
}

//+------------------------------------------------------------------+
//| Two events in countdown: wick sweep then shift-1 close reject (edge). Multi-leg + leg vol. |
//+------------------------------------------------------------------+
bool V3DetectM2SwingSweepRejectInCountdown(const bool isBuy, const int countdown,
                                            double &outRefLevel, double &outWindowSlExtreme,
                                            int &outOldestShift, int &outNewestShift,
                                            string &outDetail)
{
   outRefLevel        = 0.0;
   outWindowSlExtreme = 0.0;
   outOldestShift     = countdown;
   outNewestShift     = 1;
   outDetail          = "";

   if(countdown < 1)
   {
      outDetail = "countdown < 1";
      return false;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   if(barsTotal < countdown + 2)
   {
      outDetail = "insufficient M2 bars";
      return false;
   }

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   V3SweepRefCandidate candidates[];
   const int candidateCount = V3BuildSweptSwingRefCandidates(isBuy, countdown, eps, candidates);
   if(candidateCount < 1)
   {
      outDetail = "no two-event sweep on shift-1 close";
      return false;
   }

   for(int candidateIndex = 0; candidateIndex < candidateCount; candidateIndex++)
   {
      const V3SweepRefCandidate candidate = candidates[candidateIndex];
      double windowSlExtreme = 0.0;
      int    triggerShift    = 0;

      if(!V3CountdownTwoEventSweepSetup(isBuy, countdown, candidate.refLevel, eps,
                                         windowSlExtreme, triggerShift))
         continue;

      string volDetail = "";
      if(!V3SwingLegRefVolumeSpikeValid(candidate.leg, volDetail))
      {
         V2LogHuntEvent(-1, "SWEEP_REF_INVALID",
                        StringFormat("%s ref=%.5f leg=%s — %s",
                                     isBuy ? "bull" : "bear",
                                     candidate.refLevel,
                                     TimeToString(candidate.legEndTime, TIME_DATE | TIME_MINUTES),
                                     volDetail));
         continue;
      }

      outRefLevel        = candidate.refLevel;
      outWindowSlExtreme = windowSlExtreme;
      outOldestShift     = countdown;
      outNewestShift     = triggerShift;
      outDetail = StringFormat("ref=%.5f leg=%s candidates=%d idx=%d %s",
                               candidate.refLevel,
                               TimeToString(candidate.legEndTime, TIME_DATE | TIME_MINUTES),
                               candidateCount, candidateIndex + 1, volDetail);
      return true;
   }

   outDetail = StringFormat("no swept ref passed leg vol (%d two-event)", candidateCount);
   return false;
}

//+------------------------------------------------------------------+
bool M2PrevLocalExtremeBeforeEngulfPair(const bool wantHigh, const int pairOldestShift,
                                         double &outExtreme)
{
   outExtreme = 0.0;
   const int lookbackStart = pairOldestShift + 1;
   const int lookbackEnd   = InputChartRangeBarCount;
   if(lookbackStart > lookbackEnd)
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   bool found = false;

   for(int shift = lookbackStart; shift <= lookbackEnd; shift++)
   {
      if(shift >= barsTotal)
         break;
      if(wantHigh)
      {
         const double barHigh = iHigh(_Symbol, timeframe, shift);
         if(!found || barHigh > outExtreme)
         {
            outExtreme = barHigh;
            found = true;
         }
      }
      else
      {
         const double barLow = iLow(_Symbol, timeframe, shift);
         if(!found || barLow < outExtreme)
         {
            outExtreme = barLow;
            found = true;
         }
      }
   }
   return found;
}

//+------------------------------------------------------------------+
bool V3EngulfPairLocalExtremeBandValid(const bool isBuy, const int countdown,
                                        const double sweepRefLevel, string &outDetail)
{
   outDetail = "";
   if(InputEngulfPairLocalExtremeMinOffsetPercentChart == 0.0 &&
      InputEngulfPairLocalExtremeMaxOffsetPercentChart == 0.0)
      return true;

   if(countdown < 1)
   {
      outDetail = "countdown < 1";
      return false;
   }

   if(sweepRefLevel <= 0.0)
   {
      outDetail = "sweep ref level unavailable";
      return false;
   }

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   const int barsTotal = iBars(_Symbol, timeframe);
   if(barsTotal < countdown + 1)
   {
      outDetail = "insufficient M2 bars";
      return false;
   }

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(1, InputChartRangeBarCount);
   if(chartHeight <= 0.0)
   {
      outDetail = "chart height unavailable";
      return false;
   }

   const double minOffset =
      chartHeight * (InputEngulfPairLocalExtremeMinOffsetPercentChart / 100.0);
   const double maxOffset =
      chartHeight * (InputEngulfPairLocalExtremeMaxOffsetPercentChart / 100.0);
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps = (pointSize > 0.0 ? pointSize : 0.00001);

   double windowHigh = -1.0e100;
   double windowLow  = 1.0e100;
   for(int shift = 1; shift <= countdown; shift++)
   {
      windowHigh = MathMax(windowHigh, iHigh(_Symbol, timeframe, shift));
      windowLow  = MathMin(windowLow, iLow(_Symbol, timeframe, shift));
   }

   if(isBuy)
   {
      const double bandHigh = sweepRefLevel - minOffset;
      const double bandLow  = sweepRefLevel - maxOffset;
      outDetail = StringFormat("windowLow=%.5f sweepRefLow=%.5f band=%.5f..%.5f",
                               windowLow, sweepRefLevel, bandLow, bandHigh);
      return windowLow <= bandHigh + eps && windowLow >= bandLow - eps;
   }

   const double bandLow  = sweepRefLevel + minOffset;
   const double bandHigh = sweepRefLevel + maxOffset;
   outDetail = StringFormat("windowHigh=%.5f sweepRefHigh=%.5f band=%.5f..%.5f",
                            windowHigh, sweepRefLevel, bandLow, bandHigh);
   return windowHigh >= bandLow - eps && windowHigh <= bandHigh + eps;
}

//+------------------------------------------------------------------+
bool V3EngulfVolumeSpikeValid(const int candle1Shift, const int candle2Shift)
{
   const long vol1 = iTickVolume(_Symbol, InputM2NarrativeTimeframe, candle1Shift);
   const long vol2 = iTickVolume(_Symbol, InputM2NarrativeTimeframe, candle2Shift);
   if(vol1 < 0 || vol2 < 0)
      return false;

   const double pairAvg = 0.5 * ((double)vol1 + (double)vol2);
   const double baselineAvg = M2AvgTickVolumeLastBars(candle2Shift, InputEngulfVolAvgBarCount);
   if(baselineAvg <= 0.0)
      return false;

   return pairAvg > baselineAvg;
}

//+------------------------------------------------------------------+
bool V3ValidateM2LegExhaustion(const bool isBuy, string &outDetail)
{
   outDetail = "";
   const bool isBearSetup = !isBuy;
   const int  exhaustLegDir = isBearSetup ? 1 : -1;

   datetime lookbackStart = iTime(_Symbol, InputM2NarrativeTimeframe, InputChartRangeBarCount);
   if(lookbackStart == 0)
   {
      outDetail = "lookback unavailable";
      return false;
   }

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(1, InputChartRangeBarCount);
   if(InputEngulfExhaustionMinLegRangePercentChart > 0.0 && chartHeight <= 0.0)
   {
      outDetail = "chart height unavailable";
      return false;
   }

   const int requiredLegCount = 2;
   long legVolumes[];
   ArrayResize(legVolumes, requiredLegCount);
   int found = 0;

   for(int legIndex = g_m2Swing.swingHistoryCount - 1; legIndex >= 0 && found < requiredLegCount; legIndex--)
   {
      const Swing leg = g_m2Swing.swingHistory[legIndex];
      if(leg.swingDirection != exhaustLegDir)
         continue;
      if(leg.legEndTime == 0 || leg.legStartTime == 0)
         continue;
      if(leg.legEndTime < lookbackStart)
         continue;
      if(!M2SwingLegMeetsExhaustionMinRange(leg, chartHeight))
         continue;
      if(legIndex < 1)
         continue;

      long sumVol = 0;
      if(!M2SumLegTickVolumeFromPrevLegWindow(g_m2Swing.swingHistory[legIndex - 1], leg, sumVol))
         continue;

      legVolumes[found++] = sumVol;
   }

   if(found < 2)
   {
      outDetail = StringFormat("need 2 %s legs w/ vol window found=%d",
                               isBearSetup ? "up" : "down", found);
      return false;
   }

   const long volC = legVolumes[0]; // latest same-dir leg
   const long volB = legVolumes[1]; // prior same-dir leg
   outDetail = StringFormat("volC=%lld volB=%lld", (long)volC, (long)volB);

   return volC > volB;
}

bool V3M2SwingSweepSetupPatternValidCore(const bool isBuy, const double barClose,
                                          double &outStopLoss, datetime &outSignalBarOpen,
                                          double &outRefLevel, int &outCountdown,
                                          string &outExhaustDetail)
{
   outStopLoss = 0.0;
   outSignalBarOpen = 0;
   outRefLevel = 0.0;
   outCountdown = 0;
   outExhaustDetail = "";

   const int countdown = MathMax(1, InputEngulfSweepCountdownBars);
   outCountdown = countdown;

   double refLevel = 0.0;
   double windowSlExtreme = 0.0;
   int    c1Shift = 0;
   int    c2Shift = 0;
   string sweepDetail = "";
   if(!V3DetectM2SwingSweepRejectInCountdown(isBuy, countdown, refLevel, windowSlExtreme,
                                              c1Shift, c2Shift, sweepDetail))
      return false;

   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;

   string localBandDetail = "";
   if(!V3EngulfPairLocalExtremeBandValid(isBuy, countdown, refLevel, localBandDetail))
      return false;

   string exhaustDetail = "";
   if(!V3ValidateM2LegExhaustion(isBuy, exhaustDetail))
      return false;

   const double stopLoss = NormalizeDouble(windowSlExtreme, _Digits);
   if(stopLoss <= 0.0 || (isBuy && stopLoss >= barClose) || (!isBuy && stopLoss <= barClose))
      return false;

   outStopLoss = stopLoss;
   outSignalBarOpen = iTime(_Symbol, timeframe, c2Shift);
   outRefLevel = refLevel;
   outExhaustDetail = exhaustDetail;
   return true;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void V3TryScanM2SwingSweepSetup(const bool isBuy, const double barClose)
{
   double stopLoss = 0.0;
   datetime signalBarOpen = 0;
   double refLevel = 0.0;
   int countdown = 0;
   string exhaustDetail = "";
   if(V3M2SwingSweepSetupPatternValidCore(isBuy, barClose, stopLoss, signalBarOpen,
                                           refLevel, countdown, exhaustDetail))
   {
      const double entryPrice = barClose;
      int setupLogIndex = -1;
      const double setupScore = CalculateSetupTradeScore(isBuy, setupLogIndex, signalBarOpen);

      V2LogHuntEvent(-1, InputScoreLogWriteCsv ? "SWEEP_ZONE_LOG" : "SWEEP_SIGNAL",
                     StringFormat("%s entry=%.5f sl=%.5f ref=%.5f cd=%d%s %s bar=%s",
                                  isBuy ? "bull" : "bear", entryPrice, stopLoss, refLevel, countdown,
                                  InputScoreLogWriteCsv ? "" : StringFormat(" score=%.2f", setupScore),
                                  exhaustDetail,
                                  TimeToString(signalBarOpen, TIME_DATE | TIME_MINUTES)));

      if(!SetupScoreAllowsTradeEntry(setupScore))
      {
         V2LogHuntEvent(-1, "SWEEP_SKIP",
                        StringFormat("%s setupScore=%.2f <= min %.2f",
                                     isBuy ? "bull" : "bear", setupScore,
                                     GetMinScoreThreshold()));
         return;
      }

      TryPlaceEngulfAbsorptionTradeSetup(-1, isBuy, entryPrice, stopLoss,
                                          signalBarOpen, signalBarOpen, setupScore, setupLogIndex);
      return;
   }

   const int countdownBars = MathMax(1, InputEngulfSweepCountdownBars);

   double windowSlExtreme = 0.0;
   int    c1Shift = 0;
   int    c2Shift = 0;
   string sweepDetail = "";
   if(!V3DetectM2SwingSweepRejectInCountdown(isBuy, countdownBars, refLevel, windowSlExtreme,
                                              c1Shift, c2Shift, sweepDetail))
      return;

   string localBandDetail = "";
   if(!V3EngulfPairLocalExtremeBandValid(isBuy, countdownBars, refLevel, localBandDetail))
   {
      V2LogHuntEvent(-1, "SWEEP_SKIP",
                     StringFormat("%s local extreme band fail — %s",
                                  isBuy ? "bull" : "bear", localBandDetail));
      return;
   }

   if(!V3ValidateM2LegExhaustion(isBuy, exhaustDetail))
   {
      V2LogHuntEvent(-1, "SWEEP_SKIP",
                     StringFormat("%s exhaustion fail — %s",
                                  isBuy ? "bull" : "bear", exhaustDetail));
      return;
   }

   const double slCheck = NormalizeDouble(windowSlExtreme, _Digits);
   if(slCheck <= 0.0 || (isBuy && slCheck >= barClose) || (!isBuy && slCheck <= barClose))
      V2LogHuntEvent(-1, "SWEEP_SKIP",
                     StringFormat("%s SL vs entry invalid", isBuy ? "bull" : "bear"));
}

#ifdef H4_LQ_VOLUME_BREACH_ENABLED
// --- hunt arm on H4 volume breach (disabled v3.04) ---

//+------------------------------------------------------------------+
#endif // H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
#ifdef H4_LQ_VOLUME_BREACH_ENABLED
// --- M2 wick vs breach-record level → hunt arm (disabled v3.04) ---

#endif // H4_LQ_VOLUME_BREACH_ENABLED

//+------------------------------------------------------------------+
bool V3ResolveSetupExtremesForZoneScoring(const bool isBuy, double &outSetupLow, double &outSetupHigh)
{
   const ENUM_TIMEFRAMES timeframe = InputM2NarrativeTimeframe;
   outSetupLow  = iLow(_Symbol, timeframe, 1);
   outSetupHigh = iHigh(_Symbol, timeframe, 1);
   if(outSetupLow <= 0.0 || outSetupHigh <= 0.0)
      return false;

   const int countdown = MathMax(1, InputEngulfSweepCountdownBars);
   double refLevel = 0.0;
   double windowSlExtreme = 0.0;
   int    c1Shift = 0;
   int    c2Shift = 0;
   string sweepDetail = "";
   if(V3DetectM2SwingSweepRejectInCountdown(isBuy, countdown, refLevel, windowSlExtreme,
                                             c1Shift, c2Shift, sweepDetail)
      && windowSlExtreme > 0.0)
   {
      if(isBuy)
         outSetupLow = windowSlExtreme;
      else
         outSetupHigh = windowSlExtreme;
   }

   return true;
}

//+------------------------------------------------------------------+
double CalculateSetupTradeScore(const bool isBullishTrade, int &outSetupLogIndex,
                                 const datetime setupBarOpenTime = 0)
{
   outSetupLogIndex = -1;

   double setupLow  = 0.0;
   double setupHigh = 0.0;
   V3ResolveSetupExtremesForZoneScoring(isBullishTrade, setupLow, setupHigh);

   if(InputScoreLogWriteCsv)
   {
      ENUM_SMC_ZONE_TYPE zoneTypes[];
      CollectMatchingSetupZoneTypes(isBullishTrade, setupLow, setupHigh, zoneTypes);
      outSetupLogIndex = LogSetupZoneTypesJsonEntry(isBullishTrade, zoneTypes, setupLow, setupHigh,
                                                     setupBarOpenTime);
      return 0.0;
   }

   return CalculateTotalTradeScore(isBullishTrade, setupLow, setupHigh);
}

//+------------------------------------------------------------------+
void ProcessM2EngulfDirectionOnBarClose(const bool isBuy, const double barClose)
{
   V3TryScanM2SwingSweepSetup(isBuy, barClose);
}

//+------------------------------------------------------------------+
void ProcessHuntEngulfingOnM2BarClose()
{
   if(!InputEnableEngulfHuntAfterH4Breach)
      return;

   const double barClose = iClose(_Symbol, InputM2NarrativeTimeframe, 1);

   ProcessM2EngulfDirectionOnBarClose(true, barClose);
   ProcessM2EngulfDirectionOnBarClose(false, barClose);
}

#endif // H4_LQ_V3_ENGULFSWEEPSETUP
