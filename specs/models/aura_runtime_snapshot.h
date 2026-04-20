#ifndef AURA_SERVICES_MODELS_AURA_RUNTIME_SNAPSHOT_H_
#define AURA_SERVICES_MODELS_AURA_RUNTIME_SNAPSHOT_H_

#include <optional>
#include <string>
#include <vector>

#include "aura/services/models/aura_entities.h"

namespace aura_browser {

struct AuraRuntimeSnapshot {
  std::string active_space_id;
  AuraSelectionState selection;
  std::optional<AuraEmptySpaceSurfaceState> empty_space_surface_state;
  std::optional<AuraSpaceTransitionState> space_transition_state;
  AuraSidebarVisualDensityState sidebar_visual_density_state;
  AuraPanelVisualTokens panel_visual_tokens;
  std::vector<AuraTransientSurfaceLayoutState> transient_surface_layout_states;
  std::optional<AuraThemeEditorState> theme_editor_state;
  std::vector<AuraLauncherRuntimeState> launcher_runtime_states;
  std::vector<AuraFolderRuntimeState> folder_runtime_states;
  std::vector<AuraFolderProjectionState> folder_projection_states;
  std::vector<AuraProfileRuntimeRecord> profile_runtime_states;
  std::vector<AuraEssentialInstance> live_essentials;
  SiteControlsSnapshot site_controls;
  std::vector<BackgroundMediaSession> background_media_sessions;
  std::vector<AuraMediaCardModel> media_cards;
  std::vector<AuraSplitState> split_states;
  std::optional<AuraGlanceState> glance_state;
};

}  // namespace aura_browser

#endif  // AURA_SERVICES_MODELS_AURA_RUNTIME_SNAPSHOT_H_
