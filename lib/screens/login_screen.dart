import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/router_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController(text: '192.168.1.1');
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // Re-remplit les champs avec les derniers identifiants saisis.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final saved = await context.read<RouterController>().loadSavedCredentials();
      if (saved != null && mounted) {
        setState(() {
          _host.text = saved.host;
          _user.text = saved.username;
          _pass.text = saved.password;
        });
      }
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await context.read<RouterController>().login(
          host: _host.text,
          username: _user.text,
          password: _pass.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RouterController>();
    final connecting = controller.status == SessionStatus.connecting;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.wifi_lock, size: 64, color: Color(0xFFFF7900)),
                    const SizedBox(height: 16),
                    Text(
                      'Contrôle du WiFi',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connecte-toi à ton routeur Orange (ZTE).\n'
                      'Ton téléphone doit être sur le même WiFi.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _host,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Adresse du routeur',
                        hintText: '192.168.1.1',
                        prefixIcon: Icon(Icons.router),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _user,
                      decoration: const InputDecoration(
                        labelText: 'Utilisateur',
                        hintText: 'admin',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pass,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Requis' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: connecting ? null : _submit,
                      icon: connecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(connecting ? 'Connexion...' : 'Se connecter'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline),
                            const SizedBox(width: 8),
                            Expanded(child: Text(controller.errorMessage!)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      "Astuce : l'utilisateur et le mot de passe sont souvent "
                      "imprimés sur l'étiquette derrière le routeur.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
