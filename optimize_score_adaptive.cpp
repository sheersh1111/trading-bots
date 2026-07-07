// optimize_score_adaptive.cpp v2.6
// Score percentile calculator for setup_zone_types.json (no P/L optimization).
//
// Flow: compute all results -> print to stdout -> then write CSV/xlsx.
// Grid: incremental score deltas between consecutive permutations.
// Output: score_adaptive_thresholds_grid.csv (+ optional xlsx).

#include "json.hpp"

#if defined(_WIN32)
#include <process.h>
#include <windows.h>
#endif

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

using json = nlohmann::json;

namespace {

constexpr int kWeightCount = 12;
constexpr int kZoneSlotCount = 8;
constexpr int kSheetPercentiles[] = {0, 10, 20, 30, 80, 90, 100};
constexpr int kSheetPercentileCount = 7;

const int kDefaultWeights[kWeightCount] = {10, 8, 5, 2, 10, 8, 5, 2, 16, 8, 4, 2};

const char* kWeightNames[kWeightCount] = {
    "WeeklyFVG", "DailyFVG", "H4FVG", "M15FVG",
    "W1_HighLow", "D1_HighLow", "H4_HighLow", "M15_HighLow",
    "W1_BOS", "D1_BOS", "H4_BOS", "M15_BOS",
};

struct Setup {
    uint8_t zoneMask = 0;
    int8_t biasW1 = 0;
    int8_t biasD1 = 0;
    int8_t biasH4 = 0;
    int8_t biasM15 = 0;
    bool bull = false;
    std::string symbol;
    std::string bar;
};

struct WorkbookSheet {
    std::string name;
    std::vector<std::vector<std::pair<std::string, bool>>> rows;
};

struct ThresholdRow {
    std::string label;
    int weights[kWeightCount]{};
    int positiveCount = 0;
    double theoreticalMax = 0.0;
    double percentiles[kSheetPercentileCount]{};
};

struct Options {
    std::string jsonPath;
    std::string outputPath = "score_adaptive_results.xlsx";
    std::string gridModeName = "cartesian";
    int weightMin = 1;
    int weightMax = 25;
    int coarseStep = 5;
    size_t gridMaxRows = 500000;
    bool weightsSet = false;
    bool gridMode = false;
    bool withSetupScores = false;
    bool csvOnly = false;
    int weights[kWeightCount]{};
};

int zoneTypeToSlot(const std::string& zt) {
    static const std::unordered_map<std::string, int> map = {
        {"ZONE_BULL_WEEKLY_FVG", 0}, {"ZONE_BEAR_WEEKLY_FVG", 0},
        {"ZONE_BULL_DAILY_FVG", 1}, {"ZONE_BEAR_DAILY_FVG", 1},
        {"ZONE_BULL_H4_FVG", 2}, {"ZONE_BEAR_H4_FVG", 2},
        {"ZONE_BULL_M15_FVG", 3}, {"ZONE_BEAR_M15_FVG", 3},
        {"ZONE_BULL_SWING_W1_LOW", 4}, {"ZONE_BEAR_SWING_W1_HIGH", 4},
        {"ZONE_BULL_PROTECTED_DAILY_LOW", 5}, {"ZONE_BEAR_PROTECTED_DAILY_HIGH", 5},
        {"ZONE_BULL_SWING_DAILY_LOW", 5}, {"ZONE_BEAR_SWING_DAILY_HIGH", 5},
        {"ZONE_BULL_PROTECTED_H4_LOW", 6}, {"ZONE_BEAR_PROTECTED_H4_HIGH", 6},
        {"ZONE_BULL_SWING_H4_LOW", 6}, {"ZONE_BEAR_SWING_H4_HIGH", 6},
        {"ZONE_BULL_PROTECTED_M15_LOW", 7}, {"ZONE_BEAR_PROTECTED_M15_HIGH", 7},
        {"ZONE_BULL_SWING_M15_LOW", 7}, {"ZONE_BEAR_SWING_M15_HIGH", 7},
    };
    auto it = map.find(zt);
    return it == map.end() ? -1 : it->second;
}

void applyZoneTypeToMask(uint8_t& mask, bool usedSlots[kZoneSlotCount], const std::string& zoneType) {
    const int slot = zoneTypeToSlot(zoneType);
    if (slot < 0 || slot >= kZoneSlotCount || usedSlots[slot])
        return;
    usedSlots[slot] = true;
    mask |= static_cast<uint8_t>(1u << slot);
}

uint8_t buildZoneMaskFromZoneTypes(const std::vector<std::string>& zoneTypes) {
    uint8_t mask = 0;
    bool usedSlots[kZoneSlotCount]{};
    for (const std::string& zoneType : zoneTypes)
        applyZoneTypeToMask(mask, usedSlots, zoneType);
    return mask;
}

std::vector<Setup> loadSetups(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) throw std::runtime_error("Cannot open: " + path);
    std::string text((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    if (!text.empty() && static_cast<unsigned char>(text[0]) == 0xEF) {
        if (text.size() >= 3 && static_cast<unsigned char>(text[1]) == 0xBB &&
            static_cast<unsigned char>(text[2]) == 0xBF)
            text.erase(0, 3);
    }
    json root = json::parse(text);
    std::vector<Setup> setups;
    setups.reserve(root.size());
    for (const auto& row : root) {
        Setup s;
        s.bull = row.value("bull", false);
        s.symbol = row.value("symbol", "");
        s.bar = row.value("bar", "");
        if (row.contains("zoneTypes") && row["zoneTypes"].is_array()) {
            std::vector<std::string> zoneTypes;
            zoneTypes.reserve(row["zoneTypes"].size());
            for (const auto& zt : row["zoneTypes"])
                zoneTypes.push_back(zt.get<std::string>());
            s.zoneMask = buildZoneMaskFromZoneTypes(zoneTypes);
        }
        if (row.contains("mtfBias") && row["mtfBias"].is_object()) {
            const auto& b = row["mtfBias"];
            s.biasW1 = static_cast<int8_t>(b.value("W1", 0));
            s.biasD1 = static_cast<int8_t>(b.value("D1", 0));
            s.biasH4 = static_cast<int8_t>(b.value("H4", 0));
            s.biasM15 = static_cast<int8_t>(b.value("M15", 0));
        }
        setups.push_back(s);
    }
    return setups;
}

double alignmentContribution(int bias, int bosWeight, int tradeDir) {
    if (bias == 0) return 0.0;
    return (bias == tradeDir) ? static_cast<double>(bosWeight) : -static_cast<double>(bosWeight);
}

double theoreticalMaxScore(const int weights[kWeightCount]);
double percentileLinear(std::vector<double> values, double p);

int8_t bosCoeffSign(const int bias, const int tradeDir) {
    if (bias == 0) return 0;
    return (bias == tradeDir) ? static_cast<int8_t>(1) : static_cast<int8_t>(-1);
}

struct PrecomputedSetup {
    uint8_t zoneMask = 0;
    int8_t bosCoeff[4]{};
};

double scorePrecomputed(const PrecomputedSetup& pre, const int weights[kWeightCount]) {
    double score = 0.0;
    for (int slot = 0; slot < kZoneSlotCount; ++slot) {
        if (pre.zoneMask & (1u << slot))
            score += static_cast<double>(weights[slot]);
    }
    for (int b = 0; b < 4; ++b)
        score += static_cast<double>(pre.bosCoeff[b]) * static_cast<double>(weights[8 + b]);
    return score;
}

struct IncrementalScoreEngine {
    std::vector<PrecomputedSetup> pre_;
    std::array<std::vector<size_t>, kZoneSlotCount> setupsBySlot_{};
    std::vector<double> scores_;

    explicit IncrementalScoreEngine(const std::vector<Setup>& setups) {
        const size_t n = setups.size();
        pre_.resize(n);
        scores_.resize(n);
        for (size_t i = 0; i < n; ++i) {
            pre_[i].zoneMask = setups[i].zoneMask;
            const int tradeDir = setups[i].bull ? 1 : -1;
            pre_[i].bosCoeff[0] = bosCoeffSign(setups[i].biasW1, tradeDir);
            pre_[i].bosCoeff[1] = bosCoeffSign(setups[i].biasD1, tradeDir);
            pre_[i].bosCoeff[2] = bosCoeffSign(setups[i].biasH4, tradeDir);
            pre_[i].bosCoeff[3] = bosCoeffSign(setups[i].biasM15, tradeDir);
            for (int slot = 0; slot < kZoneSlotCount; ++slot) {
                if (pre_[i].zoneMask & (1u << slot))
                    setupsBySlot_[static_cast<size_t>(slot)].push_back(i);
            }
        }
    }

    void initScores(const int weights[kWeightCount]) {
        for (size_t i = 0; i < pre_.size(); ++i)
            scores_[i] = scorePrecomputed(pre_[i], weights);
    }

    void applyWeightDelta(const int dim, const int delta) {
        if (delta == 0) return;
        const double d = static_cast<double>(delta);
        if (dim < kZoneSlotCount) {
            for (const size_t idx : setupsBySlot_[static_cast<size_t>(dim)])
                scores_[idx] += d;
        } else {
            const int bos = dim - kZoneSlotCount;
            for (size_t i = 0; i < pre_.size(); ++i)
                scores_[i] += static_cast<double>(pre_[i].bosCoeff[bos]) * d;
        }
    }

    void transitionWeights(const int prevWeights[kWeightCount],
                           const int nextWeights[kWeightCount]) {
        for (int d = 0; d < kWeightCount; ++d) {
            if (prevWeights[d] != nextWeights[d])
                applyWeightDelta(d, nextWeights[d] - prevWeights[d]);
        }
    }

    const std::vector<double>& allScores() const { return scores_; }

    ThresholdRow makeThresholdRow(const std::string& label,
                                  const int weights[kWeightCount]) const {
        ThresholdRow row;
        row.label = label;
        std::copy(weights, weights + kWeightCount, row.weights);
        row.theoreticalMax = theoreticalMaxScore(weights);

        std::vector<double> positive;
        positive.reserve(scores_.size() / 2);
        for (const double score : scores_) {
            if (score > 0.0)
                positive.push_back(score);
        }
        row.positiveCount = static_cast<int>(positive.size());
        for (int i = 0; i < kSheetPercentileCount; ++i)
            row.percentiles[i] = percentileLinear(positive, static_cast<double>(kSheetPercentiles[i]));
        return row;
    }
};

double scoreSetup(const Setup& s, const int weights[kWeightCount]) {
    double locationScore = 0.0;
    for (int slot = 0; slot < kZoneSlotCount; ++slot) {
        if (s.zoneMask & (1u << slot))
            locationScore += static_cast<double>(weights[slot]);
    }
    const int tradeDir = s.bull ? 1 : -1;
    double alignmentScore = 0.0;
    alignmentScore += alignmentContribution(s.biasW1, weights[8], tradeDir);
    alignmentScore += alignmentContribution(s.biasD1, weights[9], tradeDir);
    alignmentScore += alignmentContribution(s.biasH4, weights[10], tradeDir);
    alignmentScore += alignmentContribution(s.biasM15, weights[11], tradeDir);
    return locationScore + alignmentScore;
}

double theoreticalMaxScore(const int weights[kWeightCount]) {
    double sum = 0.0;
    for (int i = 0; i < kWeightCount; ++i)
        sum += static_cast<double>(weights[i]);
    return sum;
}

double percentileLinear(std::vector<double> values, double p) {
    if (values.empty()) return std::numeric_limits<double>::quiet_NaN();
    std::sort(values.begin(), values.end());
    if (values.size() == 1) return values[0];
    const double rank = (values.size() - 1) * (p / 100.0);
    const size_t low = static_cast<size_t>(std::floor(rank));
    const size_t high = static_cast<size_t>(std::ceil(rank));
    if (low == high) return values[low];
    const double w = rank - static_cast<double>(low);
    return values[low] * (1.0 - w) + values[high] * w;
}

std::vector<double> buildPositiveScorePool(const std::vector<Setup>& setups,
                                           const int weights[kWeightCount]) {
    std::vector<double> positive;
    positive.reserve(setups.size() / 2);
    for (const Setup& s : setups) {
        const double score = scoreSetup(s, weights);
        if (score > 0.0)
            positive.push_back(score);
    }
    return positive;
}

ThresholdRow makeThresholdRow(const std::string& label,
                                const int weights[kWeightCount],
                                const std::vector<Setup>& setups) {
    ThresholdRow row;
    row.label = label;
    std::copy(weights, weights + kWeightCount, row.weights);
    row.theoreticalMax = theoreticalMaxScore(weights);

    const std::vector<double> positive = buildPositiveScorePool(setups, weights);
    row.positiveCount = static_cast<int>(positive.size());
    for (int i = 0; i < kSheetPercentileCount; ++i)
        row.percentiles[i] = percentileLinear(positive, static_cast<double>(kSheetPercentiles[i]));
    return row;
}

std::vector<double> buildAllScores(const std::vector<Setup>& setups,
                                   const int weights[kWeightCount]) {
    std::vector<double> scores;
    scores.reserve(setups.size());
    for (const Setup& s : setups)
        scores.push_back(scoreSetup(s, weights));
    return scores;
}

std::string formatNumber(double value);

WorkbookSheet makeThresholdsSheet(const std::vector<ThresholdRow>& rows) {
    WorkbookSheet sheet;
    sheet.name = "Thresholds";

    std::vector<std::pair<std::string, bool>> header;
    header.push_back({"Label", false});
    for (int i = 0; i < kWeightCount; ++i)
        header.push_back({kWeightNames[i], false});
    header.push_back({"PositiveCount", false});
    header.push_back({"TheoreticalMax", false});
    for (int i = 0; i < kSheetPercentileCount; ++i)
        header.push_back({"P" + std::to_string(kSheetPercentiles[i]), false});
    sheet.rows.push_back(header);

    for (const ThresholdRow& t : rows) {
        std::vector<std::pair<std::string, bool>> row;
        row.push_back({t.label, false});
        for (int i = 0; i < kWeightCount; ++i)
            row.push_back({std::to_string(t.weights[i]), true});
        row.push_back({std::to_string(t.positiveCount), true});
        row.push_back({formatNumber(t.theoreticalMax), true});
        for (int i = 0; i < kSheetPercentileCount; ++i)
            row.push_back({formatNumber(t.percentiles[i]), true});
        sheet.rows.push_back(row);
    }
    return sheet;
}

WorkbookSheet makeSetupScoresSheet(const std::vector<Setup>& setups,
                                   const std::vector<double>& scores) {
    WorkbookSheet sheet;
    sheet.name = "SetupScores";
    sheet.rows.push_back({
        {"Index", false},
        {"Symbol", false},
        {"Bar", false},
        {"Bull", false},
        {"Score", false},
    });

    const size_t count = std::min(setups.size(), scores.size());
    for (size_t i = 0; i < count; ++i) {
        sheet.rows.push_back({
            {std::to_string(i), true},
            {setups[i].symbol, false},
            {setups[i].bar, false},
            {setups[i].bull ? "true" : "false", false},
            {formatNumber(scores[i]), true},
        });
    }
    return sheet;
}

void printThresholdRow(const ThresholdRow& row) {
    std::cout << "Label: " << row.label << "\n";
    std::cout << "Weights: [";
    for (int i = 0; i < kWeightCount; ++i) {
        if (i) std::cout << ",";
        std::cout << row.weights[i];
    }
    std::cout << "]\n";
    std::cout << "TheoreticalMaxScore: " << row.theoreticalMax << "\n";
    std::cout << "PositiveScores: " << row.positiveCount << "\n";
    for (int i = 0; i < kSheetPercentileCount; ++i)
        std::cout << "P" << kSheetPercentiles[i] << " = " << row.percentiles[i] << "\n";
}

void parseWeightsCsv(const std::string& csv, int outWeights[kWeightCount]) {
    std::stringstream ss(csv);
    std::string token;
    int idx = 0;
    while (std::getline(ss, token, ',') && idx < kWeightCount) {
        outWeights[idx++] = std::stoi(token);
    }
    if (idx != kWeightCount)
        throw std::runtime_error("--weights requires exactly 12 comma-separated integers");
}

std::vector<int> buildCoarseValues(int wmin, int wmax, int step) {
    std::vector<int> vals;
    for (int v = wmin; v <= wmax; v += step)
        vals.push_back(v);
    if (vals.empty() || vals.back() != wmax)
        vals.push_back(wmax);
    return vals;
}

Options parseArgs(int argc, char** argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "-o" || a == "--output") {
            if (++i >= argc) throw std::runtime_error("Missing value for " + a);
            o.outputPath = argv[i];
        } else if (a == "--coarse-step") {
            if (++i >= argc) throw std::runtime_error("Missing value for --coarse-step");
            o.coarseStep = std::stoi(argv[i]);
        } else if (a == "--weight-min") {
            if (++i >= argc) throw std::runtime_error("Missing value for --weight-min");
            o.weightMin = std::stoi(argv[i]);
        } else if (a == "--weight-max") {
            if (++i >= argc) throw std::runtime_error("Missing value for --weight-max");
            o.weightMax = std::stoi(argv[i]);
        } else if (a == "--weights") {
            if (++i >= argc) throw std::runtime_error("Missing value for --weights");
            parseWeightsCsv(argv[i], o.weights);
            o.weightsSet = true;
        } else if (a == "--grid") {
            o.gridMode = true;
        } else if (a == "--grid-mode") {
            if (++i >= argc) throw std::runtime_error("Missing value for --grid-mode");
            o.gridModeName = argv[i];
        } else if (a == "--grid-max-rows") {
            if (++i >= argc) throw std::runtime_error("Missing value for --grid-max-rows");
            o.gridMaxRows = static_cast<size_t>(std::stoull(argv[i]));
        } else if (a == "--with-setup-scores") {
            o.withSetupScores = true;
        } else if (a == "--csv-only") {
            o.csvOnly = true;
        } else if (a.rfind("-", 0) == 0) {
            throw std::runtime_error("Unknown option: " + a);
        } else if (o.jsonPath.empty()) {
            o.jsonPath = a;
        } else {
            throw std::runtime_error("Unexpected argument: " + a);
        }
    }
    if (o.jsonPath.empty())
        o.jsonPath = "setup_zone_types.json";
    return o;
}

