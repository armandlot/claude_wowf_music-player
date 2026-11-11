"""Companion of the Forever Music Player addon.

    python -m fmp_companion            run until Ctrl+C
    python -m fmp_companion --list     show the music apps Windows can control
    python -m fmp_companion --find     look for the beacon on screen once

The companion reads the small strip of coloured pixels the addon draws in a
corner of the game, and passes the orders on to the music app through the
Windows media controls. It never reads the game's memory or files, and never
sends it any input.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
import time
from pathlib import Path

from . import __version__
from .config import Config, load

IDLE_INTERVAL = 0.25  # seconds between two looks while the beacon is out of sight


def _log(text: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {text}", flush=True)


async def _list_sessions(config: Config) -> None:
    from .media import is_browser, matches
    from .media_windows import WindowsMediaBackend

    sessions = await WindowsMediaBackend(config).sessions()
    if not sessions:
        print("Aucune application de musique n'est connue de Windows pour l'instant.")
        print("Ouvre ton application et lance un titre, puis recommence.")
        return
    print("Applications que Windows permet de piloter :")
    for session in sessions:
        owners = [p.name for p in config.platforms.values() if matches(session.app_id, p)]
        if not owners and is_browser(session.app_id, config):
            owners = ["navigateur web"]
        track = await session.now_playing()
        title = " - ".join(part for part in (track or ()) if part)
        state = "en lecture" if session.is_playing() else "en pause"
        print(f"  {session.app_id}")
        print(f"      reconnu comme : {', '.join(owners) or 'inconnu (voir config.example.toml)'}")
        print(f"      {state}{' : ' + title if title else ''}")


def _find_once() -> None:
    from .capture import MssGrabber, ScreenReader

    grabber = MssGrabber()
    try:
        reader = ScreenReader(grabber, log=print)
        message = reader.read()
    finally:
        grabber.close()
    if message is None:
        print("Balise introuvable. Vérifie que le jeu est visible à l'écran et que le lecteur")
        print("est en lecture ou en pause (la balise se cache quelques secondes après l'arrêt).")
    else:
        print(f"Message lu : {message}")


async def _run(config: Config) -> None:
    from .capture import MssGrabber, ScreenReader
    from .controller import Controller
    from .media_windows import WindowsMediaBackend

    grabber = MssGrabber()
    reader = ScreenReader(grabber, log=_log)
    controller = Controller(WindowsMediaBackend(config), config, log=_log)
    _log(f"Forever Music Player - compagnon {__version__}. Ctrl+C pour quitter.")
    _log("En attente du jeu...")
    try:
        while True:
            started = time.monotonic()
            await controller.handle(reader.read())
            await controller.tick()
            interval = config.interval if reader.locked else IDLE_INTERVAL
            await asyncio.sleep(max(0.01, interval - (time.monotonic() - started)))
    finally:
        grabber.close()


def main() -> int:
    parser = argparse.ArgumentParser(prog="fmp_companion", description="Compagnon de l'addon Forever Music Player.")
    parser.add_argument("--config", type=Path, default=Path("config.toml"),
                        help="fichier de réglages facultatif (défaut : config.toml)")
    parser.add_argument("--list", action="store_true", help="affiche les applications de musique pilotables")
    parser.add_argument("--find", action="store_true", help="cherche la balise à l'écran une fois")
    parser.add_argument("--version", action="version", version=__version__)
    args = parser.parse_args()

    if sys.platform != "win32":
        print("Ce compagnon fonctionne sous Windows uniquement.")
        return 1
    try:
        config = load(args.config)
    except (ValueError, OSError) as error:
        print(f"Réglages illisibles ({args.config}) : {error}")
        return 1

    try:
        if args.list:
            asyncio.run(_list_sessions(config))
        elif args.find:
            _find_once()
        else:
            asyncio.run(_run(config))
    except KeyboardInterrupt:
        print("\nCompagnon arrêté.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
