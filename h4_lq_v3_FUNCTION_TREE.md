# h4_lq_v3 — Function Tree & Vibe-Coding Guide

**Version:** 3.84 (`h4_lq_v3.mq5`, ~8,480 lines)  
**Purpose:** MTF SMC confluence scoring + M2 swing-sweep / engulf absorption entry + swing-group take profits.

**Related files (read these too):**

| File | Role |
|------|------|
| `ConfluenceScoring.mqh` | Zone location score + BOS alignment weights → `CalculateTotalTradeScore` |
| `ScoreLogger.mqh` | Optimization CSV: running P100 write / read for tester risk sizing |
| `merge_optimization_scores.py` | Merge 8-agent `optimization_permutation_summary.csv` files |

**Compile:**

```text
"C:\Program Files\MetaTrader 5\MetaEditor64.exe" /compile:...\h4_lq_v3.mq5
```

---

## Architecture overview

```
OnTick (every tick)
├── UpdateMTFSwings()          → W1/D1/H4/M15 bar close: swing step, zones, BOS, H4 pivots
└── optional M2 live swing visuals

OnTick (new M2 bar)
├── ProcessHuntEngulfingOnM2BarClose()   ← ONLY LIVE ENTRY PIPELINE
│   ├── CalculateSetupTradeScore (bull/bear) → LogAllSetupScores if score > 0
│   └── V3TryScanM2SwingSweepSetup → TryPlaceEngulfAbsorptionTradeSetup
├── ProcessM2SwingStep()       → g_m2Swing leg tracking (TP lookback + visuals)
└── ManageHuntOpenPositionsOnM2BarClose()

OnTimer (1 sec, when limit/stop pendings armed)
└── ProcessPendingEntryOrderExpiry()   → cancel unfilled pendings after T seconds
```

**v3.84 note:** All v2 hunt-session / touch-vol / opposite-FVG / M2 FVG trade paths were **removed**. There is no hunt arming, no `TryPlaceTouchVolumeBarTradeSetup`, no `TryPlaceOppositeFvgTradeSetup`. Engulf sweep on M2 bar close is the sole entry model.

---

## Global state (what to grep first)

| Symbol | Description |
|--------|-------------|
| `g_mtfSwingW1/D1/H4/M15` | `MTFSwingTracker` — swing history + last BOS per TF |
| `g_activeZones[]` | Persistent SMC zone ledger (`SMCZoneRecord`) — scoring source |
| `g_mtfFvgInstances[]` | MTF FVG instances (separate from swing/protected zones) |
| `g_zoneMitigationLedger[]` | Mitigated zone history (FIFO) |
| `g_m2Swing` | M2 `SwingState` — entry TP scan replays this |
| `g_v2Hunts[]` | Two slots — **order session metadata only** (comment prefix, trade watch); hunts never armed |
| `g_h4DescHighPivots[]` / `g_h4AscLowPivots[]` | H4 liquidity pivot arrays (chart/analysis) |
| `g_riskScoreP100` / `g_scoreLogP100` | Score logger read/write (see ScoreLogger.mqh) |
| `g_pendingEntryOrderExpiry*` | Limit/stop pending auto-cancel timer state |
| `g_trade` | `CTrade` — all order sends |

**Constants:** `LQ_TP_COUNT = 3` swing TPs + optional 1× fixed **2R addon** order (`TryPlaceFvgTradeDoubleRiskAddonOrder`).

---

## 1. EA lifecycle

| Function | Description |
|----------|-------------|
| `OnInit()` | Clears chart objects; warms M2 + MTF swings; resets zones/FVGs; init score logger; optional HUD. |
| `OnDeinit()` | `FlushScoreLogToFile()` if write mode; kills pending-expiry timer; deletes all EA chart objects. |
| `OnTick()` | MTF swing updates every tick; on **new M2 bar** → engulf pipeline, M2 swing step, position mgmt, HUD. |
| `OnTimer()` | `ProcessPendingEntryOrderExpiry()` — cancel unfilled limit/stop orders after `InputPendingOrderExpirySeconds`. |

