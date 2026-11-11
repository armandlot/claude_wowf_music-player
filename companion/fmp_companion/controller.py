"""Turns what the beacon says into actions on the music app.

The beacon mostly carries a wanted state ("playing on Spotify at 60%"), so
the controller acts on changes of that state, and never the other way round:
music started by hand outside the game is left alone while the in-game
player is stopped.
"""

from __future__ import annotations

import time
from collections.abc import Callable

from .config import Config
from .media import MediaBackend, MediaSession
from .protocol import BeaconMessage, Command

PENDING_PLAY_SECONDS = 45   # how long to wait for an app we just opened
LAUNCH_COOLDOWN = 30        # seconds before opening the same platform again
NOW_PLAYING_EVERY = 2.0     # seconds between two looks at the current track


class Controller:
    def __init__(self, backend: MediaBackend, config: Config,
                 log: Callable[[str], None] = print,
                 clock: Callable[[], float] = time.monotonic) -> None:
        self.backend = backend
        self.config = config
        self.log = log
        self.clock = clock

        self._seen: BeaconMessage | None = None      # last message read, not yet trusted
        self._current: BeaconMessage | None = None   # last message acted on
        self._pending_play: tuple[str, float] | None = None   # (platform, deadline)
        self._launched: dict[str, float] = {}
        self._warned: set[str] = set()
        self._track: tuple[str, str] | None = None
        self._next_track_check = 0.0

    # Reading the beacon ----------------------------------------------------

    async def handle(self, message: BeaconMessage | None) -> None:
        """Call with every reading of the beacon (None when it is not in sight)."""
        if message is None:
            return
        # A message counts once it has been read twice in a row: a capture
        # taken in the middle of a redraw is never acted on.
        if message != self._seen:
            self._seen = message
            return
        if message == self._current:
            return
        previous, self._current = self._current, message
        try:
            await self._apply(previous, message)
        except Exception as error:  # a media app that misbehaves must not stop the companion
            self.log(f"Erreur pendant la commande : {error!r}")

    async def _apply(self, previous: BeaconMessage | None, message: BeaconMessage) -> None:
        platform = message.platform_key

        # First sight of this game session (or of a UI reload): take the state
        # as it is. Start the music if the player says "playing", but never
        # pause or skip on the strength of old information.
        if previous is None or previous.nonce != message.nonce:
            self.log(f"Jeu détecté. Plateforme : {self._name(platform)}.")
            if message.playing:
                await self._play(platform)
                await self._volume(message)
            return

        platform_changed = message.platform != previous.platform
        if platform_changed:
            self.log(f"Plateforme : {self._name(platform)}.")
            self._pending_play = None
            if previous.playing:
                # Unless both names lead to the same app ("automatic" and
                # "Spotify" while Spotify is the current player).
                old = await self.backend.find_session(previous.platform_key)
                new = await self.backend.find_session(platform)
                if old is not None and (new is None or new.app_id != old.app_id):
                    await self._pause(previous.platform_key)

        if message.seq != previous.seq:
            await self._command(platform, message.cmd)

        if message.playing and (not previous.playing or platform_changed):
            await self._play(platform)
        elif previous.playing and not message.playing and not platform_changed:
            self._pending_play = None
            await self._pause(platform)

        started = message.playing and not previous.playing
        if message.volume != previous.volume or platform_changed or started:
            await self._volume(message)

    # Actions ---------------------------------------------------------------

    def _name(self, platform: str) -> str:
        known = self.config.platforms.get(platform)
        return known.name if known else "automatique"

    async def _session(self, platform: str) -> MediaSession | None:
        session = await self.backend.find_session(platform)
        if session is None:
            if platform not in self._warned:
                self._warned.add(platform)
                if platform == "auto":
                    self.log("Aucune application de musique ouverte. Lance ta musique une première fois.")
                else:
                    self.log(f"{self._name(platform)} n'est pas ouvert, ou n'a encore rien joué.")
        else:
            self._warned.discard(platform)
        return session

    async def _play(self, platform: str) -> None:
        session = await self._session(platform)
        if session is None:
            self._pending_play = (platform, self.clock() + PENDING_PLAY_SECONDS)
            self._launch(platform)
            return
        self._pending_play = None
        if not session.is_playing():
            await session.play()
        self.log(f"Lecture ({self._name(platform)}).")
        self._next_track_check = 0.0

    async def _pause(self, platform: str) -> None:
        session = await self.backend.find_session(platform)
        if session is not None and session.is_playing():
            await session.pause()
            self.log(f"Pause ({self._name(platform)}).")

    async def _command(self, platform: str, command: int) -> None:
        session = await self._session(platform)
        if session is None:
            return
        if command == Command.NEXT:
            await session.next()
            self.log("Piste suivante.")
        elif command == Command.PREVIOUS:
            await session.previous()
            self.log("Piste précédente.")
        elif command == Command.SHUFFLE:
            ok = await session.toggle_shuffle()
            self.log("Lecture aléatoire basculée." if ok else "Cette application ne permet pas de changer la lecture aléatoire.")
        elif command == Command.REPEAT:
            ok = await session.cycle_repeat()
            self.log("Répétition changée." if ok else "Cette application ne permet pas de changer la répétition.")
        self._next_track_check = 0.0

    async def _volume(self, message: BeaconMessage) -> None:
        if message.volume is None or not message.active:
            return
        session = await self.backend.find_session(message.platform_key)
        if session is None:
            return
        if self.backend.set_volume(session, message.volume):
            self.log(f"Volume : {message.volume} %.")
        elif "volume" not in self._warned:
            self._warned.add("volume")
            self.log("Volume : application introuvable dans le mélangeur Windows.")

    def _launch(self, platform: str) -> None:
        if not self.config.auto_launch or platform == "auto":
            return
        now = self.clock()
        if now - self._launched.get(platform, -LAUNCH_COOLDOWN) < LAUNCH_COOLDOWN:
            return
        self._launched[platform] = now
        if self.backend.launch(platform):
            self.log(f"Ouverture de {self._name(platform)}...")

    # Housekeeping ----------------------------------------------------------

    async def tick(self) -> None:
        """Call regularly: finishes a delayed play and reports track changes."""
        try:
            await self._finish_pending_play()
            await self._report_track()
        except Exception as error:
            self.log(f"Erreur : {error!r}")

    async def _finish_pending_play(self) -> None:
        if self._pending_play is None:
            return
        platform, deadline = self._pending_play
        current = self._current
        wanted = current is not None and current.playing and current.platform_key == platform
        if not wanted or self.clock() > deadline:
            self._pending_play = None
            return
        session = await self.backend.find_session(platform)
        if session is None:
            return
        self._pending_play = None
        self._warned.discard(platform)
        if not session.is_playing():
            await session.play()
        self.log(f"Lecture ({self._name(platform)}).")
        if current is not None:
            await self._volume(current)

    async def _report_track(self) -> None:
        current = self._current
        if current is None or not current.playing or self.clock() < self._next_track_check:
            return
        self._next_track_check = self.clock() + NOW_PLAYING_EVERY
        session = await self.backend.find_session(current.platform_key)
        if session is None:
            return
        track = await session.now_playing()
        if track and track != self._track and any(track):
            self._track = track
            artist, title = track
            self.log(f"  ♪ {artist} - {title}" if artist else f"  ♪ {title}")
