import 'dart:async';

import 'package:drivers_app/global/global.dart';
import 'package:drivers_app/models/user_ride_request_information.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_geofire/flutter_geofire.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../assistants/assistant_methods.dart';
import '../assistants/black_theme_google_map.dart';
import '../widgets/fare_amount_collection_dialog.dart';
import '../widgets/progress_dialog.dart';

class NewTripScreen extends StatefulWidget {
  UserRideRequestInformation? userRideRequestDetails;

  NewTripScreen({
    Key? key,
    this.userRideRequestDetails,
  }) : super(key: key);

  @override
  State<NewTripScreen> createState() => _NewTripScreenState();
}

class _NewTripScreenState extends State<NewTripScreen> {
  GoogleMapController? _newTripGoogleMapController;
  final Completer<GoogleMapController> _controllerGoogleMap = Completer();

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.4746,
  );

  String? _buttonTitle = 'Arrived';
  Color? _buttonColor = Colors.green;

  Set<Marker> _setOfMarkers = Set<Marker>();
  Set<Circle> _setOfCircle = Set<Circle>();
  Set<Polyline> _setOfPolyline = Set<Polyline>();
  List<LatLng> _polyLinePositionCoordinates = [];
  PolylinePoints _polylinePoints = PolylinePoints();

  double _mapPadding = 0;
  BitmapDescriptor? _iconAnimatedMarker;
  var geoLocator = Geolocator();
  Position? _onlineDriverCurrentPosition;

  String _rideRequestStatus = 'accepted';
  String _durationFromOriginToDestination = '';
  bool _isRequestDirectionDetails = false;

  //Step 1:: when driver accepts the user ride request
  // originLatLng = driverCurrent Location
  // destinationLatLng = user PickUp Location

  //Step 2:: driver already picked up the user in his/her car
  // originLatLng = user PickUp Location => driver current Location
  // destinationLatLng = user DropOff Location
  Future<void> _drawPolyLineFromOriginToDestination(
      LatLng originLatLng, LatLng destinationLatLng) async {
    showDialog(
      context: context,
      builder: (BuildContext context) => ProgressDialog(
        message: 'Please wait...',
      ),
    );

    var directionDetailsInfo =
        await AssistantMethods.obtainOriginToDestinationDirectionDetails(
            originLatLng, destinationLatLng);

    Navigator.pop(context);

    print('These are points = ');
    print(directionDetailsInfo!.encodedPoints);

    PolylinePoints pPoints = PolylinePoints();
    List<PointLatLng> decodedPolyLinePointsResultList =
        pPoints.decodePolyline(directionDetailsInfo.encodedPoints!);

    // clear the list of _polylineCoordinates before adding a new instance to it.
    _polyLinePositionCoordinates.clear();

    if (decodedPolyLinePointsResultList.isNotEmpty) {
      decodedPolyLinePointsResultList.forEach((PointLatLng pointLatLng) {
        _polyLinePositionCoordinates
            .add(LatLng(pointLatLng.latitude, pointLatLng.longitude));
      });
    }
    _setOfPolyline.clear();

    setState(() {
      Polyline polyline = Polyline(
        color: Colors.purpleAccent,
        polylineId: const PolylineId('PolylineID'), // polylineId can be any id
        jointType: JointType.round,
        points: _polyLinePositionCoordinates,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: true,
      );

      _setOfPolyline.add(polyline);
    });

    LatLngBounds boundsLatLng;
    if (originLatLng.latitude > destinationLatLng.latitude &&
        originLatLng.longitude > destinationLatLng.longitude) {
      boundsLatLng =
          LatLngBounds(southwest: destinationLatLng, northeast: originLatLng);
    } else if (originLatLng.longitude > destinationLatLng.longitude) {
      boundsLatLng = LatLngBounds(
        southwest: LatLng(originLatLng.latitude, destinationLatLng.longitude),
        northeast: LatLng(destinationLatLng.latitude, originLatLng.longitude),
      );
    } else if (originLatLng.latitude > destinationLatLng.latitude) {
      boundsLatLng = LatLngBounds(
        southwest: LatLng(destinationLatLng.latitude, originLatLng.longitude),
        northeast: LatLng(originLatLng.latitude, destinationLatLng.longitude),
      );
    } else {
      boundsLatLng =
          LatLngBounds(southwest: originLatLng, northeast: destinationLatLng);
    }

    _newTripGoogleMapController!
        .animateCamera(CameraUpdate.newLatLngBounds(boundsLatLng, 65));

    Marker originMarker = Marker(
      markerId: const MarkerId('originID'),
      position: originLatLng,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    );

    Marker destinationMarker = Marker(
      markerId: const MarkerId('destinationID'),
      position: destinationLatLng,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    );

    setState(() {
      _setOfMarkers.add(originMarker);
      _setOfMarkers.add(destinationMarker);
    });

    Circle originCircle = Circle(
      circleId: const CircleId('originID'),
      fillColor: Colors.green,
      radius: 12,
      strokeWidth: 3,
      strokeColor: Colors.white, // border of the circle
      center: originLatLng,
    );

    Circle destinationCircle = Circle(
      circleId: const CircleId('destinationID'),
      fillColor: Colors.red,
      radius: 12,
      strokeWidth: 3,
      strokeColor: Colors.white,
      center: destinationLatLng,
    );

    setState(() {
      _setOfCircle.add(originCircle);
      _setOfCircle.add(destinationCircle);
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _saveAssignedDriverDetailsToUserRideRequest();
  }

  _createDriverIconMarker() {
    if (_iconAnimatedMarker == null) {
      ImageConfiguration imageConfiguration =
          createLocalImageConfiguration(context, size: const Size(2, 2));
      BitmapDescriptor.fromAssetImage(
              imageConfiguration, 'assets/images/car.png')
          .then((value) {
        _iconAnimatedMarker = value;
      });
    }
  }

  _getDriversLocationUpdatesAtRealTime() {
    LatLng oldLatLng = LatLng(0, 0);

    streamSubscriptionDriverLivePosition =
        Geolocator.getPositionStream().listen((Position position) {
      driverCurrentPosition = position;
      _onlineDriverCurrentPosition = position;

      LatLng latLngLiveDriverPosition = LatLng(
        _onlineDriverCurrentPosition!.latitude,
        _onlineDriverCurrentPosition!.longitude,
      );

      Marker animatingMarker = Marker(
        markerId: const MarkerId('AnimatedMarker'),
        position: latLngLiveDriverPosition,
        icon: _iconAnimatedMarker!,
        infoWindow: const InfoWindow(title: 'This is your Position'),
      );

      setState(() {
        CameraPosition cameraPosition =
            CameraPosition(target: latLngLiveDriverPosition, zoom: 16);
        _newTripGoogleMapController!
            .animateCamera(CameraUpdate.newCameraPosition(cameraPosition));

        // L93
        _setOfMarkers.removeWhere(
            (element) => element.markerId.value == 'AnimatedMarker');
        _setOfMarkers.add(animatingMarker);
      });
      oldLatLng = latLngLiveDriverPosition;
      _updateDurationTimeAtRealTime();

      //updating driver location at real time in Database
      Map driverLatLngDataMap = {
        'latitude': _onlineDriverCurrentPosition!.latitude.toString(),
        'longitude': _onlineDriverCurrentPosition!.longitude.toString(),
      };
      FirebaseDatabase.instance
          .ref()
          .child('All Ride Requests')
          .child(widget.userRideRequestDetails!.rideRequestId!)
          .child('driverLocation')
          .set(driverLatLngDataMap);
    });
  }

  _updateDurationTimeAtRealTime() async {
    if (_isRequestDirectionDetails == false) {
      _isRequestDirectionDetails = true;

      if (_onlineDriverCurrentPosition == null) {
        return;
      }

      var originLatLng = LatLng(
        _onlineDriverCurrentPosition!.latitude,
        _onlineDriverCurrentPosition!.longitude,
      ); //Driver current Location

      LatLng? destinationLatLng;

      if (_rideRequestStatus == 'accepted') {
        destinationLatLng =
            widget.userRideRequestDetails!.originLatLng; //user PickUp Location
      } else {
        // arrived
        destinationLatLng = widget
            .userRideRequestDetails!.destinationLatLng; //user DropOff Location
      }

      var directionInformation =
          await AssistantMethods.obtainOriginToDestinationDirectionDetails(
              originLatLng, destinationLatLng!);

      if (directionInformation != null) {
        setState(() {
          _durationFromOriginToDestination = directionInformation.durationText!;
        });
      }

      _isRequestDirectionDetails = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _createDriverIconMarker();
    // Notification bar height
    var statusBarHeight = MediaQuery.of(context).viewPadding.top;
    return Scaffold(
      body: Stack(
        children: [
          //google map
          GoogleMap(
            padding: EdgeInsets.only(bottom: _mapPadding, top: statusBarHeight),
            mapType: MapType.normal,
            myLocationEnabled: true,
            initialCameraPosition: _kGooglePlex,
            markers: _setOfMarkers,
            circles: _setOfCircle,
            polylines: _setOfPolyline,
            onMapCreated: (GoogleMapController controller) {
              _controllerGoogleMap.complete(controller);
              _newTripGoogleMapController = controller;

              setState(() {
                _mapPadding = 350;
              });

              //black theme google map
              blackThemeGoogleMap(_newTripGoogleMapController);

              var driverCurrrentLatLng = LatLng(driverCurrentPosition!.latitude,
                  driverCurrentPosition!.longitude);

              var userPickUpLatLng =
                  widget.userRideRequestDetails!.originLatLng;

              _drawPolyLineFromOriginToDestination(
                  driverCurrrentLatLng, userPickUpLatLng!);

              _getDriversLocationUpdatesAtRealTime();
            },
          ),

          //ui
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white30,
                    blurRadius: 18,
                    spreadRadius: .5,
                    offset: Offset(0.6, 0.6),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
                child: Column(
                  children: [
                    //duration
                    Text(
                      _durationFromOriginToDestination,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.lightGreenAccent,
                      ),
                    ),

                    const SizedBox(
                      height: 18,
                    ),

                    const Divider(
                      thickness: 2,
                      height: 2,
                      color: Colors.grey,
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    //user name - icon
                    Row(
                      children: [
                        Text(
                          widget.userRideRequestDetails!.userName!,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.lightGreenAccent,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(10.0),
                          child: Icon(
                            Icons.phone_android,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 18,
                    ),

                    //user PickUp Address with icon
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/origin.png',
                          width: 30,
                          height: 30,
                        ),
                        const SizedBox(
                          width: 14,
                        ),
                        Expanded(
                          child: Container(
                            child: Text(
                              widget.userRideRequestDetails!.originAddress!,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20.0),

                    //user DropOff Address with icon
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/destination.png',
                          width: 30,
                          height: 30,
                        ),
                        const SizedBox(
                          width: 14,
                        ),
                        Expanded(
                          child: Container(
                            child: Text(
                              widget
                                  .userRideRequestDetails!.destinationAddress!,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 24,
                    ),

                    const Divider(
                      thickness: 2,
                      height: 2,
                      color: Colors.grey,
                    ),

                    const SizedBox(height: 10.0),

                    ElevatedButton.icon(
                      onPressed: () async {
                        //[driver has arrived at user PickUp Location] - Arrived Button
                        if (_rideRequestStatus == 'accepted') {
                          _rideRequestStatus = 'arrived';

                          FirebaseDatabase.instance
                              .ref()
                              .child('All Ride Requests')
                              .child(
                                  widget.userRideRequestDetails!.rideRequestId!)
                              .child('status')
                              .set(_rideRequestStatus);

                          setState(() {
                            _buttonTitle = "Let's Go"; //start the trip
                            _buttonColor = Colors.lightGreen;
                          });

                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext c) => ProgressDialog(
                              message: 'Loading...',
                            ),
                          );

                          await _drawPolyLineFromOriginToDestination(
                              widget.userRideRequestDetails!.originLatLng!,
                              widget
                                  .userRideRequestDetails!.destinationLatLng!);

                          Navigator.pop(context);
                        }
                        //[user has already sit in driver's car. Driver start trip now] - Lets Go Button
                        else if (_rideRequestStatus == 'arrived') {
                          _rideRequestStatus = 'ontrip';

                          FirebaseDatabase.instance
                              .ref()
                              .child('All Ride Requests')
                              .child(
                                  widget.userRideRequestDetails!.rideRequestId!)
                              .child('status')
                              .set(_rideRequestStatus);

                          setState(() {
                            _buttonTitle = 'End Trip'; //end the trip
                            _buttonColor = Colors.redAccent;
                          });
                        }
                        //[user/Driver reached to the dropOff Destination Location] - End Trip Button
                        else if (_rideRequestStatus == 'ontrip') {
                          _endTripNow();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        primary: _buttonColor,
                      ),
                      icon: const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                        size: 25,
                      ),
                      label: Text(
                        _buttonTitle!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _endTripNow() async {
    // s31
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => ProgressDialog(
        message: 'Please wait...',
      ),
    );

    //get the tripDirectionDetails = distance travelled
    var currentDriverPositionLatLng = LatLng(
      _onlineDriverCurrentPosition!.latitude,
      _onlineDriverCurrentPosition!.longitude,
    );

    var tripDirectionDetails =
        await AssistantMethods.obtainOriginToDestinationDirectionDetails(
            currentDriverPositionLatLng,
            widget.userRideRequestDetails!.originLatLng!);

    //fare amount
    double totalFareAmount =
        AssistantMethods.calculateFareAmountFromOriginToDestination(
            tripDirectionDetails!);

    FirebaseDatabase.instance
        .ref()
        .child('All Ride Requests')
        .child(widget.userRideRequestDetails!.rideRequestId!)
        .child('fareAmount')
        .set(totalFareAmount.toString());

    FirebaseDatabase.instance
        .ref()
        .child('All Ride Requests')
        .child(widget.userRideRequestDetails!.rideRequestId!)
        .child('status')
        .set('ended');

    streamSubscriptionDriverLivePosition!.cancel();

    Navigator.pop(context);

    // s32
    //display fare amount in dialog box
    showDialog(
      context: context,
      builder: (BuildContext c) => FareAmountCollectionDialog(
        totalFareAmount: totalFareAmount,
      ),
    );

    //save fare amount to driver total earnings
    _saveFareAmountToDriverEarnings(totalFareAmount);
  }

  _saveFareAmountToDriverEarnings(double totalFareAmount) {
    FirebaseDatabase.instance
        .ref()
        .child('drivers')
        .child(currentFirebaseUser!.uid)
        .child('earnings')
        .once()
        .then((snap) {
      if (snap.snapshot.value != null) //earnings sub Child exists
      {
        double oldEarnings = double.parse(snap.snapshot.value.toString());
        double driverTotalEarnings = totalFareAmount + oldEarnings;

        FirebaseDatabase.instance
            .ref()
            .child('drivers')
            .child(currentFirebaseUser!.uid)
            .child('earnings')
            .set(driverTotalEarnings.toString());
      } else //earnings sub Child do not exists
      {
        FirebaseDatabase.instance
            .ref()
            .child('drivers')
            .child(currentFirebaseUser!.uid)
            .child('earnings')
            .set(totalFareAmount.toString());
      }
    });
  }

  _saveAssignedDriverDetailsToUserRideRequest() {
    DatabaseReference databaseReference = FirebaseDatabase.instance
        .ref()
        .child('All Ride Requests')
        .child(widget.userRideRequestDetails!.rideRequestId!);

    Map driverLocationDataMap = {
      'latitude': driverCurrentPosition!.latitude.toString(),
      'longitude': driverCurrentPosition!.longitude.toString(),
    };
    databaseReference.child('driverLocation').set(driverLocationDataMap);

    databaseReference.child('status').set('accepted');
    databaseReference.child('driverId').set(onlineDriverData.id);
    databaseReference.child('driverName').set(onlineDriverData.name);
    databaseReference.child('driverPhone').set(onlineDriverData.phone);
    databaseReference.child('car_details').set(
        '${onlineDriverData.carColor} ${onlineDriverData.carModel} ${onlineDriverData.carNumber}');

    // _saveRideRequestIdToDriverHistory();
  }

  // removed at s28 L129
  /* _saveRideRequestIdToDriverHistory() {
    DatabaseReference tripsHistoryRef = FirebaseDatabase.instance
        .ref()
        .child('drivers')
        .child(currentFirebaseUser!.uid)
        .child('tripsHistory');

    tripsHistoryRef
        .child(widget.userRideRequestDetails!.rideRequestId!)
        .set(true);
  } */
}
