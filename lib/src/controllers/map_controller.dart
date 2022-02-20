import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mvc_pattern/mvc_pattern.dart';

import '../helpers/app_config.dart' as config;
import '../helpers/helper.dart';
import '../helpers/maps_util.dart';
import '../models/address.dart';
import '../models/order.dart';
import '../repository/order_repository.dart';
import '../repository/settings_repository.dart' as sett;

class MapController extends ControllerMVC {
  Order currentOrder;
  List<Order> orders = <Order>[];
  List<Marker> allMarkers = <Marker>[];
  Address currentAddress;
  Set<Polyline> polylines = new Set();
  CameraPosition cameraPosition;
  MapsUtil mapsUtil = new MapsUtil();
  double taxAmount = 0.0;
  double subTotal = 0.0;
  double deliveryFee = 0.0;
  double total = 0.0;
  Completer<GoogleMapController> mapController = Completer();

  // !!!!!!!!!!!!
  PolylinePoints polylinePoints;

// List of coordinates to join
  List<LatLng> polylineCoordinates = [];

// Map storing polylines created by connecting two points
  Map<PolylineId, Polyline> polylinesNew = {};

  void _createPolylines(
    double startLatitude,
    double startLongitude,
    double destinationLatitude,
    double destinationLongitude,
  ) async {
    // Initializing PolylinePoints
    polylinePoints = PolylinePoints();

    // Generating the list of coordinates to be used for
    // drawing the polylines
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      sett.setting.value?.googleMapsKey, // Google Maps API Key
      PointLatLng(startLatitude, startLongitude),
      PointLatLng(destinationLatitude, destinationLongitude),
      travelMode: TravelMode.driving,
    );

    // Adding the coordinates to the list