**Warmup**

| Function | Description |
|----------|-------------|
| `WarmupM2SwingFromHistory()` | Replays `InputM2SwingWarmupBars` through `ProcessSwingStepAtShift(g_m2Swing, …)`. |
| `WarmupMTFSwingsFromHistory()` | Replays `InputSmcMtfWarmupBars` per TF; seeds zones via `SMCSeedSwingZonesFromHistory`. |

---

## 2. Performance & mode gates

| Function | When true |
|----------|-----------|
| `H4LqLoggingEnabled()` | `!InputFastTesterMode && InputLogHuntEvents` — gates `PrintFormat` / hunt logs. |
| `H4LqChartDrawEnabled(flag)` | `!InputFastTesterMode && flag` — gates all `ObjectCreate` / HUD. |
| `ScoreLogWriteModeSkipsTrading()` | `InputScoreLogWriteCsv` — **skips** sweep scan, TP calc, orders (score-only pass). |
| `InputFastTesterMode` | Disables logs + chart objects; **does not** disable zone engine or scoring. |

| Function | Description |
|----------|-------------|
| `LogHuntEvent()` | Experts log with M2 bar timestamp. |
| `V2LogHuntEvent(huntIndex, …)` | Session-prefixed log (`HS{sessionId}`); live path uses `huntIndex = -1`. |

---

## 3. MTF swing engine (W1 / D1 / H4 / M15)

**Tick entry:** `UpdateMTFSwings()` → `SMCUpdateTrackerOnBarClose` per TF.

```
SMCUpdateTrackerOnBarClose(tracker, TF, lastBarOpen)
├── ProcessMTFSwingStepAtShift(tracker.swing, TF, shift=1, H4_BOS_ANCHOR_MULTIPLIER)
├── SMCRefreshZonesForTimeframe(TF, tracker, legClosedThisBar)
├── SMCUpdateTrackerBosOnBar(tracker, 1)
└── if H4: RebuildH4LiquidityPivotLevels(), LogH4TradeDirectionBiasIfChanged()
```

| Function | Description |
|----------|-------------|
| `ProcessMTFSwingStepAtShift` / `ProcessMTFSwingStepAtShiftCollect` | Generic swing flip on close vs anchor; leg close → history. |
| `ProcessSwingStepAtShift` | Shared swing step (M2 + MTF). Anchor multiplier differs per TF. |
| `SwingStartNew` / `SwingExtend` | Leg open / extend. |
| `SwingCloseH4ToHistory` | Push completed leg to 20-leg ring buffer. |
| `MtfTryNthCompletedSwingLeg` | Nth-from-latest completed leg on a TF. |
| `SMCGetMtfSwingTracker` | Resolve `g_mtfSwingW1` etc. by timeframe. |
| `SMCTryDetectBosOnBar` | BOS = close breaks prior same-dir leg extreme. |
| `SMCUpdateTrackerBosOnBar` | Updates `tracker.lastBosDirection/Level` on BOS bar. |

**Professional bias (trade filter + HUD)**

| Function | Description |
|----------|-------------|
| `GetProfessionalBias(TF)` | BOS default; zone touch + close-outside can override (W1/D1/H4). |
| `ProfessionalBiasSetDirection` | Sets override on zone bar close. |
| `SMCUpdateProfessionalBiasFromZoneBarClose` | Called per zone TF bar close. |
| `GetH4TradeDirectionBias` | Wrapper for H4 filter (`InputEnableH4BosTradeDirectionBias`). |
| `FvgTradeAllowedByH4BosBias` | Blocks trades against H4 bias. |
| `RefreshMtfDirectionHud` | Top-right W1/D1/H4/M15 bias arrows. |

---

## 4. SMC zone ledger & FVGs

**Zone types:** `ENUM_SMC_ZONE_TYPE` — MTF FVG, protected extremes, swing high/low per TF (28+ zone kinds).

