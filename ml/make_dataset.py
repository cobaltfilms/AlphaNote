"""Jeu d'exemples du classifieur de mode (math, list, timer, code, plain).

Un seul jeu pour les deux modèles : Create ML (macOS/iOS) et MediaPipe
TFLite (Android) s'entraînent sur les mêmes lignes, et sont évalués sur le
même jeu de test. Phrases écrites à la main + gabarits remplis au hasard
(graine fixe : le jeu est reproductible).

    python3 ml/make_dataset.py        → ml/data/{train,test}.csv
"""
import csv
import random
import unicodedata
from pathlib import Path

random.seed(20261031)
OUT = Path(__file__).parent / "data"

def pick(*options):
    return random.choice(options)

def num(lo=2, hi=500):
    return str(random.randint(lo, hi))

def dec():
    return pick(f"{random.randint(1, 99)},{random.randint(1, 99):02d}", f"{random.randint(1, 99)}.{random.randint(1, 9)}", num(1, 99))

def strip_accents(text):
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")

def typo(text):
    """Une faute de frappe : lettre doublée ou avalée."""
    if len(text) < 8:
        return text
    i = random.randint(1, len(text) - 2)
    return text[:i] + text[i] * 2 + text[i + 1:] if random.random() < 0.5 else text[:i] + text[i + 1:]

ITEMS = ["pain", "lait", "œufs", "beurre", "tomates", "pâtes", "riz", "farine", "sucre", "café", "thé", "pommes",
         "bananes", "yaourts", "fromage", "jambon", "poulet", "salade", "carottes", "oignons", "ail", "huile d'olive",
         "lessive", "papier toilette", "dentifrice", "shampoing", "piles", "ampoules", "croquettes", "eau gazeuse",
         "vin rouge", "chocolat", "céréales", "confiture", "miel", "citrons", "courgettes", "steaks", "saumon", "crème fraîche"]
TASKS = ["appeler le plombier", "payer la facture d'électricité", "envoyer le devis", "réserver le restaurant",
         "rendre les livres", "prendre rendez-vous chez le dentiste", "répondre à Marie", "sortir les poubelles",
         "réviser la voiture", "renouveler le passeport", "faire le montage", "exporter les rushs", "relancer le client",
         "préparer la réunion", "arroser les plantes", "acheter un cadeau", "ranger le garage", "faire la déclaration d'impôts"]
UNITS = [("km", "mi"), ("miles", "km"), ("kg", "lb"), ("lb", "kg"), ("°C", "°F"), ("°F", "°C"), ("m", "ft"),
         ("pieds", "mètres"), ("litres", "gallons"), ("cm", "pouces"), ("oz", "g"), ("mph", "km/h")]
CURRENCIES = [("EUR", "USD"), ("USD", "EUR"), ("euros", "dollars"), ("dollars", "euros"), ("EUR", "GBP"), ("CHF", "EUR"), ("yens", "euros")]
LANGS = ["python", "swift", "kotlin", "bash", "javascript", "sql", "zsh", "rust", "go", "typescript", "ffmpeg"]

