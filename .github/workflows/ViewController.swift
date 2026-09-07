import UIKit
import CoreBluetooth
import CommonCrypto

class ViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {

    // 白云通门禁的主服务 UUID
    private let targetServiceUUID = CBUUID(string: "14839ac4-7d7e-415c-9a42-167340cf2339")

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var readCharacteristic: CBCharacteristic?
    private var writeCharacteristic: CBCharacteristic?

    // UI 控件
    private let macTextField = UITextField()
    private let keyTextField = UITextField()
    private let saveButton = UIButton(type: .system)
    private let unlockButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSavedConfig()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - UI 布局
    private func setupUI() {
        view.backgroundColor = UIColor.systemGroupedBackground
        title = "白云通离线门禁"

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.trailingAnchor, constant: -view.frame.width + 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20)
        ])

        // MAC 输入框
        macTextField.placeholder = "门禁 MAC (如 AA:BB:CC:DD:EE:FF)"
        macTextField.borderStyle = .roundedRect
        macTextField.autocapitalizationType = .allCharacters
        stack.addArrangedSubview(macTextField)

        // Key 输入框
        keyTextField.placeholder = "门禁 Key (32位十六进制字符串)"
        keyTextField.borderStyle = .roundedRect
        keyTextField.autocapitalizationType = .allCharacters
        stack.addArrangedSubview(keyTextField)

        // 保存按钮
        saveButton.setTitle("保存门禁配置", for: .normal)
        saveButton.backgroundColor = .systemBlue
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.layer.cornerRadius = 8
        saveButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        saveButton.addTarget(self, action: #selector(saveConfigAction), for: .touchUpInside)
        stack.addArrangedSubview(saveButton)

        // 开门大按钮
        unlockButton.setTitle("🚪 离线一键开门", for: .normal)
        unlockButton.titleLabel?.font = .boldSystemFont(ofSize: 22)
        unlockButton.backgroundColor = .systemGreen
        unlockButton.setTitleColor(.white, for: .normal)
        unlockButton.layer.cornerRadius = 16
        unlockButton.heightAnchor.constraint(equalToConstant: 80).isActive = true
        unlockButton.addTarget(self, action: #selector(startUnlockAction), for: .touchUpInside)
        stack.addArrangedSubview(unlockButton)

        // 状态日志
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.text = "准备就绪"
        statusLabel.textAlignment = .center
        stack.addArrangedSubview(statusLabel)
    }

    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = message
            print("[门禁] \(message)")
        }
    }

    private func loadSavedConfig() {
        macTextField.text = UserDefaults.standard.string(forKey: "by_mac")
        keyTextField.text = UserDefaults.standard.string(forKey: "by_key")
    }

    @objc private func saveConfigAction() {
        view.endEditing(true)
        guard let mac = macTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !mac.isEmpty,
              let key = keyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            log("❌ 请先完整填写 MAC 和 Key")
            return
        }
        UserDefaults.standard.set(mac, forKey: "by_mac")
        UserDefaults.standard.set(key, forKey: "by_key")
        log("✅ 配置已保存到本机！")
    }

    // MARK: - 触发开门流程
    @objc private func startUnlockAction() {
        view.endEditing(true)
        guard let mac = UserDefaults.standard.string(forKey: "by_mac"), !mac.isEmpty,
              let key = UserDefaults.standard.string(forKey: "by_key"), !key.isEmpty else {
            log("❌ 请先填写并保存 MAC 和 Key！")
            return
        }

        guard centralManager.state == .poweredOn else {
            log("❌ 蓝牙未开启，请在系统设置中打开蓝牙")
            return
        }

        log("🔍 正在扫描白云通门禁...")
        readCharacteristic = nil
        writeCharacteristic = nil
        centralManager.scanForPeripherals(withServices: [targetServiceUUID], options: nil)
    }

    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            log("蓝牙状态异常: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log("📡 发现设备: \(peripheral.name ?? "未知") [RSSI: \(RSSI)]")
        self.peripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("🔗 蓝牙已连接，寻找主服务...")
        peripheral.delegate = self
        peripheral.discoverServices([targetServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("❌ 连接门禁失败: \(error?.localizedDescription ?? "")")
    }

    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == targetServiceUUID {
            log("⚙️ 获取特征值列表...")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for c in characteristics {
            if c.properties.contains(.read) {
                readCharacteristic = c
            }
            if c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = c
            }
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: c)
            }
        }

        if let readChar = readCharacteristic {
            log("📥 正在读取门禁随机挑战码...")
            peripheral.readValue(for: readChar)
        } else {
            log("❌ 未找到可读特征码")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        log("🔑 获得门禁挑战码 [\(data.count)字节]，计算开门指令...")

        guard let macStr = UserDefaults.standard.string(forKey: "by_mac"),
              let keyStr = UserDefaults.standard.string(forKey: "by_key") else { return }

        // 调用逆向还原的 DES 加密拼包算法
        if let packet = buildUnlockPacket(macStr: macStr, keyStr: keyStr, challenge: data),
           let writeChar = writeCharacteristic {
            log("📤 发送指令: \(packet.map { String(format: "%02X", $0) }.joined())")
            let writeType: CBCharacteristicWriteType = writeChar.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(packet, for: writeChar, type: writeType)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("❌ 指令写入失败: \(error.localizedDescription)")
        } else {
            log("🎉 开门成功！门锁已开启")
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    // MARK: - 核心算法（完全还原白云通逆向逻辑）
    private func buildUnlockPacket(macStr: String, keyStr: String, challenge: Data) -> Data? {
        let cleanMac = macStr.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard let macBytes = cleanMac.hexData, macBytes.count >= 6 else { return nil }
        guard let keyBytes = keyStr.hexData, keyBytes.count >= 8 else { return nil }

        // 1. 计算 Sum (Challenge 所有字节累加 + Key 所有字节累加)
        var sum: Int = 0
        for b in challenge { sum += Int(b) }
        for b in keyBytes { sum += Int(b) }

        // 2. 构造 DES 待加密明文: [Sum低8位, Sum高8位, Challenge字节..., 补0至8的倍数]
        var plain = [UInt8]()
        plain.append(UInt8(sum & 0xFF))
        plain.append(UInt8((sum >> 8) & 0xFF))
        plain.append(contentsOf: challenge)
        while plain.count % 8 != 0 {
            plain.append(0x00)
        }

        // 3. 执行 DES/ECB/NoPadding 加密 (Key 截取前 8 字节)
        guard let cipherData = desEncrypt(data: Data(plain), key: keyBytes.prefix(8)) else { return nil }

        // 4. 组装 20 字节开门指令包
        var packet = [UInt8](repeating: 0, count: 20)
        packet[0] = 0xA5
        packet[1] = 0x14  // 包长 20
        packet[2] = 0x05
        packet[3] = macBytes[2]
        packet[4] = macBytes[3]
        packet[5] = macBytes[4]
        packet[6] = macBytes[5]
        packet[7] = 0x00
        packet[8] = 0x01
        packet[9] = 0x05

        // 填入加密密文的前 8 字节 (索引 10 ~ 17)
        let cipherBytes = [UInt8](cipherData)
        for i in 0..<8 {
            packet[10 + i] = cipherBytes[i]
        }

        // 计算整包校验和取反 (前 18 字节累加)
        var checkSum: Int = 0
        for i in 0..<18 {
            checkSum += Int(packet[i])
        }
        packet[18] = UInt8((~checkSum) & 0xFF)
        packet[19] = 0x5A  // 包尾标识

        return Data(packet)
    }

    private func desEncrypt(data: Data, key: Data) -> Data? {
        var outData = Data(count: data.count)
        var bytesEncrypted: size_t = 0

        let status = outData.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmDES),
                            CCOptions(kCCOptionECBMode),
                            keyBytes.baseAddress, kCCKeySizeDES,
                            nil,
                            inBytes.baseAddress, data.count,
                            outBytes.baseAddress, data.count,
                            &bytesEncrypted)
                }
            }
        }

        return status == kCCSuccess ? outData : nil
    }
}

// 扩展：Hex 字符串转 Data
extension String {
    var hexData: Data? {
        var data = Data()
        var temp = ""
        for char in self {
            temp.append(char)
            if temp.count == 2 {
                guard let byte = UInt8(temp, radix: 16) else { return nil }
                data.append(byte)
                temp = ""
            }
        }
        return data
    }
}