**Lifecycle (per zone TF bar close):**

```
SMCRefreshZonesForTimeframe
├── on leg close: SMCRegisterSwingZoneFromJustClosedLeg (new zone only that bar)
├── SMCAdvanceZoneBreachLedgerOnBarClose (wick enter → isBreached)
├── SMCApplyZoneExitBiasAndMitigationForTimeframe (close outside → mitigate)
├── SMCExpireZonesPastBarLimitForTimeframe
├── SMCUpdateMtfFvgInstancesMitigationForTimeframe
└── SMCSyncZoneRectanglesForTimeframe / SMCSyncMtfFvgZoneRectanglesForTimeframe
```

| Function | Description |
|----------|-------------|
| `RegisterOrMergeZone` | Add/update slot in `g_activeZones[]`; merge swing zones by leg origin time. |
| `SMCDeactivateZoneLedgerSlot` | `isActive=false` on mitigation/expiry. |
| `SMCMitigateOverlappingMtfFvgPeers` | Cascade-mitigate overlapping same-TF FVG peers. |
| `UpdateSMCZoneMatrix` | Full matrix rebuild (init / warmup). |
| `SMCMapUnbrokenSwingZones` | Maps unbroken swing highs/lows into zone ledger. |
| `SMCRegisterLiquidityHighZone` / `LowZone` | One-sided buffer bands (10% chart height). |

**Key rules (v3.54+):** Zones are **additive** (no destructive refresh). Mitigation = wick into zone then **close outside**. Expiry = `InputSmcZoneExpiryBars` on zone TF. Bull zones register **below** price; bear **above**.

MTF FVG instances in `g_mtfFvgInstances[]` feed **scoring only** — not the live trade entry path.

---

## 5. Confluence scoring (`ConfluenceScoring.mqh`)

**Called from:** `CalculateSetupTradeScore`, `CalculateSetupTradeScoreFromStopLoss`, trade placement for lot sizing.

```
CalculateSetupTradeScore(isBuy)
└── V3ResolveSetupExtremesForZoneScoring → setup low/high
└── CalculateTotalTradeScore(isBuy, setupLow, setupHigh)
    ├── locationScore: active zones where probe inside zone [bottom, top]
    │   └── bull: setup **low** must be in zone; bear: setup **high**
    └── bosScore: ± InputWeight_*_BOS per TF vs trade direction
```

| Function | Description |
|----------|-------------|
| `GetOptimizedZoneWeight(type)` | Maps zone type → FVG or HighLow weight inputs. |
| `SMCAlignmentContribution` | +weight if BOS aligned, −weight if opposed. |
| `GetMaxPossibleScore()` | Theoretical max (fallback risk denom). |
| `SetupScoreAllowsTradeEntry(score)` | `score >= InputMinScore` (signed; 0 blocks negatives). |
| `GetRiskNormalizationScore()` | Tester: CSV P100; else theoretical max. |
| `GetOptimizedLotSize(entry, sl, score, isBuy, riskFraction)` | `InputBaseRiskPercent × |score|/denom × fraction`. |

**Setup extremes for scoring:** `V3ResolveSetupExtremesForZoneScoring` uses bar 1 high/low; if sweep pattern detected, replaces with countdown window SL extreme.

---

## 6. Score logger & optimization workflow (`ScoreLogger.mqh`)

| Mode | `InputScoreLogWriteCsv` | Behavior |
|------|-------------------------|----------|
| **Write** | `true` | Track `g_scoreLogP100` (int max); **no TP/orders**; flush CSV on deinit. |
| **Read** | `false` (tester) | Load P100 from `optimization_permutation_summary_combined.csv` or `_summary.csv`. |

| Function | Description |
|----------|-------------|
| `InitScoreLogPermutationFile(...)` | Stores weight permutation key; sets write mode. |
| `LogAllSetupScores(score)` | Updates running max if `score > 0`. |
| `FlushScoreLogToFile()` | Upserts row in agent `MQL5\Files\optimization_permutation_summary.csv`. |
| `InitRiskScoreP100FromPermutationSummary()` | Read combined CSV first, then per-agent summary. |

