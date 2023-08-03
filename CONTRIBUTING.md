## Setting Up The Repository On Your Local Machine
Sender-backend repository uses Docker to provide a consistent and portable development environment. Docker images and containers enable developers to work seamlessly across different platforms. Some essential docker commands used in this repository which will help you to get started are recorded under this [docker cheatsheat]().
1. Clone this repository.
    ```bash
    git clone https://github.com/UPRI-earthquake/sender-backend.git
    ```
2. Configure the sender-back-end setup by creating a file named `.env`, containing the config variables. An example is available on `.env.example`.
3. Run `npm install` or `yarn install` to install dependencies.
4. This repository docker image is built using linux/arm/v7 platform to replicate the architecture used inside the rshake. To build the docker image, run this command in the terminal:
    ```bash
    docker buildx build --platform linux/arm/v7 -t sender-backend:dev .
    ```
    You can create a multi-platform docker builder by following this [tutorial](https://docs.docker.com/build/building/multi-platform/#getting-started).
5. After building, you may now create and start a docker container from the image via:
    ```bash
    docker compose up
    ```
6. You may access the web application in your browser at `http://localhost:5001`. Editing the codebase at this point should result to an automatic restart of the node process. This is done via nodemon (See package.json `start:dev` script).

## Development Workflow: Creating New Feature
Please refer to the [contributing guide](https://upri-earthquake.github.io/dev-guide-contributing) to the entire EarthquakeHub suite.