std::vector<std::array<int, kWeightCount>> buildGridWeightSets(const Options& opts) {
    int base[kWeightCount];
    if (opts.weightsSet)
        std::copy(opts.weights, opts.weights + kWeightCount, base);
    else
        std::copy(std::begin(kDefaultWeights), std::end(kDefaultWeights), base);

    const std::vector<int> coarseVals =
        buildCoarseValues(opts.weightMin, opts.weightMax, opts.coarseStep);

    std::vector<std::array<int, kWeightCount>> out;
    {
        std::array<int, kWeightCount> w{};
        std::copy(base, base + kWeightCount, w.begin());
        out.push_back(w);
    }
    for (int dim = 0; dim < kWeightCount; ++dim) {
        for (int v : coarseVals) {
            if (v == base[dim])
                continue;
            std::array<int, kWeightCount> w{};
            std::copy(base, base + kWeightCount, w.begin());
            w[dim] = v;
            out.push_back(w);
        }
    }
    return out;
}

size_t cartesianProductSize(const size_t valuesPerDim, const int dims) {
    size_t total = 1;
    for (int d = 0; d < dims; ++d) {
        if (valuesPerDim > 0 && total > std::numeric_limits<size_t>::max() / valuesPerDim)
            return std::numeric_limits<size_t>::max();
        total *= valuesPerDim;
    }
    return total;
}

