# Calendar & Time

<!--toc:start-->
- [Calendar & Time](#calendar-time)
  - [Calendar](#calendar)
  - [Weather](#weather)
<!--toc:end-->

## Calendar

A month grid with the weather glance to the left and an event editor that
slides out to the right when you pick a day. The grid sizes itself to exactly
the rows the month needs, so it never wastes vertical space. Today keeps a
warm frame with the Ame ring, and days that hold events mark their number
with a small ember dot.

The editor lists the picked day's events with a delete tap, plus an add form
with title, all-day or timed times, repeat, and an optional multi-day span
that you can arm directly from the grid.

## Weather

Served by Open-Meteo, so no API key is needed. Location resolves once and is
cached, so a restart never re-hits the network for coordinates. By default it
uses a keyless IP lookup, or you can override the city in settings and it
geocodes that name instead. The forecast refreshes every 20 minutes and
drives both the current condition in the hover glance and a 24-hour strip.
