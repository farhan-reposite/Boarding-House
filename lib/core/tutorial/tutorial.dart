import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/rooms/room_form_screen.dart';
import '../../features/rooms/room_setup_wizard.dart';
import '../../features/tenants/tenant_form_screen.dart';
import '../../providers.dart';
import '../i18n/app_language.dart';
import '../theme.dart';
import 'tutorial_target.dart';

// ============================================================================
// First-run tutorial: a spotlight ("highlight") tour of
//   1. Quick setup      2. Adding a single room      3. Assigning a tenant
//
// How it works
// - Widgets the tour points at are wrapped in TutorialTarget(id: ...).
// - TutorialLayer sits above the Navigator (see main.dart), so it can
//   highlight things on any screen. It dims everything, cuts a hole around
//   the current target and shows an explanation card next to it.
// - On "interactive" steps the hole lets taps through, so the user can really
//   tap the button / type in the field. The tour moves on by itself when the
//   next screen appears. The card's button does the same thing for them.
// ============================================================================

/// Index of the step being shown, or null when no tour is running.
final tutorialStepProvider = StateProvider<int?>((ref) => null);

/// Starts (or restarts) the tour from the welcome card.
void startTutorial(WidgetRef ref) {
  appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
  ref.read(shellTabProvider.notifier).state = 0;
  ref.read(tutorialStepProvider.notifier).state = 0;
}

/// How a step moves on after the user acts on the highlighted widget.
enum _Auto {
  /// Only the card's button moves on.
  none,

  /// Moves on once the NEXT step's target is on screen (e.g. a tab or screen
  /// opened).
  nextReady,

  /// Moves on once this step's target has disappeared (the screen closed).
  closed,
}

class _Step {
  _Step({
    this.target,
    this.tab,
    this.section,
    required this.title,
    required this.body,
    this.interactive = false,
    this.auto = _Auto.none,
    this.nextLabel,
    this.onNext,
  });

  /// TutorialTarget id; null = a centered card with no spotlight.
  final String? target;

  /// The target only counts as visible while this tab is selected.
  final int? tab;

  /// English text keys (translated when shown).
  final String? section;
  final String title;
  final String body;

  /// Taps and typing reach the highlighted widget.
  final bool interactive;
  final _Auto auto;
  final String? nextLabel;

  /// What the card's button does for the user (open the tab/screen, close it).
  final void Function(WidgetRef ref)? onNext;
}

void _push(Widget page) {
  appNavigatorKey.currentState
      ?.push(MaterialPageRoute<void>(builder: (_) => page));
}

void _pop() {
  appNavigatorKey.currentState?.maybePop();
}

