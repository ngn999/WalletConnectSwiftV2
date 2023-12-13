import Foundation
import Combine

class AuthRequestSubscriber {
    private let networkingInteractor: NetworkInteracting
    private let logger: ConsoleLogging
    private let kms: KeyManagementServiceProtocol
    private var publishers = [AnyCancellable]()
    private let walletErrorResponder: WalletErrorResponder
    private let pairingRegisterer: PairingRegisterer
    private let verifyClient: VerifyClientProtocol
    private let verifyContextStore: CodableStore<VerifyContext>

    var onRequest: (((request: AuthenticationRequest, context: VerifyContext?)) -> Void)?
    
    init(
        networkingInteractor: NetworkInteracting,
        logger: ConsoleLogging,
        kms: KeyManagementServiceProtocol,
        walletErrorResponder: WalletErrorResponder,
        pairingRegisterer: PairingRegisterer,
        verifyClient: VerifyClientProtocol,
        verifyContextStore: CodableStore<VerifyContext>
    ) {
        self.networkingInteractor = networkingInteractor
        self.logger = logger
        self.kms = kms
        self.walletErrorResponder = walletErrorResponder
        self.pairingRegisterer = pairingRegisterer
        self.verifyClient = verifyClient
        self.verifyContextStore = verifyContextStore
        subscribeForRequest()
    }
    
    private func subscribeForRequest() {
        pairingRegisterer.register(method: SessionAuthenticatedProtocolMethod())
            .sink { [unowned self] (payload: RequestSubscriptionPayload<SessionAuthenticateRequestParams>) in
                logger.debug("WalletRequestSubscriber: Received request")
                
                pairingRegisterer.setReceived(pairingTopic: payload.topic)
                
                let request = AuthenticationRequest(id: payload.id, topic: payload.topic, payload: payload.request.authPayload, requester: payload.request.requester.metadata)

                Task(priority: .high) {
                    let assertionId = payload.decryptedPayload.sha256().toHexString()
                    do {
                        let response = try await verifyClient.verifyOrigin(assertionId: assertionId)
                        let verifyContext = verifyClient.createVerifyContext(origin: response.origin, domain: payload.request.authPayload.domain, isScam: response.isScam)
                        verifyContextStore.set(verifyContext, forKey: request.id.string)
                        onRequest?((request, verifyContext))
                    } catch {
                        let verifyContext = verifyClient.createVerifyContext(origin: nil, domain: payload.request.authPayload.domain, isScam: nil)
                        verifyContextStore.set(verifyContext, forKey: request.id.string)
                        onRequest?((request, verifyContext))
                        return
                    }
                }
            }.store(in: &publishers)
    }
}
