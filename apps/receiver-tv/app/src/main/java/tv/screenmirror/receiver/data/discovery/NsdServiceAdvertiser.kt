package tv.screenmirror.receiver.data.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import tv.screenmirror.receiver.core.Protocol
import tv.screenmirror.receiver.domain.discovery.DiscoveryAdvertiser
import java.util.concurrent.Executors

/**
 * Anuncia `_screenmirror._tcp` con NsdManager (mDNS del sistema).
 *
 * NsdManager no admite llamadas desde el hilo principal en todas las versiones,
 * así que todo va por un executor de un solo hilo: anuncio y retirada en orden.
 */
class NsdServiceAdvertiser(
    context: Context,
    private val records: ServiceRecords,
) : DiscoveryAdvertiser {

    private val nsdManager =
        context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var isRegistered = false

    private val listener = object : NsdManager.RegistrationListener {
        override fun onServiceRegistered(info: NsdServiceInfo) {
            isRegistered = true
            // El sistema puede renombrar si hay colisión ("TV Salón 2"): logueamos el nombre real.
            Log.i(TAG, "Anunciando ${info.serviceName} en ${Protocol.SERVICE_TYPE}")
        }

        override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
            // Sin anuncio el emisor no ve la TV: el fallo debe quedar visible, no tragado.
            Log.e(TAG, "No se pudo anunciar por mDNS (error $errorCode)")
        }

        override fun onServiceUnregistered(info: NsdServiceInfo) {
            isRegistered = false
        }

        override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {
            Log.w(TAG, "No se pudo retirar el anuncio mDNS (error $errorCode)")
        }
    }

    override fun start() {
        executor.execute {
            val info = NsdServiceInfo().apply {
                serviceName = records.serviceName()
                // Sin tipo explícito el sistema rechaza el registro:
                // "Service type cannot be empty" (lo exige NsdService en Android moderno).
                serviceType = Protocol.SERVICE_TYPE
                port = Protocol.PORT
                records.txt().forEach { (key, value) -> setAttribute(key, value) }
            }
            try {
                nsdManager.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
            } catch (e: IllegalArgumentException) {
                Log.e(TAG, "registerService rechazado: ${e.message}")
            }
        }
    }

    override fun stop() {
        executor.execute {
            if (!isRegistered) return@execute
            try {
                nsdManager.unregisterService(listener)
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "unregisterService rechazado: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "NsdServiceAdvertiser"
    }
}
