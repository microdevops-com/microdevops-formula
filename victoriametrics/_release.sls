{%- set response = salt.http.query(defaults["platforms"][platform]["tags_url"]) %}
{%- if not "error" in response and "body" in response %}
  {%- set body = response["body"] | load_json %}
  {%- set latest = body[0]["name"].replace("-cluster","") %}
{%- else %}
  {{ raise("\n>>> CRITICAL: error occured during fetching \"latest\" release tag\n>>> kind: " ~ kind ~ "\n>>> remote response: " ~ response ~ "\n>>> remote url: " ~ defaults["platforms"][platform]["tags_url"] ) }}
{%- endif %}
