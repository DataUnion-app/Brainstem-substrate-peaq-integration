import SubstrateSdk
import IrohaCrypto
import RobinHood
import BigInt

extension MainViewController {
    func connectPeaqNetwork(accountAddress: String) {
        // display account balance
        do {
            self.accountInfo = try getAccountBalance(accountAddress: accountAddress)
            if (self.accountInfo != nil) {
                let available = self.accountInfo.map {
                    Decimal.fromSubstrateAmount(
                        $0.data.available,
                        precision: liveOrTest ? Int16(assetModelPeaqLive!.precision) : Int16(assetModelPeaqTest!.precision)
                    ) ?? 0.0
                } ?? 0.0

                resultLabel.text = "Balance: \(available.stringWithPointSeparator) \(liveOrTest ? assetModelPeaqLive!.symbol : assetModelPeaqTest!.symbol)"
            } else {
                errorLabel.text = "Unexpected Error"
            }
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }
}
