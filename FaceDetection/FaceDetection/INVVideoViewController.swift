//
//  INVVideoViewController.swift
//
//
//  Created by Krzysztof Kryniecki on 9/23/16.
//  Copyright © 2016 InventiApps. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit
import CoreImage
import ImageIO
import CoreFoundation

enum INVVideoControllerErrors: Error {
    case unsupportedDevice
    case undefinedError
}

protocol INVRecordingViewControllerProtocol {
    func startRecording()
    func stopRecording()
    func startCaptureSesion()
    func stopCaptureSession()
    func startMetaSession()
}

class INVVideoViewController: UIViewController {

    var audioOutput: AVCaptureAudioDataOutput?
    var captureOutput: AVCaptureVideoDataOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var writer: INVWriter?
    var outputFilePath: URL?
    var isRecording: Bool = false
    var recordingActivated: Bool = false
    let outputQueue = DispatchQueue(label: "session output queue",
                                    qos: .userInteractive, target: nil)
    let cameraQueue = DispatchQueue(label: "camera queue")
    let audioOutputQueue = DispatchQueue(label: "audiosession output queue",
                                         qos: .userInteractive, target: nil)

    fileprivate let sessionQueue = DispatchQueue(label: "session queue",
                                     qos: .userInteractive,
                                     target: nil)
    fileprivate let captureSession = AVCaptureSession()
    private var numberOfAuthorizedDevices = 0
    fileprivate var runtimeCaptureErrorObserver: NSObjectProtocol?
    fileprivate var movieFileOutputCapture: AVCaptureMovieFileOutput?
    fileprivate let kINVRecordedFileName = "movie.mov"
    private var isAssetWriter: Bool = false
    @IBOutlet weak private var recordButton: UIButton!

