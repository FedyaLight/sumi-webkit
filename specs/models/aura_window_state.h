#ifndef AURA_SERVICES_MODELS_AURA_WINDOW_STATE_H_
#define AURA_SERVICES_MODELS_AURA_WINDOW_STATE_H_

#include <optional>
#include <string>
#include <vector>

#include "aura/services/models/aura_entities.h"

namespace aura_browser {

struct AuraWindowState {
  int schema_version = 1;
  std::string window_id;
  AuraWindowMode window_mode = AuraWindowMode::kStandard;
  std::string active_space_id;
  std::vector<std::string> collapsed_pinned_space_ids;
  AuraSelectionState selection;
  std::vector<std::string> expanded_folder_ids;
  AuraCompactModeState compact_mode_state;
  std::vector<AuraEssentialInstance> live_essentials;
  AuraMediaCardsState media_cards_state;
  std::vector<std::string> mru_tab_ids;
  std::vector<AuraSplitState> split_states;
  std::optional<AuraGlanceState> glance_state;
};

}  // namespace aura_browser

#endif  // AURA_SERVICES_MODELS_AURA_WINDOW_STATE_H_
