#!/usr/bin/env bash
# omarchy-zero - the Omarchy shell on a plain Arch install, without the
# official installer.
#
#   ./install.sh --dry-run     # print every action, change nothing
#   ./install.sh               # do it
#
# Runs as your user and asks for sudo one action at a time, so --dry-run shows
# exactly what would run as root. Safe to run again: every step checks first,
# and every file it replaces is copied to <file>.bak.<timestamp> before.
#
# Options:
#   --no-login      no sddm; start with `uwsm start` from tty1 instead
#   --no-splash     no plymouth boot splash
#   --no-dolphin    no file manager (saves ~174 packages of KDE Frameworks)
#   --server        never sleep: ignore lid and idle, disable the idle plugin
#   --split-network cable stays with systemd-networkd, NetworkManager only
#                   manages Wi-Fi
#   --terminal NAME terminal written to xdg-terminals.list (default: foot)
#   --theme NAME    Omarchy theme applied headless (default: tokyo-night)
set -uo pipefail

VERSION="0.1.0"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$HERE/files"
STAMP="$(date +%Y%m%d-%H%M%S)"

OMARCHY_REPO="${OMARCHY_REPO:-https://github.com/basecamp/omarchy.git}"
OMARCHY_BRANCH="${OMARCHY_BRANCH:-quattro}"
OMARCHY_DIR="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
GUEST_REPO="${GUEST_REPO:-https://github.com/zednaked/omarchy-guest.git}"
GUEST_SRC="${GUEST_SRC:-$HOME/.local/src/omarchy-guest}"
GUARD_DIR="$HOME/.local/share/omarchy-guest/guard/bin"
MIGRATION_STATE="$HOME/.local/state/omarchy/migrations"

DRY=0 LOGIN=1 SPLASH=1 DOLPHIN=1 SERVER=0 SPLITNET=0
TERMINAL="foot" THEME="tokyo-night" TERMINAL_SET=0