final List<_Step> _steps = [
  // ---- welcome
  _Step(
    title: 'Welcome to Kost Manager',
    body:
        'Let\'s take a quick tour. You will set up your building, add a single room and move in a tenant. It takes about two minutes.',
    nextLabel: 'Start',
  ),

  // ---- 1. quick setup
  _Step(
    target: 'nav.rooms',
    section: 'Quick setup',
    title: 'Open the Rooms tab',
    body: 'Everything about your rooms lives here. Tap Rooms to continue.',
    interactive: true,
    auto: _Auto.nextReady,
    onNext: (ref) => ref.read(shellTabProvider.notifier).state = 1,
  ),
  _Step(
    target: 'rooms.quickSetup',
    tab: 1,
    section: 'Quick setup',
    title: 'Create many rooms at once',
    body:
        'Got a whole building? This wand creates all your rooms in one go, with names and prices. Tap it to open Quick setup.',
    interactive: true,
    auto: _Auto.nextReady,
    onNext: (ref) => _push(const RoomSetupWizard()),
  ),
  _Step(
    target: 'wizard.layout',
    section: 'Quick setup',
    title: 'Describe your building',
    body:
        'Enter how many floors you have and how many rooms are on each floor. The rooms are named for you, like 101, 102, 201.',
    interactive: true,
  ),
  _Step(
    target: 'wizard.price',
    section: 'Quick setup',
    title: 'Set the price',
    body:
        'Enter the standard monthly price. You can also add an extra amount for every higher floor.',
    interactive: true,
  ),
  _Step(
    target: 'wizard.create',
    section: 'Quick setup',
    title: 'Create the rooms',
    body:
        'A preview of every room appears on this screen. When it looks right, tap Create. We will skip it for now, you can run Quick setup any time.',
    interactive: true,
    auto: _Auto.closed,
    nextLabel: 'Skip for now',
    onNext: (ref) => _pop(),
  ),

  // ---- 2. a single room
  _Step(
    target: 'rooms.add',
    tab: 1,
    section: 'Add a single room',
    title: 'Add one room',
    body: 'Only need one room, or adding one later? Tap Add room.',
    interactive: true,
    auto: _Auto.nextReady,
    onNext: (ref) => _push(const RoomFormScreen()),
  ),
  _Step(
    target: 'roomForm.name',
    section: 'Add a single room',
    title: 'Name the room',
    body: 'Type the room name or number, for example A1 or 101.',
    interactive: true,
  ),
  _Step(
    target: 'roomForm.price',
    section: 'Add a single room',
    title: 'Set the monthly price',
    body:
        'This is what a tenant pays each month. It is filled in automatically when you add a tenant to this room.',
    interactive: true,
  ),
  _Step(
    target: 'roomForm.save',
    section: 'Add a single room',
    title: 'Save the room',
    body:
        'Pick the facilities above if you like, then tap Add room to save it. Photos can be added afterwards from the room details.',
    interactive: true,
    auto: _Auto.closed,
    nextLabel: 'Skip for now',
    onNext: (ref) => _pop(),
  ),

  // ---- 3. assign a tenant
  _Step(
    target: 'nav.tenants',
    section: 'Assign a tenant',
    title: 'Open the Tenants tab',
    body: 'Now let\'s move someone in. Tap Tenants.',
    interactive: true,
    auto: _Auto.nextReady,
    onNext: (ref) => ref.read(shellTabProvider.notifier).state = 2,
  ),
  _Step(
    target: 'tenants.add',
    tab: 2,
    section: 'Assign a tenant',
    title: 'Add a tenant',
    body:
        'Tap Add tenant to check someone in. You can also do this from a room\'s details page.',
    interactive: true,
    auto: _Auto.nextReady,
    onNext: (ref) => _push(const TenantFormScreen()),
  ),
  _Step(
    target: 'tenantForm.rooms',
    section: 'Assign a tenant',
    title: 'Choose the room',
    body:
        'Pick the room this tenant will live in. Only available or reserved rooms are listed. If there are none, add a room first.',
    interactive: true,
  ),
  _Step(
    target: 'tenantForm.contact',
    section: 'Assign a tenant',
    title: 'Who is moving in?',
    body:
        'Enter the name and the WhatsApp number. The number is used to send invoices and payment reminders.',
    interactive: true,
  ),
  _Step(
    target: 'tenantForm.rent',
    section: 'Assign a tenant',
    title: 'Rent and deposit',
    body:
        'The rent is filled in from the room price. Change it if this tenant pays a different amount, and add the deposit if you received one.',
    interactive: true,
  ),
  _Step(
    target: 'tenantForm.save',
    section: 'Assign a tenant',
    title: 'Check the tenant in',
    body:
        'Tap Add tenant to save. The room becomes occupied and the first invoice is created for you.',
    interactive: true,
    auto: _Auto.closed,
    nextLabel: 'Skip for now',
    onNext: (ref) => _pop(),
  ),

  // ---- done
  _Step(
    title: 'You are all set!',
    body:
        'That is the basics: rooms first, then tenants, then payments. You can replay this tour any time from Settings.',
    nextLabel: 'Done',
  ),
];

// ============================================================================

/// The overlay. Put it above the Navigator (MaterialApp.builder).
class TutorialLayer extends ConsumerStatefulWidget {
  const TutorialLayer({super.key});

  @override
  ConsumerState<TutorialLayer> createState() => _TutorialLayerState();
}

