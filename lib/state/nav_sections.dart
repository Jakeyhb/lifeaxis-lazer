import 'package:flutter/material.dart';

/// One destination of the bottom navigation bar and the desktop sidebar.
///
/// The order and visibility are the listener's own and persist across
/// launches. Hiding the section that is currently open falls back to the
/// first visible one so the shell never shows an unselectable tab.
enum NavSection {
  home('home', '主页', Icons.home_outlined, Icons.home_rounded),
  search('search', '搜索', Icons.search_outlined, Icons.search_rounded),
  library(
    'library',
    '音乐库',
    Icons.library_music_outlined,
    Icons.library_music_rounded,
  ),
  likes('likes', '我喜欢', Icons.favorite_border_rounded, Icons.favorite_rounded),
  settings('settings', '设置', Icons.settings_outlined, Icons.settings_rounded);

  const NavSection(this.id, this.labelKey, this.icon, this.selectedIcon);

  /// Stable identifier persisted in preferences.
  final String id;

  /// Untranslated section title, used as the localization key.
  final String labelKey;

  final IconData icon;
  final IconData selectedIcon;

  static const List<NavSection> defaultOrder = <NavSection>[
    home,
    search,
    library,
    likes,
    settings,
  ];

  static const int minimumVisibleCount = 2;

  static NavSection? fromId(String id) {
    for (final NavSection section in values) {
      if (section.id == id) return section;
    }
    return null;
  }

  /// Restores a persisted order, dropping unknown ids and appending every
  /// section the stored list did not mention, so a section added by a later
  /// build still appears instead of being silently hidden.
  static List<NavSection> restoreOrder(Object? stored) {
    final List<NavSection> restored = <NavSection>[];
    if (stored is String && stored.isNotEmpty) {
      for (final String id in stored.split(',')) {
        final NavSection? section = fromId(id.trim());
        if (section != null && !restored.contains(section)) restored.add(section);
      }
    }
    for (final NavSection section in values) {
      if (!restored.contains(section)) restored.add(section);
    }
    return restored;
  }

  /// Restores the hidden set from a persisted comma-separated id list.
  static Set<NavSection> restoreHidden(Object? stored) {
    if (stored is! String || stored.isEmpty) return <NavSection>{};
    final Set<NavSection> result = <NavSection>{};
    for (final String id in stored.split(',')) {
      final NavSection? section = fromId(id.trim());
      if (section != null) result.add(section);
    }
    for (final NavSection section in defaultOrder) {
      if (values.length - result.length >= minimumVisibleCount) break;
      result.remove(section);
    }
    return result;
  }
}
