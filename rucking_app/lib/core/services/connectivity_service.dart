import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/app_logger.dart';

abstract class ConnectivityService {
  Stream<bool> get connectivityStream;
  Future<bool> isConnected();
  void dispose();
}

class ConnectivityServiceImpl implements ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  late StreamController<bool> _connectivityController;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isConnected = false;

  ConnectivityServiceImpl() {
    _connectivityController = StreamController<bool>.broadcast();
    _startListening();
  }

  @override
  Stream<bool> get connectivityStream => _connectivityController.stream;

  @override
  Future<bool> isConnected() async {
    final result = await _connectivity.checkConnectivity();
    return _isConnectedFromResult(result);
  }

  void _startListening() {
    _subscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isConnected = _isConnectedFromResult(results);
      if (isConnected != _isConnected) {
        _isConnected = isConnected;
        _connectivityController.add(isConnected);
        AppLogger.info('Network connectivity changed: ${isConnected ? 'Connected' : 'Disconnected'}');
      }
    });
  }

  bool _isConnectedFromResult(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _connectivityController.close();
  }
}
