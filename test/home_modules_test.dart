import 'package:flutter_test/flutter_test.dart';
import 'package:lazer_nextgen/state/home_modules.dart';

void main() {
  group('HomeModule', () {
    test('restores a persisted order and keeps every module', () {
      final List<HomeModule> restored = HomeModule.restoreOrder(
        'stations,recent',
      );
      expect(restored.first, HomeModule.stations);
      expect(restored[1], HomeModule.recent);
      expect(restored.length, HomeModule.values.length);
      expect(restored.toSet(), HomeModule.values.toSet());
    });

    test('appends modules the stored order did not mention', () {
      final List<HomeModule> restored = HomeModule.restoreOrder('recent');
      expect(restored, containsAll(HomeModule.values));
      expect(
        restored.indexOf(HomeModule.recent),
        lessThan(restored.indexOf(HomeModule.stations)),
      );
    });

    test('drops unknown ids without losing a module', () {
      final List<HomeModule> restored = HomeModule.restoreOrder(
        'recent,unknown,charts',
      );
      expect(restored.length, HomeModule.values.length);
      expect(restored.toSet(), HomeModule.values.toSet());
    });

    test('falls back to the default order for an empty store', () {
      expect(HomeModule.restoreOrder(null), HomeModule.defaultOrder);
      expect(HomeModule.restoreOrder(''), HomeModule.defaultOrder);
    });

    test('restores the hidden set', () {
      expect(
        HomeModule.restoreHidden('recent,charts'),
        <HomeModule>{HomeModule.recent, HomeModule.charts},
      );
      expect(HomeModule.restoreHidden(null), isEmpty);
      expect(HomeModule.restoreHidden(''), isEmpty);
      expect(HomeModule.restoreHidden('nope'), isEmpty);
    });

    test('resolves ids back to modules', () {
      for (final HomeModule module in HomeModule.values) {
        expect(HomeModule.fromId(module.id), module);
      }
      expect(HomeModule.fromId('missing'), isNull);
    });
  });
}
