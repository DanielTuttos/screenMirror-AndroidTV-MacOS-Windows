package tv.screenmirror.receiver.core

import android.content.Context
import android.os.Build
import tv.screenmirror.receiver.data.ReceiverRuntimeImpl
import tv.screenmirror.receiver.data.discovery.NsdServiceAdvertiser
import tv.screenmirror.receiver.data.discovery.ServiceRecords
import tv.screenmirror.receiver.data.http.HttpStreamServer
import tv.screenmirror.receiver.data.identity.DeviceIdentity
import tv.screenmirror.receiver.data.pairing.SharedPreferencesTokenStorage
import tv.screenmirror.receiver.data.pairing.PairingStore
import tv.screenmirror.receiver.core.stream.VideoPipeline
import tv.screenmirror.receiver.domain.discovery.DiscoveryAdvertiser
import tv.screenmirror.receiver.domain.repository.PairingRepository
import tv.screenmirror.receiver.domain.repository.StreamServer
import tv.screenmirror.receiver.domain.runtime.ReceiverRuntime

/**
 * Raíz de composición (DI manual): un solo lugar donde se montan las piezas.
 */
class ReceiverContainer(context: Context) {
    val videoSurface = VideoSurface()

    val pairing: PairingRepository = PairingStore(storage = SharedPreferencesTokenStorage(context))

    private val identity = DeviceIdentity(context)
    private val pipeline = VideoPipeline(videoSurface)
    private val streamServer: StreamServer =
        HttpStreamServer(pairing, pipeline, receiverId = identity.id)

    private val advertiser: DiscoveryAdvertiser = NsdServiceAdvertiser(
        context,
        // El nombre del anuncio y el de /status deben coincidir: el emisor los empareja.
        ServiceRecords(deviceId = identity.id, deviceName = Build.MODEL),
    )

    val runtime: ReceiverRuntime = ReceiverRuntimeImpl(pairing, streamServer, pipeline, advertiser)
}
