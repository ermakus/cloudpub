FROM    python:3.12-slim AS dev

ENV     HOME="/home/cloudpub"
ENV     NODE_VERSION=22.11.0
ENV     NVM_DIR=$HOME/.nvm

USER    root

RUN     mkdir -p $HOME && \
        adduser cloudpub --home $HOME --shell /bin/bash && \
        chown -R cloudpub:cloudpub $HOME

#       Base dependencies
RUN     apt-get update
RUN     apt-get install -y sudo file curl libcap2-bin libxml2 mime-support git-core

#       Support of i686 build
RUN     dpkg --add-architecture i386 && apt-get update

#       Common dependencie
RUN     apt install -y build-essential cmake

#       Tauri dependencies
RUN     apt install -y libwebkit2gtk-4.0-dev libssl-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev

#       Install ARM and i686 toolchains
RUN     apt install -y libc6:i386 libncurses5:i386 libstdc++6:i386 gcc-i686-linux-gnu g++-i686-linux-gnu gcc-12-multilib
RUN     apt install -y gcc-arm-linux-gnueabi g++-arm-linux-gnueabi
RUN     apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

USER    cloudpub:cloudpub

RUN     curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

RUN     . "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION}
RUN     . "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION}
RUN     . "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION}

ENV     PATH="$PATH:$HOME/.cargo/bin:$HOME/.nvm/versions/node/v${NODE_VERSION}/bin"

RUN     npm install -g yarn

RUN     curl https://sh.rustup.rs -sSf | bash -s -- -y

RUN     cargo install cargo-chef

#       Install i686 and ARM toolchains
RUN     rustup target add i686-unknown-linux-musl
RUN     rustup target add arm-unknown-linux-musleabi
RUN     rustup target add armv5te-unknown-linux-musleabi
RUN     rustup target add aarch64-unknown-linux-musl

##########################################
FROM    dev AS planner
COPY    --chown=cloudpub:cloudpub . $HOME

WORKDIR $HOME
RUN     cargo chef prepare --recipe-path recipe.json

##########################################
FROM    dev AS builder
COPY    --from=planner $HOME/recipe.json $HOME/recipe.json

ENV     CARGO_TARGET_ARM_UNKNOWN_LINUX_GNUEABIHF_LINKER=/usr/bin/arm-linux-gnueabihf-gcc

WORKDIR $HOME
RUN     cargo chef cook --bin server --release --recipe-path $HOME/recipe.json

RUN     cargo chef cook --bin client --profile minimal --target x86_64-unknown-linux-gnu --recipe-path $HOME/recipe.json
RUN     cargo chef cook --bin client --profile minimal --target i686-unknown-linux-gnu --recipe-path $HOME/recipe.json
RUN     cargo chef cook --bin client --profile minimal --target arm-unknown-linux-gnueabihf --recipe-path $HOME/recipe.json

RUN     mkdir -p $HOME/backend $HOME/frontend $HOME/docs

COPY    --chown=cloudpub:cloudpub frontend/package.json $HOME/frontend/package.json
COPY    --chown=cloudpub:cloudpub frontend/yarn.lock $HOME/frontend/yarn.lock
WORKDIR $HOME/frontend
RUN     yarn install

COPY    --chown=cloudpub:cloudpub docs/package.json $HOME/docs/package.json
COPY    --chown=cloudpub:cloudpub docs/package-lock.json $HOME/docs/package-lock.json
WORKDIR $HOME/docs
RUN     npm install

COPY    --chown=cloudpub:cloudpub backend/pyproject.toml $HOME/backend/pyproject.toml
WORKDIR $HOME
RUN     python -m venv venv && \
        . venv/bin/activate && \
        cd backend && \
        pip install .

COPY    --chown=cloudpub:cloudpub . $HOME

ENV     PATH="$PATH:$HOME/bin"

RUN     clo build clients
