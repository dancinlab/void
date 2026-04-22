# Parts of this script are based on Kitty's bash integration. Kitty is
# distributed under GPLv3, so this file is also distributed under GPLv3.
# The license header is reproduced below:
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# We need to be in interactive mode to proceed.
if [[ "$-" != *i* ]]; then builtin return; fi

# When automatic shell integration is active, we were started in POSIX
# mode and need to manually recreate the bash startup sequence.
if [ -n "$VOID_BASH_INJECT" ]; then
  # Store a temporary copy of our startup flags and unset these global
  # environment variables so we can safely handle reentrancy.
  builtin declare __void_bash_flags="$VOID_BASH_INJECT"
  builtin unset ENV VOID_BASH_INJECT

  # Restore an existing ENV that was replaced by the shell integration code.
  if [[ -n "$VOID_BASH_ENV" ]]; then
    builtin export ENV=$VOID_BASH_ENV
    builtin unset VOID_BASH_ENV
  fi

  # Restore bash's default 'posix' behavior. Also reset 'inherit_errexit',
  # which doesn't happen as part of the 'posix' reset.
  builtin set +o posix
  builtin shopt -u inherit_errexit 2>/dev/null

  # Unexport HISTFILE if it was set by the shell integration code.
  if [[ -n "$VOID_BASH_UNEXPORT_HISTFILE" ]]; then
    builtin export -n HISTFILE
    builtin unset VOID_BASH_UNEXPORT_HISTFILE
  fi

  # Manually source the startup files. See INVOCATION in bash(1) and
  # run_startup_files() in shell.c in the Bash source code.
  if builtin shopt -q login_shell; then
    if [[ $__void_bash_flags != *"--noprofile"* ]]; then
      [ -r /etc/profile ] && builtin source "/etc/profile"
      for __void_rcfile in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        [ -r "$__void_rcfile" ] && {
          builtin source "$__void_rcfile"
          break
        }
      done
    fi
  else
    if [[ $__void_bash_flags != *"--norc"* ]]; then
      # The location of the system bashrc is determined at bash build
      # time via -DSYS_BASHRC and can therefore vary across distros:
      #  Arch, Debian, Ubuntu use /etc/bash.bashrc
      #  Fedora uses /etc/bashrc sourced from ~/.bashrc instead of SYS_BASHRC
      #  Void Linux uses /etc/bash/bashrc
      #  Nixos uses /etc/bashrc
      for __void_rcfile in /etc/bash.bashrc /etc/bash/bashrc /etc/bashrc; do
        [ -r "$__void_rcfile" ] && {
          builtin source "$__void_rcfile"
          break
        }
      done
      if [[ -z "$VOID_BASH_RCFILE" ]]; then VOID_BASH_RCFILE="$HOME/.bashrc"; fi
      [ -r "$VOID_BASH_RCFILE" ] && builtin source "$VOID_BASH_RCFILE"
    fi
  fi

  builtin unset __void_rcfile
  builtin unset __void_bash_flags
  builtin unset VOID_BASH_RCFILE
fi

# Add Void binary to PATH if the path feature is enabled
if [[ "$VOID_SHELL_FEATURES" == *"path"* && -n "$VOID_BIN_DIR" ]]; then
  if [[ ":$PATH:" != *":$VOID_BIN_DIR:"* ]]; then
    export PATH="$PATH:$VOID_BIN_DIR"
  fi
fi

# Sudo
if [[ "$VOID_SHELL_FEATURES" == *"sudo"* && -n "$TERMINFO" ]]; then
  # Wrap `sudo` command to ensure Void terminfo is preserved.
  #
  # This approach supports wrapping a `sudo` alias, but the alias definition
  # must come _after_ this function is defined. Otherwise, the alias expansion
  # will take precedence over this function, and it won't be wrapped.
  function sudo {
    builtin local sudo_has_sudoedit_flags="no"
    for arg in "$@"; do
      # Check if argument is '-e' or '--edit' (sudoedit flags)
      if [[ "$arg" == "-e" || $arg == "--edit" ]]; then
        sudo_has_sudoedit_flags="yes"
        builtin break
      fi
      # Check if argument is neither an option nor a key-value pair
      if [[ "$arg" != -* && "$arg" != *=* ]]; then
        builtin break
      fi
    done
    if [[ "$sudo_has_sudoedit_flags" == "yes" ]]; then
      builtin command sudo "$@"
    else
      builtin command sudo --preserve-env=TERMINFO "$@"
    fi
  }
fi

