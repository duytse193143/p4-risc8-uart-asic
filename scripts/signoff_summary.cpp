// =============================================================================
// signoff_summary.cpp  -  D50 / D54 / D55: one-page signoff summary of a run
// -----------------------------------------------------------------------------
// Build once:   g++ -std=c++17 -O2 -o scripts/signoff_summary scripts/signoff_summary.cpp
// Use:          ./scripts/signoff_summary              (latest run in runs/)
//               ./scripts/signoff_summary runs/<run>   (a specific run)
//
// Reads runs/<run>/final/metrics.json and prints PASS/FAIL for every P4 target.
// Timing and skew are judged at the SIGNOFF corners: by default the typical
// corners ("tt", 25 C, 1.8 V), the same corners LibreLane checks. The slow
// corner ("ss", 100 C, 1.6 V) is printed for information.
// Clock skew is the real clock-tree skew (source latency - target latency),
// read from the post-route STA skew reports. Newer OpenSTA versions add the
// SDC clock uncertainty (0.25 ns here) into the "skew" metric; that margin is
// not part of the clock tree, so it is taken out here.
//   ./scripts/signoff_summary runs/<run> ss     -> judge at the slow corners
// Standard library only (C++17). metrics.json is a flat {"key": value} object.
// =============================================================================
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace {

// Minimal reader for a flat JSON object: keys are strings, values are
// numbers, strings, true/false/null. Nested objects/arrays are kept as raw text.
std::map<std::string, std::string> read_flat_json(const std::string& path) {
    std::ifstream f(path);
    std::stringstream ss;
    ss << f.rdbuf();
    const std::string s = ss.str();
    std::map<std::string, std::string> out;
    size_t i = s.find('{');
    if (i == std::string::npos) return out;
    ++i;
    auto skip_ws = [&]() { while (i < s.size() && std::isspace(static_cast<unsigned char>(s[i]))) ++i; };
    auto read_string = [&]() {
        std::string r;
        ++i;  // opening quote
        while (i < s.size() && s[i] != '"') {
            if (s[i] == '\\' && i + 1 < s.size()) { r += s[i + 1]; i += 2; }
            else r += s[i++];
        }
        ++i;  // closing quote
        return r;
    };
    while (i < s.size()) {
        skip_ws();
        if (i >= s.size() || s[i] == '}') break;
        if (s[i] == ',') { ++i; continue; }
        if (s[i] != '"') { ++i; continue; }
        std::string key = read_string();
        skip_ws();
        if (i < s.size() && s[i] == ':') ++i;
        skip_ws();
        std::string val;
        if (i < s.size() && s[i] == '"') {
            val = read_string();
        } else if (i < s.size() && (s[i] == '{' || s[i] == '[')) {
            int depth = 0;
            size_t start = i;
            do {
                if (s[i] == '{' || s[i] == '[') ++depth;
                else if (s[i] == '}' || s[i] == ']') --depth;
                ++i;
            } while (i < s.size() && depth > 0);
            val = s.substr(start, i - start);
        } else {
            size_t start = i;
            while (i < s.size() && s[i] != ',' && s[i] != '}') ++i;
            val = s.substr(start, i - start);
            while (!val.empty() && std::isspace(static_cast<unsigned char>(val.back()))) val.pop_back();
        }
        out[key] = val;
    }
    return out;
}

bool to_number(const std::string& v, double& d) {
    if (v.empty() || v == "null" || v == "true" || v == "false") return false;
    try {
        size_t pos = 0;
        d = std::stod(v, &pos);
        return pos == v.size();
    } catch (...) {
        return false;
    }
}

// Worst value of a metric over all corners whose name contains 'corner_tag'
// (e.g. "tt"). worst_is_min: true for slack/TNS, false for |skew|.
bool corner_worst(const std::map<std::string, std::string>& m, const std::string& key,
                  const std::string& corner_tag, bool worst_is_min, double& out) {
    const std::string prefix = key + "__corner:";
    bool found = false;
    for (const auto& [k, v] : m) {
        if (k.compare(0, prefix.size(), prefix) != 0) continue;
        if (k.find(corner_tag, prefix.size()) == std::string::npos) continue;
        double d;
        if (!to_number(v, d)) continue;
        if (!worst_is_min) d = std::fabs(d);
        if (!found || (worst_is_min ? d < out : d > out)) out = d;
        found = true;
    }
    return found;
}

// Real clock skew (|source latency - target latency|, without clock
// uncertainty) from <run>/NN-openroad-stapostpnr/<corner>/skew.max.rpt,
// worst over the corners whose name contains 'corner_tag'.
// Understands both report styles:
//   new:  "  0.51 source latency X"  /  " -0.46 target latency Y"
//   old:  a "Latency CRPR Skew" table whose last line ends with the skew
bool real_skew_from_reports(const fs::path& run, const std::string& corner_tag, double& out) {
    // pick the last post-route STA step (highest step number)
    fs::path sta_dir;
    int best_num = -1;
    if (!fs::is_directory(run)) return false;
    for (const auto& e : fs::directory_iterator(run)) {
        const std::string name = e.path().filename().string();
        if (!e.is_directory() || name.find("stapostpnr") == std::string::npos) continue;
        int num = std::atoi(name.c_str());
        if (num > best_num) { best_num = num; sta_dir = e.path(); }
    }
    if (sta_dir.empty()) return false;

    bool found = false;
    for (const auto& c : fs::directory_iterator(sta_dir)) {
        if (!c.is_directory()) continue;
        if (c.path().filename().string().find(corner_tag) == std::string::npos) continue;
        std::ifstream f(c.path() / "skew.max.rpt");
        if (!f) continue;
        std::string line;
        double src = 0, tgt = 0, table_skew = 0;
        bool have_src = false, have_tgt = false, have_table = false, in_table = false;
        while (std::getline(f, line)) {
            std::istringstream ls(line);
            double v;
            std::string w1, w2;
            if (line.find("source latency") != std::string::npos && (ls >> v)) { src = v; have_src = true; }
            else if (line.find("target latency") != std::string::npos && (ls >> v)) { tgt = v; have_tgt = true; }
            else if (line.find("Latency") != std::string::npos && line.find("Skew") != std::string::npos) in_table = true;
            else if (in_table) {
                double a, b, cval;
                std::istringstream ts(line);
                if (ts >> a >> b >> cval) { table_skew = cval; have_table = true; }
            }
        }
        double skew;
        if (have_src && have_tgt) skew = std::fabs(src + tgt);   // target is printed negative
        else if (have_table) skew = std::fabs(table_skew);
        else continue;
        if (!found || skew > out) out = skew;
        found = true;
    }
    return found;
}

fs::path latest_run() {
    if (!fs::is_directory("runs")) {
        std::cerr << "No runs/ folder found. Run the flow first.\n";
        std::exit(1);
    }
    fs::path best;
    fs::file_time_type best_t{};
    for (const auto& e : fs::directory_iterator("runs")) {
        if (!e.is_directory()) continue;
        auto t = fs::last_write_time(e);
        if (best.empty() || t > best_t) { best = e.path(); best_t = t; }
    }
    if (best.empty()) { std::cerr << "runs/ is empty. Run the flow first.\n"; std::exit(1); }
    return best;
}

struct Check {
    const char* label;
    const char* key;
    std::function<bool(double)> ok;
    const char* target;
    int per_corner;   // 0 = single value, 1 = worst slack/TNS, 2 = worst |skew|
};

}  // namespace

