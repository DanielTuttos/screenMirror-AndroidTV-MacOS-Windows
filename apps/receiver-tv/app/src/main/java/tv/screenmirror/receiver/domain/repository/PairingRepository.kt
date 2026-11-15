package tv.screenmirror.receiver.domain.repository

import tv.screenmirror.receiver.domain.Outcome

interface PairingRepository {
    fun currentPin(): String

    /** Intercambia un PIN por un token de sesión. */
    fun pair(pin: String): Outcome<String>

    fun isValidToken(token: String?): Boolean

    fun activeTokenCount(): Int
}
