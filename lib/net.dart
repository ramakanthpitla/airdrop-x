import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const discPort = 45454, xferPort = 45455;
const _chunk = 1 << 20; // 1 MiB reads
const _streams = 4; // parallel TCP streams for big files

class Peer {
  final String id, name;
  final InternetAddress ip;
  DateTime seen = DateTime.now();
  Peer(this.id, this.name, this.ip);
}

class _Rx {
  final File file;
  final RandomAccessFile raf;
  final int size, n;
  final got = <int, int>{};
  final done = <int>{};
  _Rx(this.file, this.raf, this.size, this.n);
}

class Net extends ChangeNotifier {
  final String id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final String name = Platform.localHostname.split('.').first;
  final Map<String, Peer> peers = {};
  double progress = 0;
  String status = 'Looking for nearby devices…';
  String? lastReceived;
  void Function(String)? onNotify;
  RawDatagramSocket? _udp;
  final _rx = <String, Future<_Rx>>{};
  int _lastUi = 0, _lastNote = 0;

  void _tick(double p, [bool force = false]) {
    progress = p.isNaN ? 0 : p.clamp(0, 1);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (force || now - _lastUi > 80) { _lastUi = now; notifyListeners(); }
    if (now - _lastNote > 1000) {
      _lastNote = now;
      onNotify?.call('$status ${(progress * 100).round()}%');
    }
  }

  Future<void> start() async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discPort, reuseAddress: true);
    } catch (e) {
      status = 'Discovery failed: $e';
      notifyListeners();
      return;
    }
    _udp!.broadcastEnabled = true;
    _udp!.listen((ev) {
      if (ev != RawSocketEvent.read) return;
      final d = _udp!.receive();
      if (d == null) return;
      final p = utf8.decode(d.data, allowMalformed: true).split('|');
      if (p.length != 3 || p[0] != 'ADX' || p[1] == id) return;
      final isNew = !peers.containsKey(p[1]);
      peers[p[1]] = Peer(p[1], p[2], d.address);
      if (isNew) notifyListeners();
    });
    Timer.periodic(const Duration(seconds: 2), (_) =>
        _udp?.send(utf8.encode('ADX|$id|$name'), InternetAddress('255.255.255.255'), discPort));
    Timer.periodic(const Duration(seconds: 3), (_) {
      final b = peers.length;
      peers.removeWhere((_, p) => DateTime.now().difference(p.seen).inSeconds > 8);
      if (peers.length != b) notifyListeners();
    });
    final srv = await ServerSocket.bind(InternetAddress.anyIPv4, xferPort, shared: true);
    srv.listen(_receive);
  }

  Future<Directory> _dir() async {
    if (Platform.isAndroid) return (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
    return (await getDownloadsDirectory()) ?? await getApplicationDocumentsDirectory();
  }

  Future<_Rx> _open(Map h) => _rx.putIfAbsent(h['id'], () async {
        final dir = await _dir();
        final n = (h['name'] as String).replaceAll(RegExp(r'[\\/]'), '_');
        var f = File('${dir.path}/$n');
        for (var i = 1; f.existsSync(); i++) { f = File('${dir.path}/($i) $n'); }
        final raf = await f.open(mode: FileMode.write);
        await raf.truncate(h['size']);
        status = 'Receiving $n';
        return _Rx(f, raf, h['size'], h['n']);
      });

  Future<void> _receive(Socket s) async {
    s.setOption(SocketOption.tcpNoDelay, true);
    final buf = BytesBuilder();
    _Rx? rx;
    var off = 0, len = 0, got = 0, idx = 0, finished = false;
    final sink = AccumulatorSink<Digest>();
    late ByteConversionSink conv;
    try {
      await for (final chunk in s) {
        if (finished) continue;
        Uint8List data = chunk;
        if (rx == null) {
          buf.add(chunk);
          final b = buf.takeBytes();
          final nl = b.indexOf(10);
          if (nl < 0) { buf.add(b); continue; }
          final h = jsonDecode(utf8.decode(b.sublist(0, nl))) as Map;
          rx = await _open(h);
          off = h['off']; len = h['len']; idx = h['i'];
          conv = sha256.startChunkedConversion(sink);
          data = Uint8List.sublistView(b, nl + 1);
        }
        final take = min(data.length, len - got);
        if (take > 0) {
          final part = Uint8List.sublistView(data, 0, take);
          conv.add(part);
          await rx.raf.setPosition(off + got);
          await rx.raf.writeFrom(part);
          got += take;
          rx.got[idx] = got;
          _tick(rx.got.values.fold<int>(0, (a, b) => a + b) / max(1, rx.size));
        }
        if (got >= len) {
          finished = true;
          conv.close();
          s.write('${sink.events.single}\n');
          await s.flush();
          rx.done.add(idx);
          if (rx.done.length == rx.n) {
            await rx.raf.close();
            _rx.remove(rx.file.path);
            lastReceived = rx.file.path;
            status = 'Received ${rx.file.uri.pathSegments.last} ✓';
            _tick(0, true);
          }
        }
      }
    } catch (_) {
      s.destroy();
    }
  }

  Future<bool> send(Peer p, File f) async {
    final size = await f.length();
    final n = size > (16 << 20) ? _streams : 1;
    final per = (size / n).ceil();
    final tid = '$id${DateTime.now().microsecondsSinceEpoch}';
    final sent = List<int>.filled(n, 0);
    status = 'Sending to ${p.name}…';
    _tick(0, true);
    final r = await Future.wait([
      for (var i = 0; i < n; i++)
        _range(p, f, tid, i, n, i * per, max(0, min(per, size - i * per)), size, sent)
    ]);
    final ok = r.every((e) => e);
    status = ok ? 'Sent ✓ (verified)' : 'Transfer failed';
    _tick(0, true);
    return ok;
  }

  Future<bool> _range(Peer p, File f, String tid, int i, int n, int off, int len, int size, List<int> sent) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      Socket? s;
      RandomAccessFile? raf;
      try {
        s = await Socket.connect(p.ip, xferPort, timeout: const Duration(seconds: 5));
        s.setOption(SocketOption.tcpNoDelay, true);
        raf = await f.open();
        await raf.setPosition(off);
        s.write('${jsonEncode({'id': tid, 'name': f.uri.pathSegments.last, 'size': size, 'n': n, 'i': i, 'off': off, 'len': len})}\n');
        final sink = AccumulatorSink<Digest>();
        final conv = sha256.startChunkedConversion(sink);
        final reply = s.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).first;
        unawaited(reply.then((_) {}, onError: (_) {}));
        var left = len;
        sent[i] = 0;
        while (left > 0) {
          final b = await raf.read(min(_chunk, left));
          if (b.isEmpty) break;
          conv.add(b);
          s.add(b);
          await s.flush();
          left -= b.length;
          sent[i] += b.length;
          _tick(sent.fold<int>(0, (a, b) => a + b) / max(1, size));
        }
        conv.close();
        final remote = await reply.timeout(const Duration(seconds: 30));
        if (remote == sink.events.single.toString()) return true;
      } catch (_) {
      } finally {
        s?.destroy();
        await raf?.close();
      }
      status = 'Retrying part ${i + 1} ($attempt/3)…';
      await Future.delayed(Duration(milliseconds: 300 * attempt));
    }
    return false;
  }
}
