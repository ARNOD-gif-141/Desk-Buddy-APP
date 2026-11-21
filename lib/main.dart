// Arno Link v2 - control app for the ARNO OS Desk Buddy (Android)
// Created By- Arnod
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const svcUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
const rxUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
const txUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
const native = MethodChannel('arno/native');

const faceNames = [
  'Smirk', 'Winking Heart', 'Laughing', 'Crying', 'Enraged', 'Mind Blown', 'Starry Eyed', 'Thinking', 'Yawning', 'Skeptic',
  'Sweating', 'In Love', 'Determined', 'Boo', 'Silly', 'Cool', 'Ninja', 'Robot', 'Cat', 'Nerd',
  'Vampire', 'Ghost Panic', 'Angel', 'Devil', 'Money Eyes', 'Alien', 'Victorious', 'Teasing', 'Exhausted', 'Loading',
  'Glitch', 'Pixel Heart', 'Cyber Shield', 'Matrix Code', 'Neon Spiral', 'Equalizer', 'Radar', 'Battery Low', 'Charging', 'WiFi Search',
  'Bluetooth', 'Terminal', 'Skull', 'Crosshair', 'Gamepad', 'Rocket', 'Atom', 'Infinity', 'Biohazard', 'Radioactive',
  'Fire', 'Water Drop', 'Lightning', 'Snowflake', 'Sun Rays', 'Crescent Moon', 'Cloud Rain', 'Wind Gust', 'Compass', 'Bullseye',
  'Sleepy', 'Surprised', 'Kiss', 'Dizzy', 'Party Hat', 'Pirate', 'Sick', 'Normal', 'Coffee', 'Music Notes',
];
const faceEmoji = [
  '😏', '😘', '😂', '😢', '😡', '🤯', '🤩', '🤔', '🥱', '🤨',
  '😅', '😍', '😤', '👻', '😜', '😎', '🥷', '🤖', '🐱', '🤓',
  '🧛', '😱', '😇', '😈', '🤑', '👽', '✌️', '😛', '😩', '⏳',
  '📺', '❤️', '🛡️', '💻', '🌀', '🎚️', '📡', '🪫', '🔋', '📶',
  '🔷', '⌨️', '💀', '🎯', '🎮', '🚀', '⚛️', '♾️', '☣️', '☢️',
  '🔥', '💧', '⚡', '❄️', '☀️', '🌙', '🌧️', '💨', '🧭', '🎯',
  '😴', '😲', '😗', '😵', '🥳', '🏴‍☠️', '🤒', '🙂', '☕', '🎵',
];

const mediaPkgs = {
  'com.spotify.music', 'com.google.android.youtube', 'com.google.android.apps.youtube.music', 'com.vanced.android.youtube',
  'org.videolan.vlc', 'com.amazon.mp3', 'com.apple.android.music', 'in.startv.hotstar', 'com.netflix.mediaclient',
  'com.jio.media.jiobeats', 'com.gaana', 'com.mxtech.videoplayer.ad', 'com.soundcloud.android', 'deezer.android.app',
  'com.google.android.music', 'com.miui.player', 'com.sec.android.app.music', 'com.audiomack',
};
const skipPkgs = {'android', 'com.android.systemui', 'com.android.providers.downloads', 'com.google.android.gms', 'com.arnod.arno_link'};

String appName(String pkg) {
  const known = {
    'com.whatsapp': 'WhatsApp', 'com.whatsapp.w4b': 'WhatsApp Biz', 'com.instagram.android': 'Instagram',
    'org.telegram.messenger': 'Telegram', 'com.google.android.gm': 'Gmail', 'com.google.android.apps.messaging': 'Messages',
    'com.samsung.android.messaging': 'Messages', 'com.google.android.dialer': 'Phone', 'com.android.phone': 'Phone',
    'com.facebook.orca': 'Messenger', 'com.twitter.android': 'X', 'com.snapchat.android': 'Snapchat', 'com.discord': 'Discord',
    'com.spotify.music': 'Spotify', 'com.google.android.youtube': 'YouTube', 'com.google.android.apps.youtube.music': 'YT Music',
  };
  if (known.containsKey(pkg)) return known[pkg]!;
  final parts = pkg.split('.');
  final n = parts.isNotEmpty ? parts.last : pkg;
  return n.isEmpty ? pkg : n[0].toUpperCase() + n.substring(1);
}

class Ev {
  Ev(this.md, this.title);
  String md; // MM-DD
  String title;
  Map<String, dynamic> toJson() => {'d': md, 't': title};
  static Ev from(Map<String, dynamic> j) => Ev(j['d'] as String, j['t'] as String);
}

