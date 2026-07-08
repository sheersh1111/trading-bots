# h4_lq_v3 — Optimization Runbook

Current versions: **EA v3.120** · **ScoreLogger v2.9** · **optimize_score_adaptive.cpp v2.7**

This document describes the two-phase score optimization workflow: **write mode** captures frozen setup state; **read mode** replays that state with different weight permutations during genetic optimization.

---

## Architecture (short)

| Artifact | What it stores | When written |
|----------|----------------|--------------|
| `setup_zone_types.json` | Per-setup zone types + MTF bias + direction (human/C++ readable) | Write mode, OnDeinit |
| `setup_zone_types.bin` | Same data as compact bitmask records (fast OnInit) | Write mode, OnDeinit |
| `setup_zone_scores.json` | Per-setup **scores** (verification only) | Read mode, OnDeinit if `InputVerifyPermutationScores=true` |

JSON and BIN are **setup-state replay**, not pre-computed thresholds. Scores and P-thresholds are derived at read time from the current formula and `InputWeight_*` values.

Score formula lives in **`ConfluenceScoring.mqh`**. C++ mirror: **`optimize_score_adaptive.cpp`** (`scoreSetup()`).

---

## Phase 1 — Write mode (capture setups)

Run **once** per symbol / date range / SMC configuration you want to optimize against.

### Inputs

| Input | Value |
|-------|-------|
| `InputScoreLogWriteCsv` | `true` |
| `InputFastTesterMode` | `false` (optional; logging only) |
| `InputVerifyPermutationScores` | `false` |
| `InputEnableEngulfHuntAfterH4Breach` | `true` (required for flush on deinit) |

Use the same symbol, date range, and `InputEnableMtfSmcEngine` setting you plan for genetic optimization.

### Run

1. Compile `h4_lq_v3.mq5` in MetaEditor.
2. Strategy Tester → single backtest (not genetic).
3. Let the test finish completely (OnDeinit must run).

### Output files

Written to the tester agent **Files** folder, e.g.:

```
%APPDATA%\MetaQuotes\Tester\<terminal-id>\Agent-<host>\MQL5\Files\
  setup_zone_types.json
  setup_zone_types.bin
```

Also check `MQL5\Files\` under the terminal if not found in the agent path.

---

## Phase 2 — Copy artifacts

Copy both files into the Files folder used by **every** optimization agent:

```
setup_zone_types.json
setup_zone_types.bin
```

**Archive bundle** (recommended before long runs):

- Both files above
- `h4_lq_v3.ex5` or git tag (e.g. `v3.120`)
- Tester `.set` file (symbol, dates, modeling mode)
- Note: EA version, date range, `InputEnableMtfSmcEngine`, weight defaults used during write pass

---

## Phase 3 — Genetic optimization (read mode)

### Inputs

| Input | Value |
|-------|-------|
| `InputScoreLogWriteCsv` | `false` |
| `InputFastTesterMode` | `true` (recommended) |
| `InputVerifyPermutationScores` | `false` (keep off during genetic — verification is slow) |
| `InputMinScorePercentile` | Optimize: P0 … P90 |
| `InputScoreDenominatorPercentile` | Optimize: P80 / P90 / P100 |
| `InputWeight_*` (12 weights) | Genetic parameters |

### What happens each pass

1. **OnInit** loads `setup_zone_types.bin` (falls back to JSON if bin missing).
2. Scores every logged setup with **current** weight inputs.
3. Computes only the **two active percentiles** selected by inputs (gate + risk denom).
4. Backtest runs with `setupScore > gate` and risk scaled by `|score| / denom`.

### OnInit log (expect)

```
Score thresholds [bin]: Setups=… PositiveScores=… TheoreticalMax=… (in … ms)
Score thresholds [bin]: gate P30=…. (score >) | risk denom P80=….
```

If init fails: `INIT_FAILED` — trades blocked until bin/JSON is present in Files.

### Performance notes

- `InputFastTesterMode=true`: skips intra-bar OnTick work and OnDeinit chart cleanup.
- Bin path avoids JSON string parsing; much faster for thousands of genetic passes.
- Globals do **not** persist between genetic passes — caching parsed setups in memory does not help.

---

## Phase 4 — Verification (optional)

### A. Single-pass EA vs C++ (recommended before long genetic)

**EA:** One read-mode backtest with fixed weights. Copy OnInit threshold lines from the Experts log.

**C++** (from `MQL5\Experts`):

```bat
optimize_score_adaptive_build.cmd
optimize_score_adaptive.exe setup_zone_types.json --weights 10,8,5,2,10,8,5,2,16,8,4,2 --csv-only
```

Weight order (12 ints):  
`WeeklyFVG, DailyFVG, H4FVG, M15FVG, W1_HighLow, D1_HighLow, H4_HighLow, M15_HighLow, W1_BOS, D1_BOS, H4_BOS, M15_BOS`

Compare C++ `P0`…`P100` with EA logs. Match the **same** `--weights` as EA inputs.

> Do **not** run C++ without `--weights` — it enters full cartesian grid (millions of rows).

### B. Per-setup score dump (EA)

| Input | Value |
|-------|-------|
| `InputScoreLogWriteCsv` | `false` |
| `InputVerifyPermutationScores` | `true` |

Single backtest → OnDeinit writes `setup_zone_scores.json` using `CalculateReplayTradeScore()` from `ConfluenceScoring.mqh`.

---

## Entry gate rule

Trades require **strictly greater than** the gate threshold:

```
setupScore > GetMinScoreThreshold()   // not >=
```

Implemented in `SetupScoreAllowsTradeEntry()` (`TradeExecution.mqh`).

Keep `InputScoreDenominatorPercentile` ≥ `InputMinScorePercentile` if you want risk ratio `|score|/denom` to stay in a sensible range.

---

## Changing the score formula later

| Change | Action |
|--------|--------|
| Formula / weights math only | Edit `ConfluenceScoring.mqh` + `ScoreLogScoreBinRecord()` (or refactor to shared helper) + `optimize_score_adaptive.cpp`. **No** new write pass. |
| Zone matching rules (`CollectMatchingSetupZoneTypes`) | **New write pass** required — logged setup set changes. |

Central scoring functions:

- **Live entry:** `CalculateTotalTradeScore()`
- **JSON replay / verify:** `CalculateReplayTradeScore()`
- **Bin OnInit:** `ScoreLogScoreBinRecord()` (duplicate of replay math today)

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `INIT_FAILED` on genetic start | `setup_zone_types.bin` (or `.json`) missing from agent `MQL5\Files\` |
| P-scores differ EA vs C++ | Same weights? Same JSON file? Same EA version? |
| Genetic very slow | `InputFastTesterMode=true`, bin present, `InputVerifyPermutationScores=false` |
| Empty / missing JSON on write | `InputEnableEngulfHuntAfterH4Breach=true` and test ran to completion |
| Too many trades (no SMC) | Raise `InputMinScorePercentile` (e.g. P70–P90) |

---

## Quick checklist

- [ ] Write pass completed; JSON + BIN archived
- [ ] Files copied to tester agent `MQL5\Files\`
- [ ] One C++ vs EA sanity check on fixed weights
- [ ] Genetic: `InputScoreLogWriteCsv=false`, `InputFastTesterMode=true`
- [ ] Git tag / commit on known-good EA + C++ build
