;;; doom-vague-theme.el --- A dark, understated theme based on Vague -*- lexical-binding: t; no-byte-compile: t; -*-
;;
;; Author: Josh
;; Maintainer: Josh
;; Source: https://github.com/vague-theme/vague.nvim
;;
;;; Commentary:
;;
;; A port of the Vague colorscheme for Neovim.  Vague is deliberately
;; understated: a near-black background, muted grey text and a small set of
;; desaturated pastel accents.  The palette below is reproduced verbatim from
;; vague.nvim and mapped onto Doom's semantic color classes, so both the faces
;; defined here and the faces inherited from `doom-themes-base' share the same
;; look.
;;
;; Faces are grouped by area.  Faces for packages that are not installed are
;; harmless: Emacs stores theme face specs by name and applies them when the
;; package (and its faces) eventually load.
;;
;;; Code:

(require 'doom-themes)


;;
;;; Options

(defgroup doom-vague-theme nil
  "Options for the `doom-vague' theme."
  :group 'doom-themes
  :prefix "doom-vague-")

(defcustom doom-vague-padded-modeline doom-themes-padded-modeline
  "If non-nil, add padding to the mode-line.
Can be an integer to set the exact padding in pixels."
  :group 'doom-vague-theme
  :type '(choice integer boolean))

(defcustom doom-vague-italic-comments t
  "If non-nil, comments are italicized, as in Vague."
  :group 'doom-vague-theme
  :type 'boolean)

(defcustom doom-vague-italic-strings t
  "If non-nil, strings are italicized, as in Vague."
  :group 'doom-vague-theme
  :type 'boolean)


;;
;;; Theme definition

(def-doom-theme doom-vague
  "A dark, low-contrast theme based on the Vague colorscheme."
  :family 'doom-vague
  :background-mode 'dark

  ;; name        default   256            16
  ((bg          '("#141415" "black"       "black"))
   (bg-alt      '("#18181c" "black"       "black"))
   (fg          '("#cdcdcd" "#cdcdcd"     "white"))
   (fg-alt      '("#878787" "#878787"     "brightblack"))

   ;; A spectrum from the darkest background (base0) to the brightest
   ;; foreground (base8), used throughout `doom-themes-base'.
   (base0       '("#0f0f10" "black"       "black"))
   (base1       '("#141415" "black"       "black"))
   (base2       '("#18181c" "#1c1c1c"     "black"))
   (base3       '("#1c1c24" "#262626"     "brightblack"))
   (base4       '("#252530" "#303030"     "brightblack"))
   (base5       '("#333738" "#3a3a3a"     "brightblack"))
   (base6       '("#606079" "#5f5f87"     "brightblack"))
   (base7       '("#878787" "#878787"     "brightblack"))
   (base8       '("#d7d7d7" "#d7d7d7"     "white"))

   (grey        base4)
   (red         '("#d8647e" "#d75f87"     "red"))
   (orange      '("#e0a363" "#d7af5f"     "brightred"))
   (green       '("#7fa563" "#87af5f"     "green"))
   (teal        '("#b4d4cf" "#afd7d7"     "brightcyan"))
   (yellow      '("#f3be7c" "#f5d787"     "yellow"))
   (blue        '("#6e94b2" "#7f9fbf"     "blue"))
   (dark-blue   '("#4c6b87" "#5f7f9f"     "blue"))
   (magenta     '("#bb9dbd" "#bfafd7"     "magenta"))
   (violet      '("#aeaed1" "#afafd7"     "brightmagenta"))
   (cyan        '("#9bb4bc" "#9fb8bf"     "cyan"))
   (dark-cyan   '("#6f8d94" "#5f8787"     "cyan"))

   ;; Doom's universal syntax classes.
   (highlight   '("#7e98e8" "#8787d7"     "brightblue"))
   (vertical-bar base4)
   (selection   base5)
   (builtin     teal)
   (comments    base6)
   (doc-comments (doom-lighten comments 0.15))
   (constants   violet)
   (functions   '("#c48282" "#c48282"     "brightred"))
   (keywords    blue)
   (methods     cyan)
   (operators   '("#90a0b5" "#8f9faf"     "blue"))
   (type        cyan)
   (strings     '("#e8b589" "#e8b589"     "yellow"))
   (variables   fg)
   (numbers     orange)
   (region      selection)
   (error       red)
   (warning     yellow)
   (success     green)
   (vc-modified yellow)
   (vc-added    green)
   (vc-deleted   red)

   ;; Verbatim Vague colors.  Kept separate from the semantic names above so
   ;; that faces can refer to the exact palette slot Vague itself uses.
   (vague-bg            bg)
   (vague-bg-inactive   base3)
   (vague-fg            fg)
   (vague-float-border  fg-alt)
   (vague-line          base4)
   (vague-comment       base6)
   (vague-builtin       teal)
   (vague-func          functions)
   (vague-string        strings)
   (vague-number        orange)
   (vague-property      '("#c3c3d5" "#c3c3d5" "brightwhite"))
   (vague-constant      constants)
   (vague-parameter     magenta)
   (vague-visual        base5)
   (vague-error         red)
   (vague-warning       yellow)
   (vague-hint          highlight)
   (vague-operator      operators)
   (vague-keyword       keywords)
   (vague-type          type)
   (vague-search        '("#405065" "#405065" "blue"))
   (vague-plus          green)
   (vague-delta         yellow)

   ;; Brighter ANSI variants used by Vague's terminal palette.
   (vague-ansi-red       '("#e08398" "#e08398" "brightred"))
   (vague-ansi-green     '("#99b782" "#99b782" "brightgreen"))
   (vague-ansi-yellow    '("#f5cb96" "#f5cb96" "brightyellow"))
   (vague-ansi-blue      '("#8ba9c1" "#8ba9c1" "brightblue"))
   (vague-ansi-magenta   '("#c9b1ca" "#c9b1ca" "brightmagenta"))
   (vague-ansi-cyan      '("#bebeda" "#bebeda" "brightcyan"))
   (vague-ansi-white     '("#d7d7d7" "#d7d7d7" "brightwhite"))

   ;; Mode-line and UI surfaces.  Vague gives the status line the slightly
   ;; lighter `inactiveBg' color, while floats use the same surface.
   (modeline-fg              fg)
   (modeline-fg-alt          fg-alt)
   (modeline-bg              vague-bg-inactive)
   (modeline-bg-alt          '("#20202a" "#20202a" "brightblack"))
   (modeline-bg-inactive     bg-alt)
   (modeline-bg-inactive-alt base2)

   (-modeline-pad
    (when doom-vague-padded-modeline
      (if (integerp doom-vague-padded-modeline)
          doom-vague-padded-modeline
        4)))

   ;; Diff backgrounds, taken directly from vague.nvim.
   (diff-add-bg    '("#293125" "#293125" "black"))
   (diff-change-bg '("#41362a" "#41362a" "black"))
   (diff-delete-bg '("#3b242a" "#3b242a" "black"))
   (diff-text-bg   '("#6d583e" "#6d583e" "brightblack"))
   (diff-add-hl    '("#31402b" "#31402b" "black"))
   (diff-change-hl '("#4c3f30" "#4c3f30" "black"))
   (diff-delete-hl '("#4a2c33" "#4a2c33" "black")))

  ;; Faces are laid out in the order they appear in the UI: base surfaces
  ;; first, then text, then the packages built on top.

  ;;
  ;;; Core UI

  ((default
     :background vague-bg :foreground vague-fg)

  (cursor
    :background fg :foreground bg)

  (region
    :background vague-visual :extend t)
  (secondary-selection
    :background base3 :extend t)
  (highlight
    :background vague-search :foreground fg)
  (hl-line
    :background vague-line :extend t)

  (fringe
    :background 'unspecified :foreground base6)
  (border
    :background bg :foreground base4)
  (internal-border
    :background bg)
  (child-frame-border
    :background bg)
  (vertical-border
    :foreground vague-float-border)
  (window-divider
    :foreground base4)
  (window-divider-first-pixel
    :foreground base4)
  (window-divider-last-pixel
    :foreground base4)
  (scroll-bar
    :background base4 :foreground base5)
  (tool-bar
    :background bg :foreground fg)

  (tab-bar
    :background bg-alt :foreground fg-alt)
  (tab-bar-tab
    :background bg :foreground fg :weight 'bold)
  (tab-bar-tab-inactive
    :background bg-alt :foreground fg-alt)
  (tab-line
    :background bg-alt :foreground fg-alt)
  (tab-line-tab
    :background bg :foreground fg)
  (tab-line-tab-current
    :background bg :foreground fg :weight 'bold)
  (tab-line-tab-inactive
    :background bg-alt :foreground fg-alt)
  (tab-line-highlight
    :background base3)

  (tooltip
    :background vague-bg-inactive :foreground fg)
  (menu
    :background bg-alt :foreground fg)
  (minibuffer-prompt
    :foreground vague-constant)
  (shadow
    :foreground fg-alt)
  (link
    :foreground vague-hint :underline t)
  (link-visited
    :foreground vague-parameter :underline t)
  (button
    :inherit 'link)

  (error
    :foreground vague-error :weight 'bold)
  (warning
    :foreground yellow :weight 'bold)
  (success
    :foreground green :weight 'bold)
  (escape-glyph
    :foreground vague-func)
  (nobreak-space
    :foreground vague-func)
  (homoglyph
    :foreground vague-hint)
  (glyphless-char
    :foreground base6)

  (match
    :background vague-search :foreground fg)
  (isearch
    :background vague-search :foreground fg)
  (isearch-fail
    :background red :foreground bg)
  (lazy-highlight
    :background vague-search :foreground fg)
  (query-replace
    :inherit 'isearch)

  ;;
  ;;; Line numbers and whitespace

  (line-number
    :foreground vague-comment :background 'unspecified)
  (line-number-current-line
    :foreground fg :background vague-line)
  (line-number-major-tick
    :foreground base6)
  (line-number-minor-tick
    :foreground base5)
  (fill-column-indicator
    :foreground base4)

  (show-paren-match
    :background vague-visual :weight 'bold)
  (show-paren-mismatch
    :background red :foreground bg)

  (trailing-whitespace
    :background base5)
  (whitespace-space
    :foreground base6)
  (whitespace-hspace
    :foreground base6)
  (whitespace-tab
    :foreground base6)
  (whitespace-newline
    :foreground base6)
  (whitespace-trailing
    :background base5)
  (whitespace-line
    :background base2 :foreground fg-alt)
  (whitespace-indentation
    :foreground base6)
  (whitespace-space-before-tab
    :background base5)
  (whitespace-empty
    :background base2 :foreground base6)
  (whitespace-big-indent
    :background red :foreground bg)
  (whitespace-missing-newline-at-eof
    :background red :foreground bg)
  (whitespace-space-after-tab
    :background base5)

  ;;
  ;;; Mode line and header line

  (mode-line
    :background modeline-bg :foreground modeline-fg
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,(doom-color 'modeline-bg))))
  (mode-line-inactive
    :background modeline-bg-inactive :foreground vague-comment
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,(doom-color 'modeline-bg-inactive))))
  (mode-line-emphasis
    :foreground fg :weight 'bold)
  (mode-line-highlight
    :background base5 :foreground fg)
  (mode-line-buffer-id
    :foreground fg :weight 'bold)

  (header-line
    :background bg-alt :foreground fg)
  (header-line-inactive
    :background bg-alt :foreground fg-alt)

  ;;
  ;;; Minibuffer and completion

  (completions-common-part
    :foreground vague-hint :weight 'bold)
  (completions-first-difference
    :foreground vague-delta)
  (completion-preview
    :background base2 :foreground fg-alt)
  (completion-preview-common
    :foreground vague-hint)
  (completion-preview-exact
    :foreground vague-hint :weight 'bold)
  (completion-preview-highlight
    :background vague-visual)

  ;; corfu
  (corfu-default
    :background vague-line :foreground fg)
  (corfu-current
    :background vague-visual :foreground fg)
  (corfu-bar
    :background vague-comment)
  (corfu-border
    :background vague-visual)
  (corfu-annotations
    :foreground fg-alt)
  (corfu-deprecated
    :foreground red :strike-through t)

  ;; vertico
  (vertico-current
    :background vague-visual :extend t)
  (vertico-group-title
    :foreground vague-comment :slant 'italic)
  (vertico-group-separator
    :foreground vague-comment :strike-through t)
  (vertico-multiline
    :foreground fg-alt)

  ;; consult
  (consult-preview-line
    :background vague-line :extend t)
  (consult-preview-match
    :background vague-search :foreground fg)
  (consult-preview-insertion
    :background base3)
  (consult-highlight-match
    :background vague-search :foreground fg)
  (consult-highlight-mark
    :background base5 :underline t)
  (consult-async-running
    :foreground vague-hint)
  (consult-async-finished
    :foreground vague-plus)
  (consult-async-failed
    :foreground red)
  (consult-async-split
    :foreground vague-parameter)
  (consult-async-option
    :foreground vague-type)
  (consult-narrow-indicator
    :foreground vague-func)
  (consult-key
    :foreground vague-parameter)
  (consult-line-number
    :foreground vague-comment)
  (consult-line-number-prefix
    :foreground vague-comment)
  (consult-line-number-wrapped
    :foreground vague-warning)
  (consult-file
    :foreground vague-hint)
  (consult-grep-context
    :foreground fg-alt)
  (consult-help
    :foreground vague-constant)
  (consult-bookmark
    :foreground vague-constant)
  (consult-buffer
    :foreground fg)

  ;; marginalia
  (marginalia-documentation
    :foreground fg-alt :slant 'italic)
  (marginalia-key
    :foreground vague-parameter)
  (marginalia-type
    :foreground vague-type)
  (marginalia-char
    :foreground vague-constant)
  (marginalia-lighter
    :foreground vague-comment)
  (marginalia-on
    :foreground vague-plus)
  (marginalia-off
    :foreground vague-comment)
  (marginalia-value
    :foreground fg)
  (marginalia-null
    :foreground vague-comment)
  (marginalia-true
    :foreground vague-plus)
  (marginalia-function
    :foreground vague-func)
  (marginalia-symbol
    :foreground vague-constant)
  (marginalia-list
    :foreground fg)
  (marginalia-mode
    :foreground vague-hint)
  (marginalia-date
    :foreground vague-comment)
  (marginalia-version
    :foreground vague-string)
  (marginalia-archive
    :foreground vague-comment)
  (marginalia-installed
    :foreground vague-plus)
  (marginalia-size
    :foreground vague-parameter)
  (marginalia-number
    :foreground vague-number)
  (marginalia-string
    :foreground vague-string)
  (marginalia-modified
    :foreground vague-warning)
  (marginalia-file-name
    :foreground fg)
  (marginalia-file-owner
    :foreground vague-comment)
  (marginalia-file-priv-no
    :foreground vague-comment)
  (marginalia-file-priv-dir
    :foreground vague-hint)
  (marginalia-file-priv-link
    :foreground vague-parameter)
  (marginalia-file-priv-read
    :foreground vague-warning)
  (marginalia-file-priv-write
    :foreground red)
  (marginalia-file-priv-exec
    :foreground vague-plus)
  (marginalia-file-priv-other
    :foreground vague-type)
  (marginalia-file-priv-rare
    :foreground fg)

  ;; orderless
  (orderless-match-face-0
    :foreground vague-hint :weight 'bold)
  (orderless-match-face-1
    :foreground vague-parameter :weight 'bold)
  (orderless-match-face-2
    :foreground vague-plus :weight 'bold)
  (orderless-match-face-3
    :foreground vague-warning :weight 'bold)

  ;; embark
  (embark-target
    :background vague-visual :foreground fg)
  (embark-keybinding
    :foreground vague-parameter)
  (embark-keybinding-repeat
    :foreground vague-comment)
  (embark-keymap
    :foreground vague-type)
  (embark-collect-candidate
    :foreground fg)
  (embark-collect-group-title
    :foreground vague-comment :slant 'italic)
  (embark-collect-group-separator
    :foreground vague-comment :strike-through t)
  (embark-collect-annotation
    :foreground fg-alt)
  (embark-selected
    :background vague-visual)
  (embark-verbose-indicator-title
    :foreground vague-constant :weight 'bold)
  (embark-verbose-indicator-documentation
    :foreground fg-alt)
  (embark-verbose-indicator-shadowed
    :foreground vague-comment)

  ;;
  ;;; Diagnostics and errors

  (flymake-error
    :underline `(:style wave :color ,(doom-color 'red)))
  (flymake-warning
    :underline `(:style wave :color ,(doom-color 'yellow)))
  (flymake-note
    :underline `(:style wave :color ,(doom-color 'green)))
  (flymake-error-echo
    :foreground red)
  (flymake-warning-echo
    :foreground yellow)
  (flymake-note-echo
    :foreground green)
  (flymake-error-echo-at-eol
    :foreground red)
  (flymake-warning-echo-at-eol
    :foreground yellow)
  (flymake-note-echo-at-eol
    :foreground green)
  (flymake-end-of-line-diagnostics-face
    :height 0.9)
  (flymake-eol-information-face
    :foreground fg-alt :slant 'italic)

  (flycheck-error
    :underline `(:style wave :color ,(doom-color 'red)))
  (flycheck-warning
    :underline `(:style wave :color ,(doom-color 'yellow)))
  (flycheck-info
    :underline `(:style wave :color ,(doom-color 'vague-hint)))
  (flycheck-fringe-error
    :foreground red)
  (flycheck-fringe-warning
    :foreground yellow)
  (flycheck-fringe-info
    :foreground vague-hint)
  (flycheck-error-list-error
    :foreground red)
  (flycheck-error-list-warning
    :foreground yellow)
  (flycheck-error-list-info
    :foreground vague-hint)
  (flycheck-error-list-line-number
    :foreground vague-comment)
  (flycheck-error-list-column-number
    :foreground vague-comment)
  (flycheck-error-list-filename
    :foreground vague-hint)
  (flycheck-error-list-highlight
    :background vague-visual :extend t)

  (flyspell-incorrect
    :underline `(:style wave :color ,(doom-color 'red)))
  (flyspell-duplicate
    :underline `(:style wave :color ,(doom-color 'yellow)))

  ;; eglot (the LSP client Doom uses with `(lsp +eglot)')
  (eglot-highlight-symbol-face
    :background vague-visual)
  (eglot-mode-line
    :foreground vague-hint :weight 'bold)
  (eglot-diagnostic-tag-unnecessary-face
    :foreground vague-comment :underline t)
  (eglot-diagnostic-tag-deprecated-face
    :foreground vague-comment :strike-through t)
  (eglot-inlay-hint-face
    :foreground fg-alt :height 0.9)
  (eglot-type-hint-face
    :inherit 'eglot-inlay-hint-face)
  (eglot-parameter-hint-face
    :inherit 'eglot-inlay-hint-face)

  ;;
  ;;; Syntax highlighting

  (font-lock-comment-face
    :foreground vague-comment
    :slant (if doom-vague-italic-comments 'italic 'normal))
  (font-lock-comment-delimiter-face
    :foreground vague-comment
    :slant (if doom-vague-italic-comments 'italic 'normal))
  (font-lock-doc-face
    :foreground doc-comments
    :slant (if doom-vague-italic-comments 'italic 'normal))
  (font-lock-doc-markup-face
    :foreground vague-property :weight 'bold)

  (font-lock-string-face
    :foreground vague-string
    :slant (if doom-vague-italic-strings 'italic 'normal))
  (font-lock-regexp-face
    :foreground vague-string)
  (font-lock-regexp-grouping-backslash
    :foreground vague-builtin :weight 'bold)
  (font-lock-regexp-grouping-construct
    :foreground vague-builtin :weight 'bold)
  (font-lock-escape-face
    :foreground vague-builtin)

  (font-lock-keyword-face
    :foreground vague-keyword)
  (font-lock-builtin-face
    :foreground vague-builtin)
  (font-lock-function-name-face
    :foreground vague-func)
  (font-lock-function-call-face
    :foreground vague-parameter)
  (font-lock-variable-name-face
    :foreground fg)
  (font-lock-variable-use-face
    :foreground fg)
  (font-lock-type-face
    :foreground vague-type)
  (font-lock-constant-face
    :foreground vague-constant)
  (font-lock-number-face
    :foreground vague-number)
  (font-lock-property-name-face
    :foreground vague-property)
  (font-lock-property-use-face
    :foreground vague-property)
  (font-lock-operator-face
    :foreground vague-operator)
  (font-lock-negation-char-face
    :foreground vague-operator)
  (font-lock-preprocessor-face
    :foreground vague-keyword)
  (font-lock-warning-face
    :foreground vague-warning :weight 'bold)

  (font-lock-bracket-face
    :foreground fg)
  (font-lock-delimiter-face
    :foreground fg)
  (font-lock-punctuation-face
    :foreground fg)
  (font-lock-misc-punctuation-face
    :foreground fg)

  ;; sh-mode
  (sh-heredoc
    :foreground vague-string)
  (sh-quoted-exec
    :foreground vague-builtin)

  ;; markdown-mode
  (markdown-header-face
    :foreground vague-keyword :weight 'bold)
  (markdown-header-face-1
    :foreground vague-keyword :weight 'bold :height 1.15)
  (markdown-header-face-2
    :foreground vague-type :weight 'bold :height 1.1)
  (markdown-header-face-3
    :foreground vague-func :weight 'bold)
  (markdown-header-face-4
    :foreground vague-parameter :weight 'bold)
  (markdown-header-face-5
    :foreground vague-constant :weight 'bold)
  (markdown-header-face-6
    :foreground vague-builtin :weight 'bold)
  (markdown-bold-face
    :foreground fg :weight 'bold)
  (markdown-italic-face
    :foreground fg :slant 'italic)
  (markdown-link-face
    :foreground vague-hint :underline t)
  (markdown-url-face
    :foreground vague-func :underline t)
  (markdown-code-face
    :background bg-alt :foreground vague-constant :extend t)
  (markdown-inline-code-face
    :background base2 :foreground vague-constant)
  (markdown-pre-face
    :foreground fg-alt)
  (markdown-list-face
    :foreground vague-func)
  (markdown-blockquote-face
    :foreground vague-comment :slant 'italic)
  (markdown-markup-face
    :foreground base6)
  (markdown-language-keyword-face
    :foreground vague-comment)
  (markdown-table-face
    :foreground vague-type)
  (markdown-html-tag-name-face
    :foreground vague-keyword)
  (markdown-html-tag-delimiter-face
    :foreground fg)
  (markdown-html-attr-name-face
    :foreground vague-property)
  (markdown-html-attr-value-face
    :foreground vague-string)
  (markdown-html-entity-face
    :foreground vague-builtin)
  (markdown-footnote-marker-face
    :foreground vague-hint)
  (markdown-footnote-text-face
    :foreground fg-alt)
  (markdown-reference-face
    :foreground vague-comment)
  (markdown-metadata-key-face
    :foreground vague-comment)
  (markdown-metadata-value-face
    :foreground fg)
  (markdown-gfm-checkbox-face
    :foreground vague-hint)

  ;;
  ;;; Org

  (org-level-1
    :foreground vague-keyword :weight 'bold :height 1.15)
  (org-level-2
    :foreground vague-type :weight 'bold :height 1.1)
  (org-level-3
    :foreground vague-func :weight 'bold)
  (org-level-4
    :foreground vague-parameter :weight 'bold)
  (org-level-5
    :foreground vague-constant)
  (org-level-6
    :foreground vague-builtin)
  (org-level-7
    :foreground vague-string)
  (org-level-8
    :foreground vague-number)

  (org-document-title
    :foreground vague-func :weight 'bold :height 1.2)
  (org-document-info
    :foreground fg-alt)
  (org-document-info-keyword
    :foreground vague-comment)
  (org-meta-line
    :foreground vague-comment :slant 'italic)

  (org-block
    :background bg-alt :extend t)
  (org-block-begin-line
    :foreground vague-comment :background bg-alt :slant 'italic :extend t)
  (org-block-end-line
    :inherit 'org-block-begin-line)
  (org-code
    :foreground vague-constant :background base2)
  (org-verbatim
    :foreground vague-string :background base2)
  (org-quote
    :foreground fg-alt :slant 'italic)
  (org-verse
    :foreground fg-alt :slant 'italic)
  (org-inline-src-block
    :foreground vague-constant :background base2)
  (org-macro
    :foreground vague-parameter)

  (org-table
    :foreground vague-type)
  (org-table-row
    :foreground vague-type)
  (org-table-header
    :foreground vague-type :weight 'bold)
  (org-formula
    :foreground vague-string)

  (org-link
    :foreground vague-hint :underline t)
  (org-footnote
    :foreground vague-hint :underline t)
  (org-target
    :foreground vague-hint :underline t)

  (org-todo
    :foreground red :weight 'bold)
  (org-done
    :foreground vague-plus :weight 'bold)
  (org-headline-todo
    :foreground fg)
  (org-headline-done
    :foreground fg-alt)
  (org-priority
    :foreground vague-warning :weight 'bold)
  (org-checkbox
    :foreground vague-hint :weight 'bold)
  (org-checkbox-statistics-todo
    :foreground red)
  (org-checkbox-statistics-done
    :foreground vague-plus)
  (org-warning
    :foreground red :weight 'bold)

  (org-scheduled
    :foreground vague-plus)
  (org-scheduled-today
    :foreground vague-plus :weight 'bold)
  (org-scheduled-previously
    :foreground vague-delta)
  (org-upcoming-deadline
    :foreground vague-warning)
  (org-upcoming-distant-deadline
    :foreground fg-alt)
  (org-imminent-deadline
    :foreground red :weight 'bold)
  (org-agenda-done
    :foreground vague-plus)

  (org-agenda-structure
    :foreground vague-keyword :weight 'bold)
  (org-agenda-structure-secondary
    :foreground fg-alt)
  (org-agenda-current-time
    :foreground vague-hint :weight 'bold)
  (org-agenda-date
    :foreground vague-type)
  (org-agenda-date-today
    :foreground vague-hint :weight 'bold)
  (org-agenda-date-weekend
    :foreground fg-alt)
  (org-agenda-date-weekend-today
    :foreground vague-hint :weight 'bold)

  (org-date
    :foreground vague-hint :underline t)
  (org-time-stamp
    :foreground vague-hint)
  (org-time-stamp-inactive
    :foreground fg-alt)
  (org-tag
    :foreground vague-comment :weight 'normal)
  (org-special-keyword
    :foreground vague-comment)
  (org-property-value
    :foreground fg)
  (org-drawer
    :foreground vague-comment)
  (org-ellipsis
    :foreground vague-comment :underline nil)
  (org-hide
    :foreground bg)
  (org-indent
    :inherit 'org-hide)
  (org-latex-and-related
    :foreground vague-constant)
  (org-list-dt
    :foreground vague-parameter :weight 'bold)
  (org-column
    :background base3)
  (org-column-title
    :background base4 :foreground fg :weight 'bold)

  ;;
  ;;; Magit, VC and diffs

  (magit-section-heading
    :foreground vague-keyword :weight 'bold)
  (magit-section-heading-selection
    :foreground fg :background vague-visual)
  (magit-section-highlight
    :background base2 :extend t)
  (magit-section-secondary-heading
    :foreground vague-comment :weight 'bold)
  (magit-section-child-count
    :foreground vague-comment)

  (magit-branch-local
    :foreground vague-hint)
  (magit-branch-remote
    :foreground vague-plus)
  (magit-branch-current
    :foreground vague-hint :weight 'bold)
  (magit-branch-remote-head
    :foreground vague-plus :weight 'bold)
  (magit-branch-upstream
    :foreground vague-parameter :slant 'italic)
  (magit-branch-warning
    :foreground vague-warning)
  (magit-head
    :foreground vague-hint :weight 'bold)
  (magit-tag
    :foreground vague-delta)
  (magit-refname
    :foreground vague-comment)
  (magit-refname-stash
    :foreground vague-parameter)
  (magit-refname-wip
    :foreground vague-warning)
  (magit-refname-pullreq
    :foreground vague-constant)

  (magit-hash
    :foreground vague-comment)
  (magit-filename
    :foreground fg)
  (magit-dimmed
    :foreground vague-comment)
  (magit-keyword
    :foreground vague-parameter :weight 'bold)
  (magit-keyword-squash
    :foreground vague-warning :weight 'bold)
  (magit-log-author
    :foreground vague-func)
  (magit-log-date
    :foreground vague-comment)
  (magit-log-graph
    :foreground base5)

  (magit-diff-added
    :foreground vague-plus :background diff-add-bg :extend t)
  (magit-diff-added-highlight
    :foreground vague-plus :background diff-add-hl :extend t)
  (magit-diff-removed
    :foreground red :background diff-delete-bg :extend t)
  (magit-diff-removed-highlight
    :foreground red :background diff-delete-hl :extend t)
  (magit-diff-context
    :foreground fg-alt :extend t)
  (magit-diff-context-highlight
    :foreground fg :background base2 :extend t)
  (magit-diff-hunk-heading
    :foreground vague-comment :background base2 :extend t)
  (magit-diff-hunk-heading-highlight
    :foreground fg :background base3 :extend t)
  (magit-diff-hunk-heading-selection
    :foreground fg :background vague-visual :extend t)
  (magit-diff-file-heading
    :foreground fg :weight 'bold)
  (magit-diff-file-heading-highlight
    :foreground fg :background base2 :weight 'bold :extend t)
  (magit-diff-file-heading-selection
    :foreground fg :background vague-visual :weight 'bold)
  (magit-diff-lines-heading
    :foreground vague-hint :background base3 :extend t)
  (magit-diff-lines-boundary
    :foreground vague-hint)
  (magit-diffstat-added
    :foreground vague-plus)
  (magit-diffstat-removed
    :foreground red)
  (magit-diff-whitespace-warning
    :background red)

  (magit-process-ok
    :foreground vague-plus :weight 'bold)
  (magit-process-ng
    :foreground red :weight 'bold)
  (magit-mode-line-process
    :foreground vague-hint)
  (magit-mode-line-process-error
    :foreground red)

  (magit-signature-good
    :foreground vague-plus)
  (magit-signature-bad
    :foreground red)
  (magit-signature-error
    :foreground red)
  (magit-signature-expired
    :foreground vague-warning)
  (magit-signature-expired-key
    :foreground vague-warning)
  (magit-signature-revoked
    :foreground vague-parameter)
  (magit-signature-untrusted
    :foreground vague-delta)

  (magit-sequence-done
    :foreground vague-plus)
  (magit-sequence-stop
    :foreground vague-warning)
  (magit-sequence-drop
    :foreground red)
  (magit-sequence-head
    :foreground vague-hint)
  (magit-sequence-part
    :foreground vague-parameter)
  (magit-sequence-onto
    :foreground vague-comment)
  (magit-sequence-pick
    :foreground vague-type)
  (magit-sequence-exec
    :foreground vague-string)
  (magit-cherry-equivalent
    :foreground vague-plus)
  (magit-cherry-unmatched
    :foreground vague-comment)
  (magit-bisect-good
    :foreground vague-plus)
  (magit-bisect-bad
    :foreground red)
  (magit-bisect-skip
    :foreground vague-warning)

  (magit-blame-heading
    :foreground fg-alt :background base2 :extend t)
  (magit-blame-highlight
    :foreground fg :background base3 :extend t)
  (magit-blame-summary
    :foreground fg)
  (magit-blame-name
    :foreground vague-hint)
  (magit-blame-date
    :foreground vague-comment)
  (magit-blame-hash
    :foreground vague-comment)
  (magit-blame-margin
    :foreground fg-alt)
  (magit-blame-dimmed
    :foreground vague-comment)

  (magit-header-line
    :background bg-alt :foreground fg :weight 'bold)
  (magit-header-line-key
    :foreground vague-parameter)
  (magit-header-line-log-select
    :foreground vague-hint)
  (magit-reflog-commit
    :foreground vague-plus)
  (magit-reflog-checkout
    :foreground vague-hint)
  (magit-reflog-cherry-pick
    :foreground vague-plus)
  (magit-reflog-merge
    :foreground vague-plus)
  (magit-reflog-remote
    :foreground vague-type)
  (magit-reflog-rebase
    :foreground vague-parameter)
  (magit-reflog-amend
    :foreground vague-warning)
  (magit-reflog-reset
    :foreground red)
  (magit-reflog-other
    :foreground vague-comment)
  (magit-left-margin
    :foreground base5)

  ;; git-commit / git-rebase
  (git-commit-summary
    :foreground fg :weight 'bold)
  (git-commit-overlong-summary
    :foreground red :weight 'bold)
  (git-commit-nonempty-second-line
    :foreground red)
  (git-commit-keyword
    :foreground vague-parameter)
  (git-commit-trailer-token
    :foreground vague-comment)
  (git-commit-trailer-value
    :foreground fg)
  (git-commit-comment-branch-local
    :foreground vague-hint)
  (git-commit-comment-branch-remote
    :foreground vague-plus)
  (git-commit-comment-detached
    :foreground vague-warning)
  (git-commit-comment-heading
    :foreground vague-keyword :weight 'bold)
  (git-commit-comment-button
    :foreground vague-hint :underline t)
  (git-commit-comment-file
    :foreground fg)
  (git-commit-comment-action
    :foreground vague-comment)
  (git-rebase-hash
    :foreground vague-comment)
  (git-rebase-label
    :foreground vague-hint)
  (git-rebase-description
    :foreground fg)
  (git-rebase-action
    :foreground vague-parameter)
  (git-rebase-killed-action
    :foreground vague-comment :strike-through t)
  (git-rebase-comment-hash
    :foreground vague-comment)
  (git-rebase-comment-heading
    :foreground vague-keyword :weight 'bold)

  ;; diff-mode
  (diff-header
    :foreground fg-alt :background bg-alt :extend t)
  (diff-file-header
    :foreground vague-hint :weight 'bold)
  (diff-function
    :foreground vague-comment)
  (diff-index
    :foreground vague-comment)
  (diff-hunk-header
    :foreground vague-comment :background base2)
  (diff-context
    :foreground fg-alt)
  (diff-added
    :foreground vague-plus :background diff-add-bg :extend t)
  (diff-removed
    :foreground red :background diff-delete-bg :extend t)
  (diff-changed
    :foreground vague-delta :background diff-change-bg :extend t)
  (diff-changed-unspecified
    :foreground vague-delta :background diff-change-bg :extend t)
  (diff-indicator-added
    :foreground vague-plus)
  (diff-indicator-removed
    :foreground red)
  (diff-indicator-changed
    :foreground vague-delta)
  (diff-refine-added
    :background diff-text-bg)
  (diff-refine-removed
    :background diff-delete-hl)
  (diff-refine-changed
    :background diff-text-bg)
  (diff-nonexistent
    :foreground vague-comment)
  (diff-error
    :foreground red :background diff-delete-bg)

  ;; smerge
  (smerge-upper
    :background diff-delete-bg)
  (smerge-lower
    :background diff-add-bg)
  (smerge-base
    :background diff-change-bg)
  (smerge-markers
    :foreground vague-comment :background base3 :weight 'bold)
  (smerge-refined-added
    :background diff-text-bg)
  (smerge-refined-removed
    :background diff-delete-hl)
  (smerge-refined-changed
    :background diff-change-hl)

  ;; log-view / log-edit
  (log-view-file
    :foreground vague-keyword :weight 'bold)
  (log-view-message
    :foreground vague-comment)
  (log-view-commit-body
    :foreground fg)
  (log-edit-summary
    :foreground fg :weight 'bold)
  (log-edit-header
    :foreground vague-comment)
  (log-edit-unknown-header
    :foreground vague-warning)
  (log-edit-headers-separator
    :foreground base4)

  ;; VC directory
  (vc-dir-header
    :foreground vague-keyword :weight 'bold)
  (vc-dir-header-value
    :foreground fg)
  (vc-dir-directory
    :foreground vague-hint)
  (vc-dir-file
    :foreground fg)
  (vc-dir-mark-indicator
    :foreground vague-parameter)
  (vc-dir-status-warning
    :foreground vague-warning)
  (vc-dir-status-edited
    :foreground vague-delta)
  (vc-dir-status-up-to-date
    :foreground vague-plus)
  (vc-dir-status-ignored
    :foreground vague-comment)

  ;; diff-hl (Doom's `vc-gutter +pretty')
  (diff-hl-insert
    :foreground vague-plus :background vague-plus)
  (diff-hl-change
    :foreground vague-delta :background vague-delta)
  (diff-hl-delete
    :foreground red :background red)
  (diff-hl-reverted-hunk-highlight
    :background vague-visual)
  (diff-hl-reference-insert
    :foreground vague-comment)
  (diff-hl-reference-change
    :foreground vague-comment)
  (diff-hl-reference-delete
    :foreground vague-comment)

  ;;
  ;;; Doom interfaces

  ;; doom-modeline
  (doom-modeline
    :background modeline-bg :foreground modeline-fg)
  (doom-modeline-emphasis
    :foreground fg :weight 'bold)
  (doom-modeline-highlight
    :foreground fg :background base5 :weight 'bold)
  (doom-modeline-buffer-path
    :foreground fg-alt :weight 'bold)
  (doom-modeline-buffer-file
    :foreground fg :weight 'bold)
  (doom-modeline-buffer-modified
    :foreground vague-warning :weight 'bold)
  (doom-modeline-buffer-major-mode
    :foreground vague-hint)
  (doom-modeline-buffer-minor-mode
    :foreground vague-comment)
  (doom-modeline-project-parent-dir
    :foreground vague-comment)
  (doom-modeline-project-dir
    :foreground vague-hint :weight 'bold)
  (doom-modeline-project-root-dir
    :foreground fg)
  (doom-modeline-project-name
    :foreground vague-hint)
  (doom-modeline-panel
    :background vague-visual :foreground fg)
  (doom-modeline-host
    :foreground vague-parameter)
  (doom-modeline-input-method
    :foreground vague-parameter)
  (doom-modeline-input-method-alt
    :foreground vague-parameter)
  (doom-modeline-debug
    :foreground vague-comment)
  (doom-modeline-info
    :foreground vague-plus)
  (doom-modeline-warning
    :foreground vague-warning)
  (doom-modeline-urgent
    :foreground red)
  (doom-modeline-notification
    :foreground vague-hint)
  (doom-modeline-unread-number
    :foreground vague-hint :weight 'bold)
  (doom-modeline-bar
    :background vague-hint)
  (doom-modeline-bar-inactive
    :background modeline-bg-inactive)
  (doom-modeline-debug-visual
    :foreground red)
  (doom-modeline-evil-emacs-state
    :foreground vague-parameter :weight 'bold)
  (doom-modeline-evil-insert-state
    :foreground vague-plus :weight 'bold)
  (doom-modeline-evil-motion-state
    :foreground vague-comment :weight 'bold)
  (doom-modeline-evil-normal-state
    :foreground vague-hint :weight 'bold)
  (doom-modeline-evil-operator-state
    :foreground vague-constant :weight 'bold)
  (doom-modeline-evil-visual-state
    :foreground vague-warning :weight 'bold)
  (doom-modeline-evil-replace-state
    :foreground red :weight 'bold)
  (doom-modeline-evil-user-state
    :foreground vague-string :weight 'bold)
  (doom-modeline-overwrite
    :foreground red :weight 'bold)
  (doom-modeline-workspace-name
    :foreground vague-parameter :weight 'bold)
  (doom-modeline-persp-name
    :foreground vague-parameter :weight 'bold)
  (doom-modeline-persp-buffer-not-in-persp
    :foreground vague-comment :slant 'italic)
  (doom-modeline-repl-success
    :foreground vague-plus)
  (doom-modeline-repl-warning
    :foreground vague-warning)
  (doom-modeline-vcs-default
    :foreground fg-alt)
  (doom-modeline-lsp-success
    :foreground vague-plus)
  (doom-modeline-lsp-warning
    :foreground vague-warning)
  (doom-modeline-lsp-error
    :foreground red)
  (doom-modeline-lsp-running
    :foreground vague-hint)
  (doom-modeline-battery-charging
    :foreground vague-plus)
  (doom-modeline-battery-full
    :foreground vague-plus)
  (doom-modeline-battery-normal
    :foreground fg-alt)
  (doom-modeline-battery-warning
    :foreground vague-warning)
  (doom-modeline-battery-critical
    :foreground red)
  (doom-modeline-battery-error
    :foreground red)
  (doom-modeline-time
    :foreground fg-alt)
  (doom-modeline-compilation
    :foreground vague-hint)
  (doom-modeline-spell
    :foreground vague-warning)

  ;; solaire-mode
  (solaire-default-face
    :background bg-alt)
  (solaire-fringe-face
    :background bg-alt :foreground base6)
  (solaire-line-number-face
    :background bg-alt :foreground vague-comment)
  (solaire-hl-line-face
    :background base2 :extend t)
  (solaire-org-hide-face
    :foreground bg-alt)
  (solaire-region-face
    :background vague-visual :extend t)
  (solaire-mode-line-face
    :background modeline-bg-alt :foreground modeline-fg
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,(doom-color 'modeline-bg-alt))))
  (solaire-mode-line-active-face
    :inherit 'solaire-mode-line-face)
  (solaire-mode-line-inactive-face
    :background modeline-bg-inactive-alt :foreground vague-comment
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,(doom-color 'modeline-bg-inactive-alt))))
  (solaire-header-line-face
    :background bg-alt :foreground fg)

  ;; Doom's dashboard
  (+dashboard-banner
    :foreground vague-comment)
  (+dashboard-footer
    :foreground vague-keyword :slant 'italic)
  (+dashboard-footer-icon
    :foreground vague-hint)
  (+dashboard-loaded
    :foreground vague-comment)
  (+dashboard-menu-desc
    :foreground vague-constant)
  (+dashboard-menu-title
    :foreground vague-keyword :weight 'bold)

  ;; which-key
  (which-key-key-face
    :foreground vague-hint :weight 'bold)
  (which-key-separator-face
    :foreground vague-comment)
  (which-key-note-face
    :foreground fg-alt :slant 'italic)
  (which-key-command-description-face
    :foreground fg)
  (which-key-local-map-description-face
    :foreground vague-parameter)
  (which-key-highlighted-command-face
    :foreground vague-warning :weight 'bold)
  (which-key-group-description-face
    :foreground vague-type)
  (which-key-special-key-face
    :foreground vague-func :weight 'bold)
  (which-key-docstring-face
    :foreground fg-alt :slant 'italic)

  ;; helpful
  (helpful-heading
    :foreground vague-keyword :weight 'bold :height 1.15)

  ;; perspective / workspaces
  (persp-face-lighter-buffer-not-in-persp
    :foreground vague-warning :weight 'bold)
  (persp-face-lighter-nil-persp
    :foreground vague-comment)
  (persp-face-lighter-default
    :foreground vague-parameter)

  ;; misc Doom UI
  (vi-tilde-fringe-face
    :foreground base5)
  (+fold-hideshow-folded-face
    :foreground vague-comment :background base2 :extend t)

  ;;
  ;;; Programming aids

  (hl-todo
    :foreground red :weight 'bold)
  (hl-todo-flymake-type
    :foreground red :weight 'bold)

  ;; smartparens
  (sp-show-pair-match-face
    :inherit 'show-paren-match)
  (sp-show-pair-mismatch-face
    :inherit 'show-paren-mismatch)
  (sp-show-pair-match-content-face
    :background vague-visual)
  (sp-show-pair-enclosing
    :inherit 'show-paren-match)
  (sp-pair-overlay-face
    :background vague-visual)
  (sp-wrap-overlay-face
    :background vague-visual)
  (sp-wrap-overlay-opening-pair
    :foreground vague-func :background vague-visual)
  (sp-wrap-overlay-closing-pair
    :foreground vague-func :background vague-visual)
  (sp-wrap-tag-overlay-face
    :background vague-visual)

  ;; evil-goggles (Doom's `ophints' module)
  (evil-goggles-default-face
    :background vague-visual :extend t)
  (evil-goggles-delete-face
    :background diff-delete-bg :extend t)
  (evil-goggles-change-face
    :background diff-change-bg :extend t)
  (evil-goggles-yank-face
    :background diff-add-bg :extend t)
  (evil-goggles-paste-face
    :background diff-add-bg :extend t)
  (evil-goggles-indent-face
    :background base2 :extend t)
  (evil-goggles-join-face
    :background diff-add-bg :extend t)
  (evil-goggles-fill-and-move-face
    :background base2 :extend t)
  (evil-goggles-shift-face
    :background base2 :extend t)
  (evil-goggles-surround-face
    :background vague-visual :extend t)
  (evil-goggles-commentary-face
    :background base2 :extend t)
  (evil-goggles-nerd-commenter-face
    :background base2 :extend t)
  (evil-goggles-replace-with-register-face
    :background diff-change-bg :extend t)
  (evil-goggles-set-marker-face
    :background vague-visual :extend t)
  (evil-goggles-record-macro-face
    :background diff-change-bg :extend t)

  ;; evil search
  (evil-ex-search
    :background vague-search :foreground fg)
  (evil-ex-lazy-highlight
    :background vague-search :foreground fg)
  (evil-ex-substitute-matches
    :background diff-delete-bg :foreground red)
  (evil-ex-substitute-replacement
    :background diff-add-bg :foreground vague-plus)
  (evil-ex-info
    :foreground vague-hint)
  (evil-ex-commands
    :foreground vague-parameter)

  ;;
  ;;; Search, compilation and help buffers

  (compilation-error
    :foreground red :weight 'bold)
  (compilation-warning
    :foreground yellow :weight 'bold)
  (compilation-info
    :foreground vague-hint)
  (compilation-line-number
    :foreground vague-comment)
  (compilation-column-number
    :foreground vague-comment)
  (compilation-mode-line-fail
    :foreground red :weight 'bold)
  (compilation-mode-line-run
    :foreground vague-hint :weight 'bold)
  (compilation-mode-line-exit
    :foreground vague-plus :weight 'bold)

  (help-key-binding
    :foreground vague-hint :background base2)
  (help-argument-name
    :foreground vague-parameter :slant 'italic)

  (apropos-keybinding
    :foreground vague-hint)
  (apropos-property
    :foreground vague-parameter)
  (apropos-symbol
    :foreground fg :weight 'bold)
  (apropos-function-button
    :foreground vague-func)
  (apropos-variable-button
    :foreground vague-constant)
  (apropos-user-option-button
    :foreground vague-type)

  ;; dired (Doom's `:emacs dired' module enables diredfl)
  (dired-directory
    :foreground vague-hint)
  (dired-flagged
    :foreground red)
  (dired-header
    :foreground vague-keyword :weight 'bold)
  (dired-ignored
    :foreground vague-comment)
  (dired-mark
    :foreground vague-warning :weight 'bold)
  (dired-marked
    :foreground vague-parameter :weight 'bold :inverse-video t)
  (dired-perm-write
    :foreground fg :underline t)
  (dired-symlink
    :foreground vague-type :weight 'bold)
  (dired-warning
    :foreground vague-warning)

  (diredfl-dir-heading
    :foreground vague-keyword :weight 'bold)
  (diredfl-dir-name
    :foreground vague-hint)
  (diredfl-dir-priv
    :foreground vague-hint)
  (diredfl-file-name
    :foreground fg)
  (diredfl-file-suffix
    :foreground fg-alt)
  (diredfl-symlink
    :foreground vague-type)
  (diredfl-executable-tag
    :foreground vague-plus)
  (diredfl-exec-priv
    :foreground vague-plus)
  (diredfl-read-priv
    :foreground vague-warning)
  (diredfl-write-priv
    :foreground red)
  (diredfl-no-priv
    :foreground vague-comment)
  (diredfl-other-priv
    :foreground vague-parameter)
  (diredfl-rare-priv
    :foreground fg)
  (diredfl-link-priv
    :foreground vague-parameter)
  (diredfl-number
    :foreground vague-number)
  (diredfl-date-time
    :foreground vague-comment)
  (diredfl-compressed-file-name
    :foreground vague-string)
  (diredfl-compressed-file-suffix
    :foreground vague-string)
  (diredfl-ignored-file-name
    :foreground vague-comment)
  (diredfl-autofile-name
    :foreground base5)
  (diredfl-deletion
    :foreground red :background diff-delete-bg :weight 'bold)
  (diredfl-deletion-file-name
    :foreground red :background diff-delete-bg)
  (diredfl-flag-mark
    :foreground vague-warning :background diff-change-bg :weight 'bold)
  (diredfl-flag-mark-line
    :background base2)
  (diredfl-tagged-autofile-name
    :foreground base5)

  ;;
  ;;; Terminal and ANSI colors

  (term
    :background bg :foreground fg)
  (term-color-black
    :background base1 :foreground base1)
  (term-color-red
    :background red :foreground red)
  (term-color-green
    :background green :foreground green)
  (term-color-yellow
    :background yellow :foreground yellow)
  (term-color-blue
    :background blue :foreground blue)
  (term-color-magenta
    :background magenta :foreground magenta)
  (term-color-cyan
    :background cyan :foreground cyan)
  (term-color-white
    :background fg :foreground fg)
  (term-color-bright-black
    :background base6 :foreground base6)
  (term-color-bright-red
    :background vague-ansi-red :foreground vague-ansi-red)
  (term-color-bright-green
    :background vague-ansi-green :foreground vague-ansi-green)
  (term-color-bright-yellow
    :background vague-ansi-yellow :foreground vague-ansi-yellow)
  (term-color-bright-blue
    :background vague-ansi-blue :foreground vague-ansi-blue)
  (term-color-bright-magenta
    :background vague-ansi-magenta :foreground vague-ansi-magenta)
  (term-color-bright-cyan
    :background vague-ansi-cyan :foreground vague-ansi-cyan)
  (term-color-bright-white
    :background vague-ansi-white :foreground vague-ansi-white)

  (ansi-color-black
    :background base1 :foreground base1)
  (ansi-color-red
    :background red :foreground red)
  (ansi-color-green
    :background green :foreground green)
  (ansi-color-yellow
    :background yellow :foreground yellow)
  (ansi-color-blue
    :background blue :foreground blue)
  (ansi-color-magenta
    :background magenta :foreground magenta)
  (ansi-color-cyan
    :background cyan :foreground cyan)
  (ansi-color-white
    :background fg :foreground fg)
  (ansi-color-bright-black
    :background base6 :foreground base6)
  (ansi-color-bright-red
    :background vague-ansi-red :foreground vague-ansi-red)
  (ansi-color-bright-green
    :background vague-ansi-green :foreground vague-ansi-green)
  (ansi-color-bright-yellow
    :background vague-ansi-yellow :foreground vague-ansi-yellow)
  (ansi-color-bright-blue
    :background vague-ansi-blue :foreground vague-ansi-blue)
  (ansi-color-bright-magenta
    :background vague-ansi-magenta :foreground vague-ansi-magenta)
  (ansi-color-bright-cyan
    :background vague-ansi-cyan :foreground vague-ansi-cyan)
  (ansi-color-bright-white
    :background vague-ansi-white :foreground vague-ansi-white)

  (ansi-color-bold
    :weight 'bold)
  (ansi-color-faint
    :weight 'light)
  (ansi-color-italic
    :slant 'italic)
  (ansi-color-underline
    :underline t)
  (ansi-color-slow-blink
    :underline t)
  (ansi-color-fast-blink
    :underline t)
  (ansi-color-inverse
    :inverse-video t)

  ;; eshell (not enabled by default in this config, but inexpensive to style)
  (eshell-prompt
    :foreground vague-hint :weight 'bold)
  (eshell-ls-directory
    :foreground vague-hint)
  (eshell-ls-symlink
    :foreground vague-type)
  (eshell-ls-executable
    :foreground vague-plus)
  (eshell-ls-readonly
    :foreground vague-warning)
  (eshell-ls-unreadable
    :foreground vague-comment)
  (eshell-ls-special
    :foreground vague-parameter)
  (eshell-ls-missing
    :foreground red)
  (eshell-ls-archive
    :foreground vague-string)
  (eshell-ls-backup
    :foreground vague-comment)
  (eshell-ls-product
    :foreground vague-constant)
  (eshell-ls-clutter
    :foreground vague-comment))

  ;;
  ;;; Theme variables

  ())