bool cartesianOdometerStep(std::array<int, kWeightCount>& indices,
                           std::array<int, kWeightCount>& weights,
                           const std::vector<int>& coarseVals) {
    const size_t nVals = coarseVals.size();
    for (int d = 0; d < kWeightCount; ++d) {
        indices[static_cast<size_t>(d)]++;
        if (indices[static_cast<size_t>(d)] < nVals) {
            weights[static_cast<size_t>(d)] = coarseVals[indices[static_cast<size_t>(d)]];
            return true;
        }
        indices[static_cast<size_t>(d)] = 0;
        weights[static_cast<size_t>(d)] = coarseVals[0];
    }
    return false;
}

std::vector<ThresholdRow> scoreSweepGridIncremental(const std::vector<std::array<int, kWeightCount>>& grid,
                                                   IncrementalScoreEngine& engine) {
    std::vector<ThresholdRow> rows;
    if (grid.empty()) return rows;

    rows.reserve(grid.size());
    engine.initScores(grid[0].data());
    rows.push_back(engine.makeThresholdRow("row1", grid[0].data()));

    int prevWeights[kWeightCount];
    std::copy(grid[0].begin(), grid[0].end(), prevWeights);
    for (size_t i = 1; i < grid.size(); ++i) {
        engine.transitionWeights(prevWeights, grid[i].data());
        std::ostringstream label;
        label << "row" << (i + 1);
        rows.push_back(engine.makeThresholdRow(label.str(), grid[i].data()));
        std::copy(grid[i].begin(), grid[i].end(), prevWeights);
    }
    return rows;
}

