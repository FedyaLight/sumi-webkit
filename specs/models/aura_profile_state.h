#ifndef AURA_SERVICES_MODELS_AURA_PROFILE_STATE_H_
#define AURA_SERVICES_MODELS_AURA_PROFILE_STATE_H_

#include <optional>
#include <string>
#include <vector>

#include "aura/services/models/aura_entities.h"

namespace aura_browser {

enum class WorkspaceThemeAlgorithm {
  kComplementary,
  kSplitComplementary,
  kAnalogous,
  kTriadic,
  kFloating,
};

struct WorkspaceThemeColorPoint {
  std::string id;
  std::string color_hex;
  double x = 0.5;
  double y = 0.5;
  double intensity = 1.0;
};

enum class WorkspaceThemePresetPage {
  kLightFloating,
  kLightAnalogous,
  kDarkFloating,
  kDarkAnalogous,
  kBlackWhite,
  kCustom,
};

struct WorkspaceThemePresetSelection {
  WorkspaceThemePresetPage page = WorkspaceThemePresetPage::kLightFloating;
  std::string preset_id;
  bool uses_explicit_black_white_page = false;
  int preset_lightness = 50;
};

struct WorkspaceThemeState {
  std::string space_id;
  std::string primary_color_hex = "#ffb787";
  std::vector<WorkspaceThemeColorPoint> color_points;
  std::optional<WorkspaceThemePresetSelection> preset_selection;
  bool monochrome = false;
  WorkspaceThemeAlgorithm algorithm = WorkspaceThemeAlgorithm::kFloating;
  double opacity = 0.4;
  double texture_strength = 0.0;
};

struct AuraProfileState {
  int schema_version = 1;
  std::string profile_id;
  std::vector<AuraSpace> spaces;
  std::vector<WorkspaceThemeState> workspace_themes;
};

}  // namespace aura_browser

#endif  // AURA_SERVICES_MODELS_AURA_PROFILE_STATE_H_
