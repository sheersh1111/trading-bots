//+------------------------------------------------------------------+
//| plot_swing_m2.mq5                                                |
//| M2 BOS-opposite FVG + M15 BOS gate + H4 demand/supply path OR       |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.38"

#include <Trade\Trade.mqh>

CTrade tradeLayer;

const ENUM_TIMEFRAMES SwingTimeframe = PERIOD_M2;

input bool InputSwitchChartToMinuteTwo = true;   // Set chart period to M2 on attach
input bool InputDrawSwingLegVisuals = false;      // Swing leg OBJ_TREND + High/Low labels (off)

input group "BOS opposite FVG (M2: bar 1 vs bar 3)"
input bool InputDrawBosOppositeFairValueGapZones = true; // Rectangles for BOS-qualified FVG only
input double InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg = 15.0; // Cancel FVG watch if close exceeds this % of chart height past broken leg (0 = off)
input int  InputChartRangeBarCount = 147;        // Bars for chart height (FVG min-gap filter)
input double InputFairValueGapMinimumPercentOfChartRange = 2.0; // Min gap as % of height (0 = off)
input int  InputMaximumFairValueGapRectangles = 120;

input group "H4 alignment (HTF buffers — visuals + trade gate)"
input bool   InputEnableHtfTradeGate = true;       // M15 BOS + H4 demand/supply path & price OR
input bool   InputHtfAllowCounterTrendFvg = false; // If false: M15 BOS must match FVG (no bull-M15 + bear-FVG etc.)
input double InputH4AlignmentBufferPercentOfChartRange = 3.5; // ±% of H4 chart-range height around levels
input int    InputH4ChartRangeBarCount = 80;         // H4 bars for height reference (buffer + FVG min-gap)
input int    InputH4MaxSwingLegsToScan = 6;        // Newest N H4 legs for buffer band drawing
input bool   InputDrawH4DemandSupplyZones = false; // Padded H4 demand vs supply (matches gate OR bands)
input color  InputH4DemandZoneDrawColor = clrPaleGreen;
input color  InputH4SupplyZoneDrawColor = clrThistle;
input bool   InputDrawH4AlignmentBufferZones = false; // Legacy undifferentiated bands (if demand/supply off)
input color  InputH4AlignmentBufferLegZoneColor = clrPaleGreen;
input color  InputH4AlignmentBufferFvgZoneColor = clrThistle;
input bool   InputDrawH4FairValueGapZones = true;  // H4 FVG rectangles (bar 1 vs bar 3)
input bool   InputPrintHtfTradeDecision = true;    // Log YES/NO for HTF gate on M2 BOS-FVG bar
input int    InputHtfWarmupBarsOnInit = 147;       // 0=off: on attach, replay last N M15/H4 bars into swing + H4 FVG memory

input group "M15 plot (HTF context on M2 chart)"
input bool   InputDrawM15SwingLegVisuals = true;    // M15 leg OBJ_TREND + High/Low labels
input color  InputM15SwingTrendLineColor = clrGold;
input bool   InputDrawM15FairValueGapZones = true; // M15 FVG rectangles (bar 1 vs 3, same min-% as M2)

input group "FVG trade (M2)"
input bool   InputEnableAutomatedTrading = true;   // Send market/limit orders (false = log only)
input ulong  InputExpertMagicNumber = 940031;
input double InputRiskPercentPerTrade = 1.0;       // %% of balance for this setup; split 50/50 between 2R and 3R legs
input double InputFvgStopBufferPercentOfM2Range = 3.0; // SL padding beyond FVG edge / path (%% of M2 range height)
input int    InputFvgPlanAMaxM2BarShift = 3;      // Plan A while iBarShift(FVG) <= this (then Plan B path SL)
input int    InputFvgTradeMaxM2BarShift = 24;     // Stop trade attempts when FVG bar is older than this shift

// --- swing structs (detect_swing logic) ---
struct Swing
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection; // 1 = up, -1 = down, 0 = unset
};

struct SwingState
{
   Swing    currentSwingLeg;
   Swing    swingHistory[20];
   int      swingHistoryCount;
   double   priceAnchorLevel;
};

struct LiquidityPool
{
   double poolLowPrice;
   double poolHighPrice;
   bool   isSupplyPool; // true = resistance / supply, false = demand
};

#define LiquidityPoolCapacity 32

struct BosOppositeFairValueGapMemory
{
   bool     isBullishFairValueGap;
   double   fairValueGapZoneLowPrice;
   double   fairValueGapZoneHighPrice;
   datetime fairValueGapBarOpenTime;
   double   bosBarClosePrice;
   double   pathMinLowSinceBos;
   double   pathMaxHighSinceBos;
};

#define BosOppositeFairValueGapMemoryCapacity 32

struct BosOppositeFvgWatch
{
   int      counter;
   bool     expectsBullishFairValueGap; // true = expect bullish FVG (after bearish BOS)
   bool     skipDecrementOnce;          // no countdown tick on the bar where BOS was detected
   double   bosLegLevelPrice;           // broken swing high (bull BOS) or low (bear BOS)
   double   maxCloseSinceBos;           // bull BOS: running max close vs leg high (impulse filter)
   double   minCloseSinceBos;           // bear BOS: running min close vs leg low (impulse filter)
   datetime bosM2BarOpenTime;
   double   bosBarClosePrice;
   double   pathMinLowSinceBos;
   double   pathMaxHighSinceBos;
};

#define BosOppositeFvgWatchCapacity 32

SwingState     globalSwingState;
LiquidityPool  globalLiquidityPools[LiquidityPoolCapacity];
int            globalLiquidityPoolCount = 0;

datetime globalLastSwingTimeframeBarOpenTime = 0;
int      globalBosMarkedFairValueGapRectangleSequence = 0;

BosOppositeFvgWatch globalBosOppositeFvgWatchList[BosOppositeFvgWatchCapacity];
int                   globalBosOppositeFvgWatchCount = 0;

BosOppositeFairValueGapMemory globalBosOppositeFairValueGapMemory[BosOppositeFairValueGapMemoryCapacity];
int                           globalBosOppositeFairValueGapMemoryCount = 0;

#define FvgPlanAStopHitFormationCapacity 64
datetime globalFvgPlanAStopHitFormations[FvgPlanAStopHitFormationCapacity];
int      globalFvgPlanAStopHitFormationCount = 0;

struct M15FairValueGapMemory
{
   bool     isBullishFairValueGap;
   double   fairValueGapZoneLowPrice;
   double   fairValueGapZoneHighPrice;
   datetime formationBarOpenTime;
};

#define M15FairValueGapMemoryCapacity 32

SwingState globalM15SwingState;
datetime   globalLastM15BarOpenForContext = 0;
M15FairValueGapMemory globalM15FairValueGapMemory[M15FairValueGapMemoryCapacity];
int                   globalM15FairValueGapMemoryCount = 0;
int                   globalM15FairValueGapPlotSequence = 0;

int globalM15LatestBosDirection = 0; // 1 = last M15 BOS bullish, -1 = bearish, 0 = none yet

SwingState globalH4SwingState;
datetime   globalLastH4BarOpenForContext = 0;

struct H4FairValueGapMemory
{
   bool     isBullishFairValueGap;
   double   fairValueGapZoneLowPrice;
   double   fairValueGapZoneHighPrice;
   datetime formationBarOpenTime;
   datetime thirdBarOpenTime; // bar 3 of FVG pattern (rectangle left anchor)
};

#define H4FairValueGapMemoryCapacity 32

H4FairValueGapMemory globalH4FairValueGapMemory[H4FairValueGapMemoryCapacity];
int                  globalH4FairValueGapMemoryCount = 0;
int                  globalH4FairValueGapPlotSequence = 0;

int globalH4LatestBosDirection = 0; // 1 = last H4 BOS bullish, -1 = bearish, 0 = none yet

const string ChartObjectNamePrefixSwingTrendLine = "M2_Swing_";
const string ChartObjectNamePrefixSwingLabelText = "M2_SWLBL_";
const string ChartObjectNamePrefixBosMarkedFairValueGap = "M2_FVG_BOS_";
const string ChartObjectNamePrefixBosFvgTypeLabel = "M2_FVG_TYPE_";
const string ChartObjectNamePrefixM15SwingTrendLine     = "M15_Swing_";
const string ChartObjectNamePrefixM15SwingLabelText     = "M15_SWLBL_";
const string ChartObjectNamePrefixM15MemoryFairValueGap = "M15_FVG_";
const string ChartObjectNamePrefixH4MemoryFairValueGap = "H4_FVG_";
const string ChartObjectNamePrefixH4AlignmentBuffer    = "H4_ALIGNBUF_";
const string ChartObjectNamePrefixH4DemandSupply       = "H4_DSD_";
const string ChartObjectNamePrefixHtfDirectionHud    = "M2_HTF_HUD_";

void   ProcessSwingStep(SwingState &swingState, const ENUM_TIMEFRAMES timeframe);
void   SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                     const double highPrice, const double lowPrice, const int lastClosedBarShift = 1);
void   SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice);
void   SwingClose(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                  const string chartObjectNamePrefix);
void   DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                         const double labelPrice, const bool isUplegSwingDirection);

void   PushLiquidityPoolFromClosedSwing(const double poolLowPrice, const double poolHighPrice,
                                        const bool isSupplyPool);

double ReferenceChartHeightForFairValueGapFilter(const ENUM_TIMEFRAMES timeframe);
bool   FairValueGapGapMeetsMinimumPercentOfRange(const ENUM_TIMEFRAMES timeframe,
                                                 const double zoneLowPrice, const double zoneHighPrice);
bool   DetectFairValueGapOnLastClosedBar(bool &isBullishFairValueGap, double &fairValueGapZoneLowPrice,
                                       double &fairValueGapZoneHighPrice);
bool   TryDetectBreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap,
                                               double &outBosLegLevelPrice);
void   RemoveBosOppositeFvgWatchAt(const int removeIndex);
void   PushBosOppositeFvgWatch(const bool expectsBullishFairValueGap, const double bosLegLevelPrice);
bool   HasAnyActiveBosOppositeFvgWatch();
int    FindFirstMatchingBosFvgWatchIndex(const bool isBullishFairValueGap);
void   ProcessBosOppositeFvgWatchDecrements();
void   ProcessBosOppositeFvgWatchImpulseInvalidation();
void   ProcessBosOppositeFairValueGapWindow();
void   PushBosOppositeFairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                        const double zoneHighPrice, const datetime fairValueGapBarOpenTime,
                                        const double bosBarClosePrice, const double pathMinLowSinceBos,
                                        const double pathMaxHighSinceBos);
void   DrawBosMarkedFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                     const double zoneHighPrice, const datetime leftBarTime,
                                     const datetime rightBarTime);
bool   GetBosOppositeFairValueGapFromMemoryForBarOpenTime(const datetime barOpenTime,
                                                        bool &outIsBullishFairValueGap,
                                                        double &outZoneLowPrice,
                                                        double &outZoneHighPrice,
                                                        double &outBosBarClosePrice,
                                                        double &outPathMinLowSinceBos,
                                                        double &outPathMaxHighSinceBos);

double CalculateVolumeForFixedUsdRisk(const ENUM_ORDER_TYPE orderType, const double entryPrice,
                                      const double stopLossPrice, const double riskAccountCurrency);
void   ApplyTradeFillingModeFromSymbol();
bool   StopsDistanceAllowed(const bool isBuy, const double entryPrice, const double stopLossPrice,
                            const double takeProfitPrice);

void   TryExecuteFairValueGapTradePlan();

double M2FairValueGapStopBufferPrice();
bool   HasOurFvgOpenPositionOnSymbol();
bool   HasOurFvgPendingForFormation(const datetime formationTime);
int    GetOurFvgPendingPlanKindForFormation(const datetime formationTime);
void   CancelOurFvgPendingOrdersForFormation(const datetime formationTime);

bool   TryParseFormationTimeFromM2FvgOrderComment(const string &comment, datetime &outFormation);
void   RegisterFvgPlanAStopLossHit(const datetime formationTime);
bool   IsFvgPlanBSkippedAfterPlanAStopHit(const datetime formationTime);

void   UpdateBosOppositeFvgWatchPathExtremes();
void   ProcessM15ContextOnNewM15Bar();
void   SwingCloseM15Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                            const int lastClosedBarShift = 1);
void   ProcessM15SwingStep(const int lastClosedBarShift = 1);
bool   DetectFairValueGapOnLastClosedBarForTf(const ENUM_TIMEFRAMES tf, bool &isBullishFairValueGap,
                                              double &fairValueGapZoneLowPrice,
                                              double &fairValueGapZoneHighPrice);
bool   PushM15FairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                 const double zoneHighPrice, const datetime formationBarOpenTime);
void   ProcessM15FairValueGapMemoryOnly();
void   DrawM15MemoryFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                     const double zoneHighPrice, const datetime leftBarTime,
                                     const datetime rightBarTime);
void   DrawH4AlignmentBufferZones();
void   DrawH4DemandSupplyZones();
double H4ReferenceHeightFromChartRangeBars();
double H4BufferBandHalfWidth();
datetime H4RectRightFromAnchor(const datetime timeAnchor);

void   ProcessH4ContextOnNewH4Bar();
void   SwingCloseH4Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                           const int lastClosedBarShift = 1);
void   ProcessH4SwingStep(const int lastClosedBarShift = 1);
bool   PushH4FairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                const double zoneHighPrice, const datetime formationBarOpenTime,
                                const datetime thirdBarOpenTime);
