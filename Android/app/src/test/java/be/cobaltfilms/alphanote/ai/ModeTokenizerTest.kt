package be.cobaltfilms.alphanote.ai

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Jetons du classifieur local : exactement ceux de `tokens()` dans
 * ml/train_tflite.py, sinon le modèle reçoit autre chose qu'à l'entraînement.
 * Vecteurs produits par le script Python (ml/build/tflite_vector.json).
 */
class ModeTokenizerTest {
    private fun ids(text: String) = ModeTokenizer.tokens(text).filter { it != 0 }

    @Test
    fun matchesPythonTokenizer() {
        assertEquals(
            listOf(1788, 4328, 8185, 3412, 1900, 10, 5190, 263, 306, 547, 3171, 2919, 6190, 8054, 6748, 6355, 3319, 1915, 127,
                4160, 3900, 7776, 6344, 7243, 1615, 2009, 4682, 3969, 5873, 1077, 1474),
            ids("Combien font 3 pizzas à 12,50 € ?")
        )
        // Accents, majuscules, apostrophe et point d'exclamation.
        assertEquals(
            listOf(7348, 959, 7159, 4154, 3732, 940, 2520, 5179, 4087, 3088, 3119, 7863, 1547, 295, 3996, 3867, 2707, 3937, 7198,
                6140, 3267, 793, 8186, 705, 7133, 4958, 2627, 800),
            ids("Lance un CHRONO pour l'été !")
        )
    }

    @Test
    fun paddedToModelLength() {
        assertEquals(ModeTokenizer.SEQ_LEN, ModeTokenizer.tokens("minuteur").size)
        assertEquals(ModeTokenizer.SEQ_LEN, ModeTokenizer.tokens("mot ".repeat(200)).size)
    }
}