std::vector<ThresholdRow> scoreCartesianGridIncremental(const std::vector<int>& coarseVals,
                                                         const size_t rowCount,
                                                         IncrementalScoreEngine& engine) {
    std::vector<ThresholdRow> rows;
    if (rowCount == 0 || coarseVals.empty()) return rows;

    std::array<int, kWeightCount> indices{};
    std::array<int, kWeightCount> weights{};
    for (int d = 0; d < kWeightCount; ++d)
        weights[static_cast<size_t>(d)] = coarseVals[0];

    rows.reserve(rowCount);
    engine.initScores(weights.data());
    rows.push_back(engine.makeThresholdRow("row1", weights.data()));

    int prevWeights[kWeightCount];
    std::copy(weights.begin(), weights.end(), prevWeights);
    for (size_t rowIdx = 1; rowIdx < rowCount; ++rowIdx) {
        if (!cartesianOdometerStep(indices, weights, coarseVals))
            break;
        engine.transitionWeights(prevWeights, weights.data());
        std::ostringstream label;
        label << "row" << (rowIdx + 1);
        rows.push_back(engine.makeThresholdRow(label.str(), weights.data()));
        std::copy(weights.begin(), weights.end(), prevWeights);
        if (rowIdx % 5000 == 0)
            std::cout << "  scored " << rowIdx << " / " << rowCount << " rows...\n";
    }
    return rows;
}

