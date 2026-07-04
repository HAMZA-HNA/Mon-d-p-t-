/// Un appareil vu sur le réseau local (téléphone, PC, TV, etc.).
///
/// L'adresse MAC est l'identifiant stable utilisé pour bloquer/débloquer :
/// l'IP peut changer (DHCP) mais la MAC reste la même pour un appareil donné.
class NetworkDevice {
  const NetworkDevice({
    required this.mac,
    this.ip,
    this.hostname,
    this.connectionType,
    this.isBlocked = false,
    this.isOnline = true,
  });

  /// Adresse MAC normalisée en majuscules avec `:` comme séparateur.
  final String mac;

  /// Dernière IP connue de l'appareil (peut être nulle si hors ligne).
  final String? ip;

  /// Nom d'hôte / nom d'appareil rapporté par le routeur.
  final String? hostname;

  /// "WiFi", "Ethernet"... selon ce que le routeur expose.
  final String? connectionType;

  /// True si l'appareil est actuellement bloqué (filtrage MAC).
  final bool isBlocked;

  /// True si l'appareil est actuellement connecté.
  final bool isOnline;

  /// Nom affiché à l'utilisateur : le hostname s'il existe, sinon la MAC.
  String get displayName {
    final h = hostname?.trim();
    if (h != null && h.isNotEmpty && h != '--' && h.toLowerCase() != 'unknown') {
      return h;
    }
    return mac;
  }

  NetworkDevice copyWith({
    String? ip,
    String? hostname,
    String? connectionType,
    bool? isBlocked,
    bool? isOnline,
  }) {
    return NetworkDevice(
      mac: mac,
      ip: ip ?? this.ip,
      hostname: hostname ?? this.hostname,
      connectionType: connectionType ?? this.connectionType,
      isBlocked: isBlocked ?? this.isBlocked,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  /// Normalise une adresse MAC brute vers `AA:BB:CC:DD:EE:FF`.
  static String normalizeMac(String raw) {
    final hex = raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (hex.length != 12) return raw.trim().toUpperCase();
    final parts = <String>[];
    for (var i = 0; i < 12; i += 2) {
      parts.add(hex.substring(i, i + 2));
    }
    return parts.join(':');
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkDevice && other.mac == mac;

  @override
  int get hashCode => mac.hashCode;
}