void   DrawAllH4FairValueGapMemoryFromStore();
void   ProcessH4FairValueGapMemoryOnly(const int lastClosedBarShift = 1, const bool skipChartDraw = false);
void   DrawH4MemoryFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                    const double zoneHighPrice, const datetime leftBarTime,
                                    const datetime rightBarTime);

bool   TryDetectM15BreakOfStructureOnLastClosedBar(bool &outM15BosIsBullish, const int closeShift = 1);
bool   TryDetectH4BreakOfStructureOnLastClosedBar(bool &outH4BosIsBullish, const int closeShift = 1);
void   WarmupHtfContextFromHistory();
void   UpdateHtfDirectionHud();

bool   FairValueGapGapMeetsMinimumPercentOfH4Range(const double zoneLowPrice,
                                                    const double zoneHighPrice);

datetime SwingAnchorTime(const Swing &s);
bool   H4GetSecondLastCompletedUpLeg(double &outLevel, datetime &outAnchor);
bool   H4GetSecondLastCompletedDownLeg(double &outLevel, datetime &outAnchor);
bool   PriceInH4DemandBands(const double price);
bool   PriceInH4SupplyBands(const double price);
void   PathOverlapsH4DemandSupplyBands(const double pathMinLow, const double pathMaxHigh,
                                       bool &outDemandHit, bool &outSupplyHit,
                                       datetime &outNewestDemandAnchor, datetime &outNewestSupplyAnchor);
bool   PassesHtfTradeGate(const bool isBullishFairValueGap, const double pathMinLowSinceBos,
                          const double pathMaxHighSinceBos, string &outReason);

//+------------------------------------------------------------------+
int OnInit()
{
   tradeLayer.SetExpertMagicNumber(InputExpertMagicNumber);

   if(InputSwitchChartToMinuteTwo)
   {
      ChartSetSymbolPeriod(0, _Symbol, SwingTimeframe);
      ChartRedraw(0);
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("plot_swing_m2: enable AutoTrading in terminal to send orders.");
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      Print("plot_swing_m2: trading not allowed for this EA (Common / account).");

   ObjectsDeleteAll(0, "M2_SWEEP_", -1, -1);
   ObjectsDeleteAll(0, "M2_FVG_", -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingLabelText, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15MemoryFairValueGap, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4MemoryFairValueGap, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4AlignmentBuffer, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4DemandSupply, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixHtfDirectionHud, -1, -1);

   WarmupHtfContextFromHistory();

   UpdateHtfDirectionHud();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int deinitializationReason)
{
   ObjectsDeleteAll(0, ChartObjectNamePrefixSwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixSwingLabelText, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixBosMarkedFairValueGap, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixBosFvgTypeLabel, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingTrendLine, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15SwingLabelText, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixM15MemoryFairValueGap, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4MemoryFairValueGap, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4AlignmentBuffer, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixH4DemandSupply, -1, -1);
   ObjectsDeleteAll(0, ChartObjectNamePrefixHtfDirectionHud, -1, -1);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InputExpertMagicNumber)
      return;
   if((ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON) != DEAL_REASON_SL)
      return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;

   const string dealComment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   datetime     formationTime = 0;
   if(TryParseFormationTimeFromM2FvgOrderComment(dealComment, formationTime))
   {
      RegisterFvgPlanAStopLossHit(formationTime);
      return;
   }

   const ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(positionId == 0)
      return;
   if(!HistorySelectByPosition(positionId))
      return;
   const int dealsTotal = HistoryDealsTotal();
   for(int i = dealsTotal - 1; i >= 0; i--)
   {
      const ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;
      if(!HistoryDealSelect(dealTicket))
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InputExpertMagicNumber)
         continue;
      const string openComment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
      if(TryParseFormationTimeFromM2FvgOrderComment(openComment, formationTime))
      {
         RegisterFvgPlanAStopLossHit(formationTime);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Top-right HUD: M15 last BOS (↑/↓). H4 only if HTF gate on and    |
//| globalH4LatestBosDirection != 0 (otherwise H4 label removed).     |
//+------------------------------------------------------------------+
void UpdateHtfDirectionHud()
{
   const string nameM15 = ChartObjectNamePrefixHtfDirectionHud + "M15";
   const string nameH4  = ChartObjectNamePrefixHtfDirectionHud + "H4";

   string arrowM15 = "—";
   color  colM15   = clrSilver;
   if(globalM15LatestBosDirection == 1)
   {
      arrowM15 = "↑";
      colM15   = clrLime;
   }
   else if(globalM15LatestBosDirection == -1)
   {
      arrowM15 = "↓";
      colM15   = clrTomato;
   }

   if(ObjectFind(0, nameM15) < 0)
   {
      ObjectCreate(0, nameM15, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nameM15, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, nameM15, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, nameM15, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nameM15, OBJPROP_HIDDEN, true);
      ObjectSetString(0, nameM15, OBJPROP_FONT, "Arial Bold");
   }
   ObjectSetInteger(0, nameM15, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, nameM15, OBJPROP_YDISTANCE, 18);
   ObjectSetInteger(0, nameM15, OBJPROP_FONTSIZE, 11);
   ObjectSetString(0, nameM15, OBJPROP_TEXT, "M15 " + arrowM15);
   ObjectSetInteger(0, nameM15, OBJPROP_COLOR, colM15);

   const bool h4HudActive =
      InputEnableHtfTradeGate && (globalH4LatestBosDirection == 1 || globalH4LatestBosDirection == -1);

   if(!h4HudActive)
   {
      if(ObjectFind(0, nameH4) >= 0)
         ObjectDelete(0, nameH4);
      return;
   }

   string arrowH4 = (globalH4LatestBosDirection == 1) ? "↑" : "↓";
   color  colH4   = (globalH4LatestBosDirection == 1) ? clrLime : clrTomato;

   if(ObjectFind(0, nameH4) < 0)
   {
      ObjectCreate(0, nameH4, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nameH4, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, nameH4, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0, nameH4, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nameH4, OBJPROP_HIDDEN, true);
      ObjectSetString(0, nameH4, OBJPROP_FONT, "Arial Bold");
   }
   ObjectSetInteger(0, nameH4, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, nameH4, OBJPROP_YDISTANCE, 38);
   ObjectSetInteger(0, nameH4, OBJPROP_FONTSIZE, 11);
   ObjectSetString(0, nameH4, OBJPROP_TEXT, "H4 " + arrowH4);
   ObjectSetInteger(0, nameH4, OBJPROP_COLOR, colH4);
}

//+------------------------------------------------------------------+
void OnTick()
{
   const datetime h4BarOpenTime = iTime(_Symbol, PERIOD_H4, 0);
   if(h4BarOpenTime != globalLastH4BarOpenForContext)
   {
      globalLastH4BarOpenForContext = h4BarOpenTime;
      ProcessH4ContextOnNewH4Bar();
   }

   const datetime m15BarOpenTime = iTime(_Symbol, PERIOD_M15, 0);
   if(m15BarOpenTime != globalLastM15BarOpenForContext)
   {
      globalLastM15BarOpenForContext = m15BarOpenTime;
      ProcessM15ContextOnNewM15Bar();
   }

   UpdateHtfDirectionHud();

   const datetime currentBarOpenTime = iTime(_Symbol, SwingTimeframe, 0);
   if(currentBarOpenTime == globalLastSwingTimeframeBarOpenTime)
      return;

   globalLastSwingTimeframeBarOpenTime = currentBarOpenTime;
   UpdateBosOppositeFvgWatchPathExtremes();
   ProcessSwingStep(globalSwingState, SwingTimeframe);
   ProcessBosOppositeFairValueGapWindow();
   TryExecuteFairValueGapTradePlan();
}

//+------------------------------------------------------------------+
void PushLiquidityPoolFromClosedSwing(const double poolLowPrice, const double poolHighPrice,
                                      const bool isSupplyPool)
{
   if(poolLowPrice >= poolHighPrice)
      return;

   if(globalLiquidityPoolCount < LiquidityPoolCapacity)
   {
      globalLiquidityPools[globalLiquidityPoolCount].poolLowPrice  = poolLowPrice;
      globalLiquidityPools[globalLiquidityPoolCount].poolHighPrice = poolHighPrice;
      globalLiquidityPools[globalLiquidityPoolCount].isSupplyPool   = isSupplyPool;
      globalLiquidityPoolCount++;
   }
   else
   {
      for(int poolShiftIndex = 1; poolShiftIndex < LiquidityPoolCapacity; poolShiftIndex++)
         globalLiquidityPools[poolShiftIndex - 1] = globalLiquidityPools[poolShiftIndex];
      globalLiquidityPools[LiquidityPoolCapacity - 1].poolLowPrice  = poolLowPrice;
      globalLiquidityPools[LiquidityPoolCapacity - 1].poolHighPrice = poolHighPrice;
      globalLiquidityPools[LiquidityPoolCapacity - 1].isSupplyPool  = isSupplyPool;
   }
}

//+------------------------------------------------------------------+
void ProcessSwingStep(SwingState &swingState, const ENUM_TIMEFRAMES timeframe)
{
   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, 1);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, 1);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, 1);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, 1);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);
   const double lastClosedBarRange = lastClosedBarHigh - lastClosedBarLow;

   if(swingState.currentSwingLeg.swingDirection == 0)
   {
      SwingStartNew(swingState, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      return;
   }

   double sumRangeFivePriorBars = 0.0;
   for(int barShiftIndex = 2; barShiftIndex <= 6; barShiftIndex++)
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, barShiftIndex) - iLow(_Symbol, timeframe, barShiftIndex));
   const double averageRangeFiveBars = sumRangeFivePriorBars / 5.0;

   const bool isDecentMovement = (lastClosedBarRange > (averageRangeFiveBars * 1.0));
   if(isDecentMovement && candleDirection == swingState.currentSwingLeg.swingDirection)
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

   int nextSwingDirection = swingState.currentSwingLeg.swingDirection;
   if(swingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < swingState.priceAnchorLevel)
      nextSwingDirection = -1;
   else if(swingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > swingState.priceAnchorLevel)
      nextSwingDirection = 1;

   if(nextSwingDirection == swingState.currentSwingLeg.swingDirection)
   {
      SwingExtend(swingState, lastClosedBarHigh, lastClosedBarLow);
   }
   else
   {
      const color  swingLineColor = clrYellow;
      const string chartObjectNamePrefix = ChartObjectNamePrefixSwingTrendLine;
      SwingClose(swingState, timeframe, swingLineColor, chartObjectNamePrefix);

      Swing closedSwingLeg = swingState.swingHistory[swingState.swingHistoryCount - 1];
      double newSwingLegHigh = lastClosedBarHigh;
      double newSwingLegLow  = lastClosedBarLow;
      if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
         newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
      else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
         newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

      SwingStartNew(swingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow);
      swingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
   }
}

//+------------------------------------------------------------------+
void SwingStartNew(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const int swingDirection,
                   const double highPrice, const double lowPrice, const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.swingDirection = swingDirection;
   swingState.currentSwingLeg.legHighPrice   = highPrice;
   swingState.currentSwingLeg.legLowPrice    = lowPrice;
   swingState.currentSwingLeg.legStartTime   = iTime(_Symbol, timeframe, lastClosedBarShift);
}

//+------------------------------------------------------------------+
void SwingExtend(SwingState &swingState, const double highPrice, const double lowPrice)
{
   if(highPrice > swingState.currentSwingLeg.legHighPrice)
      swingState.currentSwingLeg.legHighPrice = highPrice;
   if(lowPrice < swingState.currentSwingLeg.legLowPrice)
      swingState.currentSwingLeg.legLowPrice = lowPrice;
}

