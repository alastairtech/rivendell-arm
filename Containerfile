ARG BASE_TAG="develop"
ARG BASE_IMAGE="core-ubuntu-jammy"
FROM docker.io/kasmweb/$BASE_IMAGE:$BASE_TAG
USER root

ENV HOME /home/kasm-default-profile
ENV STARTUPDIR /dockerstartup
ENV INST_SCRIPTS $STARTUPDIR/install
WORKDIR $HOME

######### Customize Container Here ###########

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       software-properties-common \
       rsyslog systemd systemd-cron sudo \
    && apt-get clean \
    && rm -Rf /usr/share/doc && rm -Rf /usr/share/man \
    && rm -rf /var/lib/apt/lists/* \
    && touch -d "2 hours ago" /var/lib/apt/lists
RUN sed -i 's/^\($ModLoad imklog\)/#\1/' /etc/rsyslog.conf

RUN rm -f /lib/systemd/system/systemd*udev* \
  && rm -f /lib/systemd/system/getty.target

VOLUME ["/sys/fs/cgroup", "/tmp", "/run"]
CMD ["/lib/systemd/systemd"]

# RUN export DEBIAN_FRONTEND=noninteractive && sudo apt update && sudo apt install tzdata && sudo rm /etc/localtime && sudo ln -s /usr/share/zoneinfo/Australia/Melbourne /etc/localtime

RUN useradd -m rd

RUN apt-get update \
    && apt-get install -y sudo \
    && echo 'kasm-user ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers \
    && rm -rf /var/lib/apt/list/*

RUN apt-get install -y gedit wget nano firefox nfs-common

RUN wget https://software.paravelsystems.com/ubuntu/dists/jammy/main/Paravel-Ubuntu-22.04-Test.gpg -P /etc/apt/trusted.gpg.d/ \
    && wget https://software.paravelsystems.com/ubuntu/dists/jammy/main/Paravel-Ubuntu-22.04-Test.list -P /etc/apt/sources.list.d/ \
    && apt-get update \
    && apt-get -y install ubuntu-rivendell-installer \
    && /usr/share/ubuntu-rivendell-installer/installer_install_rivendell.sh --standalone

RUN echo "mount -o 192.168.1.11:/volume1/snd /var/snd" > $STARTUPDIR/custom_startup.sh \
&& chmod +x $STARTUPDIR/custom_startup.sh

# RUN echo "192.168.1.11:/volume1/snd /var/snd nfs nofail,noauto,x-systemd.automount" | sudo tee -a /etc/fstab

RUN echo "rd:$(mkpasswd)" | sudo chpasswd

######### End Customizations ###########

RUN chown 1000:0 $HOME
RUN $STARTUPDIR/set_user_permission.sh $HOME

ENV HOME /home/kasm-user
WORKDIR $HOME
RUN mkdir -p $HOME && chown -R 1000:0 $HOME

USER 1000