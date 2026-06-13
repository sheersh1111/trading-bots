# h4_lq_v2 — Function Tree & Descriptions

**Version:** 2.55 (`h4_lq_v2.mq5`)  
**Purpose:** H4 primary narrative + M2 execution — H4 liquidity breach → hunt → touch validation → volume-bar entry → swing-group TPs.

---

## Architecture overview

```
OnInit / OnTick / OnTimer
├── H4 bar close  → swing legs, volume breach levels, BOS, pivots
├── M2 bar close  → swing legs, hunt processing, breach detection, trades
└── Every tick    → pre-entry cancel checks, optional M2 live visuals
```

**Global state (main structs):**
- `g_h4Swing` — H4 swing legs for breach/hunt (anchor 0.5)
- `g_h4BosSwing` — separate H4 swing track for BOS bias (anchor 1.0)
- `g_m2Swing` — M2 swing legs for FVG, touch, entry management
- `g_v2Hunts[]` — up to `V2_MAX_HUNT_SESSIONS` concurrent hunt sessions
- `g_h4LegVolumeBreaches[]` — cached max-volume breach level per completed H4 leg

---

## 1. EA lifecycle

| Function | Description |
|----------|-------------|
| `OnInit()` | Clears chart objects, zeroes swing/hunt/trade state, runs H4/M2 warmup, rebuilds breach cache & liquidity pivots, starts 1s timer, optional HUD init. |
| `OnDeinit()` | Kills timer, deletes all EA chart objects. |
| `OnTick()` | Pre-entry TP3 / FVG-range cancel checks; on new H4 bar → swing, BOS, pivots, breach rays; on new M2 bar → hunt window, M2 swing, open-position mgmt, hunt HUD. |
| `OnTimer()` | Same cancel checks as tick (backup for tester). |

**Warmup**

| Function | Description |
|----------|-------------|
| `WarmupH4SwingFromHistory()` | Replays `InputWarmupBars` closed H4 bars through `ProcessH4SwingStep`. |
| `WarmupM2SwingFromHistory()` | Replays `InputM2SwingWarmupBars` closed M2 bars through `ProcessM2SwingStep` (`replayOnly=true`). |

---

## 2. Performance & logging gates

| Function | Description |
|----------|-------------|
| `H4LqLoggingEnabled()` | `true` when `InputFastTesterMode=false` and `InputLogHuntEvents=true`. Gates all `PrintFormat` hunt logs. |
| `H4LqChartDrawEnabled(featureFlag)` | `true` when fast tester off and per-feature draw flag on. Gates all `ObjectCreate` / HUD updates. |
| `LogHuntEvent()` | Experts-tab log with M2 bar timestamp prefix. |
| `V2LogHuntEvent(huntIndex, …)` | Hunt-session prefixed log (`HS{sessionId}`). |

---

## 3. H4 swing engine

**Entry points**

| Function | Calls |
|----------|-------|
| `ProcessH4SwingStep(shift)` | `ProcessH4SwingStepCore(g_h4Swing, …, breachContext=true)` + `ProcessH4BosSwingStep` |
| `ProcessH4BosSwingStep(shift)` | `ProcessH4SwingStepCore(g_h4BosSwing, …, breachContext=false)` |

**Core swing mechanics**

| Function | Description |
|----------|-------------|
| `ProcessH4SwingStepCore()` | On each closed H4 bar: extend/flip swing leg via anchor multiplier; on leg close → history, volume breach finalize, hunt leg callback. |
| `ProcessSwingStepAtShift()` | Generic swing step (used by H4 core and M2). Compares bar range vs prior 5-bar average × anchor; flip on close cross of `priceAnchorLevel`. |
| `SwingStartNew()` | Opens new leg at bar open; sets direction, anchor, extremes. |
| `SwingExtend()` | Updates running leg high/low. |
| `SwingCloseH4ToHistory()` | Pushes completed leg to 20-leg ring buffer; triggers `H4FinalizeActiveLegVolumeBreach`, `V2OnH4LegClosedForHunts`. |
| `SwingCloseH4Context()` | Closes leg + pushes liquidity pool + optional H4 trend line draw. |
| `PushLiquidityPoolFromClosedSwing()` | Records supply/demand pool from closed leg (legacy pool array). |

**H4 leg lookups**

