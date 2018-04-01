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
        let headerExpectation = expectation(description: "Header callback called")
        let bodyExpectation = expectation(description: "Body callback called")
        
        let parser = HTTPResponseParser(headersReadCallback: { (statusCode: Int, headers: [String:String]) in
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(headers.count, 0)
            headerExpectation.fulfill()
        },
                                        chunkReadCallback: { (body: String) in
                                            XCTAssertEqual(body, "Hello, world!")
                                            bodyExpectation.fulfill()
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
        let headerExpectation = expectation(description: "Header callback called")
        let bodyExpectation = expectation(description: "Body callback called")
        
        let parser = HTTPResponseParser(headersReadCallback: { (statusCode: Int, headers: [String:String]) in
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(headers.count, 0)
            headerExpectation.fulfill()
        },
                                        chunkReadCallback: { (body: String) in
                                            XCTAssertEqual(body, "Hello, world!")
                                            bodyExpectation.fulfill()
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
        let headerExpectation = expectation(description: "Header callback called")
        let bodyExpectation = expectation(description: "Body callback called")
        
        let parser = HTTPResponseParser(headersReadCallback: { (statusCode: Int, headers: [String:String]) in
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(headers.count, 0)
            headerExpectation.fulfill()
        },
                                        chunkReadCallback: { (body: String) in
                                            XCTAssertEqual(body, "Hello, world!")
                                            bodyExpectation.fulfill()
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
        let headerExpectation = expectation(description: "Header callback called")
        let bodyExpectation = expectation(description: "Body callback called")
        
        let parser = HTTPResponseParser(headersReadCallback: { (statusCode: Int, headers: [String:String]) in
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(headers.count, 0)
            headerExpectation.fulfill()
        },
                                        chunkReadCallback: { (body: String) in
                                            XCTAssertEqual(body, "Hello, world!")
                                            bodyExpectation.fulfill()
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
        
        let responseString = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\nHello, world!\r\n\r\n"
        let headerExpectation = expectation(description: "Header callback called")
        let bodyExpectation = expectation(description: "Body callback called")
        
        let parser = HTTPResponseParser(headersReadCallback: { (statusCode: Int, headers: [String:String]) in
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(headers.count, 2)
            headerExpectation.fulfill()
        },
                                        chunkReadCallback: { (body: String) in
                                            XCTAssertEqual(body, "Hello, world!")
                                            bodyExpectation.fulfill()
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
        let headerExpectation = expectation(description: "Header callback called")
        let bodyExpectation = expectation(description: "Body callback called")
        
        let parser = HTTPResponseParser(headersReadCallback: { (statusCode: Int, headers: [String:String]) in
            XCTAssertEqual(statusCode, 200)
            headerExpectation.fulfill()
        },
        chunkReadCallback: { (body: String) in
            XCTAssertEqual(body, "")
            bodyExpectation.fulfill()
        })
        
        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))
        
        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }
    }
    
    func testMultipleResponses() {
        
        let responseString = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\nHello, world!\r\n\r\n"
        let headerExpectation = expectation(description: "Header callback called")
        headerExpectation.expectedFulfillmentCount = 2
        let bodyExpectation = expectation(description: "Body callback called")
        bodyExpectation.expectedFulfillmentCount = 2
        
        let parser = HTTPResponseParser(headersReadCallback: { (statusCode: Int, headers: [String:String]) in
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(headers.count, 2)
            headerExpectation.fulfill()
        },
        chunkReadCallback: { (body: String) in
            XCTAssertEqual(body, "Hello, world!")
            bodyExpectation.fulfill()
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
        let headerExpectation = expectation(description: "Header callback called")
        let bodyExpectation = expectation(description: "Body callback called")
        bodyExpectation.expectedFulfillmentCount = 2
        
        var content = ""
        
        let parser = HTTPResponseParser(headersReadCallback: { (statusCode: Int, headers: [String:String]) in
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(headers.count, 2)
            headerExpectation.fulfill()
        },
        chunkReadCallback: { (body: String) in
            content += body
            bodyExpectation.fulfill()
        })
        
        XCTAssertNoThrow(try parser.processResponseData(responseData: responseString.data(using: .utf8)!))
        
        waitForExpectations(timeout: 1) { (error) in
            if let error = error {
                XCTFail("Failed \(error)")
            }
        }
        
        XCTAssertEqual(content, "helloworld")
    }
}
