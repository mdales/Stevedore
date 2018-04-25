//
//  HTTPResponseParserTests.swift
//  StevedoreTests
//
//  Created by Michael Dales on 29/03/2018.
//  Copyright © 2018 Digital Flapjack. All rights reserved.
//

import XCTest

class HTTPResponseParserTests: XCTestCase {
    
    func testSimple1point0StatusResponse() {
        
        let responseString = "HTTP/1.0 200 OK\r\n\r\nHello, world!\r\n\r\n"
        let responseExpectation = expectation(description: "Response callback called")
        
        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            XCTAssertEqual(response.StatusCode, 200)
            XCTAssertEqual(response.Headers.count, 0)
            XCTAssertEqual(response.Body, "Hello, world!")
            responseExpectation.fulfill()
        })
        
        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))
        
        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }
        
        XCTAssertEqual(parser.count, 0)
    }

    func testSimple1point1StatusResponse() {

        let responseString = "HTTP/1.1 200 OK\r\n\r\nHello, world!\r\n\r\n"
        let responseExpectation = expectation(description: "Response callback called")

        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            XCTAssertEqual(response.StatusCode, 200)
            XCTAssertEqual(response.Headers.count, 0)
            XCTAssertEqual(response.Body, "Hello, world!")
            responseExpectation.fulfill()
        })

        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }

        XCTAssertEqual(parser.count, 0)
    }

    func testSimple2point0StatusResponse() {

        let responseString = "HTTP/2 200\r\n\r\nHello, world!\r\n\r\n"
        let responseExpectation = expectation(description: "Response callback called")
        
        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            XCTAssertEqual(response.StatusCode, 200)
            XCTAssertEqual(response.Headers.count, 0)
            XCTAssertEqual(response.Body, "Hello, world!")
            responseExpectation.fulfill()
        })

        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }

        XCTAssertEqual(parser.count, 0)
    }

    func testSimpleIncrementalResponse() {

        let responseString = "HTTP/1.1 200 OK\r\n\r\nHello, world!\r\n\r\n"
        let responseExpectation = expectation(description: "Response callback called")

        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            XCTAssertEqual(response.StatusCode, 200)
            XCTAssertEqual(response.Headers.count, 0)
            XCTAssertEqual(response.Body, "Hello, world!")
            responseExpectation.fulfill()
        })

        for char in responseString {
            let charStr = "\(char)"
            XCTAssertNoThrow(try parser.processResponseData(responseData: charStr.data(using: .utf8)!))
        }

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }

        XCTAssertEqual(parser.count, 0)
    }

    func testSimpleContentLengthParsing() {

        let responseString = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\nHello, world!"
        let responseExpectation = expectation(description: "Response callback called")
        
        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            XCTAssertEqual(response.StatusCode, 200)
            XCTAssertEqual(response.Headers.count, 2)
            XCTAssertEqual(response.Body, "Hello, world!")
            responseExpectation.fulfill()
        })


        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }

        XCTAssertEqual(parser.count, 0)
    }

    func testSimpleEmptyBody() {

        let responseString = "HTTP/1.1 200 OK\r\n\r\n\r\n\r\n"
        let responseExpectation = expectation(description: "Response callback called")
        
        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            XCTAssertEqual(response.StatusCode, 200)
            XCTAssertEqual(response.Headers.count, 0)
            XCTAssertEqual(response.Body, "")
            responseExpectation.fulfill()
        })

        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }
    }

    func testMultipleResponses() {

        let responseString = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\nHello, world!"
        let responseExpectation = expectation(description: "Response callback called")
        responseExpectation.expectedFulfillmentCount = 2
        
        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            XCTAssertEqual(response.StatusCode, 200)
            XCTAssertEqual(response.Headers.count, 2)
            XCTAssertEqual(response.Body, "Hello, world!")
            responseExpectation.fulfill()
        })

        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))
        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }
    }

    func testChunkedResponse() {
        let responseString = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n5\r\nworld\r\n0\r\n\r\n"
        let responseExpectation = expectation(description: "Response callback called")
        responseExpectation.expectedFulfillmentCount = 2

        var content = ""

        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            XCTAssertEqual(response.StatusCode, 200)
            XCTAssertEqual(response.Headers.count, 2)
            content += response.Body
            responseExpectation.fulfill()
        })

        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }

        XCTAssertEqual(content, "helloworld")
    }

    func testIncrementalChunkedResponse() {

        let responseString = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n5\r\nworld\r\n0\r\n\r\n"
        let responseExpectation = expectation(description: "Response callback called")
        responseExpectation.expectedFulfillmentCount = 2
        
        var content = ""
        
        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            XCTAssertEqual(response.StatusCode, 200)
            XCTAssertEqual(response.Headers.count, 2)
            content += response.Body
            responseExpectation.fulfill()
        })

        for char in responseString {
            let charStr = "\(char)"
            XCTAssertNoThrow(try parser.processResponseData(responseData: charStr.data(using: .utf8)!))
        }

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }

        XCTAssertEqual(content, "helloworld")

        XCTAssertEqual(parser.count, 0)
    }

    func test204NoContentResponse() {
        let responseString1 = "HTTP/1.1 204 OK\r\n\r\n"
        let responseString2 = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\nHello, world!"
        let responseExpectation = expectation(description: "Response callback called")
        responseExpectation.expectedFulfillmentCount = 2

        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            switch response.StatusCode {
            case 200:
                XCTAssertEqual(response.Body, "Hello, world!")
            case 204:
                XCTAssertEqual(response.Body, "")
            default:
                XCTAssert(false)
            }
            responseExpectation.fulfill()
        })

        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString1.data(using: .utf8)!))
        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString2.data(using: .utf8)!))

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }
    }

    func test205ResetContentResponse() {
        let responseString1 = "HTTP/1.1 205 OK\r\n\r\n"
        let responseString2 = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\nHello, world!"
        let responseExpectation = expectation(description: "Response callback called")
        responseExpectation.expectedFulfillmentCount = 2
        
        let parser = HTTPResponseParser(responseCallback: { (response: HTTPResponseParserResponse) in
            switch response.StatusCode {
            case 200:
                XCTAssertEqual(response.Body, "Hello, world!")
            case 205:
                XCTAssertEqual(response.Body, "")
            default:
                XCTAssert(false)
            }
            responseExpectation.fulfill()
        })

        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString1.data(using: .utf8)!))
        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString2.data(using: .utf8)!))

        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }
    }
}
