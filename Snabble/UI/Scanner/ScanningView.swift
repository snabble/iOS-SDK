//
//  ScanningView.swift
//
//  Copyright © 2018 snabble. All rights reserved.
//

import UIKit
import AVFoundation

extension ScanFormat {
    var avType: AVMetadataObject.ObjectType {
        switch self {
        case .ean8: return .ean8
        case .ean13: return .ean13
        case .code128: return .code128
        case .code39: return .code39
        case .itf14: return .itf14
        case .qr: return .qr
        case .dataMatrix: return .dataMatrix
        }
    }
}

extension AVMetadataObject.ObjectType {
    var scanFormat: ScanFormat? {
        switch self {
        case .ean13: return .ean13
        case .ean8: return .ean8
        case .code128: return .code128
        case .code39: return .code39
        case .itf14: return .itf14
        case .qr: return .qr
        case .dataMatrix: return .dataMatrix
        default: return nil
        }
    }
}

/// custom barcode detectors need to conform to this protocol
public protocol BarcodeDetector {
    /// a scan formats are should be detected
    var scanFormats: [ScanFormat] { get set }

    /// the AVCaptureOutput to use
    var captureOutput: AVCaptureOutput { get }

    /// the ScanningViewDelegate
    var delegate: ScanningViewDelegate? { get set }

    /// the UIView for camera preview. Use this for scale calculations
    var cameraView: UIView? { get set }

    /// the UIView used to mark the detected code within the camera preview. Modify its frame
    /// when a barcode is detected
    var indicatorView: UIView? { get set }
}

public protocol ScanningViewDelegate: class {

    /// called when the ScanningView needs to close itself
    func closeScanningView()

    /// callback for a successful scan
    func scannedCode(_ code: String, _ format: ScanFormat)

    /// called to request camera permission
    func requestCameraPermission(currentStatus: AVAuthorizationStatus)

    /// called when the "enter barcode" button is tapped
    func enterBarcode()

    /// called when the device has no back camera
    func noCameraFound()

    func track(_ event: AnalyticsEvent)
}

/// configuration of a ScanningView
public struct ScanningViewConfig {

    /// title for the view
    public var title: String?

    /// title for the "enter barcode" button
    public var enterButtonTitle: String?
    /// icon for the "enter barcode" button
    public var enterButtonImage: UIImage?

    /// title for the "torch toggle" button
    public var torchButtonTitle: String?
    /// icon for the "torch toggle" button
    public var torchButtonImage: UIImage?

    /// text color
    public var textColor = UIColor.white

    /// color of the reticle's border. Default: 100% white, 20% alpha
    public var reticleBorderColor = UIColor.init(white: 1.0, alpha: 0.2)
    /// width of the reticle's border, default 0.5
    public var reticleBorderWidth: CGFloat = 0.5
    /// corner radius of the reticle's border, default 0
    public var reticleCornerRadius: CGFloat = 0

    /// height of the reticle, in pixels
    public var reticleHeight: CGFloat = 160

    /// color for the dimming overlay. Default: 13% white, 60% alpha
    public var dimmingColor = UIColor(white: 0.13, alpha: 0.6)

    /// initial visibility of the button bar
    public var bottomBarHidden = false

    /// which object types should be recognized. Default: EAN-13/UPC-A
    public var scanFormats = [ ScanFormat.ean13 ]

    /// delegate object, the ScanningView keeps a weak reference to this
    public var delegate: ScanningViewDelegate?

    /// if nil, use AVFoundation's built-in barcode detection, can be set to a host app's implementation eg. using Firebase/MLKit
    public var barcodeDetector: BarcodeDetector?

    public init() {}
}

public final class ScanningView: DesignableView {

    @IBOutlet weak var reticleWrapper: UIView!
    @IBOutlet weak var reticle: UIView!
    @IBOutlet weak var bottomBar: UIView!

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var enterCodeWrapper: UIView!
    @IBOutlet weak var enterCodeIcon: UIImageView!
    @IBOutlet weak var enterCodeLabel: UILabel!

    @IBOutlet weak var torchWrapper: UIView!
    @IBOutlet weak var torchIcon: UIImageView!
    @IBOutlet weak var torchLabel: UILabel!

    @IBOutlet weak var reticleHeight: NSLayoutConstraint!

    @objc private var camera: AVCaptureDevice? = AVCaptureDevice.default(for: AVMediaType.video)

    weak var delegate: ScanningViewDelegate!
    var scanFormats = [ScanFormat]()

    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer!

    var serialQueue = DispatchQueue(label: "snabble.scannerQueue")
    var metadataOutput: AVCaptureMetadataOutput?
    var barcodeDetector: BarcodeDetector?

    var dimmingColor: UIColor!
    var reticleBorderLayer: CAShapeLayer!   // dims the preview, leaving a hole for the reticle
    var firstLayoutDone = false
    var fullDimmingLayer: CAShapeLayer!     // dims the whole preview layer

