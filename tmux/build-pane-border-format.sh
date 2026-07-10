#!/bin/sh
# Generate the responsive `pane-border-format` and write it to
# pane-border-format.conf (next to this script), which tmux.conf source-files
# (via the ~/.tmux/pane-border-format.conf symlink). Re-run after editing this
# file, then commit the regenerated .conf:
#
#     tmux/build-pane-border-format.sh && tmux source-file ~/.tmux.conf
#
# Why a builder instead of writing the format by hand: the branch-width
# sub-expression (#{w:#(…git…)}) is repeated in every fit/trim calculation, so
# the final format is ~13 KB — impossible to maintain inline. Here it is a
# handful of named shell fragments composed at the bottom.
#
# ── What the border shows ────────────────────────────────────────────────────
# A powerline-style bar at the BOTTOM of each pane (pane-border-status bottom).
# "All slate" treatment: dark-grey slab segments with the hues in the text
# (see the style block below), tapering to  arrow points where they meet the
# border-line filler in the middle — the two groups point at each other:
#
#   [ title  ❯ command  ────────────  branch  cwd ]
#
# Left, flush left:   "title" seg (fg colour173) →  → "❯ command" seg (fg colour141) →
# Right, flush right:  ← "<branch-glyph> branch" seg ←  ← "<folder-glyph> cwd" seg (fg colour110)
#   branch text: active+clean colour108, active+dirty colour220,
#                inactive+clean colour242, inactive+dirty colour94 (a muted
#                yellowish).
#   branch-glyph = Devicons git-branch (U+E725), resolved by Ghostty's automatic
#                  fallback to the Symbols Nerd Font Mono installed by /shell-setup.
#   folder-glyph = FontAwesome folder-open (U+F07C), same fallback.
#   arrows       = Powerline solid triangles  (U+E0B0) /  (U+E0B2) — drawn
#                  NATIVELY by Ghostty (like box-drawing), no font dependency.
# A border-line (─) filler sits between the two groups. As the pane narrows the
# layout degrades through stages, always keeping ≥1 filler column:
#   S0  everything (both glyphs, the ❯ caret, command, full title/branch/cwd)
#   S1  drop the branch+folder glyphs and ❯  (when S0 would leave <1 filler col)
#   S2  also drop the command segment (+ its junction arrow)
#   S3  trim title (end…) and cwd (start…) PROPORTIONALLY to their lengths
#   S4  also trim the branch (start…, like a path) — only when title+cwd are
#       already at their 3-col minimum and it still overflows
# The stage is chosen by comparing each stage's full content width to the
# available width; the cwd/title/branch are only trimmed in the trim stage.
#
# ── tmux-format quirks this relies on (all learned the hard way) ──────────────
#  * #(…) shell jobs use `echo`, never `printf "…%s…"`: tmux runs strftime over
#    the format before executing #(), so a literal %s becomes a Unix timestamp.
#  * The generated value is SINGLE-quoted in the .conf: tmux expands $VAR inside
#    a double-quoted config value at parse time, which would blank the shell's
#    $p/$b before #() ran. Single quotes keep them literal; #{…}/#() still
#    expand at render time.
#  * #{w:X} (display width) only evaluates when X contains a nested #{…}/#() —
#    a bare #{w:literal} reads 0. Every width term here wraps such a nesting.
#  * The branch #() is async: it refreshes on status-interval (≤15s) and reads
#    empty on the very first (cold-cache) render. Identical #() strings are
#    deduped by tmux, so it is one git process per pane per refresh.
#  * The filler between #[align=left] and #[align=right] is drawn with the
#    pane-border style, not the last #[…] style in the format — so the
#    segments' bg colors don't bleed into the line.
#  * Framing reserve = 3 = tmux's 1-col border margin on each edge + 1 minimum
#    filler column.
#
# ── Width accounting (cells) ──────────────────────────────────────────────────
# Every segment pads its text with 1 space each side; arrows are 1 cell. The
# left group opens with a  taper (tmux hardcodes a 2-cell margin before the
# strip — screen-redraw.c draws it at xoff+2 — so the taper makes that inset
# read as deliberate powerline shape instead of a gap).
#   S0 left  = taper 1 | title+2 | arr 1 | 1+"❯ "(2)+cmd+1 | arr 1 = Tt+Cc+9
#   S0 right = arr 1 | 1+glyph+1+branch+1 | arr 1 | 1+glyph+2+cwd+1
#            = Bb+Pp+11 with a branch, Pp+6 without
#   ⇒ s0 = Tt+Cc+Pp+Bb + 15 + (branch ? 5 : 0)
#   S1 drops the glyphs and ❯ (−2 left, −1/−3 right per glyph):
#   ⇒ s1 = Tt+Cc+Pp+Bb + 10 + (branch ? 3 : 0)
#   S2 also drops the command segment and its junction arrow (left = Tt+4):
#   ⇒ s2 = Tt+Pp+Bb + 7 + (branch ? 3 : 0)
# Trim stage fixed overhead = 4 (left) + (branch ? branchBudget+6 : 3) (right).
#
# EMPTY-FIELD GUARDS: a segment with empty content must not render at all — an
# empty pane_title would otherwise leave a 4-cell "blob" (taper+pads+taper).
# When the title is empty the title segment AND its tapers/junction disappear
# (the command segment, if shown, wears the tapers instead), so the left-fixed
# constants above drop by 3 (with command) / 4 (without): the ?$Tt conditionals
# in s0/s1/s2, maxb, remaining and titleTarget below. Command and cwd get the
# same treatment (showCmd additionally requires Cc>0; the right group requires
# Pp>0); the branch was always guarded by PRES.

