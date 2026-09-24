# omarchy-zero (rascunho, privado)

Omarchy num Arch comum, instalado do zero, **sem o instalador oficial** e sem
os ~150 pacotes dele. Entra só o que o shell chama, e cada pacote tem um motivo
escrito. Nenhum `omarchy update` pode quebrar a instalação.

Este repositório nasceu da instalação do **zednet** em 24/09/2026. É a primeira
máquina que rodou o Omarchy sem host nenhum. O relato completo está em
`omarchy-guest/docs/NO-HOST.md` (branch `docs/no-host`), e o log bruto em
`~/zednet/ACHADOS.md`. Aqui fica **só o que se repete** numa máquina nova.

> Estado: rascunho para análise. Ainda não há instalador. `files/` tem os
> arquivos reais, tirados do zednet, que o instalador vai colocar no lugar.

---

## Premissa

- O instalador oficial toma o disco e o bootloader. Aqui o Arch é seu, e o
  Omarchy entra como um checkout em `~/.local/share/omarchy`, fixado num ref
  verificado.
- Pouco pacote, sempre com motivo. No zednet, o desktop completo (som, rede,
  login, splash e Tailscale) ficou em **526 pacotes**, e 174 deles vieram só do
  Dolphin. O mínimo que roda o shell é bem menor (tabela abaixo).
- O dono da atualização é você. O `omarchy-update` e a família dele ficam
  atrás de uma trava.

## Números do zednet (referência)

| etapa | pacotes (`pacman -Q`) |
|---|---|
| `pacstrap` base | 150 |
| + shell mínimo | 299 |
| + `jq` | 306 |
| + som (PipeWire) | +22 |
| + NetworkManager (só Wi-Fi) | +12 |
| + plymouth / sddm | +2 / +9 |
| + dolphin (opcional) | +174 |

Boot: 11,1 s (firmware 4,0, loader 1,0, kernel 1,4, initrd 2,1 e userspace 2,5).
RAM em repouso: 1198 MB, dos quais 82 MB eram o Xorg da tela de login. Esse
Xorg foi cortado depois, e a medição nova ainda está por fazer.

## Pacotes, por camada

| camada | pacotes | por quê |
|---|---|---|
| base | `base linux linux-firmware-<cpu/gpu/rede> <cpu>-ucode e2fsprogs sudo` | firmware só dos fabricantes presentes, não o `linux-firmware` inteiro |
| shell | `hyprland quickshell uwsm git` | compositor, shell, sessão e checkout |
| runtime do shell | `gum xdg-terminal-exec qrencode wtype jq gtk3` | `jq` é chamado por 76 comandos do `bin/`; `gtk3` traz o `gtk-launch`, que o launcher usa para abrir **qualquer** app. O doctor não pede nenhum dos dois |
| terminal e fonte | `foot ttf-jetbrains-mono-nerd` | foot é o padrão deles e o mais leve |
| som | `pipewire pipewire-pulse wireplumber` | o painel de áudio chama `pactl` e `wpctl` |
| rede | `networkmanager` | o painel de rede chama `nmcli`. Cuida só do Wi-Fi, e o cabo continua no networkd |
| desktop | `udiskie wl-clipboard slurp grim hyprpicker brightnessctl hyprsunset less imagemagick` | autostart deles, print, área de transferência, brilho, luz noturna, conta-gotas (varredura em NO-HOST.md) |
| login | `sddm` + o tema, `plymouth` | tela de login e splash (opcionais) |

Fora de propósito: `ttfx` (screensaver, só no AUR/repo deles), `hypridle`,
`bt-agent`, `fcitx5`, `gsettings-desktop-schemas`, o `config/` inteiro deles
(chromium, obsidian, opencode…).

## O que o instalador precisa fazer (ordem)

1. **Checkout** do Omarchy em `~/.local/share/omarchy` no ref verificado:
   `git clone --depth 1 -b quattro` e depois fetch do SHA. Um bundle feito de
   clone raso sai incompleto.
