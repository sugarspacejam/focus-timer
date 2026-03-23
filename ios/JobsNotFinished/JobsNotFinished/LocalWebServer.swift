import Foundation
import Network

final class LocalWebServer: ObservableObject {
    static let shared = LocalWebServer()

    @Published private(set) var url: URL?
    @Published private(set) var errorMessage: String?

    private var listener: NWListener?
    private var started = false
    private let listenerQueue = DispatchQueue(label: "LocalWebServer.listener")
    private let connectionQueue = DispatchQueue(label: "LocalWebServer.connection")

    private init() {}

    func startIfNeeded() {
        if started {
            return
        }
        started = true

        do {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        Task { @MainActor in
                            self.errorMessage = "Local server port is missing"
                        }
                        return
                    }
                    let portValue = Int(port.rawValue)
                    guard let url = URL(string: "http://127.0.0.1:\(portValue)/index.html") else {
                        Task { @MainActor in
                            self.errorMessage = "Failed to build app URL"
                        }
                        return
                    }
                    Task { @MainActor in
                        self.url = url
                    }

                case .failed(let error):
                    Task { @MainActor in
                        self.errorMessage = "Local web server failed: \(error)"
                    }

                default:
                    break
                }
            }

            listener.start(queue: listenerQueue)
        } catch {
            Task { @MainActor in
                self.errorMessage = "Failed to start local web server: \(error)"
            }
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: connectionQueue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.sendResponse(connection: connection, status: 500, contentType: "text/plain", body: Data("Server error: \(error)".utf8))
                return
            }

            guard let data else {
                self.sendResponse(connection: connection, status: 400, contentType: "text/plain", body: Data("Bad request".utf8))
                return
            }

            guard let requestText = String(data: data, encoding: .utf8) else {
                self.sendResponse(connection: connection, status: 400, contentType: "text/plain", body: Data("Invalid request encoding".utf8))
                return
            }

            guard let firstLine = requestText.split(separator: "\n", omittingEmptySubsequences: true).first else {
                self.sendResponse(connection: connection, status: 400, contentType: "text/plain", body: Data("Missing request line".utf8))
                return
            }

            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                self.sendResponse(connection: connection, status: 400, contentType: "text/plain", body: Data("Malformed request line".utf8))
                return
            }

            let method = String(parts[0])
            if method != "GET" && method != "HEAD" {
                self.sendResponse(connection: connection, status: 405, contentType: "text/plain", body: Data("Method not allowed".utf8))
                return
            }

            let rawPath = String(parts[1])
            let path = rawPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rawPath

            let resolvedPath = self.sanitize(path: path)
            guard let fileURL = self.fileURL(for: resolvedPath) else {
                self.sendResponse(connection: connection, status: 404, contentType: "text/plain", body: Data("Not found".utf8))
                return
            }

            do {
                let fileData = try Data(contentsOf: fileURL)
                let contentType = self.contentType(for: fileURL)
                if method == "HEAD" {
                    self.sendResponse(connection: connection, status: 200, contentType: contentType, body: Data())
                } else {
                    self.sendResponse(connection: connection, status: 200, contentType: contentType, body: fileData)
                }
            } catch {
                self.sendResponse(connection: connection, status: 500, contentType: "text/plain", body: Data("Failed to read file".utf8))
            }
        }
    }

    private func sanitize(path: String) -> String {
        if path == "/" {
            return "/index.html"
        }
        if !path.hasPrefix("/") {
            return "/" + path
        }
        return path
    }

    private func fileURL(for path: String) -> URL? {
        guard let assetsURL = Bundle.main.resourceURL?.appendingPathComponent("WebAssets", isDirectory: true) else {
            return nil
        }

        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fileURL = assetsURL.appendingPathComponent(clean)

        let standardizedAssets = assetsURL.standardizedFileURL.path
        let standardizedTarget = fileURL.standardizedFileURL.path
        if !standardizedTarget.hasPrefix(standardizedAssets) {
            return nil
        }

        return fileURL
    }

    private func contentType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "html":
            return "text/html; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "js":
            return "application/javascript; charset=utf-8"
        case "json":
            return "application/json; charset=utf-8"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "svg":
            return "image/svg+xml"
        case "wasm":
            return "application/wasm"
        default:
            return "application/octet-stream"
        }
    }

    private func sendResponse(connection: NWConnection, status: Int, contentType: String, body: Data) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Server Error"
        }

        var headers = "HTTP/1.1 \(status) \(statusText)\r\n"
        headers += "Connection: close\r\n"
        headers += "Content-Type: \(contentType)\r\n"
        headers += "Content-Length: \(body.count)\r\n"
        headers += "Access-Control-Allow-Origin: *\r\n"
        headers += "\r\n"

        var response = Data(headers.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
