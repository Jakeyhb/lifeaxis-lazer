import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lazer_nextgen/state/app_state.dart';
import 'package:lazer_nextgen/state/nav_sections.dart';
import 'package:lazer_nextgen/theme/apple_design.dart';
import 'package:lazer_nextgen/ui/nav_sections_page.dart';
import 'package:lazer_nextgen/ui/pages.dart';
import 'package:lazer_nextgen/ui/shell.dart';

Finder _row(NavSection section) =>
    find.byKey(ValueKey<String>('nav-section-${section.id}'));

Finder _switch(NavSection section) =>
    find.descendant(of: _row(section), matching: find.byType(Switch));

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
      final Finder handle = find.descendant(
        of: _row(NavSection.home),
        matching: find.byType(ReorderableDragStartListener),
      );
      final double distance =
          tester.getCenter(_row(NavSection.library)).dy -
          tester.getCenter(_row(NavSection.home)).dy;
      await tester.drag(handle, Offset(0, distance));
      await tester.pumpAndSettle();
      expect(state.navSectionOrder, <NavSection>[
        NavSection.search,
        NavSection.home,
        NavSection.library,
        NavSection.likes,
        NavSection.settings,
      ]);
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(1, 4);
      await tester.pumpAndSettle();
      expect(state.navSectionOrder.last, NavSection.home);
      await tester.tap(_switch(NavSection.search));
      await tester.pumpAndSettle();
      expect(state.hiddenNavSections, contains(NavSection.search));
      expect(tester.widget<Switch>(_switch(NavSection.search)).value, isFalse);
      expect(_row(NavSection.search), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('nav-sections-reset')),
      );
      await tester.pumpAndSettle();
      expect(state.navSectionOrder, NavSection.defaultOrder);
      expect(state.hiddenNavSections, contains(NavSection.search));
      await tester.tap(_switch(NavSection.search));
      await tester.pumpAndSettle();
      expect(state.hiddenNavSections, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

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
