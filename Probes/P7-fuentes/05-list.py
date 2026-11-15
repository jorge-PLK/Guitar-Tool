"""Lista candidatos de un JSON de yt-dlp --flat-playlist, con diff de duración vs Spotify."""
import json
import sys

SPOTIFY_S = 267.186
d = json.load(open(sys.argv[1]))
for e in d.get("entries", []):
    dur = e.get("duration")
    diff = None if dur is None else round(dur - SPOTIFY_S, 1)
    print(e.get("id"), "|", e.get("title"), "|", e.get("channel") or e.get("uploader"), "|", dur, "|", diff)
