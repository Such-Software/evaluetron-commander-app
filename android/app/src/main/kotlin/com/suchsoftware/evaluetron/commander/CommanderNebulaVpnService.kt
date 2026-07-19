package com.suchsoftware.evaluetron.commander

import android.content.Intent
import android.net.VpnService
import android.os.IBinder

/**
 * Permission-gated service boundary reserved for the audited Nebula engine.
 *
 * This scaffold never establishes a TUN interface. Unexpected starts are
 * stopped immediately until the native engine and foreground lifecycle are
 * integrated and tested.
 */
class CommanderNebulaVpnService : VpnService() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopSelf(startId)
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        stopSelf()
        super.onRevoke()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)
}
