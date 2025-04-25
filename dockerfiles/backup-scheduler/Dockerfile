ARG AWS_CLI_VERSION=2.17.11
FROM amazon/aws-cli:${AWS_CLI_VERSION}

# Install necessary packages for cron and PostgreSQL client
# Using yum as the base image is Amazon Linux 2 based
RUN yum update -y && \
    yum install -y cronie postgresql15 tar gzip jq && \
    yum clean all && \
    rm -rf /var/cache/yum

# Copy the entrypoint script into the container
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"] 