# Linux "remote server" for Kamal deploys when developing on macOS.
# Provides sshd + docker CLI + GNU userland so Kamal's Linux assumptions
# (cp -T, etc.) all hold. The host's docker daemon is mounted via socket
# so containers Kamal spawns actually run on the host.
FROM ubuntu:24.04

# Defaults are placeholders; docker-compose.kamal-host.yml overrides all four
# with values derived from the host ($USER, id -u, id -g, $PWD) so the
# container user matches whoever is running it.
ARG USER_NAME=deploy
ARG USER_UID=1000
ARG USER_GID=1000
ARG USER_HOME=/srv/app

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
      openssh-server docker.io sudo rsync curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Match macOS uid/gid so bind-mounted files keep correct ownership on host.
# Home is set to the bind-mounted project path so $PWD aligns between
# container and host (required because docker socket is shared).
RUN if ! getent group ${USER_GID} >/dev/null; then groupadd -g ${USER_GID} hostgroup; fi && \
    useradd -u ${USER_UID} -g ${USER_GID} -d ${USER_HOME} -M -s /bin/bash ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER_NAME}

RUN mkdir -p /run/sshd /etc/ssh/authorized_keys.d && \
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's|^#*AuthorizedKeysFile.*|AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u|' /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
