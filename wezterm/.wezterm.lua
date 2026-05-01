local wezterm = require 'wezterm'

wezterm.on("format-tab-title", function(tab)
  local index = tab.tab_index + 1

  local pane = tab.active_pane
  local title = pane.title or ""

  title = title
    :gsub("^.*\\", "")
    :gsub("%.exe$", "")
    :gsub("%s+$", "")

  return {
    { Text = string.format(" %d:%s ", index, title) }
  }
end)

return {
    default_prog = { "powershell.exe" },
    font = wezterm.font_with_fallback({
        "JetBrainsMono Nerd Font",
        "FiraCode Nerd Font",
    }),
    font_size = 18.0,
    hide_tab_bar_if_only_one_tab = true,
    tab_bar_at_bottom = true,
    use_fancy_tab_bar = false,

    enable_tab_bar = true,

    window_padding = {
        left = 8,
        right = 8,
        top = 8,
        bottom = 8,
    },

    window_decorations = "INTEGRATED_BUTTONS|RESIZE",

    window_frame = {
        inactive_titlebar_bg = "#000000",
        active_titlebar_bg = "#000000",

        inactive_titlebar_fg = "#aaaaaa",
        active_titlebar_fg = "#ffffff",

        inactive_titlebar_border_bottom = "#000000",
        active_titlebar_border_bottom = "#000000",
    },

    colors = {
        tab_bar = {
          background = "#000000",

          active_tab = {
            bg_color = "#1a1a1a",
            fg_color = "#ffffff",
          },

          inactive_tab = {
            bg_color = "#000000",
            fg_color = "#777777",
          },

          inactive_tab_hover = {
            bg_color = "#111111",
            fg_color = "#cccccc",
          },

          new_tab = {
            bg_color = "#000000",
            fg_color = "#777777",
          },
        },

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