    var frameView = UIView()    // indicator for where the barcode was detected
    var frameTimer: Timer?

    /// toggle the visibility of the "barcode entry" and "torch" buttons at the bottom
    public var bottomBarHidden = false {
        didSet {
            self.bottomBar.isHidden = bottomBarHidden
        }
    }

    public var reticleHidden = false {
        didSet {
            self.reticle.isHidden = reticleHidden
            self.reticleBorderLayer.isHidden = reticleHidden
            self.fullDimmingLayer.isHidden = !reticleHidden
        }
    }

    public override func awakeFromNib() {
        super.awakeFromNib()

        self.view.backgroundColor = .black
        self.reticle.backgroundColor = .clear
        self.reticle.layer.masksToBounds = true

        let codeTap = UITapGestureRecognizer(target: self, action: #selector(self.enterButtonTapped(_:)))
        self.enterCodeWrapper.addGestureRecognizer(codeTap)

        let torchTap = UITapGestureRecognizer(target: self, action: #selector(self.torchButtonTapped(_:)))
        self.torchWrapper.addGestureRecognizer(torchTap)

        self.frameView.backgroundColor = .clear
        self.frameView.layer.borderColor = UIColor.lightGray.cgColor
        self.frameView.layer.borderWidth = 1
        self.frameView.layer.cornerRadius = 3
        self.view.addSubview(self.frameView)
        self.view.bringSubviewToFront(self.frameView)
    }

    /// this passes the `ScanningViewConfig` data to the ScanningView. This method must be called before the first pass of the
    /// layout engine, i.e. in you view controller's `viewDidLoad` or `viewWillAppear`
    public func setup(with config: ScanningViewConfig) {
        self.titleLabel.text = config.title
        self.titleLabel.textColor = config.textColor
        
        self.reticle.layer.borderColor = config.reticleBorderColor.cgColor
        self.reticle.layer.borderWidth = config.reticleBorderWidth
        self.reticle.layer.cornerRadius = config.reticleCornerRadius
        self.dimmingColor = config.dimmingColor

        self.enterCodeLabel.text = config.enterButtonTitle
        self.enterCodeIcon.image = config.enterButtonImage
        self.enterCodeLabel.textColor = config.textColor

        self.torchLabel.text = config.torchButtonTitle
        self.torchIcon.image = config.torchButtonImage
        self.torchLabel.textColor = config.textColor

        self.barcodeDetector = config.barcodeDetector
        self.barcodeDetector?.cameraView = self.view
        self.barcodeDetector?.indicatorView = self.frameView
        
        self.delegate = config.delegate
        self.scanFormats = config.scanFormats

        self.bottomBarHidden = config.bottomBarHidden

        self.reticleHeight.constant = config.reticleHeight
    }

    /// this must be called once to initialize the camera. If the app doesn't already have camera usage permission,
    /// the `requestCameraPermission` method of the delegate is called
    public func initializeCamera() {
        if self.checkCameraStatus() {
            self.initCaptureSession()
        }
    }

    /// start scanning
    public func startScanning() {
        self.frameView.isHidden = true
        self.frameView.frame = self.reticle.frame
        self.initCaptureSession()

        self.view.bringSubviewToFront(self.reticle)
        self.view.bringSubviewToFront(self.bottomBar)

        if let camera = self.camera {
            let torchToggleSupported = camera.isTorchModeSupported(.on) && camera.isTorchModeSupported(.off)
            self.torchWrapper.isHidden = !torchToggleSupported
        }

        self.startCaptureSession()
    }

    private func startCaptureSession() {
        if let capture = self.captureSession, !capture.isRunning, self.firstLayoutDone {
            self.serialQueue.async {
                capture.startRunning()
            }
        }
    }

    /// stop scanning
    public func stopScanning() {
        self.frameTimer?.invalidate()
        self.captureSession?.stopRunning()
    }

    /// is it possible to scan?
    public func readyToScan() -> Bool {
        return self.captureSession != nil
    }

    public func setScanFormats(_ formats: [ScanFormat]) {
        self.barcodeDetector?.scanFormats = formats
        self.metadataOutput?.metadataObjectTypes = formats.map { $0.avType }
    }

    @objc func enterButtonTapped(_ button: UIButton) {
        self.delegate.enterBarcode()
    }
    
    @objc func torchButtonTapped(_ button: UIButton) {
        guard let camera = self.camera else {
            return
        }

        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            camera.torchMode = camera.torchMode == .on ? .off : .on
            self.delegate.track(.toggleTorch)
        } catch {}
    }

    private func checkCameraStatus() -> Bool {
        // get the back camera device
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: .back) else {
            self.delegate?.noCameraFound()
            return false
        }

        // camera found, are we allowed to access it?
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        if authorizationStatus != .authorized {
            self.delegate.requestCameraPermission(currentStatus: authorizationStatus)
            return false
        }

        // set focus/low light properties of the back camera
        if camera.position == .back {
            do {
                try camera.lockForConfiguration()
                defer { camera.unlockForConfiguration() }

                if camera.isAutoFocusRangeRestrictionSupported {
                    camera.autoFocusRangeRestriction = .near
                }
                if camera.isFocusModeSupported(.continuousAutoFocus) {
                    camera.focusMode = .continuousAutoFocus
                }
                if camera.isLowLightBoostSupported {
                    camera.automaticallyEnablesLowLightBoostWhenAvailable = true
                }
            } catch {}
        }
        return true
    }


