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
    The above command shall show the logs of all the containers (see the `docker-compose.yml` file to check the container names) spun up by `docker compose`. Wait for the `sender-backend-dev` container to log its “http://IP:PORT” before starting to code/test.
    
    Due to the local bind mount to the docker container, your changes in you the local directory should reflect to changes in the container. As such, you should be able to cycle with code-save-test without having to restart the docker containers.

    Installing npm modules should be done simply by running npm install in the local directory. This should also be reflected within the docker container due to the bind mount.
    
    See [this cheatsheet](https://upri-earthquake.github.io/docker-cheatsheet) for useful docker recipes.

## Publishing container image (For admins)
1. Build the image, and tag with the correct [semantic versioning](https://semver.org/): 
    > Note: replace X.Y.Z, and you should be at the same directory as the Dockerfile

    ```bash
    docker build -t ghcr.io/upri-earthquake/sender-frontend:X.Y.Z .
    ```
2. Push the image to ghcr.io:
    ```bash
    docker push ghcr.io/upri-earthquake/sender-frontend:X.Y.Z
    ```
    > ℹ️ Note: You need an access token to publish, install, and delete private, internal, and public packages in Github Packages. Refer to this [tutorial](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry) on how to authenticate to the container registry.

## Development Workflow: Creating New Feature
Please refer to the [contributing guide](https://upri-earthquake.github.io/dev-guide-contributing) to the entire EarthquakeHub suite.