class _TutorialLayerState extends ConsumerState<TutorialLayer>
    with SingleTickerProviderStateMixin {
  static const _holePadding = 6.0;
  static const _cardWidth = 360.0;
  static const _fallbackAfter = Duration(milliseconds: 1400);

  late final Ticker _ticker;
  Duration _now = Duration.zero;

  int? _trackedStep;
  Duration _stepStarted = Duration.zero;
  Rect? _hole; // the (smoothly moving) rectangle being drawn
  bool _targetReady = false;
  bool _scrolled = false;
  bool _wasMounted = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- measuring

  /// The target's rectangle on screen, or null when it isn't visible right
  /// now (not built, on another tab, or covered by another screen).
  Rect? _rectFor(_Step step) {
    final id = step.target;
    if (id == null) return null;
    if (step.tab != null && ref.read(shellTabProvider) != step.tab) {
      return null;
    }
    final targetContext = TutorialKeys.of(id).currentContext;
    if (targetContext == null || !targetContext.mounted) return null;
    final box = targetContext.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.size.isEmpty) return null;
    final route = ModalRoute.of(targetContext);
    if (route != null && !route.isCurrent) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  bool _isMounted(_Step step) {
    final id = step.target;
    return id != null && TutorialKeys.of(id).currentContext != null;
  }

  // -------------------------------------------------------------------- tick

  void _onTick(Duration elapsed) {
    _now = elapsed;
    final index = ref.read(tutorialStepProvider);
    if (index == null || index >= _steps.length) {
      _ticker.stop();
      return;
    }
    if (index != _trackedStep) {
      _trackedStep = index;
      _stepStarted = elapsed;
      _scrolled = false;
      _wasMounted = false;
    }
    final step = _steps[index];
    final rect = _rectFor(step);

    _targetReady = rect != null;
    if (rect != null) {
      final current = _hole;
      if (current == null) {
        _hole = rect;
      } else {
        final next = Rect.lerp(current, rect, 0.3)!;
        _hole = ((next.topLeft - rect.topLeft).distance < 0.5 &&
                (next.bottomRight - rect.bottomRight).distance < 0.5)
            ? rect
            : next;
      }
      _scrollIntoView(step, rect);
    }

    // Move on by itself after the user acted on the highlighted widget.
    var advance = false;
    switch (step.auto) {
      case _Auto.none:
        break;
      case _Auto.nextReady:
        if (index + 1 < _steps.length && _rectFor(_steps[index + 1]) != null) {
          advance = true;
        }
      case _Auto.closed:
        if (_isMounted(step)) {
          _wasMounted = true;
        } else if (_wasMounted) {
          advance = true;
        }
    }
    if (advance) {
      _go(index + 1);
      return;
    }
    if (mounted) setState(() {});
  }

  void _scrollIntoView(_Step step, Rect rect) {
    if (_scrolled) return;
    final media = MediaQuery.of(context);
    final bottomLimit = media.size.height - media.viewInsets.bottom - 8;
    final topLimit = media.padding.top + 8;
    if (rect.top >= topLimit && rect.bottom <= bottomLimit) return;
    _scrolled = true;
    final targetContext = TutorialKeys.of(step.target!).currentContext;
    if (targetContext != null && targetContext.mounted) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.3,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // ----------------------------------------------------------------- actions

  void _go(int index) {
    if (index >= _steps.length) {
      _finish();
      return;
    }
    ref.read(tutorialStepProvider.notifier).state = index;
  }

  void _finish() {
    ref.read(tutorialStepProvider.notifier).state = null;
    _hole = null;
    _trackedStep = null;
    unawaited(ref.read(repoProvider).setTutorialDone(true));
  }

  void _next() {
    final index = ref.read(tutorialStepProvider);
    if (index == null) return;
    final step = _steps[index];
    step.onNext?.call(ref);
    if (index + 1 >= _steps.length) {
      _finish();
      return;
    }
    if (step.auto == _Auto.none) {
      _go(index + 1);
    } else {
      // The step moves on by itself once the new screen is up. This is only a
      // safety net so the tour can never get stuck.
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && ref.read(tutorialStepProvider) == index) _go(index + 1);
      });
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tutorialStepProvider);
    if (index == null || index >= _steps.length) {
      if (_ticker.isActive) _ticker.stop();
      _hole = null;
      _trackedStep = null;
      return const SizedBox.shrink();
    }
    if (!_ticker.isActive) _ticker.start();

    final step = _steps[index];
    final screen = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);
    // `fresh`: the step just changed and the ticker hasn't measured its
    // target yet (the old spotlight is kept so it can glide to the new one).
    final fresh = step.target != null && index != _trackedStep;
    final ready = !fresh && _targetReady;
    final waitedTooLong =
        step.target != null && !fresh && !_targetReady &&
            (_now - _stepStarted) > _fallbackAfter;

    // While the next screen is still opening, just dim; the card appears as
    // soon as the target is on screen. If it never shows, fall back to a
    // centered card so the tour can still continue.
    final showCard = step.target == null || ready || waitedTooLong;
    final hole = (step.target != null && _hole != null && (ready || fresh))
        ? _hole!.inflate(_holePadding)
        : null;

    final pulse = 0.5 - 0.5 * math.cos(2 * math.pi * ((_now.inMilliseconds % 1500) / 1500));

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: CustomPaint(
            painter: _ScrimPainter(
              hole: hole,
              pulse: pulse,
              scrim: Colors.black.withValues(alpha: 0.10),
              accent: kGold,
            ),
          ),
        ),
        ..._barriers(hole, step.interactive, screen),
        if (showCard) _buildCard(context, step, index, hole, screen, insets),
      ],
    );
  }

  /// Widgets that swallow taps everywhere except inside the hole (and, on
  /// non-interactive steps, inside the hole too).
  List<Widget> _barriers(Rect? hole, bool interactive, Size screen) {
    Widget block(Rect r) => Positioned.fromRect(
          rect: r,
          child: const Listener(
            behavior: HitTestBehavior.opaque,
            child: SizedBox.expand(),
          ),
        );
    if (hole == null || !interactive) {
      return [block(Offset.zero & screen)];
    }
    final h = Rect.fromLTRB(
      hole.left.clamp(0.0, screen.width).toDouble(),
      hole.top.clamp(0.0, screen.height).toDouble(),
      hole.right.clamp(0.0, screen.width).toDouble(),
      hole.bottom.clamp(0.0, screen.height).toDouble(),
    );
    return [
      block(Rect.fromLTRB(0, 0, screen.width, h.top)),
      block(Rect.fromLTRB(0, h.bottom, screen.width, screen.height)),
      block(Rect.fromLTRB(0, h.top, h.left, h.bottom)),
      block(Rect.fromLTRB(h.right, h.top, screen.width, h.bottom)),
    ];
  }

  Widget _buildCard(BuildContext context, _Step step, int index, Rect? hole,
      Size screen, EdgeInsets insets) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final guided = step.section != null;
    final isLast = index == _steps.length - 1;
    final width = math.min(_cardWidth, screen.width - 32);

    final card = Material(
      color: scheme.surface,
      elevation: 10,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (guided)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(step.section!).toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    tr('Step {i} of {n}',
                        {'i': index, 'n': _steps.length - 2}),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            if (guided) const SizedBox(height: 8),
            Text(tr(step.title),
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(tr(step.body),
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
            const SizedBox(height: 10),
            Row(
              children: [
                if (!isLast)
                  TextButton(
                    onPressed: _finish,
                    child: Text(tr('Skip tutorial')),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _next,
                  child: Text(tr(step.nextLabel ?? 'Next')),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // No spotlight: center the card.
    if (hole == null) {
      return Positioned.fill(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(width: width, child: card),
            ),
          ),
        ),
      );
    }

    // Spotlight: put the card on whichever side has more room.
    final usableHeight = screen.height - insets.bottom;
    final below = usableHeight - hole.bottom;
    final above = hole.top;
    final left = (hole.center.dx - width / 2)
        .clamp(16.0, math.max(16.0, screen.width - width - 16))
        .toDouble();
    final topSafe = MediaQuery.paddingOf(context).top + 8;

    if (below >= 230 || below >= above) {
      final top = math.min(hole.bottom + 12, math.max(topSafe, usableHeight - 220));
      return Positioned(left: left, top: top, width: width, child: card);
    }
    final bottom = math.max(8.0, screen.height - hole.top + 12);
    return Positioned(left: left, bottom: bottom, width: width, child: card);
  }
}

// ============================================================================

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({
    required this.hole,
    required this.pulse,
    required this.scrim,
    required this.accent,
  });

  final Rect? hole;
  final double pulse; // 0..1, drives the glow
  final Color scrim;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final h = hole;
    if (h == null) {
      canvas.drawPath(full, Paint()..color = scrim);
      return;
    }
    final rrect = RRect.fromRectAndRadius(h, const Radius.circular(14));
    final dimmed =
        Path.combine(PathOperation.difference, full, Path()..addRRect(rrect));
    canvas.drawPath(dimmed, Paint()..color = scrim);

    // Soft pulsing halo, then a crisp ring.
    canvas.drawRRect(
      rrect.inflate(2 + 5 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = accent.withValues(alpha: 0.55 - 0.4 * pulse),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => true;
}
