
import Foundation

public class WalletConnectClient {
    
    let metadata: AppMetadata
    public weak var delegate: WalletConnectClientDelegate?
    let isController: Bool
    private let pairingEngine: PairingEngine
    private let sessionEngine: SessionEngine
    private let relay: Relay
    private let crypto = Crypto()
    
    // MARK: - Public interface
    public init(options: WalletClientOptions) {
        self.isController = options.isController
        self.metadata = options.metadata
        self.relay = Relay(transport: JSONRPCTransport(url: options.relayURL), crypto: crypto)
        let wcSubscriber = WCSubscriber(relay: relay)
        self.pairingEngine = PairingEngine(relay: relay, crypto: crypto, subscriber: wcSubscriber, isController: options.isController)
        self.sessionEngine = SessionEngine(relay: relay, crypto: crypto, subscriber: wcSubscriber)
        pairingEngine.onSessionProposal = { [unowned self] proposal in
            self.delegate?.didReceiveSessionProposal(proposal)
        }
        pairingEngine.onPairingSettled = { [unowned self] settledPairing in
            self.delegate?.didSettlePairing(settledPairing)
        }
        // TODO: Store api key
    }
    
    // for proposer to propose a session to a responder
    public func connect(params: ConnectParams) -> String? {
        Logger.debug("Connecting Application")
        if let topic = params.pairing?.topic,
           let pairing = pairingEngine.sequences.get(topic: topic ){
            Logger.debug("Connecting with existing pairing")
            createSession(pairing: pairing)
            return nil
        } else {
            let pending = pairingEngine.propose(params)
            return pending?.proposal.signal.params.uri
        }
    }
    
    // for responder to receive a session proposal from a proposer
    public func pair(uri: String, completion: @escaping (Result<String, Error>) -> Void) throws {
        print("start pair")
        guard let pairingURI = PairingType.UriParameters(uri) else {
            throw WalletConnectError.PairingParamsUriInitialization
        }
        let proposal = PairingType.Proposal.createFromURI(pairingURI)
        let approved = proposal.proposer.controller != isController
        if !approved {
            throw WalletConnectError.unauthorizedMatchingController
        }
        pairingEngine.respond(to: proposal) { result in
            switch result {
            case .success:
                print("Pairing Success")
            case .failure(let error):
                print("Pairing Failure: \(error)")
            }
            completion(result)
        }
    }
    
    // for either to disconnect a session
    public func disconnect(params: SessionType.DeleteParams) {
        sessionEngine.delete(params: params)
    }
    
    // for responder to approve a session proposal
    public func approve(proposal: SessionType.Proposal, completion: @escaping ((Result<SessionType.Settled, Error>) -> Void)) {
        sessionEngine.approve(proposal: proposal, completion: completion)
    }
    
    // for responder to reject a session proposal
    public func reject(proposal: SessionType.Proposal, reason: SessionType.Reason) {
        sessionEngine.reject(proposal: proposal, reason: reason)
    }
    
    public func getSettledSessions() -> [SessionType.Settled] {
        return sessionEngine.sequences.getSettled() as! [SessionType.Settled]
    }
    
    public func getSettledPairings() -> [PairingType.Settled] {
        pairingEngine.sequences.getSettled() as! [PairingType.Settled]
    }
    
    //MARK: - Private
    
    private func createSession(pairing: Pairing) {
        
    }
}

public protocol WalletConnectClientDelegate: AnyObject {
    func didReceiveSessionProposal(_ sessionProposal: SessionType.Proposal)
    func didSettleSession(_ sessionSettled: SessionType.Settled)
    func didSettlePairing(_ settledPairing: PairingType.Settled)
}


public struct ConnectParams {
    let permissions: SessionType.BasePermissions
    let metadata: AppMetadata?
    let relay: RelayProtocolOptions
    let pairing: ParamsPairing?
    struct ParamsPairing {
        let topic: String
    }
}
