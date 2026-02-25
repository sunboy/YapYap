import XCTest
@testable import YapYap

final class TranscriptionExecutorTests: XCTestCase {
    func testInitialStateNotLoaded() async {
        let executor = TranscriptionExecutor()
        let isSTTLoaded = await executor.isSTTLoaded
        let isLLMLoaded = await executor.isLLMLoaded
        XCTAssertFalse(isSTTLoaded)
        XCTAssertFalse(isLLMLoaded)
    }

    func testStreamingEngineNilWhenNoSTT() async {
        let executor = TranscriptionExecutor()
        let streaming = await executor.streamingEngine
        XCTAssertNil(streaming)
    }

    func testIsStreamingFalseByDefault() async {
        let executor = TranscriptionExecutor()
        let isStreaming = await executor.isStreaming
        XCTAssertFalse(isStreaming)
    }

    func testActiveLLMModelIdNilWhenNotLoaded() async {
        let executor = TranscriptionExecutor()
        let activeId = await executor.activeLLMModelId
        XCTAssertNil(activeId)
    }

    func testSTTModelIdNilWhenNotLoaded() async {
        let executor = TranscriptionExecutor()
        let modelId = await executor.sttModelId
        XCTAssertNil(modelId)
    }

    func testLLMModelIdNilWhenNotLoaded() async {
        let executor = TranscriptionExecutor()
        let modelId = await executor.llmModelId
        XCTAssertNil(modelId)
    }
}
