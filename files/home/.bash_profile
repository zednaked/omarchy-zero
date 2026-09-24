[[ -f ~/.bashrc ]] && . ~/.bashrc
export OMARCHY_PATH="$HOME/.local/share/omarchy"
case ":$PATH:" in *":$OMARCHY_PATH/bin:"*) ;; *) PATH="$OMARCHY_PATH/bin:$PATH" ;; esac
export PATH
# Trava do omarchy-guest na frente de tudo (ver docs/NO-HOST.md).
case ":$PATH:" in *":$HOME/.local/share/omarchy-guest/guard/bin:"*) ;; *) PATH="$HOME/.local/share/omarchy-guest/guard/bin:$PATH" ;; esac
export PATH
