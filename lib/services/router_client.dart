import '../models/network_device.dart';

/// Exception levée par un client routeur avec un message lisible.
class RouterException implements Exception {
  RouterException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Interface commune à tous les routeurs.
///
/// Chaque marque (ZTE, Huawei, Sagemcom...) fournit sa propre implémentation.
/// L'interface utilisateur ne dépend que de cette abstraction : pour supporter
/// un nouveau modèle, il suffit d'écrire une nouvelle classe qui l'implémente,
/// sans toucher aux écrans.
abstract class RouterClient {
  /// Adresse du routeur, ex. `192.168.1.1`.
  String get host;

  /// Ouvre une session authentifiée avec le routeur.
  /// Lève [RouterException] si le login échoue.
  Future<void> login({
    required String username,
    required String password,
  });

  /// Ferme la session (best-effort).
  Future<void> logout();

  /// Liste tous les appareils connus du routeur (connectés + bloqués).
  Future<List<NetworkDevice>> fetchDevices();

  /// Bloque l'accès réseau d'un appareil via son adresse MAC.
  Future<void> blockDevice(String mac);

  /// Rétablit l'accès réseau d'un appareil.
  Future<void> unblockDevice(String mac);
}
