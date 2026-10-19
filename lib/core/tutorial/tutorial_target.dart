import 'package:flutter/widgets.dart';

/// The app's single Navigator key. The first-run tutorial uses it to open and
/// close screens on the user's behalf (see tutorial.dart).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// One GlobalKey per highlightable widget, looked up by a string id.
abstract final class TutorialKeys {
  static final Map<String, GlobalKey> _keys = {};

  static GlobalKey of(String id) =>
      _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tutorial:$id'));
}

/// Wrap a widget with this so the tutorial can find it and put a spotlight on
/// it. It has no visual or layout effect of its own.
///
/// Each [id] must be used by only one widget at a time.
class TutorialTarget extends StatelessWidget {
  const TutorialTarget({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: TutorialKeys.of(id), child: child);
}
