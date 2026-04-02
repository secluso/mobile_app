//! SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;

class SeclusoQrReader extends StatefulWidget {
  const SeclusoQrReader({
    super.key,
    required this.onScan,
    this.onScanFailure,
    this.onControllerCreated,
    this.codeFormat = zxing.Format.any,
    this.tryHarder = false,
    this.tryInverted = false,
    this.tryRotate = true,
    this.tryDownscale = false,
    this.maxNumberOfSymbols = 10,
    this.cropPercent = 0.5,
    this.horizontalCropOffset = 0.0,
    this.verticalCropOffset = 0.0,
    this.resolution = ResolutionPreset.high,
    this.lensDirection = CameraLensDirection.back,
    this.scanDelay = const Duration(milliseconds: 1000),
    this.scanDelaySuccess = const Duration(milliseconds: 1000),
    this.loading = const DecoratedBox(
      decoration: BoxDecoration(color: Colors.black),
    ),
  });

  final ValueChanged<zxing.Code> onScan;
  final ValueChanged<zxing.Code>? onScanFailure;
  final void Function(CameraController? controller, Exception? error)?
  onControllerCreated;
  final int codeFormat;
  final bool tryHarder;
  final bool tryInverted;
  final bool tryRotate;
  final bool tryDownscale;
  final int maxNumberOfSymbols;
  final double cropPercent;
  final double horizontalCropOffset;
  final double verticalCropOffset;
  final ResolutionPreset resolution;
  final CameraLensDirection lensDirection;
  final Duration scanDelay;
  final Duration scanDelaySuccess;
  final Widget loading;

  @override
  State<SeclusoQrReader> createState() => _SeclusoQrReaderState();
}

