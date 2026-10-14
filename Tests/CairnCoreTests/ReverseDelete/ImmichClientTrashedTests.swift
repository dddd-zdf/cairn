import Foundation
import Testing
@testable import CairnCore

@Suite("ImmichClient.listTrashedAssets", .serialized)
struct ImmichClientTrashedTests {

    private func makeClient() -> (client: ImmichClient, mock: MockSession) {
        let mock = MockURLProtocol.session()
        let client = ImmichClient(baseURL: URL(string: "https://photos.example.com")!, apiKey: "TEST-KEY", session: mock.session)
        return (client, mock)
    }

    private static func ok(_ req: URLRequest, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    @Test("queries timeline then archive with trashedAfter + withDeleted, never hidden")
    func requestShape() async throws {
        let (client, mock) = makeClient()
        let seenVisibilities = Ref<[String]>([])
        mock.handler = { req in
            #expect(req.url?.path == "/api/search/metadata")
            let json = try JSONSerialization.jsonObject(with: req.readBody()) as! [String: Any]
            #expect(json["withDeleted"] as? Bool == true)
            #expect((json["trashedAfter"] as? String)?.hasPrefix("2023-11-14T22:13:20") == true)
            seenVisibilities.mutate { $0.append(json["visibility"] as? String ?? "none") }
            return Self.ok(req, #"{"assets":{"items":[],"nextPage":null}}"#)
        }
        _ = try await client.listTrashedAssets(trashedAfter: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(seenVisibilities.value == ["timeline", "archive"])
    }

    @Test("pages, dedupes across visibilities, and drops non-trashed rows")
    func pagingAndFiltering() async throws {
        let (client, mock) = makeClient()
        mock.handler = { req in
            let json = try JSONSerialization.jsonObject(with: req.readBody()) as! [String: Any]
            let page = json["page"] as? Int ?? 1
            let visibility = json["visibility"] as? String
            if visibility == "timeline" && page == 1 {
                return Self.ok(req, #"{"assets":{"items":[{"id":"a","checksum":"A","isTrashed":true},{"id":"live","checksum":"L","isTrashed":false}],"nextPage":"2"}}"#)
            }
            if visibility == "timeline" {
                return Self.ok(req, #"{"assets":{"items":[{"id":"b","checksum":"B","isTrashed":true}],"nextPage":null}}"#)
            }
            return Self.ok(req, #"{"assets":{"items":[{"id":"a","checksum":"A","isTrashed":true}],"nextPage":null}}"#)
        }
        let assets = try await client.listTrashedAssets(trashedAfter: Date())
        #expect(assets.map(\.id) == ["a", "b"])
    }
}
