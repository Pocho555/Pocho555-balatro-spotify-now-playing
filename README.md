# Spotify Now Playing for Balatro

A Balatro-style Spotify button for the game. It shows the current song and lets you go to the previous song, pause/play and skip without leaving the game.

- Round Spotify button in a screen corner, styled like the rest of the game UI
- Panel with title (scrolls when long), artist, progress bar and time
- Previous, Play/Pause and Skip buttons
- Panel pops up for a few seconds when a new song starts
- Config menu inside the game (Mods -> Spotify Now Playing -> Config)

**Windows only.** Requires the Spotify desktop app.

## Requirements

- Balatro (Steam)
- [Lovely](https://github.com/ethangreen-dev/lovely-injector)
- [Steamodded](https://github.com/Steamodded/smods)

## Installation

1. Install Lovely and Steamodded (see their pages).
2. Download the `SpotifyBalatro` zip from the [latest release](../../releases/latest).
3. Extract the zip into `%AppData%\Balatro\Mods` (paste `%AppData%\Balatro\Mods` into the Explorer address bar). You should end up with:

```
%AppData%\Balatro\Mods\SpotifyBalatro\main.lua
%AppData%\Balatro\Mods\SpotifyBalatro\helper.ps1
%AppData%\Balatro\Mods\SpotifyBalatro\config.lua
%AppData%\Balatro\Mods\SpotifyBalatro\SpotifyBalatro.json
```

4. Start Spotify, play something, start Balatro.

If you download the source code instead of the release, put the files in a folder inside the `Mods` folder yourself (the folder name does not matter).

## Usage

- **Left click** the button: open or close the panel
- **Right click** the button: move it to the next corner
- **Prev / Play-Pause / Next** buttons in the panel control Spotify

## Config

Open it in the game under Mods -> Spotify Now Playing -> Config.

| Tab | Option | What it does |
| --- | --- | --- |
| Look | Position | Top left, top right, bottom left, bottom right |
| Look | Accent color | Color of the play button and progress bar |
| Look | Size | Scales the button and panel |
| Look | Opacity | Transparency of the UI |
| Behavior | Show button | Show or hide the button |
| Behavior | Keep panel open | Keep the panel open permanently |
| Behavior | Popup on new song / Popup seconds | Open the panel briefly when the song changes |
| Behavior | Progress bar / Time | Show or hide them |
| Behavior | Scrolling title | Scroll long titles or cut them off |
| Behavior | Click sounds | Button click sound |
| Behavior | Hotkeys | F6 previous, F7 play/pause, F8 skip |

Settings are saved when you leave the mod menu.

## How it works

On start the mod launches a hidden PowerShell script (`helper.ps1`). The script reads the Windows media session of Spotify (the same data that shows in the Windows volume flyout), writes the current song to a small file next to the mod and reads commands from another one. It exits when Balatro closes.

- No login, no API key, no Spotify Premium needed
- No network access, nothing is sent anywhere
- Only the Spotify session is read and controlled, other media players are ignored

The script is started with `-ExecutionPolicy Bypass` so it can run without changing your system settings. Read `helper.ps1` if you want to check it, it is short.

## Notes

- Characters the Balatro font cannot show (for example Japanese) appear as `?`.
- Runs saved before Steamodded was installed may crash when continued. This is a Steamodded issue, not caused by this mod.

## Disclaimer

Not affiliated with or endorsed by Spotify AB, Balatro or PlayStack. Spotify is a trademark of Spotify AB.

## License

MIT, see [LICENSE](LICENSE).
