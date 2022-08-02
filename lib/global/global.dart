import 'dart:async';

import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:drivers_app/models/driver_data.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../models/user_model.dart';

final FirebaseAuth fAuth = FirebaseAuth.instance;
User? currentFirebaseUser;
// update live location
StreamSubscription<Position>? streamSubscriptionPosition;
StreamSubscription<Position>? streamSubscriptionDriverLivePosition; // s28
AssetsAudioPlayer audioPlayer = AssetsAudioPlayer();
// to access the driver current position from the homeTab screen in newTripScreen
Position? driverCurrentPosition;
DriverData onlineDriverData = DriverData();

String? driverVehicleType = '';

String titleStarsRating = '';
