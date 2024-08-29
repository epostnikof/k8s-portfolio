FROM ubuntu:latest
RUN apt update && \ 
  apt install curl -y && \
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \ 
  chmod 700 get_helm.sh && \
  ./get_helm.sh && \
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
  mv kubectl /usr/bin/kubectl && \
  chmod +x /usr/bin/kubectl && \
  apt install openssh-client -y
