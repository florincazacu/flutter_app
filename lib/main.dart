import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:geofencing/geofencing.dart';
import 'package:rxdart/rxdart.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

final BehaviorSubject<ReceivedNotification> didReceiveLocalNotificationSubject =
BehaviorSubject<ReceivedNotification>();

final BehaviorSubject<String> selectNotificationSubject =
BehaviorSubject<String>();

NotificationAppLaunchDetails notificationAppLaunchDetails;
NotificationDetails platformChannelSpecifics;

class ReceivedNotification {
  final int id;
  final String title;
  final String body;
  final String payload;

  ReceivedNotification({
    @required this.id,
    @required this.title,
    @required this.body,
    @required this.payload,
  });
}

void main() async{

  WidgetsFlutterBinding.ensureInitialized();
  notificationAppLaunchDetails =
  await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
  var initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  // Note: permissions aren't requested here just to demonstrate that can be done later using the `requestPermissions()` method
  // of the `IOSFlutterLocalNotificationsPlugin` class
  var initializationSettingsIOS = IOSInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      onDidReceiveLocalNotification:
          (int id, String title, String body, String payload) async {
        didReceiveLocalNotificationSubject.add(ReceivedNotification(
            id: id, title: title, body: body, payload: payload));
      });
  var initializationSettings = InitializationSettings(
      initializationSettingsAndroid, initializationSettingsIOS);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings,
      onSelectNotification: (String payload) async {
        if (payload != null) {
          debugPrint('notification payload: ' + payload);
        }
        selectNotificationSubject.add(payload);
      });
  var androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'your channel id', 'your channel name', 'your channel description',
      importance: Importance.Max, priority: Priority.High, ticker: 'ticker');
  var iOSPlatformChannelSpecifics = IOSNotificationDetails();
  platformChannelSpecifics = NotificationDetails(
      androidPlatformChannelSpecifics, iOSPlatformChannelSpecifics);
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String geofenceState = 'N/A';
  List<String> registeredGeofences = [];
  double latitude = 44.412995;
  double longitude = 26.152327;
  double radius = 150.0;
  ReceivePort port = ReceivePort();
  final List<GeofenceEvent> triggers = <GeofenceEvent>[
    GeofenceEvent.enter,
    GeofenceEvent.dwell,
    GeofenceEvent.exit
  ];
  final AndroidGeofencingSettings androidSettings = AndroidGeofencingSettings(
      initialTrigger: <GeofenceEvent>[
        GeofenceEvent.enter,
        GeofenceEvent.exit,
        GeofenceEvent.dwell
      ],
      loiteringDelay: 1000);

  @override
  void initState() {
    super.initState();

    IsolateNameServer.registerPortWithName(
        port.sendPort, 'geofencing_send_port');
    port.listen((dynamic data) {
      print('Event: $data');
      setState(() {
        geofenceState = data;
      });
    });
    initPlatformState();
  }

  static void callback(List<String> ids, Location l, GeofenceEvent e) async {
    print('Fences: $ids Location $l Event: $e');
    final SendPort send =
    IsolateNameServer.lookupPortByName('geofencing_send_port');
    send?.send(e.toString());
    await _showNotification();
    _onGeofence(e);
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    print('Initializing...');
    await GeofencingManager.initialize();
    print('Initialization done');
  }

  String numberValidator(String value) {
    if (value == null) {
      return null;
    }
    final num a = num.tryParse(value);
    if (a == null) {
      return '"$value" is not a valid number';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            title: const Text('Flutter Geofencing Example'),
          ),
          body: Container(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text('Current state: $geofenceState'),
                    Center(
                      child: RaisedButton(
                        child: const Text('Register'),
                        onPressed: () async {
                          await _showNotification();
                          if (latitude == null) {
                            setState(() => latitude = 0.0);
                          }
                          if (longitude == null) {
                            setState(() => longitude = 0.0);
                          }
                          if (radius == null) {
                            setState(() => radius = 0.0);
                          }
                          GeofencingManager.registerGeofence(
                              GeofenceRegion('mtv', latitude, longitude,
                                  radius, triggers,
                                  androidSettings: androidSettings),
                              callback)
                              .then((_) {
                            GeofencingManager.getRegisteredGeofenceIds()
                                .then((value) {
                              setState(() {
                                registeredGeofences = value;
                              });
                            });
                          });
                        },
                      ),
                    ),
                    Text('Registered Geofences: $registeredGeofences'),
                    Center(
                      child: RaisedButton(
                        child: const Text('Unregister'),
                        onPressed: () =>
                            GeofencingManager.removeGeofenceById('mtv')
                                .then((_) {
                              GeofencingManager.getRegisteredGeofenceIds()
                                  .then((value) {
                                setState(() {
                                  registeredGeofences = value;
                                });
                              });
                            }),
                      ),
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Latitude',
                      ),
                      keyboardType: TextInputType.number,
                      controller:
                      TextEditingController(text: latitude.toString()),
                      onChanged: (String s) {
                        latitude = double.tryParse(s);
                      },
                    ),
                    TextField(
                        decoration:
                        const InputDecoration(hintText: 'Longitude'),
                        keyboardType: TextInputType.number,
                        controller:
                        TextEditingController(text: longitude.toString()),
                        onChanged: (String s) {
                          longitude = double.tryParse(s);
                        }),
                    TextField(
                        decoration: const InputDecoration(hintText: 'Radius'),
                        keyboardType: TextInputType.number,
                        controller:
                        TextEditingController(text: radius.toString()),
                        onChanged: (String s) {
                          radius = double.tryParse(s);
                        }),
                  ]))),
    );
  }

  static void _onGeofence(GeofenceEvent event) async {
    print('onGeofence called. Event: $event');
//    await _createNotificationChannel();
    await _showNotification();
//    var platformChannelSpecifics =
//    NotificationDetails(null, IOSNotificationDetails());
//    flutterLocalNotificationsPlugin
//        .show(0, 'Welcome home!', 'Don\'t forget to wash your hands!', platformChannelSpecifics)
//        .then((result) {})
//        .catchError((onError) {
//      print('[flutterLocalNotificationsPlugin.show] ERROR: $onError');
//    });
  }

  static Future<void> _showNotification() async {
    await flutterLocalNotificationsPlugin.show(
        0, 'Entered parking area', 'plain body', platformChannelSpecifics,
        payload: 'item x');
  }
}