FROM debian:trixie-slim

# Clean installation of NSD & minimun dependables & tools
RUN apt update && \
	apt install -y nsd supervisor dnsutils curl jq && \
	apt clean && \
	rm -rf /var/lib/apt/lists/*

# Create dirs
RUN mkdir -p /run/nsd /var/run/nsd /etc/nsd/zones && \
    chown -R nsd:nsd /run/nsd /var/run/nsd /etc/nsd

# Listen to DNS ports
EXPOSE 53/tcp 53/udp

# Health Check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD nsd-control status || exit 1

CMD ["nsd", "-d", "-c", "/etc/nsd/nsd.conf"]
