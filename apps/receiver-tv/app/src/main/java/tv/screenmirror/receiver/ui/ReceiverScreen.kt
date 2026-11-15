package tv.screenmirror.receiver.ui

import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import tv.screenmirror.receiver.R
import tv.screenmirror.receiver.core.Protocol
import tv.screenmirror.receiver.domain.model.ReceiverState
import tv.screenmirror.receiver.domain.model.StreamStats
import java.net.Inet4Address
import java.net.NetworkInterface

@Composable
fun ReceiverScreen(viewModel: ReceiverViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        // Surface siempre presente para que el decoder pueda arrancar en cuanto llegue un stream.
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                SurfaceView(context).apply {
                    holder.addCallback(object : SurfaceHolder.Callback {
                        override fun surfaceCreated(holder: SurfaceHolder) =
                            viewModel.onSurfaceChanged(holder.surface)

                        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) =
                            viewModel.onSurfaceChanged(holder.surface)

                        override fun surfaceDestroyed(holder: SurfaceHolder) =
                            viewModel.onSurfaceChanged(null)
                    })
                }
            },
        )

        when (val current = state) {
            is ReceiverState.Starting -> CenteredText("Iniciando receptor…")
            is ReceiverState.Ready -> PinOverlay(pin = current.pin)
            is ReceiverState.Streaming -> StatsHud(stats = current.stats)
            is ReceiverState.Stopped -> CenteredText("Detenido: ${current.reason}")
        }
    }
}

@Composable
private fun CenteredText(text: String) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text = text, color = Color(0xFF8B949E), fontSize = 22.sp)
    }
}

@Composable
private fun PinOverlay(pin: String) {
    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(48.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = context.getString(R.string.app_name),
            color = Color(0xFF3DDC84),
            fontSize = 34.sp,
        )
        Text(
            text = "Código de emparejamiento",
            color = Color(0xFF8B949E),
            fontSize = 20.sp,
            modifier = Modifier.padding(top = 24.dp),
        )
        Text(
            text = pin,
            color = Color.White,
            fontSize = 88.sp,
            fontFamily = FontFamily.Monospace,
            letterSpacing = 12.sp,
            modifier = Modifier.padding(top = 8.dp),
        )
        Text(
            text = "Esperando emisor…\n${localIpv4() ?: "sin red"}:${Protocol.PORT}",
            color = Color(0xFF8B949E),
            fontSize = 18.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 32.dp),
        )
    }
}

@Composable
private fun StatsHud(stats: StreamStats) {
    Column(
        modifier = Modifier
            .padding(24.dp)
            .background(Color(0xCC0D1117), MaterialTheme.shapes.small)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(text = "● RECIBIENDO", color = Color(0xFF3DDC84), fontSize = 16.sp)
        Text(text = "${stats.bitrateKbps} kbps · ${stats.fps} fps", color = Color.White, fontSize = 16.sp)
        Text(
            text = "frames ${stats.frames} · descartados ${stats.droppedFrames}",
            color = Color(0xFF8B949E),
            fontSize = 14.sp,
        )
    }
}

/** IPv4 local no-loopback para mostrar en el overlay (sin permisos especiales). */
private fun localIpv4(): String? = NetworkInterface.getNetworkInterfaces()
    ?.toList()
    ?.filter { !it.isLoopback && it.isUp }
    ?.flatMap { it.inetAddresses.toList() }
    ?.filterIsInstance<Inet4Address>()
    ?.firstOrNull()
    ?.hostAddress
