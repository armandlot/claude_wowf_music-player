-- Locales.lua
-- Every text shown to the player lives here. English is the default; a locale
-- block below only has to override the strings it translates.

local ADDON_NAME, ns = ...

local L = {}
ns.L = L

L.TITLE = "Forever Music Player"

-- Chat messages
L.LOADED = "v%s loaded. Type |cffffd100/fmp|r to open the player."
L.COMPANION_HINT = "Start the companion app on your PC so the buttons can drive your music app."
L.CVAR_BLOCKED = "The game refused the sound change for now; it will be applied when you leave combat."
L.UNKNOWN_COMMAND = "Unknown command. Type |cffffd100/fmp help|r."
L.UNKNOWN_PLATFORM = "Unknown platform. Use: auto, spotify, deezer, apple, youtube."
L.BAD_NUMBER = "Expected a number between %s and %s."
L.PLATFORM_SET = "Platform: %s"
L.VOLUME_SET = "Music app volume: %d%%"
L.VOLUME_RELEASED = "Music app volume is no longer managed from the game."
L.OPTION_ON = "%s: on"
L.OPTION_OFF = "%s: off"
L.WINDOW_RESET = "Window position reset."
L.BEACON_SIZE = "Beacon cell size: %d px"
L.BEACON_CORNER = "Beacon corner: %s"

-- States
L.STATE_PLAYING = "Playing"
L.STATE_PAUSED = "Paused"
L.STATE_STOPPED = "Stopped"
L.GAME_MUSIC_MUTED = "Game music is muted."
L.GAME_MUSIC_ON = "Game music is on."

-- Option names (used in "%s: on/off" messages and /fmp status)
L.OPT_AMBIENCE = "Also mute ambient sounds"
L.OPT_PAUSE_RESTORE = "Bring the game music back while paused"
L.OPT_BEACON = "Pixel beacon"
L.OPT_MINIMAP = "Minimap button"
L.OPT_LOCK = "Window lock"

-- Buttons and tooltips
L.PLAY = "Play"
L.PAUSE = "Pause"
L.STOP = "Stop"
L.STOP_TIP = "Pauses your music app and brings the game music back."
L.NEXT = "Next track"
L.PREVIOUS = "Previous track"
L.SHUFFLE = "Shuffle on/off"
L.REPEAT = "Repeat: off / all / one"
L.ONE_WAY_TIP = "The current setting is shown in your music app."
L.CLOSE = "Hide the window"
L.CLOSE_TIP = "The music keeps playing. Type /fmp to show the window again."
L.PLATFORM = "Platform"
L.PLATFORM_TIP = "Choose which music app the buttons control."
L.PLATFORM_AUTO = "Automatic"
L.PLATFORM_AUTO_TIP = "Whichever app Windows considers the current media player."
L.VOLUME = "Volume"
L.VOLUME_TIP = "Volume of your music app in the Windows mixer. The game volume is never touched.\nMouse wheel: adjust. Right-click: stop managing the volume from the game."
L.VOLUME_UNMANAGED = "--"
L.MINIMAP_LEFT = "Left-click: show or hide the player"
L.MINIMAP_RIGHT = "Right-click: play / pause"
L.MINIMAP_DRAG = "Drag: move this button"

-- Slash command help
L.HELP = {
    "|cffffd100/fmp|r - show or hide the player",
    "|cffffd100/fmp play|r, |cffffd100pause|r, |cffffd100stop|r, |cffffd100toggle|r, |cffffd100next|r, |cffffd100prev|r, |cffffd100shuffle|r, |cffffd100repeat|r",
    "|cffffd100/fmp platform|r auto | spotify | deezer | apple | youtube",
    "|cffffd100/fmp volume|r 0-100 | off",
    "|cffffd100/fmp ambience|r on | off - also mute ambient sounds while playing",
    "|cffffd100/fmp pausemusic|r on | off - bring the game music back while paused",
    "|cffffd100/fmp beacon|r on | off | size 2-12 | corner topleft, topright, bottomleft, bottomright",
    "|cffffd100/fmp minimap|r, |cffffd100lock|r, |cffffd100scale|r 0.6-1.6, |cffffd100reset|r, |cffffd100status|r",
}

-- Key binding names (Options > Keybindings > AddOns)
L.BINDING_TOGGLEWINDOW = "Show / hide the player"
L.BINDING_PLAYPAUSE = "Play / pause"
L.BINDING_STOP = "Stop"
L.BINDING_NEXT = "Next track"
L.BINDING_PREVIOUS = "Previous track"
L.BINDING_VOLUMEUP = "Volume up"
L.BINDING_VOLUMEDOWN = "Volume down"

