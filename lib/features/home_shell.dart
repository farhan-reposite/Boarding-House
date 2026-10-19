import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n/app_language.dart';
import '../core/icons.dart';
import '../core/tutorial/tutorial.dart';
import '../core/tutorial/tutorial_target.dart';
import '../core/widgets/kost_logo.dart';
import '../providers.dart';
import 'dashboard/dashboard_screen.dart';
import 'payments/payments_screen.dart';
import 'rooms/rooms_screen.dart';
import 'settings/settings_screen.dart';
import 'tenants/tenants_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, {this.tutorialId});

  /// English text; translated when shown.
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Lets the first-run tutorial point at this tab.
  final String? tutorialId;
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _dests = <_Dest>[
    _Dest('Home', Ph.house, Ph.houseFill),
    _Dest('Rooms', Ph.doorOpen, Ph.doorOpenFill, tutorialId: 'nav.rooms'),
    _Dest('Tenants', Ph.users, Ph.usersFill, tutorialId: 'nav.tenants'),
    _Dest('Payments', Ph.receipt, Ph.receiptFill),
    _Dest('Settings', Ph.gearSix, Ph.gearSixFill),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartTutorial());
  }

  /// First launch: walk the owner through setting up their building.
  Future<void> _maybeStartTutorial() async {
    final done = await ref.read(repoProvider).getTutorialDone();
    if (done || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    startTutorial(ref);
  }

  void _go(int i) => ref.read(shellTabProvider.notifier).state = i;

  Widget _tagged(_Dest d, Widget child) =>
      d.tutorialId == null
          ? child
          : TutorialTarget(id: d.tutorialId!, child: child);

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    final language = ref.watch(languageProvider);

    final pages = <Widget>[
      DashboardScreen(onOpenTab: _go),
      const RoomsScreen(),
      const TenantsScreen(),
      const PaymentsScreen(),
      const SettingsScreen(),
    ];
    // Keyed by language so every tab rebuilds (and re-translates) the moment
    // the language is changed in Settings. The selected tab is kept.
    final body = IndexedStack(
      key: ValueKey(language),
      index: index,
      children: pages,
    );

    // Wide windows (Windows desktop, tablets): sidebar with "icon  text" rows.
    final wide = MediaQuery.sizeOf(context).width >= 800;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _SideNav(
              selectedIndex: index,
              onSelected: _go,
              items: [
                for (var i = 0; i < _dests.length; i++)
                  _SideNavItem(
                    label: tr(_dests[i].label),
                    icon: _dests[i].icon,
                    selectedIcon: _dests[i].selectedIcon,
                    tutorialId: _dests[i].tutorialId,
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _go,
        destinations: [
          for (final d in _dests)
            _tagged(
              d,
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: tr(d.label),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- sidebar

class _SideNavItem {
  const _SideNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.tutorialId,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? tutorialId;
}

/// Desktop sidebar: each entry is a single row, the icon followed by its text.
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<_SideNavItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 232,
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
              child: Row(
                children: [
                  const KostLogo(size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Kost Manager',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: _row(context, i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    final item = items[i];
    final selected = i == selectedIndex;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    final row = Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onSelected(i),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(selected ? item.selectedIcon : item.icon,
                    size: 22, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.onSurface : fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return item.tutorialId == null
        ? row
        : TutorialTarget(id: item.tutorialId!, child: row);
  }
}