void writeThresholdCsv(const std::string& path, const std::vector<ThresholdRow>& rows) {
    std::ofstream out(path, std::ios::binary);
    if (!out) throw std::runtime_error("Cannot write csv: " + path);

    out << "Label";
    for (int i = 0; i < kWeightCount; ++i)
        out << "," << kWeightNames[i];
    out << ",PositiveCount,TheoreticalMax";
    for (int i = 0; i < kSheetPercentileCount; ++i)
        out << ",P" << kSheetPercentiles[i];
    out << "\n";

    for (const ThresholdRow& t : rows) {
        out << t.label;
        for (int i = 0; i < kWeightCount; ++i)
            out << "," << t.weights[i];
        out << "," << t.positiveCount << "," << formatNumber(t.theoreticalMax);
        for (int i = 0; i < kSheetPercentileCount; ++i)
            out << "," << formatNumber(t.percentiles[i]);
        out << "\n";
    }
}

bool tryWriteThresholdCsv(const std::string& path, const std::vector<ThresholdRow>& rows) {
    try {
        writeThresholdCsv(path, rows);
        return true;
    } catch (const std::exception& ex) {
        std::cerr << "Warning: " << ex.what() << "\n";
        return false;
    }
}

void writeSetupScoresCsv(const std::string& path,
                         const std::vector<Setup>& setups,
                         const std::vector<double>& scores) {
    std::ofstream out(path, std::ios::binary);
    if (!out) throw std::runtime_error("Cannot write csv: " + path);

    out << "Index,Symbol,Bar,Bull,Score\n";
    const size_t count = std::min(setups.size(), scores.size());
    for (size_t i = 0; i < count; ++i) {
        out << i << "," << setups[i].symbol << "," << setups[i].bar << ","
            << (setups[i].bull ? "true" : "false") << ","
            << formatNumber(scores[i]) << "\n";
    }
}