class _SeclusoQrReaderState extends State<SeclusoQrReader>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const <CameraDescription>[];
  CameraDescription? _selectedCamera;
  CameraController? _controller;

  bool _isProcessing = false;
  bool _isCameraOn = false;
  bool _isInitializing = false;
  bool _cameraProcessingStarted = false;
  String _controllerVersion = '';

  bool _isAndroid() => Theme.of(context).platform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeScanner());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isInitializing &&
            _controller == null &&
            _cameras.isNotEmpty &&
            mounted) {
          unawaited(_selectCamera(_selectedCamera ?? _cameras.first));
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_disposeController());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeController());
    if (_cameraProcessingStarted) {
      zxing.zx.stopCameraProcessing();
    }
    super.dispose();
  }

  Future<void> _initializeScanner() async {
    try {
      if (!_cameraProcessingStarted) {
        await zxing.zx.startCameraProcessing();
        _cameraProcessingStarted = true;
      }

      final cameras = await availableCameras();
      if (!mounted) {
        return;
      }

      _cameras = cameras;
      if (cameras.isEmpty) {
        _reportControllerError(Exception('No cameras available.'));
        return;
      }

      _selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == widget.lensDirection,
        orElse: () => cameras.first,
      );
      await _selectCamera(_selectedCamera!);
    } catch (error) {
      _reportControllerError(error);
    }
  }

  Future<void> _selectCamera(CameraDescription cameraDescription) async {
    if (_isInitializing) {
      return;
    }

    _isInitializing = true;
    await _disposeController();

    final controllerVersion = DateTime.now().millisecondsSinceEpoch.toString();
    _controllerVersion = controllerVersion;

    final controller = CameraController(
      cameraDescription,
      widget.resolution,
      enableAudio: false,
    );
    _controller = controller;
    _selectedCamera = cameraDescription;

    try {
      await controller.initialize();
      if (!mounted ||
          _controller != controller ||
          _controllerVersion != controllerVersion) {
        return;
      }

      widget.onControllerCreated?.call(controller, null);

      await controller.startImageStream(
        (image) => _processImageStream(image, controllerVersion),
      );

      if (!mounted ||
          _controller != controller ||
          _controllerVersion != controllerVersion) {
        return;
      }

      setState(() {
        _isCameraOn = true;
      });
    } catch (error) {
      if (_controller == controller) {
        await _disposeController();
      }
      _reportControllerError(error);
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    _isCameraOn = false;
    _isProcessing = false;
    _controllerVersion = 'disposed_${DateTime.now().millisecondsSinceEpoch}';

    if (controller == null) {
      return;
    }

    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }

    try {
      await controller.dispose();
    } catch (_) {}
  }

  void _reportControllerError(Object error) {
    widget.onControllerCreated?.call(
      null,
      error is Exception ? error : Exception(error.toString()),
    );
  }

  Future<void> _processImageStream(
    CameraImage image,
    String controllerVersion,
  ) async {
    if (_isProcessing ||
        _isInitializing ||
        !mounted ||
        _controller == null ||
        controllerVersion != _controllerVersion) {
      return;
    }

    _isProcessing = true;
    try {
      final cropPercent = widget.cropPercent <= 0 ? 1.0 : widget.cropPercent;
      final cropSize = max(
        1,
        (min(image.width, image.height) * cropPercent).round(),
      );

      final swapAxes =
          _isAndroid() &&
          MediaQuery.of(context).orientation == Orientation.portrait;
      final horizontalOffset =
          swapAxes ? widget.verticalCropOffset : widget.horizontalCropOffset;
      final verticalOffset =
          swapAxes ? -widget.horizontalCropOffset : widget.verticalCropOffset;
      final cropLeft = ((image.width - cropSize) ~/ 2 +
              (horizontalOffset * (image.width - cropSize) / 2))
          .round()
          .clamp(0, image.width - cropSize);
      final cropTop = ((image.height - cropSize) ~/ 2 +
              (verticalOffset * (image.height - cropSize) / 2))
          .round()
          .clamp(0, image.height - cropSize);

      final params = zxing.DecodeParams(
        imageFormat: _imageFormat(image.format.group),
        format: widget.codeFormat,
        width: image.width,
        height: image.height,
        cropLeft: cropLeft,
        cropTop: cropTop,
        cropWidth: cropSize,
        cropHeight: cropSize,
        tryHarder: widget.tryHarder,
        tryRotate: widget.tryRotate,
        tryInverted: widget.tryInverted,
        tryDownscale: widget.tryDownscale,
        maxNumberOfSymbols: widget.maxNumberOfSymbols,
      );

      final result = await zxing.zx.processCameraImage(image, params);
      if (result.isValid) {
        widget.onScan(result);
        await Future<void>.delayed(widget.scanDelaySuccess);
      } else {
        widget.onScanFailure?.call(result);
      }
    } catch (error) {
      debugPrint('SeclusoQrReader processImageStream error: $error');
    } finally {
      if (mounted && controllerVersion == _controllerVersion) {
        await Future<void>.delayed(widget.scanDelay);
      }
      _isProcessing = false;
    }
  }

  int _imageFormat(ImageFormatGroup group) {
    switch (group) {
      case ImageFormatGroup.unknown:
        return zxing.ImageFormat.none;
      case ImageFormatGroup.bgra8888:
        return zxing.ImageFormat.bgrx;
      case ImageFormatGroup.yuv420:
        return zxing.ImageFormat.lum;
      case ImageFormatGroup.jpeg:
        return zxing.ImageFormat.rgb;
      case ImageFormatGroup.nv21:
        return zxing.ImageFormat.rgb;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isCameraReady =
        _cameras.isNotEmpty &&
        _isCameraOn &&
        controller != null &&
        controller.value.isInitialized;
    final size = MediaQuery.of(context).size;
    final cameraMaxSize = max(size.width, size.height);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!isCameraReady) widget.loading,
        if (isCameraReady)
          SizedBox(
            width: cameraMaxSize,
            height: cameraMaxSize,
            child: OverflowBox(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cameraMaxSize,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
