package be.cobaltfilms.alphanote.domain

import be.cobaltfilms.alphanote.ai.KeywordIntentRouter
import be.cobaltfilms.alphanote.ai.NoteMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RecipeIngredientExtractorTest {

    @Test
    fun jsonLdRecipeIsRead() {
        val html = """
            <html><head><script type="application/ld+json">
            {"@context":"https://schema.org","@type":"Recipe","name":"Crêpes",
             "recipeIngredient":["250 g de farine","4 œufs","50 cl de lait"]}
            </script></head></html>
        """
        val recipe = RecipeIngredientExtractor.extract(html)
        assertEquals("Crêpes", recipe?.title)
        assertEquals(listOf("250 g de farine", "4 œufs", "50 cl de lait"), recipe?.ingredients)
    }

    @Test
    fun recipeInsideGraphWithTypeArrayAndEntities() {
        val html = """
            <script type='application/ld+json'>
            {"@graph":[{"@type":"WebPage","name":"Site"},
                       {"@type":["Recipe","NewsArticle"],"name":"Tarte &amp; pommes",
                        "recipeIngredient":["1 p&acirc;te bris&eacute;e","4 pommes","4 pommes"," "]}]}
            </script>
        """
        val recipe = RecipeIngredientExtractor.extract(html)
        assertEquals("Tarte & pommes", recipe?.title)
        assertEquals(listOf("1 pâte brisée", "4 pommes"), recipe?.ingredients)
    }

    @Test
    fun invalidJsonLdFallsBackToMicrodata() {
        val html = """
            <script type="application/ld+json">{ cassé </script>
            <ul><li itemprop="recipeIngredient"><span>200 g</span> de sucre</li>
            <li itemprop="recipeIngredient">1 pincée de sel</li></ul>
        """
        assertEquals(listOf("200 g de sucre", "1 pincée de sel"), RecipeIngredientExtractor.extract(html)?.ingredients)
    }

    @Test
    fun pageWithoutRecipeIsNull() {
        assertNull(RecipeIngredientExtractor.extract("""<script type="application/ld+json">{"@type":"Article","name":"x"}</script>"""))
    }

    @Test
    fun firstUrlIsFoundAndCompleted() {
        assertEquals("https://www.marmiton.org/r.aspx", RecipeIngredientExtractor.firstUrl("liste depuis www.marmiton.org/r.aspx."))
        assertNull(RecipeIngredientExtractor.firstUrl("courses : tomates, pâtes"))
    }

    @Test
    fun urlRoutesToListBeforeMath() {
        assertEquals(NoteMode.LIST, KeywordIntentRouter.classify("https://www.marmiton.org/recettes/recette_crepes-1234.aspx", null))
    }
}