**Two-pass optimization:**

1. Write mode ON → run all permutations → merge 8 agents → `optimization_permutation_summary_combined.csv`
2. Write mode OFF → backtest with CSV-based risk sizing

---

## 7. M2 swing engine

| Function | Description |
|----------|-------------|
| `ProcessM2SwingStep()` | On M2 bar close: `ProcessSwingStepAtShift(g_m2Swing, M2, …)` + optional live draw. |
| `SwingCloseM2Leg` | Close M2 leg + trend line draw. |
| `UpdateM2LiveSwingLegVisualOnTick` | Extends open leg line each tick. |
| `UpdateM2SwingAnchorVisualRealtime` | Yellow anchor line at flip level. |
| `V2TryGetLastCompletedM2Leg` | Used by exhaustion validation (last 2 same-dir legs). |

Used heavily by **TP builder** (replay swing history backward from formation bar).

---

## 8. v3 entry model — M2 swing sweep + engulf

**Main hook:** `ProcessHuntEngulfingOnM2BarClose()` (every M2 bar close).

```
ProcessHuntEngulfingOnM2BarClose
├── bullScore = CalculateSetupTradeScore(true)  → LogAllSetupScores if > 0
├── if !ScoreLogWriteModeSkipsTrading && score OK:
│       V3TryScanM2SwingSweepSetup(true, barClose, bullScore)
└── (mirror for bear)
```

**Sweep pipeline:**

```
V3TryScanM2SwingSweepSetup
├── V3M2SwingSweepSetupPatternValidCore
│   ├── V3DetectM2SwingSweepRejectInCountdown   (wick sweep + close reject)
│   ├── V3EngulfPairLocalExtremeBandValid       (-2%..+20% local extreme band)
│   ├── V3ValidateM2LegExhaustion               (volC > volB on last 2 same-dir legs)
│   └── SL = windowSlExtreme from countdown
└── TryPlaceEngulfAbsorptionTradeSetup(-1, …, signalBarOpen, signalBarOpen, setupScore)
    └── huntSessionId = signal bar open time (not a hunt slot)
```

| Function | Description |
|----------|-------------|
| `V3DetectM2SwingSweepRejectInCountdown` | `InputEngulfSweepCountdownBars` window; multi-level sweep picks extreme. |
| `V3TryGetM2SwingLegRefLevel` | Reference swing extreme for sweep. |
| `V3ValidateM2LegExhaustion` | Leg range ≥ `InputEngulfExhaustionMinLegRangePercentChart`; volume exhaustion. |
| `V3SwingLegRefVolumeSpikeValid` | Vol spike at ref leg (formation validation). |
| `V3EngulfPairLocalExtremeBandValid` | Local extreme band filter on engulf pair. |

---

## 9. Trade placement & take profits

**Single live path:** `TryPlaceEngulfAbsorptionTradeSetup`.

```
TryPlaceEngulfAbsorptionTradeSetup
├── gates: score, H4 BOS bias, ResolveHuntFvgOrderPlacementGate (no open position for session)
├── referenceEntry = bar close; orderEntry = ResolveTradeEntryPriceForOrderType(...)
├── ApplyTouchVolMinimumSlDistance (alias: InputEngulfMinSlPoints / engulf SL buffer)
├── BuildTradeSwingGroupTakeProfits(orderEntry, …)
│   ├── Pass 1: cluster ≥2 swings within 10% chart band → line TP (min R:R 2.0, 2% front-run)
│   ├── Pass 2 (fallback): solo swings if count < 3; 10% proximity vs cluster TPs
│   └── cap at LQ_TP_COUNT (3)
├── broker StopsDistanceAllowed per TP
├── IsFvgAutomatedTradingAllowed (InputEnableAutomatedTrading + terminal flags)
├── PlaceFvgTradeOrderForSetup × N  (comments: OV_TP1..3, risk 3:1:1)
├── TryPlaceFvgTradeDoubleRiskAddonOrder  (OV_2R_, full risk fraction)
└── FinalizeTradePlacementBatch → RegisterHuntTrade + arm pending expiry if limit/stop
```

