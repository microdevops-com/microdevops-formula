# Core socket buffer ceilings = 16 MiB, for high-RTT links.
# Max TCP throughput = window / RTT, and the window cannot exceed the socket
# buffer. Default ceilings (~208 KiB) cap a ~280ms path at ~6 Mbit/s no matter
# how fast the uplink is -- large transfers crawl or stall. 16 MiB lifts that
# ceiling well above any realistic bandwidth-delay product (16M/0.28s ~ 450 Mbit/s).
# Only the *_max ceilings are raised; kernel autotuning grows real buffers on
# demand, so idle/small connections keep their tiny footprint (RAM-safe).
sysctl:
  default:
    net.core.rmem_max: 16777216
    net.core.wmem_max: 16777216
