import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../state/nav_sections.dart';
import '../widgets/apple_ui.dart';
import '../widgets/settings_detail.dart';
import '../widgets/spring_buttons.dart';

/// Lets the listener arrange the bottom navigation bar and hide the
/// destinations they never open. The choice is local to the device.
class NavSectionsPage extends StatelessWidget {
  const NavSectionsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => NavSectionsView(state: state);
}

class NavSectionsView extends StatelessWidget {
  const NavSectionsView({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (BuildContext context, _) {
        final List<NavSection> order = state.navSectionOrder;
        return SettingsDetailScaffold(
          title: '导航栏',
          actions: <Widget>[
            SpringTextButton(
              key: const ValueKey<String>('nav-sections-reset'),
              onPressed: () => unawaited(
                state.setNavSectionOrder(NavSection.defaultOrder),
              ),
              child: const TrText('恢复默认顺序'),
            ),
          ],
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: TrText('拖动调整底部导航栏的顺序，关闭开关可隐藏对应入口。至少保留两个入口，隐藏的入口可随时重新开启。'),
                  ),
                  AppleGroupedCard(
                    child: order.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: TrText('没有可显示的入口'),
                          )
                        : ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: order.length,
                            onReorderItem: (int oldIndex, int newIndex) {
                              final List<NavSection> next =
                                  List<NavSection>.of(order);
                              final NavSection section = next.removeAt(
                                oldIndex,
                              );
                              next.insert(newIndex, section);
                              unawaited(state.setNavSectionOrder(next));
                            },
                            itemBuilder: (BuildContext context, int index) {
                              final NavSection section = order[index];
                              final bool hidden = state.hiddenNavSections
                                  .contains(section);
                              final bool canHide =
                                  state.visibleNavSections.length >
                                  NavSection.minimumVisibleCount;
                              return AppleListTile(
                                key: ValueKey<String>(
                                  'nav-section-${section.id}',
                                ),
                                leading: Icon(
                                  hidden ? section.icon : section.selectedIcon,
                                ),
                                title: context.tr(section.labelKey),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Switch(
                                      value: !hidden,
                                      onChanged: hidden || canHide
                                          ? (bool value) => unawaited(
                                              state.setNavSectionHidden(
                                                section,
                                                !value,
                                              ),
                                            )
                                          : null,
                                    ),
                                    Tooltip(
                                      message: context.tr('拖动调整顺序'),
                                      child: ReorderableDragStartListener(
                                        index: index,
                                        child: const SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: Icon(
                                            Icons.drag_indicator_rounded,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
