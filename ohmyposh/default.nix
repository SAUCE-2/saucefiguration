# Oh My Posh prompt, from theme.omp.json beside this file.
{ ... }:
{
  programs.oh-my-posh = {
    enable = true;
    configFile = "${./theme.omp.json}";
  };
}
