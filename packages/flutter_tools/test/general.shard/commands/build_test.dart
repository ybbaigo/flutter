// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/args.dart';
import 'package:flutter_tools/src/commands/build.dart';
import 'package:flutter_tools/src/commands/build_aar.dart';
import 'package:flutter_tools/src/commands/build_apk.dart';
import 'package:flutter_tools/src/commands/build_appbundle.dart';
import 'package:flutter_tools/src/commands/build_fuchsia.dart';
import 'package:flutter_tools/src/commands/build_ios.dart';
import 'package:flutter_tools/src/commands/build_linux.dart';
import 'package:flutter_tools/src/commands/build_macos.dart';
import 'package:flutter_tools/src/commands/build_web.dart';
import 'package:flutter_tools/src/commands/build_windows.dart';

import '../../src/common.dart';
import '../../src/context.dart';

void main() {
  testUsingContext('All build commands support null safety options', () {
    final List<BuildSubCommand> commands = <BuildSubCommand>[
      BuildWindowsCommand(verboseHelp: false),
      BuildLinuxCommand(verboseHelp: false),
      BuildMacosCommand(verboseHelp: false),
      BuildWebCommand(verboseHelp: false),
      BuildApkCommand(verboseHelp: false),
      BuildIOSCommand(verboseHelp: false),
      BuildAppBundleCommand(verboseHelp: false),
      BuildFuchsiaCommand(verboseHelp: false),
      BuildAarCommand(verboseHelp: false),
    ];

    for (final BuildSubCommand command in commands) {
      final ArgResults results = command.argParser.parse(<String>[
        '--sound-null-safety',
        '--enable-experiment=non-nullable',
      ]);

      expect(results.wasParsed('sound-null-safety'), true);
      expect(results.wasParsed('enable-experiment'), true);
    }
  });
}
