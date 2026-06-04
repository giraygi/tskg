# =============================================================================
# Dockerfile
#
# Base:  adfreiburg/qlever  (Ubuntu, QLever C++ binaries pre-compiled)
# Adds:  Python 3 · rdflib · qlever CLI · Java 21 · ROBOT · Apache Jena (RIOT)
#
# The same image is used for both services in docker-compose:
#   ontology-prep  →  runs prep.sh     (download, convert, merge → .nq)
#   qlever         →  runs entrypoint.sh (index, start SPARQL server)
#
# Build args:
#   JENA_VERSION   Apache Jena release  (default: 6.0.0)
#   ROBOT_VERSION  ROBOT jar release    (default: 1.9.10)
#
# Files expected in the build context:
#   Qleverfile              (USE_DOCKER = false required)
#   entrypoint.sh
#   prep.sh
#   merge_versions.sh
#   matomo_ontology_stats.py
#   download_ontologies.py
#   ontologies.json
# =============================================================================

FROM adfreiburg/qlever:latest

# The adfreiburg/qlever image runs as a non-root "qlever" user by default.
# All installation steps require root.
USER root

ARG JENA_VERSION=6.0.0
ARG ROBOT_VERSION=1.9.10

# -----------------------------------------------------------------------------
# System packages
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        openjdk-21-jre-headless \
        curl \
        wget \
        bash \
        less \
        procps \
    && rm -rf /var/lib/apt/lists/*

RUN java -version

# -----------------------------------------------------------------------------
# Python packages
# -----------------------------------------------------------------------------
RUN pip3 install --no-cache-dir --break-system-packages \
        rdflib \
        qlever \
        requests

# -----------------------------------------------------------------------------
# ROBOT
# -----------------------------------------------------------------------------
RUN mkdir -p /opt/robot \
    && curl -fsSL \
       "https://github.com/ontodev/robot/releases/download/v${ROBOT_VERSION}/robot.jar" \
       -o /opt/robot/robot.jar

RUN printf '#!/bin/sh\nexec java ${ROBOT_JAVA_ARGS:--Xmx8g} -jar /opt/robot/robot.jar "$@"\n' \
    > /usr/local/bin/robot \
    && chmod +x /usr/local/bin/robot

RUN robot --version

# -----------------------------------------------------------------------------
# Apache Jena (RIOT + arq + other CLI tools)
# -----------------------------------------------------------------------------
RUN wget -qO /tmp/apache-jena.tar.gz \
       "https://archive.apache.org/dist/jena/binaries/apache-jena-${JENA_VERSION}.tar.gz" \
    && tar -xzf /tmp/apache-jena.tar.gz -C /opt \
    && mv "/opt/apache-jena-${JENA_VERSION}" /opt/jena \
    && rm /tmp/apache-jena.tar.gz

ENV PATH="/opt/jena/bin:${PATH}"
ENV JENA_HOME="/opt/jena"

RUN riot --version

# -----------------------------------------------------------------------------
# Qleverfile — stored outside /data so the ./data:/data bind mount in
# docker-compose cannot shadow it at runtime.
# -----------------------------------------------------------------------------
RUN mkdir -p /etc/qlever
COPY Qleverfile /etc/qlever/Qleverfile

# -----------------------------------------------------------------------------
# Ontology preparation scripts
# -----------------------------------------------------------------------------
RUN mkdir -p /app
COPY merge_versions.sh        /usr/local/bin/merge_versions.sh
COPY matomo_ontology_stats.py /app/matomo_ontology_stats.py
COPY download_ontologies.py   /app/download_ontologies.py
COPY ontologies.json          /app/ontologies.json
RUN chmod +x /usr/local/bin/merge_versions.sh

# -----------------------------------------------------------------------------
# Pipeline scripts
# -----------------------------------------------------------------------------
COPY prep.sh       /prep.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /prep.sh /entrypoint.sh

WORKDIR /data
VOLUME ["/data"]
EXPOSE 7001

# Default entrypoint for the qlever service.
# The ontology-prep service overrides this with `command: /prep.sh`.
ENTRYPOINT ["/entrypoint.sh"]
