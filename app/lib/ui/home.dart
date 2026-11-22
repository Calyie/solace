// The app shell (Today, Talk, Practices, Progress, You) and the Today tab.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/home_link.dart' show staysOnFor;
import '../core/dates.dart';
import '../core/questionnaires.dart';
import 'app_lock.dart' show LockNeedsPasscodeNotice;
import 'chat.dart';
import 'check_in.dart';
import 'crisis.dart';
import 'desktop.dart';
import 'emotion_sheet.dart';
import 'help_me_start.dart';
import 'model_files.dart';
import 'plan_sheet.dart';
import 'plan_today.dart';
import 'practices.dart';
import 'premium.dart';
import 'storage.dart';
import 'presence.dart';
import 'programmes.dart';
import 'progress.dart';
import 'questionnaire.dart';
import 'settings.dart';
import 'theme.dart';
import 'vision_board.dart';
import 'you.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [TodayTab(onTab: (i) => setState(() => _tab = i)), const TalkTab(), const PracticesTab(),
        const ProgressTab(), const YouTab()];
    const tabs = [(Icons.wb_sunny_outlined, Icons.wb_sunny, 'Today'), (Icons.chat_bubble_outline, Icons.chat_bubble, 'Talk'),
        (Icons.self_improvement, Icons.self_improvement, 'Practices'), (Icons.insights_outlined, Icons.insights, 'Progress'),
        (Icons.person_outline, Icons.person, 'You')];
    void go(int i) {
      if (i != _tab) feelChoice();
      setState(() => _tab = i);
    }

    // the Mac and Linux menus and shortcuts can ask for a tab (ui/desktop.dart)
    return DesktopTabSwitch(onTab: go, child: LayoutBuilder(builder: (context, size) {
      final window = windowSize(size.maxWidth);
      // the tabs fade into each other, calmly; on a large screen every tab takes the same width (one reading column,
      // two panes, or three on a very large window), centred, so a tab's title never moves when the tab changes
      // (ui/premium.dart tabWidth, Breakpoints and Widths)
      final body = LayoutBuilder(builder: (context, box) => AnimatedSwitcher(duration: Calm.normal,
          switchInCurve: Calm.curve, switchOutCurve: Calm.curve, child: KeyedSubtree(key: ValueKey(_tab),
          child: Readable(maxWidth: tabWidth(box.maxWidth), child: pages[_tab]))));
      final t = Theme.of(context).textTheme;
      final extended = window == WindowSize.large && size.maxHeight >= 560;
      // the space beside the rail, and the heart's place: over the right edge of the tab's cards, not in a large
      // window's far corner (its circle is 40 wide in a 48 target, so 16 from the edge lines it up with them)
      final beside = size.maxWidth - (window == WindowSize.compact ? 0 : (extended ? 220 : 80) + 1);
      final margin = math.max(0.0, (beside - math.min(beside, tabWidth(beside))) / 2) + tabPadding.right - 4;
      return Scaffold(
        // the approved design: no title bar text; support is one tap away on every tab, top right. On a phone,
        // Settings is beside it on every tab (owner, 2026-11-16: "isn't hard to find things especially settings");
        // a tablet or a computer has it in the rail. Support stays first in the focus order (report P1 18)
        appBar: AppBar(toolbarHeight: 52, actions: [
          FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (window == WindowSize.compact)
              const FocusTraversalOrder(order: NumericFocusOrder(2), child: SettingsButton()),
            const FocusTraversalOrder(order: NumericFocusOrder(1), child: SupportButton()),
          ])),
          SizedBox(width: margin),
        ]),
        // a phone: the tab bar at the bottom; a tablet or the Mac: a rail at the side, with names beside the icons
        // when the window is large
        body: window == WindowSize.compact
            ? body
            : SafeArea(top: false, bottom: false, right: false, child: Row(children: [
                // a phone on its side with the keyboard up leaves the rail too little height: it scrolls (cycle 2
                // flows follow-up: it overflowed by 83 px)
                LayoutBuilder(builder: (context, rail) => SingleChildScrollView(child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: rail.maxHeight), child: IntrinsicHeight(child:
                MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: NavigationRail(
                    selectedIndex: _tab, onDestinationSelected: go,
                    extended: extended, minExtendedWidth: 220,
                    // a phone on its side has no height for five labelled places: icons only, names on long-press
                    labelType: window == WindowSize.large || size.maxHeight < 560
                        ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                    groupAlignment: -0.85,
                    leading: window == WindowSize.large
                        ? Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 20), child: SizedBox(width: 188,
                            child: Text(appName, style: t.headlineSmall)))
                        : null,
                    // Settings, with the model, voice and safety files near its top, one click from every tab on a
                    // tablet or a computer (owner, 2026-11-16: never through the profile)
                    trailing: _RailSettings(extended: extended),
                    destinations: [
                  for (final (icon, selected, label) in tabs)
                    NavigationRailDestination(icon: Tooltip(message: label, child: Icon(icon, key: Key('tab_$label'))),
                        selectedIcon: Icon(selected), label: Text(label)),
                ])))))),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ])),
        bottomNavigationBar: window != WindowSize.compact ? null : MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: go,
            destinations: [
              for (final (icon, selected, label) in tabs)
                NavigationDestination(icon: Icon(icon, key: Key('tab_$label')), selectedIcon: Icon(selected), label: label),
            ],
          ),
        ),
      );
    }));
  }
}