| Function | Description |
|----------|-------------|
| `TryNthH4CompletedSwingLeg(dir, n, …)` | Nth-from-latest completed leg in `g_h4Swing.swingHistory`. |
| `TryLatestH4CompletedUpLegHigh` / `DownLegLow` | Convenience wrappers for n=1. |
| `TrySecondLastH4CompletedUpLegHigh` / `DownLegLow` | Convenience wrappers for n=2. |

---

## 4. H4 volume breach (liquidity level)

Breach level = **low/high of highest-volume H4 bar** in a leg window (not raw swing extreme).

**Window & scan**

| Function | Description |
|----------|-------------|
| `H4TryGetLegVolumeBreachWindowStartForScan()` | Window start from last “decent” bar on previous completed leg. |
| `H4TryGetLegVolumeBreachWindowEndForScan()` | Window end from last decent bar on leg being scored. |
| `H4TryResolveLegVolumeBreachWindowEnd()` | Resolves end for active (open) leg using last closed bar shift. |
| `H4ScanVolumeWindowMonotonic()` | Scans H4 tick volumes; tracks max-vol bar + breach price. |
| `ComputeH4LegVolumeBreachLevel()` | Full breach computation for one completed leg pair (last + prev). |
| `H4BreachLevelPriceFromVolumeBar()` | Up leg → bar low; down leg → bar high. |
| `FindMaxVolumeH4BarBetweenOpenTimes()` | Simple max-vol scan between two open times. |

**Active leg tracking (live update while leg open)**

| Function | Description |
|----------|-------------|
| `H4OnH4ActiveLegStarted()` | Initializes `g_h4ActiveLegVolumeTrack` when new H4 leg starts. |
| `H4OnH4ActiveLegBarClosed()` | Extends volume scan each H4 bar close on active leg. |
| `H4FinalizeActiveLegVolumeBreach()` | Commits active track to breach cache when leg closes. |
| `H4RestoreActiveLegVolumeBreachTrackFromSwing()` | Rebuilds active track after warmup/history replay. |
| `H4ResetActiveLegVolumeBreachTrack()` | Clears in-progress active-leg scan. |

**Cache & activation**

| Function | Description |
|----------|-------------|
| `RememberH4LegVolumeBreachRecord()` | Stores breach level + volume bar time keyed by leg end. |
| `TryGetH4LegVolumeBreachLevel()` | Lookup breach record by leg end + direction. |
| `TryResolveH4LegVolumeBreachLevel()` | Resolves level for leg (cache or recompute). |
| `IsH4LegVolumeBreachActiveInBufferWindow()` | Leg eligible for hunt if vol bar or leg end within `InputH4BreachBufferChartBarCount` H4 bars. |
| `IsH4VolumeBreachLevelAlreadyBreached()` | True if level already swept (prevents re-hunt). |
| `RememberH4VolumeBreachLevelSwept()` | Marks level swept after price violates it post-formation. |
| `WasH4VolumeBreachLevelViolatedSinceFormation()` | M2 scan: close beyond breach level since volume bar. |
| `RebuildH4LegVolumeBreachLevelsFromSwingHistory()` | Rebuilds entire breach cache from swing history. |
| `H4ClearVolumeBreachMemoryAndChart()` | Wipes breach memory + chart rays (post-warmup realtime attach). |
| `UpdateH4LegLiquidityBreachMemoryOnM2Bar()` | Each M2 bar: mark swept levels, skip stale hunts. |

**Chart**

| Function | Description |
|----------|-------------|
| `DrawH4VolumeBreachLevelRay()` | Horizontal ray from max-vol bar at breach level (green up / pink down). |
| `RebuildAllH4VolumeBreachMarkers()` | Redraws all active breach rays. |
| `DeleteH4VolumeBreachLevelRay()` | Removes ray for one leg. |

**Decent-movement helpers (window bounds)**

| Function | Description |
|----------|-------------|
| `H4BarHasDecentMovementForLegDirection()` | Body direction matches leg + body ≥ threshold vs wick range. |
| `H4TryGetLegLastDecentMovementBarOpen()` | Finds last decent bar in leg range. |
| `H4TryGetVolumeBreachWindowBoundFromLastDecent()` | Nth-from-end decent bar open time. |

---

## 5. H4 breach buffer & hunt arming

