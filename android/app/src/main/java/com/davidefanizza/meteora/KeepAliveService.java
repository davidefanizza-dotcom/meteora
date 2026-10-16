package com.davidefanizza.meteora;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

/**
 * Servizio in primo piano (con notifica discreta) che tiene attiva Meteora a schermo spento,
 * così può passare da un Momento all'altro e far avanzare il Meteo Mix mentre Spotify suona.
 */
public class KeepAliveService extends Service {
    private static final String CHANNEL = "meteora_attiva";
    private PowerManager.WakeLock lock;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            NotificationChannel ch = new NotificationChannel(CHANNEL, "Meteora attiva", NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("Mostrata mentre Meteora segue il Meteo Mix o i Momenti");
            ch.setShowBadge(false);
            nm.createNotificationChannel(ch);
        }
        PendingIntent open = PendingIntent.getActivity(this, 0,
                new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CHANNEL) : new Notification.Builder(this);
        Notification n = b.setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("Meteora")
                .setContentText("Segue la coda mentre ascolti")
                .setContentIntent(open)
                .setOngoing(true)
                .build();
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
            else startForeground(1, n);
        } catch (Exception e) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if (lock == null) {
            PowerManager pm = getSystemService(PowerManager.class);
            lock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Meteora:coda");
            lock.acquire(6 * 60 * 60 * 1000L);
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        if (lock != null && lock.isHeld()) lock.release();
        lock = null;
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