class Chat {
  Chat(this.me, this.text);
  final bool me;
  final String text;
}

// ---------------------------------------------------------------- link to the Desk Buddy
class Link extends ChangeNotifier {
  late SharedPreferences prefs;
  BluetoothDevice? dev;
  BluetoothCharacteristic? rx, tx;
  StreamSubscription? _stateSub, _valSub, _scanSub, _notifSub;
  bool connected = false, connecting = false, userStopped = false, fwd = true, ready = false;
  String status = 'Not connected';
  final Map<String, String> info = {};
  int face = 0;
  String phoneName = 'Phone';
  List<Ev> events = [];
  String gKey = '', gModel = 'gemini-2.5-flash';
  final List<Chat> chat = [];
  bool aiBusy = false;
  String musicTitle = '', musicApp = '';
  String _buf = '';
  Future<void> _chain = Future.value();
  int _retry = 0;
  Timer? _retryTimer;
  final Map<String, int> _recent = {};
  final List<String> _fwdQ = [];
  bool _fwdBusy = false;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    fwd = prefs.getBool('fwd') ?? true;
    gKey = prefs.getString('gkey') ?? '';
    gModel = prefs.getString('gmodel') ?? 'gemini-2.5-flash';
    final ev = prefs.getString('events');
    if (ev != null) {
      try { events = (jsonDecode(ev) as List).map((e) => Ev.from(e as Map<String, dynamic>)).toList(); } catch (_) {}
    }
    chat.add(Chat(false, 'Hi! I am Buddy AI v1. Ask me anything and I will answer here and on your Desk Buddy. Try: "show weather", "show time", "show dino game".'));
    ready = true;
    notifyListeners();
    await _perms();
    try { phoneName = await FlutterBluePlus.adapterName; } catch (_) {}
    if (phoneName.isEmpty) phoneName = 'Phone';
    _startNotifListener();
    connect();
  }

  Future<void> _perms() async {
    try { await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.notification, Permission.locationWhenInUse].request(); } catch (_) {}
  }

  void refresh() => notifyListeners();
  void _setStatus(String s) { status = s; notifyListeners(); }

  // ---- connection (own reconnect loop: works every time, no need to remove the phone's Bluetooth history)
  Future<void> connect() async {
    if (connecting || connected) return;
    userStopped = false; connecting = true; _retryTimer?.cancel();
    _setStatus('Looking for Desk Buddy...');
    try {
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        try { await FlutterBluePlus.turnOn(); } catch (_) {}
        await Future.delayed(const Duration(seconds: 1));
      }
      BluetoothDevice? found;
      final lastId = prefs.getString('lastId');
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((rs) {
        for (final r in rs) {
          final n = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
          if (n.startsWith('ARNO') || r.advertisementData.serviceUuids.contains(Guid(svcUuid))) found ??= r.device;
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      for (var i = 0; i < 90 && found == null && FlutterBluePlus.isScanningNow; i++) { await Future.delayed(const Duration(milliseconds: 100)); }
      try { await FlutterBluePlus.stopScan(); } catch (_) {}
      await _scanSub?.cancel();
      found ??= lastId != null ? BluetoothDevice.fromId(lastId) : null;
      if (found == null) throw 'Desk Buddy not found';
      await _open(found!);
    } catch (e) {
      connecting = false; connected = false;
      _setStatus('Not found - retrying...');
      _scheduleRetry();
    }
  }

  Future<void> _open(BluetoothDevice d) async {
    dev = d;
    await _stateSub?.cancel();
    _stateSub = d.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && (connected || connecting)) _lost();
    });
    _setStatus('Connecting...');
    try { await d.disconnect(); } catch (_) {}
    await d.connect(autoConnect: false, timeout: const Duration(seconds: 15));
    try { await d.clearGattCache(); } catch (_) {}
    try { await d.requestMtu(247); } catch (_) {}
    final svcs = await d.discoverServices();
    rx = null; tx = null;
    for (final s in svcs) {
      if (s.uuid == Guid(svcUuid)) {
        for (final c in s.characteristics) {
          if (c.uuid == Guid(rxUuid)) rx = c;
          if (c.uuid == Guid(txUuid)) tx = c;
        }
      }
    }
    if (rx == null || tx == null) throw 'Wrong device';
    await _valSub?.cancel();
    _buf = '';
    _valSub = tx!.onValueReceived.listen(_onBytes);
    await tx!.setNotifyValue(true);
    await prefs.setString('lastId', d.remoteId.str);
    connected = true; connecting = false; _retry = 0;
    _setStatus('Connected');
    send('PN|$phoneName');
    await Future.delayed(const Duration(milliseconds: 250));
    send('I?');
    send('EV?');
    if (gKey.isNotEmpty) send('GK|$gKey');
    send('GM|$gModel');
    syncEvents();
  }

  void _lost() {
    connected = false; connecting = false; rx = null; tx = null; _valSub?.cancel();
    _setStatus(userStopped ? 'Disconnected' : 'Connection lost - reconnecting...');
    if (!userStopped) _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final wait = Duration(seconds: (2 + _retry * 2).clamp(2, 12));
    _retry++;
    _retryTimer = Timer(wait, () { if (!connected && !connecting && !userStopped) connect(); });
  }

  Future<void> disconnect() async {
    userStopped = true; _retryTimer?.cancel();
    try { await dev?.disconnect(); } catch (_) {}
    connected = false; connecting = false;
    _setStatus('Disconnected');
  }

  // ---- protocol
  void send(String s) {
    if (rx == null || !connected) return;
    final c = rx!;
    _chain = _chain.then((_) async {
      try { await c.write(utf8.encode('$s\n'), withoutResponse: false, allowLongWrite: true); } catch (_) {}
    });
  }

  void _onBytes(List<int> b) {
    _buf += utf8.decode(b, allowMalformed: true);
    int i;
    while ((i = _buf.indexOf('\n')) >= 0) {
      final line = _buf.substring(0, i).trim();
      _buf = _buf.substring(i + 1);
      if (line.isNotEmpty) _onLine(line);
    }
    if (_buf.length > 600) _buf = '';
  }

  void _onLine(String l) {
    final p = l.split('|');
    if (p.length < 2) return;
    switch (p[0]) {
      case 'I': info[p[1]] = p.length > 2 ? p.sublist(2).join('|') : ''; break;
      case 'S':
        if (p[1] == 'cd') { _toast('Timer completed', 'Your timer on the Desk Buddy is done.'); }
        else { face = int.tryParse(p[1]) ?? face; }
        break;
      case 'G': _toast('Desk Buddy', p.sublist(1).join('|')); break;
      case 'M': _toast('Desk Buddy', p.sublist(1).join('|')); break;
      case 'C':
        if (p[1] == 'PP') media('pp');
        if (p[1] == 'MUSIC1') _sendNow();
        break;
      default: break;
    }
    notifyListeners();
  }

  Future<void> _toast(String t, String b) async { try { await native.invokeMethod('notify', {'title': t, 'body': b}); } catch (_) {} }
  Future<void> media(String k) async { try { await native.invokeMethod('media', {'key': k}); } catch (_) {} }

  // ---- events
  void syncEvents() {
    if (!connected) return;
    send('EV|CLR');
    for (final e in events) { send('EV|ADD|${e.md}|${e.title}'); }
  }
  Future<void> saveEvents() async { await prefs.setString('events', jsonEncode(events.map((e) => e.toJson()).toList())); syncEvents(); notifyListeners(); }

  // ---- settings
  Future<void> setKey(String k, String model) async {
    gKey = k.trim(); gModel = model.trim().isEmpty ? 'gemini-2.5-flash' : model.trim();
    await prefs.setString('gkey', gKey); await prefs.setString('gmodel', gModel);
    send('GK|$gKey'); send('GM|$gModel'); notifyListeners();
  }
  Future<void> setFwd(bool v) async { fwd = v; await prefs.setBool('fwd', v); notifyListeners(); }

  // ---- Buddy AI
  Future<String> gemini(String q) async {
    if (gKey.isEmpty) return 'No Gemini key yet - add it in Settings.';
    final express = gKey.startsWith('AQ.');
    for (var attempt = 0; attempt < 2; attempt++) {
      final url = express
          ? 'https://aiplatform.googleapis.com/v1/publishers/google/models/$gModel:generateContent'
          : 'https://generativelanguage.googleapis.com/v1beta/models/$gModel:generateContent?key=$gKey';
      final body = {
        'contents': [{'role': 'user', 'parts': [{'text': 'You are Buddy AI, a friendly desk companion. Answer briefly (under 250 characters, plain text, no markdown).\n\n$q'}]}],
        'generationConfig': {'maxOutputTokens': 400, if (attempt == 0) 'thinkingConfig': {'thinkingBudget': 0}},
      };
      try {
        final r = await http.post(Uri.parse(url),
            headers: {'Content-Type': 'application/json', if (express) 'x-goog-api-key': gKey}, body: jsonEncode(body)).timeout(const Duration(seconds: 25));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body);
          final t = j['candidates'][0]['content']['parts'][0]['text'] as String;
          return t.trim();
        }
        if (r.statusCode != 400) return 'AI error ${r.statusCode}. Check the key in Settings.';
      } catch (e) { return 'No internet or AI error.'; }
    }
    return 'AI error. Check the key/model in Settings.';
  }

  static const _quick = <String, String>{
    'forecast': 'MFORECAST', 'weather': 'MWEATHER', 'analog': 'MCLOCK', 'clock': 'MCLOCK', 'time': 'MTIME', 'dino': 'MDINO', 'game': 'MDINO',
    'sleep': 'MSLEEP', 'system info': 'MINFO', 'info': 'MINFO', 'location': 'MLOC', 'music': 'MMUSIC', 'stopwatch': 'MSW', 'timer': 'MCD',
  };
  Future<void> ask(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    chat.add(Chat(true, q));
    final low = q.toLowerCase();
    if (RegExp(r'^(show|open|go to|switch to|display|play|start)\b').hasMatch(low) || low == 'weather' || low == 'time') {
      for (final e in _quick.entries) {
        if (low.contains(e.key)) {
          send(e.value);
          chat.add(Chat(false, connected ? 'Done - showing "${e.key}" on the Desk Buddy.' : 'Desk Buddy is not connected.'));
          notifyListeners();
          return;
        }
      }
    }
    notifyListeners();
    aiBusy = true; notifyListeners();
    final a = await gemini(q);
    aiBusy = false;
    chat.add(Chat(false, a));
    if (connected) {
      final short = a.length > 280 ? a.substring(0, 280) : a;
      send('A|${q.replaceAll('|', ' ').substring(0, q.length > 40 ? 40 : q.length)}|${short.replaceAll('\n', ' ').replaceAll('|', '/')}');
    }
    notifyListeners();
  }

  // ---- phone notifications -> Desk Buddy
  Future<void> _startNotifListener() async {
    try {
      var ok = await NotificationListenerService.isPermissionGranted();
      if (!ok) ok = await NotificationListenerService.requestPermission();
      if (!ok) return;
      _notifSub?.cancel();
      _notifSub = NotificationListenerService.notificationsStream.listen(_onNotif);
    } catch (_) {}
  }
  Future<bool> notifAccess() async { try { return await NotificationListenerService.isPermissionGranted(); } catch (_) { return false; } }
  Future<void> openNotifAccess() async { await _startNotifListener(); notifyListeners(); }

  void _onNotif(ServiceNotificationEvent e) {
    final pkg = e.packageName ?? '';
    if (skipPkgs.contains(pkg)) return;
    final title = (e.title ?? '').trim(), text = (e.content ?? '').trim();
    if (mediaPkgs.contains(pkg)) {   // media players -> now playing
      if (e.hasRemoved == true) { if (musicApp == appName(pkg)) { send('MU|2|||'); musicTitle = ''; } }
      else if (title.isNotEmpty) { musicTitle = title; musicApp = appName(pkg); _musicSend(1, text); }
      return;
    }
    if (!fwd || !connected || e.hasRemoved == true) return;
    if (title.isEmpty && text.isEmpty) return;
    final key = '$pkg|$title|$text';
    final now = DateTime.now().millisecondsSinceEpoch;
    _recent.removeWhere((_, t) => now - t > 8000);
    if (_recent.containsKey(key)) return;
    _recent[key] = now;
    String c(String s, int n) => (s.length > n ? s.substring(0, n) : s).replaceAll('|', '/').replaceAll('\n', ' ');
    _fwdQ.add('N|${c(appName(pkg), 18)}|${c(title, 30)}|${c(text, 160)}');
    if (_fwdQ.length > 6) _fwdQ.removeAt(0);
    _drainFwd();
  }
  Future<void> _drainFwd() async {
    if (_fwdBusy) return;
    _fwdBusy = true;
    while (_fwdQ.isNotEmpty) { send(_fwdQ.removeAt(0)); await Future.delayed(const Duration(milliseconds: 700)); }
    _fwdBusy = false;
  }
  void _musicSend(int st, String artist) {
    String c(String s, int n) => (s.length > n ? s.substring(0, n) : s).replaceAll('|', '/').replaceAll('\n', ' ');
    send('MU|$st|${c(musicApp, 20)}|${c(musicTitle, 60)}|${c(artist, 36)}');
  }
  void _sendNow() { if (musicTitle.isNotEmpty) _musicSend(1, ''); else send('MU|2|||'); }
}

