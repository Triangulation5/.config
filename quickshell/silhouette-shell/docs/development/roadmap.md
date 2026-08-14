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

## Medium

- Split up monolithic files and make the shell more modular. Prioritize the
  easy-to-clean ones.
- Add a profile data surface with your user icon, user name and something
  like `josh@core`, plus a `fastfetch`-style info page with stats.
- Add more dynamic features like dragging installers onto the pill to
  install applications.
- Polkit password prompts on the pill's surface.

## Hard

- iPhone-style dynamic island face ID verification on the lockscreen.
- Make authentication prompts from Fedora run on the pill.
- Make the lockscreen use fingerprint, make that a toggle, and restart the
  fingerprint daemon when it fails so fingerprint can always stay enabled.
- Add a custom theme switcher (vague theme, old Ricelin theme).
- Add an AI assistant like the Google Gemini Assistant on Android.
- Open terminal applications via the launcher.
