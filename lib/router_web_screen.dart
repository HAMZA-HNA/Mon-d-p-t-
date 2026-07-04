import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'settings_store.dart';

/// Écran principal : affiche l'interface web du routeur dans l'application.
///
/// Le routeur (ZTE F6600P) sert son interface en HTTPS avec un certificat
/// auto-signé : on l'accepte via [onReceivedServerTrustAuthRequest] (c'est un
/// équipement local possédé par l'utilisateur).
class RouterWebScreen extends StatefulWidget {
  const RouterWebScreen({super.key});

  @override
  State<RouterWebScreen> createState() => _RouterWebScreenState();
}

class _RouterWebScreenState extends State<RouterWebScreen> {
  static const _defaultUrl = 'https://192.168.11.1/';

  final SettingsStore _store = const SettingsStore();
  InAppWebViewController? _controller;

  String _url = _defaultUrl;
  bool _ready = false; // adresse chargée depuis le stockage
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _store.loadUrl().then((saved) {
      setState(() {
        if (saved != null && saved.isNotEmpty) _url = saved;
        _ready = true;
      });
    });
  }

  /// Complète l'adresse saisie (ajoute https:// et le / final si besoin).
  String _normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return _defaultUrl;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    if (!s.endsWith('/')) s = '$s/';
    return s;
  }

  Future<void> _goHome() async {
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(_url)));
  }

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
            helperText: "L'adresse est la « passerelle par défaut » de ton WiFi.",
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final normalized = _normalize(result);
    await _store.saveUrl(normalized);
    setState(() => _url = normalized);
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(normalized)));
  }

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
          await SystemNavigator.pop(); // quitter l'app
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mon WiFi'),
          actions: [
            IconButton(
              tooltip: 'Accueil du routeur',
              icon: const Icon(Icons.home),
              onPressed: _goHome,
            ),
            IconButton(
              tooltip: 'Recharger',
              icon: const Icon(Icons.refresh),
              onPressed: () => _controller?.reload(),
            ),
            IconButton(
              tooltip: 'Changer l\'adresse',
              icon: const Icon(Icons.settings),
              onPressed: _changeAddress,
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress < 1.0)
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_url)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useHybridComposition: true,
                  mediaPlaybackRequiresUserGesture: false,
                  // Le routeur mélange parfois http/https : on autorise.
                  mixedContentMode:
                      MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                ),
                onWebViewCreated: (c) => _controller = c,
                onProgressChanged: (c, p) =>
                    setState(() => _progress = p / 100.0),
                // Accepte le certificat auto-signé du routeur local.
                onReceivedServerTrustAuthRequest: (controller, challenge) async {
                  return ServerTrustAuthResponse(
                    action: ServerTrustAuthResponseAction.PROCEED,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
