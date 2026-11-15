package tv.screenmirror.receiver.data.discovery

import org.junit.Assert.assertEquals
import org.junit.Test
import tv.screenmirror.receiver.core.Protocol

class ServiceRecordsTest {

    @Test
    fun `los registros TXT cumplen la spec del protocolo`() {
        val records = ServiceRecords(deviceId = "uuid-1234", deviceName = "TV Salon")

        val txt = records.txt()

        assertEquals("0", txt["v"])
        assertEquals("uuid-1234", txt["id"])
        assertEquals("TV Salon", txt["name"])
        assertEquals("true", txt["pin"])
        assertEquals(4, txt.size)
    }

    @Test
    fun `el nombre del servicio coincide con el de status`() {
        val records = ServiceRecords(deviceId = "uuid-1234", deviceName = "AI PONT")

        // El emisor empareja el anuncio con GET /status por nombre: deben ser idénticos.
        assertEquals("AI PONT", records.serviceName())
    }

    @Test
    fun `el tipo de servicio es el que declara la spec`() {
        assertEquals("_screenmirror._tcp", Protocol.SERVICE_TYPE)
    }
}
