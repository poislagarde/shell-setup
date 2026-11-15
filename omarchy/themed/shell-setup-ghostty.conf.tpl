# Omarchy renders this into the current theme on every theme change, and
# ghostty/linux.conf loads the result. Light themes have no
# ~/.shell-setup/ghostty-light.conf, so they keep their own text color.
config-file = ?"~/.shell-setup/ghostty-{{ mode }}.conf"
