import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'settings_store.dart';

/// Écran principal : affiche l'interface web du routeur dans l'application,
/// avec connexion automatique, raccourcis, tirer-pour-rafraîchir et un écran
/// d'aide si le téléphone n'est pas connecté au bon WiFi.
class RouterWebScreen extends StatefulWidget {
  const RouterWebScreen({super.key});

  @override
  State<RouterWebScreen> createState() => _RouterWebScreenState();
}

class _RouterWebScreenState extends State<RouterWebScreen> {
  static const _defaultUrl = 'https://192.168.11.1/';
  static const _orange = Color(0xFFFF7900);

  final SettingsStore _store = const SettingsStore();
  InAppWebViewController? _controller;
  PullToRefreshController? _pullToRefresh;

  String _url = _defaultUrl;
  (String, String)? _creds; // (utilisateur, mot de passe)
  List<Bookmark> _bookmarks = [];

  bool _ready = false;
  bool _loadError = false;
  bool _autoSubmitted = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _pullToRefresh = PullToRefreshController(
      settings: PullToRefreshSettings(color: _orange),
      onRefresh: () => _controller?.reload(),
    );
    _load();
  }

  Future<void> _load() async {
    final url = await _store.loadUrl();
    final creds = await _store.loadCredentials();
    final bm = await _store.loadBookmarks();
    setState(() {
      if (url != null && url.isNotEmpty) _url = url;
      _creds = creds;
      _bookmarks = bm;
      _ready = true;
    });
  }

  String _normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return _defaultUrl;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    if (!s.endsWith('/')) s = '$s/';
    return s;
  }

  void _loadUrl(String url) {
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  // --- Connexion automatique -------------------------------------------------

  /// JS injecté sur la page de login pour remplir (et éventuellement soumettre)
  /// les identifiants. Best-effort : s'il n'y a pas de champ de login, ne fait
  /// rien.
  String _autoFillJs(String user, String pass, bool submit) {
    final u = jsonEncode(user);
    final p = jsonEncode(pass);
    final sub = submit ? 'true' : 'false';
    return '''
    (function(){
      try {
        var uf = document.getElementById('Frm_Username')
              || document.querySelector('input[name="Frm_Username"]')
              || document.querySelector('input[type="text"]');
        var pf = document.getElementById('Frm_Password')
              || document.querySelector('input[name="Frm_Password"]')
              || document.querySelector('input[type="password"]');
        if(!uf || !pf){ return 'nofields'; }
        uf.value = $u; pf.value = $p;
        uf.dispatchEvent(new Event('input',{bubbles:true}));
        pf.dispatchEvent(new Event('input',{bubbles:true}));
        if($sub){
          var b = document.getElementById('LoginId')
               || document.querySelector('[onclick*="ogin"]')
               || document.querySelector('input[type="submit"]')
               || document.querySelector('button');
          if(b){ b.click(); return 'submitted'; }
          return 'filled';
        }
        return 'filled';
      } catch(e){ return 'err'; }
    })();
    ''';
  }

  Future<void> _tryAutoLogin(InAppWebViewController c) async {
    final creds = _creds;
    if (creds == null) return;
    final res = await c.evaluateJavascript(
      source: _autoFillJs(creds.$1, creds.$2, !_autoSubmitted),
    );
    if (res != null && res.toString().contains('submitted')) {
      _autoSubmitted = true;
    }
  }

  // --- Dialogues -------------------------------------------------------------

  Future<void> _changeAddress() async {
    final ctrl = TextEditingController(text: _url);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adresse du routeur'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '192.168.11.1',
            border: OutlineInputBorder(),
            helperText: "La « passerelle par défaut » de ton WiFi.",
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Ouvrir')),
        ],
      ),
    );
    if (result == null) return;
    final normalized = _normalize(result);
    await _store.saveUrl(normalized);
    setState(() {
      _url = normalized;
      _autoSubmitted = false;
    });
    _loadUrl(normalized);
  }

  Future<void> _editCredentials() async {
    final userCtrl = TextEditingController(text: _creds?.$1 ?? 'user');
    final passCtrl = TextEditingController(text: _creds?.$2 ?? '');
    var obscure = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Connexion automatique'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "L'app remplira l'utilisateur et le mot de passe toute seule "
                "sur la page du routeur.",
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Utilisateur',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setD(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await _store.saveCredentials(userCtrl.text.trim(), passCtrl.text);
    setState(() {
      _creds = (userCtrl.text.trim(), passCtrl.text);
      _autoSubmitted = false;
    });
    _loadUrl(_url); // recharge la page de login pour se connecter tout de suite
  }

  Future<void> _addBookmarkForCurrentPage() async {
    final current = (await _controller?.getUrl())?.toString() ?? _url;
    final title = (await _controller?.getTitle()) ?? 'Raccourci';
    if (!mounted) return;
    final nameCtrl = TextEditingController(text: title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajouter un raccourci'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom du raccourci',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(current,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ajouter')),
        ],
      ),
    );
    if (ok != true) return;
    final updated = [
      ..._bookmarks,
      Bookmark(name: nameCtrl.text.trim().isEmpty ? 'Raccourci' : nameCtrl.text.trim(), url: current),
    ];
    await _store.saveBookmarks(updated);
    setState(() => _bookmarks = updated);
  }

  Future<void> _removeBookmark(Bookmark b) async {
    final updated = _bookmarks.where((x) => x.url != b.url || x.name != b.name).toList();
    await _store.saveBookmarks(updated);
    setState(() => _bookmarks = updated);
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          await c.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _orange,
          foregroundColor: Colors.white,
          title: const Text('Mon WiFi'),
          actions: [
            IconButton(
              tooltip: 'Accueil',
              icon: const Icon(Icons.home),
              onPressed: () => _loadUrl(_url),
            ),
            IconButton(
              tooltip: 'Recharger',
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller?.reload(),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'bookmark':
                    _addBookmarkForCurrentPage();
                  case 'address':
                    _changeAddress();
                  case 'creds':
                    _editCredentials();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'bookmark',
                    child: ListTile(
                        leading: Icon(Icons.star_border),
                        title: Text('Ajouter un raccourci'))),
                PopupMenuItem(
                    value: 'creds',
                    child: ListTile(
                        leading: Icon(Icons.password),
                        title: Text('Connexion automatique'))),
                PopupMenuItem(
                    value: 'address',
                    child: ListTile(
                        leading: Icon(Icons.router),
                        title: Text('Adresse du routeur'))),
              ],
            ),
          ],
          bottom: _progress < 1.0
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    backgroundColor: Colors.transparent,
                  ),
                )
              : null,
        ),
        body: Column(
          children: [
            if (_bookmarks.isNotEmpty) _shortcutsBar(),
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(_url)),
                    pullToRefreshController: _pullToRefresh,
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      useHybridComposition: true,
                      mediaPlaybackRequiresUserGesture: false,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    ),
                    onWebViewCreated: (c) => _controller = c,
                    onProgressChanged: (c, p) =>
                        setState(() => _progress = p / 100.0),
                    onReceivedServerTrustAuthRequest: (c, challenge) async =>
                        ServerTrustAuthResponse(
                            action: ServerTrustAuthResponseAction.PROCEED),
                    onLoadStop: (c, url) async {
                      _pullToRefresh?.endRefreshing();
                      setState(() => _loadError = false);
                      await _tryAutoLogin(c);
                    },
                    onReceivedError: (c, request, error) {
                      _pullToRefresh?.endRefreshing();
                      if (request.isForMainFrame ?? false) {
                        setState(() => _loadError = true);
                      }
                    },
                  ),
                  if (_loadError) _errorOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcutsBar() {
    return Container(
      height: 48,
      color: _orange.withValues(alpha: 0.08),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: _bookmarks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final b = _bookmarks[i];
          return GestureDetector(
            onLongPress: () async {
              final del = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Supprimer « ${b.name} » ?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Supprimer')),
                  ],
                ),
              );
              if (del == true) _removeBookmark(b);
            },
            child: ActionChip(
              avatar: const Icon(Icons.bolt, size: 18),
              label: Text(b.name),
              onPressed: () => _loadUrl(b.url),
              tooltip: b.url,
            ),
          );
        },
      ),
    );
  }

  Widget _errorOverlay() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 72, color: _orange),
          const SizedBox(height: 16),
          const Text(
            'Impossible de joindre le routeur',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            "Vérifie que ton téléphone est bien connecté au WiFi de ton "
            "routeur (pas en 4G/5G), puis réessaie.\n\nAdresse : $_url",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () {
                  setState(() => _loadError = false);
                  _controller?.reload();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
              OutlinedButton.icon(
                onPressed: _changeAddress,
                icon: const Icon(Icons.router),
                label: const Text('Changer l\'adresse'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
