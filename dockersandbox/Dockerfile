FROM docker/sandbox-templates:claude-code
USER root
RUN apt-get update && apt-get install -y curl ca-certificates lsb-release && \
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    az extension add --name azure-devops
USER agent
