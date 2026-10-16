package com.davidefanizza.meteora;

import android.Manifest;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.webkit.GeolocationPermissions;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Meteora per Android: la web app (sempre aggiornata da GitHub Pages) dentro una finestra nativa.
 * La musica suona nell'app Spotify; Meteora la comanda.
 */
public class MainActivity extends Activity {

    static final String HOME = "https://davidefanizza-dotcom.github.io/meteora/";
    private static final int REQ_FILE = 1, REQ_LOC = 2, REQ_NOTIF = 3;

    private WebView web;
    private ValueCallback<Uri[]> fileCallback;
    private GeolocationPermissions.Callback geoCallback;
    private String geoOrigin;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#0B0D12"));
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setGeolocationEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setUserAgentString(s.getUserAgentString() + " MeteoraAndroid/1.0");

        web.addJavascriptInterface(new Bridge(), "MeteoraAndroid");

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                return handleUrl(req.getUrl());
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onGeolocationPermissionsShowPrompt(String origin, GeolocationPermissions.Callback callback) {
                if (hasLocation()) {
                    callback.invoke(origin, true, false);
                } else {
                    geoOrigin = origin;
                    geoCallback = callback;
                    requestPermissions(new String[]{Manifest.permission.ACCESS_COARSE_LOCATION,
                            Manifest.permission.ACCESS_FINE_LOCATION}, REQ_LOC);
                }
            }

            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (fileCallback != null) fileCallback.onReceiveValue(null);
                fileCallback = callback;
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("*/*");
                try {
                    startActivityForResult(Intent.createChooser(i, "Scegli il backup"), REQ_FILE);
                } catch (ActivityNotFoundException e) {
                    fileCallback = null;
                    return false;
                }
                return true;
            }
        });

        if (state != null) web.restoreState(state);
        else web.loadUrl(HOME);
    }

    /** true = gestito fuori dalla WebView. */
    private boolean handleUrl(Uri u) {
        String scheme = u.getScheme() == null ? "" : u.getScheme();
        String host = u.getHost() == null ? "" : u.getHost();
        if (scheme.equals("http") || scheme.equals("https")) {
            // Meteora e l'accesso a Spotify restano dentro l'app
            if (host.equals("davidefanizza-dotcom.github.io") || (host.endsWith("spotify.com") && !host.equals("open.spotify.com"))) {
                return false;
            }
            openExternal(u);
            return true;
        }
        openExternal(u);
        return true;
    }

    private void openExternal(Uri u) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, u));
        } catch (ActivityNotFoundException e) {
            Toast.makeText(this, "spotify".equals(u.getScheme()) ? "Installa l'app Spotify" : "Nessuna app per aprire il link", Toast.LENGTH_LONG).show();
        }
    }

    private boolean hasLocation() {
        return checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        if (code == REQ_LOC && geoCallback != null) {
            geoCallback.invoke(geoOrigin, hasLocation(), false);
            geoCallback = null;
        }
    }

    @Override
    protected void onActivityResult(int code, int result, Intent data) {
        if (code == REQ_FILE && fileCallback != null) {
            Uri[] r = null;
            if (result == RESULT_OK && data != null && data.getData() != null) r = new Uri[]{data.getData()};
            fileCallback.onReceiveValue(r);
            fileCallback = null;
            return;
        }
        super.onActivityResult(code, result, data);
    }

    @Override
    public void onBackPressed() {
        // Prima chiude finestre/schermate aperte in Meteora, poi torna indietro, poi va in sottofondo.
        web.evaluateJavascript("(window.__meteoraBack&&window.__meteoraBack())?'1':'0'", v -> {
            if (v != null && v.contains("1")) return;
            if (web.canGoBack()) web.goBack();
            else moveTaskToBack(true);
        });
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
        web.resumeTimers();
    }

    // In pausa NON fermiamo i timer: servono a seguire la coda del Meteo Mix e dei Momenti.

    @Override
    protected void onDestroy() {
        stopService(new Intent(this, KeepAliveService.class));
        web.destroy();
        super.onDestroy();
    }

    /** Funzioni chiamabili da Meteora (window.MeteoraAndroid). */
    class Bridge {
        @JavascriptInterface
        public boolean saveFile(String name, String text) {
            try {
                byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
                if (Build.VERSION.SDK_INT >= 29) {
                    ContentValues v = new ContentValues();
                    v.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
                    v.put(MediaStore.MediaColumns.MIME_TYPE, "application/json");
                    v.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Meteora");
                    Uri uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                    if (uri == null) throw new Exception("uri");
                    try (OutputStream o = getContentResolver().openOutputStream(uri)) { o.write(bytes); }
                } else {
                    File dir = new File(getExternalFilesDir(null), "Meteora");
                    dir.mkdirs();
                    try (FileOutputStream o = new FileOutputStream(new File(dir, name))) { o.write(bytes); }
                }
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "Salvato in Download/Meteora", Toast.LENGTH_LONG).show());
                return true;
            } catch (Exception e) {
                runOnUiThread(() -> Toast.makeText(MainActivity.this, "Salvataggio non riuscito", Toast.LENGTH_LONG).show());
                return false;
            }
        }

        /** Tiene viva l'app in sottofondo durante Meteo Mix e Momenti. */
        @JavascriptInterface
        public void keepAlive(boolean on) {
            runOnUiThread(() -> {
                Intent i = new Intent(MainActivity.this, KeepAliveService.class);
                if (on) {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQ_NOTIF);
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(i); else startService(i);
                    } catch (Exception ignored) { }
                } else {
                    stopService(i);
                }
            });
        }

        @JavascriptInterface
        public void openSpotify() {
            runOnUiThread(() -> {
                Intent i = getPackageManager().getLaunchIntentForPackage("com.spotify.music");
                if (i != null) startActivity(i);
                else openExternal(Uri.parse("https://play.google.com/store/apps/details?id=com.spotify.music"));
            });
        }

        @JavascriptInterface
        public String version() {
            try {
                return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
            } catch (Exception e) {
                return "?";
            }
        }
    }
}
