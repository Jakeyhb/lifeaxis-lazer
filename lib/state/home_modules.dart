/// One configurable section of the home page.
///
/// The order and visibility are the listener's own and persist across
/// launches. The catalogue only decides whether a module has anything to
/// show, so a hidden module stays hidden and an empty one collapses.
enum HomeModule {
  actions('actions', '为你打造'),
  recent('recent', '最近播放'),
  newReleases('new_releases', '为你推荐的新发行'),
  editorial('editorial', '网易云编辑精选'),
  charts('charts', '排行榜'),
  recommendations('recommendations', '猜你喜欢'),
  stations('stations', '为你创建的电台');

  const HomeModule(this.id, this.titleKey);

  /// Stable identifier persisted in preferences.
  final String id;

  /// Untranslated section title, used as the localization key.
  final String titleKey;

  static const List<HomeModule> defaultOrder = <HomeModule>[
    actions,
    recent,
    newReleases,
    editorial,
    charts,
    recommendations,
    stations,
  ];

  static HomeModule? fromId(String id) {
    for (final HomeModule module in values) {
      if (module.id == id) return module;
    }
    return null;
  }

  /// Restores a persisted order, dropping unknown ids and appending every
  /// module the stored list did not mention, so a section added by a later
  /// build still appears instead of being silently hidden.
  static List<HomeModule> restoreOrder(Object? stored) {
    final List<HomeModule> restored = <HomeModule>[];
    if (stored is String && stored.isNotEmpty) {
      for (final String id in stored.split(',')) {
        final HomeModule? module = fromId(id.trim());
        if (module != null && !restored.contains(module)) restored.add(module);
      }
    }
    for (final HomeModule module in values) {
      if (!restored.contains(module)) restored.add(module);
    }
    return restored;
  }

  /// Restores the hidden set from a persisted comma-separated id list.
  static Set<HomeModule> restoreHidden(Object? stored) {
    if (stored is! String || stored.isEmpty) return <HomeModule>{};
    final Set<HomeModule> result = <HomeModule>{};
    for (final String id in stored.split(',')) {
      final HomeModule? module = fromId(id.trim());
      if (module != null) result.add(module);
    }
    return result;
  }
}
