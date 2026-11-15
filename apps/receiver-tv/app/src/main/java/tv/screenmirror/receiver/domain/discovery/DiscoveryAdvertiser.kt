package tv.screenmirror.receiver.domain.discovery

/**
 * Anuncia la presencia del receptor en la red para que el emisor lo encuentre
 * sin que nadie teclee una IP (spec: docs/protocol.md § Descubrimiento).
 */
interface DiscoveryAdvertiser {
    fun start()

    fun stop()
}
