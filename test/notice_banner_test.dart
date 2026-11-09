import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skinai_assist/core/widgets/common.dart';

void main() {
  testWidgets(
      'disclaimer notice explains screening limitation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: NoticeBanner())));
    expect(find.textContaining('cannot diagnose'),
        findsOneWidget);
  });
}
