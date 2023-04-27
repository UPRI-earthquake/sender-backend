const request = require('supertest');
const app = require('../app');

describe("POST /deviceLinkRequest", () => {
    describe("when accountName is empty", () => {
        //should respond with a status code 400
        test("should respond with a 400 status code", async () => {
            const response = await request(app).post("/deviceLinkRequest").send({
                accountName: "",
                accountPassword: "test"
            })
            expect(response.statusCode).toBe(400)
        })
    })

    describe("when accountPassword is empty", () => {
        //should respond with a status code 400
        test("should respond with a 400 status code", async () => {
            const response = await request(app).post("/deviceLinkRequest").send({
                accountName: "test",
                accountPassword: ""
            })
            expect(response.statusCode).toBe(400)
        })
    })

    describe("given an accountName and accountPassword", () => {
        //should respond with a json object
        
        //This test would only pass given the following condition:
        //1. W1_DEV_HOST (http://172.22.0.3:5000) is reachable
        //2. accountName and accountPassword fields are not empty
        //3. Device's Mac Address is acquired.
        test("should respond with a 200 status code", async () => {
            const response = await request(app).post("/deviceLinkRequest").send({
                accountName: "test",
                accountPassword: "test"
            })
            // console.log(response.text)
            expect(response.statusCode).toBe(200)
        })

        test("should specify json in the content type header", async () => {
            const response = await request(app).post("/deviceLinkRequest").send({
                accountName: "test",
                accountPassword: "test"
            })
            expect(response.headers['content-type']).toEqual(expect.stringContaining('json'))
        })
    })
})