| Function | Description |
|----------|-------------|
| `ReferenceChartHeightForH4BreachBuffer()` | H4 high−low over `InputH4BreachBufferChartBarCount` bars. |
| `H4BreachBufferBandForUpLegHigh()` | Near −2% / far +10% band below/up from high. |
| `H4BreachBufferBandForDownLegLow()` | Near +2% / far −10% band around low. |
| `M2WickCrossesIntoH4UpBreachBuffer()` | M2 wick enters up-leg breach buffer band. |
| `M2WickCrossesIntoH4DownBreachBuffer()` | M2 wick enters down-leg breach buffer band. |
| `M2WickCrossesAboveLevel()` / `BelowLevel()` | Wick cross helpers for level + buffer. |
| `TryDetectH4WickLiquidityBreachForLeg()` | Per-leg breach: buffer cross OR level cross → accept. |
| `TryDetectH4WickLiquidityBreach()` | Scans active breach records; returns first hit. |
| `TryAcceptH4BreachForHunt()` | Final gate: not already breached, records acceptance. |
| `V2ArmOppositeFvgHuntAfterH4Breach()` | Allocates hunt slot, sets polarity (high breach→bull FVG hunt), touch/buffer state, session id. |
| `H4BreachImpulseCancelZonePrices()` | Impulse cancel band at far buffer % — hunt OFF if close exceeds. |
| `RebuildH4LiquidityPivotLevels()` | Rebuilds pivot array from replay legs for analysis/legacy. |

---

## 6. H4 BOS & trade direction bias

| Function | Description |
|----------|-------------|
| `TryDetectH4BosCrossOnBar()` | Close cross beyond latest same-dir BOS swing leg extreme. |
| `ProcessH4BosOnH4Close()` | Cross → pending; next bar confirms or rejects. |
| `TryConfirmH4BosPendingOnBarClose()` | Confirms BOS if close holds beyond level; else `H4_BOS_REJECT`. |
| `H4BosCloseHoldsBeyondLevel()` | Confirmation candle validation. |
| `RecordH4BosBreak()` | Stores last valid BOS in `g_h4LastBosRecord`. |
| `GetH4TradeDirectionBias()` | Returns 1 / −1 / 0 from last confirmed H4 BOS (if enabled). |
| `FvgTradeAllowedByH4BosBias()` | Blocks trades against H4 BOS direction when filter on. |
| `LogH4TradeDirectionBiasIfChanged()` | Logs bias changes. |
| `RefreshH4BosBiasHud()` | Top-right ↑/↓ HUD. |

---

## 7. M2 swing engine

| Function | Description |
|----------|-------------|
| `ProcessM2SwingStep()` | Closed M2 bar → `ProcessSwingStepAtShift(g_m2Swing, …)`. |
| `SwingCloseM2Leg()` | Closes M2 leg to history; optional trend line + label; fires `OnM2SwingLegDirectionChange`. |
| `OnM2SwingLegDirectionChange()` | Dispatches leg change to touch-recalc buffer + hunt touch updates. |
| `UpdateM2LiveSwingLegVisualOnTick()` | Extends live M2 leg line to current bar (tick). |
| `UpdateM2SwingAnchorVisualRealtime()` | Horizontal anchor line at flip level. |
| `TryNthM2CompletedSwingLeg()` | Nth completed M2 leg by direction. |

---

## 8. FVG detection (M2)

| Function | Description |
|----------|-------------|
| `TryDetectFairValueGapPatternOnLastClosedBarM2()` | 3-bar FVG pattern on shift 1 (bull/bear gap). |
| `FairValueGapGapMeetsMinimumPercentOfRangeM2()` | Gap size vs M2 chart height % filter. |
| `ReferenceChartHeightForFairValueGapFilterM2()` | Chart height over `InputChartRangeBarCount` M2 bars. |
| `DetectFairValueGapOnLastClosedBarM2()` | Wrapper used outside hunt context. |

During hunt, FVGs are stored in `g_v2Hunts[i].fvgMem[]` and optionally drawn; they still matter for recalc-skip / hunt-off paths (touch entry uses volume bar, not FVG).

---

## 9. Hunt session (`V2*`)

### 9.1 Slot management

