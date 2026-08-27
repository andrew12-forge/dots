brew_prefix := if os() == "macos" { "/opt/homebrew" } else { "/home/linuxbrew/.linuxbrew" }

brew:
  brew bundle install --file=homebrew/Brewfile

init-fish:
  grep -qxF "{{brew_prefix}}/bin/fish" /etc/shells || echo "{{brew_prefix}}/bin/fish" | sudo tee -a /etc/shells
  chsh -s {{brew_prefix}}/bin/fish

stow:
  stow -t ~ claude
  stow -t ~ fish
  stow -t ~ forge-tools
  stow -t ~ nvim
  stow -t ~ wezterm

init: brew stow init-fish
  @echo "✓ Initialization complete!"

# Install the Chime Dev Tools editor extension (repo: Forge-FDE/chime-dev-tools).
install-chime-dev-tools:
  cd ~/_dev/chime-dev-tools && ./build-vsix.py
  cursor --install-extension ~/_dev/chime-dev-tools/chime-dev-tools-1.1.0.vsix --force
  @echo "✓ installed; reload the Cursor window (Cmd+Shift+P → Developer: Reload Window)"
