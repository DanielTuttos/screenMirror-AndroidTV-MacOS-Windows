package tv.screenmirror.receiver.domain

/**
 * Resultado tipado: nada de excepciones ni nulls silenciosos.
 */
sealed interface Outcome<out T> {
    data class Success<T>(val value: T) : Outcome<T>
    data class Failure(val error: ReceiverError) : Outcome<Nothing>
}
