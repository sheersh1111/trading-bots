//+------------------------------------------------------------------+
//| MtfSwingBos.mqh
//| MTF swing and BOS
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_MTFSWINGBOS
#define H4_LQ_V3_MTFSWINGBOS

//+------------------------------------------------------------------+
bool TryPushH4ReplayLeg(H4ReplayLeg &replayLegs[], int &replayLegCount, const Swing &closedLeg)
{
   if(closedLeg.swingDirection == 0 || closedLeg.legEndTime == 0)
      return false;
   if(replayLegCount >= H4_REPLAY_LEG_CAPACITY)
      return false;

   replayLegs[replayLegCount].legHighPrice    = closedLeg.legHighPrice;
   replayLegs[replayLegCount].legLowPrice     = closedLeg.legLowPrice;
   replayLegs[replayLegCount].legStartTime    = closedLeg.legStartTime;
   replayLegs[replayLegCount].legEndTime      = closedLeg.legEndTime;
   replayLegs[replayLegCount].swingDirection = closedLeg.swingDirection;
   replayLegCount++;
   return true;
}

//+------------------------------------------------------------------+
//| Replay one closed TF bar; append completed legs (no live side effects). |
//+------------------------------------------------------------------+
void MtfSwingStepReplayAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                                const int lastClosedBarShift,
                                H4ReplayLeg &replayLegs[], int &replayLegCount)
{
   bool unusedLegClosed = false;
   ProcessMTFSwingStepAtShiftCollect(swingState, timeframe, lastClosedBarShift,
                                      InputSmcSwingAnchorMultiplier, false,
                                      replayLegs, replayLegCount, true, unusedLegClosed);
}

//+------------------------------------------------------------------+
//| MTF SMC Confluence Engine — Phase 1: multi-timeframe swing trackers |
//+------------------------------------------------------------------+
void ProcessMTFSwingStepAtShiftCollect(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                                        const int lastClosedBarShift, const double anchorMultiplier,
                                        const bool useWickAndBodyForDecent,
                                        H4ReplayLeg &replayLegs[], int &replayLegCount,
                                        const bool collectCompletedLegs, bool &outLegClosedThisBar)
{
   outLegClosedThisBar = false;
   const int sh = lastClosedBarShift;

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
   const double minDecentRange       = averageRangeFiveBars * anchorMultiplier;
   const bool isDecentMovement =
      useWickAndBodyForDecent
      ? (lastClosedBarWickRange > minDecentRange && lastClosedBarBodyRange > minDecentRange)
      : (lastClosedBarWickRange > minDecentRange);

   const double anchorForFlipCheck = swingState.priceAnchorLevel;
   int nextSwingDirection = swingState.currentSwingLeg.swingDirection;
   if(swingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < anchorForFlipCheck)
      nextSwingDirection = -1;
   else if(swingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > anchorForFlipCheck)
      nextSwingDirection = 1;

   if(nextSwingDirection == swingState.currentSwingLeg.swingDirection)
   {
      if(isDecentMovement && candleDirection == swingState.currentSwingLeg.swingDirection)
         swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);
      return;
   }

   SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);

   Swing closedSwingLeg = swingState.currentSwingLeg;
   if(collectCompletedLegs)
   {
      closedSwingLeg.legEndTime = iTime(_Symbol, timeframe, sh);
      TryPushH4ReplayLeg(replayLegs, replayLegCount, closedSwingLeg);
      outLegClosedThisBar = true;
   }
   else
   {
      SwingCloseH4ToHistory(swingState, timeframe, sh);
      outLegClosedThisBar = true;
      if(swingState.swingHistoryCount < 1)
         return;
      closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
   }

   double newSwingLegHigh = lastClosedBarHigh;
   double newSwingLegLow  = lastClosedBarLow;
   if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
      newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
   else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
      newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

   SwingStartNew(swingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow, sh);
   swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
}

