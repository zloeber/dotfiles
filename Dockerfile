FROM alpine:latest AS setup

# Let scripts know we're running in Docker (useful for containerised development)
ENV RUNNING_IN_DOCKER true

# Use the unprivileged `main` user (created without a password ith `-D`) for safety
RUN adduser -D main

# Set up ZSH and our preferred terminal environment for containers
RUN mkdir -p /home/main/dotfiles && \
    apk --no-cache add zsh curl git make automake autoconf unzip tmux bash
COPY . /home/main/dotfiles

RUN chown -R main:main /home/main

# Set up ZSH as the unprivileged user (we just need to start it, it'll initialise our setup itself)
USER main

RUN cd /home/main/dotfiles && ls -al && ./bootstrap-docker.sh
