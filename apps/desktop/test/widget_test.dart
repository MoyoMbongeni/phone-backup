import 'package:flutter_test/flutter_test.dart';
import 'package:phone_backup_desktop/app_state.dart';
import 'package:phone_backup_desktop/main.dart';

void main() {
  testWidgets('with no vault open, the app offers to create or open one', (tester) async {
    await tester.pumpWidget(PhoneBackupApp(state: AppState()));
    expect(find.text('Phone Backup'), findsOneWidget);
    expect(find.text('Create a new vault…'), findsOneWidget);
    expect(find.text('Open another vault…'), findsOneWidget);
  });
}
