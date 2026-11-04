// Optional reproducible screenshots of the real Flutter UI for the school demo.
// DEMO_CAPTURE_DIR=/absolute/path DEMO_FONT_PATH=/path/to/Roboto-Regular.ttf
// flutter test test/demo/capture_demo_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_app/core/app.dart';
import 'package:household_app/data/household_store.dart';

import '../data/household_store_test.dart' show MemoryStorage;

void main() {
  final output = Platform.environment['DEMO_CAPTURE_DIR'];
  testWidgets('capture a repeatable chore walkthrough', (tester) async {
    await tester.runAsync(() async {
      final font = FontLoader('Roboto')
        ..addFont(
          File(Platform.environment['DEMO_FONT_PATH']!)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '${File(Platform.environment['DEMO_FONT_PATH']!).parent.path}/MaterialIcons-Regular.otf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await icons.load();
    });
    await tester.binding.setSurfaceSize(const Size(440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final store = HouseholdStore(
      MemoryStorage(),
      clock: () => DateTime(2026, 11, 4),
    );
    await store.load();
    await store.loadDemo();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: HouseholdApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output!).create(recursive: true);
        await File('$output/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> tab(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    await capture('01-dashboard');
    await tester.tap(find.text('My Responsibilities'));
    await tester.pumpAndSettle();
    await capture('02-my-responsibilities');
    await tester.tap(find.text('Mark complete').first);
    await tester.pumpAndSettle();
    expect(store.chores.first.assignee, 'jordan');
    await tester.tap(find.text('Household chores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    await capture('03-rotated');
    await tester.tap(find.byTooltip('Completion history'));
    await tester.pumpAndSettle();
    await capture('04-history');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tab('Fairness');
    await capture('05-fairness');
    await tab('Household');
    await capture('06-household');
    await tab('Chores');
    await tester.tap(find.text('Add chore'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Sweep the hallway',
    );
    await capture('07-editor');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save chore'));
    await tester.pumpAndSettle();
    expect(store.chores.any((c) => c.title == 'Sweep the hallway'), isTrue);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
  }, skip: output == null);
}
