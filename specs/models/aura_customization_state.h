#ifndef AURA_SERVICES_MODELS_AURA_CUSTOMIZATION_STATE_H_
#define AURA_SERVICES_MODELS_AURA_CUSTOMIZATION_STATE_H_

#include <string>
#include <vector>

#include "aura/services/models/aura_entities.h"

namespace aura_browser {

struct AuraCustomizationGlobalState {
  std::vector<AuraLauncher> essentials;
  AuraKeyboardState keyboard_state;
  AuraWorkspaceNavigationPreferences workspace_navigation_preferences;
  AuraCompactModePreferences compact_mode_preferences;
  AuraLayoutPreferences layout_preferences;
  AuraUrlBarPreferences urlbar_preferences;
  bool use_acrylic_elements = false;
  AuraWindowSchemeMode window_scheme_mode = AuraWindowSchemeMode::kAuto;
  AuraDarkThemeStyle dark_theme_style = AuraDarkThemeStyle::kDefault;
  double dark_mode_bias = 0.5;
};

// Internal persisted Aura-owned customization state. This is not the
// import/export bundle format.
struct AuraCustomizationState {
  int schema_version = 1;
  AuraCustomizationGlobalState global_state;
};

}  // namespace aura_browser

#endif  // AURA_SERVICES_MODELS_AURA_CUSTOMIZATION_STATE_H_
