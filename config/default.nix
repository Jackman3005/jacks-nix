{
  imports = [ ./options.nix ];

  jacks-nix = {
    # Set your personal details here
    user = {
      name = "Jack Coy";
      email = "jackman3000@gmail.com";
      username = "jack";
    };

    # Toggle features on or off
    enableGit = true;
    enableZsh = true;
    enableNvim = true;
    enableHomebrew = true;
  };
}
