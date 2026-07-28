import 'package:flutter/material.dart';
import 'package:fingerprint/fingerprint.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Map<String, dynamic>? _fingerprintWithLocation;
  Map<String, dynamic>? _detailedLocation;
  bool _isLoading = false;
  bool _isVPN = false;

  @override
  void initState() {
    super.initState();
    _getLocationInfo();
  }

  Future<void> _getLocationInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Một lần gọi là đủ: getFingerprintWithLocation đã gồm location + is_vpn
      // (tránh gọi mạng lặp lại như trước).
      final fingerprint = await FingerPrintUUID.getFingerprintWithLocation();

      setState(() {
        _fingerprintWithLocation = fingerprint;
        _detailedLocation = fingerprint['location'] as Map<String, dynamic>?;
        _isVPN = fingerprint['is_vpn'] == true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fingerprint Location Demo',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('🌍 Location Detection Demo'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // VPN Warning
                        if (_isVPN)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              border: Border.all(color: Colors.orange),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.warning, color: Colors.orange),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '⚠️ VPN/Proxy detected! Location may be inaccurate.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const Text(
                          '📍 Location Information',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (_detailedLocation != null) ...[
                          _buildLocationCard(
                            'Country',
                            _detailedLocation!['country'],
                          ),
                          _buildLocationCard(
                            'Region/State',
                            _detailedLocation!['region'],
                          ),
                          _buildLocationCard(
                            'City',
                            _detailedLocation!['city'],
                          ),
                          _buildLocationCard(
                            'Postal Code',
                            _detailedLocation!['postal'],
                          ),
                          _buildLocationCard(
                            'Timezone',
                            _detailedLocation!['timezone'],
                          ),
                          _buildLocationCard(
                            'ISP/Organization',
                            _detailedLocation!['org'],
                          ),

                          if (_detailedLocation!['coordinates'] != null) ...[
                            const SizedBox(height: 16),
                            const Text(
                              '🗺️ Coordinates:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Latitude: ${_detailedLocation!['latitude']}',
                                    ),
                                    Text(
                                      'Longitude: ${_detailedLocation!['longitude']}',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],

                        const SizedBox(height: 32),
                        const Text(
                          '🔑 Device Information',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (_fingerprintWithLocation != null) ...[
                          _buildInfoCard(
                            'Install ID (định danh chính, không trùng)',
                            _fingerprintWithLocation!['install_id'],
                          ),
                          _buildInfoCard(
                            'Hardware ID (có thể trùng trên máy clone)',
                            _fingerprintWithLocation!['hardware_id'],
                          ),
                          _buildInfoCard(
                            'Local IP',
                            _fingerprintWithLocation!['ip'],
                          ),
                          _buildInfoCard(
                            'Public IP',
                            _fingerprintWithLocation!['public_ip'],
                          ),
                        ],

                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _getLocationInfo,
                            child: const Text('🔄 Refresh Location'),
                          ),
                        ),

                        const SizedBox(height: 16),
                        const Text(
                          'ℹ️ How it works:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '• Gets your public IP address\n'
                          '• Uses IP geolocation to find location\n'
                          '• Detects VPN/Proxy usage\n'
                          '• Combines with device fingerprint',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }

  Widget _buildLocationCard(String title, dynamic value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value?.toString() ?? 'Unknown',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (value != null)
              const Icon(Icons.check_circle, color: Colors.green, size: 16)
            else
              const Icon(Icons.help_outline, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, dynamic value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              value?.toString() ?? 'null',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