final link = Link();
final accent = ValueNotifier<int>(0xFF1FB5C9);
final dark = ValueNotifier<bool>(true);
final textScale = ValueNotifier<double>(1.0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final p = await SharedPreferences.getInstance();
  accent.value = p.getInt('accent') ?? 0xFF1FB5C9;
  dark.value = p.getBool('dark') ?? true;
  textScale.value = p.getDouble('tscale') ?? 1.0;
  runApp(const ArnoApp());
}

class ArnoApp extends StatelessWidget {
  const ArnoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([accent, dark, textScale]),
      builder: (_, __) {
        final seed = Color(accent.value);
        return MaterialApp(
          title: 'Arno Link',
          debugShowCheckedModeBanner: false,
          themeMode: dark.value ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light)),
          darkTheme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: const Color(0xFF08121B), colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark, surface: const Color(0xFF0E1D2B))),
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale.value)), child: w!),
          home: const Home(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- UI
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  @override
  void initState() { super.initState(); link.init(); }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (_, __) {
        final pages = [const ControlPage(), const FacesPage(), const AiPage(), const EventsPage(), const SettingsPage()];
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('Arno Link', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('Created By- Arnod', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
            ]),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: (link.connected ? Colors.green : Colors.orange).withOpacity(.18), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(link.connected ? Icons.bluetooth_connected : Icons.bluetooth_searching, size: 16, color: link.connected ? Colors.green : Colors.orange),
                  const SizedBox(width: 5),
                  Text(link.connected ? 'Connected' : (link.connecting ? 'Connecting' : 'Offline'), style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ],
          ),
          body: SafeArea(child: pages[tab]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            backgroundColor: cs.surface,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Control'),
              NavigationDestination(icon: Icon(Icons.emoji_emotions_outlined), selectedIcon: Icon(Icons.emoji_emotions), label: 'Faces'),
              NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Buddy AI'),
              NavigationDestination(icon: Icon(Icons.event_outlined), selectedIcon: Icon(Icons.event), label: 'Events'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}

Widget sectionTitle(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 8), child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)));

