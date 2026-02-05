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

COPY --from=build-env /app/slink2dali /app/slink2dali

WORKDIR /app

RUN apk add dumb-init

# install node modules
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --only=production --loglevel=verbose

# copy codebase
COPY src/ ./src/

# define fixed environment variables
ENV SLINK2DALIPATH=/app/slink2dali
ENV SLINK2DALI_VERBOSITY=-v
ENV SLINK2DALI_VERBOSE_LOGS=false
ENV CLIENT_PROD_IP=rs.local
ENV CLIENT_PROD_PORT=3000
ENV BACKEND_PROD_IP=0.0.0.0
ENV BACKEND_PROD_PORT=5001
ENV NODE_ENV=production

EXPOSE 5001
CMD ["dumb-init", "npm", "run", "start"]

LABEL org.opencontainers.image.source="https://github.com/UPRI-earthquake/sender-backend"
LABEL org.opencontainers.image.description="Base docker image for sender-backend"
LABEL org.opencontainers.image.authors="earthquake@science.upd.edu.ph"
