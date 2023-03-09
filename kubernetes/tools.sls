{% if pillar["kubernetes"] is defined and "tools" in pillar["kubernetes"] %}

  {%- if "kubectl" in pillar["kubernetes"]["tools"] %}
k8s_tools_kubectl_repo:
  pkgrepo.managed:
    - humanname: Kubernetes Repository
    - name: deb http://apt.kubernetes.io/ kubernetes-{{ "xenial" if grains["oscodename"] in ["bionic", "focal", "jammy"] else grains["oscodename"] }} main
    - file: /etc/apt/sources.list.d/kubernetes.list
    - key_url: https://packages.cloud.google.com/apt/doc/apt-key.gpg
    - clean_file: True

    {%- if pillar["kubernetes"]["tools"]["kubectl"] == "latest" %}
k8s_tools_kubectl:
  pkg.latest:
    - refresh: True
    - pkgs:
      - kubectl
    - require:
      - pkgrepo: k8s_tools_kubectl_repo
    {%- else %}
k8s_tools_kubectl:
  pkg.installed:
    - refresh: True
    - pkgs:
      - kubectl: '{{ pillar["kubernetes"]["tools"]["kubectl"] }}*'
    - require:
      - pkgrepo: k8s_tools_kubectl_repo
    {%- endif %}

  {%- endif %}

  {%- if "helm-assistant" in pillar["kubernetes"]["tools"] %}
k8s_tools_helm_assistant_curl:
  cmd.run:
    - name: |
        curl -L https://github.com/SomeBlackMagic/helm-assistant/releases/download/v{{ pillar["kubernetes"]["tools"]["helm-assistant"] }}/helm-assistant-linux-amd64 -o /usr/local/bin/helm-assistant
        chmod +x /usr/local/bin/helm-assistant

  {%- endif %}

  {%- if "helm" in pillar["kubernetes"]["tools"] %}
k8s_tools_helm_curl:
  cmd.run:
    - name: |
        curl -L https://get.helm.sh/helm-v{{ pillar["kubernetes"]["tools"]["helm"] }}-linux-amd64.tar.gz -o /tmp/helm.tar.gz
        tar -zxvf /tmp/helm.tar.gz -C /tmp
        mv /tmp/linux-amd64/helm /usr/local/bin/helm
        chmod +x /usr/local/bin/helm

  {%- endif %}

{% endif %}
