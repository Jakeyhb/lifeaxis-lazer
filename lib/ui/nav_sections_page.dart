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

  void _move(NavSection section, int offset) {
    final List<NavSection> next = List<NavSection>.of(state.navSectionOrder);
    final int index = next.indexOf(section);
    final int destination = index + offset;
    if (index < 0 || destination < 0 || destination >= next.length) return;
    next.removeAt(index);
    next.insert(destination, section);
    unawaited(state.setNavSectionOrder(next));
  }

  Widget _sectionControls(BuildContext context, NavSection section) {
    final int index = state.navSectionOrder.indexOf(section);
    final bool hidden = state.hiddenNavSections.contains(section);
    final bool canToggle =
        hidden ||
        state.visibleNavSections.length > NavSection.minimumVisibleCount;
    final ButtonStyle moveStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

    return Column(
      key: ValueKey<String>('nav-section-${section.id}'),
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: SwitchListTile(
            key: ValueKey<String>('nav-section-toggle-${section.id}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            secondary: Icon(hidden ? section.icon : section.selectedIcon),
            title: Text(context.tr(section.labelKey)),
            value: !hidden,
            onChanged: canToggle
                ? (bool value) =>
                      unawaited(state.setNavSectionHidden(section, !value))
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Tooltip(
                  message:
                      '${context.tr('上移')}：${context.tr(section.labelKey)}',
                  child: SpringOutlinedButton.icon(
                    key: ValueKey<String>('nav-section-up-${section.id}'),
                    style: moveStyle,
                    onPressed: index > 0 ? () => _move(section, -1) : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    label: const TrText('上移'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Tooltip(
                  message:
                      '${context.tr('下移')}：${context.tr(section.labelKey)}',
                  child: SpringOutlinedButton.icon(
                    key: ValueKey<String>('nav-section-down-${section.id}'),
                    style: moveStyle,
                    onPressed: index < state.navSectionOrder.length - 1
                        ? () => _move(section, 1)
                        : null,
                    icon: const Icon(Icons.arrow_downward_rounded),
                    label: const TrText('下移'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (BuildContext context, _) {
        final List<NavSection> order = state.navSectionOrder;
        return SettingsDetailScaffold(
          title: '导航栏',
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: TrText(
                      '点击“上移”或“下移”调整顺序，无需拖动。点击入口整行或开关可切换显示，至少保留两个入口。',
                    ),
                  ),
                  SpringOutlinedButton.icon(
                    key: const ValueKey<String>('nav-sections-reset'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: () => unawaited(
                      state.setNavSectionOrder(NavSection.defaultOrder),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const TrText('恢复默认顺序'),
                  ),
                  const SizedBox(height: 16),
                  AppleGroupedCard(
                    margin: EdgeInsets.zero,
                    child: order.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: TrText('没有可显示的入口'),
                          )
                        : Material(
                            color: Colors.transparent,
                            child: Column(
                              children: <Widget>[
                                for (final NavSection section
                                    in order) ...<Widget>[
                                  _sectionControls(context, section),
                                  if (section != order.last)
                                    const Divider(height: 1),
                                ],
                              ],
                            ),
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
