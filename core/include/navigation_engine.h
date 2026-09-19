#ifndef NAVIGATION_ENGINE_H
#define NAVIGATION_ENGINE_H

#include "orbisnav_types.h"
#include <vector>
#include <string>
#include <unordered_map>
#include <optional>

namespace orbisnav {

struct NavEdge {
    uint32_t to_node_id;
    float distance_meters;
    bool is_accessible{true}; // wheelchair / obstacle clear
    bool is_floor_transition{false};
    float floor_penalty_cost{15.0f}; // step 5.1: cost penalty for floor transitions
};

class NavigationEngine {
public:
    NavigationEngine();
    ~NavigationEngine();

    // Map Management
    void addNode(const NavNode& node);
    void addEdge(uint32_t from_id, uint32_t to_id, float distance_meters, bool is_floor_transition = false, float floor_penalty = 15.0f);
    void clearMap();

    // Phase 4.1: A* Path Generation
    std::vector<uint32_t> computeAStarPath(uint32_t start_node_id, uint32_t goal_node_id);

    // Phase 4.2: Relative Clock-Face Mapping
    // Translates vector from current pos to target pos given user heading (radians)
    ClockDirection computeClockDirection(
        const Vector2& current_pos,
        float current_heading_rad,
        const Vector2& target_pos) const;

    std::string clockDirectionToString(ClockDirection clock_dir) const;

    // Phase 4.3: Pedestrian Dead Reckoning (PDR)
    void processStep(float step_length_meters, float heading_rad);
    PdrState getPdrState() const { return pdr_state_; }
    void setPdrPosition(const Vector2& pos, float heading_rad);

    // Phase 4.4: OCR Ground-Truth Snap
    // Fuzzy-match OCR string using Levenshtein distance (Sim >= 0.75)
    // Snaps user coordinates directly to spatial node and zeros out drift: e_drift = 0
    bool snapToOcrGroundTruth(const std::string& detected_text, float similarity_threshold = 0.75f);

    // Levenshtein similarity metric calculation [0.0, 1.0]
    static float computeLevenshteinSimilarity(const std::string& s1, const std::string& s2);
    static int computeLevenshteinDistance(const std::string& s1, const std::string& s2);

    // Current active route query
    const std::vector<uint32_t>& getActivePath() const { return active_path_; }
    std::optional<NavNode> getNode(uint32_t id) const;

private:
    std::unordered_map<uint32_t, NavNode> nodes_;
    std::unordered_map<uint32_t, std::vector<NavEdge>> adjacency_list_;
    std::vector<uint32_t> active_path_;
    PdrState pdr_state_;

    float heuristic(const Vector2& a, const Vector2& b) const;
};

} // namespace orbisnav

#endif // NAVIGATION_ENGINE_H
