# Forever Music Player

Un lecteur de musique pour **World of Warcraft: Forever**. Depuis une petite
fenêtre en jeu, tu pilotes ta musique Spotify, Deezer, Apple Music ou YouTube
Music. Tant que ta musique joue, celle du jeu est coupée ; quand tu arrêtes le
lecteur, elle revient exactement comme avant.

Le projet a deux parties :

| Dossier | Rôle |
| --- | --- |
| `ForeverMusicPlayer/` | L'addon : la fenêtre du lecteur en jeu, la coupure et le retour de la musique du jeu. |
| `companion/` | Le compagnon : un petit programme Windows qui transmet tes ordres à ton application de musique. |

> **État du projet (v0.1.0).** Le code est testé hors du jeu, avec un faux
> environnement WoW et de faux écrans (voir [Développement](#développement)).
> Il n'a pas encore tourné dans le vrai client ni sur un vrai Windows : le
> premier essai en jeu reste à faire, la liste des points à vérifier est
> [plus bas](#premier-essai-en-jeu).

## Ce qu'il faut savoir avant de commencer

**Un addon WoW ne peut pas se connecter à Internet ni lire un flux audio.**
Le jeu enferme les addons dans un bac à sable : pas de réseau, pas de fichiers,
pas d'accès aux autres programmes. Aucun addon ne peut donc ouvrir une session
Spotify ou Deezer lui-même. D'où ce fonctionnement :

- **Tu te connectes à ta plateforme dans son application officielle** (ou son
  lecteur web), comme d'habitude. C'est elle qui joue le son.
- **L'addon** affiche le lecteur en jeu et gère la musique du jeu.
- **Le compagnon** fait le lien entre les deux, en passant par les contrôles
  multimédias de Windows (les mêmes que les touches lecture/pause d'un clavier).

Conséquences à connaître :

- Le lien va **dans un seul sens**, du jeu vers l'application. Le titre en
  cours ne s'affiche donc pas en jeu (il s'affiche dans la fenêtre du
  compagnon), et si tu mets en pause directement dans Spotify, le lecteur en
  jeu ne le sait pas.
- Le compagnon existe pour **Windows** uniquement.
- Aucun compte développeur, aucune clé d'API : rien n'est demandé à Spotify,
  Deezer, Apple ou YouTube, et ta musique n'est ni copiée ni enregistrée.

## Installation

### 1. L'addon

1. Copie le dossier `ForeverMusicPlayer` dans le dossier des addons de WoW
   Forever : `World of Warcraft\_forever_\Interface\AddOns\`.
   Pour trouver le bon dossier : Battle.net → roue dentée à côté de « Jouer » →
   « Afficher dans l'explorateur ».
2. Lance le jeu. À l'écran des personnages, vérifie que **Forever Music
   Player** est coché dans la liste des addons.

Si le jeu indique que l'addon est obsolète, tape en jeu
`/dump (select(4, GetBuildInfo()))` et reporte le nombre affiché sur la ligne
`## Interface:` du fichier `ForeverMusicPlayer.toc` (16001 pour la version
1.60.1).

### 2. Le compagnon

1. Installe [Python](https://www.python.org/downloads/) 3.11 ou plus récent, en
   cochant « Add python.exe to PATH ».
2. Double-clique sur `companion\run.bat`. Au premier lancement, il télécharge
   ce dont il a besoin, puis affiche « En attente du jeu... ».
3. Laisse cette fenêtre ouverte pendant que tu joues. `Ctrl+C` pour l'arrêter.

Le compagnon doit pouvoir voir le jeu à l'écran : si le jeu est réduit ou
caché derrière une autre fenêtre, les ordres attendent qu'il réapparaisse (la
musique, elle, continue).

## Utilisation

1. Ouvre ton application de musique, connecte-toi, et lance un titre une
   première fois (Windows ne connaît souvent une application qu'après sa
   première lecture).
2. Lance le compagnon, puis le jeu.
3. En jeu, tape `/fmp` ou clique sur le bouton de la minicarte.

| Dans la fenêtre | Effet |
| --- | --- |
| Lecture / pause | Lance ou met en pause ta musique. La musique du jeu est coupée. |
| Arrêt | Met ta musique en pause et **rétablit la musique du jeu**. |
| Précédent / suivant | Change de piste. |
| Aléatoire, répétition | Bascule le réglage dans l'application (son état se lit dans l'application). |
| Menu plateforme | Choisit l'application pilotée : automatique, Spotify, Deezer, Apple Music, YouTube Music. |
| Curseur de volume | Règle le volume de l'application dans le mélangeur de Windows. Clic droit : ne plus le gérer. Tant que tu n'y touches pas, le volume de l'application n'est pas modifié. |

Tu peux associer des touches dans Options → Raccourcis → AddOns, ou écrire des
macros : `/fmp toggle`, `/fmp next`...

« Automatique » pilote l'application que Windows considère comme le lecteur en
cours. Si l'application d'une plateforme n'est pas ouverte, le compagnon pilote
ton navigateur web (lecteur web de la plateforme) ; s'il n'y a rien du tout, il
ouvre la plateforme (réglable, voir `companion\config.example.toml`).

### La musique du jeu

- Seul l'interrupteur « Musique » du jeu est basculé. Les curseurs de volume ne
  sont jamais modifiés : la musique revient au même niveau.
- Si la musique du jeu était déjà coupée avant, elle le reste après l'arrêt.
- Si tu la réactives toi-même pendant l'écoute (Ctrl+M), ton choix est gardé.
- À la déconnexion ou à la fermeture du jeu, les réglages du jeu sont remis en
  place avant d'être enregistrés : même si tu supprimes l'addon, le jeu ne
  reste pas muet.
- Après un `/reload` ou un changement rapide de personnage, le lecteur reprend
  dans le même état. Après une vraie pause (plus de 3 minutes), il redémarre
  arrêté.

### Commandes

| Commande | Effet |
| --- | --- |
| `/fmp` | Affiche ou masque le lecteur. |
| `/fmp play`, `pause`, `stop`, `toggle`, `next`, `prev`, `shuffle`, `repeat` | Les boutons, en commandes. |
| `/fmp platform auto\|spotify\|deezer\|apple\|youtube` | Choisit la plateforme. |
| `/fmp volume 0-100\|off` | Règle le volume de l'application, ou cesse de le gérer. |
| `/fmp ambience on\|off` | Coupe aussi les sons d'ambiance pendant la lecture. |
| `/fmp pausemusic on\|off` | Rétablit la musique du jeu pendant les pauses. |
| `/fmp beacon on\|off` | Active ou coupe la balise de pixels. |
| `/fmp beacon size 2-12` | Taille des cellules de la balise, en pixels (4 par défaut). |
| `/fmp beacon corner topleft\|topright\|bottomleft\|bottomright` | Coin de l'écran où la balise est dessinée. |
| `/fmp minimap`, `lock`, `scale 0.6-1.6`, `reset` | Bouton de minicarte, verrouillage, taille et position de la fenêtre. |
| `/fmp status`, `/fmp help` | État actuel, aide. |

## Comment l'addon parle au compagnon

L'addon dessine dans un coin de l'écran une **balise** : une bande de 24 petits
carrés de couleur (96 × 4 pixels par défaut). Leurs couleurs codent ce que tu
demandes : lecture ou pause, plateforme, volume, dernier ordre (suivant,
précédent...). Le compagnon lit ces pixels à l'écran, comme le ferait un outil
de capture, vérifie une somme de contrôle, puis agit sur l'application de
musique.

La balise se cache quelques secondes après l'arrêt du lecteur. Le détail du
codage est décrit en tête de `ForeverMusicPlayer/Protocol.lua`.

## Règles de Blizzard

**L'addon** respecte la politique de développement d'addons de Blizzard :

- gratuit, sans publicité ni appel aux dons ;
- code entièrement lisible, sans rien de caché ;
- aucun message envoyé à d'autres joueurs ni au serveur, aucune charge pour
  les royaumes ;
- aucune automatisation du jeu, aucune lecture de données de combat. Il se
  limite à afficher une fenêtre, dessiner des carrés de couleur et basculer le
  réglage « Musique », ce que le raccourci Ctrl+M du jeu fait déjà.

**Le compagnon** mérite une mise en garde honnête. Il ne lit pas la mémoire du
jeu, ne touche à aucun de ses fichiers, ne lui envoie aucune touche ni aucun
clic, et ne donne aucun avantage en jeu : il regarde quelques pixels à l'écran.
Mais Blizzard n'a jamais autorisé explicitement les programmes externes qui
lisent l'écran du jeu, et son contrat de licence interdit en termes larges les
logiciels tiers non autorisés. C'est une **zone grise** : je n'ai trouvé aucune
prise de position officielle sur ce cas précis, ni dans un sens ni dans
l'autre. Tu l'utilises donc en connaissance de cause.

Pour rester strictement dans les règles, sans aucun programme externe : tape
`/fmp beacon off` et ne lance pas le compagnon. L'addon continue de couper et
rétablir la musique du jeu ; tu pilotes alors ta musique avec les touches
multimédias de ton clavier.

## Dépannage

| Problème | Piste |
| --- | --- |
| Le compagnon reste sur « En attente du jeu... » | Le lecteur est-il en lecture ou en pause ? (La balise se cache à l'arrêt.) Le jeu est-il en mode fenêtré (plein écran) ? Une autre fenêtre ou un compteur d'images par seconde couvre-t-il le coin de l'écran ? Essaie `/fmp beacon corner bottomleft` ou `/fmp beacon size 6`. Un filtre de couleurs ou le HDR peuvent aussi gêner la lecture. `run.bat --find` cherche la balise une fois et dit ce qu'il voit. |
| « Spotify n'est pas ouvert, ou n'a encore rien joué » | Lance un titre une fois dans l'application. `run.bat --list` affiche les applications que Windows permet de piloter et comment le compagnon les reconnaît. |
| La mauvaise application réagit | Choisis la plateforme dans le menu au lieu de « Automatique ». Pour un cas particulier, voir `companion\config.example.toml`. |
| Le volume ne change pas | Le compagnon règle le curseur de l'application dans le mélangeur de volume de Windows. Pour un lecteur web, c'est le volume de tout le navigateur. |
| La musique du jeu reste coupée après un plantage du jeu | Ctrl+M en jeu, ou Options → Audio → Musique. |
| Les boutons en jeu ne font rien | Le compagnon est-il lancé ? La balise est-elle activée (`/fmp status`) ? |

## Développement

```
ForeverMusicPlayer/        l'addon
  ForeverMusicPlayer.toc     fiche de l'addon et ordre de chargement
  Locales.lua                tous les textes (anglais, français)
  Protocol.lua               codage de la balise (sans API du jeu)
  Core.lua                   état du lecteur, réglages, commandes
  Audio.lua                  coupure et retour de la musique du jeu
  Beacon.lua                 dessin de la balise
  UI.lua                     fenêtre, menu, bouton de minicarte
  Bindings.xml               raccourcis clavier
  Media/                     icônes (générées par tools/make_icons.py)
companion/                 le compagnon Windows (Python)
  fmp_companion/
    protocol.py              décodage de la balise (miroir de Protocol.lua)
    locator.py               recherche de la balise dans une capture
    capture.py               surveillance de l'écran
    controller.py            des messages de la balise aux actions
    media.py, config.py      plateformes et réglages
    media_windows.py         contrôles multimédias et mélangeur de Windows
  tests/
tests/lua/                 tests de l'addon, avec un faux environnement WoW
tools/make_icons.py        dessine les icônes
```

Lancer les tests (Lua 5.1, Python 3.11+ avec `numpy` et `pytest`) :

```sh
lua5.1 tests/lua/run.lua            # l'addon
cd companion && python -m pytest     # le compagnon, dont un test de bout en bout
```

Le test de bout en bout fait jouer une session au vrai code Lua de l'addon,
peint sa balise sur un faux écran et vérifie les ordres reçus par de fausses
applications de musique. Ce que les tests ne couvrent pas : l'affichage réel
dans le client du jeu et les appels à Windows (seuls leurs noms et leurs types
sont vérifiés, contre les définitions des bibliothèques utilisées).

### Premier essai en jeu

À vérifier lors du premier lancement dans le vrai client :

1. L'addon apparaît dans la liste et se charge sans erreur (`/console scriptErrors 1`).
2. La fenêtre et ses icônes s'affichent ; le bouton de la minicarte aussi.
3. Lecture coupe la musique du jeu, Arrêt la rétablit.
4. `run.bat --find` trouve la balise pendant la lecture.
5. Lecture, pause, suivant et précédent agissent sur l'application de musique.
6. Le curseur de volume agit sur l'application dans le mélangeur de Windows.
