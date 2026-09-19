#include "../include/navigation_engine.h"
#include <queue>
#include <cmath>
#include <algorithm>
#include <iostream>

namespace orbisnav {

NavigationEngine::NavigationEngine() {
    pdr_state_.current_pos = {0.0f, 0.0f};
    pdr_state_.heading_rad = 0.0f;
    pdr_state_.step_count = 0;
    pdr_state_.accumulated_drift = {0.0f, 0.0f};
}

NavigationEngine::~NavigationEngine() = default;

void NavigationEngine::addNode(const NavNode& node) {
    nodes_[node.id] = node;
}

void NavigationEngine::addEdge(uint32_t from_id, uint32_t to_id, float distance_meters, bool is_floor_transition, float floor_penalty) {
    adjacency_list_[from_id].push_back({to_id, distance_meters, true, is_floor_transition, floor_penalty});
    adjacency_list_[to_id].push_back({from_id, distance_meters, true, is_floor_transition, floor_penalty}); // Bidirectional
}

void NavigationEngine::clearMap() {
    nodes_.clear();
    adjacency_list_.clear();
    active_path_.clear();
}

std::optional<NavNode> NavigationEngine::getNode(uint32_t id) const {
    auto it = nodes_.find(id);
    if (it != nodes_.end()) {
        return it->second;
    }
    return std::nullopt;
}

float NavigationEngine::heuristic(const Vector2& a, const Vector2& b) const {
    float dx = a.x - b.x;
    float dy = a.y - b.y;
    return std::sqrt(dx * dx + dy * dy);
}

std::vector<uint32_t> NavigationEngine::computeAStarPath(uint32_t start_node_id, uint32_t goal_node_id) {
    active_path_.clear();

    if (nodes_.find(start_node_id) == nodes_.end() || nodes_.find(goal_node_id) == nodes_.end()) {
        return active_path_;
    }

    const Vector2& goal_pos = nodes_[goal_node_id].coordinate;

    struct QueueItem {
        uint32_t node_id;
        float priority; // f = g + h
        bool operator>(const QueueItem& other) const {
            return priority > other.priority;
        }
    };

    std::priority_queue<QueueItem, std::vector<QueueItem>, std::greater<QueueItem>> open_set;
    std::unordered_map<uint32_t, uint32_t> came_from;
    std::unordered_map<uint32_t, float> g_score;

    for (const auto& pair : nodes_) {
        g_score[pair.first] = 1e9f;
    }

    g_score[start_node_id] = 0.0f;
    open_set.push({start_node_id, heuristic(nodes_[start_node_id].coordinate, goal_pos)});

    while (!open_set.empty()) {
        uint32_t current = open_set.top().node_id;
        open_set.pop();

        if (current == goal_node_id) {
            // Reconstruct path
            uint32_t curr = goal_node_id;
            while (curr != start_node_id) {
                active_path_.push_back(curr);
                curr = came_from[curr];
            }
            active_path_.push_back(start_node_id);
            std::reverse(active_path_.begin(), active_path_.end());
            return active_path_;
        }

        auto adj_it = adjacency_list_.find(current);
        if (adj_it == adjacency_list_.end()) continue;

        for (const auto& edge : adj_it->second) {
            if (!edge.is_accessible) continue;

            float edge_cost = edge.distance_meters;
            // Step 5.1: Apply cost penalty for floor transitions
            if (edge.is_floor_transition) {
                edge_cost += edge.floor_penalty_cost;
            }

            float tentative_g = g_score[current] + edge_cost;
            if (tentative_g < g_score[edge.to_node_id]) {
                came_from[edge.to_node_id] = current;
                g_score[edge.to_node_id] = tentative_g;
                float f = tentative_g + heuristic(nodes_[edge.to_node_id].coordinate, goal_pos);
                open_set.push({edge.to_node_id, f});
            }
        }
    }

    return active_path_;
}

ClockDirection NavigationEngine::computeClockDirection(
    const Vector2& current_pos,
    float current_heading_rad,
    const Vector2& target_pos) const {

    // Vector to target
    float dx = target_pos.x - current_pos.x;
    float dy = target_pos.y - current_pos.y;

    if (std::abs(dx) < 1e-4f && std::abs(dy) < 1e-4f) {
        return ClockDirection::TwelveOClock;
    }

    // World bearing in radians: 0 along +Y (North), +PI/2 along +X (East)
    // dy is North (+Y), dx is East (+X)
    float target_bearing_rad = std::atan2(dx, dy);

    // Relative angle = target_bearing - current_heading
    float rel_angle_rad = target_bearing_rad - current_heading_rad;

    // Normalize to [-PI, PI]
    while (rel_angle_rad > 3.1415926535f) rel_angle_rad -= 2.0f * 3.1415926535f;
    while (rel_angle_rad < -3.1415926535f) rel_angle_rad += 2.0f * 3.1415926535f;

    // Convert to degrees [-180, 180]
    float rel_deg = rel_angle_rad * (180.0f / 3.1415926535f);

    // Clock hour mapping: 360 / 12 = 30 deg per hour
    // 0 deg = 12 o'clock, 90 deg = 3 o'clock, 180 deg = 6 o'clock, -90 deg = 9 o'clock
    float clock_float = rel_deg / 30.0f;
    int hour = static_cast<int>(std::round(clock_float));

    if (hour <= 0) hour += 12;
    if (hour > 12) hour -= 12;

    return static_cast<ClockDirection>(hour);
}

std::string NavigationEngine::clockDirectionToString(ClockDirection clock_dir) const {
    switch (clock_dir) {
        case ClockDirection::TwelveOClock: return "12 o'clock (straight ahead)";
        case ClockDirection::OneOClock:    return "1 o'clock";
        case ClockDirection::TwoOClock:    return "2 o'clock";
        case ClockDirection::ThreeOClock:  return "3 o'clock (direct right)";
        case ClockDirection::FourOClock:   return "4 o'clock";
        case ClockDirection::FiveOClock:   return "5 o'clock";
        case ClockDirection::SixOClock:    return "6 o'clock (behind you)";
        case ClockDirection::SevenOClock:  return "7 o'clock";
        case ClockDirection::EightOClock:  return "8 o'clock";
        case ClockDirection::NineOClock:   return "9 o'clock (direct left)";
        case ClockDirection::TenOClock:    return "10 o'clock";
        case ClockDirection::ElevenOClock: return "11 o'clock";
        default: return "12 o'clock";
    }
}

void NavigationEngine::processStep(float step_length_meters, float heading_rad) {
    pdr_state_.step_count++;
    pdr_state_.heading_rad = heading_rad;

    // Heading: 0 = North (+y), PI/2 = East (+x)
    float dx = step_length_meters * std::sin(heading_rad);
    float dy = step_length_meters * std::cos(heading_rad);

    pdr_state_.current_pos.x += dx;
    pdr_state_.current_pos.y += dy;

    // Simulated IMU drift: ~2-5% drift vector accumulation per step
    float drift_x = dx * 0.035f;
    float drift_y = dy * 0.035f;
    pdr_state_.accumulated_drift.x += drift_x;
    pdr_state_.accumulated_drift.y += drift_y;
}

void NavigationEngine::setPdrPosition(const Vector2& pos, float heading_rad) {
    pdr_state_.current_pos = pos;
    pdr_state_.heading_rad = heading_rad;
}

int NavigationEngine::computeLevenshteinDistance(const std::string& s1, const std::string& s2) {
    size_t m = s1.size();
    size_t n = s2.size();

    if (m == 0) return static_cast<int>(n);
    if (n == 0) return static_cast<int>(m);

    std::vector<std::vector<int>> dp(m + 1, std::vector<int>(n + 1, 0));

    for (size_t i = 0; i <= m; ++i) dp[i][0] = static_cast<int>(i);
    for (size_t j = 0; j <= n; ++j) dp[0][j] = static_cast<int>(j);

    for (size_t i = 1; i <= m; ++i) {
        for (size_t j = 1; j <= n; ++j) {
            char c1 = std::tolower(static_cast<unsigned char>(s1[i - 1]));
            char c2 = std::tolower(static_cast<unsigned char>(s2[j - 2 + 1]));
            int cost = (c1 == c2) ? 0 : 1;

            dp[i][j] = std::min({
                dp[i - 1][j] + 1,      // deletion
                dp[i][j - 1] + 1,      // insertion
                dp[i - 1][j - 1] + cost // substitution
            });
        }
    }

    return dp[m][n];
}

float NavigationEngine::computeLevenshteinSimilarity(const std::string& s1, const std::string& s2) {
    int max_len = static_cast<int>(std::max(s1.length(), s2.length()));
    if (max_len == 0) return 1.0f;

    int dist = computeLevenshteinDistance(s1, s2);
    return 1.0f - (static_cast<float>(dist) / static_cast<float>(max_len));
}

bool NavigationEngine::snapToOcrGroundTruth(const std::string& detected_text, float similarity_threshold) {
    // Find best matching plaque across all map nodes
    float best_sim = 0.0f;
    uint32_t best_node_id = 0;
    bool found = false;

    for (const auto& pair : nodes_) {
        const auto& node = pair.second;
        if (node.plaque_label.empty()) continue;

        float sim = computeLevenshteinSimilarity(detected_text, node.plaque_label);
        if (sim >= similarity_threshold && sim > best_sim) {
            best_sim = sim;
            best_node_id = node.id;
            found = true;
        }
    }

    if (found) {
        // Spec: Snap estimated user coordinates directly to the plaque's spatial node
        // and zero out accumulated drift (e_drift = 0).
        pdr_state_.current_pos = nodes_[best_node_id].coordinate;
        pdr_state_.accumulated_drift = {0.0f, 0.0f}; // e_drift = 0
        return true;
    }

    return false;
}

} // namespace orbisnav
