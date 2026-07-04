import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Un raccourci enregistré vers une page du routeur.
class Bookmark {
  const Bookmark({required this.name, required this.url});
  final String name;
  final String url;

  Map<String, String> toJson() => {'name': name, 'url': url};
  factory Bookmark.fromJson(Map<String, dynamic> j) =>
      Bookmark(name: j['name'] as String, url: j['url'] as String);
}

/// Stocke l'adresse du routeur, les identifiants (pour la connexion
/// automatique) et les raccourcis, dans le stockage sécurisé du système.
class SettingsStore {
  const SettingsStore();

  static const _storage = FlutterSecureStorage();
  static const _kUrl = 'router_url';
  static const _kUser = 'router_user';
  static const _kPass = 'router_pass';
  static const _kBookmarks = 'router_bookmarks';

  // Adresse ---------------------------------------------------------------
  Future<void> saveUrl(String url) => _storage.write(key: _kUrl, value: url);
  Future<String?> loadUrl() => _storage.read(key: _kUrl);

  // Identifiants ----------------------------------------------------------
  Future<void> saveCredentials(String user, String pass) async {
    await _storage.write(key: _kUser, value: user);
    await _storage.write(key: _kPass, value: pass);
  }

  Future<(String, String)?> loadCredentials() async {
    final u = await _storage.read(key: _kUser);
    final p = await _storage.read(key: _kPass);
    if (u == null || u.isEmpty) return null;
    return (u, p ?? '');
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kPass);
  }

  // Raccourcis ------------------------------------------------------------
  Future<void> saveBookmarks(List<Bookmark> items) => _storage.write(
        key: _kBookmarks,
        value: jsonEncode(items.map((b) => b.toJson()).toList()),
      );

  Future<List<Bookmark>> loadBookmarks() async {
    final raw = await _storage.read(key: _kBookmarks);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
