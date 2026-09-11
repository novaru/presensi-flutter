import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';
import '../services/attendance_service.dart';
import '../services/location_service.dart';

/// Default camera when no GPS / record is available yet (Jakarta).
const _defaultCenter = LatLng(-6.2088, 106.8456);

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _authService = AuthService();
  final _attendanceService = AttendanceService();
  final _locationService = LocationService();
  final _mapController = MapController();

  bool _loading = false;
  bool _statusLoading = true;
  bool _mapReady = false;
  DateTime? _masukTime;
  DateTime? _keluarTime;
  LatLng? _masukPos;
  LatLng? _keluarPos;
  LatLng? _currentPos;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _loadTodayStatus();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadTodayStatus() async {
    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) setState(() => _statusLoading = false);
      return;
    }
    try {
      final today = await _attendanceService.getTodayAttendance(user.uid);
      if (!mounted) return;
      setState(() {
        _masukTime = today['masuk'] as DateTime?;
        _keluarTime = today['keluar'] as DateTime?;
        _masukPos = _toLatLng(today['masukLat'], today['masukLng']);
        _keluarPos = _toLatLng(today['keluarLat'], today['keluarLng']);
        _statusLoading = false;
      });
      _focusMap();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusLoading = false;
        _isError = true;
        _message = 'Gagal memuat status presensi hari ini.';
      });
    }
    // Live GPS preview for the map when nothing is recorded yet.
    // Failures (permission denied, GPS off) are ignored — map shows default.
    try {
      final position = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _currentPos = LatLng(position.latitude, position.longitude);
      });
      _focusMap();
    } catch (_) {
      // No preview available; recorded pins (if any) still show.
    }
  }

  LatLng? _toLatLng(dynamic lat, dynamic lng) {
    final la = (lat as num?)?.toDouble();
    final ln = (lng as num?)?.toDouble();
    if (la == null || ln == null) return null;
    return LatLng(la, ln);
  }

  bool get _masukDone => _masukTime != null;
  bool get _keluarDone => _keluarTime != null;

  /// Camera target priority: both records -> midpoint, one record -> that
  /// record, otherwise live GPS preview, otherwise default city.
  LatLng get _focusTarget {
    if (_masukPos != null && _keluarPos != null) {
      return LatLng(
        (_masukPos!.latitude + _keluarPos!.latitude) / 2,
        (_masukPos!.longitude + _keluarPos!.longitude) / 2,
      );
    }
    return _masukPos ?? _keluarPos ?? _currentPos ?? _defaultCenter;
  }

  void _focusMap() {
    if (!_mapReady) return;
    final hasRecord = _masukPos != null || _keluarPos != null;
    final target = _focusTarget;
    final zoom = hasRecord ? 15.0 : (_currentPos != null ? 16.0 : 11.0);
    _mapController.move(target, zoom);
  }

  Future<void> _checkIn(String type) async {
    // Guard against double records (UI level; service enforces it too).
    if (type == 'masuk' && _masukDone) {
      setState(() {
        _isError = true;
        _message = 'Sudah absen masuk hari ini.';
      });
      return;
    }
    if (type == 'keluar' && _keluarDone) {
      setState(() {
        _isError = true;
        _message = 'Sudah absen pulang hari ini.';
      });
      return;
    }
    if (type == 'keluar' && !_masukDone) {
      setState(() {
        _isError = true;
        _message = 'Absen masuk terlebih dahulu.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final position = await _locationService.getCurrentLocation();
      final user = _authService.currentUser!;
      await _attendanceService.recordAttendance(
        employeeId: user.uid,
        position: position,
        type: type,
      );
      // Optimistic update so the button disables and the pin appears
      // immediately even if serverTimestamp hasn't propagated yet.
      final now = DateTime.now();
      final pos = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _currentPos = pos;
        if (type == 'masuk') {
          _masukTime = _masukTime ?? now;
          _masukPos = _masukPos ?? pos;
        } else {
          _keluarTime = _keluarTime ?? now;
          _keluarPos = _keluarPos ?? pos;
        }
      });
      _focusMap();
      // Refresh from Firestore so info shows server time/coords.
      await _loadTodayStatus();
      if (!mounted) return;
      setState(() {
        _isError = false;
        _message = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _message = _friendlyError(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object e) {
    final raw = e.toString().replaceFirst('Exception: ', '');
    if (raw.contains('Sudah absen masuk') ||
        raw.contains('Sudah absen pulang') ||
        raw.contains('Belum absen masuk') ||
        raw.contains('Absen masuk')) {
      return raw;
    }
    return 'Gagal merekam presensi. Silakan coba lagi.';
  }

  String _formatTime(DateTime dt) => DateFormat('HH:mm:ss').format(dt);

  String _coordLabel(LatLng? pos) => pos == null
      ? '-'
      : '(${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})';

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h jam $m menit';
    if (m > 0) return '$m menit $s detik';
    return '$s detik';
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    if (_masukPos != null) {
      markers.add(
        Marker(
          point: _masukPos!,
          width: 44,
          height: 44,
          child: const Icon(Icons.location_on, color: Colors.green, size: 40),
        ),
      );
    }
    if (_keluarPos != null) {
      markers.add(
        Marker(
          point: _keluarPos!,
          width: 44,
          height: 44,
          child: const Icon(Icons.location_on, color: Colors.red, size: 40),
        ),
      );
    }
    // Live preview dot only before anything is recorded.
    if (_masukPos == null && _keluarPos == null && _currentPos != null) {
      markers.add(
        Marker(
          point: _currentPos!,
          width: 44,
          height: 44,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 32),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final masukInfo = _masukDone
        ? 'Masuk pada ${_formatTime(_masukTime!)}'
        : 'Belum absen masuk hari ini';
    final pulangInfo = _keluarDone
        ? 'Pulang pada ${_formatTime(_keluarTime!)}'
        : 'Belum absen pulang hari ini';
    final totalInfo = (_masukDone && _keluarDone)
        ? 'Total kehadiran ${_formatDuration(_keluarTime!.difference(_masukTime!))}'
        : 'Total kehadiran -';
    final markers = _buildMarkers();
    final hasAnyPin = markers.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Presensi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _authService.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('Logged in as: ${user?.email ?? '-'}',
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _statusLoading
                      ? const Center(
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.login, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(masukInfo)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.logout, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(pulangInfo)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(totalInfo)),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 220,
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: _focusTarget,
                              initialZoom: 15.0,
                              minZoom: 3.0,
                              maxZoom: 19.0,
                              onMapReady: () {
                                _mapReady = true;
                                _focusMap();
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.my_app',
                              ),
                              MarkerLayer(markers: markers),
                            ],
                          ),
                          if (!hasAnyPin && _statusLoading)
                            const Center(
                              child: Card(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Text('Memuat lokasi...'),
                                ),
                              ),
                            )
                          else if (!hasAnyPin && _currentPos == null)
                            const Center(
                              child: Card(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Text(
                                      'Belum ada lokasi — aktifkan GPS'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 16, color: Colors.green),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Masuk ${_coordLabel(_masukPos)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Pulang ${_coordLabel(_keluarPos)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_loading || _statusLoading || _masukDone)
                          ? null
                          : () => _checkIn('masuk'),
                      icon: const Icon(Icons.login),
                      label: const Text('Masuk'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_loading ||
                              _statusLoading ||
                              !_masukDone ||
                              _keluarDone)
                          ? null
                          : () => _checkIn('keluar'),
                      icon: const Icon(Icons.logout),
                      label: const Text('Keluar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_loading) const CircularProgressIndicator(),
              if (_message != null)
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _isError ? Colors.red : Colors.green),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
