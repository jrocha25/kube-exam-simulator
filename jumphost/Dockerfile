# Base Image
FROM ubuntu:22.04

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
    openssh-server \
    vim \
    bash-completion\
    nano \
    docker.io\
    jq

# Accept build-time architecture argument
ARG TARGETARCH

# kubectl version. Kept in step with the cluster's Kubernetes minor
# (see K3S_VERSION in kind-cluster/Dockerfile) -- the supported client/server skew
# is one minor, and installing whatever "stable.txt" happens to point at on build
# day drifts far outside it.
ARG KUBECTL_VERSION=v1.34.10

#install kubectl for x86_64 and ARM64 architectures
RUN if [ "$TARGETARCH" = "amd64" ]; then \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/kubectl; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/kubectl; \
    fi

# Install Helm.
# Pinned to Helm 3: the get-helm-3 script now resolves to Helm 4, whose CLI output
# differs enough to break the `helm repo list | awk` parsing the Helm exercises do.
ARG HELM_VERSION=v3.21.3
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    && chmod 700 get_helm.sh \
    && DESIRED_VERSION="${HELM_VERSION}" ./get_helm.sh \
    && rm get_helm.sh \
    && helm version --short

#override docker daemon to use cfg2group
RUN echo '{ "exec-opts": ["native.cgroupdriver=cgroupfs"] }' > /etc/docker/daemon.json

# Set up SSH server
RUN mkdir -p /var/run/sshd

# Generate SSH host keys
RUN ssh-keygen -A

# Disable SSH authentication (VERY INSECURE: USE WITH CAUTION)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication no/' /etc/ssh/sshd_config
RUN sed -i 's/#UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# Completely remove password requirement
RUN echo "root::0:0:root:/root:/bin/bash" > /etc/passwd

# Create a new user 'candidate' with Docker permissions
RUN useradd -m candidate

#disable password login for candidate user
RUN echo "candidate::0:0:candidate:/home/candidate:/bin/bash" > /etc/passwd
RUN echo "candidate:x:1000:1000:candidate:/home/candidate:/bin/bash" >> /etc/passwd

# Set up Minikube cluster on startup
RUN mkdir -p /home/candidate/.kube /home/candidate/.minikube
RUN chown -R candidate: /home/candidate/.kube /home/candidate/.minikube

# ---------------------------------------------------------------------------
# Node shells for the kubeadm (kind) cluster flavour.
#
# The cluster's node containers run inside the k8s-api-server container's own
# docker daemon and are not routable from here, so each node's sshd is mapped out
# to a distinct port on that container (see env-setup-kind: controlplane -> 2222,
# node01 -> 2223, node02 -> 2224). These aliases turn that into the "ssh node01"
# the real CKA exam gives you.
#
# "aux" is the auxiliary cluster's single control-plane node, on 2232 -- a lab
# that carries "auxCluster" in its config.json gets a second cluster there, so a
# question may break something cluster-wide without the rest of the lab having to
# be written around the damage. It is worked the way the real exam is: ssh in and
# run kubectl on the node, where env-setup-kind leaves /root/.kube/config. The
# gap to 2232 leaves room for more primary workers.
#
# On a k3d lab the ports are simply closed and "ssh node01" fails, which is
# correct -- k3s has no node to get a shell on. The same is true of "ssh aux" on
# any lab that does not ask for an auxiliary cluster.
# ---------------------------------------------------------------------------
RUN mkdir -p /home/candidate/.ssh \
    && printf '%s\n' \
        'Host controlplane cp master' \
        '  HostName k8s-api-server' \
        '  Port 2222' \
        '  User root' \
        '  StrictHostKeyChecking no' \
        '  UserKnownHostsFile /dev/null' \
        '  LogLevel ERROR' \
        '' \
        'Host node01' \
        '  HostName k8s-api-server' \
        '  Port 2223' \
        '  User root' \
        '  StrictHostKeyChecking no' \
        '  UserKnownHostsFile /dev/null' \
        '  LogLevel ERROR' \
        '' \
        'Host node02' \
        '  HostName k8s-api-server' \
        '  Port 2224' \
        '  User root' \
        '  StrictHostKeyChecking no' \
        '  UserKnownHostsFile /dev/null' \
        '  LogLevel ERROR' \
        '' \
        'Host node03' \
        '  HostName k8s-api-server' \
        '  Port 2225' \
        '  User root' \
        '  StrictHostKeyChecking no' \
        '  UserKnownHostsFile /dev/null' \
        '  LogLevel ERROR' \
        '' \
        'Host aux aux-controlplane' \
        '  HostName k8s-api-server' \
        '  Port 2232' \
        '  User root' \
        '  StrictHostKeyChecking no' \
        '  UserKnownHostsFile /dev/null' \
        '  LogLevel ERROR' \
        > /home/candidate/.ssh/config \
    && chmod 700 /home/candidate/.ssh \
    && chmod 600 /home/candidate/.ssh/config \
    && chown -R candidate: /home/candidate/.ssh

# Copy exam environment scripts
COPY scripts/prepare-exam-env.sh /usr/local/bin/prepare-exam-env
COPY scripts/cleanup-exam-env.sh /usr/local/bin/cleanup-exam-env

# Make scripts executable
RUN chmod +x /usr/local/bin/prepare-exam-env
RUN chmod +x /usr/local/bin/cleanup-exam-env

RUN mkdir -p /tmp/exam-env

# Expose SSH port
EXPOSE 22

RUN echo "export TERM=xterm" >> /home/candidate/.bashrc
RUN echo "export KUBECONFIG=/home/candidate/.kube/kubeconfig" >> /home/candidate/.bashrc
RUN echo "PS1='\[\e[32m\]\u@\h:\w\$ \[\e[0m\]'" >> /home/candidate/.bashrc

#set kubectl autocompletion
RUN echo "source /usr/share/bash-completion/bash_completion" >> /home/candidate/.bashrc && \
    echo "source <(kubectl completion bash)" >> /home/candidate/.bashrc && \
    echo "alias k=kubectl" >> /home/candidate/.bashrc && \
    echo "complete -F __start_kubectl k" >> /home/candidate/.bashrc && \
    echo "source <(helm completion bash)" >> /home/candidate/.bashrc

#start ssh service
RUN useradd -r -s /usr/sbin/nologin sshd
# RUN service ssh start

ENV CLUSTER_NAME=cluster

# Start SSH and Minikube on container start
CMD ["/bin/bash", "-c", "service ssh start && dockerd & tail -f /dev/null"]
