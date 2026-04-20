#ifndef AURA_SERVICES_MODELS_AURA_ENTITIES_H_
#define AURA_SERVICES_MODELS_AURA_ENTITIES_H_

#include <optional>
#include <string>
#include <vector>

namespace aura_browser {

enum class LauncherKind {
  kRegular,
  kPinned,
  kEssential,
};

struct AuraLauncher {
  std::string id;
  LauncherKind kind = LauncherKind::kRegular;
  std::string title;
  std::string url;
  std::optional<std::string> icon_asset;
  bool is_live = false;
  bool reset_to_base_url_on_activate = false;
};

enum class AuraEntryNodeKind {
  kLauncher,
  kFolder,
};

struct AuraEntryNode {
  std::string id;
  AuraEntryNodeKind kind = AuraEntryNodeKind::kLauncher;
  std::string title;
  std::optional<std::string> folder_icon_asset;
  std::optional<AuraLauncher> launcher;
  std::vector<AuraEntryNode> children;
  bool collapsed = false;
};

struct AuraSpace {
  std::string id;
  std::string name;
  std::string profile_id;
  std::optional<std::string> icon_asset;
  std::vector<AuraEntryNode> pinned_entries;
  std::vector<AuraEntryNode> root_entries;
};

struct AuraEssentialInstance {
  std::string id;
  std::string launcher_id;
  std::string attached_profile_id;
  std::optional<std::string> tab_id;
  std::optional<std::string> split_id;
  bool reserves_launcher_slot = true;
  bool launcher_slot_shows_split_proxy = false;
  bool detached_from_launcher = false;
  bool is_live = false;
};

struct AuraLauncherRuntimeState {
  std::string launcher_id;
  std::string space_id;
  std::optional<std::string> live_tab_id;
  LauncherKind kind = LauncherKind::kRegular;
  std::string base_url;
  std::string current_url;
  bool supports_changed_url_affordance = false;
  bool current_url_differs_from_base_url = false;
  bool show_changed_url_slash = false;
  bool show_reset_to_base_url_button = false;
  bool reset_button_uses_original_page_icon = true;
  bool reset_button_selects_launcher = true;
  bool accel_reset_duplicates_to_unpinned_tab = true;
  bool edit_link_available = false;
};

enum class AuraProfileRuntimeState {
  kDormant,
  kLoadedInactive,
  kActive,
};

struct AuraProfileRuntimeRecord {
  std::string profile_id;
  AuraProfileRuntimeState runtime_state = AuraProfileRuntimeState::kDormant;
  bool has_live_tabs = false;
  bool has_live_essential_instance = false;
  bool has_media_activity = false;
  bool has_download_or_upload_activity = false;
};

enum class AuraSiteControlsSecurityState {
  kSecure,
  kNotSecure,
};

enum class AuraSiteControlsHeaderActionId {
  kShare,
  kReaderMode,
  kScreenshot,
  kBookmark,
};

struct AuraSiteControlsHeaderActionState {
  AuraSiteControlsHeaderActionId id = AuraSiteControlsHeaderActionId::kShare;
  bool visible = true;
  bool enabled = true;
  bool active = false;
  bool fallback_to_copy_url = false;
};

struct AuraSitePermissionRow {
  std::string id;
  std::string title;
  std::string icon_name;
  std::optional<std::string> secondary_label;
  bool visible = true;
  bool enabled = true;
};

struct AuraSiteControlsFooterState {
  AuraSiteControlsSecurityState security_state =
      AuraSiteControlsSecurityState::kSecure;
  bool show_security_button = true;
  bool show_actions_menu = true;
};

struct SiteControlsSnapshot {
  std::string origin;
  std::vector<AuraSiteControlsHeaderActionState> header_actions;
  std::vector<AuraSitePermissionRow> settings_rows;
  std::vector<AuraSitePermissionRow> third_party_storage_rows;
  AuraSiteControlsFooterState footer;
  bool anchor_visible = true;
  bool hide_anchor_on_empty_space_surface = true;
  bool hide_anchor_on_floating_urlbar = true;
  bool share_uses_copy_url_fallback = false;
  bool autoplay_blocked = false;
  bool tracking_protection_enabled = true;
  bool can_clear_site_data = true;
};

enum class AuraMediaCardSuppressedReason {
  kNone,
  kVisibleTab,
  kDismissedPlaybackEpoch,
  kPictureInPictureOrFullscreen,
  kUpstreamSuppressed,
};

struct BackgroundMediaSession {
  std::string id;
  std::string playback_epoch_id;
  std::string tab_id;
  std::string title;
  std::string artist;
  std::string source_name;
  std::string origin;
  std::string artwork_url;
  bool muted = false;
  bool audible = false;
  bool playing = false;
  bool buffering = false;
  bool can_seek = false;
  bool can_skip_next = false;
  bool can_skip_previous = false;
  bool can_focus_tab = true;
  bool can_picture_in_picture = false;
  bool media_sharing = false;
  bool media_position_hidden = false;
  bool is_picture_in_picture_or_fullscreen = false;
  bool sharing_microphone = false;
  bool sharing_camera = false;
  bool microphone_muted = false;
  bool camera_muted = false;
  bool can_mute_microphone = false;
  bool can_mute_camera = false;
  AuraMediaCardSuppressedReason suppressed_reason =
      AuraMediaCardSuppressedReason::kNone;
  double position_seconds = 0.0;
  double duration_seconds = 0.0;
};

struct AuraMediaCardModel {
  std::string session_id;
  std::string playback_epoch_id;
  std::string tab_id;
  std::string title;
  std::string subtitle;
  std::string source_name;
  std::string origin;
  std::string artwork_url;
  bool show_progress = false;
  bool show_previous = false;
  bool show_next = false;
  bool show_play_pause = true;
  bool show_mute_toggle = true;
  bool show_mute_microphone = false;
  bool show_mute_camera = false;
  bool show_focus_button = true;
  bool show_picture_in_picture = false;
  bool show_hover_reveal_controls = true;
  bool show_media_sharing_device_controls = false;
  bool marquee_on_hover_only = true;
  bool show_notes_animation = false;
  bool show_media_position = true;
  bool media_sharing = false;
  bool sharing_microphone = false;
  bool sharing_camera = false;
  bool microphone_muted = false;
  bool camera_muted = false;
  AuraMediaCardSuppressedReason suppressed_reason =
      AuraMediaCardSuppressedReason::kNone;
  double position_seconds = 0.0;
  double duration_seconds = 0.0;
};

enum class AuraAddressBarPresentation {
  kAttached,
  kFloating,
  kCompactReveal,
};

enum class AuraAddressBarOpenReason {
  kDirectFocus,
  kNewTabReplacement,
  kShortcut,
  kCommandBar,
};

enum class AuraUrlBarBehaviorMode {
  kNormal,
  kFloatingOnType,
  kAlwaysFloating,
};

struct AuraAddressBarState {
  bool visible = false;
  AuraAddressBarPresentation presentation =
      AuraAddressBarPresentation::kAttached;
  AuraAddressBarOpenReason open_reason = AuraAddressBarOpenReason::kDirectFocus;
  std::string query;
  bool preserve_query_on_close = true;
  bool preserve_on_window_blur = true;
  bool show_all_commands_on_empty_tab = true;
  bool allow_space_switch_results = true;
  bool allow_extension_results = true;
  bool prefixed_action_mode = false;
  bool select_full_untrimmed_value = false;
  bool suppress_site_controls_anchor = false;
  bool show_overflow_extensions_below_address_bar = false;
};

struct AuraUrlBarPreferences {
  AuraUrlBarBehaviorMode behavior_mode = AuraUrlBarBehaviorMode::kNormal;
  bool show_copy_url_button = true;
  bool show_picture_in_picture_button = true;
  bool show_contextual_identity = true;
};

struct AuraWorkspaceNavigationPreferences {
  bool wrap_around_navigation = true;
  bool open_new_tab_if_last_unpinned_closes = false;
};

enum class AuraDarkThemeStyle {
  kDefault,
  kNight,
  kColorful,
};

enum class AuraWindowSchemeMode {
  kAuto,
  kLight,
  kDark,
};

enum class AuraLayoutMode {
  kSingleToolbar,
  kMultipleToolbar,
  kCollapsedToolbar,
};

struct AuraLayoutPreferences {
  AuraLayoutMode layout_mode = AuraLayoutMode::kSingleToolbar;
  bool tabs_on_right = false;
};

struct AuraCompactModeState {
  bool enabled = false;
  bool hide_sidebar = true;
  bool hide_toolbar = false;
  bool sidebar_revealed = false;
  bool toolbar_revealed = false;
  bool reveal_locked_by_keyboard = false;
  bool hover_reveal_enabled = true;
  int hover_hide_delay_ms = 1000;
  bool flash_popup_enabled = false;
  int flash_popup_duration_ms = 800;
};

struct AuraCompactModePreferences {
  bool enabled = false;
  bool hide_sidebar = true;
  bool hide_toolbar = false;
  bool hover_reveal_enabled = true;
  int hover_hide_delay_ms = 1000;
  bool flash_popup_enabled = false;
  int flash_popup_duration_ms = 800;
  bool use_themed_background = false;
};

enum class AuraKeyboardTraversalMode {
  kSequential,
  kMostRecentlyUsed,
};

enum class AuraKeyboardCommandId {
  kFocusAddressBar,
  kToggleAddressBarNewTabMode,
  kShowAllCommandBarActions,
  kCreateBlankWindow,
  kOpenCtrlTabPanel,
  kCycleCtrlTabForward,
  kCycleCtrlTabBackward,
  kToggleCompactMode,
  kSwitchToNextSpace,
  kSwitchToPreviousSpace,
  kSwitchToIndexedSpace,
  kSelectIndexedTab,
  kToggleSplitHorizontal,
  kToggleSplitVertical,
  kToggleSplitGrid,
  kUnsplitAllTabs,
  kPromoteGlanceToTab,
  kPromoteGlanceToSplit,
};

struct AuraKeyboardState {
  AuraKeyboardTraversalMode traversal_mode =
      AuraKeyboardTraversalMode::kSequential;
  bool shortcuts_customizable = true;
  bool numbering_includes_essentials = true;
  bool numbering_includes_pinned = true;
  bool command_results_have_priority = true;
};

struct AuraKeyboardCommand {
  AuraKeyboardCommandId id = AuraKeyboardCommandId::kFocusAddressBar;
  std::optional<int> numeric_index;
};

enum class AuraWindowMode {
  kStandard,
  kBlank,
};

enum class AuraSpaceSwitchTrigger {
  kSidebar,
  kKeyboard,
  kAddressBar,
  kGesture,
  kDragHover,
};

enum class AuraSurfaceId {
  kExtensionsHub,
  kThemeEditor,
  kGlance,
  kSplitView,
  kCtrlTabPanel,
  kSidebarContextMenu,
  kMediaMenu,
};

struct AuraCtrlTabPanelState {
  bool visible = false;
  bool uses_mru_order = true;
  std::vector<std::string> ordered_tab_ids;
  std::optional<std::string> selected_tab_id;
};

struct AuraSpaceTransitionState {
  bool active = false;
  std::string source_space_id;
  std::string target_space_id;
  AuraSpaceSwitchTrigger trigger = AuraSpaceSwitchTrigger::kSidebar;
  double progress = 0.0;
  bool gesture_driven = false;
  bool warm_target_tab_before_commit = true;
  bool activate_target_space_without_loading_profile = false;
};

struct AuraMediaCardsState {
  std::vector<std::string> dismissed_playback_epoch_ids;
};

struct AuraSidebarVisualDensityState {
  int collapsed_sidebar_width = 60;
  int essentials_min_item_height = 44;
  int tab_block_margin = 2;
  int section_gap = 10;
  int header_horizontal_padding = 10;
  int header_vertical_padding = 6;
  int regular_row_min_height = 36;
  int pinned_row_min_height = 36;
  int folder_indent_step = 14;
  int footer_gap = 12;
  int media_stack_gap = 10;
};

struct AuraPanelVisualTokens {
  int panel_width = 380;
  int panel_padding = 10;
  int context_menu_radius = 8;
  int arrow_panel_radius = 10;
  int arrow_panel_radius_macos_tahoe = 12;
  int arrow_panel_shadow_margin = 8;
  int native_macos_arrow_panel_shadow_margin = 0;
  int menu_item_border_radius = 5;
  int menu_item_padding_block = 8;
  int menu_item_padding_inline = 14;
  int menu_item_margin_inline = 4;
  int menu_item_margin_block = 2;
  int menu_icon_margin_inline = 14;
  int panel_separator_margin_vertical = 2;
  int panel_separator_margin_horizontal = 1;
  int panel_footer_button_padding_block = 20;
  int panel_footer_button_padding_inline = 15;
  int permission_section_padding_block = 8;
  int permission_section_padding_inline = 16;
  int permission_row_padding_block = 4;
  int theme_picker_overlay_button_size = 30;
  int theme_picker_page_button_size = 28;
  int theme_picker_overlay_button_gap = 5;
  int theme_picker_scheme_top_inset = 15;
  int theme_picker_swatch_size = 26;
  int theme_picker_primary_dot_diameter = 38;
  int theme_picker_primary_dot_border_width = 6;
  double theme_picker_swatch_hover_scale = 1.05;
  double theme_picker_swatch_active_scale = 0.95;
  bool native_macos_arrow_panels_use_os_shadow = true;
  bool native_macos_arrow_panels_force_transparent_background = true;
  bool non_native_macos_popovers_use_menu_background = true;
  bool constrain_popovers_to_available_screen = true;
};

enum class AuraSurfaceKind {
  kContextMenu,
  kPopoverPanel,
  kPersistentTransientSurface,
};

enum class AuraSurfaceAnchorKind {
  kAddressBarCluster,
  kAddressBarOverflowStrip,
  kSidebarBackground,
  kSpaceHeader,
  kEntryRow,
  kMediaCard,
  kWindowCenter,
};

struct AuraTransientSurfaceLayoutState {
  AuraSurfaceId surface_id = AuraSurfaceId::kExtensionsHub;
  AuraSurfaceKind surface_kind = AuraSurfaceKind::kPopoverPanel;
  AuraSurfaceAnchorKind anchor_kind = AuraSurfaceAnchorKind::kAddressBarCluster;
  std::optional<std::string> anchor_id;
  bool bounded_to_window = true;
  bool prefers_material_blur = false;
  bool hide_popover_tail = false;
  bool prefer_native_macos_popover = false;
  bool force_non_native_macos_popover = false;
  bool constrain_height_to_available_screen = true;
};

struct AuraThemeEditorState {
  bool visible = false;
  std::string space_id;
  std::optional<std::string> opener_id;
  int preset_page_index = 0;
  bool preview_dirty = false;
};

enum class AuraSelectionKind {
  kNone,
  kSpace,
  kEmptySpaceSurface,
  kEntryNode,
  kTab,
  kEssential,
  kSplitItem,
  kGlance,
};

struct AuraSelectionState {
  AuraSelectionKind kind = AuraSelectionKind::kNone;
  std::string active_space_id;
  std::optional<std::string> active_empty_space_surface_id;
  std::optional<std::string> selected_entry_id;
  std::optional<std::string> active_tab_id;
  std::optional<std::string> focused_split_tab_id;
  std::optional<std::string> active_glance_id;
  std::optional<std::string> active_essential_instance_id;
  std::optional<std::string> most_recent_tab_id;
};

struct AuraEmptySpaceSurfaceState {
  std::string surface_id;
  std::string space_id;
  bool visible = false;
  bool selected = false;
  bool uses_new_tab_affordance = true;
};

struct AuraFolderPlaceholderState {
  std::string folder_id;
  bool visible = false;
  bool first_in_folder_presentation = true;
};

struct AuraFolderRuntimeState {
  std::string folder_id;
  std::vector<std::string> active_child_ids;
  bool has_active_projection = false;
  bool collapsed = false;
  int current_level = 0;
  int max_depth = 5;
};

struct AuraFolderIconPresentationState {
  std::string folder_id;
  std::optional<std::string> icon_asset;
  bool icon_lives_inside_folder_shell = true;
  bool open_state = false;
  bool active_projection_state = false;
};

struct AuraFolderProjectionState {
  std::string folder_id;
  std::vector<std::string> projected_child_ids;
  std::optional<AuraFolderPlaceholderState> placeholder_state;
  bool reset_available = false;
};

enum class AuraDragItemKind {
  kEntryNode,
  kTab,
  kEssential,
  kSplitItem,
  kGlance,
};

struct AuraDragSession {
  std::string drag_id;
  AuraDragItemKind kind = AuraDragItemKind::kEntryNode;
  std::string source_id;
  std::string source_space_id;
  std::optional<std::string> source_parent_id;
  std::optional<std::string> source_tab_id;
  bool from_pinned_section = false;
  bool from_essentials = false;
  bool from_split = false;
  bool from_glance = false;
};

enum class AuraDropDisposition {
  kNone,
  kBeforeTarget,
  kAfterTarget,
  kIntoFolder,
  kIntoSpaceRoot,
  kPromoteToEssential,
  kSplitLeft,
  kSplitRight,
  kSplitTop,
  kSplitBottom,
};

enum class AuraSplitLayoutPreset {
  kGrid,
  kVertical,
  kHorizontal,
};

enum class AuraSplitLayoutNodeKind {
  kLeaf,
  kRow,
  kColumn,
};

struct AuraSplitLayoutNode {
  AuraSplitLayoutNodeKind kind = AuraSplitLayoutNodeKind::kLeaf;
  double size_in_parent = 100.0;
  std::optional<std::string> tab_id;
  std::vector<AuraSplitLayoutNode> children;
};

struct AuraSplitHeaderControlsState {
  bool visible_on_hover = true;
  bool show_rearrange_button = true;
  bool show_unsplit_button = true;
};

struct AuraDropIntent {
  AuraDropDisposition disposition = AuraDropDisposition::kNone;
  std::string target_space_id;
  std::optional<std::string> target_id;
  std::optional<std::string> target_parent_id;
  std::optional<std::string> target_tab_id;
  std::optional<std::string> target_split_id;
  bool preview_only = false;
  bool keep_focus_on_current = false;
  bool duplicate_source_if_pinned = false;
  bool create_empty_split_if_target_matches_source = false;
  AuraSplitLayoutPreset split_layout_preset = AuraSplitLayoutPreset::kGrid;
};

enum class AuraSplitAxis {
  kHorizontal,
  kVertical,
};

struct AuraSplitItem {
  std::string tab_id;
  double flex = 1.0;
};

struct AuraSplitState {
  std::string split_id;
  std::string group_id;
  std::string space_id;
  AuraSplitAxis axis = AuraSplitAxis::kHorizontal;
  AuraSplitLayoutPreset layout_preset = AuraSplitLayoutPreset::kGrid;
  // Runtime-facing flat projection derived from `layout_tree`. Persisted split
  // restore must treat `layout_tree` as the canonical source of truth.
  std::vector<AuraSplitItem> projected_items;
  std::optional<AuraSplitLayoutNode> layout_tree;
  std::optional<std::string> focused_tab_id;
  std::optional<std::string> folder_parent_id;
  AuraSplitHeaderControlsState header_controls;
  bool render_as_grouped_sidebar_unit = true;
  bool sidebar_group_collapsible = false;
  bool move_as_single_sidebar_unit = true;
  bool show_active_outline = true;
  bool pin_state_propagates_across_group = true;
  bool allow_empty_split_replacement = true;
  bool pinned_group = false;
  bool hide_in_fullscreen = true;
};

struct AuraGlanceState {
  std::string glance_id;
  std::string parent_tab_id;
  std::string preview_tab_id;
  std::string source_url;
  bool can_promote_to_split = true;
  bool expanded_to_full_tab = false;
  bool visible_across_workspace_filtering = true;
  bool selects_preview_when_parent_selected = true;
  bool hidden_from_sidebar_counts = true;
  bool render_as_standalone_sidebar_entry = false;
  bool follows_parent_space_on_move = true;
  bool close_requires_focused_confirmation = true;
  int close_confirmation_timeout_ms = 3000;
  bool split_with_parent_only = true;
  bool reverse_split_order_on_right_sidebar = true;
  bool reduce_motion_skips_expand_animation = true;
};

struct AuraRestoreSnapshot {
  AuraWindowMode window_mode = AuraWindowMode::kStandard;
  std::string active_space_id;
  std::vector<std::string> expanded_folder_ids;
  AuraSelectionState selection;
  AuraCompactModeState compact_mode_state;
  std::vector<AuraEssentialInstance> live_essentials;
  AuraMediaCardsState media_cards_state;
  AuraSidebarVisualDensityState sidebar_visual_density_state;
  std::vector<AuraSplitState> split_states;
  std::optional<AuraGlanceState> glance_state;
};

}  // namespace aura_browser

#endif  // AURA_SERVICES_MODELS_AURA_ENTITIES_H_
