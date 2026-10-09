import 'dart:convert';

class EmployeeModel {
  int? employeeId;
  String? name;
  String? designation;
  String? geofenceUser;
  String? latitute;
  String? longitude;
  String? dimeter;
  String? companyName;
  String? department;
  String? gender;
  String? regImage;
  String? email;
  String? phone;
  String? dateofBirth;
  String? userImage;
  String? isAdmin;
  int? companyId;
  String? enrollmentId;
  String? trackingTime;
  String? bioMatricTime;
  String? dateofJoin;
  int? managerId;
  String? mobileCode;

  bool? isManager;
  bool? isSelfService;
  bool? isNFC;
  bool? bluetooth;
  bool? geoUser;
  bool? nonGeoUser;
  bool? isleave;
  bool? isManaul;
  bool? isBusiness;
  bool? isWFH;
  bool? isCO;
  bool? isSite;
  bool? isIncident;
  bool? isAutoOutCheck;

  String? geoFenceType;
  String? multipleGeoIds;

  bool? isPermissionReq;
  bool? isTracking;
  bool? isPunching;
  bool? isPassword;
  bool? isLocationTrackingRequired;
  bool? isLeaveAttachmentRequired;
  bool? isBusinessTravelAttachmentRequired;
  bool? isFirstInLastOut;
  bool? showOfficeLocation;
  bool? offline;
  bool? allowOffline;

  List<double>? faceEmbedding;

  bool? isFaceEmbedding;
  bool? isFaceRegister;

  String? realFace;
  String? employeeNo;
  String? appVersion;
  String? iosAppVersion;

  bool? isNewVersionNeeded;

  /// Effective employee identifier used throughout the application.
  /// Priority:
  /// 1. [mobileCode] (Primary employee code in this system, e.g. "LTDEMO111241")
  /// 2. [employeeNo] (if non-empty and not '0')
  /// 3. [enrollmentId] (if non-empty)
  /// 4. [employeeId] (only if non-zero integer)
  String get effectiveEmployeeNo {
    if (mobileCode != null && mobileCode!.trim().isNotEmpty) {
      return mobileCode!.trim();
    }
    if (employeeNo != null &&
        employeeNo!.trim().isNotEmpty &&
        employeeNo!.trim() != '0') {
      return employeeNo!.trim();
    }
    if (enrollmentId != null && enrollmentId!.trim().isNotEmpty) {
      return enrollmentId!.trim();
    }
    if (employeeId != null && employeeId != 0) {
      return employeeId.toString();
    }
    return '';
  }

