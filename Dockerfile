FROM debian:trixie-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    ninja-build gettext cmake unzip curl build-essential file git gpg coreutils moreutils \
    && apt-get clean

# Install neovim
RUN  git clone --depth 1 --branch stable https://github.com/neovim/neovim /tmp/neovim && \
    cd /tmp/neovim && \
    make CMAKE_BUILD_TYPE=RelWithDebInfo && \
    cd build && \
    cpack -G DEB && \
    dpkg -i --force-overwrite nvim-linux-x86_64.deb && \
    rm -rf /tmp/neovim

ENV PATH="/root/.local/bin:$PATH"

# Ensure /dev/null
RUN if [ -f /dev/null ]; then rm /dev/null; fi

WORKDIR /opt
