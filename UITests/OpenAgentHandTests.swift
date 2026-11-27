import XCTest

final class OpenAgentHandTests: XCTestCase {
    @MainActor
    func testOfflineInspectTalkAndActions() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Run Hello World"].tap()
        let status = app.staticTexts["hello-status"]
        expectValue("Exchange complete", asLabelOf: status)
        let receiver = app.buttons["Receiver · Ring"]
        receiver.tap()
        let received = app.descendants(matching: .any)["agent-received"]
        XCTAssertTrue(received.waitForExistence(timeout: 5))
        XCTAssertEqual(received.value as? String, "Hello, world!")
        XCTAssertEqual(app.descendants(matching: .any)["agent-replied"].value as? String, "Hello back!")
        attach("Receiver evidence")
        app.buttons["agent-done"].tap()

        app.buttons["Talk"].tap()
        receiver.tap()
        let input = app.textFields["agent-message"]
        input.tap()
        input.typeText("Hi")
        app.buttons["Send message"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["agent-talk-reply"].value as? String, "I received “Hi”.")
        app.buttons["agent-done"].tap()

        app.buttons["Actions"].tap()
        receiver.tap()
        app.buttons["Run Hello World again"].tap()
        expectValue("Exchange complete", asLabelOf: status)
        receiver.tap()
        app.buttons["Clear exchange"].tap()
        expectValue("Ready to run", asLabelOf: status)
    }

    @MainActor
    func testTwoProducersReachTheSameHand() throws {
        let env = ProcessInfo.processInfo.environment
        guard let port = env["OPEN_AGENT_HAND_PORT"], let token = env["OPEN_AGENT_HAND_TOKEN"] else {
            throw XCTSkip("Launch the bridge and pass the test runner a session port and token.")
        }
        let app = XCUIApplication()
        app.launch()
        app.buttons["Live feed"].tap()
        let address = app.textFields["feed-address"]
        address.tap()
        address.typeText("http://127.0.0.1:\(port)")
        let secret = app.secureTextFields["feed-token"]
        secret.tap()
        secret.typeText(token)
        app.buttons["Connect"].tap()
        expectValue("Live feed connected", asLabelOf: app.staticTexts["feed-status"])
        let reviewer = app.buttons["Ring · Reviewer · Done"]
        XCTAssertTrue(reviewer.waitForExistence(timeout: 90))
        reviewer.tap()
        XCTAssertEqual(app.descendants(matching: .any)["agent-feed-detail"].value as? String,
                       "Interpreter echoed the scout’s signal")
        app.buttons["agent-done"].tap()
        let builder = app.buttons["Middle · Builder · Done"]
        XCTAssertTrue(builder.waitForExistence(timeout: 15))
        builder.tap()
        XCTAssertEqual(app.descendants(matching: .any)["agent-feed-detail"].value as? String,
                       "Threadmark returned public GitHub stars")
        attach("Threadmark evidence")
        app.buttons["agent-done"].tap()
        if !app.switches["Replay"].isHittable { app.swipeUp() }
        app.switches["Replay"].tap()
        let position = app.staticTexts["replay-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        XCTAssertTrue(position.label.hasPrefix("Event 1 of "))
    }

    @MainActor
    private func expectValue(_ label: String, asLabelOf element: XCUIElement) {
        let predicate = NSPredicate(format: "label == %@", label)
        wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 12)
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
