# Base Image
FROM nishanb/ck-x-simulator-vnc-base:v3@sha256:deb815df50076b6a4408d79f3206b727e8433c6ff7378beee1d68b7612060d9b

# Switch to root user for installations
USER 0

# Update and install required dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    ssh-client \
    telnet \
    nano \
    vim \
    curl \
    wget \
    xclip

#replace the base image's Firefox 88 (the last build Ubuntu shipped for 16.04) with Mozilla's ESR.
#Firefox 88 runs an inline async module script ahead of the classic scripts after it, so on any
#kubernetes.io page with a mermaid diagram the theme observer sees Docsy's first data-bs-theme
#write and calls location.reload() on every load. The stale profile goes too: it came with the base.
ARG FIREFOX_VERSION=153.5.1esr
ARG FIREFOX_SHA256=e289bdc532decf2b54dea9b5ac64cf6f84a62eeec4d4a9ec2f69590f61b0ff1c
RUN apt-get purge -y firefox xul-ext-ubufox \
    && rm -rf /usr/lib/firefox /headless/.mozilla \
    && curl -fsSL -o /tmp/firefox.tar.xz "https://ftp.mozilla.org/pub/firefox/releases/${FIREFOX_VERSION}/linux-x86_64/en-US/firefox-${FIREFOX_VERSION}.tar.xz" \
    && echo "${FIREFOX_SHA256}  /tmp/firefox.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/firefox.tar.xz -C /opt \
    && rm /tmp/firefox.tar.xz \
    && ln -sf /opt/firefox/firefox /usr/bin/firefox \
    && sed -i 's|^Icon=.*|Icon=/opt/firefox/browser/chrome/icons/default/default128.png|' /headless/Desktop/firefox.desktop
#no updates, telemetry or first-run dialogs; kubernetes.io as the homepage
COPY firefox-policies.json /opt/firefox/distribution/policies.json

#create candidate user
RUN useradd -m candidate

#set hostname as terminal
RUN echo "export HOSTNAME=terminal" >> /headless/.bashrc
#set terminal to bash
RUN echo "export TERM=xterm" >> /headless/.bashrc

#when shell open switch to candidate user
RUN echo "cd /home/candidate && su candidate" >> /headless/.bashrc

#disable asking for ssh host verification
RUN mkdir -p /home/candidate/.ssh
RUN touch /home/candidate/.ssh/config
RUN echo "StrictHostKeyChecking no" >> /home/candidate/.ssh/config
RUN echo "UserKnownHostsFile /dev/null" >> /home/candidate/.ssh/config


# Copy startup script
COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

COPY agent.py /tmp/agent.py

RUN sed -i '/### every exit != 0 fails the script/a /usr/local/bin/startup.sh' /dockerstartup/vnc_startup.sh
