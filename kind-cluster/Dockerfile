FROM docker:dind

# Accept build-time architecture argument
ARG TARGETARCH

#install curl
RUN apk add --no-cache curl
# use our own to start kind cluster
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# persist existing entrypoint
RUN cp /usr/local/bin/dockerd-entrypoint.sh /usr/local/bin/startup.sh

#copy scripts
COPY scripts/ /usr/local/bin/

#make scripts executable
RUN chmod +x /usr/local/bin/env-setup
RUN chmod +x /usr/local/bin/env-setup-kind
RUN chmod +x /usr/local/bin/env-cleanup
RUN chmod +x /usr/local/bin/k3d-install.sh

# Kubernetes version served to candidates. Single source of truth: env-setup pins
# the k3d cluster to this exact k3s image instead of inheriting whatever k3s tag was
# baked into the k3d binary at its own build time.
# Note: the k3s git tag "v1.34.10+k3s1" is published as the image tag "v1.34.10-k3s1".
ARG K3S_VERSION=v1.34.10-k3s1
ENV K3S_VERSION=${K3S_VERSION}

# k3d release used to create the cluster.
ARG K3D_VERSION=v5.9.0
ENV K3D_VERSION=${K3D_VERSION}

# ---------------------------------------------------------------------------
# kubeadm cluster flavour (clusterType "kind" in a lab's config.json).
#
# k3s runs the control plane as a single embedded process: there is no
# /etc/kubernetes/manifests, no static pods and no kubeadm. kind bootstraps its
# nodes with kubeadm, so labs that need to break and repair a static pod, read
# crictl logs on a node or take an etcd snapshot have to run on this flavour.
#
# The node image is pinned by digest to the one kind v0.32.0 was released with,
# and its minor is kept in step with KUBECTL_VERSION in jumphost/Dockerfile --
# the supported client/server skew is one minor.
#
# It is the image for the primary cluster. A lab may start its *auxiliary* cluster
# on a different one with "auxNodeImage" in config.json (cka/010 starts its aux a
# minor behind, on v1.33, so that a question can upgrade it with kubeadm). Keep
# CALICO_VERSION inside its tested range for both minors when bumping either --
# Calico 3.32 is tested on 1.34+, 3.31 on 1.32-1.35 -- and keep any such lab's
# auxNodeImage within one minor of the jumphost kubectl.
# ---------------------------------------------------------------------------
ARG KIND_VERSION=v0.32.0
ENV KIND_VERSION=${KIND_VERSION}

ARG KIND_NODE_IMAGE=kindest/node:v1.34.8@sha256:02722c2dedddcfc00febf5d27fbeb9b7b2c14294c82109ff4a85d89ac9ba3256
ENV KIND_NODE_IMAGE=${KIND_NODE_IMAGE}

# Calico replaces kindnet on the kind flavour: kindnet does not implement
# NetworkPolicy, so a policy question would silently pass no matter what the
# candidate wrote. k3s needs no equivalent -- it ships a policy controller.
ARG CALICO_VERSION=v3.32.1
ENV CALICO_VERSION=${CALICO_VERSION}

# kubectl, needed by env-setup-kind to install the CNI and wait on the nodes.
# The k3d path never needed one -- k3d talks to the cluster through its own
# binary -- so this image had no kubectl at all. Pinned to the node image's minor.
ARG KUBECTL_VERSION=v1.34.8
RUN if [ "$TARGETARCH" = "arm64" ]; then KARCH=arm64; else KARCH=amd64; fi \
    && wget -q "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KARCH}/kubectl" -O /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && kubectl version --client=true

# install kind for x86_64 and ARM64 architectures
RUN if [ "$TARGETARCH" = "amd64" ]; then \
    wget -q "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" -O /usr/local/bin/kind; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
    wget -q "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-arm64" -O /usr/local/bin/kind; \
    fi \
    && chmod +x /usr/local/bin/kind \
    && kind version

# env-setup is invoked over SSH and sshd does not hand the image's ENV to the
# session, so the versions are also persisted to a file that the scripts source.
RUN printf 'K3S_VERSION=%s\nK3D_VERSION=%s\nKIND_VERSION=%s\nKIND_NODE_IMAGE=%s\nCALICO_VERSION=%s\n' \
    "${K3S_VERSION}" "${K3D_VERSION}" "${KIND_VERSION}" "${KIND_NODE_IMAGE}" "${CALICO_VERSION}" > /etc/ck-x-versions

RUN apk add --no-cache openssh-server
RUN apk add bash 
RUN apk add openssh-server-pam

RUN ssh-keygen -A

# allow root ssh login without password 
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication no/' /etc/ssh/sshd_config
RUN sed -i 's/^#UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

# create a non-login user for ssh access
RUN adduser -D -s /bin/bash candidate
RUN passwd -d candidate

# #set not password for candidate user
RUN echo "candidate::0:0:candidate:/home/candidate:/bin/bash" > /etc/passwd
RUN echo "candidate:x:1000:1000:candidate:/home/candidate:/bin/bash" >> /etc/passwd

# create a home directory for the candidate user
RUN mkdir -p /home/candidate
RUN chown -R candidate: /home/candidate

EXPOSE 6443
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]