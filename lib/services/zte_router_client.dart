import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/network_device.dart';
import 'router_client.dart';

/// Points d'entrée (URLs / champs) de l'interface web ZTE.
///
/// ⚠️ Les firmwares ZTE (ZXHN F660, F670, F6600P, H168N...) diffèrent.
/// Les valeurs ci-dessous couvrent les cas les plus courants. Pour trouver
/// celles de TON modèle : PC → http(s)://<routeur> → F12 → onglet Network →
/// observe les requêtes lors du login / de l'affichage des appareils.
class ZteEndpoints {
  const ZteEndpoints({
    this.loginPath = '/',
    this.logoutPath = '/?_type=loginData&_tag=logout&_=0',
    this.deviceListPaths = const [
      '/getpage.gch?pid=1002&nextpage=net_dhcp_dynamic_t.gch',
      '/getpage.gch?pid=1002&nextpage=Localnet_LANDevice_t.gch',
      '/getpage.gch?pid=1002&nextpage=access_dev_t.gch',
      '/common_page/lanMgrList_lua.lua',
      '/?_type=menuData&_tag=localNetStatus_lua.lua',
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
/// Deux particularités gérées ici :
///  - Le routeur sert souvent son interface en **HTTPS avec un certificat
///    auto-signé** : on l'accepte (c'est un équipement local possédé par
///    l'utilisateur), sinon la connexion échoue avec CERTIFICATE_VERIFY_FAILED.
///  - Le package `http` ne gère pas les cookies : on maintient la session
///    manuellement (cookie `SID` posé après le login).
class ZteRouterClient implements RouterClient {
  ZteRouterClient({
    required this.host,
    this.preferHttps = true,
    this.endpoints = const ZteEndpoints(),
    http.Client? httpClient,
    Duration? timeout,
  })  : _http = httpClient ?? _createTlsTolerantClient(),
        _timeout = timeout ?? const Duration(seconds: 12);

  @override
  final String host;

  /// Essaie HTTPS d'abord (cas des F6600P / firmwares récents).
  final bool preferHttps;
  final ZteEndpoints endpoints;
  final http.Client _http;
  final Duration _timeout;

  /// Schéma retenu après détection (`https` ou `http`).
  String _scheme = 'https';

  /// Cookies de session, sous forme `nom=valeur`.
  final Map<String, String> _cookies = {};

  /// Dernier diagnostic de recherche des appareils (pages explorées).
  String lastFetchDiag = '';

  /// Traces de diagnostic, jointes aux messages d'erreur pour aider au débogage.
  final List<String> _diag = [];

  /// Client HTTP qui accepte le certificat auto-signé du routeur local.
  static http.Client _createTlsTolerantClient() {
    final io = HttpClient();
    io.connectionTimeout = const Duration(seconds: 12);
    io.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return IOClient(io);
  }

  Uri _uri(String path) => Uri.parse('$_scheme://$host$path');

  String get _cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  void _absorbCookies(http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return;
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
        .get(_uri(path), headers: {
          'Cookie': _cookieHeader,
          'Referer': '$_scheme://$host/',
        })
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
            'Referer': '$_scheme://$host/',
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
    _diag.clear();
    _cookies.clear();

    // 1. Détecte le bon schéma (HTTPS puis HTTP, ou l'inverse) en chargeant la
    //    page de login.
    await _detectSchemeAndFetchLogin();

    // Variantes de hachage du mot de passe rencontrées selon le firmware ZTE.
    // Le token étant souvent à usage unique, on le re-récupère avant CHAQUE
    // tentative (sinon les essais suivants échouent avec un token périmé).
    final schemes = <String, String Function(String pw, String token)>{
      // Firmwares récents (F6600P/F670L) : double SHA256, sel = token.
      'sha(sha(pw)+tok)': (pw, tok) => _sha(_sha(pw) + tok),
      // Ancienne variante : SHA256(mot_de_passe + token).
      'sha(pw+tok)': (pw, tok) => _sha(pw + tok),
      // Sans token.
      'sha(pw)': (pw, tok) => _sha(pw),
      'plain': (pw, tok) => pw,
    };

    var dumpedContext = false;
    for (final entry in schemes.entries) {
      String pageBody;
      try {
        pageBody = (await _get(endpoints.loginPath)).body;
      } catch (_) {
        continue;
      }
      final token = _extractToken(pageBody);
      // Si on ne trouve pas le jeton, on affiche une fois le texte brut autour
      // des mots-clés pour voir dans quel format le firmware le fournit.
      if (token == null && !dumpedContext) {
        dumpedContext = true;
        _diag.add('CTX Frm_Logintoken=«${_context(pageBody, "Frm_Logintoken", 110)}»');
        _diag.add('CTX sessionTOKEN=«${_context(pageBody, "sessionTOKEN", 90)}»');
      }
      final hashed = entry.value(password, token ?? '');
      _diag.add('try ${entry.key} tok=${token ?? "∅"}');
      if (await _attemptLogin(username, hashed, token)) return;
    }

    throw RouterException(
      "Login refusé par le routeur.\n\n"
      "Vérifie l'utilisateur (souvent « user » ou « admin ») et le mot de "
      "passe de l'étiquette. Si un seul appareil peut être connecté à l'admin "
      "à la fois, déconnecte les autres sessions.\n\n"
      "Diagnostic : ${_diag.join(' | ')}",
    );
  }

  /// Charge la page de login en testant HTTPS puis HTTP (ordre selon
  /// [preferHttps]). Mémorise le schéma qui marche.
  Future<String> _detectSchemeAndFetchLogin() async {
    final order = preferHttps ? ['https', 'http'] : ['http', 'https'];
    Object? lastError;
    for (final scheme in order) {
      _scheme = scheme;
      try {
        final res = await _http
            .get(Uri.parse('$scheme://$host${endpoints.loginPath}'))
            .timeout(_timeout);
        _absorbCookies(res);
        final kw = [
          'Frm_Logintoken',
          'logintoken',
          'lgToken',
          'sessionTOKEN',
          'getServerToken',
          'RandCount',
          '_sessionid'
        ].where((k) => res.body.toLowerCase().contains(k.toLowerCase())).toList();
        _diag.add('$scheme:${res.statusCode} page=${res.body.length}b '
            'kw[${kw.join(",")}]');
        return res.body;
      } on TimeoutException {
        lastError = 'timeout($scheme)';
        _diag.add('timeout($scheme)');
      } catch (e) {
        lastError = e;
        _diag.add('$scheme:err');
      }
    }
    throw RouterException(
      "Impossible de joindre le routeur à l'adresse « $host ».\n\n"
      "Vérifie que ton téléphone est bien connecté au WiFi de ce routeur et "
      "que l'adresse est correcte (souvent 192.168.1.1 ou 192.168.11.1 — c'est "
      "la « passerelle par défaut » de ta connexion WiFi).\n\n"
      "Détail : $lastError",
    );
  }

  String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

  /// Renvoie le texte autour de la première occurrence (insensible à la casse)
  /// de [keyword], pour diagnostiquer le format d'un jeton dans la page.
  String _context(String text, String keyword, int span) {
    final i = text.toLowerCase().indexOf(keyword.toLowerCase());
    if (i < 0) return 'absent';
    final s = (i - 15).clamp(0, text.length).toInt();
    final e = (i + span).clamp(0, text.length).toInt();
    return text.substring(s, e).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Extrait la valeur numérique de l'input caché `Frm_Logintoken` de la page
  /// de login ZTE. Gère les deux ordres d'attributs (id avant/après value).
  String? _extractToken(String text) {
    // Cas courant : <input ... name/id="Frm_Logintoken" ... value="12345">
    final m1 = RegExp(
      'Frm_Logintoken[^>]{0,160}?value\\s*=\\s*["\']?(\\d{3,})',
      caseSensitive: false,
    ).firstMatch(text);
    if (m1 != null) return m1.group(1);
    // Cas inversé : value="12345" ... Frm_Logintoken
    final m2 = RegExp(
      'value\\s*=\\s*["\']?(\\d{3,})["\']?[^>]{0,160}?Frm_Logintoken',
      caseSensitive: false,
    ).firstMatch(text);
    if (m2 != null) return m2.group(1);
    // Cas JS : Frm_Logintoken = "12345" ou 'lgToken':'12345'
    final m3 = RegExp(
      '(?:Frm_Logintoken|lgToken|sessionTOKEN)["\']?\\s*[:=]\\s*["\']?(\\d{3,})',
      caseSensitive: false,
    ).firstMatch(text);
    return m3?.group(1);
  }

  Future<bool> _attemptLogin(
      String username, String password, String? token) async {
    final randomNum = (Random().nextDouble() * 1e8).floor().toString();
    final body = {
      'action': 'login',
      'Username': username,
      'Password': password,
      'UserRandomNum': randomNum,
      if (token != null) 'Frm_Logintoken': token,
    };
    http.Response res;
    try {
      res = await _post(endpoints.loginPath, body);
    } catch (e) {
      _diag.add('post:err');
      return false;
    }
    // Détection de succès : la réponse ne doit plus être le formulaire de
    // login, ET doit soit contenir un marqueur de page authentifiée, soit être
    // une redirection vers l'accueil.
    final b = res.body.toLowerCase();
    final isLoginForm = b.contains('frm_logintoken') || b.contains('frm_username');
    final hasAuthMarker = b.contains('logout') ||
        b.contains('deconnexion') ||
        b.contains('topologie') ||
        b.contains('menuview') ||
        b.contains('gestion et diagnostic');
    final isRedirect = res.statusCode == 301 ||
        res.statusCode == 302 ||
        b.contains('top.location') ||
        b.contains('window.location');
    final ok = res.statusCode < 400 && !isLoginForm && (hasAuthMarker || isRedirect);
    _diag.add('login:${res.statusCode} ck[${_cookies.keys.join(",")}] '
        'form=$isLoginForm auth=$hasAuthMarker rdr=$isRedirect ok=$ok');
    return ok;
  }

  @override
  Future<void> logout() async {
    try {
      await _get(endpoints.logoutPath);
    } catch (_) {}
    _cookies.clear();
  }

  // ---------------------------------------------------------------------------
  // Liste des appareils
  // ---------------------------------------------------------------------------

  /// Explore l'interface du routeur pour trouver la page qui liste les
  /// appareils. Plutôt que de deviner l'URL exacte (elle varie selon le
  /// firmware Orange), on part de la racine et on suit les liens/frames en
  /// cherchant la page contenant le plus d'adresses MAC.
  @override
  Future<List<NetworkDevice>> fetchDevices() async {
    final diag = <String>[];
    final blockedMacs = await _fetchBlockedMacs();

    final visited = <String>{};
    final queue = <String>['/', ...endpoints.deviceListPaths];
    List<NetworkDevice> best = [];
    var fetches = 0;

    while (queue.isNotEmpty && fetches < 15) {
      final path = queue.removeAt(0);
      if (!visited.add(path) || _isUnsafeLink(path)) continue;

      http.Response r;
      try {
        r = await _get(path);
      } catch (_) {
        diag.add('${_short(path)}:err');
        continue;
      }
      fetches++;

      final devices = _parseDevices(r.body, blockedMacs);
      final active = devices.where((d) => !d.isBlocked).length;
      diag.add('${_short(path)}:${r.statusCode}:${active}d');
      if (devices.length > best.length) best = devices;

      // Assez d'appareils trouvés : inutile de continuer à explorer.
      if (active >= 2) break;

      for (final u in _discoverLinks(r.body)) {
        if (!visited.contains(u)) queue.add(u);
      }
    }

    lastFetchDiag = diag.join(' | ');

    final map = {for (final d in best) d.mac: d};
    for (final m in blockedMacs) {
      map.putIfAbsent(
          m, () => NetworkDevice(mac: m, isBlocked: true, isOnline: false));
    }
    return map.values.toList();
  }

  /// Liens/frames à explorer, extraits d'une page HTML (chemins internes
  /// pointant vers des pages `.gch` / `.lua` / `.html` / `.asp`).
  Iterable<String> _discoverLinks(String html) {
    final found = <String>{};
    final re = RegExp(
      '''(?:src|href|url|location)\\s*[=:]\\s*["']?([^"'\\s>()]+\\.(?:gch|lua|html?|asp)(?:\\?[^"'\\s>()]*)?)''',
      caseSensitive: false,
    );
    final re2 = RegExp('''getpage\\.gch\\?[^"'\\s>()]+''', caseSensitive: false);
    for (final m in [
      ...re.allMatches(html).map((m) => m.group(1)!),
      ...re2.allMatches(html).map((m) => m.group(0)),
    ]) {
      var u = m!.trim();
      if (u.startsWith('http') || u.startsWith('//')) continue; // externe
      if (!u.startsWith('/')) u = '/$u';
      if (!_isUnsafeLink(u)) found.add(u);
    }
    return found;
  }

  /// Évite d'explorer les liens destructeurs (déconnexion, reboot, reset...)
  /// qui casseraient la session ou la config.
  bool _isUnsafeLink(String path) {
    final p = path.toLowerCase();
    return p.contains('logout') ||
        p.contains('logoff') ||
        p.contains('reboot') ||
        p.contains('restart') ||
        p.contains('reset') ||
        p.contains('restore') ||
        p.contains('save');
  }

  String _short(String path) =>
      path.length <= 34 ? path : '…${path.substring(path.length - 33)}';

  List<NetworkDevice> _parseDevices(String text, Set<String> blocked) {
    final macRe = RegExp(r'([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})');
    final ipRe = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})');
    final seen = <String, NetworkDevice>{};

    for (final match in macRe.allMatches(text)) {
      final mac = NetworkDevice.normalizeMac(match.group(1)!);
      if (mac.startsWith('00:00:00') || mac.startsWith('FF:FF:FF')) continue;

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

    for (final m in blocked) {
      seen.putIfAbsent(
        m,
        () => NetworkDevice(mac: m, isBlocked: true, isOnline: false),
      );
    }
    return seen.values.toList();
  }

  String? _guessHostname(String window) {
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

  Future<void> _setMacFilter(String mac, {required bool block}) async {
    final normalized = NetworkDevice.normalizeMac(mac);
    final body = {
      'IF_ACTION': block ? 'Apply' : 'Delete',
      'Btn_add_dev': block ? 'Add' : '',
      'action': block ? 'add' : 'del',
      'MACAddress': normalized,
      'macAddr': normalized,
      'AccessControl': '1',
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
          "n'a peut-être pas les droits de filtrage MAC (fréquent quand le "
          "compte « user » d'Orange est limité).");
    }
  }
}
