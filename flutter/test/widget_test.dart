import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brazil_exit_button/main.dart';

void main() {
  testWidgets('Missing configuration keeps control unavailable',
      (tester) async {
    await tester.pumpWidget(const BrazilExitApp());
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Build-time configuration missing; see README.'),
        findsOneWidget);
    expect(find.text('TURN OFF'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