def math_examples():
    fixed = [
        "12 * 8", "combien font 3 + 4", "15 % de 80", "pourcentage de réduction entre 120 et 90",
        "aire d'un cercle de rayon 3", "volume d'une sphère de 10 cm de diamètre", "racine carrée de 144",
        "2 puissance 10", "moyenne de 12, 15 et 18", "combien de litres dans une piscine de 8 m sur 4 m et 1,5 m de profondeur",
        "mensualité d'un prêt de 200000 € sur 20 ans à 3,5 %", "intérêts composés de 1000 € à 4 % pendant 10 ans",
        "prix TTC de 250 € HT", "TVA à 21 % sur 1500", "combien coûte 3 pizzas à 12,50 € plus 15 % de pourboire",
        "écart de prix entre 49,99 et 39,99", "diviser 1250 par 7", "combien de secondes dans une journée",
        "combien de jours entre le 3 mars et le 20 juin", "périmètre d'un rectangle de 4 m sur 7 m",
        "surface d'un appartement de 6 m sur 9 m", "consommation pour 450 km à 6,5 l aux 100",
        "calcule 17 au carré", "partage 86 € entre 4 personnes", "combien me reste-t-il si je dépense 340 sur 1200",
        "budget vacances 640 + 170 + 315", "hypoténuse d'un triangle de côtés 3 et 4", "18 fois 24",
        "rendement de 12 sur 150 en pourcentage", "convertis 1 To en Go", "combien font 7 heures à 45 € de l'heure",
        "remise de 30 % sur 79 €", "augmentation de 5 % sur un salaire de 2800", "pi fois 2", "log de 1000",
        "sinus de 30 degrés", "factorielle de 6", "combien d'images pour 12 secondes à 25 images par seconde",
        "durée de 3500 images à 24 i/s", "débit pour 4 Go en 10 minutes", "taille d'un fichier de 90 min à 50 Mb/s",
    ]
    templates = [
        lambda: f"{num()} {pick('*', 'x', '+', '-', '/')} {num()}",
        lambda: f"{pick('combien font', 'combien fait', 'calcule', 'ça fait combien', 'c koi')} {num()} {pick('fois', 'plus', 'moins', 'divisé par')} {num()}",
        lambda: f"{num(1, 90)} % de {num(20, 5000)}",
        lambda: f"{num(1, 1000)} {(u := random.choice(UNITS))[0]} {pick('en', 'to', 'in')} {u[1]}",
        lambda: f"{pick('convertis', 'convertir', 'combien font')} {num(1, 500)} {(u := random.choice(UNITS))[0]} en {u[1]}",
        lambda: f"{num(5, 5000)} {(c := random.choice(CURRENCIES))[0]} {pick('en', 'to')} {c[1]}",
        lambda: f"{pick('prix', 'total', 'coût')} de {num(2, 12)} {pick('billets', 'places', 'menus', 'licences', 'jours de location')} à {dec()} €",
        lambda: f"{pick('réduction', 'remise', 'promo')} de {num(5, 70)} % sur {dec()} €",
        lambda: f"{pick('aire', 'surface', 'périmètre')} d'un {pick('carré', 'rectangle', 'cercle', 'triangle')} de {num(1, 30)} {pick('cm', 'm')}",
        lambda: f"{pick('combien de', 'nombre de')} {pick('minutes', 'heures', 'secondes', 'semaines')} dans {num(2, 90)} {pick('jours', 'heures', 'mois')}",
        lambda: f"{pick('loyer', 'logement', 'essence', 'repas')}: {num()} {pick('+', '*')} {num(2, 9)}",
        lambda: f"{pick('quel est le', 'calcule le')} {pick('pourcentage', 'ratio', 'taux')} de {num()} sur {num()}",
        lambda: f"{pick('mensualité', 'remboursement mensuel')} pour {num(5, 400)}000 € sur {num(5, 25)} ans",
        lambda: f"{pick('ajoute', 'compte')} {num(5, 30)} % de {pick('TVA', 'pourboire', 'frais')} à {dec()}",
        lambda: f"{num()} {pick('/', '-', '+', '*')} {num()} {pick('+', '-', '*', '/')} {num()}",
        lambda: f"{num()} {pick('/', '-')} {num()}",
        lambda: f"{pick('budget', 'total', 'dépenses', 'frais')} {pick('vacances', 'courses', 'tournage', 'mois', 'week-end')} {num()} + {num()} + {num()}",
        lambda: f"({num()} + {num()}) {pick('*', '/')} {num(2, 12)}",
    ]
    return fixed + [t() for t in templates for _ in range(10)]

