
import Foundation
import XCTest
@testable import WalletConnect

final class ClientTests: XCTestCase {
    
    let url = URL(string: "wss://staging.walletconnect.org")!

    func makeClientDelegate(isController: Bool) -> ClientDelegate {
        let options = WalletClientOptions(apiKey: "", name: "", isController: isController, metadata: AppMetadata(name: nil, description: nil, url: nil, icons: nil), relayURL: url)
        let client = WalletConnectClient(options: options)
        return ClientDelegate(client: client)
    }
    
    func testNewPairingWithoutSession() {
        let proposerSettlesPairingExpectation = expectation(description: "Proposer settles pairing")
        let responderSettlesPairingExpectation = expectation(description: "Responder settles pairing")
        let proposer = makeClientDelegate(isController: false)
        let responder = makeClientDelegate(isController: true)
        
        let permissions = SessionType.BasePermissions(blockchain: SessionType.BlockchainTypes.Permissions(chains: [""]))
        let relay = RelayProtocolOptions(protocol: "waku", params: nil)
        let connectParams = ConnectParams(permissions: permissions, metadata: proposer.client.metadata, relay: relay, pairing: nil)
        
        let uri = proposer.client.connect(params: connectParams)!
        _ = try! responder.client.pair(uri: uri) { result in
            switch result {
            case .success(_):
                responderSettlesPairingExpectation.fulfill()
            case .failure(_):
                XCTFail()
            }
        }
        
        proposer.onPairingSettled = { pairing in
            proposerSettlesPairingExpectation.fulfill()
        }
        waitForExpectations(timeout: 2.0, handler: nil)
    }
}

class ClientDelegate: WalletConnectClientDelegate {
    var client: WalletConnectClient
    var onSessionSettled: ((SessionType.Settled)->())?
    var onPairingSettled: ((PairingType.Settled)->())?
    var onSessionProposal: ((SessionType.Proposal)->())?

    internal init(client: WalletConnectClient) {
        self.client = client
        client.delegate = self
    }

    func didReceiveSessionProposal(_ sessionProposal: SessionType.Proposal) {
        onSessionProposal?(sessionProposal)
    }
    
    func didSettleSession(_ sessionSettled: SessionType.Settled) {
        onSessionSettled?(sessionSettled)
    }
    
    func didSettlePairing(_ settledPairing: PairingType.Settled) {
        onPairingSettled?(settledPairing)
    }
    
    
}