### Order type (v3.83+)

| `InputTradeEntryOrderType` | Value | Placement |
|----------------------------|-------|-----------|
| Limit | 0 | `BuyLimit` / `SellLimit` @ reference entry |
| Market | 1 | `Buy` / `Sell` at ask/bid |
| Stop | 2 | `BuyStop` / `SellStop` @ reference + `InputPendingStopEntryOffsetPoints` |

| Function | Description |
|----------|-------------|
| `ResolveTradeEntryPriceForOrderType` | Maps reference → limit / market / stop price. |
| `M2PendingStopEntryPrice` | Stop entry above/below reference (broker stops-level aware). |
| `PlaceOneFvgTradeOrder` | Low-level `CTrade` send by `ENUM_TRADE_ENTRY_ORDER_TYPE`. |
| `PlaceFvgTradeOrderForSetup` | Resolves entry from reference + `InputTradeEntryOrderType`. |
| `ValidateTradeOrderEntryVsStop` | Ensures entry on correct side of SL. |
| `FinalizeTradePlacementBatch` | Registers trade; arms expiry timer for pending types. |
| `ProcessPendingEntryOrderExpiry` | After T sec, `CancelOurHuntPendingOrders` + log `PENDING_EXPIRE`. |

| Function | Description |
|----------|-------------|
| `BuildTradeSwingGroupTakeProfits` | **Skipped** when `ScoreLogWriteModeSkipsTrading()`. |
| `CollectM2SwingExtremesBackwardFromFormation` | Replays M2 swing + optional drawn legs in lookback window. |
| `AppendIndividualSwingTakeProfitLevels` | Solo fallback TP levels. |
| `GetOptimizedLotSize` | Score-normalized lots per TP fraction. |
| `ComputeDoubleRiskTakeProfitPrice` | Entry ± 2× SL distance. |
| `RegisterHuntTradeAfterSuccessfulPlace` | Records global hunt trade watch + optional slot metadata. |
| `ResolveHuntFvgOrderPlacementGate` | Blocks if open position exists for session comment prefix. |

**Order count:** up to **3 swing TPs + 1× 2R addon = 4 orders** (fewer if not enough qualifying swing levels).

**Log-only mode:** `InputEnableAutomatedTrading=false` still runs TP calc; logs `TRADE_PLAN` then returns before orders.

**Pending expiry:** `InputPendingOrderExpirySeconds` (0 = off). Applies to limit and stop only; market fills immediately.

---

## 10. Open trade management

| Function | Description |
|----------|-------------|
| `ManageHuntOpenPositionsOnM2BarClose()` | Once per M2 bar: tiered SL + first opposite BOS mgmt. |
| `ManageHuntTradeTieredStopLoss` | Trail/adjust SL on open hunt trades. |
| `HasOurHuntTradeOpenPosition` | Magic + `LQ2_HS` comment prefix check. |
| `HuntTradeCommentIsOvTpIndex` | Match `OV_TP1..3` in order comment. |
| `CancelOurHuntPendingOrders` | Delete pending orders for session (or all `LQ2_HS`). |
| `HasOurHuntPendingEntryOrders` | Detect unfilled limit/stop pendings for expiry logic. |

---

## 11. Remaining `V2*` helpers (not hunt pipeline)

These survived v3.84 cleanup — **naming legacy only**:

| Function | Still used for |
|----------|----------------|
| `V2HuntTradeCommentPrefix` | Order comments: `LQ2_HS{sessionId}_OV_TP…` |
| `V2FindHuntSlotBySessionId` | Optional slot lookup when registering trades |
| `V2InitHuntSlot` / `V2InitAllHuntSlots` | OnInit zero state |
| `V2LogHuntEvent` | Prefixed Experts logging |
| `V2HuntHasOpenPositionForSession` | Placement gate |
| `V2HuntHasPendingOrdersForSession` | Pending-order checks |