//+------------------------------------------------------------------+
void SwingClose(SwingState &swingState, const ENUM_TIMEFRAMES timeframe, const color swingLineColor,
                const string chartObjectNamePrefix)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, 1);

   const double poolLowPrice  = swingState.currentSwingLeg.legLowPrice;
   const double poolHighPrice = swingState.currentSwingLeg.legHighPrice;
   const bool   isSupplyPool  = (swingState.currentSwingLeg.swingDirection == 1);
   PushLiquidityPoolFromClosedSwing(poolLowPrice, poolHighPrice, isSupplyPool);

   const string chartObjectName =
      chartObjectNamePrefix + IntegerToString((long)swingState.currentSwingLeg.legEndTime);

   double trendLineStartPrice;
   double trendLineEndPrice;
   if(swingState.currentSwingLeg.swingDirection == 1)
   {
      trendLineStartPrice = swingState.currentSwingLeg.legLowPrice;
      trendLineEndPrice   = swingState.currentSwingLeg.legHighPrice;
   }
   else
   {
      trendLineStartPrice = swingState.currentSwingLeg.legHighPrice;
      trendLineEndPrice   = swingState.currentSwingLeg.legLowPrice;
   }

   if(InputDrawSwingLegVisuals)
   {
      if(ObjectCreate(0, chartObjectName, OBJ_TREND, 0, swingState.currentSwingLeg.legStartTime,
                      trendLineStartPrice, swingState.currentSwingLeg.legEndTime, trendLineEndPrice))
      {
         ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, swingLineColor);
         ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, chartObjectName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
      }

      const bool isUplegSwingDirection = (swingState.currentSwingLeg.swingDirection == 1);
      DrawSwingLegLabel(ChartObjectNamePrefixSwingLabelText, swingState.currentSwingLeg.legEndTime,
                        trendLineEndPrice, isUplegSwingDirection);
   }

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
void DrawSwingLegLabel(const string chartObjectNamePrefix, const datetime labelBarTime,
                       const double labelPrice, const bool isUplegSwingDirection)
{
   const string chartObjectName = chartObjectNamePrefix + IntegerToString((long)labelBarTime);
   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);

   const double symbolPointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double labelVerticalOffset =
      isUplegSwingDirection ? (labelPrice + symbolPointSize * 8.0) : (labelPrice - symbolPointSize * 8.0);

   if(!ObjectCreate(0, chartObjectName, OBJ_TEXT, 0, labelBarTime, labelVerticalOffset))
      return;

   ObjectSetString(0, chartObjectName, OBJPROP_TEXT, isUplegSwingDirection ? "High" : "Low");
   ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, isUplegSwingDirection ? clrDodgerBlue : clrOrange);
   ObjectSetInteger(0, chartObjectName, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, chartObjectName, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, chartObjectName, OBJPROP_ANCHOR,
                    isUplegSwingDirection ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void SwingCloseM15Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                          const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   if(InputDrawM15SwingLegVisuals)
   {
      const string chartObjectName =
         ChartObjectNamePrefixM15SwingTrendLine + IntegerToString((long)swingState.currentSwingLeg.legEndTime);

      double trendLineStartPrice;
      double trendLineEndPrice;
      if(swingState.currentSwingLeg.swingDirection == 1)
      {
         trendLineStartPrice = swingState.currentSwingLeg.legLowPrice;
         trendLineEndPrice   = swingState.currentSwingLeg.legHighPrice;
      }
      else
      {
         trendLineStartPrice = swingState.currentSwingLeg.legHighPrice;
         trendLineEndPrice   = swingState.currentSwingLeg.legLowPrice;
      }

      if(ObjectCreate(0, chartObjectName, OBJ_TREND, 0, swingState.currentSwingLeg.legStartTime,
                      trendLineStartPrice, swingState.currentSwingLeg.legEndTime, trendLineEndPrice))
      {
         ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, InputM15SwingTrendLineColor);
         ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, chartObjectName, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
      }

      const bool isUplegSwingDirection = (swingState.currentSwingLeg.swingDirection == 1);
      DrawSwingLegLabel(ChartObjectNamePrefixM15SwingLabelText, swingState.currentSwingLeg.legEndTime,
                        trendLineEndPrice, isUplegSwingDirection);
   }

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
void ProcessM15SwingStep(const int lastClosedBarShift = 1)
{
   const ENUM_TIMEFRAMES timeframe = PERIOD_M15;
   const int         sh            = lastClosedBarShift;

   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, sh);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, sh);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, sh);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, sh);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);
   const double lastClosedBarRange = lastClosedBarHigh - lastClosedBarLow;

   if(globalM15SwingState.currentSwingLeg.swingDirection == 0)
   {
      SwingStartNew(globalM15SwingState, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow, sh);
      globalM15SwingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      return;
   }

   double sumRangeFivePriorBars = 0.0;
   for(int k = 1; k <= 5; k++)
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, sh + k) - iLow(_Symbol, timeframe, sh + k));
   const double averageRangeFiveBars = sumRangeFivePriorBars / 5.0;

   const bool isDecentMovement = (lastClosedBarRange > (averageRangeFiveBars * 1.0));
   if(isDecentMovement && candleDirection == globalM15SwingState.currentSwingLeg.swingDirection)
      globalM15SwingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

   int nextSwingDirection = globalM15SwingState.currentSwingLeg.swingDirection;
   if(globalM15SwingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < globalM15SwingState.priceAnchorLevel)
      nextSwingDirection = -1;
   else if(globalM15SwingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > globalM15SwingState.priceAnchorLevel)
      nextSwingDirection = 1;

   if(nextSwingDirection == globalM15SwingState.currentSwingLeg.swingDirection)
   {
      SwingExtend(globalM15SwingState, lastClosedBarHigh, lastClosedBarLow);
   }
   else
   {
      SwingCloseM15Context(globalM15SwingState, timeframe, sh);

      Swing closedSwingLeg = globalM15SwingState.swingHistory[globalM15SwingState.swingHistoryCount - 1];
      double newSwingLegHigh = lastClosedBarHigh;
      double newSwingLegLow  = lastClosedBarLow;
      if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
         newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
      else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
         newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

      SwingStartNew(globalM15SwingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow, sh);
      globalM15SwingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
   }
}

//+------------------------------------------------------------------+
// M15 FVG: detect bar-1 vs bar-3, push memory, draw M15_FVG_* — disabled; HTF legs only in memory.
bool PushM15FairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                               const double zoneHighPrice, const datetime formationBarOpenTime)
{
   /*
   for(int memoryIndex = 0; memoryIndex < globalM15FairValueGapMemoryCount; memoryIndex++)
   {
      if(globalM15FairValueGapMemory[memoryIndex].formationBarOpenTime == formationBarOpenTime)
         return false;
   }

   if(globalM15FairValueGapMemoryCount < M15FairValueGapMemoryCapacity)
   {
      const int idx = globalM15FairValueGapMemoryCount;
      globalM15FairValueGapMemory[idx].isBullishFairValueGap   = isBullishFairValueGap;
      globalM15FairValueGapMemory[idx].fairValueGapZoneLowPrice  = zoneLowPrice;
      globalM15FairValueGapMemory[idx].fairValueGapZoneHighPrice = zoneHighPrice;
      globalM15FairValueGapMemory[idx].formationBarOpenTime  = formationBarOpenTime;
      globalM15FairValueGapMemoryCount++;
      return true;
   }

   for(int shiftIndex = 1; shiftIndex < M15FairValueGapMemoryCapacity; shiftIndex++)
      globalM15FairValueGapMemory[shiftIndex - 1] = globalM15FairValueGapMemory[shiftIndex];

   const int lastIndex = M15FairValueGapMemoryCapacity - 1;
   globalM15FairValueGapMemory[lastIndex].isBullishFairValueGap   = isBullishFairValueGap;
   globalM15FairValueGapMemory[lastIndex].fairValueGapZoneLowPrice  = zoneLowPrice;
   globalM15FairValueGapMemory[lastIndex].fairValueGapZoneHighPrice = zoneHighPrice;
   globalM15FairValueGapMemory[lastIndex].formationBarOpenTime  = formationBarOpenTime;
   return true;
   */
   return false;
}

//+------------------------------------------------------------------+
void DrawM15MemoryFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                    const double zoneHighPrice, const datetime leftBarTime,
                                    const datetime rightBarTime)
{
   /*
   if(!InputDrawM15FairValueGapZones)
      return;

   globalM15FairValueGapPlotSequence++;
   const string chartObjectName =
      ChartObjectNamePrefixM15MemoryFairValueGap + IntegerToString(globalM15FairValueGapPlotSequence);
   if(globalM15FairValueGapPlotSequence > InputMaximumFairValueGapRectangles)
   {
      const string oldRectangleName =
         ChartObjectNamePrefixM15MemoryFairValueGap +
         IntegerToString(globalM15FairValueGapPlotSequence - InputMaximumFairValueGapRectangles);
      ObjectDelete(0, oldRectangleName);
   }

   const datetime rectangleTimeLeft  = (leftBarTime <= rightBarTime) ? leftBarTime : rightBarTime;
   const datetime rectangleTimeRight = (leftBarTime <= rightBarTime) ? rightBarTime : leftBarTime;
   const double rectanglePriceLow    = MathMin(zoneLowPrice, zoneHighPrice);
   const double rectanglePriceHigh   = MathMax(zoneLowPrice, zoneHighPrice);

   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);

   if(!ObjectCreate(0, chartObjectName, OBJ_RECTANGLE, 0, rectangleTimeLeft, rectanglePriceHigh,
                    rectangleTimeRight, rectanglePriceLow))
      return;

   const color zoneColor = isBullishFairValueGap ? clrDeepSkyBlue : clrOrchid;
   ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, chartObjectName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, chartObjectName, OBJPROP_BACK, true);
   ObjectSetInteger(0, chartObjectName, OBJPROP_FILL, true);
   ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, true);
   */
}

//+------------------------------------------------------------------+
void ProcessM15FairValueGapMemoryOnly()
{
   /*
   bool isBullishFairValueGap;
   double fairValueGapZoneLowPrice;
   double fairValueGapZoneHighPrice;
   if(!DetectFairValueGapOnLastClosedBarForTf(PERIOD_M15, isBullishFairValueGap, fairValueGapZoneLowPrice,
                                              fairValueGapZoneHighPrice))
      return;

   const datetime formationBarOpenTime = iTime(_Symbol, PERIOD_M15, 1);
   const datetime thirdBarOpenTime     = iTime(_Symbol, PERIOD_M15, 3);
   if(!PushM15FairValueGapMemory(isBullishFairValueGap, fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                                 formationBarOpenTime))
      return;

   DrawM15MemoryFairValueGapZone(isBullishFairValueGap, fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                                 thirdBarOpenTime, formationBarOpenTime);
   */
}

//+------------------------------------------------------------------+
void ProcessM15ContextOnNewM15Bar()
{
   ProcessM15SwingStep();

   bool m15BosIsBullish = false;
   if(TryDetectM15BreakOfStructureOnLastClosedBar(m15BosIsBullish))
      globalM15LatestBosDirection = m15BosIsBullish ? 1 : -1;
}

//+------------------------------------------------------------------+
double H4ReferenceHeightFromChartRangeBars()
{
   const int barCount = InputH4ChartRangeBarCount;
   if(barCount < 1)
      return 0.0;

   const int totalBars = iBars(_Symbol, PERIOD_H4);
   if(totalBars < barCount + 1)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = 1; barShiftIndex <= barCount; barShiftIndex++)
   {
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, PERIOD_H4, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, PERIOD_H4, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

//+------------------------------------------------------------------+
double H4BufferBandHalfWidth()
{
   const double ref = H4ReferenceHeightFromChartRangeBars();
   if(ref <= 0.0)
      return 0.0;
   return ref * (InputH4AlignmentBufferPercentOfChartRange / 100.0);
}

//+------------------------------------------------------------------+
//| Rectangle time width: 3 H4 candles from anchor (capped to now).  |
//+------------------------------------------------------------------+
datetime H4RectRightFromAnchor(const datetime timeAnchor)
{
   const long spanSec = (long)PeriodSeconds(PERIOD_H4) * 3;
   datetime   tr      = (datetime)((long)timeAnchor + spanSec);
   const datetime now = TimeCurrent();
   if(tr > now)
      tr = now;
   if((long)tr <= (long)timeAnchor)
      tr = (datetime)((long)timeAnchor + 1);
   return tr;
}

//+------------------------------------------------------------------+
bool FairValueGapGapMeetsMinimumPercentOfH4Range(const double zoneLowPrice, const double zoneHighPrice)
{
   if(InputFairValueGapMinimumPercentOfChartRange <= 0.0)
      return true;

   const double gapSize = MathAbs(zoneHighPrice - zoneLowPrice);
   if(gapSize <= 0.0)
      return false;

   const double referenceHeight = H4ReferenceHeightFromChartRangeBars();
   if(referenceHeight <= 0.0)
      return true;

   return (gapSize >= referenceHeight * (InputFairValueGapMinimumPercentOfChartRange / 100.0));
}

//+------------------------------------------------------------------+
void SwingCloseH4Context(SwingState &swingState, const ENUM_TIMEFRAMES timeframe,
                         const int lastClosedBarShift = 1)
{
   swingState.currentSwingLeg.legEndTime = iTime(_Symbol, timeframe, lastClosedBarShift);

   if(swingState.swingHistoryCount < 20)
   {
      swingState.swingHistory[swingState.swingHistoryCount] = swingState.currentSwingLeg;
      swingState.swingHistoryCount++;
   }
   else
   {
      for(int swingHistoryIndex = 1; swingHistoryIndex < 20; swingHistoryIndex++)
         swingState.swingHistory[swingHistoryIndex - 1] = swingState.swingHistory[swingHistoryIndex];
      swingState.swingHistory[19] = swingState.currentSwingLeg;
   }
}

//+------------------------------------------------------------------+
void ProcessH4SwingStep(const int lastClosedBarShift = 1)
{
   const ENUM_TIMEFRAMES timeframe = PERIOD_H4;
   const int         sh            = lastClosedBarShift;

   const double lastClosedBarOpen  = iOpen(_Symbol, timeframe, sh);
   const double lastClosedBarClose = iClose(_Symbol, timeframe, sh);
   const double lastClosedBarHigh  = iHigh(_Symbol, timeframe, sh);
   const double lastClosedBarLow   = iLow(_Symbol, timeframe, sh);

   const int candleDirection =
      (lastClosedBarClose > lastClosedBarOpen) ? 1
      : ((lastClosedBarClose < lastClosedBarOpen) ? -1 : 0);
   const double lastClosedBarRange = lastClosedBarHigh - lastClosedBarLow;

   if(globalH4SwingState.currentSwingLeg.swingDirection == 0)
   {
      SwingStartNew(globalH4SwingState, timeframe, candleDirection, lastClosedBarHigh, lastClosedBarLow, sh);
      globalH4SwingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
      return;
   }

   double sumRangeFivePriorBars = 0.0;
   for(int k = 1; k <= 5; k++)
      sumRangeFivePriorBars +=
         (iHigh(_Symbol, timeframe, sh + k) - iLow(_Symbol, timeframe, sh + k));
   const double averageRangeFiveBars = sumRangeFivePriorBars / 5.0;

   const bool isDecentMovement = (lastClosedBarRange > (averageRangeFiveBars * 1.0));
   if(isDecentMovement && candleDirection == globalH4SwingState.currentSwingLeg.swingDirection)
      globalH4SwingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;

   int nextSwingDirection = globalH4SwingState.currentSwingLeg.swingDirection;
   if(globalH4SwingState.currentSwingLeg.swingDirection == 1 && lastClosedBarClose < globalH4SwingState.priceAnchorLevel)
      nextSwingDirection = -1;
   else if(globalH4SwingState.currentSwingLeg.swingDirection == -1 && lastClosedBarClose > globalH4SwingState.priceAnchorLevel)
      nextSwingDirection = 1;

   if(nextSwingDirection == globalH4SwingState.currentSwingLeg.swingDirection)
   {
      SwingExtend(globalH4SwingState, lastClosedBarHigh, lastClosedBarLow);
   }
   else
   {
      SwingCloseH4Context(globalH4SwingState, timeframe, sh);

      Swing closedSwingLeg = globalH4SwingState.swingHistory[globalH4SwingState.swingHistoryCount - 1];
      double newSwingLegHigh = lastClosedBarHigh;
      double newSwingLegLow  = lastClosedBarLow;
      if(closedSwingLeg.swingDirection == 1 && nextSwingDirection == -1)
         newSwingLegHigh = MathMax(lastClosedBarHigh, closedSwingLeg.legHighPrice);
      else if(closedSwingLeg.swingDirection == -1 && nextSwingDirection == 1)
         newSwingLegLow = MathMin(lastClosedBarLow, closedSwingLeg.legLowPrice);

      SwingStartNew(globalH4SwingState, timeframe, nextSwingDirection, newSwingLegHigh, newSwingLegLow, sh);
      globalH4SwingState.priceAnchorLevel = (lastClosedBarHigh + lastClosedBarLow) / 2.0;
   }
}

//+------------------------------------------------------------------+
bool PushH4FairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                              const double zoneHighPrice, const datetime formationBarOpenTime,
                              const datetime thirdBarOpenTime)
{
   for(int memoryIndex = 0; memoryIndex < globalH4FairValueGapMemoryCount; memoryIndex++)
   {
      if(globalH4FairValueGapMemory[memoryIndex].formationBarOpenTime == formationBarOpenTime)
         return false;
   }

   if(globalH4FairValueGapMemoryCount < H4FairValueGapMemoryCapacity)
   {
      const int idx = globalH4FairValueGapMemoryCount;
      globalH4FairValueGapMemory[idx].isBullishFairValueGap   = isBullishFairValueGap;
      globalH4FairValueGapMemory[idx].fairValueGapZoneLowPrice  = zoneLowPrice;
      globalH4FairValueGapMemory[idx].fairValueGapZoneHighPrice = zoneHighPrice;
      globalH4FairValueGapMemory[idx].formationBarOpenTime  = formationBarOpenTime;
      globalH4FairValueGapMemory[idx].thirdBarOpenTime      = thirdBarOpenTime;
      globalH4FairValueGapMemoryCount++;
      return true;
   }

   for(int shiftIndex = 1; shiftIndex < H4FairValueGapMemoryCapacity; shiftIndex++)
      globalH4FairValueGapMemory[shiftIndex - 1] = globalH4FairValueGapMemory[shiftIndex];

   const int lastIndex = H4FairValueGapMemoryCapacity - 1;
   globalH4FairValueGapMemory[lastIndex].isBullishFairValueGap   = isBullishFairValueGap;
   globalH4FairValueGapMemory[lastIndex].fairValueGapZoneLowPrice  = zoneLowPrice;
   globalH4FairValueGapMemory[lastIndex].fairValueGapZoneHighPrice = zoneHighPrice;
   globalH4FairValueGapMemory[lastIndex].formationBarOpenTime  = formationBarOpenTime;
   globalH4FairValueGapMemory[lastIndex].thirdBarOpenTime      = thirdBarOpenTime;
   return true;
}