//+------------------------------------------------------------------+
void ProcessMTFSwingStepAtShift(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                                 const int lastClosedBarShift, const double anchorMultiplier,
                                 const bool useWickAndBodyForDecent, bool &outLegClosedThisBar)
{
   H4ReplayLeg unusedReplayLegs[];
   int         unusedReplayLegCount = 0;
   ProcessMTFSwingStepAtShiftCollect(swingState, timeframe, lastClosedBarShift, anchorMultiplier,
                                      useWickAndBodyForDecent, unusedReplayLegs, unusedReplayLegCount,
                                      false, outLegClosedThisBar);
}

//+------------------------------------------------------------------+
bool SMCTryDetectBosOnBar(const SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                           const int barShift, int &outDirection, double &outBrokenLevel,
                           datetime &outBarOpenTime, datetime &outLegEndTime,
                           double &outLegHigh, double &outLegLow)
{
   outDirection   = 0;
   outBrokenLevel = 0.0;
   outBarOpenTime = 0;
   outLegEndTime  = 0;
   outLegHigh     = 0.0;
   outLegLow      = 0.0;

   if(barShift < 1 || swingState.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, timeframe, barShift);
   const double prevClose  = iClose(_Symbol, timeframe, barShift + 1);
   const double pointSize    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps          = (pointSize > 0.0 ? pointSize : 0.00001);

   outBarOpenTime = iTime(_Symbol, timeframe, barShift);
   if(outBarOpenTime == 0)
      return false;

   for(int historyIndex = swingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(swingState.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double legHigh = swingState.swingHistory[historyIndex].legHighPrice;
      if(closePrice > legHigh + eps && prevClose <= legHigh + eps)
      {
         outDirection   = 1;
         outBrokenLevel = legHigh;
         outLegEndTime  = swingState.swingHistory[historyIndex].legEndTime;
         outLegHigh     = swingState.swingHistory[historyIndex].legHighPrice;
         outLegLow      = swingState.swingHistory[historyIndex].legLowPrice;
         return true;
      }
      break;
   }

   for(int historyIndex = swingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(swingState.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double legLow = swingState.swingHistory[historyIndex].legLowPrice;
      if(closePrice < legLow - eps && prevClose >= legLow - eps)
      {
         outDirection   = -1;
         outBrokenLevel = legLow;
         outLegEndTime  = swingState.swingHistory[historyIndex].legEndTime;
         outLegHigh     = swingState.swingHistory[historyIndex].legHighPrice;
         outLegLow      = swingState.swingHistory[historyIndex].legLowPrice;
         return true;
      }
      break;
   }

   return false;
}

//+------------------------------------------------------------------+
string SMCMtfTimeframeLogTag(const ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_W1:  return "W1";
      case PERIOD_D1:  return "D1";
      case PERIOD_H4:  return "H4";
      case PERIOD_M15: return "M15";
   }
   return EnumToString(timeframe);
}

//+------------------------------------------------------------------+
void SMCUpdateTrackerBosOnBar(MTFSwingTracker &tracker, const int barShift)
{
   int        bosDir = 0;
   double     bosLevel = 0.0;
   datetime   barOpen = 0;
   datetime   legEnd = 0;
   double     legHigh = 0.0;
   double     legLow = 0.0;
   if(!SMCTryDetectBosOnBar(tracker.swing, tracker.timeframe, barShift, bosDir, bosLevel, barOpen,
                             legEnd, legHigh, legLow))
      return;

   tracker.lastBosDirection     = bosDir;
   tracker.lastBosLevel         = bosLevel;
   tracker.lastBosBarOpenTime   = barOpen;
   tracker.lastBrokenLegEndTime = legEnd;
   tracker.lastBrokenLegHigh    = legHigh;
   tracker.lastBrokenLegLow     = legLow;

   if(tracker.timeframe != 0)
      ProfessionalBiasSetDirection(tracker.timeframe, bosDir, barOpen);

   if(H4LqLoggingEnabled())
   {
      LogHuntEvent("MTF_BOS",
                   StringFormat("%s %s BOS bar=%s legEnd=%s lvl=%.5f",
                                SMCMtfTimeframeLogTag(tracker.timeframe),
                                bosDir == 1 ? "bull" : "bear",
                                TimeToString(barOpen, TIME_DATE | TIME_MINUTES),
                                TimeToString(legEnd, TIME_DATE | TIME_MINUTES),
                                bosLevel));
   }
}

//+------------------------------------------------------------------+
void SMCUpdateTrackerOnBarClose(MTFSwingTracker &tracker, const ENUM_TIMEFRAMES timeframe,
                                 datetime &lastBarOpen)
{
   const datetime barOpen = iTime(_Symbol, timeframe, 0);
   if(barOpen == 0 || barOpen == lastBarOpen)
      return;

   lastBarOpen = barOpen;
   if(tracker.timeframe == 0)
      tracker.timeframe = timeframe;

   bool legClosedThisBar = false;
   ProcessMTFSwingStepAtShift(tracker.swing, timeframe, 1, InputSmcSwingAnchorMultiplier, false,
                              legClosedThisBar);

   SMCRefreshZonesForTimeframe(timeframe, tracker, legClosedThisBar);
   SMCUpdateTrackerBosOnBar(tracker, 1);

   if(timeframe == PERIOD_M15 && legClosedThisBar)
   {
      const int histCount = tracker.swing.swingHistoryCount;
      if(histCount > 0)
      {
         const Swing closedLeg = tracker.swing.swingHistory[histCount - 1];
         if(closedLeg.swingDirection != 0 && closedLeg.legEndTime != 0)
         {
            g_m15ClosedLegForTpMgmt.ready       = true;
            g_m15ClosedLegForTpMgmt.direction   = closedLeg.swingDirection;
            g_m15ClosedLegForTpMgmt.legHigh     = closedLeg.legHighPrice;
            g_m15ClosedLegForTpMgmt.legLow      = closedLeg.legLowPrice;
            g_m15ClosedLegForTpMgmt.legStartTime = closedLeg.legStartTime;
            g_m15ClosedLegForTpMgmt.legEndTime  = closedLeg.legEndTime;
         }
      }
   }

   if(timeframe == PERIOD_H4)
   {
      RebuildH4LiquidityPivotLevels();
      if(InputEnableH4BosTradeDirectionBias)
         LogH4TradeDirectionBiasIfChanged();
#ifdef H4_LQ_VOLUME_BREACH_ENABLED
      if(H4LqChartDrawEnabled(InputDrawMtfSwingLegsH4))
         RebuildAllH4VolumeBreachMarkers();
#endif
   }
}

//+------------------------------------------------------------------+
void WarmupMTFSwingTracker(MTFSwingTracker &tracker, const ENUM_TIMEFRAMES timeframe,
                            datetime &lastBarOpen)
{
   tracker.timeframe = timeframe;
   ZeroMemory(tracker.swing);
   tracker.lastBosDirection = 0;
   tracker.lastBosLevel     = 0.0;
   tracker.lastBrokenLegHigh = 0.0;
   tracker.lastBrokenLegLow  = 0.0;

   if(InputSmcMtfWarmupBars <= 0)
   {
      lastBarOpen = iTime(_Symbol, timeframe, 0);
      return;
   }

   const int bars = iBars(_Symbol, timeframe);
   const int n = (int)MathMin(bars - 2, InputSmcMtfWarmupBars);
   if(n >= 1)
   {
      for(int k = n; k >= 1; k--)
      {
         bool unusedLegClosed = false;
         ProcessMTFSwingStepAtShift(tracker.swing, timeframe, k, InputSmcSwingAnchorMultiplier, false,
                                    unusedLegClosed);
         SMCUpdateTrackerBosOnBar(tracker, k);
      }
   }

   lastBarOpen = iTime(_Symbol, timeframe, 0);
}

//+------------------------------------------------------------------+
void WarmupMTFSwingsFromHistory()
{
   if(!InputEnableMtfSmcEngine)
      return;

   WarmupMTFSwingTracker(g_mtfSwingW1,  PERIOD_W1,  g_lastMtfBarOpenW1);
   WarmupMTFSwingTracker(g_mtfSwingD1,  PERIOD_D1,  g_lastMtfBarOpenD1);
   WarmupMTFSwingTracker(g_mtfSwingH4,  PERIOD_H4,  g_lastMtfBarOpenH4);
   WarmupMTFSwingTracker(g_mtfSwingM15, PERIOD_M15, g_lastMtfBarOpenM15);
}

//+------------------------------------------------------------------+
void UpdateMTFSwings()
{
   if(!InputEnableMtfSmcEngine)
      return;

   SMCUpdateTrackerOnBarClose(g_mtfSwingW1,  PERIOD_W1,  g_lastMtfBarOpenW1);
   SMCUpdateTrackerOnBarClose(g_mtfSwingD1,  PERIOD_D1,  g_lastMtfBarOpenD1);
   SMCUpdateTrackerOnBarClose(g_mtfSwingH4,  PERIOD_H4,  g_lastMtfBarOpenH4);
   SMCUpdateTrackerOnBarClose(g_mtfSwingM15, PERIOD_M15, g_lastMtfBarOpenM15);

   if(H4LqChartDrawEnabled(InputShowMtfDirectionHud))
      RefreshMtfDirectionHud();
}

//+------------------------------------------------------------------+
//| MTF SMC Phase 3–4 — zone matrix + fusion clustering               |
//+------------------------------------------------------------------+
void ResetProfessionalBiasOverrideState()
{
   ZeroMemory(g_profBiasOverrideW1);
   ZeroMemory(g_profBiasOverrideD1);
   ZeroMemory(g_profBiasOverrideH4);
   ZeroMemory(g_profBiasOverrideM15);
}

//+------------------------------------------------------------------+
void ProfessionalBiasGetOverrideState(const ENUM_TIMEFRAMES timeframe,
                                       int &overrideBias, datetime &overrideTime)
{
   overrideBias = 0;
   overrideTime = 0;
   if(timeframe == PERIOD_W1)
   {
      overrideBias = g_profBiasOverrideW1.overrideBias;
      overrideTime = g_profBiasOverrideW1.overrideTime;
   }
   else if(timeframe == PERIOD_D1)
   {
      overrideBias = g_profBiasOverrideD1.overrideBias;
      overrideTime = g_profBiasOverrideD1.overrideTime;
   }
   else if(timeframe == PERIOD_H4)
   {
      overrideBias = g_profBiasOverrideH4.overrideBias;
      overrideTime = g_profBiasOverrideH4.overrideTime;
   }
   else if(timeframe == PERIOD_M15)
   {
      overrideBias = g_profBiasOverrideM15.overrideBias;
      overrideTime = g_profBiasOverrideM15.overrideTime;
   }
}

//+------------------------------------------------------------------+
void ProfessionalBiasSetDirection(const ENUM_TIMEFRAMES timeframe, const int bias,
                                     const datetime setBarOpen)
{
   if(bias == 0)
      return;

   if(timeframe == PERIOD_W1)
   {
      g_profBiasOverrideW1.overrideBias = bias;
      g_profBiasOverrideW1.overrideTime = setBarOpen;
   }
   else if(timeframe == PERIOD_D1)
   {
      g_profBiasOverrideD1.overrideBias = bias;
      g_profBiasOverrideD1.overrideTime = setBarOpen;
   }
   else if(timeframe == PERIOD_H4)
   {
      g_profBiasOverrideH4.overrideBias = bias;
      g_profBiasOverrideH4.overrideTime = setBarOpen;
   }
   else if(timeframe == PERIOD_M15)
   {
      g_profBiasOverrideM15.overrideBias = bias;
      g_profBiasOverrideM15.overrideTime = setBarOpen;
   }
}

//+------------------------------------------------------------------+
bool SMCZoneBarCloseRejectionBias(const double top, const double bottom,
                                   const double barClose, const double eps,
                                   int &outBias)
{
   outBias = 0;
   if(top <= bottom || barClose <= 0.0)
      return false;

   const bool closeInside = (barClose >= bottom - eps && barClose <= top + eps);
   if(closeInside)
      return false;

   if(barClose < bottom - eps)
   {
      outBias = BIAS_BEARISH;
      return true;
   }
   if(barClose > top + eps)
   {
      outBias = BIAS_BULLISH;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void SMCUpdateProfessionalBiasFromZoneBarClose(const ENUM_TIMEFRAMES timeframe)
{
   const double barClose = iClose(_Symbol, timeframe, 1);
   const datetime barOpen = iTime(_Symbol, timeframe, 1);
   if(barClose <= 0.0 || barOpen == 0)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   int          rejectionBias = 0;

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive || g_activeZones[i].isMitigated || g_activeZones[i].isExpired)
         continue;
      if(!g_activeZones[i].isBreached)
         continue;
      if(SMCZoneTypeToTimeframe(g_activeZones[i].type) != timeframe)
         continue;

      int zoneBias = 0;
      if(SMCZoneBarCloseRejectionBias(g_activeZones[i].topPrice, g_activeZones[i].bottomPrice,
                                      barClose, eps, zoneBias))
         rejectionBias = zoneBias;
   }

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(!g_mtfFvgInstances[f].inUse || g_mtfFvgInstances[f].isMitigated || g_mtfFvgInstances[f].isExpired)
         continue;
      if(!g_mtfFvgInstances[f].isBreached)
         continue;
      if(g_mtfFvgInstances[f].timeframe != timeframe)
         continue;

      int zoneBias = 0;
      if(SMCZoneBarCloseRejectionBias(g_mtfFvgInstances[f].topPrice, g_mtfFvgInstances[f].bottomPrice,
                                      barClose, eps, zoneBias))
         rejectionBias = zoneBias;
   }

   if(rejectionBias != 0)
      ProfessionalBiasSetDirection(timeframe, rejectionBias, barOpen);
}

