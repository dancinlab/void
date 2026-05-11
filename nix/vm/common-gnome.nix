{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./common.nix
  ];

  services = {
    displayManager = {
      gdm = {
        enable = true;
        autoSuspend = false;
      };
    };
    desktopManager = {
      gnome = {
        enable = true;
      };
    };
  };

  systemd.user.services = {
    "org.gnome.Shell@wayland" = {
      serviceConfig = {
        ExecStart = [
          # Clear the list before overriding it.
          ""
          # Eval API is now internal so Shell needs to run in unsafe mode.
          "${pkgs.gnome-shell}/bin/gnome-shell --unsafe-mode"
        ];
      };
    };
  };

  environment.systemPackages = [
    pkgs.gnomeExtensions.no-overview
  ];

  environment.gnome.excludePackages = with pkgs; [
    atomix
    baobab
    cheese
    epiphany
    evince
    file-roller
    geary
    gnome-backgrounds
    gnome-calculator
    gnome-calendar
    gnome-clocks
    gnome-connections
    gnome-contacts
    gnome-disk-utility
    gnome-extension-manager
    gnome-logs
    gnome-maps
    gnome-music
    gnome-photos
    gnome-software
    gnome-system-monitor
    gnome-text-editor
    gnome-themes-extra
    gnome-tour
    gnome-user-docs
    gnome-weather
    hitori
    iagno
    loupe
    nautilus
    orca
    seahorse
    simple-scan
    snapshot
    sushi
    tali
    totem
    yelp
  ];

  programs.dconf = {
    enable = true;
    profiles.user.databases = [
      {
        settings = with lib.gvariant; {
          "org/gnome/desktop/background" = {
            picture-uri = "file://${pkgs.void}/share/icons/hicolor/512x512/apps/com.dancinlab.void.png";
            picture-uri-dark = "file://${pkgs.void}/share/icons/hicolor/512x512/apps/com.dancinlab.void.png";
            picture-options = "centered";
            primary-color = "#000000000000";
            secondary-color = "#000000000000";
          };
          "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
          };
          "org/gnome/desktop/notifications" = {
            show-in-lock-screen = false;
          };
          "org/gnome/desktop/screensaver" = {
            lock-enabled = false;
            picture-uri = "file://${pkgs.void}/share/icons/hicolor/512x512/apps/com.dancinlab.void.png";
            picture-options = "centered";
            primary-color = "#000000000000";
            secondary-color = "#000000000000";
          };
          "org/gnome/desktop/session" = {
            idle-delay = mkUint32 0;
          };
          "org/gnome/shell" = {
            disable-user-extensions = false;
            enabled-extensions = builtins.map (x: x.extensionUuid) (
              lib.filter (p: p ? extensionUuid) config.environment.systemPackages
            );
          };
        };
      }
    ];
  };

  programs.geary.enable = false;

  services.gnome = {
    gnome-browser-connector.enable = false;
    gnome-initial-setup.enable = false;
    gnome-online-accounts.enable = false;
    gnome-remote-desktop.enable = false;
    rygel.enable = false;
  };

  system.activationScripts = {
    face = {
      text = ''
        mkdir -p /var/lib/AccountsService/{icons,users}

        cp ${pkgs.void}/share/icons/hicolor/1024x1024/apps/com.dancinlab.void.png /var/lib/AccountsService/icons/void

        echo -e "[User]\nIcon=/var/lib/AccountsService/icons/void\n" > /var/lib/AccountsService/users/void

        chown root:root /var/lib/AccountsService/users/void
        chmod 0600 /var/lib/AccountsService/users/void

        chown root:root /var/lib/AccountsService/icons/void
        chmod 0444 /var/lib/AccountsService/icons/void
      '';
    };
  };
}