# SSH Integration
if [[ "$VOID_SHELL_FEATURES" == *ssh-* ]]; then
  function ssh() {
    builtin local ssh_term ssh_opts
    ssh_term="xterm-256color"
    ssh_opts=()

    # Configure environment variables for remote session
    if [[ "$VOID_SHELL_FEATURES" == *ssh-env* ]]; then
      ssh_opts+=(-o "SendEnv COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION")
    fi

    # Install terminfo on remote host if needed
    if [[ "$VOID_SHELL_FEATURES" == *ssh-terminfo* ]]; then
      builtin local ssh_user ssh_hostname

      while IFS=' ' read -r ssh_key ssh_value; do
        case "$ssh_key" in
        user) ssh_user="$ssh_value" ;;
        hostname) ssh_hostname="$ssh_value" ;;
        esac
        [[ -n "$ssh_user" && -n "$ssh_hostname" ]] && break
      done < <(builtin command ssh -G "$@" 2>/dev/null)

      if [[ -n "$ssh_hostname" ]]; then
        builtin local ssh_target="${ssh_user}@${ssh_hostname}"

        # Check if terminfo is already cached
        if "$VOID_BIN_DIR/void" +ssh-cache --host="$ssh_target" >/dev/null 2>&1; then
          ssh_term="xterm-void"
        elif builtin command -v infocmp >/dev/null 2>&1; then
          builtin local ssh_terminfo ssh_cpath_dir ssh_cpath

          ssh_terminfo=$(infocmp -0 -x xterm-void 2>/dev/null)

          if [[ -n "$ssh_terminfo" ]]; then
            builtin echo "Setting up xterm-void terminfo on $ssh_hostname..." >&2

            ssh_cpath_dir=$(mktemp -d "/tmp/void-ssh-$ssh_user.XXXXXX" 2>/dev/null) || ssh_cpath_dir="/tmp/void-ssh-$ssh_user.$$"
            ssh_cpath="$ssh_cpath_dir/socket"

            if builtin echo "$ssh_terminfo" | builtin command ssh -o ControlMaster=yes -o ControlPath="$ssh_cpath" -o ControlPersist=60s "$@" '
              infocmp xterm-void >/dev/null 2>&1 && exit 0
              command -v tic >/dev/null 2>&1 || exit 1
              mkdir -p ~/.terminfo 2>/dev/null && tic -x - 2>/dev/null && exit 0
              exit 1
            ' 2>/dev/null; then
              ssh_term="xterm-void"
              ssh_opts+=(-o "ControlPath=$ssh_cpath")

              # Cache successful installation
              "$VOID_BIN_DIR/void" +ssh-cache --add="$ssh_target" >/dev/null 2>&1 || true
            else
              builtin echo "Warning: Failed to install terminfo." >&2
            fi
          else
            builtin echo "Warning: Could not generate terminfo data." >&2
          fi
        else
          builtin echo "Warning: void command not available for cache management." >&2
        fi
      fi
    fi

    # Execute SSH with TERM environment variable
    TERM="$ssh_term" COLORTERM=truecolor builtin command ssh "${ssh_opts[@]}" "$@"
  }
fi

# This is set to 1 when we're executing a command so that we don't
# send prompt marks multiple times.
_void_executing=""
_void_last_reported_cwd=""

