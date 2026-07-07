//+------------------------------------------------------------------+
//| H4LqV3Runtime.mqh
//| Runtime flags, logging, chart-height refs
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_H4LQV3RUNTIME
#define H4_LQ_V3_H4LQV3RUNTIME

//+------------------------------------------------------------------+
bool H4LqLoggingEnabled()
{
   return (!InputFastTesterMode && InputLogHuntEvents);
}

//+------------------------------------------------------------------+
bool H4LqChartDrawEnabled(const bool featureFlag = true)
{
   return (!InputFastTesterMode && featureFlag);
}

//+------------------------------------------------------------------+
bool ScoreLogWriteModeSkipsTrading()
{
   return false;
}

//+------------------------------------------------------------------+
int TradeSwingTpTargetCount()
{
   return (InputTradeSwingTpCount == TRADE_SWING_TP_TWO) ? 2 : 3;
}

//+------------------------------------------------------------------+
void GetTradeSwingTpRiskWeights(const int actualTpCount, double &outWeights[], double &outTotalParts)
{
   const int tpCount = MathMax(1, MathMin(actualTpCount, TradeSwingTpTargetCount()));
   ArrayResize(outWeights, tpCount);

   if(tpCount == 1)
   {
      outWeights[0] = 1.0;
      outTotalParts = 1.0;
   }
   else if(tpCount == 2)
   {
      outWeights[0] = 2.0;
      outWeights[1] = 1.0;
      outTotalParts = 3.0;
   }
   else
   {
      outWeights[0] = 3.0;
      outWeights[1] = 1.0;
      outWeights[2] = 1.0;
      outTotalParts = 5.0;
   }
}
double ReferenceChartHeightForTimeframeBarCount(const ENUM_TIMEFRAMES timeframe,
                                                 const int barCount)
{
   if(barCount < 1 || timeframe == PERIOD_CURRENT)
      return 0.0;

   const int totalBars = iBars(_Symbol, timeframe);
   if(totalBars < 4)
      return 0.0;

   const int useBarCount = (int)MathMin((double)barCount, (double)(totalBars - 1));
   if(useBarCount < 1)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = 1; barShiftIndex <= useBarCount; barShiftIndex++)
   {
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, timeframe, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, timeframe, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForM2BarCount(const int barCount)
{
   return ReferenceChartHeightForTimeframeBarCount(InputM2NarrativeTimeframe, barCount);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForH4BarCount(const int barCount)
{
   return ReferenceChartHeightForTimeframeBarCount(PERIOD_H4, barCount);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForH4BreachBuffer()
{
   return ReferenceChartHeightForH4BarCount(InputH4BreachBufferChartBarCount);
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForM2BarCountFromShift(const int newestBarShift, const int barCount)
{
   if(barCount < 1 || newestBarShift < 0)
      return 0.0;

   const int totalBars = iBars(_Symbol, InputM2NarrativeTimeframe);
   if(totalBars < 4)
      return 0.0;

   const int startShift = newestBarShift;
   const int endShift   = newestBarShift + barCount;
   if(startShift >= totalBars)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = startShift; barShiftIndex <= endShift; barShiftIndex++)
   {
      if(barShiftIndex >= totalBars)
         break;
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, InputM2NarrativeTimeframe, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, InputM2NarrativeTimeframe, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

void LogHuntEvent(const string eventName, const string detail = "")
{
   if(!H4LqLoggingEnabled())
      return;

   const datetime barTime = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   const string timeText  = (barTime != 0) ? TimeToString(barTime, TIME_DATE | TIME_MINUTES) : "no-bar";

   if(StringLen(detail) > 0)
      PrintFormat("%s [%s] %s | %s", H4_LQ_LOG_PREFIX, timeText, eventName, detail);
   else
      PrintFormat("%s [%s] %s", H4_LQ_LOG_PREFIX, timeText, eventName);
}

//+------------------------------------------------------------------+

#endif // H4_LQ_V3_H4LQV3RUNTIME