**Removed in v3.84:** hunt arming, touch-vol entry, opposite FVG entry, FVG memory, touch-recalc buffers, impulse buffer, chart-range pending cancel, all `{}` stub blocks.

**Optional compile flag:** `#define H4_LQ_VOLUME_BREACH_ENABLED` — H4 breach memory + chart markers only; does **not** restore hunt trade entry.

---

## 12. Chart objects & prefixes

| Prefix / object | Drawn by |
|-----------------|----------|
| `LQ2_TRD_SWG_R_` / `LQ2_TRD_SWG_L_` | Swing-group TP zones/lines |
| `LQ_OBJ_PREFIX_SMC_ZONE_RECT` | SMC zone rectangles |
| MTF swing trends | `DrawMtfClosedSwingLegVisual` |
| `PFX_M2_TREND` / `PFX_M2_LBL` / `PFX_M2_ANCHOR` | M2 swing visuals |
| `LQ_OBJ_MTF_BIAS_HUD_*` | MTF direction HUD |
| `LQ_OBJ_HUNT_HUD` | `v3: engulf scan ON/OFF` status label |

All gated by `H4LqChartDrawEnabled()` + per-input `InputDraw*` flags.

---

## 13. Key event flow (v3.84 happy path)

```
1. Every tick: MTF bar closes → zones update, BOS, bias, FVG register/mitigate
2. M2 bar close: CalculateSetupTradeScore (uses active zones + BOS)
3. If score ≥ InputMinScore and write-mode OFF:
   a. Sweep ref extreme in countdown window
   b. Local extreme band + exhaustion pass
   c. BuildTradeSwingGroupTakeProfits (cluster → solo fallback)
   d. Place 1–3 OV_TP orders (+ optional 2R) via InputTradeEntryOrderType
   e. If limit/stop: arm pending expiry timer
4. ManageHuntOpenPositionsOnM2BarClose while trades open
5. OnTimer: cancel unfilled limit/stop pendings after T seconds
```

**Optimization-only path (`InputScoreLogWriteCsv=true`):**

```
M2 bar close → CalculateSetupTradeScore → LogAllSetupScores → (no sweep, no TP, no orders)
OnDeinit → FlushScoreLogToFile
```

---

## 14. Inputs → code map (quick reference)

| Input | Affects |
|-------|---------|
| `InputFastTesterMode` | All logging + chart objects |
| `InputEnableEngulfHuntAfterH4Breach` | Entire M2 entry + score init + HUD text |
| `InputScoreLogWriteCsv` | Write P100 vs read P100; **skips trading** when true |
| `InputEnableAutomatedTrading` | Order send vs `TRADE_PLAN` log only |
| `InputTradeEntryOrderType` | Limit / market / stop placement |
| `InputPendingStopEntryOffsetPoints` | Stop order offset from reference |
| `InputPendingOrderExpirySeconds` | Auto-cancel unfilled limit/stop (0=off) |
| `InputMinScore` | Entry gate + score log threshold |
| `InputBaseRiskPercent` | Lot sizing at P100 (or theoretical max) |
| `InputWeight_*` / `InputWeight_*_BOS` | Scoring + CSV permutation key |
| `InputTradeSwingLookbackM2Bars` | TP swing scan depth (292) |
| `InputTradeSwingProximityPercentOfChartRange` | TP cluster band (10%) |
| `InputTradeSwingTpMinRewardToRisk` | Min R:R for TP lines (2.0) |
| `InputEngulfSweepCountdownBars` | Sweep window (2) |
| `InputEngulfExhaustionMinLegRangePercentChart` | Exhaustion leg size filter |
| `InputEngulfSlBufferPercentChart` / `InputEngulfMinSlPoints` | SL distance (via `ApplyTouchVolMinimumSlDistance`) |
| `InputSmcZoneExpiryBars` | Zone scoring expiry (292 on zone TF) |
| `InputEnableH4BosTradeDirectionBias` | H4 bias trade filter |
| `InputDraw*` / `InputShow*` | Individual chart layers |

