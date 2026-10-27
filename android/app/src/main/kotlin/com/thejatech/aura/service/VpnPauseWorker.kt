package com.thejatech.aura.service

import android.content.Context
import android.net.VpnService
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.thejatech.aura.storage.AuraPreferences
import com.thejatech.aura.tunnel.AuraTunnelManager
import java.util.concurrent.TimeUnit

class VpnPauseWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : Worker(appContext, workerParams) {

    companion object {
        private const val TAG = "VpnPauseWorker"
        const val UNIQUE_WORK_NAME = "com.thejatech.aura.vpn_pause_resume"

        fun schedulePauseExpiry(context: Context, delayMillis: Long) {
            val safeDelay = delayMillis.coerceAtLeast(0L)
            val request = OneTimeWorkRequestBuilder<VpnPauseWorker>()
                .setInitialDelay(safeDelay, TimeUnit.MILLISECONDS)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                UNIQUE_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request
            )
            Log.i(TAG, "Scheduled pause expiry worker with delay ${safeDelay}ms")
        }

        fun cancelPauseExpiry(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
            Log.i(TAG, "Cancelled pause expiry worker")
        }
    }

    override fun doWork(): Result {
        Log.i(TAG, "VpnPauseWorker executing")
        val mode = AuraPreferences.getPolicyMode(applicationContext)
        val expiry = AuraPreferences.getPauseExpiryMillis(applicationContext)
        val now = System.currentTimeMillis()

        if (mode == AuraPreferences.POLICY_PAUSED) {
            val remaining = expiry - now
            if (remaining > 1000L) {
                Log.i(TAG, "VpnPauseWorker woke up early (${remaining}ms remaining); rescheduling")
                schedulePauseExpiry(applicationContext, remaining)
                return Result.success()
            }
            if (remaining > 0L) {
                try {
                    Thread.sleep(remaining)
                } catch (_: InterruptedException) {}
            }

            // Re-verify policy after sleep to ensure user did not make a newer choice
            if (AuraPreferences.getPolicyMode(applicationContext) != AuraPreferences.POLICY_PAUSED) {
                Log.i(TAG, "Policy changed during worker execution; skipping auto-reconnect")
                return Result.success()
            }

            Log.i(TAG, "Pause expired; transitioning policy to ENABLED and attempting tunnel reconnect")
            AuraPreferences.setPolicyEnabled(applicationContext)

            val isPrepared = VpnService.prepare(applicationContext) == null
            val isAutoRestart = AuraPreferences.isAutoRestartEnabled(applicationContext)

            if (isPrepared && isAutoRestart) {
                try {
                    AuraTunnelManager.shared.startTunnel(applicationContext)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start tunnel after pause expiration", e)
                }
            } else {
                Log.w(TAG, "Cannot start tunnel: isPrepared=$isPrepared, isAutoRestart=$isAutoRestart")
            }
        } else {
            Log.i(TAG, "VpnPauseWorker skipped: mode=$mode, now=$now, expiry=$expiry")
        }

        return Result.success()
    }
}
