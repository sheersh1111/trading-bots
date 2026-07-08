//+------------------------------------------------------------------+
//| TradeExecution.mqh
//| Order placement and sizing
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_TRADEEXECUTION
#define H4_LQ_V3_TRADEEXECUTION

void ApplyTradeFillingModeFromSymbol()
{
   const long fillingMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(fillingMode == 0)
      return;
   if((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
int TouchVolEffectiveMinSlPoints()
{
   int minPts = InputTouchVolMinSlPoints;
   const int brokerPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(brokerPts > minPts)
      minPts = brokerPts;
   return minPts;
}

//+------------------------------------------------------------------+
bool ApplyTouchVolMinimumSlDistance(const bool isBuy, const double entryPrice,
                                     double &inOutStopLossPrice)
{
   if(entryPrice <= 0.0 || inOutStopLossPrice <= 0.0)
      return false;

   const int    minPts    = TouchVolEffectiveMinSlPoints();
   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pointSize <= 0.0)
      return false;

   const double minDistance = (minPts > 0 ? (double)minPts * pointSize : 0.0);

   if(isBuy)
   {
      if(minDistance > 0.0)
      {
         const double maxSl = entryPrice - minDistance;
         if(inOutStopLossPrice >= maxSl)
            inOutStopLossPrice = NormalizeDouble(maxSl, _Digits);
      }
      return inOutStopLossPrice < entryPrice;
   }

   if(minDistance > 0.0)
   {
      const double minSl = entryPrice + minDistance;
      if(inOutStopLossPrice <= minSl)
         inOutStopLossPrice = NormalizeDouble(minSl, _Digits);
   }
   return inOutStopLossPrice > entryPrice;
}

//+------------------------------------------------------------------+
//| Buy hunt: vol bar low + N% chart height. Sell hunt: vol bar high âˆ’ N%. |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Scan opposite M2 leg backward for most recent decent impulse; return origin bar shift. |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 61.8% OTE on full opposite M2 leg range (down leg: from low; up leg: from high). |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
double LossPerLotFromTickSpec(const double entryPrice, const double stopLossPrice)
{
   const double slDistance = MathAbs(entryPrice - stopLossPrice);
   if(slDistance <= 0.0)
      return 0.0;

   const double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   return (slDistance / tickSize) * tickValue;
}

//+------------------------------------------------------------------+
double CalculateVolumeForFixedUsdRisk(const bool isBuy, const double entryPrice,
                                      const double stopLossPrice, const double riskAccountCurrency)
{
   const ENUM_ORDER_TYPE profitOrderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double lossPerLot = 0.0;
   double profitAtStop = 0.0;
   if(OrderCalcProfit(profitOrderType, _Symbol, 1.0, entryPrice, stopLossPrice, profitAtStop))
   {
      lossPerLot = (profitAtStop < 0.0) ? -profitAtStop : profitAtStop;
   }
   if(lossPerLot <= 0.0)
      lossPerLot = LossPerLotFromTickSpec(entryPrice, stopLossPrice);
   if(lossPerLot <= 0.0)
      return 0.0;

   double volume = riskAccountCurrency / lossPerLot;
   const double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double volumeMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double volumeMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(volumeStep > 0.0)
      volume = MathFloor(volume / volumeStep) * volumeStep;
   if(volume < volumeMin)
      volume = volumeMin;
   if(volume > volumeMax)
      volume = volumeMax;

   return volume;
}

//+------------------------------------------------------------------+
bool SetupScoreAllowsTradeEntry(const double setupScore)
{
   if(InputScoreLogWriteCsv)
      return true;
   if(!ScoreLogThresholdsReady())
      return false;
   return (setupScore > GetMinScoreThreshold());
}

//+------------------------------------------------------------------+
double GetOptimizedLotSize(const double entryPrice, const double stopLoss, const double score,
                            const bool isBuy, const double riskUsdFraction = 1.0)
{
   if(InputBaseRiskUsd <= 0.0 || riskUsdFraction <= 0.0)
      return 0.0;

   double clampedRatio = 1.0;
   if(!InputScoreLogWriteCsv)
   {
      if(!ScoreLogThresholdsReady())
         return 0.0;

      const double scoreDenom = GetRiskNormalizationScore();
      if(scoreDenom <= 0.0)
         return 0.0;

      const double alignmentRatio = MathAbs(score) / scoreDenom;
      clampedRatio = MathMax(0.1, MathMin(2.0, alignmentRatio));

      LogHuntEvent("RISK_SIZE",
                   StringFormat("setupScore=%.2f scoreDenom=%.0f alignRatio=%.3f clampedRatio=%.3f baseRiskUsd=%.2f legFrac=%.3f riskUsd=%.2f",
                                score, scoreDenom, alignmentRatio,
                                clampedRatio, InputBaseRiskUsd, riskUsdFraction,
                                InputBaseRiskUsd * clampedRatio * riskUsdFraction));
   }
   else
   {
      LogHuntEvent("RISK_SIZE",
                   StringFormat("setupScore=%.2f writeMode=Y clampedRatio=%.3f baseRiskUsd=%.2f legFrac=%.3f riskUsd=%.2f",
                                score, clampedRatio, InputBaseRiskUsd, riskUsdFraction,
                                InputBaseRiskUsd * clampedRatio * riskUsdFraction));
   }

   const double riskUsd = InputBaseRiskUsd * clampedRatio * riskUsdFraction;

   return CalculateVolumeForFixedUsdRisk(isBuy, entryPrice, stopLoss, riskUsd);
}

//+------------------------------------------------------------------+
bool StopsDistanceAllowed(const bool isBuy, const double entryPrice, const double stopLossPrice,
                          const double takeProfitPrice)
{
   const int stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double pointSize     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double minDistance   = (double)stopsLevelPoints * pointSize;
   if(minDistance <= 0.0)
      return true;

   if(isBuy)
   {
      if(MathAbs(entryPrice - stopLossPrice) < minDistance)
         return false;
      if(MathAbs(takeProfitPrice - entryPrice) < minDistance)
         return false;
   }
   else
   {
      if(MathAbs(stopLossPrice - entryPrice) < minDistance)
         return false;
      if(MathAbs(entryPrice - takeProfitPrice) < minDistance)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
void CancelOurHuntPendingOrders(const datetime huntSessionId)
{
   const int    huntIndex = V2FindHuntSlotBySessionId(huntSessionId);
   const string sessionPrefix =
      (huntSessionId != 0 ? V2HuntTradeCommentPrefix(huntSessionId) : "");

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   int deletedCount = 0;
   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(orderState != ORDER_STATE_PLACED && orderState != ORDER_STATE_PARTIAL)
         continue;

      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT &&
         orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP &&
         orderType != ORDER_TYPE_BUY_STOP_LIMIT && orderType != ORDER_TYPE_SELL_STOP_LIMIT)
         continue;

      const string comment = OrderGetString(ORDER_COMMENT);
      if(StringFind(comment, "LQ2_HS") != 0)
         continue;
      if(sessionPrefix != "" && StringFind(comment, sessionPrefix) != 0)
         continue;

      if(g_trade.OrderDelete(ticket))
         deletedCount++;
   }

   if(deletedCount > 0)
   {
      if(huntIndex >= 0)
         V2LogHuntEvent(huntIndex, "HUNT_PENDING_DELETE",
                        StringFormat("deleted=%d", deletedCount));
      else if(huntSessionId != 0)
         LogHuntEvent("HUNT_PENDING_DELETE",
                      StringFormat("HS%lld deleted=%d", (long)huntSessionId, deletedCount));
      else
         LogHuntEvent("HUNT_PENDING_DELETE", StringFormat("deleted=%d", deletedCount));
   }
}

//+------------------------------------------------------------------+
void ResetHuntTradePlacementGateOnly()
{
   g_huntTradeOrdersActive      = false;
   g_huntOrdersFvgFormationTime = 0;
}

//+------------------------------------------------------------------+
void ResetHuntTradeState()
{
   g_huntTradeOrdersActive      = false;
   g_huntOrdersFvgFormationTime = 0;
   g_huntTradeIsBuy             = false;
   g_huntTradeEntryPrice        = 0.0;
   g_huntPreEntryCancelTpLevel  = 0.0;
   if(!HasOurHuntTradeOpenPosition())
   {
      g_huntTradeSessionCommentPrefix = "";
      g_huntFirstOppBosMgmtDone       = false;
      g_lastHuntPosMgmtM2BarTime      = 0;
   }
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
bool V2HuntHasOpenPositionForSession(const datetime huntSessionId)
{
   const string prefix = V2HuntTradeCommentPrefix(huntSessionId);
   for(int positionIndex = PositionsTotal() - 1; positionIndex >= 0; positionIndex--)
   {
      if(PositionGetSymbol(positionIndex) != _Symbol)
         continue;
      const ulong ticket = PositionGetTicket(positionIndex);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != LQ_EXPERT_MAGIC)
         continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), prefix) == 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool V2HuntHasPendingOrdersForSession(const datetime huntSessionId)
{
   const string prefix = V2HuntTradeCommentPrefix(huntSessionId);
   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(orderState != ORDER_STATE_PLACED && orderState != ORDER_STATE_PARTIAL)
         continue;

      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT &&
         orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP &&
         orderType != ORDER_TYPE_BUY_STOP_LIMIT && orderType != ORDER_TYPE_SELL_STOP_LIMIT)
         continue;

      if(StringFind(OrderGetString(ORDER_COMMENT), prefix) == 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool ResolveHuntFvgOrderPlacementGate(const datetime formationTime, const datetime huntSessionId,
                                      bool &outReplacePendingOnly)
{
   outReplacePendingOnly = false;
   const int huntIndex = V2FindHuntSlotBySessionId(huntSessionId);

   if(V2HuntHasOpenPositionForSession(huntSessionId))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "hunt position open â€” one trade setup per hunt");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
void RegisterHuntTradeAfterSuccessfulPlace(const bool isBuy, const double entryPrice,
                                           const double takeProfitTp1Price,
                                           const double preEntryCancelTpLevel,
                                           const datetime fvgFormationTime,
                                           const datetime huntSessionId)
{
   const int huntIndex = V2FindHuntSlotBySessionId(huntSessionId);
   if(huntIndex >= 0)
   {
      g_v2Hunts[huntIndex].tradeOrdersActive      = true;
      g_v2Hunts[huntIndex].ordersFvgFormationTime = fvgFormationTime;
      g_v2Hunts[huntIndex].tradeIsBuy             = isBuy;
      g_v2Hunts[huntIndex].tradeEntryPrice        = entryPrice;
      g_v2Hunts[huntIndex].tradeTp1Price          = takeProfitTp1Price;
      g_v2Hunts[huntIndex].preEntryCancelTpLevel  = preEntryCancelTpLevel;
      g_v2Hunts[huntIndex].firstOppBosMgmtDone    = false;
   }
   g_huntTradeOrdersActive           = true;
   g_huntOrdersFvgFormationTime      = fvgFormationTime;
   g_huntTradeIsBuy                  = isBuy;
   g_huntTradeEntryPrice             = entryPrice;
   g_huntPreEntryCancelTpLevel       = preEntryCancelTpLevel;
   g_huntTradeSessionCommentPrefix   = V2HuntTradeCommentPrefix(huntSessionId);
   g_huntFirstOppBosMgmtDone         = false;
   ArmHuntM15TpWatchAtTradeEntry(isBuy);
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Bull: bid > top+1% M2 chart rng â†’ BuyLimit @ top+1%; else market buy.          |
//| Bear: ask < lowâˆ’1% M2 chart rng â†’ SellLimit @ lowâˆ’1%; else market sell.         |
//+------------------------------------------------------------------+
// Latest completed H4 same-dir leg (MTF SMC). TP = 0.9x / 1.4x / 1.9x from entry.
double M2PendingStopEntryPrice(const bool isBuy, const double referenceEntryPrice)
{
   if(referenceEntryPrice <= 0.0)
      return 0.0;

   const double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pointSize <= 0.0)
      return 0.0;

   int offsetPoints = InputPendingStopEntryOffsetPoints;
   if(offsetPoints < 1)
      offsetPoints = 1;
   else if(offsetPoints > 2)
      offsetPoints = 2;

   const double offsetPrice = (double)offsetPoints * pointSize;
   double stopEntry = isBuy
                      ? referenceEntryPrice + offsetPrice
                      : referenceEntryPrice - offsetPrice;
   stopEntry = NormalizeDouble(stopEntry, _Digits);

   const int stopsLevelPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double minDistance   = (double)stopsLevelPoints * pointSize;
   const double ask           = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid           = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(isBuy)
   {
      const double minBuyStop = ask + minDistance;
      if(stopEntry <= minBuyStop)
         stopEntry = NormalizeDouble(minBuyStop + offsetPrice, _Digits);
   }
   else
   {
      const double maxSellStop = bid - minDistance;
      if(stopEntry >= maxSellStop)
         stopEntry = NormalizeDouble(maxSellStop - offsetPrice, _Digits);
   }

   return stopEntry;
}

//+------------------------------------------------------------------+
double ResolveTradeEntryPriceForOrderType(const bool isBuy, const double referenceEntryPrice)
{
   if(referenceEntryPrice <= 0.0)
      return 0.0;

   switch(InputTradeEntryOrderType)
   {
      case TRADE_ENTRY_ORDER_MARKET:
      {
         double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                    : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(marketPrice <= 0.0)
            marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_LAST)
                                : SymbolInfoDouble(_Symbol, SYMBOL_LAST);
         return (marketPrice > 0.0 ? NormalizeDouble(marketPrice, _Digits) : 0.0);
      }
      case TRADE_ENTRY_ORDER_STOP:
         return M2PendingStopEntryPrice(isBuy, referenceEntryPrice);
      case TRADE_ENTRY_ORDER_LIMIT:
      default:
         return NormalizeDouble(referenceEntryPrice, _Digits);
   }
}

//+------------------------------------------------------------------+
bool TradeEntryOrderTypeIsPending(const ENUM_TRADE_ENTRY_ORDER_TYPE orderType)
{
   return (orderType == TRADE_ENTRY_ORDER_LIMIT || orderType == TRADE_ENTRY_ORDER_STOP);
}

//+------------------------------------------------------------------+
bool ValidateTradeOrderEntryVsStop(const bool isBuy, const double orderEntry, const double stopLoss,
                                    string &outReason)
{
   outReason = "";
   if(orderEntry <= 0.0)
   {
      outReason = "order entry invalid";
      return false;
   }
   if(isBuy && orderEntry <= stopLoss)
   {
      outReason = StringFormat("buy entry<=SL entry=%.5f sl=%.5f", orderEntry, stopLoss);
      return false;
   }
   if(!isBuy && orderEntry >= stopLoss)
   {
      outReason = StringFormat("sell entry>=SL entry=%.5f sl=%.5f", orderEntry, stopLoss);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool HasOurHuntPendingEntryOrders(const datetime huntSessionId)
{
   const string sessionPrefix =
      (huntSessionId != 0 ? V2HuntTradeCommentPrefix(huntSessionId) : "");

   for(int orderIndex = OrdersTotal() - 1; orderIndex >= 0; orderIndex--)
   {
      const ulong ticket = OrderGetTicket(orderIndex);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != LQ_EXPERT_MAGIC)
         continue;

      const ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
      if(orderState != ORDER_STATE_PLACED && orderState != ORDER_STATE_PARTIAL)
         continue;

      const ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(orderType != ORDER_TYPE_BUY_LIMIT && orderType != ORDER_TYPE_SELL_LIMIT &&
         orderType != ORDER_TYPE_BUY_STOP && orderType != ORDER_TYPE_SELL_STOP &&
         orderType != ORDER_TYPE_BUY_STOP_LIMIT && orderType != ORDER_TYPE_SELL_STOP_LIMIT)
         continue;

      const string comment = OrderGetString(ORDER_COMMENT);
      if(StringFind(comment, "LQ2_HS") != 0)
         continue;
      if(sessionPrefix != "" && StringFind(comment, sessionPrefix) != 0)
         continue;

      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void ClearPendingEntryOrderExpiry()
{
   g_pendingEntryOrderExpiryDeadline = 0;
   g_pendingEntryOrderExpirySessionId = 0;
   if(g_pendingEntryOrderExpiryTimerOn && !HasOurHuntPendingEntryOrders(0))
   {
      EventKillTimer();
      g_pendingEntryOrderExpiryTimerOn = false;
   }
}

//+------------------------------------------------------------------+
void ArmPendingEntryOrderExpiry(const datetime huntSessionId)
{
   if(InputPendingOrderExpirySeconds <= 0)
      return;
   if(!TradeEntryOrderTypeIsPending(InputTradeEntryOrderType))
      return;

   g_pendingEntryOrderExpiryDeadline  = TimeCurrent() + (datetime)InputPendingOrderExpirySeconds;
   g_pendingEntryOrderExpirySessionId = huntSessionId;

   if(!g_pendingEntryOrderExpiryTimerOn)
   {
      EventSetTimer(1);
      g_pendingEntryOrderExpiryTimerOn = true;
   }
}

//+------------------------------------------------------------------+
void ProcessPendingEntryOrderExpiry()
{
   if(g_pendingEntryOrderExpiryDeadline == 0)
      return;

   if(TimeCurrent() < g_pendingEntryOrderExpiryDeadline)
   {
      if(!HasOurHuntPendingEntryOrders(g_pendingEntryOrderExpirySessionId))
         ClearPendingEntryOrderExpiry();
      return;
   }

   if(!HasOurHuntPendingEntryOrders(g_pendingEntryOrderExpirySessionId))
   {
      ClearPendingEntryOrderExpiry();
      return;
   }

   CancelOurHuntPendingOrders(g_pendingEntryOrderExpirySessionId);
   LogHuntEvent("PENDING_EXPIRE",
                StringFormat("HS%lld cancelled unfilled pendings after %d sec orderType=%d",
                             (long)g_pendingEntryOrderExpirySessionId,
                             InputPendingOrderExpirySeconds,
                             (int)InputTradeEntryOrderType));
   ClearPendingEntryOrderExpiry();
}

//+------------------------------------------------------------------+
void FinalizeTradePlacementBatch(const bool isBuy, const double orderEntry, const double tp1,
                                  const double farthestTp, const datetime formationTime,
                                  const datetime huntSessionId, const int placedCount)
{
   if(placedCount <= 0)
      return;

   if(TradeEntryOrderTypeIsPending(InputTradeEntryOrderType))
      ArmPendingEntryOrderExpiry(huntSessionId);

   RegisterHuntTradeAfterSuccessfulPlace(isBuy, orderEntry, tp1, farthestTp, formationTime,
                                         huntSessionId);
}

//+------------------------------------------------------------------+
bool PlaceOneFvgTradeOrder(const bool isBuy, const ENUM_TRADE_ENTRY_ORDER_TYPE orderType,
                           const double entryPrice, const double stopLossPrice, const double takeProfitPrice,
                           const double volume, const string comment, const double setupScore,
                           ulong &outOrderTicket, ulong &outPositionId)
{
   outOrderTicket  = 0;
   outPositionId   = 0;
   if(volume <= 0.0)
   {
      LogHuntEvent("TRADE_ORDER_FAIL", StringFormat("%s volume=0", comment));
      return false;
   }

   g_trade.SetExpertMagicNumber(LQ_EXPERT_MAGIC);
   g_trade.SetDeviationInPoints(30);
   ApplyTradeFillingModeFromSymbol();

   bool ok = false;
   switch(orderType)
   {
      case TRADE_ENTRY_ORDER_MARKET:
         if(isBuy)
            ok = g_trade.Buy(volume, _Symbol, 0.0, stopLossPrice, takeProfitPrice, comment);
         else
            ok = g_trade.Sell(volume, _Symbol, 0.0, stopLossPrice, takeProfitPrice, comment);
         break;

      case TRADE_ENTRY_ORDER_STOP:
         if(isBuy)
            ok = g_trade.BuyStop(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                                 ORDER_TIME_GTC, 0, comment);
         else
            ok = g_trade.SellStop(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                                  ORDER_TIME_GTC, 0, comment);
         break;

      case TRADE_ENTRY_ORDER_LIMIT:
      default:
         if(isBuy)
            ok = g_trade.BuyLimit(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                                  ORDER_TIME_GTC, 0, comment);
         else
            ok = g_trade.SellLimit(volume, entryPrice, _Symbol, stopLossPrice, takeProfitPrice,
                                   ORDER_TIME_GTC, 0, comment);
         break;
   }

   if(!ok)
      LogHuntEvent("TRADE_ORDER_FAIL",
                   StringFormat("%s type=%d ret=%d %s", comment, (int)orderType,
                                (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
   else
      LogHuntEvent("TRADE_ORDER",
                   StringFormat("type=%d setupScore=%.2f %s %s entry=%.5f",
                                (int)orderType, setupScore,
                                isBuy ? "buy" : "sell", comment, entryPrice));

   if(ok)
   {
      outOrderTicket = g_trade.ResultOrder();
      const ulong dealTicket = g_trade.ResultDeal();
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
         outPositionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   }

   return ok;
}

//+------------------------------------------------------------------+
bool PlaceFvgTradeOrderForSetup(const bool isBuy, const double referenceEntryPrice,
                                 const double stopLossPrice, const double takeProfitPrice,
                                 const double volume, const string comment, const double setupScore,
                                 ulong &outOrderTicket, ulong &outPositionId)
{
   const double entryPrice = ResolveTradeEntryPriceForOrderType(isBuy, referenceEntryPrice);
   if(entryPrice <= 0.0)
   {
      LogHuntEvent("TRADE_ORDER_FAIL", StringFormat("%s entry resolve failed", comment));
      return false;
   }

   return PlaceOneFvgTradeOrder(isBuy, InputTradeEntryOrderType, entryPrice,
                                stopLossPrice, takeProfitPrice, volume, comment, setupScore,
                                outOrderTicket, outPositionId);
}

//+------------------------------------------------------------------+
double ComputeDoubleRiskTakeProfitPrice(const bool isBuy, const double entryPrice,
                                         const double stopLossPrice)
{
   const double slDistance = MathAbs(entryPrice - stopLossPrice);
   if(slDistance <= 0.0)
      return 0.0;

   if(isBuy)
      return NormalizeDouble(entryPrice + 2.0 * slDistance, _Digits);
   return NormalizeDouble(entryPrice - 2.0 * slDistance, _Digits);
}

//+------------------------------------------------------------------+
bool TryPlaceFvgTradeDoubleRiskAddonOrder(const bool isBuy, const double referenceEntryPrice,
                                           const double stopLossPrice,
                                           const string huntCommentPrefix, const string formationTag,
                                           int &inOutPlacedCount, int &inOutZeroVolumeCount,
                                           const double setupScore,
                                           const int setupLogIndex = -1)
{
   const double orderEntry =
      ResolveTradeEntryPriceForOrderType(isBuy, referenceEntryPrice);
   const double takeProfit2R =
      ComputeDoubleRiskTakeProfitPrice(isBuy, orderEntry, stopLossPrice);
   if(takeProfit2R <= 0.0)
      return false;

   if(!StopsDistanceAllowed(isBuy, orderEntry, stopLossPrice, takeProfit2R))
      return false;

   const string comment2R = StringFormat("%sOV_2R_%s", huntCommentPrefix, formationTag);
   const double volume2R  =
      GetOptimizedLotSize(orderEntry, stopLossPrice, setupScore, isBuy, 1.0);
   if(volume2R <= 0.0)
   {
      inOutZeroVolumeCount++;
      return false;
   }

   ulong orderTicket  = 0;
   ulong positionId   = 0;
   if(!PlaceFvgTradeOrderForSetup(isBuy, referenceEntryPrice, stopLossPrice, takeProfit2R,
                                  volume2R, comment2R, setupScore, orderTicket, positionId))
      return false;

   inOutPlacedCount++;
   return true;
}

//+------------------------------------------------------------------+
bool IsFvgAutomatedTradingAllowed(string &outBlockReason)
{
   outBlockReason = "";
   if(!InputEnableAutomatedTrading)
   {
      outBlockReason = "InputEnableAutomatedTrading=false (log only)";
      return false;
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      outBlockReason = "terminal AutoTrading off";
      return false;
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      outBlockReason = "EA trading not allowed on this chart";
      return false;
   }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      outBlockReason = "ACCOUNT_TRADE_EXPERT disabled";
      return false;
   }
   const long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      outBlockReason = "symbol trading disabled";
      return false;
   }
   if(IsMidnightBlackoutHour())
   {
      outBlockReason = "midnight hour blackout (00:00-01:00 server)";
      return false;
   }
   return true;
}

bool TryPlaceEngulfAbsorptionTradeSetup(const int huntIndex, const bool isBuy,
                                         const double entryPrice, const double stopLossPrice,
                                         const datetime signalBarOpenTime,
                                         const datetime huntSessionId,
                                         const double setupScore,
                                         const int setupLogIndex = -1)
{
   if(ScoreLogWriteModeSkipsTrading())
      return false;

   if(signalBarOpenTime == 0)
      return false;
   if(huntIndex >= V2_MAX_HUNT_SESSIONS)
      return false;

   if(!SetupScoreAllowsTradeEntry(setupScore))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("setupScore=%.2f <= min %.2f",
                                  setupScore, GetMinScoreThreshold()));
      return false;
   }

   string bosBiasBlockReason = "";
   if(!FvgTradeAllowedByH4BosBias(isBuy, bosBiasBlockReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", bosBiasBlockReason);
      return false;
   }

   bool replacePendingOnly = false;
   if(!ResolveHuntFvgOrderPlacementGate(signalBarOpenTime, huntSessionId, replacePendingOnly))
      return false;

   const double normalizedEntry = NormalizeDouble(entryPrice, _Digits);
   const double referenceEntry  = normalizedEntry;
   double stopLoss = NormalizeDouble(stopLossPrice, _Digits);
   if(!ApplyTouchVolMinimumSlDistance(isBuy, referenceEntry, stopLoss))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "engulf SL distance invalid");
      return false;
   }

   const double orderEntry =
      ResolveTradeEntryPriceForOrderType(isBuy, referenceEntry);
   string entrySideReason = "";
   if(!ValidateTradeOrderEntryVsStop(isBuy, orderEntry, stopLoss, entrySideReason))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", entrySideReason);
      return false;
   }

   double takeProfitPrices[];
   int    takeProfitCount = 0;
   if(!BuildTradeSwingGroupTakeProfits(isBuy, signalBarOpenTime, orderEntry,
                                       stopLoss, takeProfitPrices, takeProfitCount))
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                     StringFormat("no swing-group TP with min R:R %.2f entry=%.5f sl=%.5f",
                                  InputTradeSwingTpMinRewardToRisk, orderEntry, stopLoss));
      return false;
   }

   for(int tpIndex = 0; tpIndex < takeProfitCount; tpIndex++)
   {
      if(!StopsDistanceAllowed(isBuy, orderEntry, stopLoss, takeProfitPrices[tpIndex]))
      {
         V2LogHuntEvent(huntIndex, "TRADE_SKIP",
                          StringFormat("broker stops level tp=%d", tpIndex + 1));
         return false;
      }
   }

   if(InputBaseRiskUsd <= 0.0)
   {
      V2LogHuntEvent(huntIndex, "TRADE_SKIP", "InputBaseRiskUsd invalid");
      return false;
   }

   double tpRiskWeights[];
   double riskTotalParts = 0.0;
   GetTradeSwingTpRiskWeights(takeProfitCount, tpRiskWeights, riskTotalParts);
   const string huntCommentPrefix = V2HuntTradeCommentPrefix(huntSessionId);
   const string formationTag      = TimeToString(signalBarOpenTime, TIME_DATE | TIME_MINUTES);
   const string logDetail =
      StringFormat("buy=%s ref=%.5f orderEntry=%.5f sl=%.5f type=%d signal=%s score=%.2f",
                   isBuy ? "Y" : "N", referenceEntry, orderEntry, stopLoss,
                   (int)InputTradeEntryOrderType, formationTag, setupScore);

   string tradeBlockReason = "";
   if(!IsFvgAutomatedTradingAllowed(tradeBlockReason))
   {
      LogHuntEvent("TRADE_PLAN", logDetail + " | " + tradeBlockReason);
      return false;
   }

   int placedCount    = 0;
   int zeroVolumeCount = 0;

   for(int tpIndex = 0; tpIndex < takeProfitCount; tpIndex++)
   {
      const string commentOv =
         StringFormat("%sOV_TP%d_%s", huntCommentPrefix, tpIndex + 1, formationTag);
      const double riskFraction = tpRiskWeights[tpIndex] / riskTotalParts;
      const double volumeOv =
         GetOptimizedLotSize(orderEntry, stopLoss, setupScore, isBuy, riskFraction);
      if(volumeOv <= 0.0)
         zeroVolumeCount++;
      else
      {
         ulong orderTicket = 0;
         ulong positionId  = 0;
         if(PlaceFvgTradeOrderForSetup(isBuy, referenceEntry,
                                       stopLoss, takeProfitPrices[tpIndex], volumeOv,
                                       commentOv, setupScore, orderTicket, positionId))
         {
            placedCount++;
         }
      }
   }

   TryPlaceFvgTradeDoubleRiskAddonOrder(isBuy, referenceEntry, stopLoss,
                                         huntCommentPrefix, formationTag, placedCount,
                                         zeroVolumeCount, setupScore, setupLogIndex);

   const int orderTargetCount = takeProfitCount + 1;
   if(placedCount > 0)
   {
      const double farthestTp = takeProfitPrices[takeProfitCount - 1];
      FinalizeTradePlacementBatch(isBuy, orderEntry, takeProfitPrices[0],
                                  farthestTp, signalBarOpenTime, huntSessionId, placedCount);
      LogHuntEvent("TRADE_PLACE",
                   StringFormat("ENG_%s placed=%d/%d %s", formationTag, placedCount,
                                orderTargetCount, logDetail));
      return true;
   }

   V2LogHuntEvent(huntIndex, "TRADE_FAIL",
                  StringFormat("ENG_%s zeroVol=%d %s", formationTag, zeroVolumeCount, logDetail));
   return false;
}

//+------------------------------------------------------------------+

#endif // H4_LQ_V3_TRADEEXECUTION
