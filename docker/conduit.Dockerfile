ARG DEBIAN_VERSION=buster
FROM matrixdotorg/sytest:${DEBIAN_VERSION}

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    ca-certificates curl file \
    build-essential \
    openssl \
    autoconf automake autotools-dev libtool xutils-dev && \
    rm -rf /var/lib/apt/lists/*

RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- --default-toolchain nightly -y

ENV PATH=/root/.cargo/bin:$PATH

# This is where we expect Dendrite to be binded to from the host
RUN mkdir -p /src

ENTRYPOINT [ "/bin/bash", "/bootstrap.sh", "dendrite" ]
