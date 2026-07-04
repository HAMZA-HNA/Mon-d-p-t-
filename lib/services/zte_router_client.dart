import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/network_device.dart';
import 'router_client.dart';

/// Points d'entrée (URLs / champs) de l'interface web ZTE.
///
/// ⚠️ IMPORTANT : les firmwares ZTE (ZXHN F660, F670, F668, H168N...) diffèrent.
/// Les valeurs ci-dessous couvrent les cas les plus courants chez Orange Maroc,
/// mais tu devras peut-être les ajuster pour TON modèle. Comment les trouver :
///
///   1. Connecte-toi à http://192.168.1.1 depuis un PC (Chrome/Firefox).
///   2. Ouvre les outils développeur (touche F12) → onglet "Network"/"Réseau".
///   3. Va sur la page qui liste les appareils connectés, et sur la page de
///      filtrage MAC. Regarde les requêtes (URL + champs POST) qui partent.
///   4. Recopie les bons chemins ici.
///
/// Tout est centralisé dans cette classe pour n'avoir qu'un seul endroit à
/// modifier.
class ZteEndpoints {
  const ZteEndpoints({
    this.loginPath = '/',
    this.logoutPath = '/?_type=loginData&_tag=logout&_=0',
    this.deviceListPaths = const [
      // Plusieurs chemins possibles selon le firmware : on essaie chacun
      // jusqu'à en trouver un qui renvoie des adresses MAC.
      '/getpage.gch?pid=1002&nextpage=net_dhcp_dynamic_t.gch',
      '/getpage.gch?pid=1002&nextpage=Localnet_LANDevice_t.gch',
      '/getpage.gch?pid=1002&nextpage=access_dev_t.gch',
      '/common_page/lanMgrList_lua.lua',
    ],
    this.macFilterPath = '/getpage.gch?pid=1002&nextpage=access_mac_filter_t.gch',
  });

  final String loginPath;
  final String logoutPath;
  final List<String> deviceListPaths;
  final String macFilterPath;
}