if GetLocale() == "frFR" then
    L.LOADED = "v%s chargé. Tapez |cffffd100/fmp|r pour ouvrir le lecteur."
    L.COMPANION_HINT = "Lancez le programme compagnon sur votre PC pour que les boutons pilotent votre application de musique."
    L.CVAR_BLOCKED = "Le jeu refuse le réglage du son pour l'instant ; il sera appliqué à la sortie du combat."
    L.UNKNOWN_COMMAND = "Commande inconnue. Tapez |cffffd100/fmp help|r."
    L.UNKNOWN_PLATFORM = "Plateforme inconnue. Choix : auto, spotify, deezer, apple, youtube."
    L.BAD_NUMBER = "Nombre attendu entre %s et %s."
    L.PLATFORM_SET = "Plateforme : %s"
    L.VOLUME_SET = "Volume de l'application de musique : %d %%"
    L.VOLUME_RELEASED = "Le volume de l'application de musique n'est plus géré depuis le jeu."
    L.OPTION_ON = "%s : activé"
    L.OPTION_OFF = "%s : désactivé"
    L.WINDOW_RESET = "Position de la fenêtre réinitialisée."
    L.BEACON_SIZE = "Taille des cellules de la balise : %d px"
    L.BEACON_CORNER = "Coin de la balise : %s"

    L.STATE_PLAYING = "Lecture"
    L.STATE_PAUSED = "En pause"
    L.STATE_STOPPED = "Arrêté"
    L.GAME_MUSIC_MUTED = "La musique du jeu est coupée."
    L.GAME_MUSIC_ON = "La musique du jeu est active."

    L.OPT_AMBIENCE = "Couper aussi les sons d'ambiance"
    L.OPT_PAUSE_RESTORE = "Rétablir la musique du jeu pendant la pause"
    L.OPT_BEACON = "Balise de pixels"
    L.OPT_MINIMAP = "Bouton de la minicarte"
    L.OPT_LOCK = "Verrouillage de la fenêtre"

    L.PLAY = "Lecture"
    L.PAUSE = "Pause"
    L.STOP = "Arrêt"
    L.STOP_TIP = "Met votre application de musique en pause et rétablit la musique du jeu."
    L.NEXT = "Piste suivante"
    L.PREVIOUS = "Piste précédente"
    L.SHUFFLE = "Lecture aléatoire oui/non"
    L.REPEAT = "Répétition : non / tout / un titre"
    L.ONE_WAY_TIP = "Le réglage en cours s'affiche dans votre application de musique."
    L.CLOSE = "Masquer la fenêtre"
    L.CLOSE_TIP = "La musique continue. Tapez /fmp pour réafficher la fenêtre."
    L.PLATFORM = "Plateforme"
    L.PLATFORM_TIP = "Choisissez l'application de musique pilotée par les boutons."
    L.PLATFORM_AUTO = "Automatique"
    L.PLATFORM_AUTO_TIP = "L'application que Windows considère comme le lecteur multimédia en cours."
    L.VOLUME = "Volume"
    L.VOLUME_TIP = "Volume de votre application de musique dans le mélangeur Windows. Le volume du jeu n'est jamais modifié.\nMolette : ajuster. Clic droit : ne plus gérer le volume depuis le jeu."
    L.MINIMAP_LEFT = "Clic gauche : afficher ou masquer le lecteur"
    L.MINIMAP_RIGHT = "Clic droit : lecture / pause"
    L.MINIMAP_DRAG = "Glisser : déplacer ce bouton"

    L.HELP = {
        "|cffffd100/fmp|r - afficher ou masquer le lecteur",
        "|cffffd100/fmp play|r, |cffffd100pause|r, |cffffd100stop|r, |cffffd100toggle|r, |cffffd100next|r, |cffffd100prev|r, |cffffd100shuffle|r, |cffffd100repeat|r",
        "|cffffd100/fmp platform|r auto | spotify | deezer | apple | youtube",
        "|cffffd100/fmp volume|r 0-100 | off",
        "|cffffd100/fmp ambience|r on | off - couper aussi les sons d'ambiance pendant la lecture",
        "|cffffd100/fmp pausemusic|r on | off - rétablir la musique du jeu pendant la pause",
        "|cffffd100/fmp beacon|r on | off | size 2-12 | corner topleft, topright, bottomleft, bottomright",
        "|cffffd100/fmp minimap|r, |cffffd100lock|r, |cffffd100scale|r 0.6-1.6, |cffffd100reset|r, |cffffd100status|r",
    }

    L.BINDING_TOGGLEWINDOW = "Afficher / masquer le lecteur"
    L.BINDING_PLAYPAUSE = "Lecture / pause"
    L.BINDING_STOP = "Arrêt"
    L.BINDING_NEXT = "Piste suivante"
    L.BINDING_PREVIOUS = "Piste précédente"
    L.BINDING_VOLUMEUP = "Monter le volume"
    L.BINDING_VOLUMEDOWN = "Baisser le volume"
end

-- Globals read by the key binding screen (see Bindings.xml).
BINDING_HEADER_FOREVERMUSICPLAYER = L.TITLE
BINDING_NAME_FOREVERMUSICPLAYER_TOGGLEWINDOW = L.BINDING_TOGGLEWINDOW
BINDING_NAME_FOREVERMUSICPLAYER_PLAYPAUSE = L.BINDING_PLAYPAUSE
BINDING_NAME_FOREVERMUSICPLAYER_STOP = L.BINDING_STOP
BINDING_NAME_FOREVERMUSICPLAYER_NEXT = L.BINDING_NEXT
BINDING_NAME_FOREVERMUSICPLAYER_PREVIOUS = L.BINDING_PREVIOUS
BINDING_NAME_FOREVERMUSICPLAYER_VOLUMEUP = L.BINDING_VOLUMEUP
BINDING_NAME_FOREVERMUSICPLAYER_VOLUMEDOWN = L.BINDING_VOLUMEDOWN