    if (result.points.isNotEmpty) {
      result.points.forEach((PointLatLng point) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      });
      print(polylineCoordinates);
      if (polylineCoordinates != null) {
        List<LatLng> _latLng = polylineCoordinates;
        _latLng?.insert(
            0, new LatLng(currentAddress.latitude, currentAddress.longitude));
        setState(() {
          polylines.add(new Polyline(
              visible: true,
              geodesic: true,
              polylineId: new PolylineId(currentAddress.hashCode.toString()),
              points: _latLng,
              color: config.Colors().mainColor(0.8),
              width: 6));
        });
      }
    }

    // Defining an ID
    PolylineId id = PolylineId('poly');

    // Initializing Polyline
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.red,
      points: polylineCoordinates,
      width: 3,
    );

    // Adding the polyline to the map
    polylinesNew[id] = polyline;
  }

  void listenForNearOrders(Address myAddress, Address areaAddress) async {
    print('listenForOrders');
    final Stream<Order> stream = await getNearOrders(myAddress, areaAddress);
    stream.listen(
        (Order _order) {
          setState(() {
            orders.add(_order);
          });
          if (!_order.deliveryAddress.isUnknown()) {
            Helper.getOrderMarker(_order.deliveryAddress.toMap())
                .then((marker) {
              setState(() {
                allMarkers.add(marker);
              });
            });
          }
        },
        onError: (a) {},
        onDone: () {
          calculateSubtotal();
        });
  }

  void getCurrentLocation() async {
    try {
      currentAddress = sett.myAddress.value;
      setState(() {
        if (currentAddress.isUnknown()) {
          cameraPosition = CameraPosition(
            target: LatLng(40, 3),
            zoom: 4,
          );
        } else {
          cameraPosition = CameraPosition(
            target: LatLng(currentAddress.latitude, currentAddress.longitude),
            zoom: 14.4746,
          );
        }
      });
      if (!currentAddress.isUnknown()) {
        Helper.getMyPositionMarker(
                currentAddress.latitude, currentAddress.longitude)
            .then((marker) {
          setState(() {
            allMarkers.add(marker);
          });
        });
      }
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        print('Permission denied');
      }
    }
  }

  void getOrderLocation() async {
    try {
      currentAddress = sett.myAddress.value;
      setState(() {
        cameraPosition = CameraPosition(
          target: LatLng(currentOrder.deliveryAddress.latitude,
              currentOrder.deliveryAddress.longitude),
          zoom: 14.4746,
        );
      });
      print(cameraPosition);
      if (!currentAddress.isUnknown()) {
        Helper.getMyPositionMarker(
                currentAddress.latitude, currentAddress.longitude)
            .then((marker) {
          setState(() {
            allMarkers.add(marker);
          });
        });
      }
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        print('Permission denied');
      }
    }
  }

  Future<void> goCurrentLocation() async {
    final GoogleMapController controller = await mapController.future;

    sett.setCurrentLocation().then((_currentAddress) {
      setState(() {
        sett.myAddress.value = _currentAddress;
        currentAddress = _currentAddress;
      });
      controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(_currentAddress.latitude, _currentAddress.longitude),
        zoom: 14.4746,
      )));
    });
  }

  void getOrdersOfArea() async {
    setState(() {
      orders = <Order>[];
      Address areaAddress = Address.fromJSON({
        "latitude": cameraPosition.target.latitude,
        "longitude": cameraPosition.target.longitude
      });
      if (cameraPosition != null) {
        listenForNearOrders(currentAddress, areaAddress);
      } else {
        listenForNearOrders(currentAddress, currentAddress);
      }
    });
  }

  void getDirectionSteps() async {
    print("polylines");

    currentAddress = sett.myAddress.value;
    print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
    print(currentAddress.latitude.toString());
    print(currentAddress.longitude.toString());
    print(currentOrder.deliveryAddress.longitude.toString());
    print(currentOrder.deliveryAddress.latitude.toString());
    print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
    print("origin=" +
        currentAddress.latitude.toString() +
        "," +
        currentAddress.longitude.toString() +
        "&destination=" +
        currentOrder.deliveryAddress.latitude.toString() +
        "," +
        currentOrder.deliveryAddress.longitude.toString() +
        "&key=${sett.setting.value?.googleMapsKey}");

    // mapsUtil
    //     .get("origin=" +
    //         currentAddress.latitude.toString() +
    //         "," +
    //         currentAddress.longitude.toString() +
    //         "&destination=" +
    //         currentOrder.deliveryAddress.latitude.toString() +
    //         "," +
    //         currentOrder.deliveryAddress.longitude.toString() +
    //         "&key=${sett.setting.value?.googleMapsKey}")
    //     .then((dynamic res) {
    //   print(res.runtimeType);
    //   if (res != null) {
    //     List<LatLng> _latLng = res as List<LatLng>;
    //     _latLng?.insert(
    //         0, new LatLng(currentAddress.latitude, currentAddress.longitude));
    //     setState(() {
    //       polylines.add(new Polyline(
    //           visible: true,
    //           geodesic: true,
    //           polylineId: new PolylineId(currentAddress.hashCode.toString()),
    //           points: _latLng,
    //           color: config.Colors().mainColor(0.8),
    //           width: 4));
    //     });
    //   }
    // });

    _createPolylines(
        currentAddress.latitude,
        currentAddress.longitude,
        currentOrder.deliveryAddress.latitude,
        currentOrder.deliveryAddress.longitude);
  }

  void calculateSubtotal() async {
    subTotal = 0;
    currentOrder.productOrders?.forEach((food) {
      subTotal += food.quantity * food.price;
    });
    deliveryFee = currentOrder.deliveryFee > 0 ? currentOrder.deliveryFee : 0;

    //  deliveryFee =
    //      currentOrder.foodOrders?.elementAt(0)?.food?.restaurant?.deliveryFee ?? 0;
    taxAmount = (subTotal + deliveryFee) * currentOrder.tax / 100;
    total = subTotal + taxAmount + deliveryFee;

    taxAmount = subTotal * currentOrder.tax / 100;
    total = subTotal + taxAmount;
    setState(() {});
  }

  Future refreshMap() async {
    setState(() {
      orders = <Order>[];
    });
    listenForNearOrders(currentAddress, currentAddress);
  }
}
