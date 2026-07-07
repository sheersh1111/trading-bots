//+------------------------------------------------------------------+
//| ConfluenceScoring.mqh                                            |
//| v1.5: CalculateReplayTradeScore for setup_zone_types.json verification |
//| v1.2: each optimizable zone weight counts at most once (1×) in    |
//|       CalculateTotalTradeScore and GetMaxPossibleScore             |
//| Include after g_activeZones + MTF swing trackers are declared    |
//+------------------------------------------------------------------+
#ifndef CONFLUENCE_SCORING_MQH
#define CONFLUENCE_SCORING_MQH

#define SMC_ZONE_WEIGHT_SLOT_COUNT 8

int GetProfessionalBias(const ENUM_TIMEFRAMES timeframe);

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
      case ZONE_BULL_PROTECTED_DAILY_LOW:
      case ZONE_BEAR_PROTECTED_DAILY_HIGH:
         return InputWeight_D1_HighLowZones;
      case ZONE_BULL_PROTECTED_H4_LOW:
      case ZONE_BEAR_PROTECTED_H4_HIGH:
         return InputWeight_H4_HighLowZones;
      case ZONE_BULL_PROTECTED_M15_LOW:
      case ZONE_BEAR_PROTECTED_M15_HIGH:
         return InputWeight_M15_HighLowZones;
      case ZONE_BULL_SWING_W1_LOW:
      case ZONE_BEAR_SWING_W1_HIGH:
         return InputWeight_W1_HighLowZones;
      case ZONE_BULL_SWING_DAILY_LOW:
      case ZONE_BEAR_SWING_DAILY_HIGH:
         return InputWeight_D1_HighLowZones;
      case ZONE_BULL_SWING_H4_LOW:
      case ZONE_BEAR_SWING_H4_HIGH:
         return InputWeight_H4_HighLowZones;
      case ZONE_BULL_SWING_M15_LOW:
      case ZONE_BEAR_SWING_M15_HIGH:
         return InputWeight_M15_HighLowZones;
   }
   return 1;
}

//+------------------------------------------------------------------+
//| Maps zone type → one of 8 optimizable weight inputs (0..7).      |
//+------------------------------------------------------------------+
int GetZoneWeightSlotIndex(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_WEEKLY_FVG:
      case ZONE_BEAR_WEEKLY_FVG:
         return 0;
      case ZONE_BULL_DAILY_FVG:
      case ZONE_BEAR_DAILY_FVG:
         return 1;
      case ZONE_BULL_H4_FVG:
      case ZONE_BEAR_H4_FVG:
         return 2;
      case ZONE_BULL_M15_FVG:
      case ZONE_BEAR_M15_FVG:
         return 3;
      case ZONE_BULL_SWING_W1_LOW:
      case ZONE_BEAR_SWING_W1_HIGH:
         return 4;
      case ZONE_BULL_PROTECTED_DAILY_LOW:
      case ZONE_BEAR_PROTECTED_DAILY_HIGH:
      case ZONE_BULL_SWING_DAILY_LOW:
      case ZONE_BEAR_SWING_DAILY_HIGH:
         return 5;
      case ZONE_BULL_PROTECTED_H4_LOW:
      case ZONE_BEAR_PROTECTED_H4_HIGH:
      case ZONE_BULL_SWING_H4_LOW:
      case ZONE_BEAR_SWING_H4_HIGH:
         return 6;
      case ZONE_BULL_PROTECTED_M15_LOW:
      case ZONE_BEAR_PROTECTED_M15_HIGH:
      case ZONE_BULL_SWING_M15_LOW:
      case ZONE_BEAR_SWING_M15_HIGH:
         return 7;
   }
   return -1;
}

