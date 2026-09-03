# Ensure the SeaweedFS bucket TTL for the Sentry self-hosted nodestore (and optionally profiles).
#
# Why this state exists:
#   install.sh sets the S3 lifecycle policy only on first bootstrap of the bucket, and never
#   updates it afterwards (getsentry/self-hosted#4028). On top of that, `s3cmd setlifecycle`
#   hangs with /?lifecycle timeouts against the bundled SeaweedFS (#4257, #4327; seaweedfs#8754),
#   so on many installs the policy was never applied at all. Without it, nodestore blobs never
#   expire and the seaweedfs volume grows unbounded regardless of SENTRY_EVENT_RETENTION_DAYS.
#
#   This state applies the TTL directly via `weed shell fs.configure`, which talks to the filer
#   over gRPC and bypasses the broken S3 lifecycle HTTP handler. It is idempotent (the `unless`
#   below) and re-applies automatically whenever the retention pillar changes.
#
# Days come from the same pillar key init.sls writes into .env.custom, so TTL stays in sync
# with retention: sentry:config:general:options:system:event_retention_days (default 90).
#
# Optional pillar to cover more buckets (e.g. the vroom 'profiles' bucket):
#   sentry:
#     seaweedfs_ttl:
#       buckets: [nodestore, profiles]
#
# Notes:
#   - Gated to self-hosted >= 25.9.0 — the SeaweedFS nodestore did not exist before that.
#   - Do NOT pass -collection: SeaweedFS binds each S3 bucket to a same-named collection and
#     rejects a manual one ("one s3 bucket goes to one collection and not customizable").
#   - order: last runs this after sentry_docker_compose_up when included from init.sls.
#   - TTL applies to objects written after it is set; volumes created earlier without a TTL
#     stay on disk until removed manually (weed shell volume.delete).

{% if salt["pkg.version_cmp"](pillar.get("sentry", {}).get("version", "0"), "25.9.0") >= 0 %}

{%- set days    = salt["pillar.get"]("sentry:config:general:options:system:event_retention_days", 90) | int %}
{%- set buckets = salt["pillar.get"]("sentry:seaweedfs_ttl:buckets", ["nodestore"]) %}

{%- for bucket in buckets %}
sentry_seaweedfs_ttl_{{ bucket }}:
  cmd.run:
    - shell: /bin/bash
    - cwd: /opt/sentry
    - order: last
    - name: |
        set -euo pipefail
        echo "Applying TTL {{ days }}d to /buckets/{{ bucket }}/"
        docker-compose exec -T seaweedfs sh -c "echo 'fs.configure -locationPrefix=/buckets/{{ bucket }}/ -ttl={{ days }}d -apply' | weed shell"
        # fs.configure prints the filer config as JSON: {"version":N,"locations":[...]}.
        # After stripping whitespace, our entry reads {"locationPrefix":"/buckets/<b>/",...,"ttl":"<days>d"}.
        CONF=$(docker-compose exec -T seaweedfs sh -c "echo 'fs.configure' | weed shell" 2>/dev/null | tr -d ' \t\n')
        echo "Resulting filer config: ${CONF}"
        echo "${CONF}" | grep -q '"locationPrefix":"/buckets/{{ bucket }}/"[^}]*"ttl":"{{ days }}d"' \
          || { echo "TTL {{ days }}d for {{ bucket }} not visible after apply" >&2; exit 1; }
    # Idempotency: skip the apply when the filer already advertises this exact TTL for the bucket.
    - unless: |
        docker-compose exec -T seaweedfs sh -c "echo 'fs.configure' | weed shell" 2>/dev/null \
          | tr -d ' \t\n' \
          | grep -q '"locationPrefix":"/buckets/{{ bucket }}/"[^}]*"ttl":"{{ days }}d"'
    # Don't attempt anything if the seaweedfs container isn't up yet (e.g. first converge).
    - onlyif: docker inspect -f '{{ '{{.State.Running}}' }}' sentry-self-hosted-seaweedfs-1 2>/dev/null | grep -q true
{%- endfor %}

{% endif %}