    // this is a terrible hack.
    // we need one pass through the layout system in order to figure out the position of the reticle, then force a second pass
    // and only then can we add the dimming overlay with the transparent "hole" at the right position
    public override func layoutSubviews() {
        super.layoutSubviews()

        assert(self.dimmingColor != nil, "setup() must be called before the first layout pass")

        if let previewLayer = self.previewLayer {
            previewLayer.frame = self.view.frame
        }

        if self.reticleBorderLayer == nil && self.firstLayoutDone {
            let overlayPath = UIBezierPath(rect: self.view.bounds)
            let rect = self.reticle.convert(self.reticle.bounds, to: self.view)
            let transparentPath = UIBezierPath(roundedRect: rect, cornerRadius: self.reticle.layer.cornerRadius)
            overlayPath.append(transparentPath)

            self.reticleBorderLayer = CAShapeLayer()
            self.reticleBorderLayer.path = overlayPath.cgPath
            self.reticleBorderLayer.fillRule = CAShapeLayerFillRule.evenOdd
            self.reticleBorderLayer.fillColor = self.dimmingColor.cgColor
            self.reticleBorderLayer.zPosition = -0.5
            self.view.layer.addSublayer(self.reticleBorderLayer)

            self.fullDimmingLayer = CAShapeLayer()
            let path = UIBezierPath(rect: self.view.bounds)
            self.fullDimmingLayer.path = path.cgPath
            self.fullDimmingLayer.fillColor = self.dimmingColor.cgColor
            self.fullDimmingLayer.zPosition = -0.5
            self.fullDimmingLayer.isHidden = true
            self.view.layer.addSublayer(self.fullDimmingLayer)
        }

        if !self.firstLayoutDone {
            self.setNeedsLayout()
        } else {
            let rect = self.reticle.frame
            if let metadataOutput = self.metadataOutput {
                if let layer = self.previewLayer, metadataOutput.rectOfInterest.origin.x == 0 {
                    let visibleRect = layer.metadataOutputRectConverted(fromLayerRect: rect)
                    metadataOutput.rectOfInterest = visibleRect
                    self.startCaptureSession()
                }
            } else {
                self.startCaptureSession()
            }
        }

        self.firstLayoutDone = true
    }

    func initCaptureSession() {
        if self.captureSession == nil {
            guard
                let videoCaptureDevice = AVCaptureDevice.default(for: AVMediaType.video),
                let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice)
            else {
                return
            }

            let captureSession = AVCaptureSession()

            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                return
            }

            let captureOutput: AVCaptureOutput
            if let detector = self.barcodeDetector {
                captureOutput = detector.captureOutput
                captureSession.addOutput(captureOutput)
            } else {
                let metadataOutput = AVCaptureMetadataOutput()
                captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = self.scanFormats.map { $0.avType }
                captureOutput = metadataOutput
                self.metadataOutput = metadataOutput
            }

            self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            self.previewLayer.frame = self.view.frame
            self.previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill

            self.previewLayer.zPosition = -1
            self.view.layer.addSublayer(self.previewLayer)

            self.captureSession = captureSession
        }
    }
}

extension ScanningView: AVCaptureMetadataOutputObjectsDelegate {

    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard
            let metadataObject = metadataObjects.first,
            let codeObject = metadataObject as? AVMetadataMachineReadableCodeObject,
            let code = codeObject.stringValue,
            let format = codeObject.type.scanFormat
        else {
            return
        }

        if let barCodeObject = self.previewLayer?.transformedMetadataObject(for: codeObject) {
            var bounds = barCodeObject.bounds
            let minSize: CGFloat = 60
            if bounds.height < minSize {
                bounds.size.height = minSize
                bounds.origin.y -= minSize / 2
            }
            if bounds.width < minSize {
                bounds.size.width = minSize
                bounds.origin.x -= minSize / 2
            }
            self.frameView.isHidden = false
            UIView.animate(withDuration: 0.25) {
                self.frameView.frame = bounds
            }

            self.frameTimer?.invalidate()
            self.frameTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
                self.frameView.isHidden = true
            }
        }

        self.delegate.scannedCode(code, format)
    }

}