set -eu

# Git-branch glyph (Devicons git-branch, U+E725). Built via printf octal escape
# so this private-use codepoint survives editing (typing it literally tends to
# get dropped). A font glyph resolved by Ghostty's automatic fallback to the
# Symbols Nerd Font Mono installed by /shell-setup — do NOT set font-family in
# ghostty/config to force it (that breaks text metrics; see the note there).
BR=$(printf '\356\234\245')
# Folder glyph (FontAwesome folder-open, U+F07C) for the cwd — same printf
# trick; also rendered via the Symbols Nerd Font Mono fallback.
FD=$(printf '\357\201\274')
# Powerline solid arrows:  (U+E0B0, points right) and  (U+E0B2, points left).
# Ghostty draws U+E0B0–E0BF natively, so these need no font at all.
AR=$(printf '\356\202\260')
AL=$(printf '\356\202\262')
# Braille blank (U+2800): renders exactly like a space but is neither
# whitespace nor a path character, so Ghostty's link detection won't absorb it
# into the cwd when cmd+shift+clicking the path. Used as the cwd segment's
# trailing pad; a real space there gets swept into the detected file path.
PB=$(printf '\342\240\200')

# ── primitives ───────────────────────────────────────────────────────────────
# Branch name (no leaf), or empty outside a repo / detached prints the short SHA.
BN='#(p="#{pane_current_path}";b=$(git -C "$p" symbolic-ref --short HEAD 2>/dev/null||git -C "$p" rev-parse --short HEAD 2>/dev/null);[ -n "$b" ]&&echo "$b")'
# "1" when the repo has uncommitted (tracked) changes — `git diff HEAD` exits 1
# on any staged/unstaged change vs HEAD; we echo only on exit 1 (0=clean,
# ≥128=not a repo). Turns the branch segment yellow. NOTE: untracked-only files
# don't count (swap to `git status --porcelain` if you want them to).
DIRTY='#(p="#{pane_current_path}";git -C "$p" diff --quiet HEAD 2>/dev/null;[ $? = 1 ]&&echo 1)'
CWD='#{s|^#{HOME}|~|:pane_current_path}'   # cwd with $HOME collapsed to ~
Tt='#{w:#{pane_title}}'                     # title width
Cc='#{w:#{pane_current_command}}'           # command width
Pp="#{w:$CWD}"                              # cwd width
Bb="#{w:$BN}"                               # branch width (0 outside a repo)
PRES="$Bb"                                  # nonzero ⇒ branch present
avail='#{e|-:#{pane_width},3}'              # usable width (see framing note above)