/// Client pour les routeurs ZTE (interface web ZXHN).
///
/// Le package `http` ne gère pas les cookies : on maintient donc la session
/// manuellement (le routeur renvoie un cookie `SID` après le login).
class ZteRouterClient implements RouterClient {
  ZteRouterClient({
    required this.host,
    this.useHttps = false,
    this.endpoints = const ZteEndpoints(),
    http.Client? httpClient,
    Duration? timeout,
  })  : _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 12);

  @override
  final String host;

  final bool useHttps;
  final ZteEndpoints endpoints;
  final http.Client _http;
  final Duration _timeout;

  /// Cookies de session, sous forme `nom=valeur`.
  final Map<String, String> _cookies = {};

  String get _scheme => useHttps ? 'https' : 'http';
  Uri _uri(String path) => Uri.parse('$_scheme://$host$path');

  String get _cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  void _absorbCookies(http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return;
    // Découpe naïve mais suffisante : "SID=abc; Path=/, OTHER=xyz; Path=/"
    for (final chunk in raw.split(RegExp(r',(?=[^ ]+=)'))) {
      final first = chunk.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq > 0) {
        _cookies[first.substring(0, eq)] = first.substring(eq + 1);
      }
    }
  }

  Future<http.Response> _get(String path) async {
    final res = await _http
        .get(_uri(path), headers: {'Cookie': _cookieHeader})
        .timeout(_timeout);
    _absorbCookies(res);
    return res;
  }

  Future<http.Response> _post(String path, Map<String, String> body) async {
    final res = await _http
        .post(
          _uri(path),
          headers: {
            'Cookie': _cookieHeader,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: body,
        )
        .timeout(_timeout);
    _absorbCookies(res);
    return res;
  }

  // ---------------------------------------------------------------------------
  // Authentification
  // ---------------------------------------------------------------------------

  @override
  Future<void> login({
    required String username,
    required String password,
  }) async {
    http.Response page;
    try {
      page = await _get(endpoints.loginPath);
    } on TimeoutException {
      throw RouterException(
          "Pas de réponse du routeur ($host). Vérifie que ton téléphone est "
          "bien connecté au WiFi et que l'adresse IP est correcte.");
    } catch (e) {
      throw RouterException("Impossible de joindre le routeur : $e");
    }

    // Le token anti-rejeu change à chaque affichage de la page de login.
    final token = _extractLoginToken(page.body);

    // La plupart des firmwares ZXHN attendent SHA256(motDePasse + token).
    // Certains attendent SHA256(motDePasse) seul : on tente les deux.
    final hashedWithToken =
        sha256.convert(utf8.encode('$password${token ?? ''}')).toString();
    final hashedPlain = sha256.convert(utf8.encode(password)).toString();

    for (final candidate in [hashedWithToken, hashedPlain, password]) {
      final ok = await _attemptLogin(username, candidate, token);
      if (ok) return;
    }

    throw RouterException(
        "Login refusé. Vérifie l'utilisateur et le mot de passe (souvent sur "
        "l'étiquette derrière le routeur). Si un seul appareil peut être "
        "connecté à l'admin à la fois, déconnecte les autres.");
  }

  Future<bool> _attemptLogin(
      String username, String password, String? token) async {
    final body = {
      'action': 'login',
      'Username': username,
      'Password': password,
      if (token != null) 'Frm_Logintoken': token,
    };
    http.Response res;
    try {
      res = await _post(endpoints.loginPath, body);
    } catch (_) {
      return false;
    }
    // Succès typique : un cookie SID est posé, ou redirection hors login.
    final gotSession =
        _cookies.containsKey('SID') || _cookies.containsKey('sid');
    final looksLikeLoginPage =
        res.body.contains('Frm_Logintoken') || res.body.contains('loginData');
    return gotSession && !looksLikeLoginPage;
  }

  String? _extractLoginToken(String html) {
    final m = RegExp(
      r'''Frm_Logintoken["']?\s*[^>]*value\s*=\s*["']?(\d+)''',
      caseSensitive: false,
    ).firstMatch(html);
    if (m != null) return m.group(1);
    // Variante : token défini en JavaScript.
    final m2 = RegExp(r'''Frm_Logintoken["']?\s*[:=]\s*["']?(\d+)''')
        .firstMatch(html);
    return m2?.group(1);
  }

  @override
  Future<void> logout() async {
    try {
      await _get(endpoints.logoutPath);
    } catch (_) {
      // Best-effort.
    }
    _cookies.clear();
  }

  // ---------------------------------------------------------------------------
  // Liste des appareils
  // ---------------------------------------------------------------------------

  @override
  Future<List<NetworkDevice>> fetchDevices() async {
    final blockedMacs = await _fetchBlockedMacs();

    for (final path in endpoints.deviceListPaths) {
      String bodyText;
      try {
        bodyText = (await _get(path)).body;
      } catch (_) {
        continue;
      }
      final devices = _parseDevices(bodyText, blockedMacs);
      if (devices.isNotEmpty) return devices;
    }

    // Aucun appareil trouvé : renvoie au moins la liste des MAC bloquées
    // connues, pour que l'utilisateur puisse les débloquer.
    return blockedMacs
        .map((m) => NetworkDevice(mac: m, isBlocked: true, isOnline: false))
        .toList();
  }

  /// Extrait les appareils d'une page HTML en repérant les adresses MAC et,
  /// pour chacune, l'IP et le nom d'hôte les plus proches dans le texte.
  ///
  /// Cette approche par motif est volontairement tolérante : elle fonctionne
  /// sur la plupart des mises en page ZTE sans dépendre d'une structure exacte.
  List<NetworkDevice> _parseDevices(String text, Set<String> blocked) {
    final macRe = RegExp(r'([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})');
    final ipRe = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})');
    final seen = <String, NetworkDevice>{};

    for (final match in macRe.allMatches(text)) {
      final mac = NetworkDevice.normalizeMac(match.group(1)!);
      if (mac.startsWith('00:00:00') || mac.startsWith('FF:FF:FF')) continue;

      // Fenêtre de texte autour de la MAC pour deviner IP + hostname.
      final start = (match.start - 200).clamp(0, text.length).toInt();
      final end = (match.end + 200).clamp(0, text.length).toInt();
      final window = text.substring(start, end);

      final ip = ipRe.firstMatch(window)?.group(1);
      final host = _guessHostname(window);

      seen.putIfAbsent(
        mac,
        () => NetworkDevice(
          mac: mac,
          ip: ip,
          hostname: host,
          isBlocked: blocked.contains(mac),
          isOnline: true,
        ),
      );
    }

    // Marque comme bloquées (et hors ligne) les MAC filtrées non revues ici.
    for (final m in blocked) {
      seen.putIfAbsent(
        m,
        () => NetworkDevice(mac: m, isBlocked: true, isOnline: false),
      );
    }
    return seen.values.toList();
  }

  String? _guessHostname(String window) {
    // Cherche des libellés courants "HostName", "DeviceName" suivis d'une valeur.
    final m = RegExp(
      r'''(?:HostName|DeviceName|Name)["'\s:=>]+([A-Za-z0-9_\-\.]{2,32})''',
      caseSensitive: false,
    ).firstMatch(window);
    return m?.group(1);
  }

  // ---------------------------------------------------------------------------
  // Filtrage MAC (blocage)
  // ---------------------------------------------------------------------------

  Future<Set<String>> _fetchBlockedMacs() async {
    try {
      final body = (await _get(endpoints.macFilterPath)).body;
      final macRe = RegExp(r'([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})');
      return macRe
          .allMatches(body)
          .map((m) => NetworkDevice.normalizeMac(m.group(1)!))
          .where((m) => !m.startsWith('00:00:00'))
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  @override
  Future<void> blockDevice(String mac) => _setMacFilter(mac, block: true);

  @override
  Future<void> unblockDevice(String mac) => _setMacFilter(mac, block: false);

  /// Ajoute/retire une MAC de la liste de filtrage (blocage) du routeur.
  ///
  /// ⚠️ Les champs POST du filtrage MAC varient beaucoup selon le firmware.
  /// Ceux ci-dessous suivent le schéma `manager_dev_*` fréquent chez ZTE.
  /// Ajuste-les avec les outils développeur du navigateur (voir [ZteEndpoints]).
  Future<void> _setMacFilter(String mac, {required bool block}) async {
    final normalized = NetworkDevice.normalizeMac(mac);
    final body = {
      'IF_ACTION': block ? 'Apply' : 'Delete',
      'Btn_add_dev': block ? 'Add' : '',
      'action': block ? 'add' : 'del',
      'MACAddress': normalized,
      'macAddr': normalized,
      'AccessControl': '1', // 1 = interdire ; adapte selon ton firmware.
      'Frm_Logintoken': '',
    };
    http.Response res;
    try {
      res = await _post(endpoints.macFilterPath, body);
    } on TimeoutException {
      throw RouterException("Le routeur n'a pas répondu au blocage.");
    } catch (e) {
      throw RouterException("Échec de l'opération de blocage : $e");
    }
    if (res.statusCode >= 400) {
      throw RouterException(
          "Le routeur a refusé le blocage (code ${res.statusCode}). Ton compte "
          "n'a peut-être pas les droits de filtrage MAC (fréquent quand Orange "
          "verrouille le compte super-admin).");
    }
  }
}