//+------------------------------------------------------------------+
void DrawH4MemoryFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                  const double zoneHighPrice, const datetime leftBarTime,
                                  const datetime rightBarTime)
{
   if(!InputDrawH4FairValueGapZones)
      return;

   globalH4FairValueGapPlotSequence++;
   const string chartObjectName =
      ChartObjectNamePrefixH4MemoryFairValueGap + IntegerToString(globalH4FairValueGapPlotSequence);
   if(globalH4FairValueGapPlotSequence > InputMaximumFairValueGapRectangles)
   {
      const string oldRectangleName =
         ChartObjectNamePrefixH4MemoryFairValueGap +
         IntegerToString(globalH4FairValueGapPlotSequence - InputMaximumFairValueGapRectangles);
      ObjectDelete(0, oldRectangleName);
   }

   const datetime rectangleTimeLeft  = (leftBarTime <= rightBarTime) ? leftBarTime : rightBarTime;
   const datetime rectangleTimeRight = (leftBarTime <= rightBarTime) ? rightBarTime : leftBarTime;
   const double rectanglePriceLow    = MathMin(zoneLowPrice, zoneHighPrice);
   const double rectanglePriceHigh   = MathMax(zoneLowPrice, zoneHighPrice);

   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);

   if(!ObjectCreate(0, chartObjectName, OBJ_RECTANGLE, 0, rectangleTimeLeft, rectanglePriceHigh,
                    rectangleTimeRight, rectanglePriceLow))
      return;

   const color zoneColor = isBullishFairValueGap ? clrDeepSkyBlue : clrOrchid;
   ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, chartObjectName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, chartObjectName, OBJPROP_BACK, true);
   ObjectSetInteger(0, chartObjectName, OBJPROP_FILL, true);
   ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void DrawAllH4FairValueGapMemoryFromStore()
{
   if(!InputDrawH4FairValueGapZones)
      return;

   for(int i = 0; i < globalH4FairValueGapMemoryCount; i++)
   {
      const datetime t3 = globalH4FairValueGapMemory[i].thirdBarOpenTime;
      const datetime t1 = globalH4FairValueGapMemory[i].formationBarOpenTime;
      if(t3 == 0 || t1 == 0)
         continue;

      DrawH4MemoryFairValueGapZone(globalH4FairValueGapMemory[i].isBullishFairValueGap,
                                   globalH4FairValueGapMemory[i].fairValueGapZoneLowPrice,
                                   globalH4FairValueGapMemory[i].fairValueGapZoneHighPrice,
                                   t3, t1);
   }
}

//+------------------------------------------------------------------+
void ProcessH4FairValueGapMemoryOnly(const int lastClosedBarShift = 1, const bool skipChartDraw = false)
{
   bool isBullishFairValueGap;
   double fairValueGapZoneLowPrice;
   double fairValueGapZoneHighPrice;

   const int sh = lastClosedBarShift;

   const double lastClosedBarHigh = iHigh(_Symbol, PERIOD_H4, sh);
   const double lastClosedBarLow  = iLow(_Symbol, PERIOD_H4, sh);
   const double thirdBarHigh      = iHigh(_Symbol, PERIOD_H4, sh + 2);
   const double thirdBarLow       = iLow(_Symbol, PERIOD_H4, sh + 2);

   if(lastClosedBarLow > thirdBarHigh)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfH4Range(thirdBarHigh, lastClosedBarLow))
         return;
      isBullishFairValueGap = true;
      fairValueGapZoneLowPrice  = thirdBarHigh;
      fairValueGapZoneHighPrice = lastClosedBarLow;
   }
   else if(lastClosedBarHigh < thirdBarLow)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfH4Range(lastClosedBarHigh, thirdBarLow))
         return;
      isBullishFairValueGap = false;
      fairValueGapZoneLowPrice  = lastClosedBarHigh;
      fairValueGapZoneHighPrice = thirdBarLow;
   }
   else
      return;

   const datetime formationBarOpenTime = iTime(_Symbol, PERIOD_H4, sh);
   const datetime thirdBarOpenTime     = iTime(_Symbol, PERIOD_H4, sh + 2);
   if(!PushH4FairValueGapMemory(isBullishFairValueGap, fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                                formationBarOpenTime, thirdBarOpenTime))
      return;

   if(!skipChartDraw)
      DrawH4MemoryFairValueGapZone(isBullishFairValueGap, fairValueGapZoneLowPrice, fairValueGapZoneHighPrice,
                                   thirdBarOpenTime, formationBarOpenTime);
}

//+------------------------------------------------------------------+
void ProcessH4ContextOnNewH4Bar()
{
   ProcessH4SwingStep();

   bool h4BosIsBullish = false;
   if(TryDetectH4BreakOfStructureOnLastClosedBar(h4BosIsBullish))
      globalH4LatestBosDirection = h4BosIsBullish ? 1 : -1;

   ProcessH4FairValueGapMemoryOnly();
   if(InputDrawH4DemandSupplyZones)
      DrawH4DemandSupplyZones();
   else if(InputDrawH4AlignmentBufferZones)
      DrawH4AlignmentBufferZones();
}

//+------------------------------------------------------------------+
void DrawH4AlignmentBufferZones()
{
   if(!InputDrawH4AlignmentBufferZones)
      return;

   ObjectsDeleteAll(0, ChartObjectNamePrefixH4AlignmentBuffer, -1, -1);

   const double buf = H4BufferBandHalfWidth();
   if(buf <= 0.0)
      return;

   int seq = 0;

   const int maxLegs = MathMin(InputH4MaxSwingLegsToScan, globalH4SwingState.swingHistoryCount);
   for(int k = 0; k < maxLegs; k++)
   {
      const Swing s = globalH4SwingState.swingHistory[globalH4SwingState.swingHistoryCount - 1 - k];
      const double lvl = (s.swingDirection == 1) ? s.legHighPrice : s.legLowPrice;
      const datetime timeLeft = MathMin(s.legStartTime, s.legEndTime);
      if(timeLeft >= TimeCurrent())
         continue;

      const double pLow  = lvl - buf;
      const double pHigh = lvl + buf;
      const string name  = ChartObjectNamePrefixH4AlignmentBuffer + "L" + IntegerToString(seq++);

      const datetime rectLeft  = timeLeft;
      const datetime rectRight = H4RectRightFromAnchor(timeLeft);

      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, rectLeft, pHigh, rectRight, pLow))
         continue;

      ObjectSetInteger(0, name, OBJPROP_COLOR, InputH4AlignmentBufferLegZoneColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   for(int i = 0; i < globalH4FairValueGapMemoryCount; i++)
   {
      const double lo = globalH4FairValueGapMemory[i].fairValueGapZoneLowPrice;
      const double hi = globalH4FairValueGapMemory[i].fairValueGapZoneHighPrice;
      const double pLow  = MathMin(lo, hi) - buf;
      const double pHigh = MathMax(lo, hi) + buf;
      const datetime timeLeft = globalH4FairValueGapMemory[i].formationBarOpenTime;
      if(timeLeft >= TimeCurrent())
         continue;

      const string name = ChartObjectNamePrefixH4AlignmentBuffer + "F" + IntegerToString(seq++);

      const datetime rectLeft  = timeLeft;
      const datetime rectRight = H4RectRightFromAnchor(timeLeft);

      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, rectLeft, pHigh, rectRight, pLow))
         continue;

      ObjectSetInteger(0, name, OBJPROP_COLOR, InputH4AlignmentBufferFvgZoneColor);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
