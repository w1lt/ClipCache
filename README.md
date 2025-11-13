# ClipCache

A macOS menu bar app that intelligently caches your clipboard history, allowing you to paste multiple items in sequence with a single keyboard shortcut.

![ClipCache](image.png)

## How It Works

ClipCache monitors your clipboard and groups copied items into batches using a "copy window" system:

1. **Copy Window**: When you copy the first item, a time window opens (default: 30 seconds)
2. **Window Extension**: Any additional copies within this window extend the timer and add to the cache
3. **Persistent Cache**: After the window closes, the cache stays available indefinitely
4. **Reset on New Copy**: When you copy something new after the window has closed, the cache resets and a new window begins

This design allows you to:

- Copy multiple items in quick succession (screenshots, text snippets, etc.)
- Paste them all later using a single keyboard shortcut
- Keep your cache available until you're ready to start a new batch

## Usage

### Basic Flow

1. **Copy multiple items** within the copy window timeframe:

   ```
   Copy screenshot → Copy text → Copy another image → Copy more text
   ```

2. **Paste the entire batch** using the paste shortcut (default: `Cmd+Shift+X`):

   - All items in the cache will be pasted in sequence
   - Images are pasted first, then text items
   - Each item is pasted with a configurable cooldown delay (default: 200ms)

3. **Clear the cache** when needed:
   - Use the clear shortcut (default: `Cmd+Shift+R`)
   - Or click "Clear Cache" in the menu

### Menu Bar

Click the ClipCache icon in your menu bar to access:

- **Settings**: Configure shortcuts, capture options, menu bar display, and more
- **Actions**: Start/stop capture, clear cache
- **Quit**: Exit the app

### Keyboard Shortcuts

- **Paste Cache** (default: `Cmd+Shift+X`): Pastes all items in the cache sequentially
- **Clear Cache** (default: `Cmd+Shift+R`): Clears the current cache

Both shortcuts can be customized in Settings → Hotkeys.

## Features

- **Smart Copy Window**: Groups related copies together automatically
- **Image & Text Support**: Captures both images and text (configurable)
- **Menu Bar Display**: Optional display of image count and timer countdown
- **Configurable Settings**:
  - Copy window duration (1-60 seconds)
  - Paste cooldown delay (50-1000ms)
  - Keyboard shortcuts for paste and clear
  - Capture options (images/text)
  - Menu bar display options
  - Launch on startup
- **Auto-start**: Begins capturing automatically when launched

## Requirements

- macOS 12.0 or later
- Accessibility permissions (required for global keyboard shortcuts)

The app will prompt you to grant accessibility permissions on first launch.

## Installation

1. Download the latest release
2. Move ClipCache to your Applications folder (the app will prompt you on first launch)
3. Launch ClipCache
4. Grant accessibility permissions when prompted
5. Start copying and pasting!

## Example Workflow

**Scenario**: You're preparing a presentation and need to copy multiple screenshots and text snippets.

1. Take a screenshot (`Cmd+Shift+3`) → ClipCache captures it
2. Copy some text → ClipCache adds it to the cache
3. Take another screenshot → ClipCache extends the window and adds it
4. Copy more text → Added to cache
5. Switch to your presentation app
6. Press `Cmd+Shift+X` → All items paste automatically in sequence!

The copy window ensures all these related items stay grouped together, and you can paste them all at once when you're ready.

## Settings

Access settings via the menu bar icon:

- **Hotkeys**: Customize keyboard shortcuts for paste and clear
- **Capture Options**: Choose what to capture (images, text, or both)
- **Menu Bar Display**: Show/hide image count and timer countdown
- **Copy Window Timer**: Adjust the time window duration (1-60 seconds)
- **Paste Cooldown**: Adjust delay between pastes (50-1000ms)
- **Open on Startup**: Launch ClipCache automatically when you log in

## License

Copyright © Will Whitehead 2025
