# Testing the VirtualDJ link on a real VirtualDJ

The link has only ever run against a stand-in (`tests/fake_virtualdj.py`). This checks it
against the real thing. It takes about 20 minutes and needs VirtualDJ Pro, two or three
songs that are also in Precision's library, and Python 3 (only for step 2).

Anything that fails: click **Copy diagnostics** in the DJ tab (or save the probe report from
step 2) and send it back. Both say exactly which question VirtualDJ didn't understand.

## 1. Switch the link on in VirtualDJ

1. Settings > Extensions > Effects > Other > enable **Network Control**.
2. Set it as an **Auto-Start** master effect, click its cog and note the **port** (and
   password, if you set one).
3. For beat-exact timing: Settings > Options, set `os2lDirectIp` to `127.0.0.1:9996`.
   Note whether the option exists under that exact name.
4. Load a song on deck 1 and press play.

## 2. Ask VirtualDJ directly (no Precision needed)

```
python tools/vdj_probe.py --port <port> [--password <pw>]
```

It prints what VirtualDJ answers for every question Precision asks, how fast, whether the
position is a 0-1 fraction or a percentage, and whether OS2L beats arrive (it listens on
port 9996 for 10 s, so keep the song playing and **close Precision first**). Send me
`vdj_probe_report.txt`. Run it three times: playing on deck 1, paused on deck 1, and
playing on deck 2 with deck 1 stopped.

## 3. Follow it in Precision

Open the DJ tab, choose **VirtualDJ**, enter the port, press **Reconnect**. Tick each:

| # | Do this in VirtualDJ | Expect in Precision | OK? |
|---|---|---|---|
| 1 | Nothing loaded | Status says connected, "Nothing on the deck" | |
| 2 | Load a song that is in your library | Title, artist, deck; "Show: ... (matched by ...)" | |
| 3 | Press play | Timeline plays; status says Playing | |
| 4 | Pause, then play again | Timeline pauses, then continues from the same spot | |
| 5 | Click the middle of the waveform | Playhead jumps there within ~0.3 s | |
| 6 | Pitch fader to +8%, then -8% | Playhead stays in step (no creeping apart over 30 s) | |
| 7 | Hit a hot cue / loop | Playhead follows the jump | |
| 8 | Load a song **not** in the library | "Not in your library, so the lights wait" | |
| 9 | Load song B on deck 2, crossfade over | Show switches to B once VirtualDJ makes deck 2 active; note *when* | |
| 10 | Eject the track | Back to "Nothing on the deck" | |
| 11 | Quit VirtualDJ, restart it | Status goes to not connected, then reconnects by itself | |
| 12 | Wrong password / wrong port | Clear message (refused / can't reach), no freezing | |
| 13 | Watch the beat (OS2L on) | Lights hit the kick; try the Light offset slider | |

For #5-6, tap *Copy diagnostics* afterwards if anything looked off by ear.

## 4. Things I'd like to know

* Does `os2lDirectIp` exist, and does VirtualDJ connect to us after setting it?
* Does the frame rate stay smooth while polling (the poll loop runs on the main thread)?
* Which deck does VirtualDJ call "active" during a crossfade: when does the show switch?
* Does a file path in VirtualDJ match your library entry (drive letters, network paths)?

## What the diagnostics show

The **Copy diagnostics** button (DJ tab, VirtualDJ selected) copies: your settings, link
status, poll rate, the current track, OS2L client and beat counts, a table of every
question with how often it was asked, how many answers were errors or empty, the slowest
reply and the last answer, and a log of recent events (first answer to each question,
every change, connection drops, HTTP errors, OS2L beat jumps).
