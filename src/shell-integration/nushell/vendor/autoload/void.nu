# Void shell integration
export module void {
  def has_feature [feature: string] {
    $feature in ($env.VOID_SHELL_FEATURES | default "" | split row ',')
  }

  # Wrap `ssh` with Void TERMINFO support
  export def --wrapped ssh [...args] {
    mut ssh_env = {}
    mut ssh_opts = []

    # `ssh-env`: use xterm-256color and propagate COLORTERM/TERM_PROGRAM vars
    if (has_feature "ssh-env") {
      $ssh_env.TERM = "xterm-256color"
      $ssh_env.COLORTERM = "truecolor"
      $ssh_opts = [
        "-o" "SendEnv COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION"
      ]
    }

    # `ssh-terminfo`: auto-install xterm-void terminfo on remote hosts
    if (has_feature "ssh-terminfo") {
      let void = ($env.VOID_BIN_DIR? | default "") | path join "void"

      let ssh_cfg = ^ssh -G ...$args
        | lines
        | parse "{key} {value}"
        | where key in ["user" "hostname"]
        | select key value
        | transpose -rd
        | default {user: $env.USER hostname: "localhost"}
      let ssh_id = $"($ssh_cfg.user)@($ssh_cfg.hostname)"

      if (^$void "+ssh-cache" $"--host=($ssh_id)" | complete | $in.exit_code == 0) {
        $ssh_env.TERM = "xterm-void"
      } else {
        $ssh_env.TERM = "xterm-256color"

        let terminfo = try {
          ^infocmp -0 -x xterm-void
        } catch {
          print -e "infocmp failed, using xterm-256color"
        }

        if ($terminfo | is-not-empty) {
          print $"Setting up xterm-void terminfo on ($ssh_cfg.hostname)..."

          let ctrl_path = (
            mktemp -td $"void-ssh-($ssh_cfg.user).XXXXXX"
            | path join "socket"
          )

          let remote_args = $ssh_opts ++ [
            "-o" "ControlMaster=yes"
            "-o" $"ControlPath=($ctrl_path)"
            "-o" "ControlPersist=60s"
          ] ++ $args

          $terminfo | ^ssh ...$remote_args '
            infocmp xterm-void >/dev/null 2>&1 && exit 0
            command -v tic >/dev/null 2>&1 || exit 1
            mkdir -p ~/.terminfo 2>/dev/null && tic -x - 2>/dev/null && exit 0
            exit 1'
          | complete
          | if $in.exit_code == 0 {
            ^$void "+ssh-cache" $"--add=($ssh_id)" e>| print -e
            $ssh_env.TERM = "xterm-void"
            $ssh_opts = ($ssh_opts ++ ["-o" $"ControlPath=($ctrl_path)"])
          } else {
            print -e "terminfo install failed, using xterm-256color"
          }
        }
      }
    }

    let ssh_args = $ssh_opts ++ $args
    with-env $ssh_env {
      ^ssh ...$ssh_args
    }
  }

  # Wrap `sudo` to preserve Void's TERMINFO environment variable
  export def --wrapped sudo [...args] {
    mut sudo_args = $args

    if (has_feature "sudo") {
      # Extract just the sudo options (before the command)
      let sudo_options = (
        $args | take until {|arg|
          not (($arg | str starts-with "-") or ($arg | str contains "="))
        }
      )

      # Prepend TERMINFO preservation flag if not using sudoedit
      if (not ("-e" in $sudo_options or "--edit" in $sudo_options)) {
        $sudo_args = ($args | prepend "--preserve-env=TERMINFO")
      }
    }

    ^sudo ...$sudo_args
  }
}

# Clean up XDG_DATA_DIRS by removing VOID_SHELL_INTEGRATION_XDG_DIR
if 'VOID_SHELL_INTEGRATION_XDG_DIR' in $env {
  if 'XDG_DATA_DIRS' in $env {
    $env.XDG_DATA_DIRS = ($env.XDG_DATA_DIRS | str replace $"($env.VOID_SHELL_INTEGRATION_XDG_DIR):" "")
  }
  hide-env VOID_SHELL_INTEGRATION_XDG_DIR
}