//+------------------------------------------------------------------+
void TryAddLocationWeightOnce(const ENUM_SMC_ZONE_TYPE type, bool &usedWeightSlots[],
                               double &inOutLocationScore)
{
   const int slot = GetZoneWeightSlotIndex(type);
   if(slot < 0 || slot >= SMC_ZONE_WEIGHT_SLOT_COUNT)
      return;
   if(usedWeightSlots[slot])
      return;

   usedWeightSlots[slot] = true;
   inOutLocationScore += (double)GetOptimizedZoneWeight(type);
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
bool SMCSetupProbeInsideZone(const double probePrice, const double top, const double bottom)
{
   if(probePrice <= 0.0 || top <= bottom)
      return false;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double eps       = (pointSize > 0.0 ? pointSize : 0.00001);
   return (probePrice >= bottom - eps && probePrice <= top + eps);
}

//+------------------------------------------------------------------+
string SMCZoneTypeToLogName(const ENUM_SMC_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_BULL_WEEKLY_FVG:         return "ZONE_BULL_WEEKLY_FVG";
      case ZONE_BULL_DAILY_FVG:          return "ZONE_BULL_DAILY_FVG";
      case ZONE_BULL_H4_FVG:             return "ZONE_BULL_H4_FVG";
      case ZONE_BULL_M15_FVG:            return "ZONE_BULL_M15_FVG";
      case ZONE_BULL_PROTECTED_DAILY_LOW: return "ZONE_BULL_PROTECTED_DAILY_LOW";
      case ZONE_BULL_PROTECTED_H4_LOW:   return "ZONE_BULL_PROTECTED_H4_LOW";
      case ZONE_BULL_PROTECTED_M15_LOW:  return "ZONE_BULL_PROTECTED_M15_LOW";
      case ZONE_BULL_SWING_W1_LOW:       return "ZONE_BULL_SWING_W1_LOW";
      case ZONE_BULL_SWING_DAILY_LOW:    return "ZONE_BULL_SWING_DAILY_LOW";
      case ZONE_BULL_SWING_H4_LOW:       return "ZONE_BULL_SWING_H4_LOW";
      case ZONE_BULL_SWING_M15_LOW:      return "ZONE_BULL_SWING_M15_LOW";
      case ZONE_BEAR_WEEKLY_FVG:         return "ZONE_BEAR_WEEKLY_FVG";
      case ZONE_BEAR_DAILY_FVG:          return "ZONE_BEAR_DAILY_FVG";
      case ZONE_BEAR_H4_FVG:             return "ZONE_BEAR_H4_FVG";
      case ZONE_BEAR_M15_FVG:            return "ZONE_BEAR_M15_FVG";
      case ZONE_BEAR_PROTECTED_DAILY_HIGH: return "ZONE_BEAR_PROTECTED_DAILY_HIGH";
      case ZONE_BEAR_PROTECTED_H4_HIGH:  return "ZONE_BEAR_PROTECTED_H4_HIGH";
      case ZONE_BEAR_PROTECTED_M15_HIGH: return "ZONE_BEAR_PROTECTED_M15_HIGH";
      case ZONE_BEAR_SWING_W1_HIGH:      return "ZONE_BEAR_SWING_W1_HIGH";
      case ZONE_BEAR_SWING_DAILY_HIGH:   return "ZONE_BEAR_SWING_DAILY_HIGH";
      case ZONE_BEAR_SWING_H4_HIGH:      return "ZONE_BEAR_SWING_H4_HIGH";
      case ZONE_BEAR_SWING_M15_HIGH:     return "ZONE_BEAR_SWING_M15_HIGH";
   }
   return "ZONE_UNKNOWN";
}

