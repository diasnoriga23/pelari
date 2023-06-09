import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:battery_info/battery_info_plugin.dart';
import 'package:battery_info/enums/charging_status.dart';
import 'package:battery_info/model/android_battery_info.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:path_provider/path_provider.dart';
import 'package:usb_serial/transaction.dart';
import 'package:usb_serial/usb_serial.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  UsbPort? _port;
  String _status = "Idle";
  List<Widget> _ports = [];
  List<Widget> _serialData = [];
  StreamSubscription<String>? _subscription;
  Transaction<String>? _transaction;
  int? _deviceId;
  TextEditingController _textController = TextEditingController();
  TextEditingController _textControllerId = TextEditingController();
  final Location location = Location();
  LocationData? _location;
  StreamSubscription<LocationData>? _locationSubscription;
  String? _error;
  double speeds = 0;
  double? lng;
  double? lat;
  List<String> _listLat = [];
  String _dataPelari = '';
  int delaySend = 2;
  bool _isSendingData = false;
  Timer? _timer;
  List<String> _receivedData = [];
  String id_dev = '';
  AndroidBatteryInfo? androidBatteryInfo;
  DateTime? createdAt;
  bool containsStart = false;
  bool containsStop = false;
  bool tambahkan = false;
  bool exportData = false;

  Future<bool> _connectTo(device) async {
    _serialData.clear();

    if (_subscription != null) {
      _subscription?.cancel();
      _subscription = null;
    }

    if (_transaction != null) {
      _transaction?.dispose();
      _transaction = null;
    }

    if (_port != null) {
      _port?.close();
      _port = null;
    }

    if (device == null) {
      _deviceId = null;
      setState(() {
        _status = "Disconnected";
        myList.clear();
        id_dev = '';
        delaySend = 2;
      });
      return true;
    }

    _port = await device.create();
    if (!await _port!.open()) {
      setState(() {
        _status = "Failed to open port";
      });
      return false;
    }

    _deviceId = device.deviceId;
    await _port?.setDTR(true);
    await _port?.setRTS(true);
    await _port?.setPortParameters(
        115200, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    _transaction = Transaction.stringTerminated(
        _port!.inputStream!, Uint8List.fromList([13, 10]));

    _subscription =
        _port?.inputStream?.transform(StreamTransformer.fromHandlers(
      handleData: (Uint8List data, EventSink<String> sink) {
        String decodedData = utf8.decode(data);
        sink.add(decodedData);
      },
    )).listen((data) {
      setState(() {
        _receivedData.add(data);

        print('================');
        print(_receivedData);
        print('================');

        print(data);
        print('================');

        containsStart = data.contains("START");
        containsStop = data.contains("STOP");

        if (containsStart == true) {
          setState(() {
            tambahkan = true;
            // _startTambahData();
          });
          print('tambahkan nih ' + tambahkan.toString());
        } else {
          null;
        }
        if (containsStop == true) {
          setState(() {
            exportData = true;
            _stopTambahData();
          });
          print('export Data nih ' + exportData.toString());
        } else {
          null;
        }
        tambahkan == false
            ? null
            : myList.add(
                data.toString().replaceAll('*', createdAt.toString()) + ', *');
      });
    });

    setState(() {
      _status = "Connected";
    });
    return true;
  }

  void _getPorts() async {
    _ports = [];
    List<UsbDevice> devices = await UsbSerial.listDevices();
    print(devices);

    devices.forEach((device) {
      _ports.add(ListTile(
          leading: Icon(Icons.usb),
          title: Text(device.productName!),
          subtitle: Text(
              device.manufacturerName == null ? '' : device.manufacturerName!),
          trailing: ElevatedButton(
            child:
                Text(_deviceId == device.deviceId ? "Disconnect" : "Connect"),
            onPressed: () {
              _connectTo(_deviceId == device.deviceId ? null : device)
                  .then((res) {
                _getPorts();
              });
            },
          )));
    });

    setState(() {
      print(_ports);
    });
  }

  Future<void> getBatteryData() async {
    try {
      BatteryInfoPlugin batteryInfo = BatteryInfoPlugin();

      // Mengambil informasi baterai pada perangkat Android
      androidBatteryInfo = await batteryInfo.androidBatteryInfo;
      ChargingStatus? androidChargingStatus =
          androidBatteryInfo?.chargingStatus;

      print('Informasi Baterai Android:');
      print('Charging Status: $androidChargingStatus');

      // Mengambil informasi baterai pada perangkat iOS
    } catch (e) {
      print('Terjadi kesalahan saat mengambil informasi baterai: $e');
    }
  }

  Future<void> _listenLocation() async {
    _locationSubscription =
        location.onLocationChanged.handleError((dynamic err) {
      setState(() {
        _error = err.code;
      });
      _locationSubscription!.cancel();
    }).listen((LocationData currentLocation) {
      setState(() {
        _error = null;
        _location = currentLocation;

        speeds = _location!.speed!;
        lat = currentLocation.latitude;
        lng = currentLocation.longitude;

        // mkrrmp011222,lat,lng,sog,*

        _dataPelari = 'MKRRMP' +
            id_dev +
            '1222' +
            ',' +
            _location!.latitude.toString() +
            ',' +
            _location!.longitude.toString() +
            ',' +
            speeds.toStringAsFixed(6) +
            ',' +
            androidBatteryInfo!.batteryLevel.toString() +
            ',' +
            '*';
      });
    });
  }

  void _startSendingData() async {
    while (_isSendingData) {
      await Future.delayed(Duration(seconds: delaySend));
      getBatteryData();
      _sendData(_dataPelari == '' ? '0' : _dataPelari);
    }
  }

  // void _startTambahData() async {
  //   while (tambahkan == true) {
  //     print('Ada Start');

  //     print('data list nih ' + myList.length.toString());
  //     if (tambahkan == false) {
  //       break; // Hentikan loop
  //     }
  //   }
  // }

  void _stopTambahData() async {
    if (exportData == true) {
      print('Ada Stop');
      print('data list nih pas save' + myList.length.toString());
      saveListToFile(myList);
      print('save to android');
      exportData = false;
      tambahkan = false;
    }
  }

  void _sendData(String data) async {
    try {
      print('kirim');
      print(_serialData.length);
      createdAt = DateTime.now().toLocal();
      await _port?.write(Uint8List.fromList(data.codeUnits));
      print("Data sent: " + data);
    } catch (e) {
      print("Failed to send data: $e");
    }
  }

  void _muali() {
    if (_isSendingData == false) {
      setState(() {
        _isSendingData = true;
        _startSendingData();
      });
    } else {
      setState(() {
        _isSendingData = false;
        _receivedData.clear();
      });
    }
  }

  List<String> myList = [];
  Future<void> saveListToFile(List<String> list) async {
    final externalDir = await getExternalStorageDirectory();
    final filePath = '${externalDir!.path}/$createdAt.txt';

    final file = File(filePath);
    final sink = file.openWrite();

    for (final item in list) {
      sink.write('$item\n');
    }

    await sink.close();
    print('List berhasil disimpan ke dalam file: $filePath');
    myList.clear();
  }

  @override
  void initState() {
    super.initState();
    getBatteryData();
    _listenLocation();
    UsbSerial.usbEventStream?.listen((UsbEvent event) {
      _getPorts();
    });

    // createdAt = DateTime.now().toLocal();
    _getPorts();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
    _connectTo(null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blueGrey,
            title: const Text('Apps Pelari'),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                    child: Text('Save'),
                    onPressed: myList.isEmpty
                        ? null
                        : () {
                            saveListToFile(myList);
                          }),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Center(
                child: Column(children: <Widget>[
              SizedBox(
                height: 10,
              ),
              Text(
                _ports.length > 0
                    ? "Available Serial Ports"
                    : "Tidak ada serial device",
              ),
              ..._ports,
              SizedBox(
                height: 10,
              ),
              Text('Status: $_status\n'),
              Text('Latitude : $lat'),
              SizedBox(
                height: 10,
              ),
              Text('Longitude : $lng'),
              SizedBox(
                height: 10,
              ),
              Text(_location == null
                  ? 'Speed :  0'
                  : 'Speed :  ${_location!.speed != '' && _location!.speed! * 3600 / 1000 > 0 ? (_location!.speed! * 3600 / 1000).toStringAsFixed(1) : 0} KM/h'),
              SizedBox(
                height: 10,
              ),
              Text('Delay Data : $delaySend'),
              SizedBox(
                height: 10,
              ),
              ListTile(
                title: TextField(
                  controller: _textControllerId,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'ID Device',
                  ),
                ),
                trailing: ElevatedButton(
                  child: Text("Simpan"),
                  onPressed: _port == null
                      ? null
                      : () async {
                          if (_port == null) {
                            return;
                          }
                          id_dev = _textControllerId.text;
                        },
                ),
              ),
              ListTile(
                title: TextField(
                  controller: _textController,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Delay kirim data (Second)',
                  ),
                ),
                trailing: ElevatedButton(
                  child: Text("Ubah"),
                  onPressed: _port == null || id_dev == ''
                      ? null
                      : () async {
                          if (_port == null || id_dev == '') {
                            return;
                          }
                          delaySend = int.parse(_textController.text);
                        },
                ),
              ),
              SizedBox(
                height: 20,
              ),
              ElevatedButton(
                  child: Text('Clear Data'),
                  onPressed: () {
                    _receivedData.clear();
                  }),
              ElevatedButton(
                child: Text(_isSendingData == false ? "Mulai" : 'Stop'),
                onPressed: _port == null || id_dev == ''
                    ? null
                    : () async {
                        if (_port == null || id_dev == '') {
                          return;
                        }
                        _muali();
                      },
              ),

              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: _receivedData.length,
                itemBuilder: (context, index) {
                  return Center(
                      child: Column(
                    children: [
                      Text(_receivedData[index].replaceAll("\n", " ")),
                    ],
                  ));
                },
              ),
              // Text(
              //   "Result Data",
              // ),
              // ..._serialData,
            ])),
          ),
        ));
  }
}
