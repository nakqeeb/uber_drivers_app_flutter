import 'dart:async';

import 'package:drivers_app/push_notifications/push_notification_system.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_geofire/flutter_geofire.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../assistants/assistant_methods.dart';
import '../assistants/black_theme_google_map.dart';
import '../global/global.dart';

class HomeTabPage extends StatefulWidget {
  const HomeTabPage({Key? key}) : super(key: key);

  @override
  _HomeTabPageState createState() => _HomeTabPageState();
}

class _HomeTabPageState extends State<HomeTabPage>
    with AutomaticKeepAliveClientMixin {
  final Completer<GoogleMapController> _controllerGoogleMap = Completer();
  GoogleMapController? _newGoogleMapController;

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.4746,
  );

  var _geoLocator = Geolocator();
  LocationPermission? _locationPermission;

  String _statusText = 'Now Offline';
  Color _buttonColor = Colors.grey;
  bool _isDriverActive = false;

  _checkIfLocationPermissionAllowed() async {
    // ask user for permission
    _locationPermission = await Geolocator.requestPermission();
    // if not granted ask again
    if (_locationPermission == LocationPermission.denied) {
      _locationPermission = await Geolocator.requestPermission();
    }
  }

  _locateDriverPosition() async {
    Position cPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    driverCurrentPosition = cPosition;

    LatLng latLngPosition = LatLng(
        driverCurrentPosition!.latitude, driverCurrentPosition!.longitude);
    CameraPosition cameraPosition =
        CameraPosition(target: latLngPosition, zoom: 14);

    _newGoogleMapController!
        .animateCamera(CameraUpdate.newCameraPosition(cameraPosition));

    String humanReadableAddress =
        await AssistantMethods.searchAddressForGeographicCoOrdinates(
            driverCurrentPosition!, context);
    print('This is your address = ' + humanReadableAddress);

    // s39 L131
    AssistantMethods.readDriverRatings(context);
  }

  _readCurrentDriverInformation() async {
    currentFirebaseUser = fAuth.currentUser;

    await FirebaseDatabase.instance
        .ref()
        .child("drivers")
        .child(currentFirebaseUser!.uid)
        .once()
        .then((DatabaseEvent snap) {
      if (snap.snapshot.value != null) {
        onlineDriverData.id = (snap.snapshot.value as Map)["id"];
        onlineDriverData.name = (snap.snapshot.value as Map)["name"];
        onlineDriverData.phone = (snap.snapshot.value as Map)["phone"];
        onlineDriverData.email = (snap.snapshot.value as Map)["email"];
        onlineDriverData.carColor =
            (snap.snapshot.value as Map)["car_details"]["car_color"];
        onlineDriverData.carModel =
            (snap.snapshot.value as Map)["car_details"]["car_model"];
        onlineDriverData.carNumber =
            (snap.snapshot.value as Map)["car_details"]["car_number"];
        // driverVehicleType is global variable to be used to calculate fare amount in calculateFareAmountFromOriginToDestination()
        driverVehicleType = (snap.snapshot.value as Map)["car_details"]["type"];

        print("Car Details :: ");
        print(onlineDriverData.carColor);
        print(onlineDriverData.carModel);
        print(onlineDriverData.carNumber);
      }
    });
    PushNotificationSystem pushNotificationSystem = PushNotificationSystem();
    pushNotificationSystem.initializeCloudMessaging(context);
    pushNotificationSystem.generateAndGetToken();

    // s38 L129
    AssistantMethods.readDriverEarnings(context);
  }

  @override
  void initState() {
    super.initState();
    _checkIfLocationPermissionAllowed();
    _readCurrentDriverInformation();
  }

  @override
  Widget build(BuildContext context) {
    // Notification bar height
    var statusBarHeight = MediaQuery.of(context).viewPadding.top;
    return Stack(
      children: [
        GoogleMap(
          padding: EdgeInsets.only(top: statusBarHeight),
          mapType: MapType.normal,
          myLocationEnabled: true,
          initialCameraPosition: _kGooglePlex,
          onMapCreated: (GoogleMapController controller) {
            _controllerGoogleMap.complete(controller);
            _newGoogleMapController = controller;

            // for black theme google map
            blackThemeGoogleMap(_newGoogleMapController);

            _locateDriverPosition();
          },
        ),

        //ui for online offline driver
        _statusText != 'Now Online'
            ? Container(
                height: MediaQuery.of(context).size.height,
                width: double.infinity,
                color: Colors.black87,
              )
            : Container(),

        //button for online offline driver
        Positioned(
          top: _statusText != "Now Online"
              ? MediaQuery.of(context).size.height * 0.46
              : statusBarHeight,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  if (_isDriverActive != true) //offline
                  {
                    _driverIsOnlineNow();
                    _updateDriversLocationAtRealTime();

                    setState(() {
                      _statusText = 'Now Online';
                      _isDriverActive = true;
                      _buttonColor = Colors.transparent;
                    });

                    //display Toast
                    Fluttertoast.showToast(msg: 'you are Online Now');
                  } else //online
                  {
                    driverIsOfflineNow();

                    setState(() {
                      _statusText = 'Now Offline';
                      _isDriverActive = false;
                      _buttonColor = Colors.grey;
                    });

                    //display Toast
                    Fluttertoast.showToast(msg: 'you are Offline Now');
                  }
                },
                style: ElevatedButton.styleFrom(
                  primary: _buttonColor,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: _statusText != 'Now Online'
                    ? Text(
                        _statusText,
                        style: const TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.phonelink_ring,
                        color: Colors.white,
                        size: 26,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  _driverIsOnlineNow() async {
    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    driverCurrentPosition = pos;

    Geofire.initialize('activeDrivers');

    Geofire.setLocation(currentFirebaseUser!.uid,
        driverCurrentPosition!.latitude, driverCurrentPosition!.longitude);

    DatabaseReference ref = FirebaseDatabase.instance
        .ref()
        .child('drivers')
        .child(currentFirebaseUser!.uid)
        .child('newRideStatus');

    ref.set('idle'); //searching for ride request
    ref.onValue.listen((event) {});
  }

  _updateDriversLocationAtRealTime() {
    streamSubscriptionPosition =
        Geolocator.getPositionStream().listen((Position position) {
      driverCurrentPosition = position;

      if (_isDriverActive == true) {
        Geofire.setLocation(currentFirebaseUser!.uid,
            driverCurrentPosition!.latitude, driverCurrentPosition!.longitude);
      }

      LatLng latLng = LatLng(
        driverCurrentPosition!.latitude,
        driverCurrentPosition!.longitude,
      );

      _newGoogleMapController!.animateCamera(CameraUpdate.newLatLng(latLng));
    });
  }

  driverIsOfflineNow() {
    Geofire.removeLocation(currentFirebaseUser!.uid);

    DatabaseReference? ref = FirebaseDatabase.instance
        .ref()
        .child('drivers')
        .child(currentFirebaseUser!.uid)
        .child('newRideStatus');
    ref.onDisconnect();
    ref.remove();
    ref = null;

    Future.delayed(const Duration(milliseconds: 2000), () {
      //SystemChannels.platform.invokeMethod("SystemNavigator.pop");
      SystemNavigator.pop();
    });
  }

  // save current HomTab status when navigate between tabs
  // refer to https://stackoverflow.com/a/51225319/12636434
  @override
  bool get wantKeepAlive => true;
}
