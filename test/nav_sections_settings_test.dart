import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lazer_nextgen/state/app_state.dart';
import 'package:lazer_nextgen/l10n/app_localizations.dart';
import 'package:lazer_nextgen/state/nav_sections.dart';
import 'package:lazer_nextgen/theme/apple_design.dart';
import 'package:lazer_nextgen/ui/nav_sections_page.dart';
import 'package:lazer_nextgen/ui/pages.dart';
import 'package:lazer_nextgen/ui/shell.dart';

Finder _row(NavSection section) =>
    find.byKey(ValueKey<String>('nav-section-${section.id}'));

Finder _switch(NavSection section) =>
    find.descendant(of: _row(section), matching: find.byType(Switch));

Finder _moveButton(NavSection section, String direction) =>
    find.byKey(ValueKey<String>('nav-section-$direction-${section.id}'));

Finder _tile(NavSection section) =>
    find.byKey(ValueKey<String>('nav-section-toggle-${section.id}'));

OutlinedButton _button(WidgetTester tester, Finder finder) =>
    tester.widget<OutlinedButton>(
      find.descendant(of: finder, matching: find.byType(OutlinedButton)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'navigation preferences persist with every destination retained',
    () async {
      final AppState state = AppState();
      addTearDown(state.dispose);
      await state.setNavSectionOrder(<NavSection>[
        NavSection.settings,
        NavSection.likes,
        NavSection.settings,
      ]);
      await state.setNavSectionHidden(NavSection.search, true);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(state.navSectionOrder.toSet(), NavSection.values.toSet());
      expect(state.navSectionOrder.length, NavSection.values.length);
      expect(state.navSectionOrder.first, NavSection.settings);
      expect(
        NavSection.restoreOrder(prefs.getString('lazer_nav_section_order')),
        state.navSectionOrder,
      );
      expect(
        NavSection.restoreHidden(prefs.getString('lazer_nav_hidden_sections')),
        state.hiddenNavSections,
      );
      expect(state.visibleNavSections, isNot(contains(NavSection.search)));
      await state.setNavSectionOrder(<NavSection>[]);
      expect(state.navSectionOrder, NavSection.defaultOrder);
    },
  );

  test(
    'cannot hide the last two destinations, but can show hidden ones',
    () async {
      final AppState state = AppState();
      addTearDown(state.dispose);
      for (final NavSection section in NavSection.defaultOrder) {
        await state.setNavSectionHidden(section, true);
      }
      expect(state.visibleNavSections, <NavSection>[
        NavSection.likes,
        NavSection.settings,
      ]);
      await state.setNavSectionHidden(NavSection.home, false);
      expect(state.visibleNavSections.length, 3);
      await state.setNavSectionHidden(NavSection.settings, true);
      expect(state.visibleNavSections, <NavSection>[
        NavSection.home,
        NavSection.likes,
      ]);
    },
  );

  for (final double width in <double>[320, 1280]) {
    testWidgets('navigation editor reorders and hides at width $width', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppleTheme(),
          home: NavSectionsPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      expect(
        _button(tester, _moveButton(NavSection.home, 'up')).onPressed,
        isNull,
      );
      expect(
        _button(tester, _moveButton(NavSection.settings, 'down')).onPressed,
        isNull,
      );
      Future<void> pressMove(NavSection section, String direction) async {
        final Finder button = _moveButton(section, direction);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final Rect rect = tester.getRect(button);
        expect(rect.height, greaterThanOrEqualTo(52));
        expect(rect.width, greaterThanOrEqualTo(100));
        await tester.tapAt(rect.topLeft + const Offset(12, 12));
        await tester.pumpAndSettle();
      }

      await pressMove(NavSection.home, 'down');
      expect(state.navSectionOrder, <NavSection>[
        NavSection.search,
        NavSection.home,
        NavSection.library,
        NavSection.likes,
        NavSection.settings,
      ]);
      await pressMove(NavSection.home, 'up');
      expect(state.navSectionOrder, NavSection.defaultOrder);
      for (int step = 0; step < 4; step++) {
        await pressMove(NavSection.home, 'down');
      }
      expect(state.navSectionOrder.last, NavSection.home);
      expect(state.hiddenNavSections, isEmpty);
      await tester.ensureVisible(_tile(NavSection.search));
      await tester.pumpAndSettle();
      final Rect tileRect = tester.getRect(_tile(NavSection.search));
      expect(tileRect.height, greaterThanOrEqualTo(64));
      await tester.tapAt(tileRect.topLeft + Offset(8, tileRect.height / 2));
      await tester.pumpAndSettle();
      expect(state.hiddenNavSections, contains(NavSection.search));
      expect(tester.widget<Switch>(_switch(NavSection.search)).value, isFalse);
      expect(_row(NavSection.search), findsOneWidget);
      final Finder reset = find.byKey(
        const ValueKey<String>('nav-sections-reset'),
      );
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(state.navSectionOrder, NavSection.defaultOrder);
      expect(state.hiddenNavSections, contains(NavSection.search));
      await tester.ensureVisible(_switch(NavSection.search));
      await tester.pumpAndSettle();
      await tester.tap(_switch(NavSection.search));
      await tester.pumpAndSettle();
      expect(state.hiddenNavSections, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('large text and translated controls fit a narrow phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final AppState state = AppState();
    addTearDown(state.dispose);
    await tester.runAsync(
      () => AppLocalizations.delegate.load(const Locale('en')),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppleTheme(brightness: Brightness.dark),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: NavSectionsPage(state: state),
      ),
    );
    await tester.pumpAndSettle();
    final Finder down = _moveButton(NavSection.home, 'down');
    await tester.scrollUntilVisible(
      down,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Move down'), findsWidgets);
    expect(tester.getSize(down).height, greaterThanOrEqualTo(52));
    await tester.tap(down);
    await tester.pumpAndSettle();
    expect(state.navSectionOrder.indexOf(NavSection.home), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('editor disables only the last two visible switches', (
    WidgetTester tester,
  ) async {
    final AppState state = AppState();
    addTearDown(state.dispose);
    for (final NavSection section in <NavSection>[
      NavSection.home,
      NavSection.search,
      NavSection.library,
    ]) {
      await state.setNavSectionHidden(section, true);
    }
    await tester.pumpWidget(MaterialApp(home: NavSectionsPage(state: state)));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_switch(NavSection.likes)).onChanged, isNull);
    expect(
      tester.widget<Switch>(_switch(NavSection.settings)).onChanged,
      isNull,
    );
    expect(
      tester.widget<Switch>(_switch(NavSection.home)).onChanged,
      isNotNull,
    );
    await tester.tap(_switch(NavSection.home));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Switch>(_switch(NavSection.likes)).onChanged,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'bottom bar keeps the current page when reordered and falls back when hidden',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final AppState state = AppState();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppleTheme(),
          home: AppShell(state: state, autoCheckUpdates: false),
        ),
      );
      await tester.pumpAndSettle();
      NavigationBar bar() =>
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      List<String> labels() => bar().destinations
          .cast<NavigationDestination>()
          .map((NavigationDestination item) => item.label)
          .toList();
      await state.setNavSectionOrder(<NavSection>[
        NavSection.search,
        NavSection.home,
        NavSection.likes,
        NavSection.library,
        NavSection.settings,
      ]);
      await tester.pumpAndSettle();
      expect(labels(), <String>['搜索', '主页', '我喜欢', '音乐库', '设置']);
      expect(bar().selectedIndex, 1);
      await state.setNavSectionHidden(NavSection.home, true);
      await tester.pumpAndSettle();
      expect(labels(), <String>['搜索', '我喜欢', '音乐库', '设置']);
      expect(bar().selectedIndex, 0);
      expect(find.byType(AppSearchPage), findsOneWidget);
      expect(find.byType(AppHomePage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