/// Opens Settings: on a computer through the same command as the menu and the shortcut (it waits while data is being
/// changed), elsewhere straight away.
void openSettings(BuildContext context) {
  final desktop = DesktopScope.maybeOf(context);
  if (desktop != null) {
    desktop.run('settings');
  } else {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }
}

/// Settings in a phone's top bar, beside Support, on every tab.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(key: const Key('bar_settings'), tooltip: 'Settings',
      onPressed: () => openSettings(context), icon: const Icon(Icons.settings_outlined));
}

/// Settings in the navigation rail (a tablet or a computer): under the tabs, with its name when the rail shows names.
class _RailSettings extends StatelessWidget {
  const _RailSettings({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    void open() => openSettings(context);

    const icon = Icon(Icons.settings_outlined);
    return Padding(padding: const EdgeInsets.only(top: Space.l), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 40, child: Divider()),
      const SizedBox(height: Space.s),
      if (extended)
        SizedBox(width: 196, child: TextButton.icon(key: const Key('rail_settings'), onPressed: open, icon: icon,
            style: TextButton.styleFrom(alignment: AlignmentDirectional.centerStart,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
            label: const Text('Settings')))
      else
        IconButton(key: const Key('rail_settings'), tooltip: 'Open Settings', onPressed: open, icon: icon),
    ]));
  }
}

// Every session but the first starts with the check-in (B11), as in training (pipeline/series.py: v4, all but intake)
void openSession(BuildContext context, String kind, {String practiceName = ''}) => Navigator.push(context,
    MaterialPageRoute(builder: (_) => kind == 'intake'
        ? ChatScreen(kind: kind, practiceName: practiceName)
        : CheckInScreen(kind: kind, practiceName: practiceName)));

