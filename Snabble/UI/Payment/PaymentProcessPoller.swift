//
//  PaymentProcessPoller.swift
//
//  Copyright © 2019 snabble. All rights reserved.
//

import Foundation

enum PaymentEvent {
    case approval
    case paymentSuccess

    case receipt

    var abortOnFailure: Bool {
        switch self {
        case .approval: return true
        case .paymentSuccess: return true
        case .receipt: return false
        }
    }
}

final class PaymentProcessPoller {
    private var timer: Timer?

    private let process: CheckoutProcess
    private let project: Project
    private let shop: Shop

    private var task: URLSessionDataTask?
    private var completion: ((Bool) -> ())?

    private var waitingFor = [PaymentEvent]()
    private var alreadySeen = [PaymentEvent]()

    init(_ process: CheckoutProcess, _ project: Project, _ shop: Shop) {
        self.process = process
        self.project = project
        self.shop = shop
    }

    deinit {
        self.stop()
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil

        self.task?.cancel()
        self.task = nil

        self.completion = nil
    }

    // wait for a number of events, and call the completion handler as soon as one (or more) are fulfilled
    func waitFor(_ events: [PaymentEvent], completion: @escaping ([PaymentEvent: Bool]) -> () ) {
        self.waitingFor = events
        self.alreadySeen = []
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            self.checkEvents(events, completion)
        }
    }

    private func checkEvents(_ events: [PaymentEvent], _ completion: @escaping ([PaymentEvent: Bool]) -> () ) {
        self.process.update(self.project, taskCreated: { self.task = $0 }) { result in
            guard case Result.success(let process) = result else {
                return
            }

            var seenNow = [PaymentEvent: Bool]()
            var abort = false
            for event in self.waitingFor {
                if self.alreadySeen.contains(event) {
                    continue
                }

                var result: (event: PaymentEvent, ok: Bool)? = nil
                switch event {
                case .approval: result = self.checkApproval(process)
                case .paymentSuccess: result = self.checkPayment(process)
                case .receipt: result = self.checkReceipt(process)
                }

                if let result = result {
                    seenNow[result.event] = result.ok
                    self.alreadySeen.append(result.event)
                    if result.event.abortOnFailure {
                        abort = abort || !result.ok
                    }
                }
            }

            if seenNow.count > 0 {
                completion(seenNow)
            }

            if abort || self.alreadySeen.count == self.waitingFor.count {
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }

    private func checkApproval(_ process: CheckoutProcess) -> (PaymentEvent, Bool)? {
        // print("approval: \(process.paymentApproval) \(process.supervisorApproval)")
        switch (process.paymentApproval, process.supervisorApproval) {
        case (.none, .none):
            return nil
        case (.some(let paymentApproval), .none):
            return paymentApproval ? nil : (.approval, false)
        case (.none, .some(let supervisorApproval)):
            return supervisorApproval ? nil : (.approval, false)
        case (.some(let paymentApproval), .some(let supervisorApproval)):
            return (.approval, paymentApproval && supervisorApproval)
        }
    }

    private func checkPayment(_ process: CheckoutProcess) -> (PaymentEvent, Bool)? {
        // print("paymentState: \(process.paymentState)")
        let skipStates = [PaymentState.pending, .processing ]
        if skipStates.contains(process.paymentState) {
            return nil
        }

        return (.paymentSuccess, process.paymentState == .successful)
    }

    private func checkReceipt(_ process: CheckoutProcess) -> (PaymentEvent, Bool)? {
        guard process.links.receipt != nil else {
            return nil
        }

        return (.receipt, true)
    }

}
