import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../state/home_modules.dart';
import '../widgets/apple_ui.dart';
import '../widgets/settings_detail.dart';
import '../widgets/spring_buttons.dart';

/// Lets the listener arrange the home page sections and hide the ones they do
/// not want. The choice is local: it never leaves the device.
class HomeModulesPage extends StatelessWidget {
  const HomeModulesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => HomeModulesView(state: state);
}

class HomeModulesView extends StatelessWidget {
  const HomeModulesView({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (BuildContext context, _) {
        final List<HomeModule> order = state.homeModuleOrder;
        return SettingsDetailScaffold(
          title: '首页模块',
          actions: <Widget>[
            SpringTextButton(
              key: const ValueKey<String>('home-modules-reset'),
              onPressed: () => unawaited(
                state.setHomeModuleOrder(HomeModule.defaultOrder),
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
                    child: TrText('拖动调整主页模块的顺序，关闭开关可隐藏对应模块。'),
                  ),
                  AppleGroupedCard(
                    child: order.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: TrText('没有可显示的模块'),
                          )
                        : ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: order.length,
                            onReorderItem: (int oldIndex, int newIndex) {
                              final List<HomeModule> next =
                                  List<HomeModule>.of(order);
                              final HomeModule module = next.removeAt(oldIndex);
                              next.insert(newIndex, module);
                              unawaited(state.setHomeModuleOrder(next));
                            },
                            itemBuilder: (BuildContext context, int index) {
                              final HomeModule module = order[index];
                              final bool hidden = state.hiddenHomeModules.contains(
                                module,
                              );
                              return AppleListTile(
                                key: ValueKey<String>('home-module-${module.id}'),
                                title: context.tr(module.titleKey),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Switch(
                                      value: !hidden,
                                      onChanged: (bool value) => unawaited(
                                        state.setHomeModuleHidden(module, !value),
                                      ),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Icon(
                                        Icons.drag_indicator_rounded,
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