void DrawH4DemandSupplyZones()
{
   if(!InputDrawH4DemandSupplyZones)
      return;

   ObjectsDeleteAll(0, ChartObjectNamePrefixH4DemandSupply, -1, -1);

   const double buf = H4BufferBandHalfWidth();
   if(buf <= 0.0)
      return;

   int seq = 0;

   for(int i = 0; i < globalH4FairValueGapMemoryCount; i++)
   {
      const double lo = globalH4FairValueGapMemory[i].fairValueGapZoneLowPrice;
      const double hi = globalH4FairValueGapMemory[i].fairValueGapZoneHighPrice;
      const double pLow  = MathMin(lo, hi) - buf;
      const double pHigh = MathMax(lo, hi) + buf;
      const datetime timeLeft = globalH4FairValueGapMemory[i].formationBarOpenTime;
      if(timeLeft >= TimeCurrent())
         continue;

      const bool   isDemand = globalH4FairValueGapMemory[i].isBullishFairValueGap;
      const color  clr      = isDemand ? InputH4DemandZoneDrawColor : InputH4SupplyZoneDrawColor;
      const string name =
         ChartObjectNamePrefixH4DemandSupply + (isDemand ? "D_F_" : "S_F_") + IntegerToString(seq++);

      const datetime rectLeft  = timeLeft;
      const datetime rectRight = H4RectRightFromAnchor(timeLeft);

      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, rectLeft, pHigh, rectRight, pLow))
         continue;

      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }

   const int legCount = globalH4SwingState.swingHistoryCount;
   for(int k = 0; k < legCount; k++)
   {
      const Swing s = globalH4SwingState.swingHistory[legCount - 1 - k];
      const datetime timeLeft = MathMin(s.legStartTime, s.legEndTime);
      if(timeLeft >= TimeCurrent())
         continue;

      if(s.swingDirection == -1)
      {
         const double lvl  = s.legLowPrice;
         const double pLow = lvl - buf;
         const double pHigh = lvl + buf;
         const string name =
            ChartObjectNamePrefixH4DemandSupply + "D_L_" + IntegerToString(seq++);

         const datetime rectLeft  = timeLeft;
         const datetime rectRight = H4RectRightFromAnchor(timeLeft);

         if(ObjectFind(0, name) >= 0)
            ObjectDelete(0, name);
         if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, rectLeft, pHigh, rectRight, pLow))
            continue;

         ObjectSetInteger(0, name, OBJPROP_COLOR, InputH4DemandZoneDrawColor);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
      else if(s.swingDirection == 1)
      {
         const double lvl  = s.legHighPrice;
         const double pLow = lvl - buf;
         const double pHigh = lvl + buf;
         const string name =
            ChartObjectNamePrefixH4DemandSupply + "S_L_" + IntegerToString(seq++);

         const datetime rectLeft  = timeLeft;
         const datetime rectRight = H4RectRightFromAnchor(timeLeft);

         if(ObjectFind(0, name) >= 0)
            ObjectDelete(0, name);
         if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, rectLeft, pHigh, rectRight, pLow))
            continue;

         ObjectSetInteger(0, name, OBJPROP_COLOR, InputH4SupplyZoneDrawColor);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
   }

   if(globalH4LatestBosDirection == 1)
   {
      double lvl = 0.0;
      datetime anc = 0;
      if(H4GetSecondLastCompletedUpLeg(lvl, anc))
      {
         const double pLow  = lvl - buf;
         const double pHigh = lvl + buf;
         const datetime timeLeft = anc;
         if(timeLeft < TimeCurrent())
         {
            const string name =
               ChartObjectNamePrefixH4DemandSupply + "D_2U_" + IntegerToString(seq++);

            const datetime rectLeft  = timeLeft;
            const datetime rectRight = H4RectRightFromAnchor(timeLeft);

            if(ObjectFind(0, name) >= 0)
               ObjectDelete(0, name);
            if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, rectLeft, pHigh, rectRight, pLow))
            {
               ObjectSetInteger(0, name, OBJPROP_COLOR, InputH4DemandZoneDrawColor);
               ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
               ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, name, OBJPROP_BACK, true);
               ObjectSetInteger(0, name, OBJPROP_FILL, true);
               ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
               ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
            }
         }
      }
   }

   if(globalH4LatestBosDirection == -1)
   {
      double lvl = 0.0;
      datetime anc = 0;
      if(H4GetSecondLastCompletedDownLeg(lvl, anc))
      {
         const double pLow  = lvl - buf;
         const double pHigh = lvl + buf;
         const datetime timeLeft = anc;
         if(timeLeft < TimeCurrent())
         {
            const string name =
               ChartObjectNamePrefixH4DemandSupply + "S_2D_" + IntegerToString(seq++);

            const datetime rectLeft  = timeLeft;
            const datetime rectRight = H4RectRightFromAnchor(timeLeft);

            if(ObjectFind(0, name) >= 0)
               ObjectDelete(0, name);
            if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, rectLeft, pHigh, rectRight, pLow))
            {
               ObjectSetInteger(0, name, OBJPROP_COLOR, InputH4SupplyZoneDrawColor);
               ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
               ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
               ObjectSetInteger(0, name, OBJPROP_BACK, true);
               ObjectSetInteger(0, name, OBJPROP_FILL, true);
               ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
               ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void UpdateBosOppositeFvgWatchPathExtremes()
{
   const double h1 = iHigh(_Symbol, SwingTimeframe, 1);
   const double l1 = iLow(_Symbol, SwingTimeframe, 1);

   for(int i = 0; i < globalBosOppositeFvgWatchCount; i++)
   {
      if(globalBosOppositeFvgWatchList[i].counter <= 0)
         continue;
      globalBosOppositeFvgWatchList[i].pathMinLowSinceBos =
         MathMin(globalBosOppositeFvgWatchList[i].pathMinLowSinceBos, l1);
      globalBosOppositeFvgWatchList[i].pathMaxHighSinceBos =
         MathMax(globalBosOppositeFvgWatchList[i].pathMaxHighSinceBos, h1);
   }
}

//+------------------------------------------------------------------+
double ReferenceChartHeightForFairValueGapFilter(const ENUM_TIMEFRAMES timeframe)
{
   const int barCount = InputChartRangeBarCount;
   if(barCount < 1)
      return 0.0;

   const int totalBars = iBars(_Symbol, timeframe);
   if(totalBars < barCount + 1)
      return 0.0;

   double highestHighPrice = -1.0e100;
   double lowestLowPrice   = 1.0e100;
   for(int barShiftIndex = 1; barShiftIndex <= barCount; barShiftIndex++)
   {
      highestHighPrice = MathMax(highestHighPrice, iHigh(_Symbol, timeframe, barShiftIndex));
      lowestLowPrice   = MathMin(lowestLowPrice, iLow(_Symbol, timeframe, barShiftIndex));
   }
   return highestHighPrice - lowestLowPrice;
}

//+------------------------------------------------------------------+
bool FairValueGapGapMeetsMinimumPercentOfRange(const ENUM_TIMEFRAMES timeframe,
                                               const double zoneLowPrice, const double zoneHighPrice)
{
   if(InputFairValueGapMinimumPercentOfChartRange <= 0.0)
      return true;

   const double gapSize = MathAbs(zoneHighPrice - zoneLowPrice);
   if(gapSize <= 0.0)
      return false;

   const double referenceHeight = ReferenceChartHeightForFairValueGapFilter(timeframe);
   if(referenceHeight <= 0.0)
      return true;

   return (gapSize >= referenceHeight * (InputFairValueGapMinimumPercentOfChartRange / 100.0));
}

//+------------------------------------------------------------------+
bool DetectFairValueGapOnLastClosedBar(bool &isBullishFairValueGap, double &fairValueGapZoneLowPrice,
                                       double &fairValueGapZoneHighPrice)
{
   return DetectFairValueGapOnLastClosedBarForTf(SwingTimeframe, isBullishFairValueGap,
                                                 fairValueGapZoneLowPrice, fairValueGapZoneHighPrice);
}

//+------------------------------------------------------------------+
bool DetectFairValueGapOnLastClosedBarForTf(const ENUM_TIMEFRAMES tf, bool &isBullishFairValueGap,
                                            double &fairValueGapZoneLowPrice,
                                            double &fairValueGapZoneHighPrice)
{
   isBullishFairValueGap = false;
   fairValueGapZoneLowPrice  = 0.0;
   fairValueGapZoneHighPrice = 0.0;

   const double lastClosedBarHigh = iHigh(_Symbol, tf, 1);
   const double lastClosedBarLow  = iLow(_Symbol, tf, 1);
   const double thirdBarHigh      = iHigh(_Symbol, tf, 3);
   const double thirdBarLow       = iLow(_Symbol, tf, 3);

   if(lastClosedBarLow > thirdBarHigh)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfRange(tf, thirdBarHigh, lastClosedBarLow))
         return false;
      isBullishFairValueGap = true;
      fairValueGapZoneLowPrice  = thirdBarHigh;
      fairValueGapZoneHighPrice = lastClosedBarLow;
      return true;
   }

   if(lastClosedBarHigh < thirdBarLow)
   {
      if(!FairValueGapGapMeetsMinimumPercentOfRange(tf, lastClosedBarHigh, thirdBarLow))
         return false;
      isBullishFairValueGap = false;
      fairValueGapZoneLowPrice  = lastClosedBarHigh;
      fairValueGapZoneHighPrice = thirdBarLow;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Bullish BOS: last closed bar close crosses above latest completed up-leg high.|
//| Bearish BOS: last closed bar close crosses below latest completed down-leg low.|
//| Each BOS queues its own opposite-FVG countdown (see PushBosOppositeFvgWatch). |
//+------------------------------------------------------------------+
bool TryDetectBreakOfStructureOnLastClosedBar(bool &outExpectsBullishFairValueGap,
                                             double &outBosLegLevelPrice)
{
   outExpectsBullishFairValueGap = false;
   outBosLegLevelPrice = 0.0;
   if(globalSwingState.swingHistoryCount < 1)
      return false;

   const double closePrice = iClose(_Symbol, SwingTimeframe, 1);
   const double prevClose  = iClose(_Symbol, SwingTimeframe, 2);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int historyIndex = globalSwingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(globalSwingState.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double swingLegHighPrice = globalSwingState.swingHistory[historyIndex].legHighPrice;
      if(closePrice > swingLegHighPrice + pointSize && prevClose <= swingLegHighPrice + pointSize)
      {
         outExpectsBullishFairValueGap = false;
         outBosLegLevelPrice           = swingLegHighPrice;
         return true;
      }
      break;
   }

   for(int historyIndex = globalSwingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(globalSwingState.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double swingLegLowPrice = globalSwingState.swingHistory[historyIndex].legLowPrice;
      if(closePrice < swingLegLowPrice - pointSize && prevClose >= swingLegLowPrice - pointSize)
      {
         outExpectsBullishFairValueGap = true;
         outBosLegLevelPrice           = swingLegLowPrice;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Latest M15 BOS: bull = close crosses above last completed up-leg high;|
//| bear = close crosses below last completed down-leg low (same close rules as M2).|
//+------------------------------------------------------------------+
bool TryDetectM15BreakOfStructureOnLastClosedBar(bool &outM15BosIsBullish, const int closeShift = 1)
{
   outM15BosIsBullish = false;
   if(globalM15SwingState.swingHistoryCount < 1)
      return false;

   const ENUM_TIMEFRAMES tf = PERIOD_M15;
   const double closePrice = iClose(_Symbol, tf, closeShift);
   const double prevClose  = iClose(_Symbol, tf, closeShift + 1);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int historyIndex = globalM15SwingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(globalM15SwingState.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double swingLegHighPrice = globalM15SwingState.swingHistory[historyIndex].legHighPrice;
      if(closePrice > swingLegHighPrice + pointSize && prevClose <= swingLegHighPrice + pointSize)
      {
         outM15BosIsBullish = true;
         return true;
      }
      break;
   }

   for(int historyIndex = globalM15SwingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(globalM15SwingState.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double swingLegLowPrice = globalM15SwingState.swingHistory[historyIndex].legLowPrice;
      if(closePrice < swingLegLowPrice - pointSize && prevClose >= swingLegLowPrice - pointSize)
      {
         outM15BosIsBullish = false;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
bool TryDetectH4BreakOfStructureOnLastClosedBar(bool &outH4BosIsBullish, const int closeShift = 1)
{
   outH4BosIsBullish = false;
   if(globalH4SwingState.swingHistoryCount < 1)
      return false;

   const ENUM_TIMEFRAMES tf = PERIOD_H4;
   const double closePrice = iClose(_Symbol, tf, closeShift);
   const double prevClose  = iClose(_Symbol, tf, closeShift + 1);
   const double pointSize  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int historyIndex = globalH4SwingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(globalH4SwingState.swingHistory[historyIndex].swingDirection != 1)
         continue;

      const double swingLegHighPrice = globalH4SwingState.swingHistory[historyIndex].legHighPrice;
      if(closePrice > swingLegHighPrice + pointSize && prevClose <= swingLegHighPrice + pointSize)
      {
         outH4BosIsBullish = true;
         return true;
      }
      break;
   }

   for(int historyIndex = globalH4SwingState.swingHistoryCount - 1; historyIndex >= 0; historyIndex--)
   {
      if(globalH4SwingState.swingHistory[historyIndex].swingDirection != -1)
         continue;

      const double swingLegLowPrice = globalH4SwingState.swingHistory[historyIndex].legLowPrice;
      if(closePrice < swingLegLowPrice - pointSize && prevClose >= swingLegLowPrice - pointSize)
      {
         outH4BosIsBullish = false;
         return true;
      }
      break;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Oldest→newest replay of bar indices [W..1]: fills M15/H4 swings, |
//| H4 FVG memory; final M15/H4 BOS from current closes. Sync stamps |
//| so OnTick does not double-run HTF context on the same bar.        |
//+------------------------------------------------------------------+
void WarmupHtfContextFromHistory()
{
   const int W = InputHtfWarmupBarsOnInit;
   if(W <= 0)
      return;

   const int minBars = W + 5 + 1;
   if(iBars(_Symbol, PERIOD_M15) < minBars || iBars(_Symbol, PERIOD_H4) < minBars)
   {
      Print("plot_swing_m2: HTF warmup skipped (need ", minBars, " M15/H4 bars; have M15=",
            iBars(_Symbol, PERIOD_M15), " H4=", iBars(_Symbol, PERIOD_H4), ")");
      return;
   }

   for(int sh = W; sh >= 1; sh--)
      ProcessM15SwingStep(sh);

   bool m15b = false;
   if(TryDetectM15BreakOfStructureOnLastClosedBar(m15b, 1))
      globalM15LatestBosDirection = m15b ? 1 : -1;

   for(int sh = W; sh >= 1; sh--)
   {
      ProcessH4SwingStep(sh);
      ProcessH4FairValueGapMemoryOnly(sh, true);
   }

   bool h4b = false;
   if(TryDetectH4BreakOfStructureOnLastClosedBar(h4b, 1))
      globalH4LatestBosDirection = h4b ? 1 : -1;

   globalLastM15BarOpenForContext = iTime(_Symbol, PERIOD_M15, 0);
   globalLastH4BarOpenForContext    = iTime(_Symbol, PERIOD_H4, 0);

   DrawAllH4FairValueGapMemoryFromStore();

   if(InputDrawH4DemandSupplyZones)
      DrawH4DemandSupplyZones();
   else if(InputDrawH4AlignmentBufferZones)
      DrawH4AlignmentBufferZones();
}

//+------------------------------------------------------------------+
void RemoveBosOppositeFvgWatchAt(const int removeIndex)
{
   if(removeIndex < 0 || removeIndex >= globalBosOppositeFvgWatchCount)
      return;
   for(int j = removeIndex + 1; j < globalBosOppositeFvgWatchCount; j++)
      globalBosOppositeFvgWatchList[j - 1] = globalBosOppositeFvgWatchList[j];
   globalBosOppositeFvgWatchCount--;
}

//+------------------------------------------------------------------+
void PushBosOppositeFvgWatch(const bool expectsBullishFairValueGap, const double bosLegLevelPrice)
{
   if(globalBosOppositeFvgWatchCount >= BosOppositeFvgWatchCapacity)
      RemoveBosOppositeFvgWatchAt(0);

   const double barClose = iClose(_Symbol, SwingTimeframe, 1);
   const double barHigh  = iHigh(_Symbol, SwingTimeframe, 1);
   const double barLow   = iLow(_Symbol, SwingTimeframe, 1);

   const int index = globalBosOppositeFvgWatchCount;
   globalBosOppositeFvgWatchList[index].counter                    = 4;
   globalBosOppositeFvgWatchList[index].expectsBullishFairValueGap = expectsBullishFairValueGap;
   globalBosOppositeFvgWatchList[index].skipDecrementOnce          = true;
   globalBosOppositeFvgWatchList[index].bosLegLevelPrice           = bosLegLevelPrice;
   globalBosOppositeFvgWatchList[index].bosM2BarOpenTime           = iTime(_Symbol, SwingTimeframe, 1);
   globalBosOppositeFvgWatchList[index].bosBarClosePrice           = barClose;
   globalBosOppositeFvgWatchList[index].pathMinLowSinceBos         = barLow;
   globalBosOppositeFvgWatchList[index].pathMaxHighSinceBos        = barHigh;
   if(expectsBullishFairValueGap)
   {
      globalBosOppositeFvgWatchList[index].minCloseSinceBos = barClose;
      globalBosOppositeFvgWatchList[index].maxCloseSinceBos = 0.0;
   }
   else
   {
      globalBosOppositeFvgWatchList[index].maxCloseSinceBos = barClose;
      globalBosOppositeFvgWatchList[index].minCloseSinceBos = 0.0;
   }
   globalBosOppositeFvgWatchCount++;
}

//+------------------------------------------------------------------+
bool HasAnyActiveBosOppositeFvgWatch()
{
   for(int i = 0; i < globalBosOppositeFvgWatchCount; i++)
   {
      if(globalBosOppositeFvgWatchList[i].counter > 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int FindFirstMatchingBosFvgWatchIndex(const bool isBullishFairValueGap)
{
   for(int i = 0; i < globalBosOppositeFvgWatchCount; i++)
   {
      if(globalBosOppositeFvgWatchList[i].counter <= 0)
         continue;
      const bool expectsBullish = globalBosOppositeFvgWatchList[i].expectsBullishFairValueGap;
      if((expectsBullish && isBullishFairValueGap) || (!expectsBullish && !isBullishFairValueGap))
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
void ProcessBosOppositeFvgWatchDecrements()
{
   for(int i = 0; i < globalBosOppositeFvgWatchCount; i++)
   {
      if(globalBosOppositeFvgWatchList[i].skipDecrementOnce)
      {
         globalBosOppositeFvgWatchList[i].skipDecrementOnce = false;
         continue;
      }
      if(globalBosOppositeFvgWatchList[i].counter > 0)
      {
         globalBosOppositeFvgWatchList[i].counter--;
         if(globalBosOppositeFvgWatchList[i].counter <= 0)
         {
            RemoveBosOppositeFvgWatchAt(i);
            i--;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Drop BOS–FVG watches if close moves more than X% of chart height past the broken leg.|
//| Bull BOS: invalidate when max(close) − legHigh > limit. Bear BOS: legLow − min(close) > limit.|
//+------------------------------------------------------------------+
void ProcessBosOppositeFvgWatchImpulseInvalidation()
{
   if(InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg <= 0.0)
      return;

   const double referenceHeight = ReferenceChartHeightForFairValueGapFilter(SwingTimeframe);
   if(referenceHeight <= 0.0)
      return;

   const double limitPrice =
      referenceHeight * (InputBosMaxImpulsePercentOfChartRangeBeforeOppositeFvg / 100.0);
   const double barClose = iClose(_Symbol, SwingTimeframe, 1);

   for(int i = 0; i < globalBosOppositeFvgWatchCount; i++)
   {
      if(globalBosOppositeFvgWatchList[i].counter <= 0)
         continue;

      if(globalBosOppositeFvgWatchList[i].expectsBullishFairValueGap)
      {
         globalBosOppositeFvgWatchList[i].minCloseSinceBos =
            MathMin(globalBosOppositeFvgWatchList[i].minCloseSinceBos, barClose);
         const double impulse =
            globalBosOppositeFvgWatchList[i].bosLegLevelPrice - globalBosOppositeFvgWatchList[i].minCloseSinceBos;
         if(impulse > limitPrice)
         {
            RemoveBosOppositeFvgWatchAt(i);
            i--;
         }
      }
      else
      {
         globalBosOppositeFvgWatchList[i].maxCloseSinceBos =
            MathMax(globalBosOppositeFvgWatchList[i].maxCloseSinceBos, barClose);
         const double impulse =
            globalBosOppositeFvgWatchList[i].maxCloseSinceBos - globalBosOppositeFvgWatchList[i].bosLegLevelPrice;
         if(impulse > limitPrice)
         {
            RemoveBosOppositeFvgWatchAt(i);
            i--;
         }
      }
   }
}

//+------------------------------------------------------------------+
void PushBosOppositeFairValueGapMemory(const bool isBullishFairValueGap, const double zoneLowPrice,
                                     const double zoneHighPrice, const datetime fairValueGapBarOpenTime,
                                     const double bosBarClosePrice, const double pathMinLowSinceBos,
                                     const double pathMaxHighSinceBos)
{
   for(int memoryIndex = 0; memoryIndex < globalBosOppositeFairValueGapMemoryCount; memoryIndex++)
   {
      if(globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapBarOpenTime == fairValueGapBarOpenTime)
         return;
   }

   if(globalBosOppositeFairValueGapMemoryCount < BosOppositeFairValueGapMemoryCapacity)
   {
      const int index = globalBosOppositeFairValueGapMemoryCount;
      globalBosOppositeFairValueGapMemory[index].isBullishFairValueGap   = isBullishFairValueGap;
      globalBosOppositeFairValueGapMemory[index].fairValueGapZoneLowPrice  = zoneLowPrice;
      globalBosOppositeFairValueGapMemory[index].fairValueGapZoneHighPrice = zoneHighPrice;
      globalBosOppositeFairValueGapMemory[index].fairValueGapBarOpenTime  = fairValueGapBarOpenTime;
      globalBosOppositeFairValueGapMemory[index].bosBarClosePrice       = bosBarClosePrice;
      globalBosOppositeFairValueGapMemory[index].pathMinLowSinceBos     = pathMinLowSinceBos;
      globalBosOppositeFairValueGapMemory[index].pathMaxHighSinceBos  = pathMaxHighSinceBos;
      globalBosOppositeFairValueGapMemoryCount++;
      return;
   }

   for(int shiftIndex = 1; shiftIndex < BosOppositeFairValueGapMemoryCapacity; shiftIndex++)
      globalBosOppositeFairValueGapMemory[shiftIndex - 1] = globalBosOppositeFairValueGapMemory[shiftIndex];

   const int lastIndex = BosOppositeFairValueGapMemoryCapacity - 1;
   globalBosOppositeFairValueGapMemory[lastIndex].isBullishFairValueGap   = isBullishFairValueGap;
   globalBosOppositeFairValueGapMemory[lastIndex].fairValueGapZoneLowPrice  = zoneLowPrice;
   globalBosOppositeFairValueGapMemory[lastIndex].fairValueGapZoneHighPrice = zoneHighPrice;
   globalBosOppositeFairValueGapMemory[lastIndex].fairValueGapBarOpenTime  = fairValueGapBarOpenTime;
   globalBosOppositeFairValueGapMemory[lastIndex].bosBarClosePrice       = bosBarClosePrice;
   globalBosOppositeFairValueGapMemory[lastIndex].pathMinLowSinceBos     = pathMinLowSinceBos;
   globalBosOppositeFairValueGapMemory[lastIndex].pathMaxHighSinceBos  = pathMaxHighSinceBos;
}

//+------------------------------------------------------------------+
void DrawBosMarkedFairValueGapZone(const bool isBullishFairValueGap, const double zoneLowPrice,
                                   const double zoneHighPrice, const datetime leftBarTime,
                                   const datetime rightBarTime)
{
   if(!InputDrawBosOppositeFairValueGapZones)
      return;

   globalBosMarkedFairValueGapRectangleSequence++;
   const string sequenceString = IntegerToString(globalBosMarkedFairValueGapRectangleSequence);
   const string chartObjectName = ChartObjectNamePrefixBosMarkedFairValueGap + sequenceString;
   const string typeLabelName   = ChartObjectNamePrefixBosFvgTypeLabel + sequenceString;

   if(globalBosMarkedFairValueGapRectangleSequence > InputMaximumFairValueGapRectangles)
   {
      const string oldSequenceString =
         IntegerToString(globalBosMarkedFairValueGapRectangleSequence - InputMaximumFairValueGapRectangles);
      ObjectDelete(0, ChartObjectNamePrefixBosMarkedFairValueGap + oldSequenceString);
      ObjectDelete(0, ChartObjectNamePrefixBosFvgTypeLabel + oldSequenceString);
   }

   const datetime rectangleTimeLeft  = (leftBarTime <= rightBarTime) ? leftBarTime : rightBarTime;
   const datetime rectangleTimeRight = (leftBarTime <= rightBarTime) ? rightBarTime : leftBarTime;
   const double rectanglePriceLow    = MathMin(zoneLowPrice, zoneHighPrice);
   const double rectanglePriceHigh   = MathMax(zoneLowPrice, zoneHighPrice);

   if(ObjectFind(0, chartObjectName) >= 0)
      ObjectDelete(0, chartObjectName);
   if(ObjectFind(0, typeLabelName) >= 0)
      ObjectDelete(0, typeLabelName);

   if(!ObjectCreate(0, chartObjectName, OBJ_RECTANGLE, 0, rectangleTimeLeft, rectanglePriceHigh,
                    rectangleTimeRight, rectanglePriceLow))
      return;

   const color zoneColor = isBullishFairValueGap ? clrDodgerBlue : clrFuchsia;
   ObjectSetInteger(0, chartObjectName, OBJPROP_COLOR, zoneColor);
   ObjectSetInteger(0, chartObjectName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, chartObjectName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, chartObjectName, OBJPROP_BACK, true);
   ObjectSetInteger(0, chartObjectName, OBJPROP_FILL, true);
   ObjectSetInteger(0, chartObjectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, chartObjectName, OBJPROP_HIDDEN, true);

   const double symbolPointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double labelPrice      = rectanglePriceHigh + symbolPointSize * 14.0;
   if(ObjectCreate(0, typeLabelName, OBJ_TEXT, 0, rectangleTimeRight, labelPrice))
   {
      ObjectSetString(0, typeLabelName, OBJPROP_TEXT, isBullishFairValueGap ? "bull" : "bear");
      ObjectSetInteger(0, typeLabelName, OBJPROP_COLOR,
                       isBullishFairValueGap ? clrDodgerBlue : clrFuchsia);
      ObjectSetInteger(0, typeLabelName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, typeLabelName, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, typeLabelName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, typeLabelName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, typeLabelName, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
void ProcessBosOppositeFairValueGapWindow()
{
   bool   expectsBullishFairValueGapFromBreakOfStructure;
   double bosLegLevelPriceFromBreakOfStructure;
   if(TryDetectBreakOfStructureOnLastClosedBar(expectsBullishFairValueGapFromBreakOfStructure,
                                               bosLegLevelPriceFromBreakOfStructure))
      PushBosOppositeFvgWatch(expectsBullishFairValueGapFromBreakOfStructure,
                               bosLegLevelPriceFromBreakOfStructure);

   ProcessBosOppositeFvgWatchImpulseInvalidation();

   if(!HasAnyActiveBosOppositeFvgWatch())
      return;

   bool isBullishFairValueGap;
   double fairValueGapZoneLowPrice;
   double fairValueGapZoneHighPrice;
   if(DetectFairValueGapOnLastClosedBar(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                        fairValueGapZoneHighPrice))
   {
      const int matchingWatchIndex = FindFirstMatchingBosFvgWatchIndex(isBullishFairValueGap);
      if(matchingWatchIndex >= 0)
      {
         const datetime lastClosedBarOpenTime = iTime(_Symbol, SwingTimeframe, 1);
         const datetime thirdBarOpenTime      = iTime(_Symbol, SwingTimeframe, 3);

         const BosOppositeFvgWatch snapWatch = globalBosOppositeFvgWatchList[matchingWatchIndex];
         PushBosOppositeFairValueGapMemory(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                           fairValueGapZoneHighPrice, lastClosedBarOpenTime,
                                           snapWatch.bosBarClosePrice, snapWatch.pathMinLowSinceBos,
                                           snapWatch.pathMaxHighSinceBos);
         DrawBosMarkedFairValueGapZone(isBullishFairValueGap, fairValueGapZoneLowPrice,
                                       fairValueGapZoneHighPrice, thirdBarOpenTime, lastClosedBarOpenTime);
         RemoveBosOppositeFvgWatchAt(matchingWatchIndex);
      }
   }

   ProcessBosOppositeFvgWatchDecrements();
}

//+------------------------------------------------------------------+
bool GetBosOppositeFairValueGapFromMemoryForBarOpenTime(const datetime barOpenTime,
                                                        bool &outIsBullishFairValueGap,
                                                        double &outZoneLowPrice,
                                                        double &outZoneHighPrice,
                                                        double &outBosBarClosePrice,
                                                        double &outPathMinLowSinceBos,
                                                        double &outPathMaxHighSinceBos)
{
   for(int memoryIndex = globalBosOppositeFairValueGapMemoryCount - 1; memoryIndex >= 0; memoryIndex--)
   {
      if(globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapBarOpenTime != barOpenTime)
         continue;

      outIsBullishFairValueGap = globalBosOppositeFairValueGapMemory[memoryIndex].isBullishFairValueGap;
      outZoneLowPrice        = globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapZoneLowPrice;
      outZoneHighPrice       = globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapZoneHighPrice;
      outBosBarClosePrice    = globalBosOppositeFairValueGapMemory[memoryIndex].bosBarClosePrice;
      outPathMinLowSinceBos  = globalBosOppositeFairValueGapMemory[memoryIndex].pathMinLowSinceBos;
      outPathMaxHighSinceBos = globalBosOppositeFairValueGapMemory[memoryIndex].pathMaxHighSinceBos;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void ApplyTradeFillingModeFromSymbol()
{
   const long fillingMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(fillingMode == 0)
      return;
   if((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      tradeLayer.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      tradeLayer.SetTypeFilling(ORDER_FILLING_IOC);
   else
      tradeLayer.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
double CalculateVolumeForFixedUsdRisk(const ENUM_ORDER_TYPE orderType, const double entryPrice,
                                      const double stopLossPrice, const double riskAccountCurrency)
{
   double profitAtStop = 0.0;
   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entryPrice, stopLossPrice, profitAtStop))
      return 0.0;

   const double lossPerLot = (profitAtStop < 0.0) ? -profitAtStop : profitAtStop;
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
double M2FairValueGapStopBufferPrice()
{
   const double h = ReferenceChartHeightForFairValueGapFilter(SwingTimeframe);
   if(h <= 0.0)
      return 0.0;
   return h * (InputFvgStopBufferPercentOfM2Range / 100.0);
}

//+------------------------------------------------------------------+
bool HasOurFvgOpenPositionOnSymbol()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InputExpertMagicNumber)
         continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool HasOurFvgPendingForFormation(const datetime formationTime)
{
   const string tag = IntegerToString((long)formationTime);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InputExpertMagicNumber)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), tag) >= 0)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
int GetOurFvgPendingPlanKindForFormation(const datetime formationTime)
{
   const string tag = IntegerToString((long)formationTime);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InputExpertMagicNumber)
         continue;
      const string c = OrderGetString(ORDER_COMMENT);
      if(StringFind(c, tag) < 0)
         continue;
      if(StringFind(c, "PlanA") >= 0)
         return 0;
      if(StringFind(c, "PlanB") >= 0)
         return 1;
   }
   return -1;
}

//+------------------------------------------------------------------+
void CancelOurFvgPendingOrdersForFormation(const datetime formationTime)
{
   const string tag = IntegerToString((long)formationTime);
   tradeLayer.SetExpertMagicNumber(InputExpertMagicNumber);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InputExpertMagicNumber)
         continue;
      if(StringFind(OrderGetString(ORDER_COMMENT), tag) < 0)
         continue;
      tradeLayer.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
bool TryParseFormationTimeFromM2FvgOrderComment(const string &comment, datetime &outFormation)
{
   outFormation = 0;
   if(StringFind(comment, "PlanA") < 0)
      return false;
   string trimmed = comment;
   StringTrimRight(trimmed);
   string parts[];
   const int n = StringSplit(trimmed, ' ', parts);
   if(n < 1)
      return false;
   const long v = StringToInteger(parts[n - 1]);
   if(v <= 0)
      return false;
   outFormation = (datetime)v;
   return true;
}

//+------------------------------------------------------------------+
void RegisterFvgPlanAStopLossHit(const datetime formationTime)
{
   if(formationTime <= 0)
      return;
   for(int i = 0; i < globalFvgPlanAStopHitFormationCount; i++)
   {
      if(globalFvgPlanAStopHitFormations[i] == formationTime)
         return;
   }
   if(globalFvgPlanAStopHitFormationCount < FvgPlanAStopHitFormationCapacity)
   {
      globalFvgPlanAStopHitFormations[globalFvgPlanAStopHitFormationCount++] = formationTime;
      return;
   }
   for(int j = 1; j < FvgPlanAStopHitFormationCapacity; j++)
      globalFvgPlanAStopHitFormations[j - 1] = globalFvgPlanAStopHitFormations[j];
   globalFvgPlanAStopHitFormations[FvgPlanAStopHitFormationCapacity - 1] = formationTime;
}

//+------------------------------------------------------------------+
bool IsFvgPlanBSkippedAfterPlanAStopHit(const datetime formationTime)
{
   for(int i = 0; i < globalFvgPlanAStopHitFormationCount; i++)
   {
      if(globalFvgPlanAStopHitFormations[i] == formationTime)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
datetime SwingAnchorTime(const Swing &s)
{
   return (s.legStartTime >= s.legEndTime) ? s.legStartTime : s.legEndTime;
}

//+------------------------------------------------------------------+
bool H4PathOverlapsBand(const double pathMinLow, const double pathMaxHigh,
                        const double bandLoRaw, const double bandHiRaw)
{
   const double pLo = MathMin(pathMinLow, pathMaxHigh);
   const double pHi = MathMax(pathMinLow, pathMaxHigh);
   const double zLo = MathMin(bandLoRaw, bandHiRaw);
   const double zHi = MathMax(bandLoRaw, bandHiRaw);
   return (pLo <= zHi && pHi >= zLo);
}

//+------------------------------------------------------------------+
bool H4PriceInsideBand(const double price, const double bandLoRaw, const double bandHiRaw)
{
   const double zLo = MathMin(bandLoRaw, bandHiRaw);
   const double zHi = MathMax(bandLoRaw, bandHiRaw);
   return (price >= zLo && price <= zHi);
}

//+------------------------------------------------------------------+
bool H4GetSecondLastCompletedUpLeg(double &outLevel, datetime &outAnchor)
{
   const int count = globalH4SwingState.swingHistoryCount;
   int upFound = 0;
   for(int k = 0; k < count; k++)
   {
      const int idx = count - 1 - k;
      if(globalH4SwingState.swingHistory[idx].swingDirection != 1)
         continue;
      upFound++;
      if(upFound == 2)
      {
         const Swing s = globalH4SwingState.swingHistory[idx];
         outLevel  = s.legHighPrice;
         outAnchor = SwingAnchorTime(s);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool H4GetSecondLastCompletedDownLeg(double &outLevel, datetime &outAnchor)
{
   const int count = globalH4SwingState.swingHistoryCount;
   int dnFound = 0;
   for(int k = 0; k < count; k++)
   {
      const int idx = count - 1 - k;
      if(globalH4SwingState.swingHistory[idx].swingDirection != -1)
         continue;
      dnFound++;
      if(dnFound == 2)
      {
         const Swing s = globalH4SwingState.swingHistory[idx];
         outLevel  = s.legLowPrice;
         outAnchor = SwingAnchorTime(s);
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool PriceInH4DemandBands(const double price)
{
   const double buf = H4BufferBandHalfWidth();
   if(buf <= 0.0)
      return false;

   for(int i = 0; i < globalH4FairValueGapMemoryCount; i++)
   {
      if(!globalH4FairValueGapMemory[i].isBullishFairValueGap)
         continue;
      const double lo = globalH4FairValueGapMemory[i].fairValueGapZoneLowPrice;
      const double hi = globalH4FairValueGapMemory[i].fairValueGapZoneHighPrice;
      const double zLo = MathMin(lo, hi) - buf;
      const double zHi = MathMax(lo, hi) + buf;
      if(H4PriceInsideBand(price, zLo, zHi))
         return true;
   }

   const int legCount = globalH4SwingState.swingHistoryCount;
   for(int k = 0; k < legCount; k++)
   {
      const Swing s = globalH4SwingState.swingHistory[legCount - 1 - k];
      if(s.swingDirection != -1)
         continue;
      const double lvl = s.legLowPrice;
      const double zLo = lvl - buf;
      const double zHi = lvl + buf;
      if(H4PriceInsideBand(price, zLo, zHi))
         return true;
   }

   if(globalH4LatestBosDirection == 1)
   {
      double lvl = 0.0;
      datetime anc = 0;
      if(H4GetSecondLastCompletedUpLeg(lvl, anc))
      {
         const double zLo = lvl - buf;
         const double zHi = lvl + buf;
         if(H4PriceInsideBand(price, zLo, zHi))
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
bool PriceInH4SupplyBands(const double price)
{
   const double buf = H4BufferBandHalfWidth();
   if(buf <= 0.0)
      return false;

   for(int i = 0; i < globalH4FairValueGapMemoryCount; i++)
   {
      if(globalH4FairValueGapMemory[i].isBullishFairValueGap)
         continue;
      const double lo = globalH4FairValueGapMemory[i].fairValueGapZoneLowPrice;
      const double hi = globalH4FairValueGapMemory[i].fairValueGapZoneHighPrice;
      const double zLo = MathMin(lo, hi) - buf;
      const double zHi = MathMax(lo, hi) + buf;
      if(H4PriceInsideBand(price, zLo, zHi))
         return true;
   }

   const int legCount = globalH4SwingState.swingHistoryCount;
   for(int k = 0; k < legCount; k++)
   {
      const Swing s = globalH4SwingState.swingHistory[legCount - 1 - k];
      if(s.swingDirection != 1)
         continue;
      const double lvl = s.legHighPrice;
      const double zLo = lvl - buf;
      const double zHi = lvl + buf;
      if(H4PriceInsideBand(price, zLo, zHi))
         return true;
   }

   if(globalH4LatestBosDirection == -1)
   {
      double lvl = 0.0;
      datetime anc = 0;
      if(H4GetSecondLastCompletedDownLeg(lvl, anc))
      {
         const double zLo = lvl - buf;
         const double zHi = lvl + buf;
         if(H4PriceInsideBand(price, zLo, zHi))
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void PathOverlapsH4DemandSupplyBands(const double pathMinLow, const double pathMaxHigh,
                                     bool &outDemandHit, bool &outSupplyHit,
                                     datetime &outNewestDemandAnchor, datetime &outNewestSupplyAnchor)
{
   outDemandHit = false;
   outSupplyHit = false;
   outNewestDemandAnchor = 0;
   outNewestSupplyAnchor = 0;

   const double buf = H4BufferBandHalfWidth();
   if(buf <= 0.0)
      return;

   for(int i = 0; i < globalH4FairValueGapMemoryCount; i++)
   {
      const double lo = globalH4FairValueGapMemory[i].fairValueGapZoneLowPrice;
      const double hi = globalH4FairValueGapMemory[i].fairValueGapZoneHighPrice;
      const double zLo = MathMin(lo, hi) - buf;
      const double zHi = MathMax(lo, hi) + buf;
      const datetime anchor = globalH4FairValueGapMemory[i].formationBarOpenTime;

      if(globalH4FairValueGapMemory[i].isBullishFairValueGap)
      {
         if(H4PathOverlapsBand(pathMinLow, pathMaxHigh, zLo, zHi))
         {
            outDemandHit = true;
            if(anchor > outNewestDemandAnchor)
               outNewestDemandAnchor = anchor;
         }
      }
      else
      {
         if(H4PathOverlapsBand(pathMinLow, pathMaxHigh, zLo, zHi))
         {
            outSupplyHit = true;
            if(anchor > outNewestSupplyAnchor)
               outNewestSupplyAnchor = anchor;
         }
      }
   }

   const int legCount = globalH4SwingState.swingHistoryCount;
   for(int k = 0; k < legCount; k++)
   {
      const Swing s = globalH4SwingState.swingHistory[legCount - 1 - k];
      const datetime anchor = SwingAnchorTime(s);

      if(s.swingDirection == -1)
      {
         const double lvl = s.legLowPrice;
         const double zLo = lvl - buf;
         const double zHi = lvl + buf;
         if(H4PathOverlapsBand(pathMinLow, pathMaxHigh, zLo, zHi))
         {
            outDemandHit = true;
            if(anchor > outNewestDemandAnchor)
               outNewestDemandAnchor = anchor;
         }
      }
      else if(s.swingDirection == 1)
      {
         const double lvl = s.legHighPrice;
         const double zLo = lvl - buf;
         const double zHi = lvl + buf;
         if(H4PathOverlapsBand(pathMinLow, pathMaxHigh, zLo, zHi))
         {
            outSupplyHit = true;
            if(anchor > outNewestSupplyAnchor)
               outNewestSupplyAnchor = anchor;
         }
      }
   }

   if(globalH4LatestBosDirection == 1)
   {
      double lvl = 0.0;
      datetime anc = 0;
      if(H4GetSecondLastCompletedUpLeg(lvl, anc))
      {
         const double zLo = lvl - buf;
         const double zHi = lvl + buf;
         if(H4PathOverlapsBand(pathMinLow, pathMaxHigh, zLo, zHi))
         {
            outDemandHit = true;
            if(anc > outNewestDemandAnchor)
               outNewestDemandAnchor = anc;
         }
      }
   }

   if(globalH4LatestBosDirection == -1)
   {
      double lvl = 0.0;
      datetime anc = 0;
      if(H4GetSecondLastCompletedDownLeg(lvl, anc))
      {
         const double zLo = lvl - buf;
         const double zHi = lvl + buf;
         if(H4PathOverlapsBand(pathMinLow, pathMaxHigh, zLo, zHi))
         {
            outSupplyHit = true;
            if(anc > outNewestSupplyAnchor)
               outNewestSupplyAnchor = anc;
         }
      }
   }
}

//+------------------------------------------------------------------+
bool PassesHtfTradeGate(const bool isBullishFairValueGap, const double pathMinLowSinceBos,
                       const double pathMaxHighSinceBos, string &outReason)
{
   outReason = "";
   if(!InputEnableHtfTradeGate)
      return true;

   const int m15 = globalM15LatestBosDirection;
   if(m15 == 0)
   {
      outReason = "no M15 BOS yet";
      return false;
   }

   const bool aligned = (isBullishFairValueGap && m15 == 1) || (!isBullishFairValueGap && m15 == -1);

   if(aligned)
   {
      bool hitDemand = false;
      bool hitSupply = false;
      datetime tDemand = 0;
      datetime tSupply = 0;
      PathOverlapsH4DemandSupplyBands(pathMinLowSinceBos, pathMaxHighSinceBos,
                                      hitDemand, hitSupply, tDemand, tSupply);

      if(!hitDemand && !hitSupply)
      {
         outReason = "BOS path does not overlap H4 demand/supply bands";
         return false;
      }

      bool natureBullish = false;
      if(hitDemand && hitSupply)
         natureBullish = (tDemand >= tSupply);
      else if(hitDemand)
         natureBullish = true;
      else
         natureBullish = false;

      if(isBullishFairValueGap && natureBullish)
         return true;
      if(!isBullishFairValueGap && !natureBullish)
         return true;

      outReason = "M2 FVG vs H4 path context (demand/supply)";
      return false;
   }

   // Reaching here => M15 BOS and FVG direction differ ("counter-trend" FVG vs M15).
   if(!InputHtfAllowCounterTrendFvg)
   {
      outReason = "M15 BOS not aligned with FVG (enable InputHtfAllowCounterTrendFvg for counter-trend)";
      return false;
   }

   if(isBullishFairValueGap && m15 == -1)
   {
      const double p = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(PriceInH4DemandBands(p))
         return true;
      outReason = "M15 bear BOS: long needs bid in H4 demand OR bands";
      return false;
   }

   if(!isBullishFairValueGap && m15 == 1)
   {
      const double p = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(PriceInH4SupplyBands(p))
         return true;
      outReason = "M15 bull BOS: short needs ask in H4 supply OR bands";
      return false;
   }

   outReason = "FVG direction vs M15 BOS";
   return false;
}

//+------------------------------------------------------------------+
void TryExecuteFairValueGapTradePlan()
{
   if(HasOurFvgOpenPositionOnSymbol())
      return;

   const datetime lastClosedM2Open = iTime(_Symbol, SwingTimeframe, 1);

   for(int memoryIndex = globalBosOppositeFairValueGapMemoryCount - 1; memoryIndex >= 0; memoryIndex--)
   {
      const datetime formationTime = globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapBarOpenTime;
      const int      barShift      = iBarShift(_Symbol, SwingTimeframe, formationTime);
      if(barShift < 0)
         continue;
      if(barShift > InputFvgTradeMaxM2BarShift)
         continue;

      const bool   isBullishFairValueGap = globalBosOppositeFairValueGapMemory[memoryIndex].isBullishFairValueGap;
      const double fairValueGapZoneLowPrice  = globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapZoneLowPrice;
      const double fairValueGapZoneHighPrice = globalBosOppositeFairValueGapMemory[memoryIndex].fairValueGapZoneHighPrice;
      const double pathMinLowSinceBos  = globalBosOppositeFairValueGapMemory[memoryIndex].pathMinLowSinceBos;
      const double pathMaxHighSinceBos = globalBosOppositeFairValueGapMemory[memoryIndex].pathMaxHighSinceBos;

      string   htfGateReason = "";
      const bool htfGateOk =
         PassesHtfTradeGate(isBullishFairValueGap, pathMinLowSinceBos, pathMaxHighSinceBos, htfGateReason);

      if(memoryIndex == globalBosOppositeFairValueGapMemoryCount - 1 && InputPrintHtfTradeDecision)
      {
         static datetime s_lastHtfPrintFormation = 0;
         static datetime s_lastHtfPrintBarOpen   = 0;
         if(formationTime != s_lastHtfPrintFormation || lastClosedM2Open != s_lastHtfPrintBarOpen)
         {
            s_lastHtfPrintFormation = formationTime;
            s_lastHtfPrintBarOpen   = lastClosedM2Open;
            if(htfGateOk)
               Print("plot_swing_m2: HTF trade: YES");
            else
               Print("plot_swing_m2: HTF trade: NO — ", htfGateReason);
         }
      }

      if(!htfGateOk)
         continue;

      const bool usePlanA = (barShift <= InputFvgPlanAMaxM2BarShift);

      if(!usePlanA && IsFvgPlanBSkippedAfterPlanAStopHit(formationTime))
         continue;

      if(HasOurFvgPendingForFormation(formationTime))
      {
         const int pendingKind = GetOurFvgPendingPlanKindForFormation(formationTime);
         const int wantKind    = usePlanA ? 0 : 1;
         if(pendingKind == wantKind)
            return;
         CancelOurFvgPendingOrdersForFormation(formationTime);
      }

      const double higherEndOfFairValueGap = MathMax(fairValueGapZoneLowPrice, fairValueGapZoneHighPrice);
      const double lowerEndOfFairValueGap  = MathMin(fairValueGapZoneLowPrice, fairValueGapZoneHighPrice);
      const double buf                     = M2FairValueGapStopBufferPrice();

      double stopLossPrice;
      if(usePlanA)
      {
         if(isBullishFairValueGap)
            stopLossPrice = lowerEndOfFairValueGap - buf;
         else
            stopLossPrice = higherEndOfFairValueGap + buf;
      }
      else
      {
         if(isBullishFairValueGap)
            stopLossPrice = pathMinLowSinceBos - buf;
         else
            stopLossPrice = pathMaxHighSinceBos + buf;
      }

      const double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool   useMarketOrder = false;
      double entryPrice     = 0.0;

      if(isBullishFairValueGap)
      {
         const bool bidInsideFairValueGap =
            (currentBid >= lowerEndOfFairValueGap && currentBid <= higherEndOfFairValueGap);
         if(bidInsideFairValueGap)
         {
            useMarketOrder = true;
            entryPrice     = currentAsk;
         }
         else if(currentBid > higherEndOfFairValueGap)
         {
            useMarketOrder = false;
            entryPrice     = NormalizeDouble(higherEndOfFairValueGap, _Digits);
         }
         else
         {
            useMarketOrder = false;
            entryPrice     = NormalizeDouble(lowerEndOfFairValueGap, _Digits);
         }

         if(entryPrice <= stopLossPrice)
            continue;
      }
      else
      {
         const bool askInsideFairValueGap =
            (currentAsk >= lowerEndOfFairValueGap && currentAsk <= higherEndOfFairValueGap);
         if(askInsideFairValueGap)
         {
            useMarketOrder = true;
            entryPrice     = currentBid;
         }
         else if(currentAsk < lowerEndOfFairValueGap)
         {
            useMarketOrder = false;
            entryPrice     = NormalizeDouble(lowerEndOfFairValueGap, _Digits);
         }
         else
         {
            useMarketOrder = false;
            entryPrice     = NormalizeDouble(higherEndOfFairValueGap, _Digits);
         }

         if(entryPrice >= stopLossPrice)
            continue;
      }

      const double riskPerUnit = MathAbs(entryPrice - stopLossPrice);
      if(riskPerUnit <= SymbolInfoDouble(_Symbol, SYMBOL_POINT))
         continue;

      double takeProfitTwoRewardMultiple = 0.0;
      double takeProfitThreeRewardMultiple = 0.0;
      if(isBullishFairValueGap)
      {
         takeProfitTwoRewardMultiple   = NormalizeDouble(entryPrice + 2.0 * riskPerUnit, _Digits);
         takeProfitThreeRewardMultiple = NormalizeDouble(entryPrice + 3.0 * riskPerUnit, _Digits);
      }
      else
      {
         takeProfitTwoRewardMultiple   = NormalizeDouble(entryPrice - 2.0 * riskPerUnit, _Digits);
         takeProfitThreeRewardMultiple = NormalizeDouble(entryPrice - 3.0 * riskPerUnit, _Digits);
      }

      const double normalizedStopLoss = NormalizeDouble(stopLossPrice, _Digits);
      const double normalizedEntry    = NormalizeDouble(entryPrice, _Digits);

      if(!StopsDistanceAllowed(isBullishFairValueGap, normalizedEntry, normalizedStopLoss,
                             takeProfitTwoRewardMultiple))
      {
         Print("plot_swing_m2: broker stops level too large for this entry/SL/TP. plan=",
               (usePlanA ? "A" : "B"), " formation=", formationTime);
         continue;
      }

      const ENUM_ORDER_TYPE marketOrderType =
         isBullishFairValueGap ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      const double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(accountBalance <= 0.0 || InputRiskPercentPerTrade <= 0.0)
      {
         Print("plot_swing_m2: risk sizing skipped — balance or InputRiskPercentPerTrade invalid.");
         continue;
      }
      const double riskAccountCurrencyTotal =
         accountBalance * (InputRiskPercentPerTrade / 100.0);
      const double riskAccountCurrencyPerLeg = riskAccountCurrencyTotal / 2.0;

      const double volumeTwoR =
         CalculateVolumeForFixedUsdRisk(marketOrderType, normalizedEntry, normalizedStopLoss,
                                        riskAccountCurrencyPerLeg);
      const double volumeThreeR =
         CalculateVolumeForFixedUsdRisk(marketOrderType, normalizedEntry, normalizedStopLoss,
                                        riskAccountCurrencyPerLeg);
      if(volumeTwoR <= 0.0 || volumeThreeR <= 0.0)
      {
         Print("plot_swing_m2: volume from risk %% is zero — check symbol / contract size.");
         continue;
      }

      if(!useMarketOrder)
      {
         if(isBullishFairValueGap && normalizedEntry >= currentAsk)
         {
            Print("plot_swing_m2: BuyLimit invalid — entry must be below ask. entry=", normalizedEntry,
                  " ask=", currentAsk);
            continue;
         }
         if(!isBullishFairValueGap && normalizedEntry <= currentBid)
         {
            Print("plot_swing_m2: SellLimit invalid — entry must be above bid. entry=", normalizedEntry,
                  " bid=", currentBid);
            continue;
         }
      }

      const string planTag            = usePlanA ? "PlanA" : "PlanB";
      const string formationTag       = IntegerToString((long)formationTime);
      const string commentTwoR        = "M2 BOS FVG 2R " + planTag + " " + formationTag;
      const string commentThreeR      = "M2 BOS FVG 3R " + planTag + " " + formationTag;

      if(!InputEnableAutomatedTrading)
      {
         Print("plot_swing_m2: BOS opposite FVG (log only). ", planTag, " barShift=", barShift,
               " risk%%=", InputRiskPercentPerTrade, " perLegAcct=", riskAccountCurrencyPerLeg,
               " bullishFvg=", isBullishFairValueGap, " market=", useMarketOrder,
               " entry=", normalizedEntry, " sl=", normalizedStopLoss,
               " tp2R=", takeProfitTwoRewardMultiple, " tp3R=", takeProfitThreeRewardMultiple,
               " vol2R=", volumeTwoR, " vol3R=", volumeThreeR);
         return;
      }

      tradeLayer.SetExpertMagicNumber(InputExpertMagicNumber);
      tradeLayer.SetDeviationInPoints(30);
      ApplyTradeFillingModeFromSymbol();

      bool orderTwoResult   = false;
      bool orderThreeResult = false;

      if(useMarketOrder)
      {
         if(isBullishFairValueGap)
         {
            orderTwoResult =
               tradeLayer.Buy(volumeTwoR, _Symbol, 0.0, normalizedStopLoss, takeProfitTwoRewardMultiple,
                              commentTwoR);
            orderThreeResult =
               tradeLayer.Buy(volumeThreeR, _Symbol, 0.0, normalizedStopLoss, takeProfitThreeRewardMultiple,
                              commentThreeR);
         }
         else
         {
            orderTwoResult =
               tradeLayer.Sell(volumeTwoR, _Symbol, 0.0, normalizedStopLoss, takeProfitTwoRewardMultiple,
                               commentTwoR);
            orderThreeResult =
               tradeLayer.Sell(volumeThreeR, _Symbol, 0.0, normalizedStopLoss, takeProfitThreeRewardMultiple,
                               commentThreeR);
         }
      }
      else
      {
         if(isBullishFairValueGap)
         {
            orderTwoResult =
               tradeLayer.BuyLimit(volumeTwoR, normalizedEntry, _Symbol, normalizedStopLoss,
                                   takeProfitTwoRewardMultiple, ORDER_TIME_GTC, 0, commentTwoR);
            orderThreeResult =
               tradeLayer.BuyLimit(volumeThreeR, normalizedEntry, _Symbol, normalizedStopLoss,
                                   takeProfitThreeRewardMultiple, ORDER_TIME_GTC, 0, commentThreeR);
         }
         else
         {
            orderTwoResult =
               tradeLayer.SellLimit(volumeTwoR, normalizedEntry, _Symbol, normalizedStopLoss,
                                    takeProfitTwoRewardMultiple, ORDER_TIME_GTC, 0, commentTwoR);
            orderThreeResult =
               tradeLayer.SellLimit(volumeThreeR, normalizedEntry, _Symbol, normalizedStopLoss,
                                    takeProfitThreeRewardMultiple, ORDER_TIME_GTC, 0, commentThreeR);
         }
      }

      if(orderTwoResult || orderThreeResult)
         Print("plot_swing_m2: orders sent. ", planTag, " twoR=", orderTwoResult, " threeR=", orderThreeResult);
      else
         Print("plot_swing_m2: order send failed. retcode=", tradeLayer.ResultRetcode(), " ",
               tradeLayer.ResultRetcodeDescription());
      return;
   }
}

//+------------------------------------------------------------------+
