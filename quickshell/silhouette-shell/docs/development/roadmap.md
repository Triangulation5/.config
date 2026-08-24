# Roadmap

Ideas for the shell, grouped by how hard they are to build. Nothing here is
promised — it is a wishlist to pick from.

## Easy

- Minimalize the amount of code used in the shell. Turn reused code blocks
  into reusable components instead of rewriting similar things.
- Make every surface more lazy loaded (already pretty well implemented).
  Kill background surfaces after they have not been loaded for a while so
  the shell stays light on RAM, CPU and iGPU machines.
- Make everything asynchronous.
- Clean up the codebase and comments (make sure they are all docstyle).
- Fix the screencorner and the ears/flares of the pill while in notch style so
  that it matches the colors of the main pill.
- Find opportunities to optimize and refactor

## Medium

- Split up monolithic files and make the shell more modular. Prioritize the
  easy-to-clean ones.
- Add a profile data surface with your user icon, user name and something
  like `josh@core`, plus a `fastfetch`-style info page with stats.
- Add more dynamic features like dragging installers onto the pill to
  install applications.
- Downloading should show inside the island, downloads, via terminal (dnf
  upgrade, flatpak, etc). It should show the update name, and a level bar and
  the percentage. Follow the style of the pill as it is right now, I think the
  toast notification style and the osd's styles should fit something like this
  well.
- Super + Tab, application switcher. MacOS Mission control style, live
  thumbnail, match opacity of pill, keyboard navigation. Can't decide if this
  should show as a wide list of app icons (squircle styled) or it's own
  seperate surface now disconnected from the pill and in the middle of the
  screen.
- The music widget thing on the lockscreen should be clickable, when it is
  pressed it should expand the entire thing, and it should have the album in
  the center (as a square, and when it expands it's corners should become a
  little bit more rounded), Underneath the album cover there should be the song
  title (centered, like some hero text or whatever, bolded), under that should
  be the author and stuff (lower font). Underneath all that, there should be a
  card, the card should use the color of the theme, underneath that, there
  should be the ame level bar or the audio, mover thingy. On top of that there
  inside the card there should be where the audio is coming from, Firefox,
  spotify, youtube, etc. Underneath that inside the card, it should show
  previous, pause/play, and next.
- Make the calendar style thing inside the hover pill, only show 3 dates while
  90, and 100 percent ui scale, and 5 dates while on 110, and 125 percent ui
  scale.
- The album art, calendar, and all should disappear when the hover surface is
  closed, it should disappear in a way that does not leave behind artifacts.

## Hard

- iPhone-style dynamic island face ID verification on the lockscreen.
- Make authentication prompts from Fedora run on the pill.
- Make the lockscreen use fingerprint, make that a toggle, and restart the
  fingerprint daemon when it fails so fingerprint can always stay enabled.
- Add a custom theme switcher (vague theme, old Ricelin theme).
- Add an AI assistant like the Google Gemini Assistant on Android.
- Open terminal applications via the launcher.
