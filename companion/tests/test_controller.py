"""From beacon messages to actions on the music app."""

import asyncio
from dataclasses import replace

import pytest

from fmp_companion import config as config_module
from fmp_companion.config import Config
from fmp_companion.controller import LAUNCH_COOLDOWN, PENDING_PLAY_SECONDS, Controller
from fmp_companion.media import mixer_names, pick_session
from fmp_companion.protocol import BeaconMessage, Command

STOPPED = BeaconMessage(active=False, playing=False, platform=1, volume=None, nonce=9, seq=0, cmd=Command.NONE)
PLAYING = replace(STOPPED, active=True, playing=True)
PAUSED = replace(STOPPED, active=True, playing=False)


class FakeSession:
    def __init__(self, app_id, playing=False, track=("Artist", "Title")):
        self.app_id = app_id
        self.playing = playing
        self.track = track
        self.calls = []
        self.fail = False

    def is_playing(self):
        return self.playing

    async def _do(self, name):
        if self.fail:
            raise OSError("the app went away")
        self.calls.append(name)
        return True

    async def play(self):
        self.playing = True
        return await self._do("play")

    async def pause(self):
        self.playing = False
        return await self._do("pause")

    async def next(self):
        return await self._do("next")

    async def previous(self):
        return await self._do("previous")

    async def toggle_shuffle(self):
        return await self._do("shuffle")

    async def cycle_repeat(self):
        return await self._do("repeat")

    async def now_playing(self):
        return self.track


class FakeBackend:
    def __init__(self, **sessions):
        self.sessions = sessions  # platform key -> FakeSession
        self.volumes = []
        self.launched = []
        self.volume_ok = True

    async def find_session(self, platform):
        return self.sessions.get(platform)

    def set_volume(self, session, percent):
        self.volumes.append((session.app_id, percent))
        return self.volume_ok

    def launch(self, platform):
        self.launched.append(platform)
        return True


class Rig:
    def __init__(self, **sessions):
        self.backend = FakeBackend(**sessions)
        self.config = Config()
        self.logs = []
        self.now = 1000.0
        self.controller = Controller(self.backend, self.config, log=self.logs.append, clock=lambda: self.now)

    def see(self, message, times=2):
        """The beacon shows `message` for `times` captures in a row."""
        async def go():
            for _ in range(times):
                await self.controller.handle(message)
        asyncio.run(go())

    def tick(self, seconds=0.0):
        self.now += seconds
        asyncio.run(self.controller.tick())


def spotify(**kwargs):
    return FakeSession("Spotify.exe", **kwargs)


# First contact ----------------------------------------------------------------

def test_a_single_reading_is_not_acted_on():
    session = spotify()
    rig = Rig(spotify=session)
    rig.see(PLAYING, times=1)
    assert session.calls == []
    rig.see(PLAYING, times=1)
    assert session.calls == ["play"]


def test_first_sight_while_playing_starts_the_music():
    session = spotify()
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    assert session.calls == ["play"]


def test_first_sight_while_stopped_leaves_music_alone():
    session = spotify(playing=True)  # started by hand, outside the game
    rig = Rig(spotify=session)
    rig.see(STOPPED)
    rig.see(PAUSED)
    assert session.calls == []
    assert session.playing


def test_already_playing_is_not_restarted():
    session = spotify(playing=True)
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    assert session.calls == []


def test_nothing_seen_does_nothing():
    session = spotify(playing=True)
    rig = Rig(spotify=session)
    rig.see(None, times=5)
    rig.see(PLAYING)
    rig.see(None, times=5)  # loading screen: the music carries on
    assert session.calls == []
    assert session.playing


# Play, pause, stop --------------------------------------------------------------

def test_play_pause_play_stop():
    session = spotify()
    rig = Rig(spotify=session)
    rig.see(STOPPED)
    rig.see(PLAYING)
    rig.see(PAUSED)
    rig.see(PLAYING)
    rig.see(STOPPED)
    assert session.calls == ["play", "pause", "play", "pause"]


def test_repeated_messages_act_once():
    session = spotify()
    rig = Rig(spotify=session)
    rig.see(STOPPED)
    rig.see(PLAYING, times=50)
    assert session.calls == ["play"]


def test_pause_when_already_paused_does_nothing():
    session = spotify()
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    session.playing = False  # paused from the app itself
    session.calls.clear()
    rig.see(PAUSED)
    assert session.calls == []


def test_paused_to_stopped_does_nothing():
    session = spotify()
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    rig.see(PAUSED)
    session.calls.clear()
    rig.see(STOPPED)
    assert session.calls == []


# Events ----------------------------------------------------------------------------

def test_next_and_previous_run_once_each():
    session = spotify(playing=True)
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    rig.see(replace(PLAYING, seq=1, cmd=Command.NEXT), times=6)
    rig.see(replace(PLAYING, seq=2, cmd=Command.PREVIOUS), times=6)
    rig.see(replace(PLAYING, seq=3, cmd=Command.NEXT))
    assert session.calls == ["next", "previous", "next"]