class TodayTab extends StatelessWidget {
  const TodayTab({super.key, required this.onTab});
  final void Function(int) onTab;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = state.data;
    final now = state.clock();
    final t = Theme.of(context).textTheme;
    final greeting = now.hour < 12 ? 'Good morning' : now.hour < 18 ? 'Good afternoon' : 'Good evening';
    final kind = state.todaysKind();
    final todayMood = d.moods[isoDate(now)];
    final lastPhq = d.scores.where((s) => s['name'] == 'PHQ-9').map((s) => DateTime.parse(s['date'] as String))
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final checkDue = lastPhq == null || now.difference(lastPhq).inDays >= 14;
    const pad = tabPadding;
    return LayoutBuilder(builder: (context, box) {
    final columns = Panes.count(box.maxWidth - pad.horizontal); // two or three columns beside the rail
    // on a very large window the notices span two of the three columns, so their words keep a reading width
    final inner = box.maxWidth - pad.horizontal;
    Widget notice(Widget w) => columns < 3 ? w : Align(alignment: AlignmentDirectional.centerStart,
        child: SizedBox(width: (inner - 2 * Space.xl) / 3 * 2 + Space.xl, child: w));
    final header = <Widget>[
      TabTitle(greeting, overline: dayLabel(now)),
      notice(const SpaceNote()), // only when Solace's space is nearly full or full (ui/storage.dart)
      notice(const LockNeedsPasscodeNotice()), // only while the lock is off until a passcode is chosen (9A-09)
      notice(const ModelFilesCard()), // only while no trained model is in place (ui/model_files.dart)
    ];
    final primary = <Widget>[
      Card(child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('How are you right now?', style: t.titleMedium)),
          AnimatedOpacity(opacity: todayMood == null ? 0 : 1, duration: Calm.normal,
              child: Text('Saved for today', style: t.bodySmall)),
        ]),
        const SizedBox(height: Space.s),
        MoodScale(value: todayMood, onChanged: state.saveMood),
        const NameFeelingLink(), // the optional named-emotion check-in (ui/emotion_sheet.dart)
      ]))),
      const SizedBox(height: 12),
      if (now.hour < 12 && state.library.any((p) => p.id == 'morning-lift')) ...[
        Card(child: ListTile(leading: const Icon(Icons.wb_twilight), title: const Text('Morning lift'),
            subtitle: const Text('A few minutes to start the day well. Just listen.'),
            trailing: const Icon(Icons.play_circle_outline),
            onTap: () => openPractice(context, state.library.firstWhere((p) => p.id == 'morning-lift')))),
        const SizedBox(height: 12),
      ],
      // in the evening near the top on a phone; on a computer beside today's session, which stays in view
      if (now.hour >= 17 && columns == 1) const EveningDebrief(),
      if (!d.settings.therapistChosen) ...[
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Choose how Solace looks and sounds', style: t.titleMedium),
          const SizedBox(height: 4),
          const Text('Pick the face and voice that feel right. You can change them later in Settings.'),
          const SizedBox(height: 12),
          const PresencePicker(),
          const SizedBox(height: 12),
          FilledButton(onPressed: () async {
            d.settings.therapistChosen = true;
            await state.save();
          }, child: const Text('Done')),
        ]))),
        const SizedBox(height: 8),
      ],
      _SessionCard(kind: kind),
    ];
    // the plan: under today's session, or a column of its own on a very large window
    final plan = <Widget>[
      const SizedBox(height: 20),
      const PlanCard(), // where the two of them are in the plan, once the first session has made one
      const PlanTodayCard(), // the day's steps and habits, never miss twice, what the app noticed (B3)
      const ParkedThoughtsCard(),
      const EveningShutdownCard(), // from 17:00, once a day: tomorrow's first step
    ];
    final secondary = <Widget>[
      const SizedBox(height: 12), // left out at the top of a column beside the other (ui/premium.dart TwoPanes)
      const MorningCard(),
      const VisionMorningCard(), // mornings: one picture from the vision board with its plan
      if (now.hour < 17 || columns > 1) const EveningDebrief(),
      if (d.homeworkDue.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: Space.m),
            Expanded(child: Text('Your next step', style: t.titleSmall)),
          ]),
          const SizedBox(height: Space.s),
          Text(d.homeworkDue),
          const SizedBox(height: Space.s),
          TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => HelpMeStartScreen(task: d.homeworkDue))), icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Help me start')),
        ]))),
      ],
      if (d.suggestions.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(child: ListTile(leading: const Icon(Icons.lightbulb_outline),
            title: Text('${d.suggestions.length} thing${d.suggestions.length == 1 ? '' : 's'} Solace noticed about you'),
            subtitle: const Text('Values and goals waiting for your yes or no'),
            trailing: const Icon(Icons.chevron_right), onTap: () => onTab(4))),
      ],
      if (checkDue && d.sessions.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(child: ListTile(leading: const Icon(Icons.checklist), title: const Text('Two-minute check-up'),
            subtitle: const Text('Mood and anxiety questions, to see your progress'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestionnaireFlow(
                list: [phq9, gad7]))))),
      ],
      const SectionHeader('Quick practices'),
      // a phone: one row to swipe; a wide screen: two to a row, filling their column
      LayoutBuilder(builder: (context, box) {
        final cards = [
          for (final id in ['cyclic-sighing', 'compassionate-companion', 'savouring', 'grounding-54321'])
            if (state.library.any((p) => p.id == id)) QuickPracticeCard(practice: state.library.firstWhere((p) => p.id == id)),
        ];
        final height = 72 + 72 * MediaQuery.textScalerOf(context).scale(14) / 14; // grows with the text size
        final half = (box.maxWidth - Space.s) / 2;
        return columns > 1
            ? Wrap(spacing: Space.s, runSpacing: Space.s,
                children: [for (final c in cards) SizedBox(width: half, height: height, child: c)])
            : SizedBox(height: height, child: ListView.separated(scrollDirection: Axis.horizontal,
                itemCount: cards.length, separatorBuilder: (_, _) => const SizedBox(width: Space.s),
                itemBuilder: (_, i) => cards[i]));
      }),
    ];
    // a phone: one column; a computer: today beside the rest; a very large window: today, the plan, and the rest
    return ListView(padding: pad, children: [...header,
        Panes(columns: [primary, plan, secondary], twoFlex: const (6, 5))]);
    });
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.kind});
  final String kind;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final about = {
      // owner, 2026-11-19: the first session builds the plan, later ones work through it, and the person decides how
      // long a session lasts: no lengths are promised
      'intake': 'Get to know each other and build your plan together. Take as long as you like.',
      'daily_checkin': "How you are, and today's part of your plan. As short or as long as you like.",
      'weekly_session': 'Look back at your week and do the next piece of your plan together. Take as long as you like.',
    }[kind]!;
    // the approved design's therapist card: her portrait, her words in the serif voice, one white pill to begin
    return Container(
      decoration: ShapeDecoration(gradient: huesOf(context).therapist, shape: smoothShape(Radii.large)),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const PresenceAvatar(radius: 15, onDark: true),
          const SizedBox(width: 10),
          Expanded(child: Text(kindTitles[kind]!, style: t.titleMedium?.copyWith(color: Colors.white))),
        ]),
        const SizedBox(height: 14),
        Text(about, style: voiceStyle(context, size: 23, color: Colors.white)),
        const SizedBox(height: 18),
        // a white pill with the palette's deep ink, in light and dark (in dark it took the scheme's light ink: 1.3 to 1)
        FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: huesOf(context).onPill),
            onPressed: () => openSession(context, kind), icon: const Icon(Icons.play_arrow), label: const Text('Start')),
      ]),
    );
  }
}

