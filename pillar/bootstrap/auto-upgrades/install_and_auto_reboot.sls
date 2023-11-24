bootstrap:
  auto-upgrades: |
    APT::Periodic::Update-Package-Lists "1";
    APT::Periodic::Unattended-Upgrade "1";
    Unattended-Upgrade::Automatic-Reboot "true";
