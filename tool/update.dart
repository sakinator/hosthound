import 'dart:convert';
import 'dart:io';

/// Platform-neutral update pipeline for sakinator-MegaScraper.
/// Runs seamlessly on Windows, Linux, macOS, Android (Termux), and Docker.
/// Usage:
///   dart run tool/update.dart
///   dart run tool/update.dart --port 7002
///   dart run tool/update.dart --no-compile
void main(List<String> args) async {
  print('\x1B[36m==========================================================\x1B[0m');
  print('\x1B[35m ⚡ Hostreamio Cross-Platform Update Pipeline\x1B[0m');
  print('\x1B[36m==========================================================\x1B[0m');

  int port = 7002;
  bool shouldCompile = true;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--port' && i + 1 < args.length) {
      port = int.tryParse(args[i + 1]) ?? port;
    } else if (args[i] == '--no-compile') {
      shouldCompile = false;
    }
  }

  // 1. Pull updates from git repository
  print('\n\x1B[33m[1/5] Pulling latest repository updates via git...\x1B[0m');
  try {
    final gitPull = await Process.run('git', ['pull', 'origin', 'main']);
    if (gitPull.exitCode == 0) {
      print('  \x1B[32m-> ${gitPull.stdout.toString().trim()}\x1B[0m');
    } else {
      print('  \x1B[31m-> Git pull notice: ${gitPull.stderr.toString().trim()}\x1B[0m');
    }
  } catch (e) {
    print('  \x1B[90m-> Git command skipped or not found ($e)\x1B[0m');
  }

  // 2. Check upstream PlayTorrio submodule if present
  print('\n\x1B[33m[2/5] Checking upstream PlayTorrio providers...\x1B[0m');
  final upstreamGit = Directory('upstream/PlayTorrioV3/.git');
  if (await upstreamGit.exists()) {
    try {
      final upPull = await Process.run('git', ['pull', 'origin', 'main'], workingDirectory: 'upstream/PlayTorrioV3');
      if (upPull.exitCode == 0) {
        print('  \x1B[32m-> Upstream PlayTorrio updated: ${upPull.stdout.toString().trim()}\x1B[0m');
      } else {
        print('  \x1B[90m-> Upstream PlayTorrio status: ${upPull.stderr.toString().trim()}\x1B[0m');
      }
    } catch (_) {}
  } else {
    print('  \x1B[90m-> Standalone mode (upstream integrated directly into lib/upstream).\x1B[0m');
  }

  // 3. Scan scraper sites & regenerate registry for both server and android_app
  print('\n\x1B[33m[3/5] Regenerating scraper registry...\x1B[0m');
  final registryFile = File('tool/generate_registry.dart');
  if (await registryFile.exists()) {
    final regRes = await Process.run(Platform.resolvedExecutable, ['run', 'tool/generate_registry.dart']);
    if (regRes.exitCode == 0) {
      print('  \x1B[32m-> ${regRes.stdout.toString().trim()}\x1B[0m');
      // Sync registry to android_app
      final serverReg = File('lib/scraper_registry.dart');
      final appReg = File('android_app/lib/scraper_registry.dart');
      if (await serverReg.exists() && await appReg.parent.exists()) {
        await serverReg.copy(appReg.path);
        print('  \x1B[32m-> Synced scraper registry to android_app/lib/scraper_registry.dart\x1B[0m');
      }
    } else {
      print('  \x1B[31m-> Failed to regenerate registry: ${regRes.stderr}\x1B[0m');
    }
  }

  // 4. Compile standalone binary (optional)
  if (shouldCompile) {
    print('\n\x1B[33m[4/5] Compiling standalone server executable...\x1B[0m');
    final isWindows = Platform.isWindows;
    final binaryName = isWindows ? 'hostreamio.exe' : 'hostreamio';
    final tempBinary = isWindows ? 'hostreamio-new.exe' : 'hostreamio-new';

    final compileRes = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'bin/server.dart',
      '-o',
      tempBinary,
    ]);

    if (compileRes.exitCode == 0) {
      try {
        final target = File(binaryName);
        final temp = File(tempBinary);
        if (await target.exists()) {
          // If locked on Windows, catch and inform
          await temp.rename(target.path);
        } else {
          await temp.rename(target.path);
        }
        print('  \x1B[32m-> Successfully compiled $binaryName!\x1B[0m');
      } catch (_) {
        print('  \x1B[33m-> Server is currently running. Binary will update on next server restart.\x1B[0m');
      }
    } else {
      print('  \x1B[31m-> Compilation notice: ${compileRes.stderr.toString().trim()}\x1B[0m');
    }
  } else {
    print('\n\x1B[90m[4/5] Skipping binary compilation (--no-compile).\x1B[0m');
  }

  // 5. Notify Running Server (Hot-Reload)
  print('\n\x1B[33m[5/5] Notifying running addon server for instant hot-reload...\x1B[0m');
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    final req = await client.postUrl(Uri.parse('http://localhost:$port/api/pipeline/update'));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();

    if (res.statusCode == 200) {
      print('  \x1B[32m-> Server on port $port hot-reloaded successfully! Response: $body\x1B[0m');
    } else {
      print('  \x1B[33m-> Server responded with HTTP ${res.statusCode}\x1B[0m');
    }
  } catch (_) {
    print('  \x1B[90m-> Server not running on port $port (will load updated providers on launch).\x1B[0m');
  }

  print('\n\x1B[36m==========================================================\x1B[0m');
  print('\x1B[32m ✅ Platform-Neutral Update Pipeline Complete!\x1B[0m');
  print('\x1B[36m==========================================================\x1B[0m');
}
