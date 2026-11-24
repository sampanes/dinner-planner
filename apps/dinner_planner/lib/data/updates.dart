// A new version without a computer.
//
// Every version is built and signed by the repository's "Phone app" workflow
// and attached to a GitHub release named app-v<version>. The phone asks
// GitHub which is newest, downloads that file, checks it against the
// fingerprint GitHub publishes for it, and hands it to Android, which asks
// the owner once more before installing. Android itself refuses a file that
// was not signed with the same key as the app already on the phone.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// This version, the same as `version:` in pubspec.yaml (a test holds the
/// two together). A constant, so the background task knows it too.
const String appVersion = '0.11.0';

const String _tagPrefix = 'app-v';

/// Below zero when [a] is the older version, above when it is the newer.
/// "0.10.0" is newer than "0.9.2"; anything after a "+" or "-" is ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split(RegExp(r'[+-]')).first.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}

/// One published version of the app.
class Release {
  const Release({required this.version, required this.url, this.size = 0, this.sha256});

  final String version;

  /// Where its APK is.
  final String url;
  final int size;

  /// The APK's fingerprint as GitHub gives it, in hex; null when it gives none.
  final String? sha256;

  Map<String, Object?> toJson() => {'version': version, 'url': url, 'size': size, 'sha256': ?sha256};

  static Release? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['version'], url = raw['url'], size = raw['size'], sha = raw['sha256'];
    if (version is! String || url is! String || !_fromGitHub(url)) return null;
    return Release(version: version, url: url, size: size is int ? size : 0, sha256: sha is String ? sha : null);
  }
}

bool _fromGitHub(String url) {
  final u = Uri.tryParse(url);
  return u != null && u.scheme == 'https' && u.host == 'github.com';
}

/// The newest published app release with an APK, from what GitHub's
/// "list releases" answers (newest first).
Release? newestRelease(Object? releases) {
  if (releases is! List) return null;
  Release? best;
  for (final r in releases) {
    if (r is! Map || r['draft'] == true || r['prerelease'] == true) continue;
    final tag = r['tag_name'];
    if (tag is! String || !tag.startsWith(_tagPrefix) || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(tag.substring(_tagPrefix.length))) continue;
    final assets = r['assets'];
    if (assets is! List) continue;
    for (final a in assets) {
      if (a is! Map) continue;
      final name = a['name'], url = a['browser_download_url'], size = a['size'], digest = a['digest'];
      if (name is! String || !name.endsWith('.apk') || url is! String || !_fromGitHub(url)) continue;
      final found = Release(
        version: tag.substring(_tagPrefix.length),
        url: url,
        size: size is int ? size : 0,
        sha256: digest is String && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
      );
      if (best == null || compareVersions(found.version, best.version) > 0) best = found;
      break;
    }
  }
  return best;
}

/// Where GitHub lists the releases of the repository behind a recipe site
/// served from GitHub Pages (`https://<owner>.github.io/<repository>`); null
/// for a site kept anywhere else.
Uri? releasesApi(String site) {
  final u = Uri.tryParse(site);
  if (u == null || !u.host.endsWith('.github.io')) return null;
  final owner = u.host.substring(0, u.host.length - '.github.io'.length);
  final repo = u.pathSegments.where((s) => s.isNotEmpty).firstOrNull;
  if (owner.isEmpty || repo == null) return null;
  return Uri.https('api.github.com', '/repos/$owner/$repo/releases', {'per_page': '20'});
}

/// The newest version there is, or null when GitHub cannot be asked.
Future<Release?> fetchNewest(http.Client client, String site) async {
  final api = releasesApi(site);
  if (api == null) return null;
  final res = await client.get(api, headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) return null;
  return newestRelease(jsonDecode(utf8.decode(res.bodyBytes)));
}

/// The part only Android can do: somewhere to keep the download, and handing
/// it over to be installed.
abstract class Installer {
  /// A folder of this app's own that Android's installer may read from.
  Future<String> folder();

  /// Shows Android's "update this app?" for the APK at [path]. False when
  /// Android would not take it.
  Future<bool> install(String path);

  /// Puts the app behind whatever was in front of it before a link opened
  /// it, leaving it running.
  Future<void> stepBack();

  /// Has the home-screen widget drawn again from what was last published.
  Future<void> redrawWidget();
}

class AndroidInstaller implements Installer {
  static const MethodChannel _channel = MethodChannel('dinner_planner/app');

  @override
  Future<String> folder() async => (await _channel.invokeMethod<String>('updatesDir'))!;

  @override
  Future<bool> install(String path) async => await _channel.invokeMethod<bool>('install', {'path': path}) ?? false;

  @override
  Future<void> stepBack() async {
    try {
      await _channel.invokeMethod<void>('stepBack');
    } on Exception {
      await SystemNavigator.pop();
    }
  }

  @override
  Future<void> redrawWidget() async {
    try {
      await _channel.invokeMethod<void>('redrawWidget');
    } on Exception {
      // No widget to redraw; Android redraws it on its own every half hour.
    }
  }
}

/// Fetches [release] into [folder], telling [progress] how far along it is
/// (0 to 1), and returns the file. Throws when the download is cut short or
/// is not the file GitHub published.
Future<File> downloadRelease(http.Client client, Release release, String folder, {void Function(double done)? progress}) async {
  final dir = Directory(folder);
  await dir.create(recursive: true);
  // One update at a time: an older download is only in the way.
  await for (final old in dir.list()) {
    if (old is File && old.path.endsWith('.apk')) await old.delete();
  }
  final part = File('${dir.path}/update.part');
  final res = await client.send(http.Request('GET', Uri.parse(release.url))).timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
  final total = release.size > 0 ? release.size : (res.contentLength ?? 0);
  final digestOut = _Sink();
  final hash = sha256.startChunkedConversion(digestOut);
  final out = part.openWrite();
  var got = 0;
  try {
    await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
      out.add(chunk);
      hash.add(chunk);
      got += chunk.length;
      if (total > 0) progress?.call((got / total).clamp(0, 1).toDouble());
    }
  } finally {
    await out.close();
  }
  hash.close();
  final wanted = release.sha256;
  if ((release.size > 0 && got != release.size) || (wanted != null && digestOut.value.toString() != wanted)) {
    await part.delete();
    throw const HttpException('The download did not arrive whole.');
  }
  return part.rename('${dir.path}/dinner-planner-${release.version}.apk');
}

class _Sink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
