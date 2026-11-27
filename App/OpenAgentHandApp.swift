import OpenAgentHandCore
import SwiftUI

@main
struct OpenAgentHandApp: App {
    var body: some Scene {
        WindowGroup("Open Agent Hand") {
            NavigationStack {
                AgentHandView()
            }
            #if os(macOS)
            .frame(minWidth: 360, minHeight: 500)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 500, height: 720)
        #endif
    }
}

private struct AgentHandView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case hello = "Hello World", feed = "Live feed"
        var id: Self { self }
    }

    enum Intent: String, CaseIterable, Identifiable {
        case inspect = "Inspect", talk = "Talk", actions = "Actions"
        var id: Self { self }
    }

    struct Selection: Identifiable {
        let agent: Agent
        let intent: Intent
        let mode: Mode
        var id: Agent { agent }
    }

    struct Exchange {
        let sent = "Hello, world!"
        var received: String?
        var reply: String?
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = Mode.hello
    @State private var intent = Intent.inspect
    @State private var selection: Selection?
    @State private var cameraEnabled = false
    @State private var cameraStatus = "Camera off"
    @State private var cameraName = ""
    @State private var lastPinch: Agent?
    @State private var showCameraPose = false
    @State private var cameraPose: HandPose?
    @State private var exchange: Exchange?
    @State private var activeAgent: Agent?
    @State private var runID = 0
    @State private var draft = ""
    @State private var talked: String?
    @State private var address = ""
    @State private var token = ""
    @State private var feed: EventFeed?
    @State private var feedID: UUID?
    @State private var feedStatus = "Disconnected"
    @State private var snapshot: AgentSnapshot?
    @State private var replayPosition: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                RobotHandView(pose: pose)
                    .frame(height: 235)
                    .frame(maxWidth: .infinity)
                    .background(.black)
                    .clipShape(.rect(cornerRadius: 18))

                if mode == .hello { helloControls } else { feedControls }
                cameraControls
            }
            .padding()
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Open Agent Hand")
        .sheet(item: $selection, content: card)
        .task(id: cameraEnabled) {
            if cameraEnabled { await runCamera() }
        }
        .task(id: feedID) {
            if let id = feedID, let feed { await readFeed(feed, id: id) }
        }
        .task(id: runID) {
            if activeAgent == .researcher { await finishExchange() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopCamera() }
        }
        .onDisappear { stopCamera() }
    }

    private var pose: HandPose {
        if showCameraPose, let cameraPose { return cameraPose }
        if mode == .feed { return snapshot?.pose(through: replayPosition ?? snapshot?.events.count ?? 0) ?? .open }
        var result = HandPose.open
        if activeAgent == .researcher { result.index = 0.85 }
        if activeAgent == .reviewer { result.ring = 0.85 }
        return result
    }

    private var helloControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(helloStatus).font(.headline).accessibilityIdentifier("hello-status")
            Button(exchange == nil ? "Run Hello World" : "Run again", systemImage: "play.fill", action: run)
                .buttonStyle(.borderedProminent)
                .disabled(activeAgent != nil)
            Picker("Pinch action", selection: $intent) {
                ForEach(Intent.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            ViewThatFits(in: .horizontal) {
                HStack { helloButtons }
                VStack(alignment: .leading) { helloButtons }
            }
        }
    }

    private var helloButtons: some View {
        ForEach([Agent.researcher, .reviewer]) { agent in
            Button("\(name(agent, in: .hello)) · \(agent.finger)") { select(agent) }
                .buttonStyle(.bordered)
        }
    }

    private var feedControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(feedStatus).font(.headline).accessibilityIdentifier("feed-status")
            if feedID == nil {
                TextField("http://127.0.0.1:8672", text: $address)
                    .accessibilityIdentifier("feed-address")
                SecureField("Session token", text: $token)
                    .accessibilityIdentifier("feed-token")
                Button("Connect", action: connect).buttonStyle(.borderedProminent)
            } else {
                Button("Disconnect") {
                    feedID = nil
                    feed = nil
                    feedStatus = snapshot == nil ? "Disconnected" : "Disconnected · last received run"
                }
            }
            if let snapshot, !snapshot.events.isEmpty {
                let count = snapshot.events.count
                Toggle("Replay", isOn: Binding(
                    get: { replayPosition != nil },
                    set: { replayPosition = $0 ? 1 : nil }
                ))
                if let position = replayPosition {
                    HStack {
                        Text("Event \(position) of \(count)")
                            .monospacedDigit()
                            .accessibilityIdentifier("replay-position")
                        Spacer()
                        Stepper("Replay event", value: Binding(
                            get: { replayPosition ?? 1 },
                            set: { replayPosition = $0 }
                        ), in: 1...count)
                        .labelsHidden()
                    }
                }
                ForEach(Agent.allCases) { agent in
                    let phase = snapshot.latest(for: agent, through: replayPosition ?? count)?.phase
                    Button("\(agent.finger) · \(name(agent, in: .feed)) · \(phase?.rawValue.capitalized ?? "Idle")") {
                        select(agent)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var cameraControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Button(cameraEnabled ? "Stop camera" : "Enable camera pinches",
                   systemImage: cameraEnabled ? "stop.fill" : "camera") {
                if cameraEnabled {
                    stopCamera()
                } else {
                    cameraStatus = "Starting camera…"
                    cameraEnabled = true
                }
            }
            .buttonStyle(.bordered)
            Text(cameraStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("camera-status")
            if cameraEnabled {
                Toggle("Mirror my hand", isOn: $showCameraPose)
                if !cameraName.isEmpty {
                    Text(cameraName).font(.footnote).foregroundStyle(.secondary)
                }
                if let lastPinch {
                    Text("Last pinch · \(lastPinch.finger)")
                        .font(.footnote)
                        .accessibilityIdentifier("last-pinch")
                }
            }
            Text(mode == .hello
                 ? "Show an open hand, then pinch thumb to index or ring. Both agents also have buttons."
                 : "Show an open hand, then pinch thumb to a fingertip to inspect that agent. Use the button for the thumb role.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var helloStatus: String {
        switch activeAgent {
        case .researcher: "Greeter sent a message"
        case .reviewer: "Receiver received the message"
        default: exchange?.reply == nil ? "Ready to run" : "Exchange complete"
        }
    }

    private func name(_ agent: Agent, in mode: Mode) -> String {
        if mode == .hello { return agent == .researcher ? "Greeter" : "Receiver" }
        return agent.rawValue.capitalized
    }

    private func select(_ agent: Agent) {
        guard selection == nil, mode == .feed || [.researcher, .reviewer].contains(agent) else { return }
        draft = ""
        talked = nil
        selection = Selection(agent: agent, intent: mode == .hello ? intent : .inspect, mode: mode)
    }

    private func card(_ choice: Selection) -> some View {
        NavigationStack {
            Form {
                switch choice.intent {
                case .inspect:
                    inspect(choice)
                case .talk:
                    TextField("Type or dictate a message", text: $draft)
                        .accessibilityIdentifier("agent-message")
                    Button("Send message") {
                        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        talked = choice.agent == .researcher ? "Hello! I heard “\(message)”." : receiverReply(to: message)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let talked { row("Reply", talked, id: "agent-talk-reply") }
                case .actions:
                    Button("Run Hello World again") {
                        selection = nil
                        run()
                    }
                    .disabled(activeAgent != nil)
                    Button("Clear exchange", role: .destructive) {
                        exchange = nil
                        selection = nil
                    }
                    .disabled(exchange == nil || activeAgent != nil)
                }
            }
            .navigationTitle("\(choice.intent.rawValue) · \(name(choice.agent, in: choice.mode))")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { selection = nil }
                        .accessibilityIdentifier("agent-done")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 395, minHeight: 265)
        #endif
    }

    @ViewBuilder private func inspect(_ choice: Selection) -> some View {
        if choice.mode == .feed {
            if let snapshot, let event = snapshot.latest(for: choice.agent, through: replayPosition ?? snapshot.events.count) {
                row("Event", event.detail, id: "agent-feed-detail")
                row("Status", event.phase.rawValue.capitalized, id: "agent-feed-phase")
            } else {
                Text("No event for this agent.")
            }
        } else if let exchange {
            if choice.agent == .researcher {
                row("Sent", exchange.sent, id: "agent-sent")
            } else {
                row("Received", exchange.received ?? "Waiting for message", id: "agent-received")
                row("Replied", exchange.reply ?? "Waiting for reply", id: "agent-replied")
            }
        } else {
            Text("Run Hello World to see an exchange.")
        }
    }

    private func row(_ title: String, _ value: String, id: String) -> some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(value))
            .accessibilityIdentifier(id)
    }

    private func run() {
        guard activeAgent == nil else { return }
        exchange = Exchange()
        activeAgent = .researcher
        runID += 1
    }

    private func finishExchange() async {
        guard let greeting = exchange?.sent else { return }
        let duration: Duration = .milliseconds(reduceMotion ? 150 : 550)
        do {
            try await Task.sleep(for: duration)
            exchange?.received = greeting
            activeAgent = .reviewer
            try await Task.sleep(for: duration)
            exchange?.reply = receiverReply(to: greeting)
            activeAgent = nil
        } catch {
            activeAgent = nil
            exchange = nil
        }
    }

    private func receiverReply(to message: String) -> String {
        message == "Hello, world!" ? "Hello back!" : "I received “\(message)”."
    }

    private func stopCamera() {
        cameraEnabled = false
        cameraPose = nil
        cameraName = ""
        lastPinch = nil
        cameraStatus = "Camera off"
    }

    private func runCamera() async {
        let capture = CameraCapture()
        defer { capture.stop() }
        do {
            let name = try await capture.start()
            try Task.checkCancellation()
            cameraName = name
            cameraStatus = "Camera on · waiting for frames"
            var recognizer = PinchRecognizer()
            for await frame in capture.frames {
                guard !Task.isCancelled else { break }
                let pose = frame.hand.flatMap(HandPose.init)
                if showCameraPose { cameraPose = pose }
                let status = frame.hand == nil ? "Camera frames live · show one hand" : "Tracking your hand"
                if cameraStatus != status { cameraStatus = status }
                if let agent = recognizer.update(frame.hand, at: frame.time) {
                    lastPinch = agent
                    select(agent)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            cameraEnabled = false
            cameraStatus = error.localizedDescription
        }
    }

    private func connect() {
        do {
            feed = try EventFeed(address: address.isEmpty ? "http://127.0.0.1:8672" : address, token: token)
            token = ""
            snapshot = nil
            replayPosition = nil
            feedStatus = "Connecting…"
            feedID = UUID()
        } catch {
            feedStatus = error.localizedDescription
        }
    }

    private func readFeed(_ feed: EventFeed, id: UUID) async {
        while !Task.isCancelled {
            do {
                let received = try await feed.snapshot()
                guard feedID == id, !Task.isCancelled else { return }
                if received.runID != snapshot?.runID {
                    replayPosition = nil
                } else if let position = replayPosition, position > received.events.count {
                    replayPosition = received.events.isEmpty ? nil : received.events.count
                }
                snapshot = received
                feedStatus = "Live feed connected"
            } catch {
                guard feedID == id, !Task.isCancelled else { return }
                feedStatus = snapshot == nil ? error.localizedDescription : "Feed unavailable · last received run"
            }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
}
