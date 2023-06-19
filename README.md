# UPRI-SEISMO-rShake-backend
This is the backend repository for linking the rShake device to an account.

### Installation on a [RaspberryShake Device](https://shop.raspberryshake.org/)
To install the entire sender software package, run the following command on the [RaspberryShake terminal](https://manual.raspberryshake.org/ssh.html):
```bash
bash <(curl -sSL url)
```

### Development Setup
#### Prerequisites
* node
* npm or yarn

#### Modules/Dependencies
* *getmac*          - used for getting the device's mac address.
* *express*         
* *cors*              
* *body-parser*     

#### Setting Up
1. Clone this repository.
2. Create .env from .env.example.
3. Run `npm install` or `yarn install` to install dependencies.
4. Run `npm run dev` to enable the following end-points at *port 5001*:
* */deviceInfo*         
* */deviceLinkRequest*  
* */servers*            
5. Run `npm test` to perform unit tests.
