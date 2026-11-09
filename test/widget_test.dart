import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skinai_assist/core/theme/app_theme.dart';

void main() {
  testWidgets('app theme renders the primary action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: FilledButton(
              onPressed: () {},
              child: const Text('Continue')),
        ),
      ),
    ));
    expect(find.text('Continue'), findsOneWidget);
  });
}
