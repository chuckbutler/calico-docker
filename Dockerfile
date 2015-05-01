# For details and docs - see https://github.com/phusion/baseimage-docker#getting_started
FROM phusion/baseimage:0.9.16

# Use baseimage-docker's init system.
CMD ["/sbin/my_init"]

# Install Calico APT repo.  Note, we delay the apt-get update until 
# below so that the update is done in the same FS layer as the 
# install, making it unlikely to be out of sync.
#RUN curl -L http://binaries.projectcalico.org/repo/key | apt-key add - && \
#    echo "deb http://binaries.projectcalico.org/repo ./" >> /etc/apt/sources.list && \
#    echo "Package: *" >> /etc/apt/preferences &&\
#    echo "Pin: origin binaries.projectcalico.org" >> /etc/apt/preferences && \
#    echo "Pin-Priority: 1001" >> /etc/apt/preferences

# Ensure UTF-8, required for add-apt-repository call.
RUN locale-gen en_US.UTF-8
ENV LANG       en_US.UTF-8
ENV LC_ALL     en_US.UTF-8

# Copy in our custom configuration files etc.
COPY node /

RUN add-apt-repository -y ppa:cz.nic-labs/bird && \
    apt-get update && \ 
    apt-get install -qy \
        bird \
        bird6 \
        build-essential \
        ipset \
        iptables \
        libffi-dev \
        libssl-dev \
        libyaml-dev \
        python \
        python-dev \
        python-docopt \
        python-pip \
        python-pyasn1 \
        python-netaddr \
# Required by calico-felix, eventually should be removed.
        python-zmq \
        git \
        python-gevent && \
# Install Powerstrip Calico Adapter dependencies.
    pip install -r /adapter/requirements.txt && \
# Powerstrip
# Note that we are on a Metaswitch-customized version of Powerstrip that allows
# configuration to either listen on a UNIX socket, or a TCP socket for Docker,
# depending on an environment variable.
    git clone https://github.com/Metaswitch/powerstrip.git && \
    cd powerstrip && \
    sed -i s/2375/2377/ powerstrip.tac && \
    python setup.py install && \
#Remove things that were only needed for the build.
    apt-get remove -qy build-essential python-dev git libffi-dev libssl-dev libyaml-dev && \ 
    apt-get autoremove -qy && \ 
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Confd
RUN curl -L https://github.com/kelseyhightower/confd/releases/download/v0.9.0/confd-0.9.0-linux-amd64 -o confd && \
    chmod +x confd

RUN curl -L https://www.dropbox.com/s/zsr115cpuwv2okp/calico-common_0.15_all.deb?dl=1 -o common.deb && dpkg -i common.deb && rm common.deb
RUN curl -L https://www.dropbox.com/s/m959ktr1274vp9p/calico-felix_0.15_all.deb?dl=1 -o felix.deb && dpkg -i felix.deb && rm felix.deb



