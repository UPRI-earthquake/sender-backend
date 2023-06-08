# Stage 1: Build slin2kdali for node18-alpine as build env
FROM arm64v8/node:18-alpine as build-env

RUN apk add --no-cache build-base # install build tools

WORKDIR /app

# TODO: how to import slink2dali directory?
COPY ./tests2d/ .

RUN make

# add non-js deps (for deps other than node_modules)
#RUN apk add --no-cache python3 make g++

# Stage 2: prod for nodejs, adds src code, pre-installs js deps
FROM arm64v8/node:18-alpine as prod

COPY --from=build-env /app/slink2dali /app/slink2dali

WORKDIR /app

RUN apk add dumb-init

# install node modules
ENV NODE_ENV production
COPY --chown=node:node package*.json ./
RUN npm ci --only=production --loglevel=verbose

# copy codebase
# TODO: copy src code only
COPY --chown=node:node . ./

EXPOSE 5001
USER node
CMD ["dumb-init", "npm", "run", "start"]

LABEL org.opencontainers.image.source="https://github.com/UPRI-earthquake/sender-backend"
LABEL org.opencontainers.image.description="Base docker image for sender-backend"
LABEL org.opencontainers.image.authors="earthquake@science.upd.edu.ph"