while (($#)); do
  case $1 in
    --dry-run) DRY=1 ;;
    --no-login) LOGIN=0 ;;
    --no-splash) SPLASH=0 ;;
    --no-dolphin) DOLPHIN=0 ;;
    --server) SERVER=1 ;;
    --split-network) SPLITNET=1 ;;
    --terminal) TERMINAL="${2:?--terminal needs a name}"; TERMINAL_SET=1; shift ;;
    --theme) THEME="${2:?--theme needs a name}"; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --version) echo "omarchy-zero $VERSION"; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# output and actions
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' D=$'\e[2m' R=$'\e[0m'
else B='' G='' Y='' D='' R=''; fi
section() { printf '\n%s%s%s\n' "$B" "$1" "$R"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$R" "$*"; }
info() { printf '  %s→%s %s\n' "$Y" "$R" "$*"; }
note() { printf '    %s%s%s\n' "$D" "$*" "$R"; }
die()  { printf '  %s✗ %s%s\n' "$Y" "$*" "$R" >&2; exit 1; }

# run CMD...  - print it under --dry-run, run it otherwise
run() {
  if ((DRY)); then printf '    %s$ %s%s\n' "$D" "$*" "$R"; return 0; fi
  "$@"
}
root() { run sudo "$@"; }

# enable UNIT... - only the ones that are not enabled yet
enable() {
  local u
  for u in "$@"; do
    if systemctl is-enabled -q "$u" 2>/dev/null; then ok "$u (enabled)"; else root systemctl enable "$u"; fi
  done
}

# put SRC DST [root]  - install a file only if it differs, backing up first
put() {
  local src=$1 dst=$2 as=${3:-}
  local s=(); [[ $as == root ]] && s=(sudo)
  if [[ -f $dst ]] && cmp -s "$src" "$dst"; then ok "$dst (unchanged)"; return; fi
  [[ -e $dst ]] && run "${s[@]}" cp -a "$dst" "$dst.bak.$STAMP"
  run "${s[@]}" install -Dm644 "$src" "$dst"
  ((DRY)) || ok "$dst"
}

# ---------------------------------------------------------------------------
section "omarchy-zero $VERSION$( ((DRY)) && printf ' (dry run: nothing will change)')"

section "1. Preflight"
[[ -f /etc/arch-release ]] || die "this is not Arch; the installer only knows pacman"
[[ $EUID -ne 0 ]] || die "run as your user, not root: config goes to the \$HOME of whoever runs it"
command -v sudo >/dev/null || die "sudo is missing"
command -v git >/dev/null || info "git is missing; it is installed in step 2"
ok "Arch, user $USER, sudo"
if ! ((DRY)); then sudo -v || die "sudo refused"; fi

# ---------------------------------------------------------------------------
section "2. Packages (each layer has a reason, see README)"
PKGS=(
  hyprland quickshell uwsm git                                   # shell
  gum xdg-terminal-exec qrencode wtype jq gtk3                  # what the shell calls
  foot ttf-jetbrains-mono-nerd                                  # terminal and font
  pipewire pipewire-pulse wireplumber                           # the audio panel calls pactl/wpctl
  networkmanager                                                # the network panel calls nmcli
  udiskie wl-clipboard slurp grim hyprpicker brightnessctl hyprsunset less imagemagick
)
((LOGIN))   && PKGS+=(sddm)
((SPLASH))  && PKGS+=(plymouth)
((DOLPHIN)) && PKGS+=(dolphin)
[[ $TERMINAL != foot ]] && PKGS+=("$TERMINAL")
mapfile -t MISSING < <(pacman -T "${PKGS[@]}" 2>/dev/null)
if ((${#MISSING[@]})); then
  info "missing ${#MISSING[@]} of ${#PKGS[@]}: ${MISSING[*]}"
  root pacman -S --needed --noconfirm "${MISSING[@]}" || die "pacman failed"
else
  ok "all ${#PKGS[@]} present"
fi

# ---------------------------------------------------------------------------
section "3. Checkouts"
if [[ -d $GUEST_SRC/.git ]]; then ok "omarchy-guest in $GUEST_SRC"
else run git clone --depth 1 "$GUEST_REPO" "$GUEST_SRC" || die "clone of omarchy-guest failed"; fi

REF=""
[[ -f $GUEST_SRC/contract/verified ]] && REF="$(sed -n 's/^ref=//p' "$GUEST_SRC/contract/verified")"
if [[ -d $OMARCHY_DIR/.git ]]; then
  ok "Omarchy in $OMARCHY_DIR at $(git -C "$OMARCHY_DIR" rev-parse --short HEAD)"
  note "this installer never updates the checkout; see 'Updating' in README"
else
  info "cloning Omarchy ($OMARCHY_BRANCH${REF:+, pinned to $REF, the ref omarchy-guest verified})"
  # Partial clone, not --depth 1: a shallow clone cannot check out a pinned SHA.
  run git clone --filter=blob:none --branch "$OMARCHY_BRANCH" "$OMARCHY_REPO" "$OMARCHY_DIR" || die "clone of Omarchy failed"
  [[ -n $REF ]] && run git -C "$OMARCHY_DIR" checkout -q --detach "$REF"
fi
OB="$OMARCHY_DIR/bin"

# ---------------------------------------------------------------------------
section "4. Migrations"
# A fresh checkout has every migration pending. Omarchy's own installer marks
# them all done at the end; without that, the first update runs ~120 of them,
# and one installs Omarchy's kernel into Limine.
if ((DRY)) && [[ ! -d $OMARCHY_DIR/migrations ]]; then
  note "would mark every migration in $OMARCHY_DIR/migrations as done"
else
  n=0
  for m in "$OMARCHY_DIR"/migrations/*.sh; do
    [[ -e $m ]] || continue
    [[ -e $MIGRATION_STATE/$(basename "$m") ]] && continue
    ((DRY)) || { mkdir -p "$MIGRATION_STATE"; touch "$MIGRATION_STATE/$(basename "$m")"; }
    ((n++))
  done
  ((n)) && info "marked $n migrations as done" || ok "all migrations already marked"
fi

# ---------------------------------------------------------------------------
section "5. User config"
for d in hypr omarchy foot; do
  if [[ -e $HOME/.config/$d ]]; then ok "~/.config/$d exists, left alone"
  else run cp -r "$OMARCHY_DIR/config/$d" "$HOME/.config/$d"; ((DRY)) || ok "~/.config/$d"; fi
done
# Without this file Omarchy picks a terminal itself, and installs kitty to do it.
if [[ -e $HOME/.config/xdg-terminals.list ]] && ((!TERMINAL_SET)); then
  ok "~/.config/xdg-terminals.list exists, left alone (--terminal NAME overrides)"
else
  TL="$(mktemp)"; printf '%s.desktop\n' "$TERMINAL" >"$TL"
  put "$TL" "$HOME/.config/xdg-terminals.list"; rm -f "$TL"
fi

# ---------------------------------------------------------------------------
section "6. Environment (what the Omarchy package would set up in /usr/share)"
put "$FILES/home/.config/uwsm/env" "$HOME/.config/uwsm/env"
put "$FILES/home/.config/environment.d/60-omarchy.conf" "$HOME/.config/environment.d/60-omarchy.conf"
if grep -q 'omarchy-zero' "$HOME/.bash_profile" 2>/dev/null; then ok "~/.bash_profile (block present)"
else
  info "appending the PATH block to ~/.bash_profile"
  ((DRY)) || { [[ -e $HOME/.bash_profile ]] && cp -a "$HOME/.bash_profile" "$HOME/.bash_profile.bak.$STAMP"
               cat "$FILES/home/.bash_profile" >>"$HOME/.bash_profile"; }
fi

# ---------------------------------------------------------------------------
section "7. Update guard"
# Every command in GUARDED updates Omarchy or rewrites something this install
# set up by hand. The guard sits ahead of Omarchy's bin/ on PATH and outside
# the checkout, so a git pull cannot remove it. OMARCHY_GUEST_ALLOW=1 lets a
# call through.
run mkdir -p "$GUARD_DIR"
if ! cmp -s "$FILES/guard/omarchy-guard" "$GUARD_DIR/omarchy-guard" 2>/dev/null; then
  run install -m755 "$FILES/guard/omarchy-guard" "$GUARD_DIR/omarchy-guard"
fi
g=0
while read -r name; do
  [[ -z $name || $name == \#* ]] && continue
  [[ -L $GUARD_DIR/$name ]] && continue
  run ln -sf omarchy-guard "$GUARD_DIR/$name"; ((g++))
done <"$FILES/guard/GUARDED"
ok "$(grep -cv '^\s*\(#\|$\)' "$FILES/guard/GUARDED") commands guarded$( ((g)) && printf ' (%s new)' "$g")"

# ---------------------------------------------------------------------------
section "8. User units"
for u in "$FILES"/home/.config/systemd/user/*.service; do
  put "$u" "$HOME/.config/systemd/user/$(basename "$u")"
done
run systemctl --user daemon-reload
for u in "$FILES"/home/.config/systemd/user/*.service; do
  systemctl --user is-enabled -q "$(basename "$u")" 2>/dev/null && continue
  run systemctl --user enable "$(basename "$u")"
done

# ---------------------------------------------------------------------------
section "9. omarchy-guest plugins and menu overrides"
if ((DRY)); then run "$GUEST_SRC/bin/omarchy-guest" install --dry-run
else "$GUEST_SRC/bin/omarchy-guest" install || info "omarchy-guest install reported a problem, see above"; fi

# ---------------------------------------------------------------------------
section "10. System services"
enable NetworkManager.service
if ((SPLITNET)); then
  put "$FILES/etc/NetworkManager/conf.d/10-wifi-only.conf" /etc/NetworkManager/conf.d/10-wifi-only.conf root
  put "$FILES/etc/systemd/network/20-wired.network" /etc/systemd/network/20-wired.network root
  enable systemd-networkd.service systemd-resolved.service
fi
if ((SERVER)); then
  put "$FILES/etc/systemd/logind.conf.d/10-never-sleep.conf" /etc/systemd/logind.conf.d/10-never-sleep.conf root
  note "the idle plugin is disabled in step 13, once a theme exists"
fi

# ---------------------------------------------------------------------------
section "11. Login screen"
if ((LOGIN)); then
  # Omarchy's own login theme and compositor config ship in the checkout, so
  # nothing comes from the AUR.
  put "$OMARCHY_DIR/default/sddm/hyprland.lua" /usr/share/sddm/hyprland.lua root
  if [[ -d $OMARCHY_DIR/default/sddm/omarchy ]]; then
    root mkdir -p /usr/share/sddm/themes/omarchy
    root cp -r "$OMARCHY_DIR/default/sddm/omarchy/." /usr/share/sddm/themes/omarchy/
  fi
  put "$FILES/etc/sddm.conf.d/10-wayland.conf" /etc/sddm.conf.d/10-wayland.conf root
  # Own file, low prefix: a theme you already set in a later file still wins.
  put "$FILES/etc/sddm.conf.d/20-omarchy-theme.conf" /etc/sddm.conf.d/20-omarchy-theme.conf root
  enable sddm.service
else
  note "no sddm: log in on tty1 and run 'uwsm start hyprland.desktop'"
fi

# ---------------------------------------------------------------------------
section "12. Boot splash"
if ((SPLASH)); then
  root mkdir -p /usr/share/plymouth/themes/omarchy
  root cp -r "$OMARCHY_DIR/default/plymouth/." /usr/share/plymouth/themes/omarchy/
  # Only replace a stock theme; a custom one is yours.
  cur="$(plymouth-set-default-theme 2>/dev/null)"
  case $cur in
    ''|bgrt|details|fade-in|glow|script|solar|spinfinity|spinner|text|tribar) root plymouth-set-default-theme omarchy ;;
    omarchy) ok "plymouth theme omarchy" ;;
    *) ok "plymouth theme '$cur' is custom, left alone" ;;
  esac
  if grep -qE '^HOOKS=.*\bplymouth\b' /etc/mkinitcpio.conf; then ok "plymouth hook present"
  else
    info "adding the plymouth hook after systemd/udev in /etc/mkinitcpio.conf"
    root cp -a /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.$STAMP"
    root sed -i -E '/^HOOKS=/ s/\b(systemd|udev)\b/\1 plymouth/' /etc/mkinitcpio.conf
    root mkinitcpio -P
  fi
  note "the kernel command line needs 'splash' (and usually 'quiet');"
  note "that lives in your bootloader, which this installer does not edit"
fi

# ---------------------------------------------------------------------------
section "13. Theme, root-once helpers, first run"
if [[ -e $HOME/.local/state/omarchy/current/theme ]]; then ok "a theme is already set"
else run env OMARCHY_THEME_HEADLESS=1 OMARCHY_PATH="$OMARCHY_DIR" "$OB/omarchy-theme-set" "$THEME"; fi
# Omarchy escalates privilege by fixed packaged paths. A checkout has none, so
# these copy what they need into place. Never symlink into the checkout.
root env OMARCHY_INSTALL_USER="$USER" "$OB/omarchy-apply-lock"
if ((SERVER)); then
  if "$OB/omarchy-plugin-list" --json 2>/dev/null | jq -e '.[] | select(.id=="omarchy.idle" and .enabled)' >/dev/null; then
    run "$OB/omarchy-plugin-disable" omarchy.idle
  else ok "omarchy.idle already off"; fi
fi
note "first run: after you log in once and check it works, run"
note "  $OB/omarchy-done mark first-run-user"
note "(a first run that fails repeats and re-arms the update notification)"

section "Done$( ((DRY)) && printf ' (dry run: nothing changed)')"
note "log out and back in, or reboot"
note "check the result read-only with: $GUEST_SRC/bin/omarchy-guest doctor"
