import 'package:app/navigation/app_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/pages/flows_page.dart';

import 'support/flows_fixture.dart';
import 'support/screen_app.dart';

/// Where Flows' buttons lead, in Studio's own shell and router: `New
/// dataflow` opens the editor on a new flow, `Edit dataflow` on the flow
/// picked. One test, because the app's router is built once per test file.
void main() {
  testWidgets('New and Edit open the flow editor', (t) async {
    final app = ScreenApp();
    await app.logIn(t);
    app.put((s) => withFlows(s, selected: 'heat'));
    await app.pumpInStudio(t, const FlowsRoute());
    expect(app.top, FlowsRoute.name);

    Finder on(String text) =>
        find.descendant(of: find.byType(FlowsPage), matching: find.text(text));

    await t.tap(on('New dataflow'));
    await app.settle(t);
    expect(app.top, FlowEditorRoute.name);
    expect(appRouter.topRoute.argsAs<FlowEditorRouteArgs>().id, '+new');

    await app.go(t, const FlowsRoute());
    expect(app.top, FlowsRoute.name);
    await t.tap(on('Edit dataflow'));
    await app.settle(t);
    expect(app.top, FlowEditorRoute.name);
    expect(appRouter.topRoute.argsAs<FlowEditorRouteArgs>().id, 'heat');
    await app.leave(t);
  });
}
