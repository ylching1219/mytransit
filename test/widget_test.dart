import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mytransit/main.dart';
import 'package:mytransit/providers/app_state.dart';

void main() {
  testWidgets('MyTransitAssist home page renders', (tester) async {
    final state = AppState();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const SmartMoveApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Where are you going?'), findsOneWidget);
    state.dispose();
  });
}
