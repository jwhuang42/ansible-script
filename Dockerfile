FROM ubuntu:22.04
ENV ANSIBLE_VERSION 8.7.0
RUN apt-get update; \
    apt-get install -y software-properties-common; \
    echo -e "\n" | add-apt-repository ppa:deadsnakes/ppa; \
    apt-get update; \
    apt-get install -y python3.10 python3-pip python-is-python3
RUN pip3 install --upgrade pip; \
    pip3 install "ansible==${ANSIBLE_VERSION}"; \
    pip3 install ansible
RUN apt-get install -y openssh-server