| Function | Description |
|----------|-------------|
| `V2InitAllHuntSlots()` / `V2InitHuntSlot()` | Zero hunt struct fields. |
| `V2AllocHuntSlot()` | First free slot in `g_v2Hunts[]`. |
| `V2FindHuntSlotBySessionId()` | Lookup by `sessionId` timestamp. |
| `V2FindActiveHuntByH4Leg()` | Active hunt for same H4 leg end + polarity. |
| `V2FindActiveHuntByBreachPolarity()` | Active hunt for same high/low breach type. |
| `V2EndOppositeFvgHuntSession()` | Sets `active=false`, clears visuals; optional pending FVG trade. |
| `V2AbortHuntSessionForRestart()` | Ends hunt without placing trade (superseded by new breach). |
| `V2OnH4LegClosedForHunts()` | Opposite H4 leg closed before touch → optional hunt OFF (`InputEndHuntOnOppositeH4LegBeforeTouch`). |

### 9.2 Main M2 hunt loop

```
ProcessBosOppositeFairValueGapWindow()
├── for each active hunt → V2ProcessOneActiveHuntOnM2Bar()
├── TryDetectH4WickLiquidityBreach() → V2ArmOppositeFvgHuntAfterH4Breach()
└── V2UpdateAllImpulseBufferZones() / V2UpdateAllTouchRecalcBufferZones()
```

| Function | Description |
|----------|-------------|
| `V2ProcessOneActiveHuntOnM2Bar()` | Per closed M2 bar: path extremes, touch-recalc buffer, impulse cancel, FVG detect/store, touch level update, touch+volume validation, gate logic. |
| `V2HuntExpectsBullishFvg()` | High breach → bull; low breach → bear. |
| `V2FvgPolarityMatchesHunt()` | FVG direction matches hunt expectation. |

### 9.3 Touch level

| Function | Description |
|----------|-------------|
| `V2TouchLevelFromLegExtreme()` | Bull: opposite up-leg high − buffer; bear: opposite down-leg low + buffer. |
| `V2TryGetOppositeM2LegExtentsForTouch()` | Opposite completed M2 leg for initial touch lock. |
| `V2TryGetOppositeM2LegExtentsForTouchRecalc()` | Active opposite leg if open, else last completed. |
| `V2TryLockTouchLevelFromM2Leg()` | Sets `touchLevel` once from opposite leg. |
| `V2TryRecalcTouchOnHuntSameDirProgress()` | Recalculates touch when price extends same-dir path extreme. |
| `V2TryDetectTouchOfStoredLevel()` | Close beyond touch level (bull above / bear below). |
| `V2DrawTouchPointLine()` / `V2ClearTouchPointLine()` | Yellow touch line while gate open. |

### 9.4 Touch volume validation

| Function | Description |
|----------|-------------|
| `V2TryGetM2TouchLegVolumeWindowBounds()` | Start: 3rd-to-last bar of last completed opposite M2 leg; end: touch bar. |
| `M2CollectTickVolumesInOpenTimeWindow()` | Tick volumes oldest→newest in window. |
| `M2ValidateTouchLegVolumeIncreasePattern()` | Ascending pattern: end > start, more increases than decreases. |
| `V2ValidateTouchHitOppositeM2LegVolume()` | Full validation wrapper. |
| `V2InvalidateTouchHitVolumeFailed()` | `TOUCH_GATE_OFF`, latch, clear touch line. |
| `V2HandleTouchHitConfirmed()` | Max-vol bar (excl oldest) → end hunt → `TryPlaceTouchVolumeBarTradeSetup`. |

### 9.5 Post-touch gate & recalc buffer

| Function | Description |
|----------|-------------|
| `V2TouchSideBlocksBufferRecalc()` | Blocks buffer/gate while close on wrong side of touch. |
| `V2TryReopenPostTouchFvgGateOnBufferHit()` | Reopens FVG gate after recalc buffer hit (strict zone overlap). |
| `V2DetectTouchRecalcBufferHit()` | Price in N% M2 band at hunt same-dir extreme or opposite buffer. |
| `V2TryTouchRecalcAfterBufferEvent()` | Runs touch recalc after buffer arm/freeze events. |
| `V2BeginTouchRecalcBufferActiveLegTrack()` | Tracks same-dir M2 leg extreme as buffer anchor. |
| `V2SyncTouchRecalcBufferAnchorFromActiveLeg()` | Updates anchor from live leg. |
| `V2TryArmTouchRecalcBufferResumeOnCross()` | Arms resume after price crosses frozen buffer. |
| `V2OnTouchRecalcBufferLegChange()` | Handles M2 leg flip for buffer state machine. |
| `V2UpdateTouchRecalcBufferZone()` | Draws hollow recalc buffer rect. |
| `V2UpdateImpulseBufferZone()` | Draws impulse cancel buffer rect. |