class Tile extends StatelessWidget {
  const Tile(this.icon, this.label, this.onTap, {super.key});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withOpacity(.55), borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: cs.primary), const SizedBox(height: 4), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))]),
      ),
    );
  }
}

// ---------------- Control ----------------
class ControlPage extends StatefulWidget {
  const ControlPage({super.key});
  @override
  State<ControlPage> createState() => _ControlState();
}

class _ControlState extends State<ControlPage> {
  final msg = TextEditingController();
  final cdMin = TextEditingController(text: '5');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i = link.info;
    return ListView(padding: const EdgeInsets.all(14), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(faceEmoji[link.face.clamp(0, faceEmoji.length - 1)], style: const TextStyle(fontSize: 38)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(link.connected ? (i['dev'] ?? 'Desk Buddy') : 'Desk Buddy', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(link.status, style: TextStyle(color: cs.onSurfaceVariant)),
              ])),
              FilledButton.tonal(onPressed: link.connected ? link.disconnect : () => link.connect(), child: Text(link.connected ? 'Disconnect' : 'Connect')),
            ]),
            if (link.connected) ...[
              const Divider(height: 22),
              Wrap(spacing: 16, runSpacing: 4, children: [
                _kv('User', i['user']), _kv('OS', i['os']), _kv('WiFi', i['wifi']), _kv('Signal', i['rssi']), _kv('IP', i['ip']), _kv('RAM', i['ram']), _kv('Firmware', i['fw']), _kv('By', 'Arnod'),
              ]),
              TextButton.icon(onPressed: () => link.send('I?'), icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh')),
            ],
          ]),
        ),
      ),
      sectionTitle('Virtual touch pads'),
      Row(children: [
        Expanded(child: _pad('LEFT PAD', 'L', 3000)),
        const SizedBox(width: 12),
        Expanded(child: _pad('RIGHT PAD', 'R', 1000)),
      ]),
      sectionTitle('Dino game'),
      Row(children: [
        Expanded(child: FilledButton.tonalIcon(onPressed: () => link.send('MDINO'), icon: const Icon(Icons.sports_esports), label: const Text('Open'))),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: FilledButton.icon(onPressed: () { HapticFeedback.mediumImpact(); link.send('PAD|L|1'); }, icon: const Icon(Icons.arrow_upward), label: const Text('JUMP / START'))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton.tonalIcon(onPressed: () => link.send('PAD|R|1'), icon: const Icon(Icons.close), label: const Text('Quit'))),
      ]),
      sectionTitle('Show on Desk Buddy'),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.05, children: [
        Tile(Icons.access_time, 'Time', () => link.send('MTIME')),
        Tile(Icons.schedule, 'Analog', () => link.send('MCLOCK')),
        Tile(Icons.wb_sunny_outlined, 'Weather', () => link.send('MWEATHER')),
        Tile(Icons.calendar_view_week, '3-Day', () => link.send('MFORECAST')),
        Tile(Icons.place_outlined, 'Location', () => link.send('MLOC')),
        Tile(Icons.info_outline, 'Sys Info', () => link.send('MINFO')),
        Tile(Icons.bedtime_outlined, 'Sleep clock', () => link.send('MSLEEP')),
        Tile(Icons.nights_stay_outlined, 'Sleepy face', () => link.send('MSLEEPY')),
        Tile(Icons.menu_book_outlined, 'Right manual', () => link.send('MMAN1')),
        Tile(Icons.menu_book, 'Left manual', () => link.send('MMAN2')),
        Tile(Icons.timer_outlined, 'Stopwatch', () => link.send('MSW')),
        Tile(Icons.hourglass_bottom, 'Countdown', () => link.send('MCD')),
      ]),
      sectionTitle('Music control'),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Text(link.musicTitle.isEmpty ? 'Nothing playing on this phone' : '${link.musicApp}: ${link.musicTitle}', maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          IconButton.filledTonal(onPressed: () => link.media('prev'), icon: const Icon(Icons.skip_previous)),
          IconButton.filled(iconSize: 32, onPressed: () => link.media('pp'), icon: const Icon(Icons.play_arrow)),
          IconButton.filledTonal(onPressed: () => link.media('next'), icon: const Icon(Icons.skip_next)),
          FilledButton.tonalIcon(onPressed: () => link.send('MMUSIC'), icon: const Icon(Icons.music_note), label: const Text('Show on buddy')),
        ]),
      ]))),
      sectionTitle('Timer & stopwatch'),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: cdMin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Countdown minutes', border: OutlineInputBorder(), isDense: true))),
          const SizedBox(width: 8),
          FilledButton(onPressed: () { final m = double.tryParse(cdMin.text) ?? 0; link.send('CD${(m * 60).round()}'); }, child: const Text('Start')),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: () => link.send('CD0'), child: const Text('Stop')),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          FilledButton.tonal(onPressed: () => link.send('SW1'), child: const Text('Stopwatch start')),
          FilledButton.tonal(onPressed: () => link.send('SW0'), child: const Text('Stop')),
          FilledButton.tonal(onPressed: () => link.send('SWR'), child: const Text('Reset')),
        ]),
      ]))),
      sectionTitle('Send text to Desk Buddy'),
      Row(children: [
        Expanded(child: TextField(controller: msg, decoration: const InputDecoration(hintText: 'Type a message', border: OutlineInputBorder(), isDense: true))),
        const SizedBox(width: 8),
        FilledButton(onPressed: () { final t = msg.text.trim(); if (t.isNotEmpty) { link.send('T|${t.replaceAll('\n', ' ')}'); msg.clear(); } }, child: const Icon(Icons.send)),
      ]),
      const SizedBox(height: 24),
    ]);
  }

  Widget _kv(String k, String? v) => Text.rich(TextSpan(children: [TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w600)), TextSpan(text: v ?? '-')]), style: const TextStyle(fontSize: 13));

  Widget _pad(String name, String side, int holdMs) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      GestureDetector(
        onTap: () { HapticFeedback.mediumImpact(); link.send('PAD|$side|1'); },
        child: Container(
          height: 110, width: double.infinity,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary.withOpacity(.85), cs.primaryContainer]), borderRadius: BorderRadius.circular(22)),
          alignment: Alignment.center,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.touch_app, size: 34, color: cs.onPrimary), const SizedBox(height: 4),
            Text(name, style: TextStyle(fontWeight: FontWeight.w800, color: cs.onPrimary)), Text('tap = 1 tap', style: TextStyle(fontSize: 11, color: cs.onPrimary)),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 4, children: [
        for (final n in (side == 'L' ? [2, 3, 4, 5] : [2, 3, 4]))
          ActionChip(label: Text('${n}x'), visualDensity: VisualDensity.compact, onPressed: () => link.send('PAD|$side|$n')),
        ActionChip(label: Text(side == 'L' ? 'hold 3s' : 'hold 1s'), visualDensity: VisualDensity.compact, onPressed: () => link.send('PAD|$side|H')),
        if (side == 'R') ActionChip(label: const Text('hold 5s'), visualDensity: VisualDensity.compact, onPressed: () => link.send('PAD|R|L')),
      ]),
    ]);
  }
}

