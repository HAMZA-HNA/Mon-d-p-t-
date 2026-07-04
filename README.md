# Mon WiFi — Orange Maroc (ZTE)

Application mobile **Flutter** qui intègre l'interface de ton routeur Orange
(ZTE) directement dans une app, pour :

- 📋 **Voir** les appareils connectés à ton WiFi.
- 🚫 **Bloquer** l'accès des appareils non autorisés.
- 🔐 **Connexion automatique** : l'app remplit l'utilisateur et le mot de passe.
- ⭐ **Raccourcis** vers tes pages préférées (appareils, blocage…).
- 🔄 **Tirer pour rafraîchir** et écran d'aide si le WiFi n'est pas joignable.

L'app affiche la **vraie interface de ton routeur** (celle accessible sur
`https://192.168.11.1`) dans une WebView. Elle accepte automatiquement le
certificat auto-signé du routeur — ce qui évite l'erreur de sécurité qu'on a
sinon dans un navigateur — et retient l'adresse du routeur d'une fois sur
l'autre.

> **Pourquoi cette approche ?** Les routeurs Orange F6600P utilisent un login
> et un affichage des appareils entièrement en JavaScript/AJAX, propres au
> firmware et difficiles à reproduire de façon fiable. Intégrer l'interface
> officielle du routeur donne un résultat qui marche tout de suite et reste
> stable.

---

## Utilisation

1. Ouvre l'app → l'interface de ton routeur s'affiche.
2. Connecte-toi avec l'utilisateur / mot de passe (sur l'étiquette du routeur,
   souvent `user` + un mot de passe).
3. Va dans la rubrique des appareils (ex. **Périphériques WLAN** / **Réseau
   local**) pour voir qui est connecté.
4. Pour bloquer un appareil, utilise le **contrôle d'accès / filtrage MAC** du
   routeur.

Barre du haut :
- 🏠 **Accueil** : revient à la page d'accueil du routeur.
- 🔄 **Recharger** : recharge la page.
- ⚙️ **Réglages** : change l'adresse du routeur (mémorisée).

> Ton téléphone doit être connecté au **WiFi du routeur** (pas en 4G/5G).

---

## Installation (développement)

### Prérequis
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installé.
- Android Studio (SDK Android + licences acceptées).
- Un téléphone Android en mode développeur (USB ou débogage sans fil).

### Lancer

```bash
git clone https://github.com/HAMZA-HNA/Mon-d-p-t-.git orange-wifi
cd orange-wifi
git checkout claude/orange-router-wifi-control-ti6hgi
flutter pub get
flutter run
```

Pour un APK installable à partager :

```bash
flutter build apk --release
# Résultat : build/app/outputs/flutter-apk/app-release.apk
```

Le dossier `android/` est déjà généré et configuré (permission Internet).

---

## Architecture

```
lib/
  main.dart              # Point d'entrée + thème
  router_web_screen.dart # WebView de l'interface routeur (accepte le certificat)
  settings_store.dart    # Mémorise l'adresse du routeur
```

Dépendances clés :
- `flutter_inappwebview` — WebView avec gestion du certificat auto-signé.
- `flutter_secure_storage` — mémorisation de l'adresse.

---

## Confidentialité & sécurité

- L'app ne parle qu'à ton routeur, en local. Rien ne passe par Internet.
- Le certificat auto-signé n'est accepté que parce qu'il s'agit de **ton**
  routeur sur **ton** réseau local.

Utilise cette app uniquement sur ton propre réseau.