//+------------------------------------------------------------------+
bool SMCZoneTypeFromLogName(const string name, ENUM_SMC_ZONE_TYPE &outType)
{
   if(name == "ZONE_BULL_WEEKLY_FVG")         { outType = ZONE_BULL_WEEKLY_FVG; return true; }
   if(name == "ZONE_BULL_DAILY_FVG")          { outType = ZONE_BULL_DAILY_FVG; return true; }
   if(name == "ZONE_BULL_H4_FVG")             { outType = ZONE_BULL_H4_FVG; return true; }
   if(name == "ZONE_BULL_M15_FVG")            { outType = ZONE_BULL_M15_FVG; return true; }
   if(name == "ZONE_BULL_PROTECTED_DAILY_LOW") { outType = ZONE_BULL_PROTECTED_DAILY_LOW; return true; }
   if(name == "ZONE_BULL_PROTECTED_H4_LOW")   { outType = ZONE_BULL_PROTECTED_H4_LOW; return true; }
   if(name == "ZONE_BULL_PROTECTED_M15_LOW")  { outType = ZONE_BULL_PROTECTED_M15_LOW; return true; }
   if(name == "ZONE_BULL_SWING_W1_LOW")       { outType = ZONE_BULL_SWING_W1_LOW; return true; }
   if(name == "ZONE_BULL_SWING_DAILY_LOW")    { outType = ZONE_BULL_SWING_DAILY_LOW; return true; }
   if(name == "ZONE_BULL_SWING_H4_LOW")       { outType = ZONE_BULL_SWING_H4_LOW; return true; }
   if(name == "ZONE_BULL_SWING_M15_LOW")      { outType = ZONE_BULL_SWING_M15_LOW; return true; }
   if(name == "ZONE_BEAR_WEEKLY_FVG")         { outType = ZONE_BEAR_WEEKLY_FVG; return true; }
   if(name == "ZONE_BEAR_DAILY_FVG")          { outType = ZONE_BEAR_DAILY_FVG; return true; }
   if(name == "ZONE_BEAR_H4_FVG")             { outType = ZONE_BEAR_H4_FVG; return true; }
   if(name == "ZONE_BEAR_M15_FVG")            { outType = ZONE_BEAR_M15_FVG; return true; }
   if(name == "ZONE_BEAR_PROTECTED_DAILY_HIGH") { outType = ZONE_BEAR_PROTECTED_DAILY_HIGH; return true; }
   if(name == "ZONE_BEAR_PROTECTED_H4_HIGH")  { outType = ZONE_BEAR_PROTECTED_H4_HIGH; return true; }
   if(name == "ZONE_BEAR_PROTECTED_M15_HIGH") { outType = ZONE_BEAR_PROTECTED_M15_HIGH; return true; }
   if(name == "ZONE_BEAR_SWING_W1_HIGH")      { outType = ZONE_BEAR_SWING_W1_HIGH; return true; }
   if(name == "ZONE_BEAR_SWING_DAILY_HIGH")   { outType = ZONE_BEAR_SWING_DAILY_HIGH; return true; }
   if(name == "ZONE_BEAR_SWING_H4_HIGH")      { outType = ZONE_BEAR_SWING_H4_HIGH; return true; }
   if(name == "ZONE_BEAR_SWING_M15_HIGH")     { outType = ZONE_BEAR_SWING_M15_HIGH; return true; }
   return false;
}

//+------------------------------------------------------------------+
double CalculateReplayTradeScore(const bool isBullishTrade,
                                  const ENUM_SMC_ZONE_TYPE &zoneTypes[],
                                  const int biasW1,
                                  const int biasD1,
                                  const int biasH4,
                                  const int biasM15)
{
   double locationScore = 0.0;
   bool   usedWeightSlots[SMC_ZONE_WEIGHT_SLOT_COUNT];
   ArrayInitialize(usedWeightSlots, false);

   const int typeCount = ArraySize(zoneTypes);
   for(int i = 0; i < typeCount; i++)
      TryAddLocationWeightOnce(zoneTypes[i], usedWeightSlots, locationScore);

   const int tradeDir = (isBullishTrade ? 1 : -1);
   double alignmentScore = 0.0;
   alignmentScore += SMCAlignmentContribution(biasW1, InputWeight_W1_BOS, tradeDir);
   alignmentScore += SMCAlignmentContribution(biasD1, InputWeight_D1_BOS, tradeDir);
   alignmentScore += SMCAlignmentContribution(biasH4, InputWeight_H4_BOS, tradeDir);
   alignmentScore += SMCAlignmentContribution(biasM15, InputWeight_M15_BOS, tradeDir);

   return locationScore + alignmentScore;
}

//+------------------------------------------------------------------+
void AppendUniqueSetupZoneType(const ENUM_SMC_ZONE_TYPE type, ENUM_SMC_ZONE_TYPE &outTypes[])
{
   const int count = ArraySize(outTypes);
   for(int i = 0; i < count; i++)
   {
      if(outTypes[i] == type)
         return;
   }

   ArrayResize(outTypes, count + 1);
   outTypes[count] = type;
}

//+------------------------------------------------------------------+
// Same location filters as CalculateTotalTradeScore; unique zone types only.
int CollectMatchingSetupZoneTypes(const bool isBullishTrade,
                                   const double setupLow,
                                   const double setupHigh,
                                   ENUM_SMC_ZONE_TYPE &outTypes[])
{
   ArrayResize(outTypes, 0);

   const double probePrice = (isBullishTrade ? setupLow : setupHigh);
   if(probePrice <= 0.0)
      return 0;

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
         continue;
      if(g_activeZones[i].isMitigated)
         continue;
      if(g_activeZones[i].isExpired)
         continue;
      if(SMCZoneTypeIsBullish(g_activeZones[i].type) != isBullishTrade)
         continue;
      if(!SMCSetupProbeInsideZone(probePrice,
                                 g_activeZones[i].topPrice,
                                 g_activeZones[i].bottomPrice))
         continue;

      AppendUniqueSetupZoneType(g_activeZones[i].type, outTypes);
   }

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(!g_mtfFvgInstances[f].inUse)
         continue;
      if(g_mtfFvgInstances[f].isMitigated)
         continue;
      if(g_mtfFvgInstances[f].isExpired)
         continue;
      if(SMCZoneTypeIsBullish(g_mtfFvgInstances[f].type) != isBullishTrade)
         continue;
      if(!SMCSetupProbeInsideZone(probePrice,
                                 g_mtfFvgInstances[f].topPrice,
                                 g_mtfFvgInstances[f].bottomPrice))
         continue;

      AppendUniqueSetupZoneType(g_mtfFvgInstances[f].type, outTypes);
   }

   return ArraySize(outTypes);
}

