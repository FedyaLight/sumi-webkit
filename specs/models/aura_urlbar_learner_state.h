#ifndef AURA_SERVICES_MODELS_AURA_URLBAR_LEARNER_STATE_H_
#define AURA_SERVICES_MODELS_AURA_URLBAR_LEARNER_STATE_H_

#include <optional>
#include <string>
#include <vector>

namespace aura_browser {

enum class AuraUrlbarActionKind {
  kGlobalCommand,
  kWorkspaceSwitch,
  kThemeAppearance,
};

struct AuraUrlbarAction {
  std::string command_id;
  AuraUrlbarActionKind kind = AuraUrlbarActionKind::kGlobalCommand;
  std::string label;
  std::string icon_name;
  std::vector<std::string> match_terms;
  bool available = true;
  bool show_in_prefixed_mode = true;
  bool show_in_standard_mode = true;
  bool requires_http_scheme = false;
  bool requires_live_page_runtime = false;
  bool allowed_on_empty_space_surface = true;
  bool requires_multiple_spaces = false;
  bool only_when_selected_tab_pinned = false;
  bool hide_when_selected_tab_pinned = false;
  bool only_when_selected_tab_essential = false;
  bool hide_when_selected_tab_essential = false;
  bool requires_add_to_essentials_capability = false;
  bool requires_remove_from_essentials_capability = false;
  bool boost_for_current_url_match = false;
  bool boost_for_live_page_context = false;
  std::optional<std::string> workspace_id;
};

struct AuraUrlbarActionCatalog {
  std::vector<AuraUrlbarAction> actions;
};

struct AuraUrlbarActionContext {
  std::string current_uri;
  std::string current_display_url;
  std::string current_page_title;
  bool on_empty_space_surface = false;
  bool has_live_page_runtime = false;
  bool selected_tab_is_pinned = false;
  bool selected_tab_is_essential = false;
  bool can_add_selected_tab_to_essentials = false;
  bool can_remove_selected_tab_from_essentials = false;
  bool has_multiple_spaces = false;
};

struct AuraUrlbarLearnerEntry {
  std::string command_id;
  int score = 0;
};

struct AuraUrlbarLearnerState {
  int schema_version = 1;
  int prioritize_max = 5;
  int deprioritize_max = -5;
  std::vector<AuraUrlbarLearnerEntry> entries;
};

}  // namespace aura_browser

#endif  // AURA_SERVICES_MODELS_AURA_URLBAR_LEARNER_STATE_H_
