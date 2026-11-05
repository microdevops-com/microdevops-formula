# Disable Multipath TCP (kernel >= 5.6, on by default). Belt-and-braces for
# CVE-2026-98432: the bug is in plain IPv4 TCP, but the public remote code execution
# chain needs an MPTCP listener, and every Go >= 1.24 daemon (node_exporter, vmagent,
# ping_exporter, incusd, ...) opens one by default. Go and other users fall back to
# plain TCP when MPTCP is unavailable, so nothing breaks.
#
# Not a fix: the real mitigation is the firewall drop of inbound TCP with IP options
# (pillar/ufw/cve_2026_98432_mitigation.sls) or a fixed kernel. The sysctl is per
# network namespace: it does not reach Docker/k8s containers, which the firewall rule
# covers. LXC/Incus guests own their namespace and can apply it themselves.
# Rendered only where the key exists; on older kernels sysctl.present would fail.
{%- set kernel_version = grains["kernelrelease"].split("-")[0].split(".") %}
{%- if kernel_version[0] | int > 5 or (kernel_version[0] | int == 5 and kernel_version[1] | int >= 6) %}
sysctl:
  default:
    net.mptcp.enabled: 0
{%- endif %}
