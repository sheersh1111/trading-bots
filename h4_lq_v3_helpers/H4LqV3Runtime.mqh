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
//| 00:00-01:00 server time (12am-1am).                              |
//+------------------------------------------------------------------+
bool IsMidnightBlackoutHour(const datetime when = 0)
{
   if(!InputEnableMidnightHourBlackout)
      return false;

   const datetime t = (when == 0 ? TimeCurrent() : when);
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return (dt.hour >= 0 && dt.hour < 1);
}

//+------------------------------------------------------------------+
datetime MidnightBlackoutDayKey(const datetime when)
{
   MqlDateTime dt;
   TimeToStruct(when, dt);
   return StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
}

//+------------------------------------------------------------------+
//| High-impact news blackout via the MT5 economic calendar.          |
//| Returns true when 'when' falls inside [event - (before+lead),      |
//| event + after] for any qualifying event. 'extraLeadMinutesBefore'  |
//| widens only the pre-event side (used to flatten 1 min ahead of the |
//| entry-block window). Live/forward only unless the tester has       |
//| calendar data for the symbol currencies + date range. On success,  |
//| outEventTime/outEventName describe the nearest such in-window event |
//| (first match in query order).                                      |
//+------------------------------------------------------------------+
bool IsHighImpactNewsBlackout(const datetime when, datetime &outEventTime, string &outEventName,
                              const int extraLeadMinutesBefore = 0)
{
   outEventTime = 0;
   outEventName = "";

   if(!InputEnableNewsBlackout)
      return false;

   const datetime nowT      = (when == 0 ? TimeCurrent() : when);
   int            beforeMin  = InputNewsBlackoutMinutesBefore + extraLeadMinutesBefore;
   if(beforeMin < 0)
      beforeMin = 0;
   const int      beforeSec = beforeMin * 60;
   const int      afterSec  = (InputNewsBlackoutMinutesAfter  > 0 ? InputNewsBlackoutMinutesAfter  : 0) * 60;

   // now in [T-before, T+after]  <=>  T in [now-after, now+before]
   const datetime from = nowT - afterSec;
   const datetime to   = nowT + beforeSec;

   const string base  = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   const string quote = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

   MqlCalendarValue values[];
   const int total = CalendarValueHistory(values, from, to, NULL, NULL);
   if(total <= 0)
      return false;

   for(int i = 0; i < total; i++)
   {
      const datetime evtTime = values[i].time;
      if(evtTime == 0)
         continue;
      if(nowT < evtTime - beforeSec || nowT > evtTime + afterSec)
         continue;

      MqlCalendarEvent evt;
      if(!CalendarEventById(values[i].event_id, evt))
         continue;

      if(InputNewsBlackoutHighImpactOnly)
      {
         if(evt.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;
      }
      else
      {
         if(evt.importance != CALENDAR_IMPORTANCE_HIGH &&
            evt.importance != CALENDAR_IMPORTANCE_MODERATE)
            continue;
      }

      if(InputNewsBlackoutSymbolCurrenciesOnly)
      {
         MqlCalendarCountry country;
         if(!CalendarCountryById(evt.country_id, country))
            continue;
         if(country.currency != base && country.currency != quote)
            continue;
      }

      outEventTime = evtTime;
      outEventName = evt.name;
      return true;
   }

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