# ── stage content widths + which stage we are in ─────────────────────────────
s0="#{e|+:$Tt,#{e|+:$Cc,#{e|+:$Pp,#{e|+:$Bb,#{e|+:#{?$Tt,15,12},#{?$PRES,5,0}}}}}}"   # full (S0)
s1="#{e|+:$Tt,#{e|+:$Cc,#{e|+:$Pp,#{e|+:$Bb,#{e|+:#{?$Tt,10,7},#{?$PRES,3,0}}}}}}"    # no glyphs/caret (S1)
s2="#{e|+:$Tt,#{e|+:$Pp,#{e|+:$Bb,#{e|+:#{?$Tt,7,3},#{?$PRES,3,0}}}}}"                # also no command (S2)
showEmoji="#{e|>=:$avail,$s0}"   # S0 fits  → show branch+folder glyphs + ❯
showCmd="#{&&:#{e|>=:$avail,$s1},$Cc}"   # S0/S1 fit AND command nonempty → show command
trimMode="#{e|>:$s2,$avail}"     # not even S2 fits → trim text (S3/S4)

# ── trim targets (only consulted in trimMode) ────────────────────────────────
# The =/N/… truncation APPENDS the … beyond N (verified: #{=/5/…:…} renders 6
# cells), so every trimmed field costs its target +1. Reserve those cells here:
# 2 for title+cwd (always both truncation-candidates in trim mode) and 1 for
# the branch inside maxb (the branch only gains an … when capped by maxb).
# Branch keeps full width until title+cwd hit their 3-col minimum, then trims:
#   branchBudget = present ? min(Bb, max(1, avail-17)) : 0  (17 = 2*min + 10 fixed + 1 …;
#                  empty title drops its min 3, fixed 4 → 10)
maxb="#{?#{e|>:#{e|-:$avail,#{?$Tt,17,10}},1},#{e|-:$avail,#{?$Tt,17,10}},1}"
brbud="#{?#{e|<:$Bb,$maxb},$Bb,$maxb}"
branchBudget="#{?$PRES,$brbud,0}"
# left for title+cwd: avail − right fixed − left fixed (6 = 4 + title's … + cwd's …;
# empty title → 1 = just cwd's … cell)
remaining="#{e|-:$avail,#{e|+:#{?$PRES,#{e|+:$branchBudget,6},3},#{?$Tt,6,1}}}"
tpsum="#{?#{e|>:#{e|+:$Tt,$Pp},0},#{e|+:$Tt,$Pp},1}"           # title+cwd, guarded vs /0
ttRaw="#{e|/:#{e|*:$remaining,$Tt},$tpsum}"                    # proportional title share
titleTarget="#{?#{e|>:$ttRaw,3},$ttRaw,#{?$Tt,3,0}}"           # min 3 (0 when title empty)
ctRaw="#{e|-:$remaining,$titleTarget}"
cwdTarget="#{?#{e|>:$ctRaw,3},$ctRaw,3}"                       # min 3, cwd gets the rest