    static func checkDeviceAuthorizationStatus(handler: @escaping ((_ granted: Bool) -> Void)) {
        AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: handler)
        AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeAudio, completionHandler: handler)
    }

    static func deviceWithMediaType(mediaType: String,
                             position: AVCaptureDevicePosition?) throws -> AVCaptureDevice? {
        if let devices = AVCaptureDevice.devices(withMediaType: mediaType),
            let devicePosition = position {
            for deviceObj in devices {
                if let device = deviceObj as? AVCaptureDevice,
                    device.position == devicePosition {
                    return device
                }
            }
        } else {
            if let devices = AVCaptureDevice.devices(withMediaType: mediaType),
                let device = devices.first as? AVCaptureDevice {
                return device
            }
        }
        throw INVVideoControllerErrors.unsupportedDevice
    }

    private func setupPreviewView(session: AVCaptureSession) throws {
        if let previewLayer = AVCaptureVideoPreviewLayer(session: session) {
            previewLayer.masksToBounds = true
            previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
            self.view.layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
            self.previewLayer?.frame = self.view.frame
            self.view.bringSubview(toFront: self.recordButton)
        } else {
            throw INVVideoControllerErrors.undefinedError
        }
    }

    private func setupCaptureSession() throws {
        let videoDevice = try INVVideoViewController.deviceWithMediaType(
            mediaType: AVMediaTypeVideo,
            position: AVCaptureDevicePosition.front)
        let captureDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        if self.captureSession.canAddInput(captureDeviceInput) {
            self.captureSession.addInput(captureDeviceInput)
        } else {
            fatalError("Cannot add video recording input")
        }
        let audioDevice = try INVVideoViewController.deviceWithMediaType(
            mediaType: AVMediaTypeAudio,
            position: nil)
        let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
        if self.captureSession.canAddInput(audioDeviceInput) {
            self.captureSession.addInput(audioDeviceInput)
        } else {
            fatalError("Cannot add audio recording input")
        }
    }

    fileprivate func startOutputSession() {
        self.setupAssetWritter()
    }

    fileprivate func initialSessionOperations() {
        self.startOutputSession()
        self.startCaptureSesion()
        self.startMetaSession()
    }

    // Sets Up Capturing Devices And Starts Capturing Session
    func runDeviceCapture(startSession: Bool) {
        do {
            try self.setupPreviewView(session: self.captureSession)
        } catch {
            fatalError("Undefined Error")
        }
        do {
            try self.setupCaptureSession()
            DispatchQueue.main.async {
                if startSession {
                    self.initialSessionOperations()
                }
            }
        } catch INVVideoControllerErrors.unsupportedDevice {
            fatalError("Unsuported Device")
        } catch {
            fatalError("Undefined Error")
        }
    }

    fileprivate func handleVideoRotation() {
        if let connection =  self.previewLayer?.connection {
            let currentDevice: UIDevice = UIDevice.current
            let orientation: UIDeviceOrientation = currentDevice.orientation
            let previewLayerConnection: AVCaptureConnection = connection
            if previewLayerConnection.isVideoOrientationSupported,
                let videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) {
                previewLayer?.connection.videoOrientation = videoOrientation
            }
            if let outputLayerConnection: AVCaptureConnection = self.captureOutput?.connection(
                withMediaType: AVMediaTypeVideo) {
                if outputLayerConnection.isVideoOrientationSupported,
                    let videoOrientation = AVCaptureVideoOrientation(rawValue:
                        orientation.rawValue) {
                    outputLayerConnection.videoOrientation = videoOrientation
                    outputLayerConnection.isVideoMirrored = true
                }
            }
        }
    }

    func setupDeviceCapture() {
        if self.numberOfAuthorizedDevices == 2 { // Audio and Video Devices were already set up
            self.startCaptureSesion()
        } else {
            INVVideoViewController.checkDeviceAuthorizationStatus { (granted) in
                if granted {
                    self.numberOfAuthorizedDevices += 1
                    if self.numberOfAuthorizedDevices >= 2 {
                        //Audio and Video must be authorized to start capture session
                        DispatchQueue.main.async {
                            self.runDeviceCapture(startSession: true)
                        }
                    }
                } else {
                    fatalError("Video and Audio Capture must be granted")
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.black
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.removeVideoFile()
        self.writer = nil
        self.setupDeviceCapture()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.stopCaptureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer?.frame = self.view.frame
        self.handleVideoRotation()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    override var shouldAutorotate: Bool {
        return true
    }

    fileprivate func removeVideoFile() {
        if let outputFilePath = self.outputFilePath {
            do {
                try FileManager.default.removeItem(at: outputFilePath)
                print("File Removed")
            } catch {
                print("Error while Deleting recorded File")
            }
        }
    }

    fileprivate func updateButtonTitle() {
        if self.isRecording {
            self.recordButton.setTitle("Stop Recording", for: .normal)
        } else {
            self.recordButton.setTitle("Start Recording", for: .normal)
        }
    }

    @IBAction func recordButtonPressed(_ sender: AnyObject) {
        if self.isRecording == false {
            self.startRecording()
        } else {
            self.stopRecording()
        }
        self.updateButtonTitle()
    }
}

extension INVVideoViewController:INVRecordingViewControllerProtocol {

    func startAutoRecording() {
        self.setupMoviewFileOutput()
        self.outputFilePath = URL(fileURLWithPath: NSTemporaryDirectory() + kINVRecordedFileName)
        self.movieFileOutputCapture?.startRecording(toOutputFileURL:
            self.outputFilePath, recordingDelegate: self)
        self.isRecording = true
    }

    func stopAutoRecording() {
        if self.isRecording {
            self.movieFileOutputCapture?.stopRecording()
            self.isRecording = false
        }
        self.updateButtonTitle()
        print("Stopped Capture Session")
    }

    func startRecording() {
        self.outputFilePath = URL(fileURLWithPath: NSTemporaryDirectory() + kINVRecordedFileName)
        self.removeVideoFile()
        self.isRecording = true
        cameraQueue.sync {
            self.recordingActivated = true
        }
        self.updateButtonTitle()
    }

    func stopRecording() {
        cameraQueue.sync {
            if self.recordingActivated {
                self.writer?.delegate = self
                self.recordingActivated = false
                self.outputQueue.async {
                    self.writer?.stop()
                }
            }
        }
        self.isRecording = false
        self.updateButtonTitle()
        print("Stopped Capture Session")
    }

    func startCaptureSesion() {
        print("Started Capture Session")
        self.captureSession.startRunning()
        self.previewLayer?.connection.automaticallyAdjustsVideoMirroring = false
        self.previewLayer?.connection.isVideoMirrored = true
        self.runtimeCaptureErrorObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVCaptureSessionRuntimeError,
            object: self.captureSession, queue: nil) {
                [weak self] (note) in
                self?.showCaptureError()
        }
    }

    func stopCaptureSession() {
        self.captureSession.stopRunning()
        if let observer = self.runtimeCaptureErrorObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func startMetaSession() {
        let metadataOutput = AVCaptureMetadataOutput()
        metadataOutput.setMetadataObjectsDelegate(self, queue: self.sessionQueue)
        if self.captureSession.canAddOutput(metadataOutput) {
            self.captureSession.addOutput(metadataOutput)
        } else {
           fatalError("Cannot Add Meta Capture Output")
        }
        metadataOutput.metadataObjectTypes = [AVMetadataObjectTypeFace]
    }

    func setupAssetWritter() {
        self.outputFilePath = URL(fileURLWithPath: NSTemporaryDirectory() + kINVRecordedFileName)
            self.captureOutput = AVCaptureVideoDataOutput()
            self.captureOutput?.alwaysDiscardsLateVideoFrames = true
            self.captureOutput?.setSampleBufferDelegate(self, queue: outputQueue)
            self.audioOutput = AVCaptureAudioDataOutput()
            self.audioOutput?.setSampleBufferDelegate(self, queue: audioOutputQueue)
            if self.captureSession.canAddOutput(self.captureOutput) {
                self.captureSession.addOutput(self.captureOutput)
            }
            if self.captureSession.canAddOutput(self.audioOutput) {
                self.captureSession.addOutput(self.audioOutput)
            }
            let orientation: UIDeviceOrientation = UIDevice.current.orientation
            if let outputLayerConnection: AVCaptureConnection = self.captureOutput?.connection(
                withMediaType: AVMediaTypeVideo),
                outputLayerConnection.isVideoOrientationSupported,
                let videoOrientation = AVCaptureVideoOrientation(
                    rawValue: orientation.rawValue) {
                outputLayerConnection.videoOrientation = videoOrientation
                outputLayerConnection.isVideoMirrored = true
                outputLayerConnection.preferredVideoStabilizationMode = .standard
            }
    }
}

extension INVVideoViewController: AVCaptureFileOutputRecordingDelegate {
    func playVideo() {
        if let outuputFile = self.outputFilePath {
            print("Output \(outuputFile)")
            let videoController = AVPlayerViewController()
            videoController.player = AVPlayer(url: outuputFile)
            self.present(videoController, animated: true) {
                videoController.player?.play()
            }
        }
    }
    func capture(_ captureOutput: AVCaptureFileOutput!,
                 didFinishRecordingToOutputFileAt outputFileURL: URL!,
                 fromConnections connections: [Any]!, error: Error!) {
        if error != nil {
            print("Error occured during recording \(error.localizedDescription)")
            self.showCaptureError()
        } else {
            self.playVideo()
            print("Finished Recording")
        }
    }
    func setupMoviewFileOutput() {
        if self.movieFileOutputCapture != nil {
        } else {
            self.movieFileOutputCapture = AVCaptureMovieFileOutput()
            if self.captureSession.canAddOutput(self.movieFileOutputCapture) {
                self.captureSession.addOutput(self.movieFileOutputCapture)
                let connection = self.movieFileOutputCapture?.connection(
                    withMediaType: AVMediaTypeVideo)
                connection?.isVideoMirrored = true
            } else {
                fatalError("Cannot Add Movie File Output")
            }
        }
    }
    fileprivate func showCaptureError() {
        let alert = UIAlertController(title:"Error",
                                      message: "Something Went Wrong While Recording",
                                      preferredStyle: .alert)
        let alertOkAction = UIAlertAction(title: "Cancel Recording",
                                          style: .cancel,
                                          handler: { (action) in
                                            self.stopRecording()
                                            self.stopCaptureSession()
        })
        let alertRestartAction = UIAlertAction(title: "Restart Recording",
                                               style: .cancel, handler: { (action) in
                                                self.sessionQueue.async {
                                                    self.captureSession.startRunning()
                                                    if self.isRecording {
                                                        self.startRecording()
                                                    }
                                                }
        })
        alert.addAction(alertOkAction)
        alert.addAction(alertRestartAction)
        alert.show(self, sender: nil)
    }
}
