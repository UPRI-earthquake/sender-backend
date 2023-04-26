const request = require('supertest');
const app = require('../app');

describe("GET /deviceInfo", () => {
    it("should respond with a 200 status code", async () => {
        const response = await request(app).get("/deviceInfo");
        expect(response.statusCode).toBe(200)
    })

    it("should return device information", async () => {
        const response = await request(app).get("/deviceInfo");
        // console.log(response.body)
        expect(response.body).not.toBe(null)
        expect(response.body.network).not.toBe(null)
        expect(response.body.station).not.toBe(null)
        expect(response.body.location).not.toBe(null)
    })
})