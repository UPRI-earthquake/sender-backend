# Sender-backend
Sender-backend program is the server-side component of the sender web application running on the Raspberry Shake device. For more details, you may refer to the [repository overview and API](https://upri-earthquake.github.io).  

## Installation on a [RaspberryShake Device](https://shop.raspberryshake.org/)
To install the entire sender software package, run the following command on the [RaspberryShake terminal](https://manual.raspberryshake.org/ssh.html):
```bash
bash <(curl "https://raw.githubusercontent.com/UPRI-earthquake/sender-backend/main/install.sh")
```

## Development Setup
To run this repository on your local machine, please follow the instructions provided under the [Setting Up The Repository On Your Local Machine](CONTRIBUTING.md#setting-up-the-repository-on-your-local-machine) section of the [contributing.md](CONTRIBUTING.md).

### Local dev stack (backend + frontend + commons)
The repo root has `docker-compose.dev.yml` that spins up the sender backend and frontend, wired to talk to a locally deployed EarthquakeHub “commons” stack (which provides the W1 backend and MongoDB).

1. Make sure the commons stack is running from `earthquake-hub-deployment/earthquake-hub-commons` (so that `ehub-backend` and `mongodb` are available on the `earthquake-hub-network`).
2. Prepare env files:
   ```bash
   # sender-backend app env (used when running backend directly or via per-repo compose)
   cp sender-backend/.env.example sender-backend/.env

   # docker-compose.dev env (used by services in docker-compose.dev.yml)
   cp .env.example .env
   # edit .env as needed; by default W1_DEV_IP=ehub-backend and W1_DEV_PORT=5000
   ```
3. From the repo root, run:
   ```bash
   docker compose --env-file .env -f docker-compose.dev.yml up --build
   ```
   Backend: `http://localhost:5001`, Frontend: `http://localhost:3000`, commons via nginx: `https://ehub.local`.
4. To sanity-check the backend once containers are up:
   ```bash
   curl http://localhost:5001/health/time
   curl http://localhost:5001/device/info
   ```

If you prefer running the backend directly on your host instead of inside Docker, set `SLINK2DALIPATH` to a locally built binary (e.g., `./tests2d/slink2dali` after `make`) and `LOCALDBS_DIRECTORY` to a writable path such as `./localDBs`.
