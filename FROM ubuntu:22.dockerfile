FROM ubuntu:22.04

# Уникаємо інтерактивних запитів під час встановлення
ENV DEBIAN_FRONTEND=noninteractive

# Встановлення базових пакетів
RUN apt-get update && apt-get install -y \
    git \
    curl \
    zsh \
    vim \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    libpq-dev \
    postgresql-client \
    redis-tools \
    sudo \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    wget \
    jq \
    iputils-ping \
    net-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Встановлення Docker CLI
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Встановлення kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Налаштування користувача vscode
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Встановлення Oh My Zsh для користувача vscode
USER $USERNAME
RUN sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    && echo "export PATH=\$PATH:\$HOME/.local/bin" >> ~/.zshrc

# Python залежності
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --upgrade pip \
    && pip3 install -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# Робоча директорія
WORKDIR /workspace

# Скрипт для перевірки підключень
COPY .devcontainer/check_connections.sh /usr/local/bin/check_connections
RUN sudo chmod +x /usr/local/bin/check_connections

USER $USERNAME
ENV PATH="/home/$USERNAME/.local/bin:${PATH}"

CMD ["sleep", "infinity"]