//+------------------------------------------------------------------+
int GetProfessionalBias(const ENUM_TIMEFRAMES timeframe)
{
   int storedBias = 0;
   datetime storedBarOpen = 0;
   ProfessionalBiasGetOverrideState(timeframe, storedBias, storedBarOpen);
   if(storedBias != 0)
      return storedBias;

   MTFSwingTracker tracker;
   if(!SMCGetMtfSwingTracker(timeframe, tracker))
      return 0;

   return tracker.lastBosDirection;
}

void RebuildH4LiquidityPivotLevels()
{
   g_h4DescHighPivotCount = 0;
   g_h4AscLowPivotCount   = 0;

   if(InputH4LiquidityPivotLookbackBars < 2)
      return;

   const int barsTotal = iBars(_Symbol, PERIOD_H4);
   if(barsTotal < 3)
      return;

   const int maxShift =
      (int)MathMin((double)InputH4LiquidityPivotLookbackBars, (double)(barsTotal - 2));
   if(maxShift < 1)
      return;

   H4ReplayLeg replayLegs[H4_REPLAY_LEG_CAPACITY];
   int          replayLegCount = 0;
   SwingState   replaySwing;
   ZeroMemory(replaySwing);

   for(int shift = maxShift; shift >= 1; shift--)
      MtfSwingStepReplayAtShift(replaySwing, PERIOD_H4, shift, replayLegs, replayLegCount);

   if(replayLegCount <= 0)
      return;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);

   for(int legIndex = replayLegCount - 1; legIndex >= 0; legIndex--)
   {
      if(replayLegs[legIndex].swingDirection != 1)
         continue;

      bool isPivotHigh = true;
      for(int newerIndex = legIndex + 1; newerIndex < replayLegCount; newerIndex++)
      {
         if(replayLegs[newerIndex].swingDirection != 1)
            continue;
         if(replayLegs[newerIndex].legHighPrice >= replayLegs[legIndex].legHighPrice - eps)
         {
            isPivotHigh = false;
            break;
         }
      }

      if(!isPivotHigh || g_h4DescHighPivotCount >= H4_LIQUIDITY_PIVOT_CAPACITY)
         continue;

      Swing lastSwing;
      ZeroMemory(lastSwing);
      lastSwing.legHighPrice    = replayLegs[legIndex].legHighPrice;
      lastSwing.legLowPrice     = replayLegs[legIndex].legLowPrice;
      lastSwing.legStartTime    = replayLegs[legIndex].legStartTime;
      lastSwing.legEndTime      = replayLegs[legIndex].legEndTime;
      lastSwing.swingDirection  = replayLegs[legIndex].swingDirection;

      Swing prevSwing;
      ZeroMemory(prevSwing);
      const bool hasPrevLeg = (legIndex > 0);
      if(hasPrevLeg)
      {
         prevSwing.legHighPrice   = replayLegs[legIndex - 1].legHighPrice;
         prevSwing.legLowPrice    = replayLegs[legIndex - 1].legLowPrice;
         prevSwing.legStartTime   = replayLegs[legIndex - 1].legStartTime;
         prevSwing.legEndTime     = replayLegs[legIndex - 1].legEndTime;
         prevSwing.swingDirection = replayLegs[legIndex - 1].swingDirection;
      }

      double breachLevel = replayLegs[legIndex].legHighPrice;
      datetime volumeBarOpenTime = 0;
      ComputeH4LegVolumeBreachLevel(lastSwing, prevSwing, hasPrevLeg, breachLevel, volumeBarOpenTime);

      const int outIndex = g_h4DescHighPivotCount;
      g_h4DescHighPivots[outIndex].levelPrice     = breachLevel;
      g_h4DescHighPivots[outIndex].legEndTime      = replayLegs[legIndex].legEndTime;
      g_h4DescHighPivots[outIndex].legHighPrice    = replayLegs[legIndex].legHighPrice;
      g_h4DescHighPivots[outIndex].legLowPrice     = replayLegs[legIndex].legLowPrice;
      g_h4DescHighPivots[outIndex].swingDirection  = 1;
      g_h4DescHighPivotCount++;
   }

   for(int legIndex = replayLegCount - 1; legIndex >= 0; legIndex--)
   {
      if(replayLegs[legIndex].swingDirection != -1)
         continue;

      bool isPivotLow = true;
      for(int newerIndex = legIndex + 1; newerIndex < replayLegCount; newerIndex++)
      {
         if(replayLegs[newerIndex].swingDirection != -1)
            continue;
         if(replayLegs[newerIndex].legLowPrice <= replayLegs[legIndex].legLowPrice + eps)
         {
            isPivotLow = false;
            break;
         }
      }

      if(!isPivotLow || g_h4AscLowPivotCount >= H4_LIQUIDITY_PIVOT_CAPACITY)
         continue;

      Swing lastSwing;
      ZeroMemory(lastSwing);
      lastSwing.legHighPrice    = replayLegs[legIndex].legHighPrice;
      lastSwing.legLowPrice     = replayLegs[legIndex].legLowPrice;
      lastSwing.legStartTime    = replayLegs[legIndex].legStartTime;
      lastSwing.legEndTime      = replayLegs[legIndex].legEndTime;
      lastSwing.swingDirection  = replayLegs[legIndex].swingDirection;

      Swing prevSwing;
      ZeroMemory(prevSwing);
      const bool hasPrevLeg = (legIndex > 0);
      if(hasPrevLeg)
      {
         prevSwing.legHighPrice   = replayLegs[legIndex - 1].legHighPrice;
         prevSwing.legLowPrice    = replayLegs[legIndex - 1].legLowPrice;
         prevSwing.legStartTime   = replayLegs[legIndex - 1].legStartTime;
         prevSwing.legEndTime     = replayLegs[legIndex - 1].legEndTime;
         prevSwing.swingDirection = replayLegs[legIndex - 1].swingDirection;
      }

      double breachLevel = replayLegs[legIndex].legLowPrice;
      datetime volumeBarOpenTime = 0;
      ComputeH4LegVolumeBreachLevel(lastSwing, prevSwing, hasPrevLeg, breachLevel, volumeBarOpenTime);

      const int outIndex = g_h4AscLowPivotCount;
      g_h4AscLowPivots[outIndex].levelPrice     = breachLevel;
      g_h4AscLowPivots[outIndex].legEndTime      = replayLegs[legIndex].legEndTime;
      g_h4AscLowPivots[outIndex].legHighPrice    = replayLegs[legIndex].legHighPrice;
      g_h4AscLowPivots[outIndex].legLowPrice     = replayLegs[legIndex].legLowPrice;
      g_h4AscLowPivots[outIndex].swingDirection  = -1;
      g_h4AscLowPivotCount++;
   }
}

#endif // H4_LQ_V3_MTFSWINGBOS