bool tryWriteSetupScoresCsv(const std::string& path,
                            const std::vector<Setup>& setups,
                            const std::vector<double>& scores) {
    try {
        writeSetupScoresCsv(path, setups, scores);
        return true;
    } catch (const std::exception& ex) {
        std::cerr << "Warning: " << ex.what() << "\n";
        return false;
    }
}

// --- minimal xlsx writer (single Thresholds sheet) ---

std::string escapeXml(const std::string& text) {
    std::string out;
    out.reserve(text.size());
    for (char c : text) {
        switch (c) {
            case '&': out += "&amp;"; break;
            case '<': out += "&lt;"; break;
            case '>': out += "&gt;"; break;
            case '"': out += "&quot;"; break;
            default: out += c; break;
        }
    }
    return out;
}

std::string colLetter(int index) {
    int n = index + 1;
    std::string s;
    while (n > 0) {
        const int rem = (n - 1) % 26;
        s = static_cast<char>('A' + rem) + s;
        n = (n - 1) / 26;
    }
    return s;
}

std::string formatNumber(double value) {
    if (std::isnan(value)) return "";
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(6) << value;
    return oss.str();
}

std::string cellXml(int rowIdx, int colIdx, const std::string& value, bool isNumber) {
    const std::string ref = colLetter(colIdx) + std::to_string(rowIdx);
    if (value.empty())
        return "<c r=\"" + ref + "\"/>";
    if (isNumber)
        return "<c r=\"" + ref + "\"><v>" + value + "</v></c>";
    return "<c r=\"" + ref + "\" t=\"inlineStr\"><is><t>" + escapeXml(value) + "</t></is></c>";
}

std::string sheetXmlFromRows(const std::vector<std::vector<std::pair<std::string, bool>>>& rows) {
    std::ostringstream xml;
    xml << "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>";
    xml << "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>";
    for (int r = 0; r < static_cast<int>(rows.size()); ++r) {
        xml << "<row r=\"" << (r + 1) << "\">";
        for (int c = 0; c < static_cast<int>(rows[r].size()); ++c)
            xml << cellXml(r + 1, c, rows[r][c].first, rows[r][c].second);
        xml << "</row>";
    }
    xml << "</sheetData></worksheet>";
    return xml.str();
}

uint32_t crc32(const uint8_t* data, size_t len) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < len; ++i) {
        c ^= data[i];
        for (int k = 0; k < 8; ++k)
            c = (c & 1u) ? (c >> 1) ^ 0xEDB88320u : (c >> 1);
    }
    return ~c;
}

void writeUInt16LE(std::vector<uint8_t>& out, uint16_t v) {
    out.push_back(static_cast<uint8_t>(v & 0xFF));
    out.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
}

void writeUInt32LE(std::vector<uint8_t>& out, uint32_t v) {
    out.push_back(static_cast<uint8_t>(v & 0xFF));
    out.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    out.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
    out.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
}

void writeZipArchive(const std::string& path,
                     const std::vector<std::pair<std::string, std::string>>& entries) {
    std::vector<uint8_t> file;
    file.reserve(1 << 20);

    struct CentralRecord {
        std::string name;
        uint32_t crc = 0;
        uint32_t size = 0;
        uint32_t offset = 0;
    };
    std::vector<CentralRecord> central;

    for (const auto& entry : entries) {
        const std::string& name = entry.first;
        const std::string& data = entry.second;
        const uint8_t* raw = reinterpret_cast<const uint8_t*>(data.data());
        const uint32_t size = static_cast<uint32_t>(data.size());
        const uint32_t crc = crc32(raw, data.size());

        CentralRecord rec;
        rec.name = name;
        rec.crc = crc;
        rec.size = size;
        rec.offset = static_cast<uint32_t>(file.size());
        central.push_back(rec);

        writeUInt32LE(file, 0x04034B50u);
        writeUInt16LE(file, 20);
        writeUInt16LE(file, 0);
        writeUInt16LE(file, 0);
        writeUInt16LE(file, 0);
        writeUInt16LE(file, 0);
        writeUInt32LE(file, crc);
        writeUInt32LE(file, size);
        writeUInt32LE(file, size);
        writeUInt16LE(file, static_cast<uint16_t>(name.size()));
        writeUInt16LE(file, 0);
        file.insert(file.end(), name.begin(), name.end());
        file.insert(file.end(), raw, raw + data.size());
    }

    const uint32_t centralStart = static_cast<uint32_t>(file.size());
    uint32_t centralSize = 0;
    for (const CentralRecord& rec : central) {
        writeUInt32LE(file, 0x02014B50u);
        writeUInt16LE(file, 20);
        writeUInt16LE(file, 20);
        writeUInt16LE(file, 0);
        writeUInt16LE(file, 0);
        writeUInt16LE(file, 0);
        writeUInt16LE(file, 0);
        writeUInt32LE(file, rec.crc);
        writeUInt32LE(file, rec.size);
        writeUInt32LE(file, rec.size);
        writeUInt16LE(file, static_cast<uint16_t>(rec.name.size()));
        writeUInt16LE(file, 0);
        writeUInt16LE(file, 0);
        writeUInt16LE(file, 0);
        writeUInt16LE(file, 0);
        writeUInt32LE(file, 0);
        writeUInt32LE(file, rec.offset);
        file.insert(file.end(), rec.name.begin(), rec.name.end());
        centralSize += 46u + static_cast<uint32_t>(rec.name.size());
    }

    writeUInt32LE(file, 0x06054B50u);
    writeUInt16LE(file, 0);
    writeUInt16LE(file, 0);
    writeUInt16LE(file, static_cast<uint16_t>(central.size()));
    writeUInt16LE(file, static_cast<uint16_t>(central.size()));
    writeUInt32LE(file, centralSize);
    writeUInt32LE(file, centralStart);
    writeUInt16LE(file, 0);

    std::ofstream out(path, std::ios::binary);
    if (!out) throw std::runtime_error("Cannot write xlsx: " + path);
    out.write(reinterpret_cast<const char*>(file.data()), static_cast<std::streamsize>(file.size()));
}

