//+------------------------------------------------------------------+
//| HuntSession.mqh
//| Hunt session and position mgmt
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_HUNTSESSION
#define H4_LQ_V3_HUNTSESSION

bool V2TryGetLastCompletedM2Leg(const int legDirection, double &outLegLow, double &outLegHigh,
                                   datetime &outLegStartTime, datetime &outLegEndTime)
{
   outLegLow  = 0.0;
   outLegHigh = 0.0;
   outLegStartTime = 0;
   outLegEndTime   = 0;
   if(legDirection == 0 || g_m2Swing.swingHistoryCount < 1)
      return false;

   for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m2Swing.swingHistory[historyIndex].swingDirection != legDirection)
         continue;
      outLegLow         = g_m2Swing.swingHistory[historyIndex].legLowPrice;
      outLegHigh        = g_m2Swing.swingHistory[historyIndex].legHighPrice;
      outLegStartTime   = g_m2Swing.swingHistory[historyIndex].legStartTime;
      outLegEndTime     = g_m2Swing.swingHistory[historyIndex].legEndTime;
      return (outLegLow > 0.0 && outLegHigh > 0.0);
   }
   return false;
}
bool TryNthM2CompletedSwingLeg(const int swingDirection, const int nFromLatest,
                               double &outLegHigh, double &outLegLow, datetime &outLegEndTime)
{
   outLegEndTime = 0;
   if(swingDirection == 0 || nFromLatest < 1)
      return false;

   int legsFound = 0;
   for(int i = g_m2Swing.swingHistoryCount - 1; i >= 0; i--)
   {
      if(g_m2Swing.swingHistory[i].swingDirection != swingDirection)
         continue;
      legsFound++;
      if(legsFound == nFromLatest)
      {
         outLegHigh    = g_m2Swing.swingHistory[i].legHighPrice;
         outLegLow     = g_m2Swing.swingHistory[i].legLowPrice;
         outLegEndTime = g_m2Swing.swingHistory[i].legEndTime;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
// Close crossed above latest completed M2 up-leg high (bullish price BOS).
bool TryDetectM2PriceBreakAboveLatestUpLegHigh(double &outBrokenLevel)
{
   outBrokenLevel = 0.0;
   if(g_m2Swing.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, InputM2NarrativeTimeframe, 1);
   const double prevClose  = iClose(_Symbol, InputM2NarrativeTimeframe, 2);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m2Swing.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double swingLegHighPrice = g_m2Swing.swingHistory[historyIndex].legHighPrice;
      if(closePrice > swingLegHighPrice + pointSize && prevClose <= swingLegHighPrice + pointSize)
      {
         outBrokenLevel = swingLegHighPrice;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
// Close crossed below latest completed M2 down-leg low (bearish price BOS).
bool TryDetectM2PriceBreakBelowLatestDownLegLow(double &outBrokenLevel)
{
   outBrokenLevel = 0.0;
   if(g_m2Swing.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, InputM2NarrativeTimeframe, 1);
   const double prevClose  = iClose(_Symbol, InputM2NarrativeTimeframe, 2);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int historyIndex = g_m2Swing.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(g_m2Swing.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double swingLegLowPrice = g_m2Swing.swingHistory[historyIndex].legLowPrice;
      if(closePrice < swingLegLowPrice - pointSize && prevClose >= swingLegLowPrice - pointSize)
      {
         outBrokenLevel = swingLegLowPrice;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
string V2HuntTradeCommentPrefix(const datetime huntSessionId)
{
   if(huntSessionId == 0)
      return "LQ2_HS0_";
   return "LQ2_HS" + IntegerToString((long)huntSessionId) + "_";
}

//+------------------------------------------------------------------+
string HuntTradeOrderCommentPrefix(const datetime huntSessionId = 0)
{
   if(huntSessionId != 0)
      return V2HuntTradeCommentPrefix(huntSessionId);
   if(g_huntTradeSessionCommentPrefix != "")
      return g_huntTradeSessionCommentPrefix;
   return "LQ2_HS0_";
}

bool HuntTradeCommentMatchesSession(const string orderComment)
{
   if(g_huntTradeSessionCommentPrefix == "")
      return false;
   return (StringFind(orderComment, g_huntTradeSessionCommentPrefix) == 0);
}

//+------------------------------------------------------------------+
bool HuntTradeCommentIsOurs(const string orderComment)
{
   if(HuntTradeCommentMatchesSession(orderComment))
      return true;
   return (StringFind(orderComment, "LQ2_HS") == 0);
}

//+------------------------------------------------------------------+
bool IsOurHuntPendingOrderTicket(const ulong orderTicket)
{
   if(orderTicket == 0 || !OrderSelect(orderTicket))
      return false;
   if(OrderGetString(ORDER_SYMBOL) != _Symbol)
      return false;
   if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
      return false;

   const ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
   if(orderState != ORDER_STATE_PLACED && orderState != ORDER_STATE_PARTIAL)
      return false;

   const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT &&
      orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP &&
      orderType != ORDER_TYPE_BUY_STOP_LIMIT && orderType != ORDER_TYPE_SELL_STOP_LIMIT)
      return false;

   return HuntTradeCommentIsOurs(OrderGetString(ORDER_COMMENT));
}

//+------------------------------------------------------------------+
bool ParseHuntSessionIdFromTradeComment(const string orderComment, datetime &outSessionId)
{
   outSessionId = 0;
   if(StringFind(orderComment, "LQ2_HS") != 0)
      return false;

   const int afterPrefix   = 6;
   const int underscorePos = StringFind(orderComment, "_", afterPrefix);
   if(underscorePos <= afterPrefix)
      return false;

   const string sessionTag = StringSubstr(orderComment, afterPrefix, underscorePos - afterPrefix);
   const long   sessionUnix = StringToInteger(sessionTag);
   if(sessionUnix <= 0)
      return false;

   outSessionId = (datetime)sessionUnix;
   return true;
}

//+------------------------------------------------------------------+
bool TryParseFormationTimeFromHuntOrderComment(const string orderComment, datetime &outFormationTime)
{
   outFormationTime = 0;
   int lastUnderscorePos = -1;
   int searchFrom      = 0;
   while(true)
   {
      const int found = StringFind(orderComment, "_", searchFrom);
      if(found < 0)
         break;
      lastUnderscorePos = found;
      searchFrom        = found + 1;
   }

   if(lastUnderscorePos < 0)
      return false;

   const string formationTag = StringSubstr(orderComment, lastUnderscorePos + 1);
   if(StringLen(formationTag) < 8)
      return false;

   const long formationUnix = StringToInteger(formationTag);
   if(formationUnix <= 0)
      return false;

   outFormationTime = (datetime)formationUnix;
   return true;
}

datetime HuntSessionIdFromTradeCommentPrefix(const string commentPrefix)
{
   if(StringFind(commentPrefix, "LQ2_HS") != 0)
      return 0;

   const int afterPrefix = 6;
   const int underscorePos = StringFind(commentPrefix, "_", afterPrefix);
   if(underscorePos <= afterPrefix)
      return 0;

   const long sessionUnix = StringToInteger(StringSubstr(commentPrefix, afterPrefix,
                                                         underscorePos - afterPrefix));
   if(sessionUnix <= 0)
      return 0;

   return (datetime)sessionUnix;
}

//+------------------------------------------------------------------+
void EnsureHuntTradeSessionCommentPrefixFromOrdersOrPositions()
{
   if(g_huntTradeSessionCommentPrefix != "")
      return;

   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(!IsOurHuntPendingOrderTicket(ticket))
         continue;
      const string comment = OrderGetString(ORDER_COMMENT);
      const int cqPos = StringFind(comment, "_CQ_");
      const int ovPos = StringFind(comment, "_OV_");
      const int tagPos = (cqPos >= 0 ? cqPos : ovPos);
      if(tagPos >= 0)
         g_huntTradeSessionCommentPrefix = StringSubstr(comment, 0, tagPos + 1);
      else
         g_huntTradeSessionCommentPrefix = comment;
      return;
   }

   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      if(PositionGetSymbol(positionIndex) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "LQ2_HS") != 0)
         continue;
      const int cqPos = StringFind(comment, "_CQ_");
      const int ovPos = StringFind(comment, "_OV_");
      const int tagPos = (cqPos >= 0 ? cqPos : ovPos);
      if(tagPos >= 0)
         g_huntTradeSessionCommentPrefix = StringSubstr(comment, 0, tagPos + 1);
      else
         g_huntTradeSessionCommentPrefix = comment;
      return;
   }
}

//+------------------------------------------------------------------+
bool HasOurHuntTradeOpenPosition()
{
   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      if(PositionGetSymbol(positionIndex) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(HuntTradeCommentIsOurs(PositionGetString(POSITION_COMMENT)))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool StopLossModifyAllowed(const bool isBuy, const double newStopLoss, const double takeProfitPrice)
{
   const int    stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double pointSize        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minDistance      = (double)stopsLevelPoints * pointSize;
   const double bid              = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask              = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBuy)
   {
      if(bid <= 0.0)
         return false;
      if(minDistance > 0.0 && newStopLoss >= bid - minDistance)
         return false;
      if(takeProfitPrice > 0.0 && minDistance > 0.0 && takeProfitPrice <= ask + minDistance)
         return false;
   }
   else
   {
      if(ask <= 0.0)
         return false;
      if(minDistance > 0.0 && newStopLoss <= ask + minDistance)
         return false;
      if(takeProfitPrice > 0.0 && minDistance > 0.0 && takeProfitPrice >= bid - minDistance)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool TakeProfitModifyAllowed(const bool isBuy, const double stopLossPrice,
                              const double newTakeProfit)
{
   const int    stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double pointSize        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minDistance      = (double)stopsLevelPoints * pointSize;
   const double bid              = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask              = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBuy)
   {
      if(ask <= 0.0)
         return false;
      if(minDistance > 0.0 && newTakeProfit <= ask + minDistance)
         return false;
      if(stopLossPrice > 0.0 && minDistance > 0.0 && stopLossPrice >= bid - minDistance)
         return false;
   }
   else
   {
      if(bid <= 0.0)
         return false;
      if(minDistance > 0.0 && newTakeProfit >= bid - minDistance)
         return false;
      if(stopLossPrice > 0.0 && minDistance > 0.0 && stopLossPrice <= ask + minDistance)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool HuntTradeCommentIsOvSwingTp(const string orderComment)
{
   if(!HuntTradeCommentIsOurs(orderComment))
      return false;
   for(int tpIndex = 1; tpIndex <= TradeSwingTpTargetCount(); tpIndex++)
   {
      if(HuntTradeCommentIsOvTpIndex(orderComment, tpIndex))
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int HuntTradeCountOpenOvTpLegs(const int targetTpCount)
{
   bool hasTp1 = false;
   bool hasTp2 = false;
   bool hasTp3 = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const string comment = PositionGetString(POSITION_COMMENT);
      if(!HuntTradeCommentIsOurs(comment))
         continue;
      if(HuntTradeCommentIsOvTpIndex(comment, 1))
         hasTp1 = true;
      if(HuntTradeCommentIsOvTpIndex(comment, 2))
         hasTp2 = true;
      if(targetTpCount >= 3 && HuntTradeCommentIsOvTpIndex(comment, 3))
         hasTp3 = true;
   }

   int remaining = 0;
   if(hasTp1)
      remaining++;
   if(hasTp2)
      remaining++;
   if(targetTpCount >= 3 && hasTp3)
      remaining++;
   return remaining;
}

//+------------------------------------------------------------------+
bool HuntTradeCommentIsCloseQuarter(const string orderComment)
{
   return (StringFind(orderComment, "_CQ_") >= 0);
}

//+------------------------------------------------------------------+
bool HuntTradeCommentIsOverall(const string orderComment)
{
   return (StringFind(orderComment, "_OV_") >= 0);
}

//+------------------------------------------------------------------+
bool HuntTradeCommentIsOvTpIndex(const string orderComment, const int tpIndex)
{
   if(tpIndex < 1 || tpIndex > TradeSwingTpTargetCount())
      return false;

   const string token = "OV_TP" + IntegerToString(tpIndex);
   const int    pos   = StringFind(orderComment, token);
   if(pos < 0)
      return false;

   const int after = pos + StringLen(token);
   if(after < StringLen(orderComment))
   {
      const ushort nextChar = StringGetCharacter(orderComment, after);
      if(nextChar >= '0' && nextChar <= '9')
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void ClearHuntTradeSessionIfNoOpenPositions()
{
   if(HasOurHuntTradeOpenPosition())
      return;
   g_huntTradeSessionCommentPrefix = "";
   g_huntFirstOppBosMgmtDone       = false;
   g_lastHuntPosMgmtM2BarTime      = 0;
   g_m15ClosedLegForTpMgmt.ready   = false;
   g_lastM15TpMgmtAppliedLegEndTime = 0;
   g_huntM15TpEntryLegDirection     = 0;
   g_huntM15TpEntryLegStartTime     = 0;
   g_huntM15TpWatchArmed            = false;
}

//+------------------------------------------------------------------+
//| Arm M15 TP watch at trade entry.                                  |
//| Bull: entry on M15 up leg → move TP when that leg closes;         |
//|       entry on M15 down leg → wait for flip to up, then that close.|
//| Bear: symmetric (down leg / wait for down after up entry).        |
//+------------------------------------------------------------------+
void ArmHuntM15TpWatchAtTradeEntry(const bool isBuy)
{
   if(!InputEnableBosMoveTp || !InputEnableMtfSmcEngine)
   {
      g_huntM15TpWatchArmed = false;
      return;
   }

   g_huntM15TpEntryLegDirection = g_mtfSwingM15.swing.currentSwingLeg.swingDirection;
   g_huntM15TpEntryLegStartTime = g_mtfSwingM15.swing.currentSwingLeg.legStartTime;
   g_huntM15TpWatchArmed        = true;
   g_lastM15TpMgmtAppliedLegEndTime = 0;
   g_m15ClosedLegForTpMgmt.ready    = false;

   if(H4LqLoggingEnabled())
   {
      LogHuntEvent("TRADE_TP_M15_ARM",
                   StringFormat("%s entryM15Dir=%d entryLegStart=%s",
                                isBuy ? "bull" : "bear",
                                g_huntM15TpEntryLegDirection,
                                TimeToString(g_huntM15TpEntryLegStartTime,
                                             TIME_DATE | TIME_MINUTES)));
   }
}

//+------------------------------------------------------------------+
bool IsRelevantM15LegCloseForHuntTp(const bool isBuy)
{
   if(!g_huntM15TpWatchArmed)
      return false;

   const int closedDir = g_m15ClosedLegForTpMgmt.direction;
   const int targetDir = isBuy ? 1 : -1;
   if(closedDir != targetDir)
      return false;

   const int      entryDir    = g_huntM15TpEntryLegDirection;
   const datetime closedStart = g_m15ClosedLegForTpMgmt.legStartTime;
   if(closedStart == 0)
      return false;

   if(isBuy)
   {
      if(entryDir == 1)
         return (closedStart == g_huntM15TpEntryLegStartTime);
      if(entryDir == -1)
         return (closedStart > g_huntM15TpEntryLegStartTime);
      return true;
   }

   if(entryDir == -1)
      return (closedStart == g_huntM15TpEntryLegStartTime);
   if(entryDir == 1)
      return (closedStart > g_huntM15TpEntryLegStartTime);
   return true;
}

//+------------------------------------------------------------------+
bool M2LegContainsFvg(const datetime legStart, const datetime legEnd, const bool checkBullish)
{
   if(legStart == 0 || legEnd == 0)
      return false;
   int shiftStart = iBarShift(_Symbol, InputM2NarrativeTimeframe, legStart, true);
   int shiftEnd = iBarShift(_Symbol, InputM2NarrativeTimeframe, legEnd, true);
   if(shiftStart < 0)
      shiftStart = iBarShift(_Symbol, InputM2NarrativeTimeframe, legStart, false);
   if(shiftEnd < 0)
      shiftEnd = 1;
   if(shiftStart < shiftEnd)
   {
      int tmp = shiftStart;
      shiftStart = shiftEnd;
      shiftEnd = tmp;
   }

   if(shiftStart - shiftEnd < 2)
      return false;

   for(int i = shiftEnd; i <= shiftStart - 2; i++)
   {
      const double bar1High = iHigh(_Symbol, InputM2NarrativeTimeframe, i + 2);
      const double bar1Low  = iLow(_Symbol, InputM2NarrativeTimeframe, i + 2);
      const double bar3High = iHigh(_Symbol, InputM2NarrativeTimeframe, i);
      const double bar3Low  = iLow(_Symbol, InputM2NarrativeTimeframe, i);

      if(checkBullish && bar3Low > bar1High)
         return true;
      if(!checkBullish && bar3High < bar1Low)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryGetLatestQualifiedSlExtreme(const bool isBuy, double &outGroupExtreme)
{
    outGroupExtreme = 0.0;
    if(g_m2Swing.swingHistoryCount < 2) return false;

    const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    const double tolerance = (pointSize > 0.0 ? pointSize : 0.00001);
    
    int targetLegIndex = -1;

    // 1. Find most recent completed leg that caused a BOS AND has an FVG
    for(int i = g_m2Swing.swingHistoryCount - 1; i >= 1; i--)
    {
        const Swing leg = g_m2Swing.swingHistory[i];

        if(isBuy && leg.swingDirection == 1)
        {
            double prevHigh = 0.0;
            for(int j = i - 1; j >= 0; j--) {
                if(g_m2Swing.swingHistory[j].swingDirection == -1) {
                    prevHigh = g_m2Swing.swingHistory[j].legHighPrice;
                    break;
                }
            }
            if(prevHigh > 0.0 && leg.legHighPrice > prevHigh + tolerance)
            {
                if(M2LegContainsFvg(leg.legStartTime, leg.legEndTime, true))
                {
                    targetLegIndex = i;
                    break;
                }
            }
        }
        else if(!isBuy && leg.swingDirection == -1)
        {
            double prevLow = 0.0;
            for(int j = i - 1; j >= 0; j--) {
                if(g_m2Swing.swingHistory[j].swingDirection == 1) {
                    prevLow = g_m2Swing.swingHistory[j].legLowPrice;
                    break;
                }
            }
            if(prevLow > 0.0 && leg.legLowPrice < prevLow - tolerance)
            {
                if(M2LegContainsFvg(leg.legStartTime, leg.legEndTime, false))
                {
                    targetLegIndex = i;
                    break;
                }
            }
        }
    }

    if(targetLegIndex < 0) return false;

    const double originExtreme = isBuy ? g_m2Swing.swingHistory[targetLegIndex].legLowPrice 
                                       : g_m2Swing.swingHistory[targetLegIndex].legHighPrice;
    const datetime originTime  = g_m2Swing.swingHistory[targetLegIndex].legStartTime;

    // 2. Group the origin extreme with nearby equal highs/lows
    int formationShift = iBarShift(_Symbol, InputM2NarrativeTimeframe, originTime, false);
    if(formationShift < 0) formationShift = 1;
    const double chartHeight = ReferenceChartHeightForM2BarCountFromShift(formationShift, InputTradeSwingLookbackM2Bars);
    const double proximityBand = chartHeight * (InputTradeSwingProximityPercentOfChartRange / 100.0);

    outGroupExtreme = originExtreme;
    datetime earliestTime = originTime;

    for(int i = 0; i < g_m2Swing.swingHistoryCount; i++)
    {
        const Swing leg = g_m2Swing.swingHistory[i];
        if(isBuy && leg.swingDirection == 1)
        {
            if(MathAbs(leg.legLowPrice - originExtreme) <= proximityBand)
            {
                outGroupExtreme = MathMin(outGroupExtreme, leg.legLowPrice);
                if(leg.legStartTime > 0 && leg.legStartTime < earliestTime) earliestTime = leg.legStartTime;
            }
        }
        else if(!isBuy && leg.swingDirection == -1)
        {
            if(MathAbs(leg.legHighPrice - originExtreme) <= proximityBand)
            {
                outGroupExtreme = MathMax(outGroupExtreme, leg.legHighPrice);
                if(leg.legStartTime > 0 && leg.legStartTime < earliestTime) earliestTime = leg.legStartTime;
            }
        }
    }
    
    // 3. Draw the Proximity Buffer Visual (Blue Rectangle)
    if(H4LqChartDrawEnabled(InputDrawTradeSwingGroupTpZones))
    {
        double boundLow = 0.0;
        double boundHigh = 0.0;
        
        // Match TP logic: anchor to the extreme and project 10% inward
        if(isBuy)
        {
            boundLow  = outGroupExtreme;
            boundHigh = outGroupExtreme + proximityBand;
        }
        else
        {
            boundHigh = outGroupExtreme;
            boundLow  = outGroupExtreme - proximityBand;
        }

        datetime timeRight = iTime(_Symbol, InputM2NarrativeTimeframe, 0);
        if(timeRight == 0) timeRight = TimeCurrent();
        
        const string objName = "LQ2_SL_PROX_R_" + IntegerToString((long)originTime);
        if(ObjectFind(0, objName) < 0)
        {
            ObjectCreate(0, objName, OBJ_RECTANGLE, 0, earliestTime, boundHigh, timeRight, boundLow);
        }
        else
        {
            ObjectSetInteger(0, objName, OBJPROP_TIME, 0, earliestTime);
            ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, boundHigh);
            ObjectSetInteger(0, objName, OBJPROP_TIME, 1, timeRight);
            ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, boundLow);
        }
        
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDodgerBlue); // Distinct Blue Color
        ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, objName, OBJPROP_FILL, false);
        ObjectSetInteger(0, objName, OBJPROP_BACK, false);
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, objName, OBJPROP_HIDDEN, false);
        ObjectSetInteger(0, objName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
    }
    
    return true;
}

//+------------------------------------------------------------------+
void ManageHuntTradeTieredStopLoss(const bool isBuy)
{
   if(!InputEnableBosMoveSl)
      return;

   bool hasTp1 = false, hasTp2 = false, hasTp3 = false;
   double entryPrice = 0.0;
   
   // 1. Scan open positions to deduce which TPs have been hit/closed
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC) continue;
      
      string comment = PositionGetString(POSITION_COMMENT);
      if(!HuntTradeCommentIsOurs(comment)) continue;
      
      if(HuntTradeCommentIsOvTpIndex(comment, 1)) hasTp1 = true;
      if(HuntTradeCommentIsOvTpIndex(comment, 2)) hasTp2 = true;
      if(HuntTradeCommentIsOvTpIndex(comment, 3)) hasTp3 = true;
      
      if(entryPrice == 0.0) entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   }
   
   if(entryPrice <= 0.0) return; // No open positions for this hunt

   double newStopLoss = 0.0;
   int currentStage = 0;

   // STAGE 2: TP1 and TP2 are HIT (Only TP3 remains)
   if(!hasTp1 && !hasTp2 && hasTp3)
   {
      currentStage = 2;
      double groupExtreme = 0.0;
      
      // Look backward for the latest structural BOS + FVG, group it with equal highs/lows
      if(TryGetLatestQualifiedSlExtreme(isBuy, groupExtreme))
      {
         const double chartHeight = ReferenceChartHeightForFairValueGapFilterM2();
         const double buffer2Percent = chartHeight * 0.02;

         if(isBuy) newStopLoss = NormalizeDouble(groupExtreme - buffer2Percent, _Digits);
         else      newStopLoss = NormalizeDouble(groupExtreme + buffer2Percent, _Digits);
      }
   }
   // STAGE 1: TP1 is HIT (TP2 and/or TP3 still remain)
   else if(!hasTp1 && (hasTp2 || hasTp3))
   {
      currentStage = 1;
      newStopLoss = NormalizeDouble(entryPrice, _Digits); // Move to Break-Even
   }
   
   if(newStopLoss <= 0.0 || currentStage == 0) return; // Nothing to update

   // 2. Apply the modification to surviving positions
   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();

   int modifiedCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC) continue;
      if(!HuntTradeCommentIsOurs(PositionGetString(POSITION_COMMENT))) continue;

      double currentSl = PositionGetDouble(POSITION_SL);
      double currentTp = PositionGetDouble(POSITION_TP);
      bool posIsBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

      if(posIsBuy != isBuy) continue;

      // NEVER move SL backwards (widen risk)
      if(isBuy && currentSl > 0.0 && newStopLoss <= currentSl) continue;
      if(!isBuy && currentSl > 0.0 && newStopLoss >= currentSl) continue;

      if(!StopLossModifyAllowed(posIsBuy, newStopLoss, currentTp)) continue;

      if(g_trade.PositionModify(ticket, newStopLoss, currentTp))
      {
         modifiedCount++;
      }
   }
   
   if(modifiedCount > 0)
   {
       LogHuntEvent("TRADE_SL_TIERED", 
                    StringFormat("Tiered SL moved to %.5f | Stage: %s", 
                                 newStopLoss, 
                                 currentStage == 2 ? "TP2 Hit -> Structural - 2%" : "TP1 Hit -> Break-Even"));
   }
}

//+------------------------------------------------------------------+
//| M15 leg close: move remaining swing-TP legs to offset from extreme. |
//+------------------------------------------------------------------+
void ManageHuntTradeM15LegCloseTp(const bool isBuy)
{
   if(!InputEnableBosMoveTp || !InputEnableMtfSmcEngine)
      return;
   if(!g_m15ClosedLegForTpMgmt.ready)
      return;
   if(g_m15ClosedLegForTpMgmt.legEndTime == 0)
      return;
   if(g_m15ClosedLegForTpMgmt.legEndTime == g_lastM15TpMgmtAppliedLegEndTime)
   {
      g_m15ClosedLegForTpMgmt.ready = false;
      return;
   }

   // Bull: target M15 up-leg close (entry-aware). Bear: target M15 down-leg close.
   if(!IsRelevantM15LegCloseForHuntTp(isBuy))
      return;

   const int remainingTp = HuntTradeCountOpenOvTpLegs(TradeSwingTpTargetCount());
   if(remainingTp <= 0)
      return;

   const double chartHeight = ReferenceChartHeightForTimeframeBarCount(PERIOD_M15,
                                                                       InputChartRangeBarCount);
   if(chartHeight <= 0.0 || InputBosMoveTpM15OffsetPercentChart <= 0.0)
      return;

   const double offset = chartHeight * (InputBosMoveTpM15OffsetPercentChart / 100.0);
   double newTakeProfit = 0.0;
   if(isBuy)
      newTakeProfit = NormalizeDouble(g_m15ClosedLegForTpMgmt.legHigh - offset, _Digits);
   else
      newTakeProfit = NormalizeDouble(g_m15ClosedLegForTpMgmt.legLow + offset, _Digits);
   if(newTakeProfit <= 0.0)
      return;

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();

   int modifiedCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const string comment = PositionGetString(POSITION_COMMENT);
      if(!HuntTradeCommentIsOurs(comment) || !HuntTradeCommentIsOvSwingTp(comment))
         continue;

      const bool posIsBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(posIsBuy != isBuy)
         continue;

      const double currentSl = PositionGetDouble(POSITION_SL);
      const double currentTp = PositionGetDouble(POSITION_TP);

      if(!TakeProfitModifyAllowed(posIsBuy, currentSl, newTakeProfit))
         continue;

      if(g_trade.PositionModify(ticket, currentSl, newTakeProfit))
         modifiedCount++;
   }

   if(modifiedCount > 0)
   {
      g_lastM15TpMgmtAppliedLegEndTime = g_m15ClosedLegForTpMgmt.legEndTime;
      g_m15ClosedLegForTpMgmt.ready    = false;
      g_huntM15TpWatchArmed            = false;
      LogHuntEvent("TRADE_TP_M15",
                     StringFormat("%s leg close → TP=%.5f (%d legs, offset %.1f%% M15 chart, entryM15Dir=%d)",
                                  isBuy ? "M15 up" : "M15 down",
                                  newTakeProfit, modifiedCount,
                                  InputBosMoveTpM15OffsetPercentChart,
                                  g_huntM15TpEntryLegDirection));
   }
}

//+------------------------------------------------------------------+
bool TryResolveHuntTradeSide(bool &outIsBuy)
{
   outIsBuy = g_huntTradeIsBuy;
   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      if(PositionGetSymbol(positionIndex) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(!HuntTradeCommentIsOurs(PositionGetString(POSITION_COMMENT)))
         continue;
      outIsBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      return true;
   }
   return g_huntTradeOrdersActive;
}

//+------------------------------------------------------------------+
//| Run M15 leg-close TP move as soon as the snapshot is ready (not only on M2 close). |
//+------------------------------------------------------------------+
void ProcessHuntM15LegCloseTpIfReady()
{
   if(!InputEnableBosMoveTp || !InputEnableMtfSmcEngine)
      return;
   if(!g_m15ClosedLegForTpMgmt.ready)
      return;
   if(!HasOurHuntTradeOpenPosition())
      return;

   bool isBuy = g_huntTradeIsBuy;
   if(!TryResolveHuntTradeSide(isBuy))
      return;

   ManageHuntTradeM15LegCloseTp(isBuy);
}

//+------------------------------------------------------------------+
void ManageHuntOpenPositionsOnM2BarClose()
{
   if(!HasOurHuntTradeOpenPosition())
   {
      ClearHuntTradeSessionIfNoOpenPositions();
      return;
   }

   EnsureHuntTradeSessionCommentPrefixFromOrdersOrPositions();

   const datetime closedM2BarTime = iTime(_Symbol, InputM2NarrativeTimeframe, 1);
   if(closedM2BarTime == 0 || closedM2BarTime == g_lastHuntPosMgmtM2BarTime)
      return;
   g_lastHuntPosMgmtM2BarTime = closedM2BarTime;

   bool isBuy = g_huntTradeIsBuy;
   if(!TryResolveHuntTradeSide(isBuy))
      return;

   ManageHuntTradeTieredStopLoss(isBuy);
   ManageHuntTradeM15LegCloseTp(isBuy);
}

//+------------------------------------------------------------------+
int CloseAllOurHuntPositionsAtMarket()
{
   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   ApplyTradeFillingModeFromSymbol();

   int closedCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(!HuntTradeCommentIsOurs(PositionGetString(POSITION_COMMENT)))
         continue;
      if(g_trade.PositionClose(ticket))
         closedCount++;
   }
   return closedCount;
}

//+------------------------------------------------------------------+
//| Once per calendar day at 00:00 server: flatten hunt exposure.       |
//+------------------------------------------------------------------+
void ProcessMidnightHourBlackout()
{
   if(!InputEnableMidnightHourBlackout)
      return;

   const datetime now = TimeCurrent();
   if(!IsMidnightBlackoutHour(now))
      return;

   const datetime dayKey = MidnightBlackoutDayKey(now);
   if(dayKey == 0 || dayKey == g_lastMidnightBlackoutCloseDay)
      return;

   g_lastMidnightBlackoutCloseDay = dayKey;

   CancelOurHuntPendingOrders(0);
   const int closedCount = CloseAllOurHuntPositionsAtMarket();

   if(closedCount > 0)
   {
      LogHuntEvent("MIDNIGHT_BLACKOUT",
                   StringFormat("00:00 server flatten closed=%d", closedCount));
   }

   ClearHuntTradeSessionIfNoOpenPositions();
   ResetHuntTradePlacementGateOnly();
}

//| huntSessionId=0: all LQ2_HS pendings; else that session only (TP3 / chart-range cancel). |
//+------------------------------------------------------------------+
void V2InitHuntSlot(const int huntIndex)
{
   if(huntIndex < 0 || huntIndex >= V2_MAX_HUNT_SESSIONS)
      return;
   g_v2Hunts[huntIndex].active                         = false;
   g_v2Hunts[huntIndex].h4HighWasBreached             = false;
   g_v2Hunts[huntIndex].h4BreachedLegLevelPrice       = 0.0;
   g_v2Hunts[huntIndex].h4BreachedLegEndTime         = 0;
   g_v2Hunts[huntIndex].closeWhenH4LiquidityBreached  = 0.0;
   g_v2Hunts[huntIndex].pathMinLowSinceH4Breach            = 0.0;
   g_v2Hunts[huntIndex].pathMaxHighSinceH4Breach           = 0.0;
   g_v2Hunts[huntIndex].impulseCloseExtremeSinceH4Breach = 0.0;
   g_v2Hunts[huntIndex].sessionId                      = 0;
   g_v2Hunts[huntIndex].lastEngulfPairExtremeChecked    = 0.0;
   g_v2Hunts[huntIndex].tradeOrdersActive              = false;
   g_v2Hunts[huntIndex].ordersFvgFormationTime         = 0;
   g_v2Hunts[huntIndex].tradeIsBuy                     = false;
   g_v2Hunts[huntIndex].tradeEntryPrice                = 0.0;
   g_v2Hunts[huntIndex].tradeTp1Price                  = 0.0;
   g_v2Hunts[huntIndex].preEntryCancelTpLevel          = 0.0;
   g_v2Hunts[huntIndex].firstOppBosMgmtDone            = false;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void V2InitAllHuntSlots()
{
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
      V2InitHuntSlot(i);
}

int V2FindHuntSlotBySessionId(const datetime sessionId)
{
   if(sessionId == 0)
      return -1;
   for(int i = 0; i < V2_MAX_HUNT_SESSIONS; i++)
   {
      if(g_v2Hunts[i].sessionId == sessionId)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
string V2HuntObjectSuffix(const datetime sessionId)
{
   return IntegerToString((long)sessionId) + "_";
}

void V2LogHuntEvent(const int huntIndex, const string eventName, const string detail = "")
{
   if(!H4LqLoggingEnabled())
      return;
   string prefix = "";
   if(huntIndex >= 0 && huntIndex < V2_MAX_HUNT_SESSIONS && g_v2Hunts[huntIndex].sessionId != 0)
      prefix = "HS" + IntegerToString((long)g_v2Hunts[huntIndex].sessionId) + " ";
   else if(huntIndex >= 0)
      prefix = "HS? ";
   if(StringLen(detail) > 0)
      LogHuntEvent(eventName, prefix + detail);
   else
      LogHuntEvent(eventName, prefix);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| H4 up-leg breach â†’ bull FVG; H4 down-leg breach â†’ bear FVG.       |
//| Touch recalc: active opposite M2 leg while open; else last completed opposite. |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Same-dir extreme tracked while hunt is ON (path max high / min low). |
//| v3 legacy stubs
//| Hunt ON only. Opposite M2 BOS clears marked same-dir FVGs.       |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

#endif // H4_LQ_V3_HUNTSESSION