2. **Marcar todas as migrations** em `~/.local/state/omarchy/migrations/`. É o
   que o finalizer oficial faz numa instalação nova. Sem isso, um clone novo
   tem 124 pendentes, e uma delas instala o kernel deles no Limine.
3. **Config de usuário**: copiar só `config/{hypr,omarchy,foot}`, e escrever `~/.config/xdg-terminals.list` com o terminal escolhido. Sem esse arquivo o Omarchy escolhe sozinho e instala o kitty.
4. **Ambiente**: o pacote deles monta isto via `/usr/share`, e um checkout
   não tem. São três arquivos em `files/home/`:
   `~/.config/uwsm/env`, `~/.config/environment.d/60-omarchy.conf` e
   `~/.bash_profile`.
5. **Trava** (`files/guard/`): na frente de `$OMARCHY_PATH/bin` no PATH e fora
   do checkout. São 16 comandos (`update`, `migrate`, `refresh-*`,
   `reinstall*`…). `OMARCHY_GUEST_ALLOW=1` libera.
6. **Units de usuário** (`files/home/.config/systemd/user/`): as três úteis,
   com `%h` no lugar de `/usr/bin`.
7. **Padrões de máquina**: `omarchy.idle` desligado em `disabledPlugins`,
   logind ignorando a tampa e a ociosidade, e `zed.updates` no lugar do
   `omarchy.system-update` na barra.
8. **Tema sem sessão**: `OMARCHY_THEME_HEADLESS=1 omarchy-theme-set <tema>`.
9. **Root, uma vez**: `omarchy-apply-lock` (PAM do lock), `omarchy-guest-apply-browser-policy` e uma cópia do root de `omarchy-dns` em `/usr/bin`. O Omarchy escala privilégio por caminho fixo de pacote. **Nunca** usar symlink para o checkout, e reaplicar a cada update.
10. **First-run**: `omarchy-done mark first-run-user` depois de conferido,
    porque um first-run que falha se repete e rearma a notificação de update.
11. **Login**: sddm com `DisplayServer=wayland` num Hyprland mínimo (o
    `default/sddm/hyprland.lua` deles), ou tty1 com `uwsm start`.
12. **Splash (opcional)**: `plymouth` no `HOOKS` depois de `systemd`, e
    `splash` no cmdline.

## Instalador

**Decidido em 24/09:** um script bash com `--dry-run`, no mesmo estilo do
omarchy-guest.
- Roda como usuário e pede `sudo` em cada ação de root, uma de cada vez, para
  que o `--dry-run` mostre exatamente o que vai rodar como root.
- Pode rodar de novo sem estragar nada, então também conserta uma máquina que
  ficou pela metade.
- Faz backup com data e hora antes de sobrescrever qualquer arquivo.

## Relação com o omarchy-guest

O `omarchy-guest` resolve "Omarchy **em cima** de um host" (HyDE etc.). Este
resolve "Omarchy **sem** host". Muita coisa é compartilhada: trava, doctor,
contract, migrations, menu.

**Decidido em 24/09: repositório próprio, que usa o omarchy-guest.** O
instalador daqui baixa o omarchy-guest e chama as peças dele. A regra é: o que
vale para as duas situações (com host e sem host) vai para o omarchy-guest,
como a trava do atualizador, as dependências a mais no `doctor` e um
`bootstrap --minimal`. Aqui fica só o que é exclusivo da máquina sem host: os
três arquivos de ambiente, a sessão, os padrões de máquina e a ordem de
instalação.

## Perguntas em aberto

- Dolphin, sddm e plymouth ficam como opcionais ou saem de vez?
- `sudo` com `secure_path` fura a trava. Vale fechar isso?
- Tema do sddm: o astronaut é AUR. Usar o tema do próprio Omarchy
  (`default/sddm/omarchy`), que vem no checkout?