### 9.6 FVG memory & alternate trade paths

| Function | Description |
|----------|-------------|
| `V2PushHuntFvgMemory()` | Append FVG to hunt ring buffer. |
| `V2DrawHuntFairValueGapZone()` | FVG rectangle + bull/bear label. |
| `V2StorePendingTradeFvg()` | Pending FVG for hunt-off placement. |
| `V2ResolveTradeFvgForHunt()` | Select FVG from memory or pending. |
| `V2SelectTradeFvgMemIndexForHunt()` | Default 2nd FVG unless 1st gap > 2× 2nd. |
| `V2TryPlaceFvgAndEndHuntAfterRecalcSkip()` | FVG bar after `TOUCH_RECALC_SKIP` → FVG trade + hunt OFF. |
| `V2TryPlacePendingFvgTradesAfterHuntOff()` | Hunt ended with stored FVG → place trade. |
| `V2TryClearHuntFvgsOnSameDirectionBosWhileHuntOn()` | Clears FVG memory on same-dir M2 BOS during hunt. |

---

## 10. Trade placement

### 10.1 Touch volume bar entry (primary path)

```
V2HandleTouchHitConfirmed
└── TryPlaceTouchVolumeBarTradeSetup
    ├── M2FindMaxVolumeBarOpenTimeExcludingOldest  (skip vols[0])
    ├── ResolveTouchLegVolumeBarEntryAndSl
    │   ├── entry: max-vol bar close (limit or market)
    │   └── SL: wider of max-vol bar vs prior bar extreme ± 2% chart height
    ├── BuildTradeSwingGroupTakeProfits
    └── PlaceOneFvgTradeOrder × N (OV_TP1..3, 3:1:1 risk split)
```

| Function | Description |
|----------|-------------|
| `M2FindMaxVolumeBarOpenTimeExcludingOldest()` | Highest tick volume among bars after oldest in window. |
| `M2TouchVolSlReferenceExtreme()` | Buy: min(low, prevLow); sell: max(high, prevHigh). |
| `M2TouchVolSlBufferPrice()` | 2% of chart height anchored at entry bar shift. |
| `ResolveTouchLegVolumeBarEntryAndSl()` | Resolves limit/market entry + buffered SL. |
| `TryPlaceTouchVolumeBarTradeSetup()` | Full order placement pipeline for touch-vol trades. |

### 10.2 FVG entry (recalc-skip / hunt-off paths)

| Function | Description |
|----------|-------------|
| `TryPlaceOppositeFvgTradeSetup()` | FVG zone entry, 2nd-prev-bar SL, swing-group TPs, multi OV orders. |
| `ResolveFvgEntryPrice()` | Limit at gap edge + buffer offset, or market if inside gap. |
| `TryFallbackLimitEntryToMarket()` | Promote invalid limit to market. |
| `TryPromoteFvgLimitToMarketIfFormationCloseMatchesEntry()` | Formation close = limit → market. |
| `FvgFormationBarMeetsMinTickVolume()` | Formation bar vol vs prior M2 average. |
| `ResolveHuntFvgOrderPlacementGate()` | One trade setup per hunt; no duplicate if position open. |
| `BuildTradeSwingGroupTakeProfits()` | Cluster M2 swing extremes → line TPs with min R:R filter. |
| `CollectM2SwingExtremesBackwardFromFormation()` | Swing highs/lows backward from formation bar. |
| `PlaceOneFvgTradeOrder()` | Single Buy/Sell or limit via `CTrade`. |
| `CalculateVolumeForFixedUsdRisk()` | Lot size from `LQ_RISK_USD_PER_TRADE` split. |
| `RegisterHuntTradeAfterSuccessfulPlace()` | Records entry, TP1, pre-entry cancel TP3 level. |

