import 'package:flutter/foundation.dart';

import '../models/network_device.dart';
import '../services/credentials_store.dart';
import '../services/router_client.dart';
import '../services/zte_router_client.dart';

enum SessionStatus { loggedOut, connecting, loggedIn, error }

/// Orchestrateur unique de l'application : détient la session routeur, la liste
/// des appareils, et expose les actions (login, refresh, block/unblock) aux
/// écrans. Les widgets écoutent ce contrôleur via `provider`.
class RouterController extends ChangeNotifier {
  RouterController({CredentialsStore? store})
      : _store = store ?? CredentialsStore();

  final CredentialsStore _store;

  RouterClient? _client;
  SessionStatus _status = SessionStatus.loggedOut;
  String? _errorMessage;
  bool _busy = false;
  List<NetworkDevice> _devices = [];

  SessionStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isBusy => _busy;
  String? get host => _client?.host;

  List<NetworkDevice> get devices => List.unmodifiable(_devices);
  List<NetworkDevice> get activeDevices =>
      _devices.where((d) => !d.isBlocked).toList();
  List<NetworkDevice> get blockedDevices =>
      _devices.where((d) => d.isBlocked).toList();

  /// Crée le client adapté à la marque. Pour l'instant : ZTE.
  /// Ajouter un routeur = ajouter un `case` ici.
  RouterClient _buildClient(String host) => ZteRouterClient(host: host);

  /// Tente de reconnecter avec des identifiants sauvegardés au démarrage.
  Future<void> tryAutoLogin() async {
    final saved = await _store.load();
    if (saved == null) return;
    await login(
      host: saved.host,
      username: saved.username,
      password: saved.password,
      remember: true,
    );
  }

  Future<bool> login({
    required String host,
    required String username,
    required String password,
    bool remember = true,
  }) async {
    _status = SessionStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    final client = _buildClient(host.trim());
    try {
      await client.login(username: username.trim(), password: password);
      _client = client;
      _status = SessionStatus.loggedIn;
      if (remember) {
        await _store.save(RouterCredentials(
          host: host.trim(),
          username: username.trim(),
          password: password,
        ));
      }
      notifyListeners();
      await refresh();
      return true;
    } on RouterException catch (e) {
      _status = SessionStatus.error;
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _status = SessionStatus.error;
      _errorMessage = "Erreur inattendue : $e";
      notifyListeners();
      return false;
    }
  }

  Future<void> refresh() async {
    final client = _client;
    if (client == null) return;
    _busy = true;
    notifyListeners();
    try {
      _devices = await client.fetchDevices()
        ..sort((a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()));
      if (activeDevices.isEmpty && client is ZteRouterClient) {
        final diag = client.lastFetchDiag;
        _errorMessage = diag.isEmpty
            ? null
            : 'Aucun appareil trouvé. Pages explorées : $diag';
      } else {
        _errorMessage = null;
      }
    } on RouterException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = "Erreur lors du rafraîchissement : $e";
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> setBlocked(NetworkDevice device, bool blocked) async {
    final client = _client;
    if (client == null) return;
    _busy = true;
    notifyListeners();
    try {
      if (blocked) {
        await client.blockDevice(device.mac);
      } else {
        await client.unblockDevice(device.mac);
      }
      // Mise à jour optimiste locale, puis re-sync avec le routeur.
      _devices = _devices
          .map((d) => d.mac == device.mac ? d.copyWith(isBlocked: blocked) : d)
          .toList();
      _errorMessage = null;
    } on RouterException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = "Erreur : $e";
    } finally {
      _busy = false;
      notifyListeners();
    }
    await refresh();
  }

  Future<void> logout() async {
    await _client?.logout();
    await _store.clear();
    _client = null;
    _devices = [];
    _status = SessionStatus.loggedOut;
    _errorMessage = null;
    notifyListeners();
  }
}
