package com.hamza.trouvelenombre;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;

public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WebView web = new WebView(this);
        WebSettings reglages = web.getSettings();
        reglages.setJavaScriptEnabled(true);
        reglages.setDomStorageEnabled(true);
        // Le jeu est embarqué dans l'APK : il fonctionne sans connexion
        web.loadUrl("file:///android_asset/index.html");
        setContentView(web);
    }
}