  EmployeeModel({
    this.employeeId,
    this.name,
    this.designation,
    this.geofenceUser,
    this.latitute,
    this.longitude,
    this.dimeter,
    this.companyName,
    this.department,
    this.gender,
    this.regImage,
    this.email,
    this.phone,
    this.dateofBirth,
    this.userImage,
    this.isAdmin,
    this.companyId,
    this.enrollmentId,
    this.trackingTime,
    this.bioMatricTime,
    this.dateofJoin,
    this.managerId,
    this.mobileCode,
    this.isManager,
    this.isSelfService,
    this.isNFC,
    this.bluetooth,
    this.geoUser,
    this.nonGeoUser,
    this.isleave,
    this.isManaul,
    this.isBusiness,
    this.isWFH,
    this.isCO,
    this.isSite,
    this.isIncident,
    this.isAutoOutCheck,
    this.geoFenceType,
    this.multipleGeoIds,
    this.isPermissionReq,
    this.isTracking,
    this.isPunching,
    this.isPassword,
    this.isLocationTrackingRequired,
    this.isLeaveAttachmentRequired,
    this.isBusinessTravelAttachmentRequired,
    this.isFirstInLastOut,
    this.showOfficeLocation,
    this.offline,
    this.allowOffline,
    this.faceEmbedding,
    this.isFaceEmbedding,
    this.isFaceRegister,
    this.realFace,
    this.employeeNo,
    this.appVersion,
    this.iosAppVersion,
    this.isNewVersionNeeded,
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel(
      employeeId: json['EmployeeID'],
      name: json['Name'],
      designation: json['Designation'],
      geofenceUser: json['GeofenceUser'],
      latitute: json['Latitute'],
      longitude: json['Longitude'],
      dimeter: json['Dimeter'],
      companyName: json['CompanyName'],
      department: json['Department'],
      gender: json['Gender'],
      regImage: json['regImage'],
      email: json['Email'],
      phone: json['Phone'],
      dateofBirth: json['DateofBirth'],
      userImage: json['UserImage'],
      isAdmin: json['isAdmin'],
      companyId: json['CompanyID'],
      enrollmentId: json['EnrollmentID'],
      trackingTime: json['TrackingTime'],
      bioMatricTime: json['BioMatricTime'],
      dateofJoin: json['DateofJoin'],
      managerId: json['ManagerID'],
      mobileCode: json['MobileCode'],

      isManager: json['IsManager'],
      isSelfService: json['IsSelfService'],
      isNFC: json['IsNFC'],
      bluetooth: json['Bluetooth'],
      geoUser: json['GeoUser'],
      nonGeoUser: json['NonGeoUser'],
      isleave: json['Isleave'],
      isManaul: json['IsManaul'],
      isBusiness: json['IsBusiness'],
      isWFH: json['IsWFH'],
      isCO: json['IsCO'],
      isSite: json['ISSite'],
      isIncident: json['ISIncident'],
      isAutoOutCheck: json['IsAutoOutCheck'],

      geoFenceType: json['GeoFenceType'],
      multipleGeoIds: json['MultipleGeoIds'],

      isPermissionReq: json['IsPermissionReq'],
      isTracking: json['IsTracking'],
      isPunching: json['IsPunching'],
      isPassword: json['IsPassword'],
      isLocationTrackingRequired:
      json['IsLocationTrackingRequired'],
      isLeaveAttachmentRequired:
      json['IsLeaveAttachmentRequired'],
      isBusinessTravelAttachmentRequired:
      json['IsBusinessTravelAttachmentRequired'],
      isFirstInLastOut: json['IsFirstInLastOut'],
      showOfficeLocation: json['showOfficeLocation'],
      offline: json['Offline'],
      allowOffline: json['allowOffline'],

      faceEmbedding: () {
        final raw = json['FaceEmbedding'];
        if (raw == null) return null;
        if (raw is List) {
          return List<double>.from(raw.map((e) => (e as num).toDouble()));
        }
        if (raw is String && raw.trim().isNotEmpty) {
          try {
            final parsed = jsonDecode(raw);
            if (parsed is List) {
              return List<double>.from(parsed.map((e) => (e as num).toDouble()));
            }
          } catch (_) {
            try {
              return raw
                  .replaceAll('[', '')
                  .replaceAll(']', '')
                  .split(',')
                  .map((e) => double.tryParse(e.trim()))
                  .whereType<double>()
                  .toList();
            } catch (_) {}
          }
        }
        return null;
      }(),

      isFaceEmbedding: json['IsFaceEmbedding'],
      isFaceRegister: json['IsFaceRegister'],
      realFace: json['RealFace'],
      employeeNo: json['EmployeeNo'],
      appVersion: json['App_Version'],
      iosAppVersion: json['IOSApp_Version'],
      isNewVersionNeeded: json['IsNewVersionNeeded'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'EmployeeID': employeeId,
      'Name': name,
      'Designation': designation,
      'GeofenceUser': geofenceUser,
      'Latitute': latitute,
      'Longitude': longitude,
      'Dimeter': dimeter,
      'CompanyName': companyName,
      'Department': department,
      'Gender': gender,
      'regImage': regImage,
      'Email': email,
      'Phone': phone,
      'DateofBirth': dateofBirth,
      'UserImage': userImage,
      'isAdmin': isAdmin,
      'CompanyID': companyId,
      'EnrollmentID': enrollmentId,
      'TrackingTime': trackingTime,
      'BioMatricTime': bioMatricTime,
      'DateofJoin': dateofJoin,
      'ManagerID': managerId,
      'MobileCode': mobileCode,

      'IsManager': isManager,
      'IsSelfService': isSelfService,
      'IsNFC': isNFC,
      'Bluetooth': bluetooth,
      'GeoUser': geoUser,
      'NonGeoUser': nonGeoUser,
      'Isleave': isleave,
      'IsManaul': isManaul,
      'IsBusiness': isBusiness,
      'IsWFH': isWFH,
      'IsCO': isCO,
      'ISSite': isSite,
      'ISIncident': isIncident,
      'IsAutoOutCheck': isAutoOutCheck,

      'GeoFenceType': geoFenceType,
      'MultipleGeoIds': multipleGeoIds,

      'IsPermissionReq': isPermissionReq,
      'IsTracking': isTracking,
      'IsPunching': isPunching,
      'IsPassword': isPassword,
      'IsLocationTrackingRequired': isLocationTrackingRequired,
      'IsLeaveAttachmentRequired': isLeaveAttachmentRequired,
      'IsBusinessTravelAttachmentRequired':
      isBusinessTravelAttachmentRequired,
      'IsFirstInLastOut': isFirstInLastOut,
      'showOfficeLocation': showOfficeLocation,
      'Offline': offline,
      'allowOffline': allowOffline,

      'FaceEmbedding': faceEmbedding,

      'IsFaceEmbedding': isFaceEmbedding,
      'IsFaceRegister': isFaceRegister,
      'RealFace': realFace,
      'EmployeeNo': employeeNo,
      'App_Version': appVersion,
      'IOSApp_Version': iosAppVersion,
      'IsNewVersionNeeded': isNewVersionNeeded,
    };
  }
}