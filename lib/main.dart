import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'net.dart';
import 'service.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF4F8CFF)),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final net = Net();
  @override
  void initState() {
    super.initState();
    Background.start().then((_) {
      net.onNotify = Background.notify;
      net.start();
    });
  }

  Future<void> _send(Peer p) async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null) return;
    for (final f in r.files.where((f) => f.path != null)) {
      await net.send(p, File(f.path!));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF0B1220), Color(0xFF16284D)])),
          child: SafeArea(
            child: ListenableBuilder(
              listenable: net,
              builder: (_, __) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('AirDrop X', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                  Text('Visible as “${net.name}”', style: const TextStyle(color: Colors.white60)),
                  const SizedBox(height: 28),
                  Expanded(
                    child: net.peers.isEmpty
                        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(height: 16),
                            Text('Searching nearby…\nSame Wi-Fi or hotspot required',
                                textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                          ]))
                        : ListView(children: [
                            for (final p in net.peers.values)
                              Card(
                                color: Colors.white10, elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: const CircleAvatar(radius: 24, child: Icon(Icons.devices)),
                                  title: Text(p.name, style: const TextStyle(fontSize: 18)),
                                  subtitle: Text(p.ip.address),
                                  trailing: const Icon(Icons.send_rounded),
                                  onTap: () => _send(p),
                                ),
                              ),
                          ]),
                  ),
                  if (net.progress > 0)
                    Padding(padding: const EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(value: net.progress, minHeight: 8,
                            borderRadius: BorderRadius.circular(8))),
                  Row(children: [
                    Expanded(child: Text(net.status, style: const TextStyle(color: Colors.white70))),
                    if (net.lastReceived != null)
                      TextButton(onPressed: () => OpenFilex.open(net.lastReceived!), child: const Text('Open')),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      );
}
