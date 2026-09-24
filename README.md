# omarchy-zero

The [Omarchy](https://omarchy.org/) shell on a plain Arch install you set up
yourself: no official installer, no disk takeover, and only the packages the
shell actually calls.

Omarchy is an opinionated distribution, and its installer is right to own the
machine: it takes the disk and the bootloader and brings its full package set,
and in return everything fits together. This project is for the other case.
You already have an Arch install you like (or want a minimal one), and you want
the shell: the bar, the menu, the overlays and the plugin ecosystem around them.

It builds on [omarchy-guest](https://github.com/zednaked/omarchy-guest), which
runs the same shell on top of an existing desktop setup. This repository covers
the case with no host at all.

## The numbers

Measured on a real install (Intel i7-8750H laptop, systemd-boot), counting
`pacman -Q` as each layer went in:

| layer | packages | added |
|---|---|---|
| `pacstrap` base | 150 | |
| **the shell running** | **299** | **+149** |
| kitty, installed unasked on first login (`install.sh` now prevents it) | 304 | +5 |
| `jq`, which the shell needs and nothing asked for | 306 | +2 |
| sound (PipeWire) | 328 | +22 |
| NetworkManager | 340 | +12 |
| login screen (sddm) and boot splash (plymouth) | 351 | +11 |
| a file manager (Dolphin) | 525 | **+174** |

For reference, upstream's `install/omarchy-base.packages` names 151 packages
*before* dependencies. Here the shell itself costs 149 packages over base, and
the single most expensive piece of a full desktop is the file manager, because
Dolphin pulls in KDE Frameworks. `--no-dolphin` leaves it out.

Boot on that machine: 11.1 s to the login screen (`systemd-analyze`: firmware
4.0, loader 1.0, kernel 1.4, initrd 2.1, userspace 2.5).

## Install

Start from a working Arch install with a user who has `sudo`, then:

    git clone https://github.com/zednaked/omarchy-zero
    cd omarchy-zero
    ./install.sh --dry-run     # every action, printed; nothing changes
    ./install.sh

The installer runs as your user and asks for `sudo` one action at a time, so
the dry run shows exactly what would run as root. It is safe to run again: each
step checks before acting, and every file it replaces is copied to
`<file>.bak.<timestamp>` first. That also makes it the way to repair an install
that stopped halfway.

| option | effect |
|---|---|
| `--no-login` | no sddm; log in on tty1 and run `uwsm start hyprland.desktop` |
| `--no-splash` | no plymouth |
| `--no-dolphin` | no file manager |
| `--server` | never sleep: ignore lid and idle, and turn off the idle plugin |
| `--split-network` | the cable stays with systemd-networkd; NetworkManager only manages Wi-Fi |
| `--terminal NAME` | terminal for `xdg-terminals.list` (default `foot`) |
| `--theme NAME` | Omarchy theme applied without a running session (default `tokyo-night`) |

What it does, in order:

1. **Packages**, by layer, each with a reason (below).
2. **Checkouts**: omarchy-guest, and Omarchy itself in `~/.local/share/omarchy`,
   pinned to the ref omarchy-guest last verified.
3. **Migrations**: marks every existing migration as done, which is what
   Omarchy's own installer does at the end of a fresh install. Without it, the
   first update runs the entire history, and one migration installs Omarchy's
   kernel as the first Limine entry.
4. **User config**: copies `hypr`, `omarchy` and `foot` from the checkout if you
   don't have them, and writes `xdg-terminals.list`. Without that file Omarchy
   picks a terminal itself and installs kitty to do it.
5. **Environment**: the three files the Omarchy package would normally provide
   through `/usr/share` (`uwsm/env`, `environment.d`, a block in `.bash_profile`).
6. **Update guard** (see Updating).
7. **User units**: crash watch, sleep lock and internal-monitor recovery.
8. **omarchy-guest install**: its plugins and menu overrides.
9. **System services**, **login screen** and **boot splash**, with Omarchy's
   own sddm and plymouth themes from the checkout, so nothing comes from the
   AUR. A custom splash theme you already set is left alone.
10. **Theme** and the root-once helper `omarchy-apply-lock`, which writes the
    lock screen's PAM file.

Two things stay manual on purpose: adding `splash` to the kernel command line
(that is your bootloader), and `omarchy-done mark first-run-user` once the
first login works. A first run that fails repeats on every login and re-arms
the update notification.

## Packages, by layer

| layer | packages | why |
|---|---|---|
| shell | `hyprland quickshell uwsm git` | compositor, shell, session, checkout |
| what the shell calls | `gum xdg-terminal-exec qrencode wtype jq gtk3` | `jq` is called by 76 commands in Omarchy's `bin/`; `gtk3` provides `gtk-launch`, which the launcher uses to open any app |
| terminal and font | `foot ttf-jetbrains-mono-nerd` | foot is the lightest terminal Omarchy supports |
| sound | `pipewire pipewire-pulse wireplumber` | the audio panel calls `pactl` and `wpctl` |
| network | `networkmanager` | the network panel calls `nmcli` |
| desktop | `udiskie wl-clipboard slurp grim hyprpicker brightnessctl hyprsunset less imagemagick` | autostart, screenshots, clipboard, brightness, night light, color picker |
| login, splash | `sddm`, `plymouth` | on by default; `--no-login`, `--no-splash` |
| files | `dolphin` | on by default; `--no-dolphin` |

Left out on purpose: the screensaver (`ttfx` exists only in the AUR and in
Omarchy's own repository), `hypridle`, `fcitx5`, and Omarchy's app configs
(Chromium, Obsidian and others). Install what you use.

## Updating

This install does not run `omarchy-update`. That command pulls, runs migrations
and refreshes config, boot, login and pacman settings, and on this install
several of those are yours.

The **guard** is a directory of symlinks placed ahead of Omarchy's `bin/` on
PATH and outside the checkout, so a `git pull` cannot remove it. It covers 16
commands (`omarchy-update`, `omarchy-migrate`, and the `refresh-*` and
`reinstall*` families, among others). Each one explains why it stopped and
sends a notification. `OMARCHY_GUEST_ALLOW=1 <command>` lets a call through.

Its limit, accepted on purpose: it protects against clicks and calls by name.
`sudo` resets PATH, so a root call with the full path into the checkout goes
through. Nothing in the session does that.

To update Omarchy by hand, with omarchy-guest's tools:

    cd ~/.local/share/omarchy && git fetch origin quattro
    omarchy-guest-contract --ref origin/quattro --commits   # what would break
    omarchy-guest-migrations --ref origin/quattro           # what would run, classified
    git merge --ff-only origin/quattro
    omarchy-guest-migrations --apply-policy
    OMARCHY_GUEST_ALLOW=1 omarchy-migrate
    omarchy-guest doctor

`pacman -Syu` is safe: no Omarchy repository is added to `pacman.conf`.

## Relation to omarchy-guest

[omarchy-guest](https://github.com/zednaked/omarchy-guest) solves the Omarchy
shell **on top of** a host (another Hyprland config manager, for example). This
solves the Omarchy shell **with no host**. Anything that applies to both cases
(the guard, the doctor, the upstream contract, migration policy, menu
overrides) belongs there. This repository keeps only what is specific to a
machine with no host: the environment files, the session and the install order.

The full account of the first install, including everything that broke and what
the doctor did not see, is in omarchy-guest's
[`docs/NO-HOST.md`](https://github.com/zednaked/omarchy-guest/blob/main/docs/NO-HOST.md).

## Status

Version 0.1.0, tested on one machine. That install was done by hand, step by
step, before this script existed, and the script's dry run against it reports
every step as already done or as an equivalent file. A run on a second, fresh
machine has not happened yet. Reports are welcome.

## License

MIT
