{% if pillar["bootstrap"] is defined and "files" in pillar["bootstrap"] %}

  {%- set files = pillar["bootstrap"].get("files",{}) %}

  # intercepts cases with legacy bootstrap pillar, with structure like {"files": [{},{}]}
  {%- set managed = files.get("managed",{}) %}
  {%- if managed is iterable and managed is not mapping and managed is not string %}
      {%- set managed = {"bootstrap_grp": managed} %}
  {%- endif %}

  {%- set absent  = files.get("absent",{}) %}
  {%- if absent is iterable and absent is not mapping and absent is not string %}
      {%- set absent = {"bootstrap_grp": absent} %}
  {%- endif %}

  # patch each `file`, always add network domain
  {%- for blockname in managed %}
    {%- for file in managed[blockname] %}

      # ensure "values" exists in file
      {%- do file.update({"values": file.get("values", {}) }) %} 

      # skip domain updating, if it is already there
      {%- if not "bootstrap_network_domain" in file["values"] %} 

        # add domain to "values"
        {%- if "domain" in pillar["bootstrap"] %} 
          {%- do file["values"].update({"bootstrap_network_domain": pillar["bootstrap"]["domain"]}) %}
        {%- elif "network" in pillar["bootstrap"] and "domain" in pillar["bootstrap"]["network"] %}
          {%- do file["values"].update({"bootstrap_network_domain": pillar["bootstrap"]["network"]["domain"]}) %}
        {%- else %}
          {%- do file["values"].update({"bootstrap_network_domain": "local"}) %}
        {%- endif %}

      {%- endif %}

    {%- endfor %}
  {%- endfor %}

  {%- do files.update({"managed": managed, "absent": absent}) %}
  
  {%- include "_include/file_manager/init.sls" with context %}

{% endif %}
