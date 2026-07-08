//+------------------------------------------------------------------+
//| H4LqV3Types.mqh
//| Swing / SMC / hunt structs
//+------------------------------------------------------------------+
#ifndef H4_LQ_V3_H4LQV3TYPES
#define H4_LQ_V3_H4LQV3TYPES

// --- swing structs (plot_swing_h1_m5_copy.mq5) ---
struct Swing
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection; // 1 = up, -1 = down, 0 = unset
   int      keyLevelId;
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
   bool   isSupplyPool;
};

struct M2SwingExtremePoint
{
   double   extremePrice;
   datetime legStartTime;
   datetime legEndTime;
};

// --- MTF SMC confluence (Phase 1–3) ---
enum ENUM_SMC_ZONE_TYPE
{
   ZONE_BULL_WEEKLY_FVG,
   ZONE_BULL_DAILY_FVG,
   ZONE_BULL_H4_FVG,
   ZONE_BULL_M15_FVG,
   ZONE_BULL_PROTECTED_DAILY_LOW,
   ZONE_BULL_PROTECTED_H4_LOW,
   ZONE_BULL_PROTECTED_M15_LOW,
   ZONE_BULL_SWING_W1_LOW,
   ZONE_BULL_SWING_DAILY_LOW,
   ZONE_BULL_SWING_H4_LOW,
   ZONE_BULL_SWING_M15_LOW,
   ZONE_BEAR_WEEKLY_FVG,
   ZONE_BEAR_DAILY_FVG,
   ZONE_BEAR_H4_FVG,
   ZONE_BEAR_M15_FVG,
   ZONE_BEAR_PROTECTED_DAILY_HIGH,
   ZONE_BEAR_PROTECTED_H4_HIGH,
   ZONE_BEAR_PROTECTED_M15_HIGH,
   ZONE_BEAR_SWING_W1_HIGH,
   ZONE_BEAR_SWING_DAILY_HIGH,
   ZONE_BEAR_SWING_H4_HIGH,
   ZONE_BEAR_SWING_M15_HIGH,
   SMC_ZONE_TYPE_COUNT
};

struct SMCZoneRecord
{
   ENUM_SMC_ZONE_TYPE type;
   double             topPrice;
   double             bottomPrice;
   bool               isActive;
   bool               isClustered;
   bool               isMitigated;
   bool               isBreached;
   bool               isExpired;
   datetime           zoneOriginBarTime;
};

struct SMCZoneMitigationLedgerEntry
{
   bool               inUse;
   ENUM_SMC_ZONE_TYPE type;
   double             topPrice;
   double             bottomPrice;
   bool               isMitigated;
   bool               isBreached;
   bool               isExpired;
   datetime           zoneOriginBarTime;
};

#define SMC_ZONE_LEDGER_CAPACITY              256
#define SMC_ZONE_MITIGATION_LEDGER_CAPACITY   (SMC_ZONE_LEDGER_CAPACITY * 2)

struct SMCMtfFvgInstance
{
   bool               inUse;
   ENUM_SMC_ZONE_TYPE type;
   ENUM_TIMEFRAMES    timeframe;
   double             topPrice;
   double             bottomPrice;
   bool               isMitigated;
   bool               isBreached;
   bool               isExpired;
   datetime           zoneOriginBarTime;
};

#define SMC_MTF_FVG_INSTANCE_CAPACITY 256

struct MTFSwingTracker
{
   ENUM_TIMEFRAMES timeframe;
   SwingState      swing;
   int             lastBosDirection;     // 1 bull BOS, -1 bear BOS, 0 none
   double          lastBosLevel;
   datetime        lastBosBarOpenTime;
   datetime        lastBrokenLegEndTime;
   double          lastBrokenLegHigh;
   double          lastBrokenLegLow;
};

#define BIAS_BULLISH  1
#define BIAS_BEARISH -1
#define LiquidityPoolCapacity 32

struct ProfessionalBiasOverrideState
{
   int      overrideBias;     // current TF direction: 1 bull / -1 bear / 0 unset
   datetime overrideTime;     // TF bar open when direction last changed
};
struct V2HuntSession
{
   bool     active;
   bool     h4HighWasBreached;
   double   h4BreachedLegLevelPrice;
   datetime h4BreachedLegEndTime;
   double   closeWhenH4LiquidityBreached;
   double   pathMinLowSinceH4Breach;
   double   pathMaxHighSinceH4Breach;
   double   impulseCloseExtremeSinceH4Breach;
   datetime sessionId;
   double   lastEngulfPairExtremeChecked; // bear: pair high; bull: pair low; 0=none yet
   bool     tradeOrdersActive;
   datetime ordersFvgFormationTime;
   bool     tradeIsBuy;
   double   tradeEntryPrice;
   double   tradeTp1Price;
   double   preEntryCancelTpLevel;
   bool     firstOppBosMgmtDone;
};

#define H4_LIQUIDITY_PIVOT_CAPACITY 600
#define H4_REPLAY_LEG_CAPACITY      512

// M15 leg-close event captured for open-trade TP management (see ManageHuntTradeM15LegCloseTp).
struct M15ClosedLegSnapshot
{
   bool     ready;
   int      direction;   // closed leg: 1 = up, -1 = down
   double   legHigh;
   double   legLow;
   datetime legStartTime;
   datetime legEndTime;
};

struct H4LiquidityPivot
{
   double   levelPrice;
   datetime legEndTime;
   double   legHighPrice;
   double   legLowPrice;
   int      swingDirection; // 1 = up leg (high liquidity), -1 = down leg (low liquidity)
};

struct H4ReplayLeg
{
   double   legHighPrice;
   double   legLowPrice;
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection;
};

#ifdef H4_LQ_VOLUME_BREACH_ENABLED
#define H4_LEG_VOLUME_BREACH_CAPACITY 24

struct H4LegVolumeBreachRecord
{
   datetime legStartTime;
   datetime legEndTime;
   int      swingDirection;
   double   breachLevelPrice;
   datetime volumeBarOpenTime;
   bool     swept;
};

struct H4ActiveLegVolumeBreachTrack
{
   datetime legStartTime;
   int      swingDirection;
   datetime windowStartOpenTime;
   long     maxTickVolume;
   datetime maxVolumeBarOpenTime;
   double   breachLevelPrice;
};

#endif // H4_LQ_VOLUME_BREACH_ENABLED

#endif // H4_LQ_V3_H4LQV3TYPES