### 10.3 Buffers & chart reference

| Function | Description |
|----------|-------------|
| `M2FvgStopBufferPrice()` | 1% chart height (FVG SL, touch level, BOS mgmt). |
| `ReferenceChartHeightForM2BarCountFromShift()` | High−low range over N M2 bars from shift. |
| `StopsDistanceAllowed()` | Broker min stop distance check. |

---

## 11. Open trade management

| Function | Description |
|----------|-------------|
| `ManageHuntOpenPositionsOnM2BarClose()` | Once per M2 bar: same-dir BOS trail SL; first opposite BOS OV TP mgmt. |
| `TrailHuntTradeStopOnSameDirectionM2Bos()` | Moves SL to opposite extreme of BOS leg − buffer (if enabled). |
| `ApplyHuntTradeFirstOppositeM2BosMgmt()` | First opposite M2 BOS: move OV TPs to leg midpoint ± buffer. |
| `CheckHuntPreEntryTp3CancelOnTick()` | Cancel pending if price reaches TP3 before fill. |
| `CheckHuntFvgBeyondChartRangeCancelOnTick()` | Cancel if formation bar too old / off chart. |
| `CancelOurHuntPendingOrders()` | Cancel by magic + hunt comment prefix. |
| `V2RefreshGlobalHuntTradeWatchFromSessions()` | Sync global pre-entry watch from hunt slots. |

**Comment / identity helpers:** `HuntTradeCommentIsOurs`, `ParseHuntSessionIdFromTradeComment`, `V2HuntHasOpenPositionForSession`, etc.

---

## 12. Chart objects & HUD

| Object prefix / name | Drawn by |
|---------------------|----------|
| H4 swing trend lines | `SwingCloseH4Context` |
| H4 volume breach rays | `DrawH4VolumeBreachLevelRay` |
| M2 swing trends / labels | `SwingCloseM2Leg`, live tick updates |
| M2 anchor line | `UpdateM2SwingAnchorVisualRealtime` |
| FVG rectangles | `V2DrawHuntFairValueGapZone` |
| Touch line | `V2DrawTouchPointLine` |
| Impulse / recalc buffer rects | `V2UpdateImpulseBufferZone`, `V2UpdateTouchRecalcBufferZone` |
| Swing-group TP zones | `BuildTradeSwingGroupTakeProfits` |
| `LQ2_HUNT_HUD` | `RefreshLiquidityHuntHud` |
| `LQ4_H4_BIAS` | `RefreshH4BosBiasHud` |

All gated by `H4LqChartDrawEnabled()` and per-input draw flags; **`InputFastTesterMode=true`** disables all of the above plus logging.

---

## 13. Key event flow (happy path)

```
1. H4 leg completes → volume breach level cached + ray drawn
2. M2 wick enters breach buffer → V2ArmOppositeFvgHuntAfterH4Breach
3. Opposite M2 leg completes → touch level locked
4. Price closes through touch (same side as hunt) + ascending volume window
5. Max-vol bar selected (oldest excluded) → hunt OFF → touch-vol trade placed
6. Swing-group TPs; optional BOS SL/TP management while open
```

**Gate-off paths (no immediate trade):**
- Touch volume pattern fails → `TOUCH_GATE_OFF`, await recalc buffer
- Touch hit but no trade (SL/TP/R:R fail) → hunt already ended
- Recalc buffer hit → gate reopens → touch recalc / FVG marking continues

---

## 14. Inputs that map to subtrees

| Input | Affects |
|-------|---------|
| `InputFastTesterMode` | All logging + all chart objects |
| `InputEnableOppositeFvgHuntAfterH4Breach` | Entire hunt pipeline |
| `InputH4BreachBufferChartBarCount` | Breach buffer height + active breach window |
| `InputHuntTouchRecalcPercentBeforeSameDirExtreme` | Touch recalc + buffer zones |
| `InputEnableAutomatedTrading` | Actual order send vs log-only plan |
| `InputEnableH4BosTradeDirectionBias` | Trade filter + bias HUD |
| `InputTradeSwingTpMinRewardToRisk` | TP line qualification |
| `InputDraw*` / `InputShow*` | Individual chart layers (when fast mode off) |

---

*Generated for `h4_lq_v2.mq5` v2.55. For line-level detail, search function names in the source file.*