void writeXlsxWorkbook(const std::string& path, const std::vector<WorkbookSheet>& sheets) {
    if (sheets.empty())
        throw std::runtime_error("writeXlsxWorkbook: no sheets");

    std::ostringstream contentTypes;
    contentTypes << "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
                    "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
                    "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
                    "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
                    "<Override PartName=\"/xl/workbook.xml\" "
                    "ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>";
    for (size_t i = 0; i < sheets.size(); ++i) {
        contentTypes << "<Override PartName=\"/xl/worksheets/sheet"
                     << (i + 1)
                     << ".xml\" "
                        "ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>";
    }
    contentTypes << "</Types>";

    const std::string relsRoot =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" "
        "Target=\"xl/workbook.xml\"/>"
        "</Relationships>";

    std::ostringstream workbook;
    workbook << "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
                "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" "
                "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>";
    for (size_t i = 0; i < sheets.size(); ++i) {
        workbook << "<sheet name=\"" << escapeXml(sheets[i].name) << "\" sheetId=\""
                 << (i + 1) << "\" r:id=\"rId" << (i + 1) << "\"/>";
    }
    workbook << "</sheets></workbook>";

    std::ostringstream workbookRels;
    workbookRels << "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
                    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">";
    for (size_t i = 0; i < sheets.size(); ++i) {
        workbookRels << "<Relationship Id=\"rId" << (i + 1)
                     << "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" "
                        "Target=\"worksheets/sheet"
                     << (i + 1) << ".xml\"/>";
    }
    workbookRels << "</Relationships>";

    std::vector<std::pair<std::string, std::string>> zipEntries;
    zipEntries.push_back({"[Content_Types].xml", contentTypes.str()});
    zipEntries.push_back({"_rels/.rels", relsRoot});
    zipEntries.push_back({"xl/workbook.xml", workbook.str()});
    zipEntries.push_back({"xl/_rels/workbook.xml.rels", workbookRels.str()});
    for (size_t i = 0; i < sheets.size(); ++i) {
        const std::string sheetPath = "xl/worksheets/sheet" + std::to_string(i + 1) + ".xml";
        zipEntries.push_back({sheetPath, sheetXmlFromRows(sheets[i].rows)});
    }

    writeZipArchive(path, zipEntries);
}

std::string fallbackXlsxPath(const std::string& path, const int attempt) {
    const std::filesystem::path p(path);
    const std::string stem = p.stem().string();
    if (attempt == 0)
        return (p.parent_path() / (stem + "_new.xlsx")).string();
    const auto now = std::chrono::system_clock::now();
    const auto secs = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();
    return (p.parent_path() / (stem + "_" + std::to_string(secs) + ".xlsx")).string();
}

bool tryWriteXlsxWorkbook(const std::string& path, const std::vector<WorkbookSheet>& sheets) {
    try {
        writeXlsxWorkbook(path, sheets);
        return true;
    } catch (const std::exception&) {
        return false;
    }
}

bool writeXlsxWorkbookWithFallback(const std::string& preferredPath,
                                   const std::vector<WorkbookSheet>& sheets,
                                   std::string& outWrittenPath) {
    const std::vector<std::string> candidates = {
        preferredPath,
        fallbackXlsxPath(preferredPath, 0),
        fallbackXlsxPath(preferredPath, 1),
    };

    for (const std::string& candidate : candidates) {
        if (tryWriteXlsxWorkbook(candidate, sheets)) {
            outWrittenPath = candidate;
            if (candidate != preferredPath) {
                std::cerr << "Warning: could not write " << preferredPath
                          << " (file may be open in Excel); wrote " << candidate << " instead\n";
            }
            return true;
        }
    }
    return false;
}

}  // namespace

