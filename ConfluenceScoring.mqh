//+------------------------------------------------------------------+
//| ConfluenceScoring.mqh                                            |
//| Optimization-ready weightings and total trade score logic        |
//| Include after g_activeZones + MTF swing trackers are declared    |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_SCORING_MQH
#define CONFLUENCE_SCORING_MQH

//+------------------------------------------------------------------+
bool SMCZoneTypeIsBullish(const ENUM_SMC_ZONE_TYPE type);

//+------------------------------------------------------------------+
int GetOptimizedZoneWeight(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_WEEKLY_FVG:
      case ZONE_BEAR_WEEKLY_FVG:
         return InputWeight_WeeklyFVG;
      case ZONE_BULL_DAILY_FVG:
      case ZONE_BEAR_DAILY_FVG:
         return InputWeight_DailyFVG;
      case ZONE_BULL_H4_FVG:
      case ZONE_BEAR_H4_FVG:
         return InputWeight_H4FVG;
      case ZONE_BULL_M15_FVG:
      case ZONE_BEAR_M15_FVG:
         return InputWeight_M15FVG;
      case ZONE_BULL_BROKEN_DAILY_HIGH:
      case ZONE_BULL_BROKEN_H4_HIGH:
      case ZONE_BULL_BROKEN_M15_HIGH:
      case ZONE_BEAR_BROKEN_DAILY_LOW:
      case ZONE_BEAR_BROKEN_H4_LOW:
      case ZONE_BEAR_BROKEN_M15_LOW:
         return InputWeight_Breaker;
      case ZONE_BULL_PROTECTED_DAILY_LOW:
      case ZONE_BULL_PROTECTED_H4_LOW:
      case ZONE_BULL_PROTECTED_M15_LOW:
      case ZONE_BEAR_PROTECTED_DAILY_HIGH:
      case ZONE_BEAR_PROTECTED_H4_HIGH:
      case ZONE_BEAR_PROTECTED_M15_HIGH:
         return InputWeight_Protected;
      case ZONE_BULL_SWING_W1_LOW:
      case ZONE_BULL_SWING_DAILY_LOW:
      case ZONE_BULL_SWING_H4_LOW:
      case ZONE_BULL_SWING_M15_LOW:
         return InputWeight_SwingSupport;
      case ZONE_BEAR_SWING_W1_HIGH:
      case ZONE_BEAR_SWING_DAILY_HIGH:
      case ZONE_BEAR_SWING_H4_HIGH:
      case ZONE_BEAR_SWING_M15_HIGH:
         return InputWeight_SwingResistance;
   }
   return 1;
}

//+------------------------------------------------------------------+
double SMCAlignmentContribution(const int bosDirection, const int bosWeight,
                                 const int tradeDir)
{
   if(bosDirection == 0)
      return 0.0;
   if(bosDirection == tradeDir)
      return (double)bosWeight;
   return -(double)bosWeight;
}

//+------------------------------------------------------------------+
double CalculateTotalTradeScore(const bool isBullishTrade)
{
   double locationScore = 0.0;

   for(int i = 0; i < SMC_ZONE_TYPE_COUNT; i++)
   {
      if(!g_activeZones[i].isActive)
         continue;
      if(g_activeZones[i].isMitigated)
         continue;
      if(g_activeZones[i].isExpired)
         continue;
      if(SMCZoneTypeIsBullish(g_activeZones[i].type) != isBullishTrade)
         continue;

      double weight = (double)GetOptimizedZoneWeight(g_activeZones[i].type);
      if(g_activeZones[i].isClustered)
         weight *= InputClusterMultiplier;
      locationScore += weight;
   }

   const int tradeDir = (isBullishTrade ? 1 : -1);
   double alignmentScore = 0.0;
   alignmentScore += SMCAlignmentContribution(g_mtfSwingW1.lastBosDirection,
                                              InputWeight_W1_BOS, tradeDir);
   alignmentScore += SMCAlignmentContribution(g_mtfSwingD1.lastBosDirection,
                                              InputWeight_D1_BOS, tradeDir);
   alignmentScore += SMCAlignmentContribution(g_mtfSwingH4.lastBosDirection,
                                              InputWeight_H4_BOS, tradeDir);
   alignmentScore += SMCAlignmentContribution(g_mtfSwingM15.lastBosDirection,
                                              InputWeight_M15_BOS, tradeDir);

   return locationScore + alignmentScore;
}

//+------------------------------------------------------------------+
double GetMaxPossibleScore()
{
   double zoneWeightSum = (double)InputWeight_WeeklyFVG + (double)InputWeight_DailyFVG
                        + (double)InputWeight_H4FVG + (double)InputWeight_M15FVG
                        + 3.0 * (double)InputWeight_Breaker + 3.0 * (double)InputWeight_Protected
                        + 4.0 * (double)InputWeight_SwingSupport
                        + 4.0 * (double)InputWeight_SwingResistance;

   if(InputClusterMultiplier > 0.0)
      zoneWeightSum *= InputClusterMultiplier;

   const double alignmentWeightSum = (double)InputWeight_W1_BOS + (double)InputWeight_D1_BOS
                                 + (double)InputWeight_H4_BOS + (double)InputWeight_M15_BOS;
   return zoneWeightSum + alignmentWeightSum;
}

#endif // CONFLUENCE_SCORING_MQH
