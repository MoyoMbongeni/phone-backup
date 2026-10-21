// Drives the real Windows app through a whole session:
//   flutter test integration_test -d windows [--dart-define=SHOTS_DIR=<folder>]
// With SHOTS_DIR set, a screenshot of each step is saved there.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:phone_backup_desktop/app_state.dart';
import 'package:phone_backup_desktop/file_dialogs.dart';
import 'package:phone_backup_desktop/main.dart';
import 'package:vault_core/vault_core.dart';

const shotsDir = String.fromEnvironment('SHOTS_DIR');

/// Answers the folder and save pickers in order.
class ScriptedDialogs extends FileDialogs {
  final directories = <String>[];
  final saveLocations = <String>[];

  @override
  Future<String?> pickDirectory({required String confirmButtonText}) async =>
      directories.removeAt(0);

  @override
  Future<String?> pickSaveLocation({required String suggestedName}) async =>
      saveLocations.removeAt(0);
}

Future<Uint8List> picture(Color background, Color accent, int seed) async {
  const size = Size(800, 600);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawRect(Offset.zero & size, Paint()..color = background);
  final random = Random(seed);
  for (var i = 0; i < 14; i++) {
    canvas.drawCircle(
      Offset(random.nextDouble() * size.width, random.nextDouble() * size.height),
      20 + random.nextDouble() * 90,
      Paint()..color = accent.withValues(alpha: 0.65),
    );
  }
  final image = await recorder.endRecording().toImage(800, 600);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final screenKey = GlobalKey();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  late Future<void> Function(WidgetTester tester, String name) shot;

  Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 60}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data);
        print('Visible texts: ${texts.join(' | ')}');
        await shot(tester, 'timeout');
        fail('Timed out waiting for $finder');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
  }

  Future<void> waitForImages(WidgetTester tester, int count) async {
    final clock = Stopwatch()..start();
    while (find.byType(Image).evaluate().length < count) {
      if (clock.elapsed > const Duration(seconds: 20)) {
        fail('Only ${find.byType(Image).evaluate().length} of $count images after 20 s');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    print('  $count images shown after ${clock.elapsedMilliseconds} ms');
    await tester.pump(const Duration(milliseconds: 300));
  }

  shot = (WidgetTester tester, String name) async {
    print('step $name');
    if (shotsDir.isEmpty) return;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final boundary = screenKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(shotsDir).create(recursive: true);
      await File(p.join(shotsDir, '$name.png')).writeAsBytes(data!.buffer.asUint8List());
    });
  };

  testWidgets('create a vault, back up twice, browse, export, lock and unlock',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('pb_app_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final vaultDir = p.join(temp.path, 'My Vault');
    final phone = Directory(p.join(temp.path, 'Phone'))..createSync();
    Future<void> put(String relative, List<int> bytes) async {
      final file = File(p.join(phone.path, relative));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }

    late Uint8List red;
    late Uint8List blue;
    await tester.runAsync(() async {
      red = await picture(const Color(0xFFC62828), const Color(0xFFFFEB3B), 1);
      blue = await picture(const Color(0xFF1565C0), Colors.white, 2);
      await put('DCIM/Camera/IMG_0001.png', red);
      await put('DCIM/Camera/IMG_0002.png', blue);
      await put('DCIM/Camera/IMG_0003.png',
          await picture(const Color(0xFF2E7D32), const Color(0xFFFFCC80), 3));
      // The same photo received again in a chat app: stored only once.
      await put('WhatsApp/Images/IMG-WA0001.png', red);
      await put('Documents/notes.txt',
          utf8.encode('Shopping list\n- oat milk\n- bread\n'));
      await put('Music/song.mp3', List.generate(300000, (i) => (i * 7) % 256));
    });

    final dialogs = ScriptedDialogs();
    fileDialogs = dialogs;
    final state = AppState(settingsPath: p.join(temp.path, 'settings.json'));
    await tester.pumpWidget(
        RepaintBoundary(key: screenKey, child: PhoneBackupApp(state: state)));
    await settle(tester);
    await shot(tester, '01-start');

    // Create the vault.
    await tester.tap(find.text('Create a new vault…'));
    await settle(tester);
    dialogs.directories.add(vaultDir);
    await tester.tap(find.text('Choose folder…'));
    await waitFor(tester, find.text(vaultDir));
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'correct horse battery');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password again'), 'correct horse battery');
    await settle(tester);
    await shot(tester, '02-create');
    await tester.tap(find.text('Create vault'));
    await waitFor(tester, find.text('Your recovery key'));
    final recoveryKey = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!
        .replaceAll('\n', '-');
    expect(recoveryKey, matches(RegExp(r'^([0-9A-Z]{4}-){7}[0-9A-Z]{4}$')));
    await shot(tester, '03-recovery-key');
    await tester.tap(find.byType(Checkbox));
    await settle(tester);
    await tester.tap(find.text('Open the vault'));
    await waitFor(tester, find.text('The vault is empty'));
    await shot(tester, '04-empty-vault');

    // First backup of the "phone" folder.
    dialogs.directories.add(phone.path);
    await tester.tap(find.text('Back up a folder…').first);
    await waitFor(tester, find.text('Backup finished'));
    await shot(tester, '05-first-backup');
    final vault = state.vault!;
    expect(vault.index.stats.liveFiles, 6);
    expect(vault.index.stats.duplicatesAvoided, 1);
    await tester.tap(find.text('Close'));
    await settle(tester);

    // Browse; thumbnails are decrypted in memory.
    await tester.tap(find.text('DCIM'));
    await settle(tester);
    await tester.tap(find.text('Camera'));
    await waitFor(tester, find.text('IMG_0002.png'));
    await waitForImages(tester, 3);
    await shot(tester, '06-camera-folder');

    await tester.tap(find.text('IMG_0002.png'));
    await waitFor(tester, find.text('Export a copy…'));
    await waitForImages(tester, 4);
    await shot(tester, '07-preview');
    await tester.tap(find.text('History'));
    await waitFor(tester, find.text('Added DCIM/Camera/IMG_0002.png'));
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);

    // Change the phone: delete a photo, rename one, edit a note, add a photo.
    await tester.runAsync(() async {
      await File(p.join(phone.path, 'DCIM', 'Camera', 'IMG_0002.png')).delete();
      await File(p.join(phone.path, 'DCIM', 'Camera', 'IMG_0003.png'))
          .rename(p.join(phone.path, 'DCIM', 'Camera', 'Holiday 2026.png'));
      await put('Documents/notes.txt',
          utf8.encode('Shopping list\n- oat milk\n- bread\n- coffee\n'));
      await put('DCIM/Camera/IMG_0004.png',
          await picture(const Color(0xFF6A1B9A), const Color(0xFF80DEEA), 4));
    });
    await tester.tap(find.byTooltip('Back up this folder again'));
    await waitFor(tester, find.text('Backup finished'));
    await shot(tester, '08-second-backup');
    final snapshot = vault.index.events.lastWhere((e) => e.type == EventType.snapshot).info!;
    expect([snapshot['added'], snapshot['modified'], snapshot['moved'], snapshot['deleted']],
        [1, 1, 1, 1]);
    await tester.tap(find.text('Close'));
    await waitFor(tester, find.text('Holiday 2026.png'));
    await waitForImages(tester, 3);
    await shot(tester, '09-camera-after-changes');

    // The deleted photo is still in the vault and can be exported.
    await tester.tap(find.text('Deleted'));
    await waitFor(tester, find.text('IMG_0002.png'));
    await waitForImages(tester, 1);
    await shot(tester, '10-deleted');
    await tester.tap(find.text('IMG_0002.png'));
    await waitFor(tester, find.textContaining('The vault still keeps it'));
    final exportPath = p.join(temp.path, 'restored.png');
    dialogs.saveLocations.add(exportPath);
    await tester.tap(find.text('Export a copy…'));
    await waitFor(tester, find.text('Choose where…'));
    await tester.tap(find.text('Choose where…'));
    await waitFor(tester, find.textContaining('Saved to'));
    expect(await tester.runAsync(() => File(exportPath).readAsBytes()), blue);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);

    await tester.tap(find.text('Activity'));
    await settle(tester);
    expect(find.text('Moved DCIM/Camera/IMG_0003.png → DCIM/Camera/Holiday 2026.png'),
        findsOneWidget);
    await shot(tester, '11-activity');
    await tester.tap(find.text('Overview'));
    await settle(tester);
    await shot(tester, '12-overview');

    // Nothing in the vault folder is readable.
    await tester.runAsync(() async {
      await for (final entity in Directory(vaultDir).list(recursive: true)) {
        if (entity is! File) continue;
        final text = latin1.decode(await entity.readAsBytes());
        for (final secret in ['oat milk', 'Holiday 2026', 'IMG_0002', 'Camera']) {
          expect(text.contains(secret), isFalse, reason: '$secret in ${entity.path}');
        }
      }
    });

    // Lock; a wrong password is refused, the right one opens it.
    await tester.tap(find.byTooltip('Lock'));
    await waitFor(tester, find.text('Open My Vault'));
    await shot(tester, '13-locked');
    await tester.tap(find.text('Open My Vault'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'wrong password');
    await tester.tap(find.text('Unlock'));
    await waitFor(tester, find.text('That password does not open this vault.'));
    await shot(tester, '14-wrong-password');
    await tester.enterText(find.byType(TextField), 'correct horse battery');
    await tester.tap(find.text('Unlock'));
    await waitFor(tester, find.byTooltip('Lock'));

    // Forgotten password: the recovery key opens it and sets a new one.
    await tester.tap(find.byTooltip('Lock'));
    await waitFor(tester, find.text('Open My Vault'));
    await tester.tap(find.text('Open My Vault'));
    await settle(tester);
    await tester.tap(find.text('Forgot the password? Use the recovery key'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), recoveryKey.toLowerCase());
    await tester.tap(find.text('Unlock'));
    await waitFor(tester, find.text('Choose a new password'));
    await tester.enterText(
        find.widgetWithText(TextField, 'New password'), 'new horse battery staple');
    await tester.enterText(
        find.widgetWithText(TextField, 'New password again'), 'new horse battery staple');
    await settle(tester);
    await shot(tester, '15-new-password');
    await tester.tap(find.text('Save password'));
    await waitFor(tester, find.byTooltip('Lock'));
    await tester.tap(find.byTooltip('Lock'));
    await waitFor(tester, find.text('Open My Vault'));
    await tester.tap(find.text('Open My Vault'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'new horse battery staple');
    await tester.tap(find.text('Unlock'));
    await waitFor(tester, find.byTooltip('Lock'));
    expect(state.vault!.index.stats.deletedFiles, 1);
    expect(state.vault!.index.stats.liveFiles, 6);
  });
}
