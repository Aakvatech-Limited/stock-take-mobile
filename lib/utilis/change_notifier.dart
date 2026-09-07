import 'package:flutter/material.dart';

class StockTakeNotifier extends ChangeNotifier {
  String _countType = 'Count type';
  String _scanReferenceMode = '';
  String _scannedData = '';
  String _period = '';

  String get countType => _countType;
  String get scanReferenceMode => _scanReferenceMode;
  String get scannedData => _scannedData;
  String get period => _period;

  void setCountType(String newCountType) {
    _countType = newCountType;
    notifyListeners();
  }

  void setScannedData(String newScannedData) {
    _scannedData = newScannedData;
    notifyListeners(); // Notify listeners of the change
  }

  void setScanReferenceMode(String newScanReferenceMode) {
    _scanReferenceMode = newScanReferenceMode;
    notifyListeners();
  }

  void setPeriod(String newPeriod) {
    _period = newPeriod;
    notifyListeners();
  }
}
