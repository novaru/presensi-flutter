import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class AttendanceService {
  final _attendance = FirebaseFirestore.instance.collection('attendance');

  /// Writes one attendance record: who, when, where, and which type
  /// ('masuk' = check-in, 'keluar' = check-out).
  /// Each type can only be recorded once per day per employee.
  Future<void> recordAttendance({
    required String employeeId,
    required Position position,
    required String type,
  }) async {
    final today = await getTodayAttendance(employeeId);
    if (type == 'masuk' && today['masuk'] != null) {
      throw Exception('Sudah absen masuk hari ini.');
    }
    if (type == 'keluar') {
      if (today['masuk'] == null) {
        throw Exception('Belum absen masuk hari ini.');
      }
      if (today['keluar'] != null) {
        throw Exception('Sudah absen pulang hari ini.');
      }
    }
    await _attendance.add({
      'employeeId': employeeId,
      'type': type,
      'lat': position.latitude,
      'lng': position.longitude,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Returns today's check-in/out for [employeeId].
  /// Keys: 'masuk'/'keluar' ([DateTime] or null),
  /// 'masukLat'/'masukLng'/'keluarLat'/'keluarLng' ([double] or null).
  Future<Map<String, dynamic>> getTodayAttendance(String employeeId) async {
    final snapshot =
        await _attendance.where('employeeId', isEqualTo: employeeId).get();

    final now = DateTime.now();
    DateTime? masuk;
    DateTime? keluar;
    double? masukLat;
    double? masukLng;
    double? keluarLat;
    double? keluarLng;

    final todayDocs = snapshot.docs.where((doc) {
      final data = doc.data();
      final ts = data['timestamp'];
      if (ts is! Timestamp) return false;
      final dt = ts.toDate();
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList()
      ..sort((a, b) {
        final aTs = a.data()['timestamp'] as Timestamp;
        final bTs = b.data()['timestamp'] as Timestamp;
        return aTs.compareTo(bTs);
      });

    for (final doc in todayDocs) {
      final data = doc.data();
      final dt = (data['timestamp'] as Timestamp).toDate();
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (data['type'] == 'masuk' && masuk == null) {
        masuk = dt;
        masukLat = lat;
        masukLng = lng;
      } else if (data['type'] == 'keluar') {
        // Keep the latest keluar record.
        keluar = dt;
        keluarLat = lat;
        keluarLng = lng;
      }
    }
    return {
      'masuk': masuk,
      'keluar': keluar,
      'masukLat': masukLat,
      'masukLng': masukLng,
      'keluarLat': keluarLat,
      'keluarLng': keluarLng,
    };
  }
}
