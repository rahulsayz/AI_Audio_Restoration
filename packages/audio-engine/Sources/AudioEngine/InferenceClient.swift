import Foundation
import GRPC
import NIO

public final class InferenceClient {
    private let group: EventLoopGroup
    private let channel: ClientConnection
    private let client: SangeetV1RestorationServiceAsyncClient
    
    public init(socketPath: String) {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        // Binds standard macOS insecure UDS channels to the socket path
        let config = ClientConnection.Configuration.default(
            target: .unixDomainSocket(socketPath),
            eventLoopGroup: group
        )
        self.channel = ClientConnection(configuration: config)
        self.client = SangeetV1RestorationServiceAsyncClient(channel: channel)
    }
    
    deinit {
        try? channel.close().wait()
        try? group.syncShutdownGracefully()
    }
    
    public func getCapabilities() async throws -> SangeetV1Capabilities {
        try await client.getCapabilities(SangeetV1Empty())
    }
    
    public func listModels() async throws -> SangeetV1ModelList {
        try await client.listModels(SangeetV1Empty())
    }
    
    public func prepareModels(modelNames: [String]) -> GRPCAsyncResponseStream<SangeetV1PrepareProgress> {
        var req = SangeetV1PrepareRequest()
        req.modelNames = modelNames
        return client.prepareModels(req)
    }
    
    public func analyzeAudio(inputPath: String) async throws -> SangeetV1AnalysisResult {
        var req = SangeetV1AnalyzeRequest()
        req.inputPath = inputPath
        return try await client.analyzeAudio(req)
    }
    
    public func startRestoration(request: SangeetV1RestorationRequest) -> GRPCAsyncResponseStream<SangeetV1RestorationProgress> {
        return client.startRestoration(request)
    }
    
    public func cancelJob(jobId: String) async throws {
        var req = SangeetV1JobId()
        req.jobID = jobId
        _ = try await client.cancelJob(req)
    }
    
    public func shutdown() async throws {
        _ = try await client.shutdown(SangeetV1Empty())
    }
}
