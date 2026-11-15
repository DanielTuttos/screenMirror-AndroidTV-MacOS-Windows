package tv.screenmirror.receiver.data.discovery

import tv.screenmirror.receiver.core.Protocol

/**
 * Contenido del anuncio mDNS: nombre de servicio y registros TXT.
 * Puro (sin Android) para testearlo en JVM: la spec está en docs/protocol.md.
 */
class ServiceRecords(
    private val deviceId: String,
    private val deviceName: String,
) {

    fun serviceName(): String = deviceName

    fun txt(): Map<String, String> = mapOf(
        "v" to Protocol.VERSION.toString(),
        "id" to deviceId,
        "name" to deviceName,
        "pin" to "true",
    )
}