int main(int argc, char** argv) {
    try {
        const Options opts = parseArgs(argc, argv);
        const auto t0 = std::chrono::steady_clock::now();

        std::cout << "Loading " << opts.jsonPath << " ...\n";
        const std::vector<Setup> setups = loadSetups(opts.jsonPath);
        std::cout << "Setups: " << setups.size() << "\n";

        IncrementalScoreEngine engine(setups);
        std::vector<ThresholdRow> rows;
        const std::vector<double>* setupScoresForCsv = nullptr;

        if (opts.weightsSet && !opts.gridMode) {
            engine.initScores(opts.weights);
            ThresholdRow row = engine.makeThresholdRow("weights", opts.weights);
            printThresholdRow(row);
            rows.push_back(row);
            setupScoresForCsv = &engine.allScores();
            std::cout << "SetupScores: " << setupScoresForCsv->size() << " rows (in memory)\n";
        } else {
            const std::vector<int> coarseVals =
                buildCoarseValues(opts.weightMin, opts.weightMax, opts.coarseStep);
            std::cout << "Grid scoring: incremental | mode " << opts.gridModeName
                      << " | range [" << opts.weightMin << ".." << opts.weightMax
                      << "] step " << opts.coarseStep
                      << " (" << coarseVals.size() << " values/dim)\n";

            if (opts.gridModeName == "cartesian") {
                const size_t theoretical = cartesianProductSize(coarseVals.size(), kWeightCount);
                const size_t rowCount = std::min(theoretical, opts.gridMaxRows);
                const size_t skipped = (theoretical > rowCount) ? (theoretical - rowCount) : 0;
                std::cout << "Theoretical permutations: " << theoretical << "\n";
                std::cout << "Computing rows: " << rowCount;
                if (skipped > 0)
                    std::cout << " (SKIPPED " << skipped << ")";
                std::cout << "\n";
                rows = scoreCartesianGridIncremental(coarseVals, rowCount, engine);
            } else {
                const std::vector<std::array<int, kWeightCount>> grid = buildGridWeightSets(opts);
                std::cout << "Sweep rows: " << grid.size() << "\n";
                rows = scoreSweepGridIncremental(grid, engine);
            }

            if (!rows.empty())
                printThresholdRow(rows[0]);
            if (rows.size() > 1)
                std::cout << "... (" << rows.size() << " threshold rows total)\n";
        }

        const auto tCompute = std::chrono::steady_clock::now();
        const double computeSecs = std::chrono::duration<double>(tCompute - t0).count();
        std::cout << "\nResults computed in " << computeSecs << "s\n";
        std::cout << "Writing output files...\n";
        std::cout.flush();

        const std::string csvGridPath = "score_adaptive_thresholds_grid.csv";
        if (tryWriteThresholdCsv(csvGridPath, rows))
            std::cout << "Wrote CSV grid: " << csvGridPath << " (" << rows.size() << " rows)\n";
        tryWriteThresholdCsv("../Files/score_adaptive_thresholds_grid.csv", rows);
        tryWriteThresholdCsv("../../../Common/Files/score_adaptive_thresholds_grid.csv", rows);

        if (setupScoresForCsv != nullptr) {
            if (tryWriteSetupScoresCsv("setup_scores_verify.csv", setups, *setupScoresForCsv))
                std::cout << "Wrote setup scores CSV: setup_scores_verify.csv\n";
        }

        if (!opts.csvOnly) {
            std::vector<WorkbookSheet> sheets;
            sheets.push_back(makeThresholdsSheet(rows));
            if (opts.withSetupScores && setupScoresForCsv != nullptr)
                sheets.push_back(makeSetupScoresSheet(setups, *setupScoresForCsv));

            std::string writtenPath;
            if (!writeXlsxWorkbookWithFallback(opts.outputPath, sheets, writtenPath)) {
                std::cerr << "Error: could not write xlsx to " << opts.outputPath
                          << " — close it in Excel if open, or use --csv-only\n";
                return 1;
            }

            for (const std::string& extraPath : {
                     std::string("../Files/score_adaptive_results.xlsx"),
                     std::string("../../../Common/Files/score_adaptive_results.xlsx"),
                 }) {
                std::string extraWritten;
                if (!writeXlsxWorkbookWithFallback(extraPath, sheets, extraWritten))
                    std::cerr << "Warning: could not write " << extraPath << "\n";
            }

            const auto t1 = std::chrono::steady_clock::now();
            const double writeSecs = std::chrono::duration<double>(t1 - tCompute).count();
            std::cout << "Wrote xlsx: " << writtenPath << " (write " << writeSecs << "s)\n";
        }

        const auto tEnd = std::chrono::steady_clock::now();
        const double totalSecs = std::chrono::duration<double>(tEnd - t0).count();
        std::cout << "Done in " << totalSecs << "s total\n";
        return 0;
    } catch (const std::exception& ex) {
        std::cerr << "Error: " << ex.what() << "\n";
        return 1;
    }
}