# ── segment styles (active / inactive) ───────────────────────────────────────
# "All slate" powerline: every segment is a dark-grey slab and the hues live in
# the TEXT — title colour173 bold, command colour141, branch colour108 clean /
# colour220 dirty (inactive dirty a muted colour94), cwd colour110.
# Slab shades alternate outer/inner so junctions stay visible: active
# colour237/colour236 (lighter than the ##2a2a2a strip); inactive
# ##212121/##1a1a1a (truecolor — ## is the format-literal escape for #),
# DARKER than the strip — inactive panes contrast by sinking into the band
# instead of rising above it, so focus reads instantly.
# Arrow cells always paint the adjoining slab shade as fg over the next slab's
# bg; at a taper the bg is the SOLID STRIP color the borders are filled with —
# ##2a2a2a for BOTH active and inactive, matching pane-border-style AND
# pane-active-border-style in tmux.conf (fg=bg solid fill; the two must be one
# shade — see the tmux.conf comment — and changing it means changing it here
# too, or the taper points get a mismatched notch). DIRTY recolors only the
# branch text.
sT='#{?pane_active,#[fg=colour173 bg=colour237 bold],#[fg=colour244 bg=##212121 nobold]}'    # title seg
sJ1='#{?pane_active,#[fg=colour237 bg=colour236 nobold],#[fg=##212121 bg=##1a1a1a nobold]}'  # title→command join
sC='#{?pane_active,#[fg=colour141 bg=colour236],#[fg=colour242 bg=##1a1a1a]}'                # command seg
sCb='#{?pane_active,#[bold],}'                                                               # bold cmd when active
sTapC='#{?pane_active,#[fg=colour236 bg=##2a2a2a nobold],#[fg=##1a1a1a bg=##2a2a2a nobold]}'   # cmd-slab taper
sTapT='#{?pane_active,#[fg=colour237 bg=##2a2a2a nobold],#[fg=##212121 bg=##2a2a2a nobold]}'   # title-slab taper (group start + end when no cmd)
sB="#{?pane_active,#{?$DIRTY,#[fg=colour220 bg=colour236 nobold],#[fg=colour108 bg=colour236 nobold]},#{?$DIRTY,#[fg=colour94 bg=##1a1a1a nobold],#[fg=colour242 bg=##1a1a1a nobold]}}"  # branch seg
sBin='#{?pane_active,#[fg=colour236 bg=##2a2a2a nobold],#[fg=##1a1a1a bg=##2a2a2a nobold]}'    # right taper into branch
sJ2='#{?pane_active,#[fg=colour237 bg=colour236],#[fg=##212121 bg=##1a1a1a]}'                # branch→cwd join
sPin='#{?pane_active,#[fg=colour237 bg=##2a2a2a nobold],#[fg=##212121 bg=##2a2a2a nobold]}'    # right taper, no branch
sP='#{?pane_active,#[fg=colour110 bg=colour237],#[fg=colour244 bg=##212121]}'                # cwd seg

# ── rendered fragments ───────────────────────────────────────────────────────
# title trims from the END (…suffix); cwd and branch trim from the START
# (…prefix), keeping their tails — same as a path.
titleShown="#{?$trimMode,#{=/$titleTarget/…:#{pane_title}},#{pane_title}}"
branchName="#{?$trimMode,#{=/-$branchBudget/…:$BN},$BN}"
cwdShown="#{?$trimMode,#{=/-$cwdTarget/…:$CWD},$CWD}"

CMDSEG="${sC} #{?$showEmoji,❯ ,}${sCb}#{pane_current_command} ${sTapC}${AR}"
LEFT="#[align=left]#{?$Tt,${sTapT}${AL}${sT} ${titleShown} #{?$showCmd,${sJ1}${AR}${CMDSEG},${sTapT}${AR}},#{?$showCmd,${sTapC}${AL}${CMDSEG},}}"
RIGHT="#[align=right]#{?$Pp,#{?$PRES,${sBin}${AL}${sB} #{?$showEmoji,${BR} ,}${branchName} ${sJ2}${AL},${sPin}${AL}}${sP} #{?$showEmoji,${FD}  ,}${cwdShown}${PB},}#[default]"

# ── emit ─────────────────────────────────────────────────────────────────────
out="$(dirname "$0")/pane-border-format.conf"
{
  printf '%s\n' "# GENERATED by build-pane-border-format.sh — do NOT edit by hand."
  printf '%s\n' "# Edit the builder, re-run it, and commit the regenerated file."
  printf "set -g pane-border-format '%s%s'\n" "$LEFT" "$RIGHT"
} > "$out"
echo "wrote $out ($(wc -c < "$out") bytes)"
