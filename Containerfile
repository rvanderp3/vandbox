FROM registry.access.redhat.com/ubi9/ubi:latest

ARG INSTALL_STRACE=0

RUN dnf install -y nftables procps-ng && \
    if [ "${INSTALL_STRACE}" = "1" ]; then dnf install -y strace; fi && \
    dnf clean all && \
    rm -rf /var/cache/dnf

RUN useradd -m -s /bin/bash sandbox && \
    mkdir -p /var/log/vandbox /workspace && \
    chown sandbox:sandbox /var/log/vandbox /workspace

COPY scripts/ /opt/vandbox/scripts/
COPY config/ /opt/vandbox/config/
COPY seccomp/ /opt/vandbox/seccomp/

RUN chmod +x /opt/vandbox/scripts/*.sh

WORKDIR /workspace

ENTRYPOINT ["/opt/vandbox/scripts/entrypoint.sh"]
CMD ["/bin/bash"]