def list_examples():
    fixed = [
        "courses : tomates, pâtes, huile", "ajoute de l'huile d'olive à la liste", "https://www.marmiton.org/recettes/recette_crepes.aspx",
        "liste de courses pour la semaine", "fais une check-list pour le départ en vacances", "todo : appeler maman, payer le loyer",
        "les ingrédients d'un tiramisu", "ce qu'il faut emporter au camping", "mes tâches de demain",
        "ajoute du pain et du lait", "il faut acheter des piles et des ampoules", "note les films à voir",
        "liste des invités pour samedi", "check-list tournage : batteries, cartes SD, micro", "à faire avant vendredi",
        "valise : maillot, crème solaire, chargeur", "https://www.cuisineaz.com/recettes/lasagnes-a-la-bolognaise-56170.aspx",
        "https://www.750g.com/gratin-dauphinois-r12345.htm", "recette du pain perdu https://cuisine.journaldesfemmes.fr/recette/315812-pain-perdu",
        "rajoute les oeufs", "mets des bananes sur la liste",
        "liste des documents pour la mairie", "étapes pour installer le serveur", "cadeaux de Noël : papa, maman, Léo",
    ]
    def items(n):
        return random.sample(ITEMS, n)
    templates = [
        lambda: f"{pick('ajoute', 'rajoute', 'mets', 'achète')} {pick('du', 'des', 'de la', '')} {random.choice(ITEMS)} {pick('à la liste', 'aux courses', 'à mes courses', 'dans la liste', '')}".replace("  ", " "),
        lambda: f"{pick('courses', 'liste', 'à acheter', 'supermarché')} : {', '.join(items(random.randint(2, 6)))}",
        lambda: f"{pick('il faut', 'je dois', 'faut')} {pick('acheter', 'prendre', 'racheter')} {' et '.join(items(2))}",
        lambda: f"{pick('todo', 'à faire', 'tâches', 'mes tâches')} : {', '.join(random.sample(TASKS, random.randint(2, 4)))}",
        lambda: f"{pick('ajoute', 'rajoute')} « {random.choice(TASKS)} » {pick('à ma todo', 'aux tâches', 'à la liste', '')}".strip(),
        lambda: f"{pick('fais', 'crée', 'prépare')} {pick('une liste', 'une check-list', 'une todo')} pour {pick('le déménagement', 'le tournage', 'la fête', 'le week-end', 'la rentrée', 'le voyage à Lisbonne')}",
        lambda: f"{pick('ingrédients', 'ce qu il faut')} pour {pick('une quiche', 'un gâteau au chocolat', 'des crêpes', 'une ratatouille', 'un risotto', 'une pizza maison')}",
        lambda: f"https://www.{pick('marmiton.org/recettes', 'cuisineaz.com/recettes', 'ricardocuisine.com/recettes')}/{pick('quiche-lorraine', 'boeuf-bourguignon', 'tarte-aux-pommes', 'soupe-potiron', 'chili-con-carne')}-{num(1000, 99999)}",
        lambda: f"{' '.join(items(3))}",
    ]
    return fixed + [t() for t in templates for _ in range(14)]

def timer_examples():
    fixed = [
        "minuteur 25 minutes", "lance un chrono", "compte à rebours de 10 minutes", "pomodoro", "lance un pomodoro de 50 minutes",
        "rappelle-moi dans 5 minutes", "timer 3 min", "mets un minuteur pour les pâtes", "chronomètre", "démarre un chrono",
        "minuteur 1 h 30", "compte à rebours 45 secondes", "cuisson des œufs 6 minutes", "sieste de 20 minutes",
        "pause de 15 min", "session de travail de 25 min", "alarme dans 10 minutes", "lance le minuteur",
        "compte à rebours jusqu'à la fin de la réunion, 40 minutes", "timer pour le thé, 4 min",
    ]
    templates = [
        lambda: f"{pick('minuteur', 'timer', 'compte à rebours', 'décompte', 'minuterie')} {pick('de ', '')}{num(1, 90)} {pick('minutes', 'min', 'mn', 'secondes', 's', 'heures', 'h')}",
        lambda: f"{pick('lance', 'mets', 'démarre', 'programme', 'crée')} un {pick('minuteur', 'timer', 'compte à rebours', 'chrono', 'pomodoro')}{pick('', ' de ' + num(1, 60) + ' minutes')}",
        lambda: f"{pick('rappelle-moi', 'préviens-moi', 'sonne')} dans {num(1, 60)} {pick('minutes', 'secondes', 'heures')}",
        lambda: f"{pick('cuisson', 'infusion', 'pause', 'sieste', 'repos de la pâte', 'temps de pose')} {pick('de ', '')}{num(2, 45)} {pick('min', 'minutes')}",
        lambda: f"{pick('pomodoro', 'session pomodoro', 'focus')} {pick('', num(15, 60) + ' min')}".strip(),
        lambda: f"{pick('chrono', 'chronomètre', 'stopwatch')} {pick('', 'pour la course', 'pour le footing', 'pour la réunion')}".strip(),
        lambda: f"{pick('mets', 'lance', 'démarre', 'fais')} un compte à rebours {pick('de', 'sur')} {num(1, 90)} {pick('minutes', 'secondes', 'min')}",
        lambda: f"{pick('dans', 'pendant')} {num(2, 60)} minutes {pick('préviens-moi', 'fais sonner', 'sonne')}",
    ]
    return fixed + [t() for t in templates for _ in range(18)]

