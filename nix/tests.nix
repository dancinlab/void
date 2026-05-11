{
  self,
  system,
  nixpkgs,
  home-manager,
  ...
}: let
  nixos-version = nixpkgs.lib.trivial.release;

  pkgs = import nixpkgs {
    inherit system;
    overlays = [
      self.overlays.debug
    ];
  };

  pink_value = "#FF0087";

  color_test = ''
    import tempfile
    import subprocess

    def check_for_pink(final=False) -> bool:
        with tempfile.NamedTemporaryFile() as tmpin:
            machine.send_monitor_command("screendump {}".format(tmpin.name))

            cmd = 'convert {} -define histogram:unique-colors=true -format "%c" histogram:info:'.format(
                tmpin.name
            )
            ret = subprocess.run(cmd, shell=True, capture_output=True)
            if ret.returncode != 0:
                raise Exception(
                    "image analysis failed with exit code {}".format(ret.returncode)
                )

            text = ret.stdout.decode("utf-8")
            return "${pink_value}" in text
  '';

  mkNodeGnome = {
    config,
    pkgs,
    settings,
    sshPort ? null,
    ...
  }: {
    imports = [
      ./vm/wayland-gnome.nix
      settings
    ];

    virtualisation = {
      forwardPorts = pkgs.lib.optionals (sshPort != null) [
        {
          from = "host";
          host.port = sshPort;
          guest.port = 22;
        }
      ];

      vmVariant = {
        virtualisation.host.pkgs = pkgs;
      };
    };

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
        PermitEmptyPasswords = "yes";
      };
    };

    security.pam.services.sshd.allowNullPassword = true;

    users.groups.void = {
      gid = 1000;
    };

    users.users.void = {
      uid = 1000;
    };

    home-manager = {
      users = {
        void = {
          home = {
            username = config.users.users.void.name;
            homeDirectory = config.users.users.void.home;
            stateVersion = nixos-version;
          };
          programs.ssh = {
            enable = true;
            enableDefaultConfig = false;
            extraOptionOverrides = {
              StrictHostKeyChecking = "accept-new";
              UserKnownHostsFile = "/dev/null";
            };
          };
        };
      };
    };

    system.stateVersion = nixos-version;
  };

  mkTestGnome = {
    name,
    settings,
    testScript,
    ocr ? false,
  }:
    pkgs.testers.runNixOSTest {
      name = name;

      enableOCR = ocr;

      extraBaseModules = {
        imports = [
          home-manager.nixosModules.home-manager
        ];
      };

      nodes = {
        machine = {
          config,
          pkgs,
          ...
        }:
          mkNodeGnome {
            inherit config pkgs settings;
            sshPort = 2222;
          };
      };

      testScript = testScript;
    };
in {
  basic-version-check = pkgs.testers.runNixOSTest {
    name = "basic-version-check";
    nodes = {
      machine = {pkgs, ...}: {
        users.groups.void = {};
        users.users.void = {
          isNormalUser = true;
          group = "void";
          extraGroups = ["wheel"];
          hashedPassword = "";
          packages = [
            pkgs.void
          ];
        };
      };
    };
    testScript = {...}: ''
      machine.succeed("su - void -c 'void +version'")
    '';
  };

  basic-window-check-gnome = mkTestGnome {
    name = "basic-window-check-gnome";
    settings = {
      home-manager.users.void = {
        xdg.configFile = {
          "void/config".text = ''
            background = ${pink_value}
          '';
        };
      };
    };
    ocr = true;
    testScript = {nodes, ...}: let
      user = nodes.machine.users.users.void;
      bus_path = "/run/user/${toString user.uid}/bus";
      bus = "DBUS_SESSION_BUS_ADDRESS=unix:path=${bus_path}";
      gdbus = "${bus} gdbus";
      void = "${bus} void";
      su = command: "su - ${user.name} -c '${command}'";
      gseval = "call --session -d org.gnome.Shell -o /org/gnome/Shell -m org.gnome.Shell.Eval";
      wm_class = su "${gdbus} ${gseval} global.display.focus_window.wm_class";
    in ''
      ${color_test}

      with subtest("wait for x"):
          start_all()
          machine.wait_for_x()

      machine.wait_for_file("${bus_path}")

      with subtest("Ensuring no pink is present without the terminal."):
          assert (
              check_for_pink() == False
          ), "Pink was present on the screen before we even launched a terminal!"

      machine.systemctl("enable app-com.dancinlab.void-debug.service", user="${user.name}")
      machine.succeed("${su "${void} +new-window"}")
      machine.wait_until_succeeds("${wm_class} | grep -q 'com.dancinlab.void-debug'")

      machine.sleep(2)

      with subtest("Have the terminal display a color."):
          assert(
              check_for_pink() == True
          ), "Pink was not found on the screen!"

      machine.systemctl("stop app-com.dancinlab.void-debug.service", user="${user.name}")
    '';
  };

  ssh-integration-test = pkgs.testers.runNixOSTest {
    name = "ssh-integration-test";
    extraBaseModules = {
      imports = [
        home-manager.nixosModules.home-manager
      ];
    };
    nodes = {
      server = {...}: {
        users.groups.void = {};
        users.users.void = {
          isNormalUser = true;
          group = "void";
          extraGroups = ["wheel"];
          hashedPassword = "";
          packages = [];
        };
        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = "yes";
            PermitEmptyPasswords = "yes";
          };
        };
        security.pam.services.sshd.allowNullPassword = true;
      };
      client = {
        config,
        pkgs,
        ...
      }:
        mkNodeGnome {
          inherit config pkgs;
          settings = {
            home-manager.users.void = {
              xdg.configFile = {
                "void/config".text = let
                in ''
                  shell-integration-features = ssh-terminfo
                '';
              };
            };
          };
          sshPort = 2222;
        };
    };
    testScript = {nodes, ...}: let
      user = nodes.client.users.users.void;
      bus_path = "/run/user/${toString user.uid}/bus";
      bus = "DBUS_SESSION_BUS_ADDRESS=unix:path=${bus_path}";
      gdbus = "${bus} gdbus";
      void = "${bus} void";
      su = command: "su - ${user.name} -c '${command}'";
      gseval = "call --session -d org.gnome.Shell -o /org/gnome/Shell -m org.gnome.Shell.Eval";
      wm_class = su "${gdbus} ${gseval} global.display.focus_window.wm_class";
    in ''
      with subtest("Start server and wait for ssh to be ready."):
          server.start()
          server.wait_for_open_port(22)

      with subtest("Start client and wait for void window."):
          client.start()
          client.wait_for_x()
          client.wait_for_file("${bus_path}")
          client.systemctl("enable app-com.dancinlab.void-debug.service", user="${user.name}")
          client.succeed("${su "${void} +new-window"}")
          client.wait_until_succeeds("${wm_class} | grep -q 'com.dancinlab.void-debug'")

      with subtest("SSH from client to server and verify that the Void terminfo is copied."):
          client.sleep(2)
          client.send_chars("ssh void@server\n")
          server.wait_for_file("${user.home}/.terminfo/x/xterm-void", timeout=30)
    '';
  };
}
