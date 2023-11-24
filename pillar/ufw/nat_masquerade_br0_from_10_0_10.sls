ufw:
  nat:
    masquerade:
      nat_masquerade_br0_from_10_0_10:
        source: 10.0.10.0/24
        out: br0