// ---------------- Faces ----------------
class FacesPage extends StatelessWidget {
  const FacesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.05),
      itemCount: faceNames.length,
      itemBuilder: (_, i) {
        final sel = link.face == i;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () { link.send('F$i'); link.face = i; link.refresh(); },
          child: Container(
            decoration: BoxDecoration(color: sel ? cs.primaryContainer : cs.surfaceContainerHighest.withOpacity(.5), borderRadius: BorderRadius.circular(14), border: sel ? Border.all(color: cs.primary, width: 2) : null),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(faceEmoji[i], style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 4),
              Text('${i + 1}. ${faceNames[i]}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
      },
    );
  }
}

// ---------------- Buddy AI ----------------
class AiPage extends StatefulWidget {
  const AiPage({super.key});
  @override
  State<AiPage> createState() => _AiState();
}

class _AiState extends State<AiPage> {
  final c = TextEditingController();
  final sc = ScrollController();

  Future<void> _go() async {
    final t = c.text; c.clear();
    final f = link.ask(t);
    Future.delayed(const Duration(milliseconds: 200), _down);
    await f; _down();
  }
  void _down() { if (sc.hasClients) sc.animateTo(sc.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Row(children: [
          const Icon(Icons.auto_awesome), const SizedBox(width: 8),
          const Text('Buddy AI v1', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(link.gKey.isEmpty ? 'add key in Settings' : 'Gemini ready', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          controller: sc, padding: const EdgeInsets.all(12), itemCount: link.chat.length + (link.aiBusy ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= link.chat.length) return const Padding(padding: EdgeInsets.all(8), child: Align(alignment: Alignment.centerLeft, child: Text('Thinking...')));
            final m = link.chat[i];
            return Align(
              alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(11),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
                decoration: BoxDecoration(color: m.me ? cs.primaryContainer : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                child: SelectableText(m.text),
              ),
            );
          },
        ),
      ),
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
          for (final s in ['show weather', 'show time', 'show 3 day forecast', 'show dino game', 'show location', 'show music'])
            Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text(s), onPressed: () { c.text = s; _go(); })),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Row(children: [
          Expanded(child: TextField(controller: c, onSubmitted: (_) => _go(), textInputAction: TextInputAction.send, decoration: const InputDecoration(hintText: 'Ask anything or type "show weather"...', border: OutlineInputBorder(), isDense: true))),
          const SizedBox(width: 8),
          FilledButton(onPressed: _go, child: const Icon(Icons.send)),
        ]),
      ),
    ]);
  }
}

