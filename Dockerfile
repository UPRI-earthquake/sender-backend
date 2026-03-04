ARG BUNDLE_VERSION=dev
ARG BUNDLE_TAG=latest
ARG VCS_REF=unknown

# Stage 1: Build slin2kdali for node18-alpine as build env
FROM arm32v7/node:18-alpine AS build-env

RUN apk add --no-cache build-base # install build tools

WORKDIR /app

# TODO: how to import slink2dali directory?
COPY ./tests2d/ .

RUN make

# add non-js deps (for deps other than node_modules)
#RUN apk add --no-cache python3 make g++

# Stage 2: prod for nodejs, adds src code, pre-installs js deps
FROM arm32v7/node:18-alpine AS prod
ARG BUNDLE_VERSION
ARG BUNDLE_TAG
ARG VCS_REF

COPY --from=build-env /app/slink2dali /app/slink2dali

WORKDIR /app

RUN apk add --no-cache dumb-init

# install node modules
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --only=production --loglevel=verbose

# copy codebase
COPY src/ ./src/
COPY sender-backend.sh /opt/upri/scripts/payload/sender-backend
COPY bootstrap/host-scripts/sender-frontend /opt/upri/scripts/payload/sender-frontend
COPY bootstrap/sync-host-scripts.sh /opt/upri/scripts/sync-host-scripts.sh
COPY bootstrap/container-entrypoint.sh /opt/upri/scripts/container-entrypoint.sh
RUN chmod +x /opt/upri/scripts/payload/sender-backend \
    /opt/upri/scripts/payload/sender-frontend \
    /opt/upri/scripts/sync-host-scripts.sh \
    /opt/upri/scripts/container-entrypoint.sh

# define fixed environment variables
ENV SLINK2DALIPATH=/app/slink2dali
ENV SLINK2DALI_VERBOSITY=-v
ENV SLINK2DALI_VERBOSE_LOGS=false
ENV CLIENT_PROD_IP=rs.local
ENV CLIENT_PROD_PORT=3000
ENV BACKEND_PROD_IP=0.0.0.0
ENV BACKEND_PROD_PORT=5001
ENV NODE_ENV=production
ENV SENDER_IMAGE_BUNDLE_VERSION=${BUNDLE_VERSION}
ENV SENDER_BUNDLE_TAG=${BUNDLE_TAG}
ENV SENDER_SCRIPT_SYNC_MODE=fallback
ENV SENDER_SCRIPT_SYNC_TIMEOUT_SEC=20
ENV SENDER_HOST_SCRIPTS_DIR=/host-scripts

EXPOSE 5001
ENTRYPOINT ["/opt/upri/scripts/container-entrypoint.sh"]
CMD ["npm", "run", "start"]

LABEL org.opencontainers.image.source="https://github.com/UPRI-earthquake/sender-backend"
LABEL org.opencontainers.image.description="Base docker image for sender-backend"
LABEL org.opencontainers.image.authors="earthquake@science.upd.edu.ph"
LABEL org.opencontainers.image.revision="$VCS_REF"
LABEL org.upri.sender.bundle.version="$BUNDLE_VERSION"
LABEL org.upri.sender.bundle.tag="$BUNDLE_TAG"
