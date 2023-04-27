const request = require('supertest');
const app = require('../app');

describe("GET /servers", () => {
    it("should respond with a 200 status code", async () => {
        const response = await request(app).get("/servers");
        expect(response.statusCode).toBe(200)
    })

    it("should return servers information and connection status", async () => {
        const response = await request(app).get("/servers");
        // console.log(response.body)
        expect(response.body.servers.length >= 1).toBe(true)
    })
})