// ---------------- Events ----------------
class EventsPage extends StatelessWidget {
  const EventsPage({super.key});
  static const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  Future<void> _add(BuildContext context) async {
    final t = TextEditingController();
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100), helpText: 'Pick the day (year is ignored - repeats every year)');
    if (d == null || !context.mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Event on ${d.day} ${months[d.month - 1]}'),
      content: TextField(controller: t, autofocus: true, maxLength: 28, decoration: const InputDecoration(hintText: 'e.g. Arnod Birthday')),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add'))],
    ));
    if (ok == true && t.text.trim().isNotEmpty) {
      link.events.add(Ev('${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}', t.text.trim().replaceAll('|', ' ')));
      link.events.sort((a, b) => a.md.compareTo(b.md));
      await link.saveEvents();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _add(context), icon: const Icon(Icons.add), label: const Text('Add event')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text('Events & birthdays', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('When you switch the Desk Buddy on during an event day and it is online, it greets you with a Gemini message (needs the Gemini key in Settings).', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        if (link.events.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No events yet'))),
        for (var i = 0; i < link.events.length; i++)
          Card(child: ListTile(
            leading: CircleAvatar(child: Text(link.events[i].md.substring(3))),
            title: Text(link.events[i].title),
            subtitle: Text('${months[int.parse(link.events[i].md.substring(0, 2)) - 1]} ${link.events[i].md.substring(3)} - every year'),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { link.events.removeAt(i); link.saveEvents(); }),
          )),
        TextButton.icon(onPressed: link.connected ? link.syncEvents : null, icon: const Icon(Icons.sync), label: const Text('Sync to Desk Buddy now')),
        const SizedBox(height: 70),
      ]),
    );
  }
}