def test_shuffle_and_repeat():
    session = spotify(playing=True)
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    rig.see(replace(PLAYING, seq=1, cmd=Command.SHUFFLE))
    rig.see(replace(PLAYING, seq=2, cmd=Command.REPEAT))
    assert session.calls == ["shuffle", "repeat"]


def test_next_while_stopped_skips_then_plays():
    session = spotify()
    rig = Rig(spotify=session)
    rig.see(STOPPED)
    rig.see(replace(PLAYING, seq=1, cmd=Command.NEXT))
    assert session.calls == ["next", "play"]


def test_event_seen_at_first_sight_is_not_replayed():
    session = spotify(playing=True)
    rig = Rig(spotify=session)
    rig.see(replace(PLAYING, seq=12, cmd=Command.NEXT))
    assert session.calls == []


def test_event_is_not_replayed_after_a_ui_reload():
    session = spotify(playing=True)
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    rig.see(replace(PLAYING, seq=1, cmd=Command.NEXT))
    assert session.calls == ["next"]
    # /reload: new nonce, counter back to zero, then the same old "next" value
    rig.see(replace(PLAYING, nonce=33, seq=0, cmd=Command.NONE))
    rig.see(replace(PLAYING, nonce=34, seq=1, cmd=Command.NEXT))
    assert session.calls == ["next"]


def test_counter_wraps_around():
    session = spotify(playing=True)
    rig = Rig(spotify=session)
    rig.see(replace(PLAYING, seq=63, cmd=Command.NEXT))
    rig.see(replace(PLAYING, seq=0, cmd=Command.NEXT))
    assert session.calls == ["next"]


# Platforms ---------------------------------------------------------------------------

def test_switching_platform_while_playing_moves_the_music():
    old, new = spotify(), FakeSession("Deezer.exe")
    rig = Rig(spotify=old, deezer=new)
    rig.see(PLAYING)
    rig.see(replace(PLAYING, platform=2))
    assert old.calls == ["play", "pause"]
    assert new.calls == ["play"]


def test_switching_platform_while_stopped_does_nothing():
    old, new = spotify(playing=True), FakeSession("Deezer.exe")
    rig = Rig(spotify=old, deezer=new)
    rig.see(STOPPED)
    rig.see(replace(STOPPED, platform=2))
    assert old.calls == [] and new.calls == []


def test_switching_between_two_names_for_the_same_app_keeps_playing():
    session = spotify()
    rig = Rig(auto=session, spotify=session)
    rig.see(replace(PLAYING, platform=0))
    rig.see(PLAYING)
    assert session.calls == ["play"]
    assert session.playing


# Volume --------------------------------------------------------------------------------

def test_volume_follows_the_slider():
    session = spotify()
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    assert rig.backend.volumes == [], "not managed: never touched"
    rig.see(replace(PLAYING, volume=40))
    rig.see(replace(PLAYING, volume=45))
    rig.see(replace(PLAYING, volume=None))
    assert rig.backend.volumes == [("Spotify.exe", 40), ("Spotify.exe", 45)]


def test_volume_is_applied_when_playback_starts():
    session = spotify()
    rig = Rig(spotify=session)
    rig.see(replace(STOPPED, volume=30))
    assert rig.backend.volumes == [], "player off: the app's volume is left alone"
    rig.see(replace(PLAYING, volume=30))
    assert rig.backend.volumes == [("Spotify.exe", 30)]


def test_volume_is_applied_at_first_sight_while_playing():
    rig = Rig(spotify=spotify())
    rig.see(replace(PLAYING, volume=70))
    assert rig.backend.volumes == [("Spotify.exe", 70)]


def test_unknown_mixer_entry_is_reported_once():
    rig = Rig(spotify=spotify())
    rig.backend.volume_ok = False
    rig.see(replace(PLAYING, volume=10))
    rig.see(replace(PLAYING, volume=20))
    assert sum("mélangeur" in line for line in rig.logs) == 1


# Apps that are not running --------------------------------------------------------------

def test_missing_app_is_opened_and_played_when_it_appears():
    rig = Rig()
    rig.see(replace(PLAYING, volume=55))
    assert rig.backend.launched == ["spotify"]
    assert any("Ouverture de Spotify" in line for line in rig.logs)

    rig.tick(2)  # still starting
    session = spotify()
    rig.backend.sessions["spotify"] = session
    rig.tick(2)
    assert session.calls == ["play"]
    assert rig.backend.volumes == [("Spotify.exe", 55)]
    rig.tick(2)
    assert session.calls == ["play"], "played once"


def test_missing_app_is_not_opened_twice_in_a_row():
    rig = Rig()
    rig.see(PLAYING)
    rig.see(PAUSED)
    rig.see(PLAYING)
    assert rig.backend.launched == ["spotify"]
    rig.now += LAUNCH_COOLDOWN + 1
    rig.see(PAUSED)
    rig.see(PLAYING)
    assert rig.backend.launched == ["spotify", "spotify"]


