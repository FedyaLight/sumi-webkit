#ifndef AURA_SERVICES_MODELS_AURA_THEME_RUNTIME_MODEL_H_
#define AURA_SERVICES_MODELS_AURA_THEME_RUNTIME_MODEL_H_

#include <string>
#include <vector>

#include "aura/services/models/aura_entities.h"
#include "aura/services/models/aura_profile_state.h"

namespace aura_browser {

enum class AuraThemeRenderBranch {
  kDefaultTheme,
  kSingleColor,
  kCustomLinearGradient,
  kDualGradientField,
  kTripleGradientField,
};

enum class AuraThemeLayerKind {
  kSolidColor,
  kLinearGradient,
  kRadialGradient,
};

enum class AuraThemeOverlayBlendMode {
  kNone,
  kMacWhiteOverlay,
  kMicaOverlay,
};

struct AuraThemeColorStop {
  std::string color;
  double position_percent = 0.0;
};

struct AuraThemeLayerRecipe {
  AuraThemeLayerKind kind = AuraThemeLayerKind::kSolidColor;
  double angle_degrees = 0.0;
  double center_x = 0.5;
  double center_y = 0.5;
  std::vector<AuraThemeColorStop> color_stops;
};

struct AuraThemeSurfaceRecipe {
  AuraThemeRenderBranch branch = AuraThemeRenderBranch::kDefaultTheme;
  std::vector<AuraThemeLayerRecipe> layers;
  std::string fallback_color;
};

struct AuraThemeChromeRecipe {
  std::string space_id;
  AuraWindowSchemeMode window_scheme_mode = AuraWindowSchemeMode::kAuto;
  WorkspaceThemeState theme_state;
  bool can_be_transparent = false;
  bool allow_acrylic_sidebar_blend = false;
  bool is_default_theme = false;
  bool should_use_dark_toolbar_scheme = false;
  bool uses_legacy_dark_overlay = false;
  AuraThemeOverlayBlendMode overlay_blend_mode =
      AuraThemeOverlayBlendMode::kNone;
  double browser_rotation_degrees = -45.0;
  double toolbar_rotation_degrees = -45.0;
  double grain_opacity = 0.0;
  AuraThemeSurfaceRecipe browser_surface;
  AuraThemeSurfaceRecipe toolbar_surface;
  std::string primary_color;
  std::string toolbox_text_color;
  std::string toolbar_color_scheme;
};

}  // namespace aura_browser

#endif  // AURA_SERVICES_MODELS_AURA_THEME_RUNTIME_MODEL_H_
