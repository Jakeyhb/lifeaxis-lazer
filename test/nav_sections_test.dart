import 'package:flutter_test/flutter_test.dart';
import 'package:lazer_nextgen/state/nav_sections.dart';

void main() {
  group('NavSection', () {
    test('restores a persisted order and keeps every destination', () {
      final List<NavSection> restored = NavSection.restoreOrder(
        'settings,likes',
      );
      expect(restored.first, NavSection.settings);
      expect(restored[1], NavSection.likes);
      expect(restored.length, NavSection.values.length);
      expect(restored.toSet(), NavSection.values.toSet());
    });

    test('appends destinations the stored order did not mention', () {
      final List<NavSection> restored = NavSection.restoreOrder('home');
      expect(restored, containsAll(NavSection.values));
      expect(
        restored.indexOf(NavSection.home),
        lessThan(restored.indexOf(NavSection.settings)),
      );
    });

    test('drops unknown ids without losing a destination', () {
      final List<NavSection> restored = NavSection.restoreOrder(
        'home,unknown,search',
      );
      expect(restored.length, NavSection.values.length);
      expect(restored.toSet(), NavSection.values.toSet());
    });

    test('falls back to the default order for an empty store', () {
      expect(NavSection.restoreOrder(null), NavSection.defaultOrder);
      expect(NavSection.restoreOrder(''), NavSection.defaultOrder);
    });

    test('restores the hidden set', () {
      expect(NavSection.restoreHidden('home,search'), <NavSection>{
        NavSection.home,
        NavSection.search,
      });
      expect(NavSection.restoreHidden(null), isEmpty);
      expect(NavSection.restoreHidden(''), isEmpty);
      expect(NavSection.restoreHidden('nope'), isEmpty);
    });

    test('resolves ids back to destinations', () {
      for (final NavSection section in NavSection.values) {
        expect(NavSection.fromId(section.id), section);
      }
      expect(NavSection.fromId('missing'), isNull);
    });

    test('drops duplicates and whitespace from stored order', () {
      expect(
        NavSection.restoreOrder(' likes,likes, settings ,unknown'),
        <NavSection>[
          NavSection.likes,
          NavSection.settings,
          NavSection.home,
          NavSection.search,
          NavSection.library,
        ],
      );
    });

    test('repairs a stored hidden set with too few visible destinations', () {
      final Set<NavSection> hidden = NavSection.restoreHidden(
        NavSection.values.map((NavSection section) => section.id).join(','),
      );
      expect(
        NavSection.values.where(
          (NavSection section) => !hidden.contains(section),
        ),
        <NavSection>[NavSection.home, NavSection.search],
      );
    });
  });
}