class TalkTab extends StatelessWidget {
  const TalkTab({super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = AppScope.of(context).data;
    final last = d.sessions.isEmpty ? null : d.sessions.last;
    Widget option(String kind, String sub, IconData icon) => Card(child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
        leading: IconDisc(icon), title: Text(kindTitles[kind]!), subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right), onTap: () => openSession(context, kind)));
    // a phone: one column; a computer: Solace's card beside the ways to start; a very large window: the trauma work
    // in a third column (ui/premium.dart Panes)
    return ListView(padding: tabPadding, children: [
      const TabTitle('Talk'),
      Panes(pairFirst: false, columns: [[
      // the therapist, as on Today: her portrait, when you last talked, and her words in her voice
      Container(
        padding: const EdgeInsets.all(Space.l + 4),
        decoration: ShapeDecoration(gradient: huesOf(context).therapist, shape: smoothShape(Radii.large),
            shadows: softShadow(context)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const PresenceAvatar(radius: 26, onDark: true),
            const SizedBox(width: Space.m + 2),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(appName, style: t.titleMedium?.copyWith(color: Colors.white))),
                const SizedBox(width: 8),
                const AiTag(onDark: true),
              ]),
              Text(last == null ? 'Ready when you are' : 'Last time: ${dayLabel(DateTime.parse(last.date))}',
                  style: t.bodySmall?.copyWith(color: Colors.white70)),
            ])),
          ]),
          const SizedBox(height: Space.l),
          Text('Type or speak, whichever you prefer. Everything stays on ${staysOnFor(AppScope.of(context).data.settings.homeServer)}.',
              style: voiceStyle(context, size: 22, color: Colors.white)),
        ]),
      ),
      ], [
      const SectionHeader('Start a session'),
      option('daily_checkin', 'A short check-in, any day', Icons.wb_twilight),
      option('weekly_session', 'A longer session to do deeper work', Icons.event_note),
      // nothing kept, safety still on (report 2026-11-14, P1 17: an off-the-record session)
      Card(child: ListTile(key: const Key('talk_off_record'),
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
          leading: const IconDisc(Icons.visibility_off_outlined, quiet: true),
          title: const Text('Off the record'),
          subtitle: const Text('Talk without anything being kept. Safety checks still run.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
              const ChatScreen(kind: 'daily_checkin', offRecord: true))))),
      ], [
      const SectionHeader('Trauma work'),
      const TraumaCards(),
      ]]),
    ]);
  }
}
