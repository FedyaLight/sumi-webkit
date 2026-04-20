#ifndef AURA_SERVICES_MODELS_AURA_CUSTOMIZATION_BUNDLE_H_
#define AURA_SERVICES_MODELS_AURA_CUSTOMIZATION_BUNDLE_H_

#include <string>
#include <vector>

#include "aura/services/models/aura_customization_state.h"
#include "aura/services/models/aura_profile_state.h"

namespace aura_browser {

// Versioned import/export format used by `aura://settings/`. Internal persisted
// customization state lives in `AuraCustomizationState`.
struct AuraCustomizationBundle {
  int schema_version = 1;
  std::string bundle_version = "1";
  AuraCustomizationGlobalState global_state;
  std::vector<AuraProfileState> profiles;
};

struct AuraCustomizationImportPreview {
  bool valid = false;
  int profile_count = 0;
  int space_count = 0;
  int pinned_entry_count = 0;
  int tree_entry_count = 0;
  int essential_count = 0;
  int theme_count = 0;
  int saved_theme_color_count = 0;
  int pinned_extension_count = 0;
  std::vector<std::string> warnings;
};

}  // namespace aura_browser

#endif  // AURA_SERVICES_MODELS_AURA_CUSTOMIZATION_BUNDLE_H_
