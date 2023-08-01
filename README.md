# UPRI-SEISMO-rShake-backend
This is the backend repository for linking the rShake device to an account in the earthquake-hub citizen science network. This repository is relying on [earthquake-hub-backend](https://github.com/UPRI-earthquake/earthquake-hub-backend)--for authenticating a user, issuing `accessToken` to authenticated user, returning device information saved on the central database, and [slink2dali](https://github.com/UPRI-earthquake/sender-slink2dali)--for forwarding miniseed data using the data link protocol.

## Installation on a [RaspberryShake Device](https://shop.raspberryshake.org/)
To install the entire sender software package, run the following command on the [RaspberryShake terminal](https://manual.raspberryshake.org/ssh.html):
```bash
bash <(curl -sSL url)
```

## Development Setup
To run this repository on your local machine, please follow the instructions provided under the [Setting Up The Repository On Your Local Machine](CONTRIBUTING.md#setting-up-the-repository-on-your-local-machine) section of the [contributing.md](CONTRIBUTING.md).

## Technologies and Tools
This repository leverages several cutting-edge technologies and tools to provide a robust and user-friendly experience for developers and end-users alike:

- Git and GitHub: We use Git for version control and GitHub for collaborative development, making it easy for contributors to fork, make changes, and submit pull requests.

- Docker Images and Containers: Docker allows us to package the application and its dependencies into lightweight containers, ensuring consistent behavior across various environments.

## Docker Usage
This repository uses Docker to provide a consistent and portable development environment. Docker images and containers enable developers to work seamlessly across different platforms. Some essential docker commands used in this repository which will help to get started are recorded under the [Essential Docker Commands](CONTRIBUTING.md#essential-docker-commands) section of the [contributing.md](CONTRIBUTING.md).