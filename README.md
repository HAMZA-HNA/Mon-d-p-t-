# WiFi Control — Orange Maroc (ZTE)

Application mobile **Flutter** pour :

- 📋 **Voir** tous les appareils connectés à ton WiFi (routeur Orange / ZTE).
- 🚫 **Bloquer** l'accès des appareils non autorisés (filtrage MAC).
- ✅ **Débloquer** un appareil quand tu veux.

L'app tourne sur **ton téléphone** et parle directement à ton routeur sur le
réseau local (`http://192.168.1.1`). Rien ne passe par Internet, aucune donnée
n'est envoyée à un serveur externe.

---

## ⚠️ À lire avant de commencer

1. **Ton téléphone doit être connecté au WiFi du routeur** pour que l'app puisse
   le joindre. En 4G/5G ça ne marche pas.
2. **Login admin du routeur** : l'utilisateur et le mot de passe sont
   généralement imprimés sur l'**étiquette derrière le routeur** (souvent
   `admin` / un mot de passe, ou `admin` / `admin`).
3. **Droits d'administration** : sur certains routeurs Orange, le compte fourni
   au client a des droits limités. Le **filtrage MAC** (blocage) peut nécessiter
   un compte super-admin qu'Orange verrouille parfois. Si le blocage est refusé,
   l'app te l'indiquera clairement — ce n'est pas un bug de l'app mais une
   limite de droits côté routeur.
4. **Les firmwares ZTE varient** (ZXHN F660, F670, F668, H168N…). Le login et la
   lecture des appareils sont écrits pour les cas les plus courants. Si ça ne
   marche pas du premier coup sur ton modèle, voir la section
   [« Adapter à ton modèle »](#adapter-à-ton-modèle-zte).

---

## Installation

### Prérequis
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installé
  (`flutter --version` doit répondre).
- Un téléphone Android (ou l'émulateur) — voir la note iOS plus bas.

### Étapes

```bash
# 1. Se placer dans le dossier du projet
cd orange-wifi

# 2. Générer les dossiers de plateforme (android/, ios/…) autour du code
flutter create .

# 3. Installer les dépendances
flutter pub get

# 4. Brancher ton téléphone (mode développeur + débogage USB activé) puis :
flutter run
```

> `flutter create .` ne touche pas au dossier `lib/` ni au `pubspec.yaml`
> existants : il ajoute seulement le code natif des plateformes.

### Étape indispensable : autoriser le HTTP local (Android)

Depuis Android 9, le trafic HTTP **non chiffré** est bloqué par défaut. Comme le
routeur n'expose que `http://`, il faut l'autoriser pour les adresses locales.

Le fichier est déjà fourni :
`android/app/src/main/res/xml/network_security_config.xml`.

Il faut juste le référencer dans le manifeste. Ouvre
`android/app/src/main/AndroidManifest.xml` et, dans la balise `<application …>`,
ajoute l'attribut `android:networkSecurityConfig` :

```xml
<application
    android:label="orange_wifi_control"
    android:networkSecurityConfig="@xml/network_security_config"
    ... >
```

La permission Internet est aussi requise (Flutter l'ajoute en debug, mais
pour une version release, ajoute avant la balise `<application>`) :

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### Note iOS

Le code Dart est 100 % compatible iOS. Pour tester sur iPhone il faut un Mac
avec Xcode, et autoriser le HTTP local via une clé `NSAppTransportSecurity`
(`NSAllowsLocalNetworking`) dans `ios/Runner/Info.plist`. L'app demandera aussi
la permission « réseau local » au premier lancement.

---

## Utilisation

1. Lance l'app → écran de connexion.
2. Saisis l'adresse (`192.168.1.1` par défaut), l'utilisateur et le mot de passe.
3. L'app affiche deux onglets :
   - **Connectés** : les appareils actuellement sur ton WiFi.
   - **Bloqués** : les appareils dont tu as coupé l'accès.
4. Bouton **Bloquer** / **Débloquer** sur chaque appareil (avec confirmation).
5. Tire vers le bas pour rafraîchir la liste.

Les identifiants sont mémorisés de façon **sécurisée** (Keystore Android /
Keychain iOS) pour la reconnexion automatique. Le bouton « déconnexion » les
efface.

---

## Adapter à ton modèle ZTE

Les URLs et champs de l'interface web diffèrent selon le firmware. Tout est
centralisé dans **un seul fichier** : `lib/services/zte_router_client.dart`,
classe `ZteEndpoints`.

Pour trouver les bonnes valeurs pour TON routeur :

1. Depuis un PC connecté au WiFi, ouvre `http://192.168.1.1` dans Chrome.
2. Appuie sur **F12** → onglet **Network / Réseau**.
3. Connecte-toi, puis va sur la page « Appareils connectés » / « LAN » et sur la
   page « Filtrage MAC » / « Contrôle d'accès ».
4. Observe les requêtes (URL et champs envoyés) et recopie-les dans
   `ZteEndpoints` :
   - `deviceListPaths` → la page qui liste les appareils.
   - `macFilterPath` → la page qui gère le filtrage MAC.
   - dans `_setMacFilter`, ajuste les champs du formulaire (`IF_ACTION`,
     `MACAddress`, etc.) selon ce que tu vois partir.

La lecture des appareils utilise une détection **par motif** (elle repère les
adresses MAC, IP et noms dans la page), donc elle est assez tolérante aux
différences de mise en page.

---

## Ajouter un autre routeur (Huawei, Sagemcom…)

L'architecture est faite pour ça :

- `lib/services/router_client.dart` définit l'interface commune `RouterClient`.
- `lib/services/zte_router_client.dart` en est l'implémentation ZTE.

Pour un autre modèle, crée `huawei_router_client.dart` qui implémente
`RouterClient`, puis ajoute un `case` dans `RouterController._buildClient`.
**Aucun écran à modifier.**

---

## Architecture

```
lib/
  models/
    network_device.dart        # Modèle d'un appareil (MAC, IP, hostname…)
  services/
    router_client.dart         # Interface commune à tous les routeurs
    zte_router_client.dart     # Implémentation ZTE (login, liste, blocage)
    credentials_store.dart     # Stockage sécurisé des identifiants
  state/
    router_controller.dart     # État de l'app (session + appareils + actions)
  screens/
    login_screen.dart          # Écran de connexion
    home_screen.dart           # Onglets Connectés / Bloqués
  widgets/
    device_tile.dart           # Ligne d'un appareil + bouton bloquer
  main.dart                    # Point d'entrée
test/
  network_device_test.dart     # Tests unitaires
```

Lancer les tests : `flutter test`.

---

## Confidentialité & sécurité

- Aucune connexion Internet : l'app ne parle qu'à ton routeur en local.
- Le mot de passe est stocké chiffré via le stockage sécurisé du système.
- Le code est ouvert : tu peux tout vérifier.

Utilise cette app uniquement sur **ton propre réseau**.
