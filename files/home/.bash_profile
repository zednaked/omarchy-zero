
# --- omarchy-zero: Omarchy as a checkout, with the update guard first ---
export OMARCHY_PATH="$HOME/.local/share/omarchy"
case ":$PATH:" in *":$OMARCHY_PATH/bin:"*) ;; *) PATH="$OMARCHY_PATH/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/.local/share/omarchy-guest/guard/bin:"*) ;; *) PATH="$HOME/.local/share/omarchy-guest/guard/bin:$PATH" ;; esac
export PATH
# --- end omarchy-zero ---
