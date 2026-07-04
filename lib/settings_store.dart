import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stocke l'adresse du routeur pour la retrouver au prochain lancement.
class SettingsStore {
  const SettingsStore();

  static const _storage = FlutterSecureStorage();
  static const _kUrl = 'router_url';

  Future<void> saveUrl(String url) => _storage.write(key: _kUrl, value: url);

  Future<String?> loadUrl() => _storage.read(key: _kUrl);
}
