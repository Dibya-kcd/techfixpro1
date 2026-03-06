import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techfix_pro/main.dart';
import 'package:techfix_pro/screens/repair_detail.dart';
import 'package:techfix_pro/screens/settings.dart';
// ignore: unused_import — StatusProgress is used in tests
import 'package:techfix_pro/widgets/w.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: TechFixApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings screen shows owner name from settings',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('Staff page renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: StaffPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // StaffPage shows 'Staff' heading or 'No staff added' when list is empty
    expect(
      find.byType(StaffPage),
      findsOneWidget,
    );
  });

  testWidgets('StatusProgress shows on hold banner text',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusProgress('On Hold'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Job On Hold'), findsOneWidget);
  });

  testWidgets('Root shell home renders without errors',
      (WidgetTester tester) async {
    await _pumpApp(tester);
    expect(find.text('TechFix Pro'), findsWidgets);
  });

  testWidgets('Root shell home golden',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpWidget(
      const ProviderScope(
        child: TechFixApp(),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(TechFixApp),
      matchesGoldenFile('goldens/root_shell_home.png'),
    );
  }, skip: true);

  testWidgets('Navigate from dashboard to repairs and open job detail',
      (WidgetTester tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Repairs'));
    await tester.pumpAndSettle();
    expect(find.text('JOB-2025-0042'), findsWidgets);
    await tester.tap(find.text('JOB-2025-0042').first);
    await tester.pumpAndSettle();
    expect(find.text('JOB-2025-0042'), findsWidgets);
  }, skip: true);

  testWidgets('More menu opens stock and reports screens',
      (WidgetTester tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Stock'), findsWidgets);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Reports'), findsWidgets);
  });

  testWidgets('Settings screen golden',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_screen.png'),
    );
  }, skip: true);

  testWidgets('Repair detail screen golden',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: RepairDetailScreen(jobId: 'j1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(RepairDetailScreen),
      matchesGoldenFile('goldens/repair_detail_screen.png'),
    );
  }, skip: true);
}
