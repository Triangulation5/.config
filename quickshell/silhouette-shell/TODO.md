# Project TODO

## Current continuation

- [x] Restore the previous power-menu close timing and behavior.
- [x] Keep Material palette behavior across the shell; only lockscreen color
  tokens use the Washi palette equivalents.
- [x] Match the notch-ear outlines to the pill border and screen-corner fills
  to the pill surface.
- [x] Persist desktop-widget geometry and custom settings in local `flags.json`,
  including edits made before the file finishes loading; verified across reloads.
- [x] Load all desktop-widget QML types without shell QML errors and remove
  temporary validation files.
- [x] Review changed paths and the live shell reload; no new QML errors. Two
  existing `ShaderEffect` source warnings remain in unchanged effect components.
- [x] Commit and push the requested shell and attribution changes, excluding
  unrelated worktree edits.

# Implement MPD Music Integration in Silhouette Shell

## Objective

Integrate my existing MPD/ncmpcpp music setup into Silhouette Shell (Quickshell).

I want Silhouette Shell to automatically detect and display whatever music is currently playing through MPD, regardless of whether playback was initiated through ncmpcpp, my existing scripts, or another MPD client.

This should be a native, well-integrated feature of the shell, not a separate application or an isolated widget.

## 1. Inspect the Existing Environment First

Before writing any code, thoroughly inspect the project and understand its existing architecture.

In particular:

- Inspect the entire Silhouette Shell directory structure.
- Examine existing QML services, modules, components, animations, and shared state.
- Understand how the pill/dynamic island currently works.
- Examine existing configuration and settings systems.
- Inspect my music-related scripts, including the script I use to launch and control playback.
- Inspect my MPD configuration, ncmpcpp configuration, and any relevant user-level service definitions.
- Determine how MPD is started, configured, and accessed.
- Identify the actual MPD host, port, authentication requirements, and music directory.
- Check whether album artwork is already handled by any existing scripts or tools.

Do not assume a conventional MPD configuration. Discover how my actual environment works.

Do not modify my existing music scripts or MPD configuration unless absolutely necessary.

## 2. Core Music Service

Implement a centralized music service that communicates with MPD.

Prefer a native QML implementation using Qt networking capabilities, provided this fits the existing project architecture.

Requirements:

- Maintain a persistent connection to MPD.
- Retrieve current playback metadata.
- Detect playback, pause, stop, and track changes.
- Track playback position and duration.
- Support asynchronous updates.
- Use MPD's `idle` mechanism where appropriate instead of excessively polling.
- Handle connection failures and automatic reconnection.
- Handle MPD becoming unavailable or restarting.
- Avoid blocking the QML interface.
- Properly clean up connections and timers.

Expose a clean interface to other shell components.

Suggested properties:

- title
- artist
- album
- albumArtist
- file
- state
- duration
- position
- volume
- repeat
- random
- consume

Suggested methods:

- playPause()
- play()
- pause()
- stop()
- next()
- previous()
- seek(position)
- setVolume(value)

These are suggested interfaces, not mandatory names. Adapt them to existing project conventions.

## 3. Music Display and Integration

Integrate music information into the existing Silhouette Shell design.

Do not create an entirely separate UI system.

Investigate the existing pill implementation and determine the most natural way to introduce music information.

The pill should be able to display:

- Track title.
- Artist name.
- Album artwork, when available.
- Playback state.
- Playback progress.

Consider appropriate transitions when music starts, pauses, stops, or changes tracks.

Preserve existing pill behavior and animations. Do not break existing notification, clock, or other functionality.

## 4. Music Controls

Implement playback controls that communicate directly with MPD.

Include:

- Play/pause.
- Previous track.
- Next track.
- Seek/progress interaction.
- Volume control, if appropriate for the existing UI.

Controls should work regardless of which application initiated playback.

Do not duplicate playback logic or introduce a second music player.

## 5. Album Artwork

Investigate how album artwork is stored and retrieved in my existing music library.

Use MPD's available artwork functionality (`albumart` / `readpicture`) where appropriate.

Requirements:

- Display artwork when available.
- Handle missing artwork gracefully.
- Cache artwork to avoid repeatedly transferring the same image.
- Update artwork when the track changes.
- Avoid blocking the UI during artwork retrieval.
- Avoid unnecessary disk writes.

Do not assume every track has embedded artwork.

## 6. Architecture and Code Quality

Keep the implementation modular and consistent with Silhouette Shell.

The music service should be independent of visual components.

Other components should consume the music service rather than establishing their own MPD connections.

Avoid:

- Unnecessary dependencies.
- Excessive JavaScript.
- Constant polling.
- Duplicated state.
- Hardcoded assumptions about MPD configuration.
- Unnecessary Python or Rust components.
- Unrelated refactoring.

Prefer the simplest maintainable implementation that fits the existing codebase.

## 7. Error Handling

Account for:

- MPD not running.
- MPD temporarily disconnecting.
- Invalid or missing metadata.
- Empty playlists.
- Missing artwork.
- MPD authentication failures.
- Network/socket errors.
- Playback changing while a request is being processed.

The shell must remain fully functional when MPD is unavailable.

Music integration must never cause the entire shell to crash.

## 8. Testing and Verification

After implementation:

1. Verify that the service connects to my actual MPD instance.
2. Start playback through my existing music script.
3. Verify that the pill detects the track.
4. Change tracks through ncmpcpp and verify that the UI updates.
5. Pause and resume playback through ncmpcpp.
6. Verify that Quickshell reflects those changes.
7. Test playback controls initiated from Quickshell.
8. Test missing artwork.
9. Test MPD disconnecting and reconnecting.
10. Verify that existing Silhouette Shell functionality remains intact.

Do not claim something works without actually testing it.

## 9. Implementation Discipline

Work within the existing project rather than imposing a new architecture.

Before implementation, summarize your findings about:

- How my music setup works.
- How MPD is configured.
- How my existing scripts interact with it.
- How Silhouette Shell is structured.
- Where the integration should live.

Then implement the feature.

After implementation, provide a concise report covering:

- Files created.
- Files modified.
- Architectural decisions.
- Features implemented.
- Tests performed.
- Remaining limitations.

The final result should feel like a native Silhouette Shell feature, not an external music widget bolted onto it.

## And also fix the shell motion speed while in Material style, just make it the same as in Washi...
