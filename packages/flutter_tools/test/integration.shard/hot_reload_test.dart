// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../src/common.dart';
import 'test_data/hot_reload_project.dart';
import 'test_driver.dart';
import 'test_utils.dart';

void main() {
  Directory tempDir;
  final HotReloadProject project = HotReloadProject();
  FlutterRunTestDriver flutter;

  setUp(() async {
    tempDir = createResolvedTempDirectorySync('hot_reload_test.');
    await project.setUpIn(tempDir);
    flutter = FlutterRunTestDriver(tempDir);
  });

  tearDown(() async {
    await flutter?.stop();
    tryToDelete(tempDir);
  });

  test('hot reload works without error', () async {
    await flutter.run();
    await flutter.hotReload();
  });

  test('newly added code executes during hot reload', () async {
    final StringBuffer stdout = StringBuffer();
    final StreamSubscription<String> subscription = flutter.stdout.listen(stdout.writeln);
    await flutter.run();
    project.uncommentHotReloadPrint();
    try {
      await flutter.hotReload();
      expect(stdout.toString(), contains('(((((RELOAD WORKED)))))'));
    } finally {
      await subscription.cancel();
    }
  });

  test('fastReassemble behavior triggers hot reload behavior with evaluation of expression', () async {
    final StringBuffer stdout = StringBuffer();
    final StreamSubscription<String> subscription = flutter.stdout.listen(stdout.writeln);
    await flutter.run(withDebugger: true);

    final int port = flutter.vmServicePort;
    final VmService vmService = await vmServiceConnectUri('ws://localhost:$port/ws');
    try {
      // Since the single-widget reload feature is not yet implemented, manually
      // evaluate the expression for the reload.
      final Isolate isolate = await waitForExtension(vmService);
      final LibraryRef targetRef = isolate.libraries.firstWhere((LibraryRef libraryRef) {
        return libraryRef.uri == 'package:test/main.dart';
      });
      await vmService.evaluate(
        isolate.id,
        targetRef.id,
        '((){debugFastReassembleMethod=(Object x) => x is MyApp})()',
      );

      final Response fastReassemble1 = await vmService
        .callServiceExtension('ext.flutter.fastReassemble', isolateId: isolate.id);

      // _extensionType indicates success.
      expect(fastReassemble1.type, '_extensionType');
      expect(stdout.toString(), contains('(((TICK 2))))'));

      // verify evaluation did not produce invalidat type by checking with dart:core
      // type.
      await vmService.evaluate(
        isolate.id,
        targetRef.id,
        '((){debugFastReassembleMethod=(Object x) => x is bool})()',
      );

      final Response fastReassemble2 = await vmService
        .callServiceExtension('ext.flutter.fastReassemble', isolateId: isolate.id);

      // _extensionType indicates success.
      expect(fastReassemble2.type, '_extensionType');
      expect(stdout.toString(), isNot(contains('(((TICK 3))))')));

      // Invocation without evaluation leads to runtime error.
      expect(vmService
        .callServiceExtension('ext.flutter.fastReassemble', isolateId: isolate.id),
        throwsA(isA<Exception>())
      );
    } finally {
      await subscription.cancel();
    }
  });

  test('hot restart works without error', () async {
    await flutter.run();
    await flutter.hotRestart();
  });

  test('breakpoints are hit after hot reload', () async {
    Isolate isolate;
    final Completer<void> sawTick1 = Completer<void>();
    final Completer<void> sawDebuggerPausedMessage = Completer<void>();
    final StreamSubscription<String> subscription = flutter.stdout.listen(
      (String line) {
        if (line.contains('((((TICK 1))))')) {
          expect(sawTick1.isCompleted, isFalse);
          sawTick1.complete();
        }
        if (line.contains('The application is paused in the debugger on a breakpoint.')) {
          expect(sawDebuggerPausedMessage.isCompleted, isFalse);
          sawDebuggerPausedMessage.complete();
        }
      },
    );
    await flutter.run(withDebugger: true, startPaused: true);
    await flutter.resume(); // we start paused so we can set up our TICK 1 listener before the app starts
    unawaited(sawTick1.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () { print('The test app is taking longer than expected to print its synchronization line...'); },
    ));
    await sawTick1.future; // after this, app is in steady state
    await flutter.addBreakpoint(
      project.scheduledBreakpointUri,
      project.scheduledBreakpointLine,
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    await flutter.hotReload(); // reload triggers code which eventually hits the breakpoint
    isolate = await flutter.waitForPause();
    expect(isolate.pauseEvent.kind, equals(EventKind.kPauseBreakpoint));
    await flutter.resume();
    await flutter.addBreakpoint(
      project.buildBreakpointUri,
      project.buildBreakpointLine,
    );
    bool reloaded = false;
    final Future<void> reloadFuture = flutter.hotReload().then((void value) { reloaded = true; });
    print('waiting for pause...');
    isolate = await flutter.waitForPause();
    expect(isolate.pauseEvent.kind, equals(EventKind.kPauseBreakpoint));
    print('waiting for debugger message...');
    await sawDebuggerPausedMessage.future;
    expect(reloaded, isFalse);
    print('waiting for resume...');
    await flutter.resume();
    print('waiting for reload future...');
    await reloadFuture;
    expect(reloaded, isTrue);
    reloaded = false;
    print('subscription cancel...');
    await subscription.cancel();
  });

  test("hot reload doesn't reassemble if paused", () async {
    final Completer<void> sawTick1 = Completer<void>();
    final Completer<void> sawDebuggerPausedMessage1 = Completer<void>();
    final Completer<void> sawDebuggerPausedMessage2 = Completer<void>();
    final StreamSubscription<String> subscription = flutter.stdout.listen(
      (String line) {
        print('[LOG]:"$line"');
        if (line.contains('(((TICK 1)))')) {
          expect(sawTick1.isCompleted, isFalse);
          sawTick1.complete();
        }
        if (line.contains('The application is paused in the debugger on a breakpoint.')) {
          expect(sawDebuggerPausedMessage1.isCompleted, isFalse);
          sawDebuggerPausedMessage1.complete();
        }
        if (line.contains('The application is paused in the debugger on a breakpoint; interface might not update.')) {
          expect(sawDebuggerPausedMessage2.isCompleted, isFalse);
          sawDebuggerPausedMessage2.complete();
        }
      },
    );
    await flutter.run(withDebugger: true);
    await Future<void>.delayed(const Duration(seconds: 1));
    await sawTick1.future;
    await flutter.addBreakpoint(
      project.buildBreakpointUri,
      project.buildBreakpointLine,
    );
    bool reloaded = false;
    await Future<void>.delayed(const Duration(seconds: 1));
    final Future<void> reloadFuture = flutter.hotReload().then((void value) { reloaded = true; });
    final Isolate isolate = await flutter.waitForPause();
    expect(isolate.pauseEvent.kind, equals(EventKind.kPauseBreakpoint));
    expect(reloaded, isFalse);
    await sawDebuggerPausedMessage1.future; // this is the one where it say "uh, you broke into the debugger while reloading"
    await reloadFuture; // this is the one where it times out because you're in the debugger
    expect(reloaded, isTrue);
    await flutter.hotReload(); // now we're already paused
    await sawDebuggerPausedMessage2.future; // so we just get told that nothing is going to happen
    await flutter.resume();
    await subscription.cancel();
  });
}
