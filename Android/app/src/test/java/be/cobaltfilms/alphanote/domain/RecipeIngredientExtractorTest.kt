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
    fun namesOnlyRecipeTakesQuantitiesFromVisibleList() {
        // Cas papillesetpupilles.fr : JSON-LD sans quantités, liste visible complète.
        val html = """
            <script type="application/ld+json">{"@type":"Recipe","name":"Poulet mafé",
             "recipeIngredient":["Ail","Carottes","Huile d'olive","Oignons","Patates douces","Poulet entier"]}</script>
            <nav><ul><li>Accueil</li><li>Recettes</li></ul></nav>
            <h2>Ingrédients</h2>
            <p>Il vous faut pour 8/10 personnes :</p>
            <ul><li>1 <a href="#"><strong>poulet</strong></a> fermier</li>
            <li>12 gousses d&rsquo;<a href="#">ail</a></li>
            <li>3 cuillères à soupe d&rsquo;huile d&rsquo;olive</li>
            <li>1 oignon</li><li>4 carottes (225 g)</li><li>1 patate douce</li>
            <li>Pour terminer :</li><li>1 pincée de sel</li></ul>
            <h2>Préparation</h2><ul><li>Coupez le poulet en morceaux.</li></ul>
        """
        val recipe = RecipeIngredientExtractor.extract(html)
        assertEquals("Poulet mafé", recipe?.title)
        assertEquals(listOf(
            "1 poulet fermier", "12 gousses d’ail", "3 cuillères à soupe d’huile d’olive",
            "1 oignon", "4 carottes (225 g)", "1 patate douce", "1 pincée de sel"
        ), recipe?.ingredients)
    }

    @Test
    fun namesOnlyRecipeWithoutMatchingListKeepsNames() {
        val html = """
            <script type="application/ld+json">{"@type":"Recipe","recipeIngredient":["Ail","Carottes","Poulet"]}</script>
            <h2>Ingrédients</h2><ul><li>Accueil</li><li>Contact</li></ul>
        """
        assertEquals(listOf("Ail", "Carottes", "Poulet"), RecipeIngredientExtractor.extract(html)?.ingredients)
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
