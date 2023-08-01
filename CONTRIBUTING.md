## Setting Up The Repository On Your Local Machine
1. Clone this repository.
    ```bash
    git clone https://github.com/UPRI-earthquake/sender-backend.git
    ```
2. Configure the sender-back-end setup by creating a file named `.env`, containing the config variables. An example is available on `.env.example`.
3. Run `npm install` or `yarn install` to install dependencies.
4. This repository uses Docker to manage containers and images. To build the docker container, run this command in the terminal:
    ```bash
    docker buildx build --platform linux/arm/v7 -t sender-backend:dev .
    ```
5. After building, you may now run the docker container:
    ```bash
    docker compose up
    ```
6. Now, you can access the web application in your browser at `http://localhost:5001`.

## Development Workflow (Creating New Feature)

### 1. Create New Branch from `dev`

To add a new feature, create new branch on your local repository. Make sure that your base branch is the `dev` branch:
```bash
git checkout -b feature/new-feature
```
Please refer to the following tags to name your commit messages and pull request titles:
1. draft - to be completed PR/commit
2. feat - new feature
3. fix - bug fixes
4. test - unit tests
5. chore - (aka housekeeping) cleaning/styling/refactor code, documentations, adding comments

### 2. Commit Changes Then Push to github repository:

Commit your changes with a descriptive commit message then push:

```bash
git add .
git commit -m "<commit-message-tag>: Short description of the change you want to commit"
git push --upstream origin feature/new-feature
```

### 3. Create a Pull Request

Navigate to UPRI-earthquake's gitHub repository and switch to the new branch. Click the "New Pull Request" button. Be sure to follow the [template for creating a pull request](pull_request_template.md) and the Pull Request Title format: `type: [TASK ID] SHORTENED TASK TITLE`

### 4. Review and Merge

Another team member will be assigned to review your pull request and to provide feedback if necessary. Once the changes you have made are approved, they will be merged into the dev branch.


## Essential Docker Commands:
1. Building a docker image:
    ```bash
    docker buildx build --platform <specified-platform> -t <image-name>:<tag> .
    ```
    - `docker buildx`: This part of the command indicates that we are using the buildx feature of Docker to build the image which is a CLI plugin that extends the capabilities of the traditional docker build command and enables multi-platform builds.
    - `build`: This is the subcommand used to initiate the image-building process.
    - `--platform <specified-platform>`: This flag specifies the target platform for which we want to build the Docker image. The <specified-platform> should be replaced with the target platform/architecture you want to build the image for. For example, it could be linux/amd64, linux/arm64, linux/arm/v7, etc. In this project, we used the linux/arm/v7 architecture to replicate the architecture used by rshake devices.
    - `-t <image-name>:<tag>`: This flag sets the image name and tag for the Docker image being built. <image-name> should be replaced with the desired name for your image, and <tag> should be replaced with the version or tag you want to assign to the image.
    - `.`: The dot . at the end of the command represents the build context. The build context is the current directory or the directory specified in the command. It contains the files and directories needed for building the Docker image. In this case, the Dockerfile should be present in the build context.
2. Running the docker container from a docker-compose file:
    ```bash
    docker compose up
    ```
3. Interacting with the docker container:
    ```bash
    docker exec -it <image-name>:<tag> /bin/sh
    ```
    - `docker exec`: This part of the command is used to execute a command inside a running Docker container.
    - `-it`: These flags make the execution interactive. -i stands for "interactive," which allows you to interact with the shell, and -t allocates a pseudo-TTY, making the shell output more readable.
    - `<container-name>`: This should be replaced with the name or ID of the Docker container where you want to execute the shell. The container must be running for this command to work.
    - `/bin/sh`: This is the command to be executed inside the container. In this case, it runs the shell /bin/sh, providing you with an interactive shell prompt inside the container.
4. Stopping a running container:
    ```bash
    docker compose down
    ```
5. Removing an image:
    ```bash
    docker rm <image-name>
    ```
6. Removing unused networks in Docker:
    ```bash
    docker network prune
    ```