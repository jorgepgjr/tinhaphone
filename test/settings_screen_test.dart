import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinhaphone/screens/settings_screen.dart';
import 'package:tinhaphone/services/prisma_api_service.dart';
import 'package:tinhaphone/services/db_service.dart';
import 'support/session_fixtures.dart';

void main() {
  testWidgets(
    'checkbox de limpeza salva a escolha e solicita limpeza imediata',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var cleanupRequests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            api: PrismaApiService(teacherSession),
            database: DbService(teacherSession.scope),
            onSaved: () async {
              cleanupRequests++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
      final save = find.widgetWithText(FilledButton, 'Salvar');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        (await PrismaApiService(teacherSession).loadConfig()).autoDeleteSynced,
        isTrue,
      );
      expect(cleanupRequests, 1);
      expect(find.text('Configurações salvas.'), findsOneWidget);
    },
  );
}