// ---------------- Settings ----------------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  late final user = TextEditingController(text: link.info['user'] ?? '');
  late final devName = TextEditingController(text: link.info['dev'] ?? '');
  late final key = TextEditingController(text: link.gKey);
  late final model = TextEditingController(text: link.gModel);
  bool hasAccess = false;

  @override
  void initState() { super.initState(); link.notifAccess().then((v) { if (mounted) setState(() => hasAccess = v); }); }

  Future<void> _slot(int k) async {
    final s = TextEditingController(text: (link.info['w$k'] ?? '-') == '-' ? '' : link.info['w$k']);
    final p = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('WiFi slot ${k + 1}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: s, decoration: const InputDecoration(labelText: 'Network name (SSID)')),
        TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
    ));
    if (ok == true && s.text.trim().isNotEmpty) { link.send('WS|$k|${s.text.trim()}|${p.text}'); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const colors = [0xFF1FB5C9, 0xFF4CAF50, 0xFFFF9800, 0xFFE91E63, 0xFF7C4DFF, 0xFFF44336, 0xFF2196F3];
    final off = !link.connected;
    return ListView(padding: const EdgeInsets.all(14), children: [
      sectionTitle('Desk Buddy identity'),
      TextField(controller: user, decoration: InputDecoration(labelText: 'Your name', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.check), onPressed: off ? null : () => link.send('SU|${user.text.trim()}')))),
      const SizedBox(height: 10),
      TextField(controller: devName, decoration: InputDecoration(labelText: 'Device name', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.check), onPressed: off ? null : () => link.send('SD|${devName.text.trim()}')))),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: off ? null : () => link.send('TZ|${DateTime.now().timeZoneOffset.inMinutes}'), icon: const Icon(Icons.public), label: const Text('Use phone time zone'))),
      ]),
      sectionTitle('WiFi networks (up to 4)'),
      for (var k = 0; k < 4; k++)
        Card(child: ListTile(
          leading: const Icon(Icons.wifi),
          title: Text((link.info['w$k'] ?? '-') == '-' ? 'Slot ${k + 1}: empty' : link.info['w$k']!),
          subtitle: Text('Slot ${k + 1}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit), onPressed: off ? null : () => _slot(k)),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: off || (link.info['w$k'] ?? '-') == '-' ? null : () => link.send('WD|$k')),
          ]),
        )),
      if (off) const Text('Connect to the Desk Buddy to change WiFi, name and device settings.', style: TextStyle(fontSize: 12)),
      sectionTitle('Gemini AI (events + Buddy AI)'),
      TextField(controller: key, obscureText: true, decoration: const InputDecoration(labelText: 'Gemini API key', border: OutlineInputBorder(), helperText: 'Stored only on this phone and your Desk Buddy')),
      const SizedBox(height: 10),
      TextField(controller: model, decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder())),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: () async { await link.setKey(key.text, model.text); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gemini settings saved'))); }, icon: const Icon(Icons.save), label: const Text('Save key')),
      sectionTitle('Phone notifications on Desk Buddy'),
      SwitchListTile(value: link.fwd, onChanged: link.setFwd, title: const Text('Forward notifications'), subtitle: const Text('Shows WhatsApp, calls, messages... on the Desk Buddy')),
      ListTile(
        leading: Icon(hasAccess ? Icons.check_circle : Icons.error_outline, color: hasAccess ? Colors.green : Colors.orange),
        title: Text(hasAccess ? 'Notification access granted' : 'Notification access needed'),
        subtitle: const Text('Also set battery to "Unrestricted" for Arno Link so it keeps working in the background.'),
        trailing: TextButton(onPressed: () async { await link.openNotifAccess(); final v = await link.notifAccess(); if (mounted) setState(() => hasAccess = v); }, child: Text(hasAccess ? 'Re-check' : 'Grant')),
      ),
      sectionTitle('Customize the app'),
      SwitchListTile(value: dark.value, onChanged: (v) async { dark.value = v; (await SharedPreferences.getInstance()).setBool('dark', v); setState(() {}); }, title: const Text('Dark mode')),
      const Text('Accent colour'),
      const SizedBox(height: 6),
      Wrap(spacing: 10, children: [
        for (final c in colors)
          GestureDetector(
            onTap: () async { accent.value = c; (await SharedPreferences.getInstance()).setInt('accent', c); setState(() {}); },
            child: CircleAvatar(radius: 17, backgroundColor: Color(c), child: accent.value == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null),
          ),
      ]),
      const SizedBox(height: 10),
      Text('Text size: ${(textScale.value * 100).round()}%'),
      Slider(value: textScale.value, min: .85, max: 1.3, divisions: 9, onChanged: (v) => textScale.value = v, onChangeEnd: (v) async { (await SharedPreferences.getInstance()).setDouble('tscale', v); setState(() {}); }),
      sectionTitle('Device'),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: off ? null : () => link.send('RB'), icon: const Icon(Icons.restart_alt), label: const Text('Restart'))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: cs.error),
          onPressed: off ? null : () async {
            final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Erase settings?'), content: const Text('Deletes name, WiFi and keys on the Desk Buddy. The firmware stays and the setup page returns.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Erase'))]));
            if (ok == true) link.send('ERASE');
          },
          icon: const Icon(Icons.delete_forever), label: const Text('Erase'))),
      ]),
      const SizedBox(height: 18),
      Center(child: Text('Arno Link v2 - Created By- Arnod', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
      const SizedBox(height: 20),
    ]);
  }
}
