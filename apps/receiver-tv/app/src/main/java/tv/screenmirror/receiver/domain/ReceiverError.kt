package tv.screenmirror.receiver.domain

/**
 * Errores del dominio. El mapeo a códigos HTTP vive en data/http (asunto de transporte).
 */
sealed interface ReceiverError {
    val message: String

    data class InvalidRequest(override val message: String) : ReceiverError
    data class ServiceFailure(override val message: String) : ReceiverError

    data object InvalidPin : ReceiverError {
        override val message = "pin incorrecto"
    }

    data object RateLimited : ReceiverError {
        override val message = "demasiados intentos, espera un minuto"
    }

    data object InvalidToken : ReceiverError {
        override val message = "token inválido"
    }

    data object ProtocolMismatch : ReceiverError {
        override val message = "versión de protocolo no soportada"
    }

    data object StreamBusy : ReceiverError {
        override val message = "ya hay un stream activo"
    }

    data object ResolutionNotSupported : ReceiverError {
        override val message = "resolución no soportada"
    }

    data object NotFound : ReceiverError {
        override val message = "recurso no encontrado"
    }

    data object NoDisplay : ReceiverError {
        override val message = "pantalla no disponible"
    }

    data object InternalError : ReceiverError {
        override val message = "error interno"
    }
}
