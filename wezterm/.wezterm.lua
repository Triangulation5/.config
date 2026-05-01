local wezterm = require 'wezterm'

return {
    default_prog = { "powershell.exe" },
    font_size = 18.0,
    hide_tab_bar_if_only_one_tab = true,

    enable_tab_bar = true,

    window_padding = {
        left = 8,
        right = 8,
        top = 8,
        bottom = 8,
    },

  colors = {
    foreground = "#CDCDCD",
    background = "#141415",

    cursor_bg = "#CDCDCD",
    cursor_border = "#CDCDCD",
    cursor_fg = "#141415",

    selection_bg = "#252530",

    ansi = {
      "#1C1C24",
      "#D8647E",
      "#7FA563",
      "#F3BE7C",
      "#7E98E8",
      "#BB9DBD",
      "#6E94B2",
      "#CDCDCD",
    },

    brights = {
      "#606079",
      "#D8647E",
      "#7FA563",
      "#F3BE7C",
      "#7E98E8",
      "#BB9DBD",
      "#90A0B5",
      "#E8B589",
    },
  }
}