int main(int argc, char** argv) {
    const fs::path run = (argc > 1) ? fs::path(argv[1]) : latest_run();
    const std::string corner = (argc > 2) ? argv[2] : "tt";
    const std::string other = (corner == "tt") ? "ss" : "tt";
    const fs::path metrics = run / "final" / "metrics.json";
    if (!fs::is_regular_file(metrics)) {
        std::cerr << metrics.string() << " not found - did the flow finish?\n";
        return 1;
    }
    const auto m = read_flat_json(metrics.string());

    const std::vector<Check> checks = {
        {"Setup worst slack (ns)", "timing__setup__ws",  [](double v) { return v >= 0; }, ">= 0", 1},
        {"Setup TNS (ns)",         "timing__setup__tns", [](double v) { return v == 0; }, "= 0", 1},
        {"Hold worst slack (ns)",  "timing__hold__ws",   [](double v) { return v >= 0; }, ">= 0", 1},
        {"Hold TNS (ns)",          "timing__hold__tns",  [](double v) { return v == 0; }, "= 0", 1},
        {"Clock skew, real (ns)",        "clock__skew__worst_setup", [](double v) { return v <= 0.100; }, "<= 0.100", 2},
        {"Routing DRC errors",     "route__drc_errors",  [](double v) { return v == 0; }, "= 0", 0},
        {"Magic DRC errors",       "magic__drc_error__count",   [](double v) { return v == 0; }, "= 0", 0},
        {"KLayout DRC errors",     "klayout__drc_error__count", [](double v) { return v == 0; }, "= 0", 0},
        {"LVS errors",             "design__lvs_error__count",  [](double v) { return v == 0; }, "= 0", 0},
        {"Antenna violating nets", "antenna__violating__nets",  [](double v) { return v == 0; }, "= 0", 0},
    };
    const std::vector<std::pair<const char*, const char*>> info = {
        {"Instances",        "design__instance__count"},
        {"Core area (um^2)", "design__core__area"},
        {"Utilization",      "design__instance__utilization"},
        {"Die box (um)",     "design__die__bbox"},
    };

    const std::string line(62, '-');
    std::printf("\nSignoff summary for %s  (timing at '%s' corners)\n%s\n",
                run.string().c_str(), corner.c_str(), line.c_str());
    bool all_ok = true;
    for (const auto& c : checks) {
        double v = 0;
        bool have = false;
        if (c.per_corner == 2) {
            have = real_skew_from_reports(run, corner, v) ||
                   corner_worst(m, c.key, corner, false, v);
        } else if (c.per_corner) {
            have = corner_worst(m, c.key, corner, c.per_corner == 1, v);
        } else {
            auto it = m.find(c.key);
            have = (it != m.end()) && to_number(it->second, v);
        }
        if (!have) {
            std::printf("%-26s %12s   target %-9s ?\n", c.label, "n/a", c.target);
            continue;
        }
        const bool ok = c.ok(v);
        all_ok = all_ok && ok;
        std::printf("%-26s %12.3f   target %-9s %s\n", c.label, v, c.target, ok ? "PASS" : "FAIL");
    }
    double ows, ohs;
    if (corner_worst(m, "timing__setup__ws", other, true, ows) &&
        corner_worst(m, "timing__hold__ws", other, true, ohs)) {
        std::printf("%s\nFor information, '%s' corners: setup WNS %.3f ns, hold WNS %.3f ns\n",
                    line.c_str(), other.c_str(), ows, ohs);
    }
    std::printf("%s\n", line.c_str());
    for (const auto& [label, key] : info) {
        auto it = m.find(key);
        std::printf("%-26s %12s\n", label, it == m.end() ? "n/a" : it->second.c_str());
    }
    std::printf("%s\n", line.c_str());
    std::printf("P4 SIGNOFF: %s\n", all_ok ? "ALL TARGETS MET" : "NOT CLEAN - fix the FAIL lines");

    const fs::path gds_dir = run / "final" / "gds";
    if (fs::is_directory(gds_dir)) {
        for (const auto& e : fs::directory_iterator(gds_dir)) {
            if (e.path().extension() == ".gds") {
                std::printf("GDSII: %s\n", e.path().string().c_str());
                break;
            }
        }
    }
    return all_ok ? 0 : 2;
}