//+------------------------------------------------------------------+
// Bull: setupLow must be inside zone. Bear: setupHigh must be inside zone.
// Each optimizable zone weight input contributes at most once (1×).
double CalculateTotalTradeScore(const bool isBullishTrade,
                                 const double setupLow,
                                 const double setupHigh)
{
   const double probePrice = (isBullishTrade ? setupLow : setupHigh);
   const bool hasValidProbe = (probePrice > 0.0);

   double locationScore = 0.0;
   bool   usedWeightSlots[SMC_ZONE_WEIGHT_SLOT_COUNT];
   ArrayInitialize(usedWeightSlots, false);

   for(int i = 0; i < SMC_ZONE_LEDGER_CAPACITY; i++)
   {
      if(!g_activeZones[i].isActive)
         continue;
      if(g_activeZones[i].isMitigated)
         continue;
      if(g_activeZones[i].isExpired)
         continue;
      if(SMCZoneTypeIsBullish(g_activeZones[i].type) != isBullishTrade)
         continue;
      if(!hasValidProbe)
         continue;
      if(!SMCSetupProbeInsideZone(probePrice,
                                 g_activeZones[i].topPrice,
                                 g_activeZones[i].bottomPrice))
         continue;

      TryAddLocationWeightOnce(g_activeZones[i].type, usedWeightSlots, locationScore);
   }

   for(int f = 0; f < SMC_MTF_FVG_INSTANCE_CAPACITY; f++)
   {
      if(!g_mtfFvgInstances[f].inUse)
         continue;
      if(g_mtfFvgInstances[f].isMitigated)
         continue;
      if(g_mtfFvgInstances[f].isExpired)
         continue;
      if(SMCZoneTypeIsBullish(g_mtfFvgInstances[f].type) != isBullishTrade)
         continue;
      if(!hasValidProbe)
         continue;
      if(!SMCSetupProbeInsideZone(probePrice,
                                 g_mtfFvgInstances[f].topPrice,
                                 g_mtfFvgInstances[f].bottomPrice))
         continue;

      TryAddLocationWeightOnce(g_mtfFvgInstances[f].type, usedWeightSlots, locationScore);
   }

   const int tradeDir = (isBullishTrade ? 1 : -1);
   double alignmentScore = 0.0;
   alignmentScore += SMCAlignmentContribution(GetProfessionalBias(PERIOD_W1),
                                              InputWeight_W1_BOS, tradeDir);
   alignmentScore += SMCAlignmentContribution(GetProfessionalBias(PERIOD_D1),
                                              InputWeight_D1_BOS, tradeDir);
   alignmentScore += SMCAlignmentContribution(GetProfessionalBias(PERIOD_H4),
                                              InputWeight_H4_BOS, tradeDir);
   alignmentScore += SMCAlignmentContribution(GetProfessionalBias(PERIOD_M15),
                                              InputWeight_M15_BOS, tradeDir);

   return locationScore + alignmentScore;
}

//+------------------------------------------------------------------+
//| Theoretical max: each of 8 zone weight inputs at most once (1×).  |
//+------------------------------------------------------------------+
double GetMaxPossibleScore()
{
   const double zoneWeightSum = (double)InputWeight_WeeklyFVG + (double)InputWeight_DailyFVG
                              + (double)InputWeight_H4FVG + (double)InputWeight_M15FVG
                              + (double)InputWeight_W1_HighLowZones
                              + (double)InputWeight_D1_HighLowZones
                              + (double)InputWeight_H4_HighLowZones
                              + (double)InputWeight_M15_HighLowZones;

   const double alignmentWeightSum = (double)InputWeight_W1_BOS + (double)InputWeight_D1_BOS
                                 + (double)InputWeight_H4_BOS + (double)InputWeight_M15_BOS;
   return zoneWeightSum + alignmentWeightSum;
}

#endif // CONFLUENCE_SCORING_MQH
