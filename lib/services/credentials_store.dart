import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Identifiants sauvegardés pour se reconnecter automatiquement.
class RouterCredentials {
  const RouterCredentials({
    required this.host,
    required this.username,
    required this.password,
  });

  final String host;
  final String username;
  final String password;
}

/// Stockage sécurisé des identifiants du routeur.
///
/// Utilise le Keystore Android / Keychain iOS via `flutter_secure_storage` :
/// le mot de passe n'est jamais écrit en clair dans un fichier accessible.
class CredentialsStore {
  CredentialsStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kHost = 'router_host';
  static const _kUser = 'router_user';
  static const _kPass = 'router_pass';

  Future<void> save(RouterCredentials creds) async {
    await _storage.write(key: _kHost, value: creds.host);
    await _storage.write(key: _kUser, value: creds.username);
    await _storage.write(key: _kPass, value: creds.password);
  }

  Future<RouterCredentials?> load() async {
    final host = await _storage.read(key: _kHost);
    final user = await _storage.read(key: _kUser);
    final pass = await _storage.read(key: _kPass);
    if (host == null || user == null || pass == null) return null;
    return RouterCredentials(host: host, username: user, password: pass);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kHost);
    await _storage.delete(key: _kUser);
    await _storage.delete(key: _kPass);
  }
}
