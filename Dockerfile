FROM debian:trixie
ENV DEBIAN_FRONTEND=noninteractive
ENV AQ_NO_KMS_REQUIREMENT=1
ENV LIBSEAT_BACKEND=noop


RUN echo "deb http://deb.debian.org/debian trixie-backports main" >> /etc/apt/sources.list.d/backports.list

#Install deps
RUN apt-get update && apt-get install -y \
    libxkbcommon0 \
&& rm -rf /var/lib/apt/lists/*

#stoping shim , and comment everything after
# CMD ["sleep", "infinity"]


RUN apt-get update && apt-get install -y -t trixie-backports \
    hyprland \
    seatd \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -f seat
RUN usermod -aG seat root

RUN apt-get update && apt-get install -y \
    kitty \
    wayvnc \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y git \
    && git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages websockify

EXPOSE 22 5900 6080