def code_examples():
    fixed = [
        "écris une fonction python qui inverse une liste", "corrige ce code : for i in range(10) print(i)",
        "commande ffmpeg pour convertir en h264", "git log --oneline -5", "regex pour un email",
        "script bash qui renomme les fichiers en minuscules", "requête SQL pour compter les clients par ville",
        "func add(a: Int, b: Int) -> Int { a + b }", "comment faire un rsync incrémental", "snippet swift pour lire un fichier",
        "docker compose pour postgres", "ls -la | grep mp4", "range ce code json", "kotlin data class Note(val id: Long)",
        "const x = arr.map(v => v * 2)", "SELECT * FROM note WHERE archived = 0", "commande pour trouver les gros fichiers",
        "indente ce code", "fonction javascript debounce", "boucle for en rust", "ssh-keygen -t ed25519",
        "comment tuer le process sur le port 8080", "def fib(n): return n if n < 2 else fib(n-1) + fib(n-2)",
    ]
    templates = [
        lambda: f"{pick('écris', 'donne-moi', 'fais', 'génère')} {pick('une fonction', 'un script', 'un snippet', 'une classe', 'une requête')} {random.choice(LANGS)} {pick('qui trie une liste', 'pour parser du JSON', 'qui lit un CSV', 'pour télécharger un fichier', 'qui compte les mots', 'pour redimensionner des images')}",
        lambda: f"{pick('corrige', 'debug', 'optimise', 'commente', 'formate', 'range')} {pick('ce code', 'cette fonction', 'ce script', 'cette requête')} {random.choice(LANGS)}",
        lambda: f"{pick('commande', 'la commande', 'one-liner')} {random.choice(LANGS)} pour {pick('lister les fichiers', 'compresser un dossier', 'extraire l audio', 'changer les permissions', 'chercher un texte récursivement', 'faire un backup')}",
        lambda: f"{pick('git', 'docker', 'kubectl', 'brew', 'npm', 'ffmpeg -i')} {pick('status', 'run -it ubuntu bash', 'get pods', 'install jq', 'install', 'input.mov -c:v libx264 out.mp4', 'rebase -i HEAD~3', 'ps -a')}",
        lambda: f"{pick('comment', 'syntaxe pour')} {pick('faire une boucle', 'déclarer un tableau', 'gérer une exception', 'lire un fichier', 'faire une requête http')} en {random.choice(LANGS)}",
        lambda: f"{pick('SELECT', 'select')} {pick('*', 'id, title', 'count(*)', 'name')} FROM {pick('note', 'clients', 'orders', 'users')} {pick('WHERE archived = 0', 'WHERE id = 3', 'ORDER BY date DESC', 'GROUP BY city', 'LIMIT 10')}",
        lambda: f"{pick('UPDATE note SET pinned = 1 WHERE id = 4', 'DELETE FROM users WHERE active = 0', 'INSERT INTO tags (name) VALUES (?)', 'CREATE INDEX idx_date ON note(date)')}",
        lambda: f"{pick('requête', 'requete', 'query')} {pick('SQL', 'sql', 'postgres')} pour {pick('compter les clients par ville', 'trouver les doublons', 'joindre deux tables', 'supprimer les lignes vides', 'trier par date')}",
    ]
    return fixed + [t() for t in templates for _ in range(16)]