---

## 15. Vibe-coding cheat sheet

**“Score feels wrong”** → `ConfluenceScoring.mqh` + `g_activeZones[]` lifecycle in `SMCApplyZoneExitBiasAndMitigationForTimeframe`. Check `isActive`, zone TF expiry, probe price (`V3ResolveSetupExtremesForZoneScoring`).

**“No trades”** → `ProcessHuntEngulfingOnM2BarClose` → `SWEEP_SKIP` logs → exhaustion / local band / min score. If write mode ON, trading is intentionally off.

**“No TPs / TRADE_SKIP”** → `BuildTradeSwingGroupTakeProfits` → cluster/solo fallback logs. Need ≥1 swing level passing R:R; cluster needs 2+ swings in 10% band.

**“Limit/stop never fills”** → check `InputPendingOrderExpirySeconds`; look for `PENDING_EXPIRE` in Experts tab.

**“Wrong entry price”** → `InputTradeEntryOrderType` + `ResolveTradeEntryPriceForOrderType` / `M2PendingStopEntryPrice`.

**“Lots too big/small”** → `GetOptimizedLotSize` + `GetRiskNormalizationScore` + CSV P100. Read mode needs combined CSV in agent `MQL5\Files\`.

**“Zones missing on chart”** → `InputDrawMtfSwingLegsH4` etc. + `H4LqChartDrawEnabled`. Zones still score without draw.

**“Change entry logic”** → Start at `V3M2SwingSweepSetupPatternValidCore` and `V3DetectM2SwingSweepRejectInCountdown`.

**“Change TP logic”** → `BuildTradeSwingGroupTakeProfits`, `CollectM2SwingExtremesBackwardFromFormation`, `AppendIndividualSwingTakeProfitLevels`.

**“FVG not mitigating”** → `SMCUpdateMtfFvgInstancesMitigationForTimeframe`, `SMCMitigateOverlappingMtfFvgPeers`.

---

## 16. Function index by prefix

| Prefix | Area |
|--------|------|
| `SMC*` | MTF zones, FVG instances, bias, registration, mitigation |
| `V3*` | Engulf / sweep entry model (v3) |
| `V2*` | Comment prefix, logging, slot init, session order checks (legacy naming) |
| `Mtf*` / `MTF*` | Multi-timeframe swing legs |
| `H4*` | Liquidity pivots, breach memory (ifdef), bias logging |
| `BuildTrade*` / `CollectM2*` / `PlaceFvg*` / `PlaceOne*` | Trade TP + execution |
| `ResolveTrade*` / `M2PendingStop*` / `ProcessPending*` / `ArmPending*` | Order type + expiry |
| `ScoreLog*` / `LogAllSetupScores` | Optimization CSV (ScoreLogger.mqh) |
| `Calculate*` / `GetOptimized*` | Scoring + sizing |
| `ManageHunt*` / `HuntTrade*` | Open position + pending order management |
| `H4Lq*` / `ScoreLogWriteMode*` | Performance gates |

---

## 17. Version history pointer

Inline changelog in `h4_lq_v3.mq5` header (`//| v3.xx:`). Latest notable:

- **v3.84** — remove dead v2 FVG/touch-vol/hunt-session code (~2,780 lines); engulf-only live path
- **v3.83** — entry order type input (limit/market/stop) + pending order expiry timer
- **v3.82** — score write mode skips TP + orders
- **v3.81** — running int P100 (no score array)
- **v3.79–80** — solo TP fallback + proximity vs cluster TPs
- **v3.77** — price-in-zone scoring (bull low / bear high)
- **v3.54+** — persistent zone ledger

---

*Generated for `h4_lq_v3.mq5` v3.84. Search function names in source for line-level detail.*
