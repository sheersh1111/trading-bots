//+------------------------------------------------------------------+
//| TradeTakeProfit.mqh
//| Swing TP build
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_TRADETAKEPROFIT
#define H4_LQ_V3_TRADETAKEPROFIT

void SortM2SwingExtremesNewestFirst(M2SwingExtremePoint &points[], const int pointCount)
{
   for(int i = 0; i < pointCount - 1; i++)
   {
      for(int j = i + 1; j < pointCount; j++)
      {
         if(points[j].legEndTime > points[i].legEndTime)
         {
            const M2SwingExtremePoint tmp = points[i];
            points[i] = points[j];
            points[j] = tmp;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool M2SwingExtremePointExists(const M2SwingExtremePoint &points[], const int pointCount,
                               const datetime legEndTime)
{
   for(int i = 0; i < pointCount; i++)
   {
      if(points[i].legEndTime == legEndTime)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void AppendM2SwingExtremePoint(M2SwingExtremePoint &points[], int &pointCount,
                               const double extremePrice, const datetime legStartTime,
                               const datetime legEndTime)
{
   if(legEndTime == 0 || M2SwingExtremePointExists(points, pointCount, legEndTime))
      return;

   const int newIdx = pointCount;
   ArrayResize(points, pointCount + 1);
   points[newIdx].extremePrice = extremePrice;
   points[newIdx].legStartTime = legStartTime;
   points[newIdx].legEndTime   = legEndTime;
   pointCount++;
}

//+------------------------------------------------------------------+
void TryAppendM2SwingExtremeFromClosedLeg(const Swing &closedLeg, const int legDirection,
                                           const int windowNewestShift, const int windowOldestShift,
                                           M2SwingExtremePoint &outPoints[], int &outPointCount)
{
   if(closedLeg.swingDirection != legDirection || closedLeg.legEndTime == 0)
      return;

   int legEndShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, closedLeg.legEndTime, true);
   if(legEndShift < 0)
      legEndShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, closedLeg.legEndTime, false);
   if(legEndShift < 0 || legEndShift < windowNewestShift || legEndShift > windowOldestShift)
      return;

   const double extremePrice = (legDirection == 1) ? closedLeg.legHighPrice : closedLeg.legLowPrice;
   AppendM2SwingExtremePoint(outPoints, outPointCount, extremePrice,
                             closedLeg.legStartTime, closedLeg.legEndTime);
}

//+------------------------------------------------------------------+
void CollectM2SwingExtremesFromSwingHistory(const SwingState &swingState, const int formationShift,
                                             const int lookbackBars, const int legDirection,
                                             M2SwingExtremePoint &outPoints[], int &outPointCount)
{
   const int windowNewestShift = MathMax(formationShift, 1);
   const int windowOldestShift = formationShift + lookbackBars;

   for(int historyIndex = 0; historyIndex < swingState.swingHistoryCount; historyIndex++)
   {
      TryAppendM2SwingExtremeFromClosedLeg(swingState.swingHistory[historyIndex], legDirection,
                                           windowNewestShift, windowOldestShift,
                                           outPoints, outPointCount);
   }
}

//+------------------------------------------------------------------+
//| Same M2 swing legs already drawn on chart (PFX_M2_TREND) â€” optional supplement when draw is on. |
//+------------------------------------------------------------------+
void CollectM2SwingExtremesFromDrawnTrendLines(const int formationShift, const int lookbackBars,
                                               const int legDirection,
                                               M2SwingExtremePoint &outPoints[], int &outPointCount)
{
   const int windowNewestShift = MathMax(formationShift, 1);
   const int windowOldestShift = formationShift + lookbackBars;

   const int objectTotal = ObjectsTotal(0, 0, OBJ_TREND);
   for(int objIndex = objectTotal - 1; objIndex >= 0; objIndex--)
   {
      const string objName = ObjectName(0, objIndex, 0, OBJ_TREND);
      if(StringFind(objName, PFX_M2_TREND) != 0)
         continue;
      if(StringFind(objName, "LIVE") >= 0)
         continue;

      const datetime legEndTime   = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 1);
      const datetime legStartTime = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
      const int      legEndShift  = iBarShift(_Symbol, InputM2NarrativeTimeframe, legEndTime, true);
      if(legEndShift < 0 || legEndShift < windowNewestShift || legEndShift > windowOldestShift)
         continue;

      const double priceStart = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
      const double priceEnd   = ObjectGetDouble(0, objName, OBJPROP_PRICE, 1);

      if(legDirection == 1)
      {
         if(priceEnd <= priceStart)
            continue;
         AppendM2SwingExtremePoint(outPoints, outPointCount, priceEnd, legStartTime, legEndTime);
      }
      else
      {
         if(priceEnd >= priceStart)
            continue;
         AppendM2SwingExtremePoint(outPoints, outPointCount, priceEnd, legStartTime, legEndTime);
      }
   }
}

//+------------------------------------------------------------------+
//| From FVG/order formation bar: replay M2 swings backward up to lookbackBars; |
//| collect completed up-leg highs (bull) or down-leg lows (bear), newest first. |
//+------------------------------------------------------------------+
bool CollectM2SwingExtremesBackwardFromFormation(const datetime formationTime, const int lookbackBars,
                                                  const int legDirection,
                                                  M2SwingExtremePoint &outPoints[], int &outPointCount)
{
   outPointCount = 0;
   ArrayResize(outPoints, 0);
   if(formationTime == 0 || lookbackBars < 1 || (legDirection != 1 && legDirection != -1))
      return false;

   int formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, true);
   if(formationShift < 0)
      formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, false);
   if(formationShift < 0)
      return false;

   const int barsTotal = iBars(_Symbol, InputM2NarrativeTimeframe);
   if(barsTotal < 4)
      return false;

   const int windowNewestShift = MathMax(formationShift, 1);
   const int windowOldestShift = formationShift + lookbackBars;
   const int startReplayShift  = (int)MathMin((double)windowOldestShift, (double)(barsTotal - 2));
   const int endReplayShift    = windowNewestShift;
   if(startReplayShift < endReplayShift)
      return false;

   const int swingWarmupBars = MathMax(120, lookbackBars);
   const int replayFromShift = (int)MathMin((double)(startReplayShift + swingWarmupBars),
                                            (double)(barsTotal - 2));

   SwingState replayState;
   ZeroMemory(replayState);

   for(int barShift = replayFromShift; barShift >= endReplayShift; barShift--)
   {
      const int newestIdxBefore = replayState.swingHistoryCount - 1;
      const datetime newestEndBefore = (newestIdxBefore >= 0)
                                       ? replayState.swingHistory[newestIdxBefore].legEndTime
                                       : 0;

      ProcessSwingStepAtShift(replayState, InputM2NarrativeTimeframe, barShift,
                              InputM2SwingLineColor, "", "", true);

      if(barShift > startReplayShift)
         continue;

      const int newestIdxAfter = replayState.swingHistoryCount - 1;
      if(newestIdxAfter < 0)
         continue;

      const datetime newestEndAfter = replayState.swingHistory[newestIdxAfter].legEndTime;
      if(newestEndAfter == 0 || newestEndAfter == newestEndBefore)
         continue;

      TryAppendM2SwingExtremeFromClosedLeg(replayState.swingHistory[newestIdxAfter], legDirection,
                                           windowNewestShift, windowOldestShift,
                                           outPoints, outPointCount);
   }

   CollectM2SwingExtremesFromSwingHistory(g_m2Swing, formationShift, lookbackBars, legDirection,
                                        outPoints, outPointCount);

   if(H4LqChartDrawEnabled(InputDrawM2SwingLegs))
   {
      CollectM2SwingExtremesFromDrawnTrendLines(formationShift, lookbackBars, legDirection,
                                                outPoints, outPointCount);
   }

   if(outPointCount < 1)
      return false;

   SortM2SwingExtremesNewestFirst(outPoints, outPointCount);
   return true;
}

//+------------------------------------------------------------------+
bool SwingGroupLineMeetsMinRiskReward(const bool isBuy, const double entryPrice,
                                      const double stopLossPrice, const double tpLinePrice,
                                      const double minRewardToRisk)
{
   if(minRewardToRisk <= 0.0 || entryPrice <= 0.0 || stopLossPrice <= 0.0 || tpLinePrice <= 0.0)
      return false;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double risk      = MathAbs(entryPrice - stopLossPrice);
   if(risk <= pointSize)
      return false;

   const double reward = isBuy ? (tpLinePrice - entryPrice) : (entryPrice - tpLinePrice);
   if(reward <= pointSize)
      return false;

   return (reward / risk >= minRewardToRisk);
}

//+------------------------------------------------------------------+
void AppendUniqueTakeProfitLevel(double &tpPrices[], int &tpCount, const double tpPrice)
{
   const double normalized = NormalizeDouble(tpPrice, _Digits);
   for(int i = 0; i < tpCount; i++)
   {
      if(MathAbs(tpPrices[i] - normalized) <= SymbolInfoDouble(_Symbol, SYMBOL_POINT))
         return;
   }

   ArrayResize(tpPrices, tpCount + 1);
   tpPrices[tpCount] = normalized;
   tpCount++;
}

//+------------------------------------------------------------------+
void SortTakeProfitLevelsNearestFirst(const bool isBuy, double &tpPrices[], const int tpCount)
{
   for(int i = 0; i < tpCount - 1; i++)
   {
      for(int j = i + 1; j < tpCount; j++)
      {
         const bool swap =
            isBuy ? (tpPrices[j] < tpPrices[i]) : (tpPrices[j] > tpPrices[i]);
         if(swap)
         {
            const double tmp = tpPrices[i];
            tpPrices[i] = tpPrices[j];
            tpPrices[j] = tmp;
         }
      }
   }
}

//+------------------------------------------------------------------+
void TrimTakeProfitLevelsToTargetCount(double &tpPrices[], int &tpCount, const int targetCount)
{
   if(targetCount < 1 || tpCount <= targetCount)
      return;

   ArrayResize(tpPrices, targetCount);
   tpCount = targetCount;
}

//+------------------------------------------------------------------+
bool TakeProfitLevelWithinProximityBand(const double tpLinePrice,
                                        const double &existingTpPrices[],
                                        const int existingTpCount,
                                        const double proximityBand)
{
   if(proximityBand <= 0.0 || existingTpCount < 1)
      return false;

   for(int i = 0; i < existingTpCount; i++)
   {
      if(MathAbs(existingTpPrices[i] - tpLinePrice) <= proximityBand)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int AppendNearestIndividualSwingTakeProfitLevels(const bool isBuy, const double entryPrice,
                                                  const double stopLossPrice,
                                                  const M2SwingExtremePoint &points[],
                                                  const int pointCount,
                                                  const double frontRunOffset,
                                                  const double proximityBand,
                                                  double &outTakeProfitPrices[],
                                                  int &outTakeProfitCount,
                                                  const int maxLevelsToAppend,
                                                  int &outSkippedRewardToRisk,
                                                  int &outSkippedProximity)
{
   outSkippedRewardToRisk = 0;
   outSkippedProximity    = 0;
   if(maxLevelsToAppend <= 0)
      return 0;

   double candidates[];
   int    candidateCount = 0;

   for(int i = 0; i < pointCount; i++)
   {
      double linePrice = points[i].extremePrice;
      if(frontRunOffset > 0.0)
      {
         if(isBuy)
            linePrice -= frontRunOffset;
         else
            linePrice += frontRunOffset;
      }

      if(TakeProfitLevelWithinProximityBand(linePrice, outTakeProfitPrices, outTakeProfitCount,
                                            proximityBand))
      {
         outSkippedProximity++;
         continue;
      }

      if(TakeProfitLevelWithinProximityBand(linePrice, candidates, candidateCount, proximityBand))
      {
         outSkippedProximity++;
         continue;
      }

      if(!SwingGroupLineMeetsMinRiskReward(isBuy, entryPrice, stopLossPrice, linePrice,
                                           InputTradeSwingTpMinRewardToRisk))
      {
         outSkippedRewardToRisk++;
         continue;
      }

      AppendUniqueTakeProfitLevel(candidates, candidateCount, linePrice);
   }

   if(candidateCount < 1)
      return 0;

   SortTakeProfitLevelsNearestFirst(isBuy, candidates, candidateCount);

   const int takeCount = MathMin(maxLevelsToAppend, candidateCount);
   int added = 0;
   for(int i = 0; i < takeCount; i++)
   {
      const int beforeCount = outTakeProfitCount;
      AppendUniqueTakeProfitLevel(outTakeProfitPrices, outTakeProfitCount, candidates[i]);
      if(outTakeProfitCount > beforeCount)
         added++;
   }

   return added;
}

//+------------------------------------------------------------------+
//| Group swing extremes → qualifying line TPs (min R:R) + optional chart zones. |
//| Solo fallback fills only remaining slots (target − cluster); nearest solos picked. |
//| Cluster + solo merged, sorted nearest-first, trimmed to InputTradeSwingTpCount.   |
//+------------------------------------------------------------------+
bool BuildTradeSwingGroupTakeProfits(const bool isBullishTrade, const datetime formationTime,
                                     const double entryPrice, const double stopLossPrice,
                                     double &outTakeProfitPrices[], int &outTakeProfitCount)
{
   outTakeProfitCount = 0;
   ArrayResize(outTakeProfitPrices, 0);

   if(ScoreLogWriteModeSkipsTrading())
      return false;

   if(InputTradeSwingProximityPercentOfChartRange <= 0.0 || formationTime == 0)
      return false;

   const int legDirection = isBullishTrade ? 1 : -1;
   M2SwingExtremePoint points[];
   int                 pointCount = 0;
   if(!CollectM2SwingExtremesBackwardFromFormation(formationTime, InputTradeSwingLookbackM2Bars,
                                                    legDirection, points, pointCount))
      return false;

   int formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, true);
   if(formationShift < 0)
      formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, formationTime, false);
   if(formationShift < 0)
      formationShift = 1;

   const double chartHeight =
      ReferenceChartHeightForM2BarCountFromShift(formationShift, InputTradeSwingLookbackM2Bars);
   if(chartHeight <= 0.0)
      return false;

   const double proximityBand =
      chartHeight * (InputTradeSwingProximityPercentOfChartRange / 100.0);
   const double frontRunOffset =
      (InputTradeSwingTpFrontRunPercentOfChartRange > 0.0)
      ? chartHeight * (InputTradeSwingTpFrontRunPercentOfChartRange / 100.0)
      : 0.0;

   bool used[];
   ArrayResize(used, pointCount);
   ArrayInitialize(used, false);

   datetime timeRight = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
   if(timeRight == 0)
      timeRight = TimeCurrent();
   const int m2PeriodSec = (int)PeriodSeconds(InputM2NarrativeTimeframe);
   if(m2PeriodSec > 0)
      timeRight += (datetime)m2PeriodSec;

   const string formationTag = IntegerToString((long)formationTime);
   const color  rectColor    = isBullishTrade ? InputTradeSwingProximityRectColorBull
                                              : InputTradeSwingProximityRectColorBear;
   const color  lineColor    = isBullishTrade ? InputTradeSwingProximityLineColorBull
                                              : InputTradeSwingProximityLineColorBear;
   const bool   isBuy        = isBullishTrade;

   int groupSeq      = 0;
   int groupsSkipped = 0;

   for(int i = 0; i < pointCount; i++)
   {
      if(used[i])
         continue;

      int members[];
      ArrayResize(members, 1);
      members[0] = i;

      for(int j = 0; j < pointCount; j++)
      {
         if(j == i || used[j])
            continue;
         if(MathAbs(points[j].extremePrice - points[i].extremePrice) <= proximityBand)
         {
            const int memberSize = ArraySize(members);
            ArrayResize(members, memberSize + 1);
            members[memberSize] = j;
         }
      }

      if(ArraySize(members) < 2)
         continue;

      datetime mostRecentTime = 0;
      datetime earliestEnd    = timeRight;
      double   linePrice      = 0.0;
      double   groupExtreme   = isBullishTrade ? -1.0e100 : 1.0e100;

      for(int m = 0; m < ArraySize(members); m++)
      {
         const int idx = members[m];
         used[idx]     = true;

         if(points[idx].legEndTime >= mostRecentTime)
         {
            mostRecentTime = points[idx].legEndTime;
            linePrice      = points[idx].extremePrice;
         }
         if(points[idx].legEndTime < earliestEnd)
            earliestEnd = points[idx].legEndTime;

         if(isBullishTrade)
            groupExtreme = MathMax(groupExtreme, points[idx].extremePrice);
         else
            groupExtreme = MathMin(groupExtreme, points[idx].extremePrice);
      }
      if(mostRecentTime <= 0)
         continue;

      if(frontRunOffset > 0.0)
      {
         if(isBuy)
            linePrice -= frontRunOffset;
         else
            linePrice += frontRunOffset;
      }

      if(!SwingGroupLineMeetsMinRiskReward(isBuy, entryPrice, stopLossPrice, linePrice,
                                           InputTradeSwingTpMinRewardToRisk))
      {
         groupsSkipped++;
         continue;
      }

      AppendUniqueTakeProfitLevel(outTakeProfitPrices, outTakeProfitCount, linePrice);

      if(!H4LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
      {
         groupSeq++;
         continue;
      }

      double zoneLow  = 0.0;
      double zoneHigh = 0.0;
      if(isBullishTrade)
      {
         zoneHigh = groupExtreme;
         zoneLow  = groupExtreme - proximityBand;
      }
      else
      {
         zoneLow  = groupExtreme;
         zoneHigh = groupExtreme + proximityBand;
      }

      const string rectName = LQ_OBJ_TRADE_SWGRP_RECT_PREFIX + formationTag + "_" + IntegerToString(groupSeq);
      if(ObjectFind(0, rectName) < 0)
      {
         if(!ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, earliestEnd, zoneHigh, timeRight, zoneLow))
         {
            groupSeq++;
            continue;
         }
      }
      else
      {
         ObjectSetInteger(0, rectName, OBJPROP_TIME, 0, earliestEnd);
         ObjectSetDouble(0, rectName, OBJPROP_PRICE, 0, zoneHigh);
         ObjectSetInteger(0, rectName, OBJPROP_TIME, 1, timeRight);
         ObjectSetDouble(0, rectName, OBJPROP_PRICE, 1, zoneLow);
      }
      ObjectSetInteger(0, rectName, OBJPROP_COLOR, rectColor);
      ObjectSetInteger(0, rectName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, rectName, OBJPROP_FILL, false);
      ObjectSetInteger(0, rectName, OBJPROP_BACK, false);
      ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, rectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

      const string lineName = LQ_OBJ_TRADE_SWGRP_LINE_PREFIX + formationTag + "_" + IntegerToString(groupSeq);
      if(ObjectFind(0, lineName) >= 0)
         ObjectDelete(0, lineName);
      if(ObjectCreate(0, lineName, OBJ_TREND, 0, mostRecentTime, linePrice, timeRight, linePrice))
      {
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, lineName, OBJPROP_BACK, false);
         ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, false);
         ObjectSetInteger(0, lineName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      }

      groupSeq++;
   }

   int soloAdded          = 0;
   int soloSkippedRR      = 0;
   int soloSkippedProx    = 0;
   const int clusterTpCount = outTakeProfitCount;
   const int targetTpCount = TradeSwingTpTargetCount();
   const int remainingTpSlots = targetTpCount - clusterTpCount;

   if(remainingTpSlots > 0)
   {
      soloAdded = AppendNearestIndividualSwingTakeProfitLevels(isBuy, entryPrice, stopLossPrice,
                                                                points, pointCount, frontRunOffset,
                                                                proximityBand,
                                                                outTakeProfitPrices,
                                                                outTakeProfitCount,
                                                                remainingTpSlots,
                                                                soloSkippedRR, soloSkippedProx);
   }

   if(outTakeProfitCount < 1)
   {
      LogHuntEvent("TRADE_SWGRP_SKIP",
                   StringFormat("%s no TP lines met min R:R %.2f clusterSkipped=%d soloSkippedRR=%d soloSkippedProx=%d",
                                isBullishTrade ? "bull" : "bear",
                                InputTradeSwingTpMinRewardToRisk, groupsSkipped,
                                soloSkippedRR, soloSkippedProx));
      return false;
   }

   SortTakeProfitLevelsNearestFirst(isBuy, outTakeProfitPrices, outTakeProfitCount);
   TrimTakeProfitLevelsToTargetCount(outTakeProfitPrices, outTakeProfitCount, targetTpCount);

   if(soloAdded > 0)
   {
      LogHuntEvent("TRADE_SWGRP_SOLO",
                   StringFormat("%s soloTps=%d clusterTps=%d soloSkippedRR=%d soloSkippedProx=%d",
                                isBullishTrade ? "bull" : "bear", soloAdded,
                                clusterTpCount, soloSkippedRR, soloSkippedProx));
   }

   LogHuntEvent("TRADE_SWGRP_TP",
                StringFormat("%s tps=%d clusterDrawn=%d clusterSkippedRR=%d soloAdded=%d nearest=%.5f farthest=%.5f",
                             isBullishTrade ? "bull" : "bear", outTakeProfitCount, groupSeq,
                             groupsSkipped, soloAdded, outTakeProfitPrices[0],
                             outTakeProfitPrices[outTakeProfitCount - 1]));

   if(H4LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
      ChartRedraw(0);

   return true;
}

//+------------------------------------------------------------------+

#endif // H4_LQ_V3_TRADETAKEPROFIT