def test_delayed_play_is_dropped_after_stop_or_timeout():
    rig = Rig()
    rig.see(PLAYING)
    rig.see(STOPPED)
    session = spotify()
    rig.backend.sessions["spotify"] = session
    rig.tick(1)
    assert session.calls == [], "the player was stopped meanwhile"

    rig = Rig()
    rig.see(PLAYING)
    rig.tick(PENDING_PLAY_SECONDS + 1)
    session = spotify()
    rig.backend.sessions["spotify"] = session
    rig.tick(1)
    assert session.calls == [], "too late: starting music now would be a surprise"


def test_auto_launch_can_be_turned_off():
    rig = Rig()
    rig.config.auto_launch = False
    rig.see(PLAYING)
    assert rig.backend.launched == []
    assert any("n'est pas ouvert" in line for line in rig.logs)


def test_automatic_platform_never_opens_anything():
    rig = Rig()
    rig.see(replace(PLAYING, platform=0))
    assert rig.backend.launched == []


# Robustness -----------------------------------------------------------------------------

def test_a_failing_app_does_not_stop_the_companion():
    session = spotify()
    session.fail = True
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    assert any("Erreur" in line for line in rig.logs)
    session.fail = False
    rig.see(PAUSED)
    rig.see(PLAYING)
    assert session.calls[-1] == "play"


def test_track_changes_are_reported():
    session = spotify(track=("Daft Punk", "Around the World"))
    rig = Rig(spotify=session)
    rig.see(PLAYING)
    rig.tick(0)
    rig.tick(3)
    assert sum("Daft Punk - Around the World" in line for line in rig.logs) == 1
    session.track = ("", "Podcast")
    rig.tick(3)
    assert any(line.strip() == "♪ Podcast" for line in rig.logs)


# Which session belongs to which platform ------------------------------------------------------

def test_pick_session():
    config = Config()
    spotify_cfg, youtube_cfg, apple_cfg = (config.platforms[k] for k in ("spotify", "youtube", "apple"))
    ids = ["chrome.exe", "Spotify.exe", "AppleInc.AppleMusicWin_nzyj5cx40ttqa!App"]
    idle = [False, False, False]

    assert pick_session(ids, idle, spotify_cfg, config) == 1
    assert pick_session(ids, idle, apple_cfg, config) == 2
    assert pick_session(ids, idle, youtube_cfg, config) == 0, "no app of its own: the web browser"
    assert pick_session(["Spotify.exe"], [False], youtube_cfg, config) is None
    assert pick_session([], [], spotify_cfg, config) is None

    store = ["SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify"]
    assert pick_session(store, [False], spotify_cfg, config) == 0, "Microsoft Store version"

    two_browsers = ["msedge.exe", "chrome.exe"]
    assert pick_session(two_browsers, [False, True], youtube_cfg, config) == 1, "the one that is playing"
    assert pick_session(["chrome.exe", "Spotify.exe"], [True, False], spotify_cfg, config) == 1, "own app first"


def test_mixer_names():
    config = Config()
    assert mixer_names("Spotify.exe", config) == {"spotify.exe"}
    assert mixer_names("SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", config) == {"spotify.exe"}
    assert mixer_names("chrome.exe", config) == {"chrome.exe"}
    assert mixer_names("MSEdge", config) == {"msedge.exe"}
    assert "applemusic.exe" in mixer_names("AppleInc.AppleMusicWin_nzyj5cx40ttqa!App", config)
    assert mixer_names("SomeGame.Launcher!App", config) == set()


# Settings file ----------------------------------------------------------------------------------

def test_config_defaults_without_a_file(tmp_path):
    config = config_module.load(tmp_path / "missing.toml")
    assert config.auto_launch is True
    assert set(config.platforms) == {"spotify", "deezer", "apple", "youtube"}
    assert config_module.load(None).interval == 0.05


def test_config_file_overrides(tmp_path):
    path = tmp_path / "config.toml"
    path.write_text(
        'auto_launch = false\n'
        '[platforms.deezer]\n'
        'apps = ["Deezer", "MyDeezerMod"]\n'
        'launch = ""\n',
        encoding="utf-8",
    )
    config = config_module.load(path)
    assert config.auto_launch is False
    assert config.platforms["deezer"].apps == ["deezer", "mydeezermod"]
    assert config.platforms["deezer"].launch == ""
    assert config.platforms["deezer"].processes == ["Deezer.exe"], "untouched keys keep their default"
    assert config.platforms["spotify"].launch == "spotify:"


def test_config_rejects_unknown_platform(tmp_path):
    path = tmp_path / "config.toml"
    path.write_text('[platforms.tidal]\napps = ["tidal"]\n', encoding="utf-8")
    with pytest.raises(ValueError, match="tidal"):
        config_module.load(path)


def test_example_config_matches_the_defaults():
    from pathlib import Path

    example = Path(__file__).resolve().parents[1] / "config.example.toml"
    loaded = config_module.load(example)
    assert loaded == Config()
