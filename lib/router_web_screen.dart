import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'settings_store.dart';

/// Écran principal : affiche l'interface web du routeur dans l'application,
/// avec connexion automatique, tirer-pour-rafraîchir, un écran d'aide si le
/// WiFi n'est pas joignable, et un bouton qui navigue vers la page de filtrage
/// MAC (blocage) en rejouant les clics de menu.
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
    // Nettoie d'éventuels anciens raccourcis (fonction retirée).
    await _store.saveBookmarks([]);
    setState(() {
      if (url != null && url.isNotEmpty) _url = url;
      _creds = creds;
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

  // --- Aller à la page de blocage (rejoue les clics de menu) ------------------

  /// Sur ce routeur, il n'y a pas d'adresse par page (interface AJAX). Pour un
  /// « raccourci » vers le filtrage MAC, on clique par le texte des menus :
  /// Internet → Sécurité → Critères de filtrage.
  String get _gotoBlockingJs => '''
    (function(){
      function allDocs(win, acc){
        try{ acc.push(win.document); }catch(e){}
        try{ for(var i=0;i<win.frames.length;i++){ allDocs(win.frames[i], acc); } }catch(e){}
        return acc;
      }
      function fire(el){
        ['mouseover','mousedown','mouseup','click'].forEach(function(type){
          try{ el.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,view:window})); }catch(e){}
        });
      }
      function clickText(txt){
        var ds=allDocs(window, []);
        for(var d=0; d<ds.length; d++){
          var els;
          try{ els=ds[d].querySelectorAll('a,span,td,div,li,button,label,p'); }catch(e){ continue; }
          for(var i=0;i<els.length;i++){
            var e=els[i];
            var t=(e.textContent||'').replace(/\\s+/g,' ').trim();
            if(t===txt){
              var n=e;
              for(var k=0;k<6 && n;k++){
                try{ if(n.tagName==='A'||n.onclick||n.getAttribute('onclick')){ fire(n); return true; } }catch(e2){}
                n=n.parentElement;
              }
              fire(e); return true;
            }
          }
        }
        return false;
      }
      var steps=['Internet','Sécurité','Critères de filtrage'];
      var idx=0;
      (function next(){
        if(idx>=steps.length) return;
        clickText(steps[idx]); idx++;
        setTimeout(next, 1300);
      })();
    })();
  ''';

  Future<void> _goToBlocking() async {
    if (_controller == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ouverture de la page de filtrage MAC…'),
        duration: Duration(seconds: 2),
      ),
    );
    await _controller!.evaluateJavascript(source: _gotoBlockingJs);
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
    _loadUrl(_url);
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
                  case 'creds':
                    _editCredentials();
                  case 'address':
                    _changeAddress();
                }
              },
              itemBuilder: (_) => const [
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
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_url)),
              pullToRefreshController: _pullToRefresh,
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useHybridComposition: true,
                mediaPlaybackRequiresUserGesture: false,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
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
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: FilledButton.icon(
              onPressed: _goToBlocking,
              icon: const Icon(Icons.block),
              label: const Text('Bloquer un appareil (Filtre MAC)'),
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ),
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
