import 'package:app/common/window.dart';
import 'package:app/connectors/gallery_page_connector.dart';
import 'package:app/connectors/splash_page_connector.dart';
import 'package:app/connectors/toast_stack_connector.dart';
import 'package:app/connectors/top_level_page_connector.dart';
import 'package:app/connectors/window_controls_connector.dart';
import 'package:business/redux/access/actions/set_shown_action.dart';
import 'package:business/redux/common/action.dart' as redux;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:models/error_kind.dart';
import 'package:models/notice_kind.dart';
import 'package:models/studio_error.dart';
import 'package:models/studio_notice.dart';
import 'package:ui/alerts/toast_stack.dart';
import 'package:ui/dialogs/error_dialog.dart';
import 'package:ui/overlays/barrier_overlay.dart';
import 'package:ui/overlays/no_internet_overlay.dart';
import 'package:ui/pages/gallery_page.dart';
import 'package:ui/pages/splash_page.dart';
import 'package:ui/shell/window_controls.dart';

import 'support/screen_app.dart';

/// The small parts of the shell as the store makes them (studio-rules,
/// step 1): the toasts, the window's own buttons, the overlays over every
/// page, the gallery and the splash — their words in English and
/// Ukrainian and what each control does.
void main() {
  final words = ScreenWords('shell_parts');

  group('toasts', () {
    Future<ScreenApp> shown(
      WidgetTester t, {
      bool open = false,
      Locale locale = const Locale('en'),
    }) async {
      final app = ScreenApp();
      await app.logIn(t);
      app
        ..ignoreOverflow()
        ..put(
          (s) => s.copyWith.problems(
            open: open,
            items: IList([
              StudioError(
                kind: ErrorKind.reach,
                id: 3,
                message: 'timeout',
                key: '$plant/downstream/plc1/t1',
                call: const .known(.history),
                at: DateTime(2026, 11, 12, 2, 1),
                quiet: true,
                retry: () => SetShownAction(true),
              ),
              StudioError(
                kind: ErrorKind.broker,
                id: 5,
                message: 'permission denied',
                key: '$plant/sys',
                call: const .known(.list),
                at: DateTime(2026, 11, 12, 2, 2),
                quiet: true,
              ),
            ]),
            toasts: [3, 5].lock,
            notices: IList(const [
              StudioNotice(id: 4, kind: NoticeKind.detailsCopied),
            ]),
          ),
        );
      await app.pump(t, const ToastStackConnector(), locale: locale);
      return app;
    }

    testWidgets('the words of an error and a notice', (t) async {
      final app = await shown(t);
      words.check('toasts', app.words(t, find.byType(ToastStack)));
      await app.leave(t);
    });

    testWidgets('in Ukrainian', (t) async {
      final app = await shown(t, locale: const Locale('uk'));
      words.check('toasts uk', app.words(t, find.byType(ToastStack)));
      await app.leave(t);
      await S.load(const Locale('en'));
    });

    testWidgets('none while the Problems drawer is open', (t) async {
      final app = await shown(t, open: true);
      expect(find.byType(ToastStack), findsOneWidget);
      expect(t.widget<ToastStack>(find.byType(ToastStack)).toasts, isEmpty);
      await app.leave(t);
    });

    testWidgets('Try again, Details and dismiss', (t) async {
      final app = await shown(t);
      expect(app.store.state.access.shown, isFalse);
      await t.tap(find.text('Try again').first);
      await app.settle(t);
      // the error's own retry ran
      expect(app.store.state.access.shown, isTrue);

      await t.tap(find.text('Details').last);
      await app.settle(t);
      expect(app.store.state.problems.toasts, isEmpty);
      words.check('details', app.words(t, find.byType(ErrorDialog)));
      Navigator.of(t.element(find.byType(ErrorDialog))).pop();
      await app.settle(t);

      await t.tap(find.byKey(const ValueKey('toast-dismiss-4')));
      await app.settle(t);
      expect(app.store.state.problems.notices, isEmpty);
      await app.leave(t);
    });
  });

  group('window controls', () {
    const desk = TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    });

    Future<(ScreenApp, List<String>)> shown(
      WidgetTester t, {
      bool maximized = false,
      Locale locale = const Locale('en'),
    }) async {
      final window = _RecordedWindow();
      final native = appWindow;
      appWindow = window;
      addTearDown(() => appWindow = native);
      final app = ScreenApp();
      await app.logIn(t);
      app.put((s) => s.copyWith.window(maximized: maximized));
      await app.pump(
        t,
        const WindowControlsConnector(child: Text('page')),
        locale: locale,
      );
      return (app, window.calls);
    }

    testWidgets('their tooltips', (t) async {
      final (app, _) = await shown(t);
      // the buttons are named for assistive technology
      for (final name in ['Minimize', 'Maximize', 'Close window']) {
        expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
      }
      expect(find.bySemanticsLabel('Restore'), findsNothing);
      await app.leave(t);
    }, variant: desk);

    testWidgets('maximized, in Ukrainian', (t) async {
      final (app, _) = await shown(
        t,
        maximized: true,
        locale: const Locale('uk'),
      );
      for (final name in ['Згорнути', 'Відновити', 'Закрити вікно']) {
        expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
      }
      await app.leave(t);
      await S.load(const Locale('en'));
    }, variant: desk);

    testWidgets('minimize, maximize, close', (t) async {
      final (app, calls) = await shown(t);
      for (final tip in ['Minimize', 'Maximize', 'Close window']) {
        await t.tap(find.bySemanticsLabel(tip));
        await app.settle(t);
      }
      expect(calls, containsAllInOrder(['minimize', 'maximize', 'close']));
      await app.leave(t);
    }, variant: desk);

    testWidgets('none on macOS: the page alone', (t) async {
      final (app, _) = await shown(t);
      expect(find.byType(WindowControls), findsNothing);
      expect(find.text('page'), findsOneWidget);
      await app.leave(t);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  group('overlays over every page', () {
    testWidgets('no internet, then a blocking wait', (t) async {
      final app = ScreenApp();
      await app.logIn(t);
      await app.pump(t, const TopLevelPageConnector(child: Text('page')));
      expect(find.byType(NoInternetOverlay), findsNothing);
      expect(find.byType(BarrierOverlay), findsNothing);

      app.put((s) => s.copyWith.connectivity(isAvailable: false));
      await app.settle(t);
      words.check(
        'no internet',
        app.words(t, find.byType(NoInternetOverlay)),
      );
      expect(find.text('page'), findsOneWidget);

      app.put((s) => s.copyWith(wait: s.wait.add(flag: _Blocking())));
      await app.settle(t);
      expect(find.byType(BarrierOverlay), findsOneWidget);
      expect(find.byType(NoInternetOverlay), findsNothing);
      await app.leave(t);
    });
  });

  testWidgets('the gallery and the splash draw their pages', (t) async {
    final app = ScreenApp();
    await app.logIn(t);
    await app.pump(t, const GalleryPageConnector());
    expect(find.byType(GalleryPage), findsOneWidget);
    await app.pump(t, const SplashPageConnector());
    expect(find.byType(SplashPage), findsOneWidget);
    await app.leave(t);
  });
}

/// A wait that covers the app.
class _Blocking extends redux.Action
    with redux.WaitingAction, redux.BlockingAction {
  @override
  Null reduce() => null;
}

/// The window the buttons act on, as a list of what they asked of it.
final class _RecordedWindow extends AppWindow {
  final calls = <String>[];

  // a window that is not maximized: Maximize maximizes it
  @override
  bool get isMaximized => false;

  @override
  void maximize() => calls.add('maximize');

  @override
  void unmaximize() => calls.add('unmaximize');

  @override
  void minimize() => calls.add('minimize');

  @override
  void close() => calls.add('close');

  @override
  void startDragging() => calls.add('startDragging');
}