def plain_examples():
    fixed = [
        "idée : un court-métrage sur un phare abandonné", "réunion avec Paul jeudi à 14h", "penser à la lumière du matin pour la scène 3",
        "pourquoi le ciel est bleu", "j'ai bien aimé le film d'hier soir", "citation : la simplicité est la sophistication suprême",
        "le code wifi du bureau est sur le frigo", "Marie préfère le bleu", "brouillon du mail pour le client",
        "qu'est-ce qu'on mange ce soir", "rêve bizarre cette nuit, un train sous l'eau", "notes de la conférence sur l'étalonnage",
        "le rendez-vous est reporté à mardi", "anniversaire de Léo le 12 avril", "bonjour", "test", "à méditer",
        "le plombier passe entre 8h et 12h", "titre possible : Les Heures Claires", "résumé du livre : un homme seul sur Mars",
        "numéro de commande 4471-AB", "adresse : 12 rue des Lilas, Bruxelles", "mot du jour : sérendipité", "ok pour samedi",
        "il pleut depuis trois jours", "à quoi sert un étalonneur", "le chat a encore vomi sur le tapis", "écrire à grand-mère",
        "souvenir : la plage de Knokke en 2019", "projet : refaire le site de Cobalt Films", "la réunion a duré 2 heures",
        "j'ai couru 10 km ce matin", "le film fait 90 minutes", "on était 12 au dîner", "version 3 du montage validée",
    ]
    templates = [
        lambda: f"{pick('idée', 'pensée', 'note', 'remarque', 'à retenir')} : {pick('tourner au lever du soleil', 'tester une autre police pour le générique', 'demander à Léa pour la voix off', 'revoir la fin du scénario', 'un podcast sur le cinéma belge', 'proposer un atelier étalonnage')}",
        lambda: f"{pick('réunion', 'rendez-vous', 'appel', 'déjeuner')} avec {pick('Paul', 'Marie', 'le client', 'l équipe', 'Léo', 'la banque')} {pick('lundi', 'mardi', 'jeudi', 'demain', 'la semaine prochaine')}{pick('', ' à ' + num(8, 18) + 'h')}",
        lambda: f"{pick('pourquoi', 'comment', 'est-ce que', 'qui a')} {pick('les chats ronronnent', 'on dit bonjour', 'le film a gagné', 'la mer est salée', 'les oiseaux migrent', 'il fait si chaud')}",
        lambda: f"{pick('j ai', 'on a', 'nous avons')} {pick('vu', 'fini', 'commencé', 'adoré', 'raté')} {pick('le film', 'la série', 'le livre', 'le projet', 'le concert')} {pick('hier', 'ce matin', 'ce week-end', '')}".strip(),
        lambda: f"{pick('le', 'la', 'mon', 'notre')} {pick('rendez-vous', 'livraison', 'colis', 'tournage', 'mixage')} {pick('est reporté', 'arrive', 'commence', 'est annulé', 'se passe bien')} {pick('mardi', 'demain', 'la semaine prochaine', 'à 9h', '')}".strip(),
        lambda: f"{pick('citation', 'phrase', 'réplique')} : « {pick('rien ne se perd', 'le temps file', 'tout est possible', 'la lumière fait le film')} »",
        lambda: f"{pick('code wifi', 'numéro client', 'référence', 'adresse', 'téléphone')} {pick('du bureau', 'de la banque', 'du fournisseur', 'de Marie')} : {pick('voir carnet', num(1000, 99999), 'rue du Midi 8', 'sur le frigo')}",
        lambda: f"{pick('souvenir', 'rêve', 'journal', 'impression', 'ressenti')} : {pick('la plage de Knokke en 2019', 'un train sous l eau, très étrange', 'journée longue, mais belle', 'le concert était trop fort, mais génial', 'Lisbonne sous la pluie, en 2022')}",
        lambda: f"{pick('adresse', 'lieu de tournage', 'rendez-vous')} : {num(1, 120)} {pick('rue des Lilas', 'avenue Louise', 'chaussée de Wavre', 'place Flagey')}, {pick('Bruxelles', 'Liège', 'Namur', 'Gand')}",
        lambda: f"{pick('hier', 'ce matin', 'cette nuit', 'samedi')}, {pick('on a parlé du projet', 'il a fait très beau', 'j ai revu Thomas', 'le serveur est tombé')}, {pick('c était bien', 'à suivre', 'rien de grave', 'je suis content')}",
    ]
    return fixed + [t() for t in templates for _ in range(16)]

def augment(rows):
    """Variantes réalistes : sans accents, minuscules, faute de frappe."""
    extra = []
    for text, label in rows:
        r = random.random()
        if r < 0.15:
            extra.append((strip_accents(text), label))
        elif r < 0.25:
            extra.append((typo(text), label))
        elif r < 0.32:
            extra.append((text.capitalize(), label))
    return rows + extra

def main():
    rows = []
    for label, maker in [("math", math_examples), ("list", list_examples), ("timer", timer_examples),
                         ("code", code_examples), ("plain", plain_examples)]:
        rows += [(" ".join(t.split()), label) for t in maker()]
    rows = list(dict.fromkeys(augment(rows)))  # sans doublons, ordre stable
    random.shuffle(rows)

    # Test stratifié (20 %), jamais vu à l'entraînement.
    train, test = [], []
    by_label = {}
    for row in rows:
        by_label.setdefault(row[1], []).append(row)
    for label, items in by_label.items():
        cut = len(items) // 5
        test += items[:cut]
        train += items[cut:]
    OUT.mkdir(exist_ok=True)
    for name, data in [("train", train), ("test", test)]:
        with open(OUT / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["text", "label"])
            writer.writerows(data)
    counts = {label: len(items) for label, items in sorted(by_label.items())}
    print(f"{len(train)} entraînement, {len(test)} test — {counts}")

if __name__ == "__main__":
    main()