function __void_precmd() {
  local ret="$?"
  if test "$_void_executing" != "0"; then
    _VOID_SAVE_PS1="$PS1"
    _VOID_SAVE_PS2="$PS2"

    # Use 133;P (not 133;A) inside PS1 to avoid fresh-line behavior on
    # readline redraws (e.g., vi mode switches, Ctrl-L). The initial
    # 133;A with fresh-line is emitted once via printf below.
    PS1='\[\e]133;P;k=i\a\]'$PS1'\[\e]133;B\a\]'
    PS2='\[\e]133;P;k=s\a\]'$PS2'\[\e]133;B\a\]'

    # Bash doesn't redraw the leading lines in a multiline prompt so we mark
    # the start of each line (after each newline) as a secondary prompt. This
    # correctly handles multiline prompts by setting the first to primary and
    # the subsequent lines to secondary.
    #
    # We only replace the \n prompt escape, not literal newlines ($'\n'),
    # because literal newlines may appear inside $(...) command substitutions
    # where inserting escape sequences would break shell syntax.
    if [[ "$PS1" == *"\n"* ]]; then
      PS1="${PS1//\\n/\\n$'\\[\\e]133;P;k=s\\a\\]'}"
    fi

    # Cursor
    if [[ "$VOID_SHELL_FEATURES" == *"cursor"* ]]; then
      builtin local cursor=5  # blinking bar
      [[ "$VOID_SHELL_FEATURES" == *"cursor:steady"* ]] && cursor=6  # steady bar

      [[ "$PS1" != *"\[\e[${cursor} q\]"* ]] && PS1=$PS1"\[\e[${cursor} q\]"
      [[ "$PS0" != *'\[\e[0 q\]'* ]] && PS0=$PS0'\[\e[0 q\]' # reset
    fi

    # Title (working directory)
    if [[ "$VOID_SHELL_FEATURES" == *"title"* ]]; then
      PS1=$PS1'\[\e]2;\w\a\]'
    fi
  fi

  if test "$_void_executing" != ""; then
    # End of current command. Report its status.
    builtin printf "\e]133;D;%s;aid=%s\a" "$ret" "$BASHPID"
  fi

  # Fresh line and start of prompt. When ble.sh is active, emit 133;P instead
  # of 133;A because ble.sh maintains its own cursor position tracking. 133;A's
  # cursor movement (CR+LF when not at column 0) is invisible to ble.sh and
  # desyncs its position state, causing display artifacts like duplicate
  # prompts. See: https://github.com/akinomyoga/ble.sh/issues/684
  if [[ -n "${BLE_VERSION-}" ]]; then
    builtin printf "\e]133;P;k=i\a"
  else
    builtin printf "\e]133;A;redraw=last;cl=line;aid=%s\a" "$BASHPID"
  fi

  # unfortunately bash provides no hooks to detect cwd changes
  # in particular this means cwd reporting will not happen for a
  # command like cd /test && cat. PS0 is evaluated before cd is run.
  if [[ "$_void_last_reported_cwd" != "$PWD" ]]; then
    _void_last_reported_cwd="$PWD"
    builtin printf "\e]7;kitty-shell-cwd://%s%s\a" "$HOSTNAME" "$PWD"
  fi

  _void_executing=0
}

function __void_preexec() {
  builtin local cmd="$1"

  PS1="$_VOID_SAVE_PS1"
  PS2="$_VOID_SAVE_PS2"

  # Title (current command)
  if [[ -n $cmd && "$VOID_SHELL_FEATURES" == *"title"* ]]; then
    builtin printf "\e]2;%s\a" "${cmd//[[:cntrl:]]/}"
  fi

  # End of input, start of output.
  builtin printf "\e]133;C;\a"
  _void_executing=1
}

if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
  __void_preexec_hook() {
    builtin local cmd
    cmd=$(LC_ALL=C HISTTIMEFORMAT='' builtin history 1)
    cmd="${cmd#*[[:digit:]][* ] }"  # remove leading history number
    [[ -n "$cmd" ]] && __void_preexec "$cmd"
  }

  __void_hook() {
    builtin local ret=$?
    __void_precmd "$ret"

    # Append preexec hook to PS0 if not already present.
    # Use function substitution in 5.3+, otherwise command substitution.
    if [[ "$PS0" != *"__void_preexec_hook"* ]]; then
      if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3) )); then
        # shellcheck disable=SC2016
        PS0+='${ __void_preexec_hook; }'
      else
        # shellcheck disable=SC2016
        PS0+='$(__void_preexec_hook >/dev/tty)'
      fi
    fi
  }

  # Append our hook to PROMPT_COMMAND, preserving its existing type.
  #
  # The 2>/dev/null suppresses "command not found" in subshells that inherit
  # PROMPT_COMMAND without the function definition. This also silences any
  # errors from inside __void_hook itself, but those are all terminal escape
  # sequences and non-actionable.
  #
  # shellcheck disable=SC2128,SC2178,SC2179
  if [[ ";${PROMPT_COMMAND[*]:-};" != *";__void_hook 2>/dev/null;"* ]]; then
    if [[ -z "${PROMPT_COMMAND[*]}" ]]; then
      if (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1) )); then
        PROMPT_COMMAND=("__void_hook 2>/dev/null")
      else
        PROMPT_COMMAND="__void_hook 2>/dev/null"
      fi
    elif [[ $(builtin declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a "* ]]; then
      PROMPT_COMMAND+=("__void_hook 2>/dev/null")
    else
      [[ "${PROMPT_COMMAND}" =~ (\;[[:space:]]*|$'\n')$ ]] || PROMPT_COMMAND+=";"
      PROMPT_COMMAND+="__void_hook 2>/dev/null"
    fi
  fi
else
  builtin source "$(dirname -- "${BASH_SOURCE[0]}")/bash-preexec.sh"
  preexec_functions+=(__void_preexec)
  precmd_functions+=(__void_precmd)
fi
