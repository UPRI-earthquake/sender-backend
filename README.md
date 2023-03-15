# UPRI-SEISMO-rShake-backend
This is the backend repository for the linking the rShake device to an account.

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
2. Run `npm install` or `yarn install` to install dependencies.
4. Run `npm run dev` to enable at *port 5001*, the following end-points:
* */mac*            - endpoint for getting device mac address. This will be available on *port 5001*.
* */accountsInfo*   - 
* */deviceInfo*     - 
* */servers*        - 