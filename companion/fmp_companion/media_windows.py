"""Media controls on Windows.

Playback goes through the system media transport controls, the same service
behind the media keys of a keyboard and the player shown in the Windows
volume flyout. Every app that registers there can be driven: Spotify, Deezer,
Apple Music, and web browsers playing YouTube Music or a web player. Nothing
is sent to the game, and no account or key of any music service is needed.

Volume goes through the Windows volume mixer (the per-app sliders).
"""

from __future__ import annotations

import os
import sys

# COM must be set up the same way for the two libraries used here; this line
# has to run before `pycaw` (and its `comtypes`) is imported.
setattr(sys, "coinit_flags", 0)

import winrt.runtime
from winrt.windows.media import MediaPlaybackAutoRepeatMode as RepeatMode
from winrt.windows.media.control import (
    GlobalSystemMediaTransportControlsSession as WinSession,
    GlobalSystemMediaTransportControlsSessionManager as SessionManager,
    GlobalSystemMediaTransportControlsSessionPlaybackStatus as PlaybackStatus,
)

from .config import Config
from .media import MediaSession, mixer_names, pick_session

try:
    winrt.runtime.init_apartment(winrt.runtime.ApartmentType.MULTI_THREADED)
except Exception:
    pass  # already set up by something else in this process

_NEXT_REPEAT = {
    RepeatMode.NONE: RepeatMode.LIST,
    RepeatMode.LIST: RepeatMode.TRACK,
    RepeatMode.TRACK: RepeatMode.NONE,
}


class WindowsSession:
    def __init__(self, session: WinSession) -> None:
        self._session = session
        self.app_id: str = session.source_app_user_model_id

    def is_playing(self) -> bool:
        info = self._session.get_playback_info()
        return info is not None and info.playback_status == PlaybackStatus.PLAYING

    async def play(self) -> bool:
        return await self._session.try_play_async()

    async def pause(self) -> bool:
        return await self._session.try_pause_async()

    async def next(self) -> bool:
        return await self._session.try_skip_next_async()

    async def previous(self) -> bool:
        return await self._session.try_skip_previous_async()

    async def toggle_shuffle(self) -> bool:
        info = self._session.get_playback_info()
        if info is None or not info.controls.is_shuffle_enabled:
            return False
        return await self._session.try_change_shuffle_active_async(not info.is_shuffle_active)

    async def cycle_repeat(self) -> bool:
        info = self._session.get_playback_info()
        if info is None or not info.controls.is_repeat_enabled:
            return False
        current = info.auto_repeat_mode or RepeatMode.NONE
        return await self._session.try_change_auto_repeat_mode_async(_NEXT_REPEAT[current])

    async def now_playing(self) -> tuple[str, str] | None:
        properties = await self._session.try_get_media_properties_async()
        if properties is None:
            return None
        return properties.artist, properties.title


class WindowsMediaBackend:
    def __init__(self, config: Config) -> None:
        self.config = config
        self._manager: SessionManager | None = None

    async def _get_manager(self) -> SessionManager:
        if self._manager is None:
            self._manager = await SessionManager.request_async()
        return self._manager

    async def sessions(self) -> list[WindowsSession]:
        manager = await self._get_manager()
        return [WindowsSession(session) for session in manager.get_sessions()]

    async def find_session(self, platform: str) -> MediaSession | None:
        known = self.config.platforms.get(platform)
        if known is None:  # "auto": whatever Windows considers the current player
            manager = await self._get_manager()
            current = manager.get_current_session()
            return WindowsSession(current) if current is not None else None

        sessions = await self.sessions()
        index = pick_session(
            [session.app_id for session in sessions],
            [session.is_playing() for session in sessions],
            known, self.config,
        )
        return sessions[index] if index is not None else None

    def set_volume(self, session: MediaSession, percent: int) -> bool:
        names = mixer_names(session.app_id, self.config)
        if not names:
            return False
        try:
            from pycaw.pycaw import AudioUtilities
        except ImportError:
            return False

        level = max(0.0, min(1.0, percent / 100))
        done = False
        for audio in AudioUtilities.GetAllSessions():
            try:
                process = audio.Process
                if process is not None and process.name().lower() in names:
                    audio.SimpleAudioVolume.SetMasterVolume(level, None)
                    done = True
            except Exception:  # the program closed while we were looking at it
                continue
        return done

    def launch(self, platform: str) -> bool:
        known = self.config.platforms.get(platform)
        if known is None or not known.launch:
            return False
        try:
            os.startfile(known.launch)
        except OSError:
            return False
        return True
