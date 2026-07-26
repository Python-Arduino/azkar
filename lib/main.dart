import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==========================================
// 1. MAIN ENTRY POINT
// ==========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة الإشعارات والصوت
  await ReminderService().init();
  
  // تهيئة خدمة الخلفية
  await ReminderService.setupBackgroundService();
  
  runApp(const AthkarApp());
}

// ==========================================
// 2. ROOT APP WIDGET
// ==========================================
class AthkarApp extends StatelessWidget {
  const AthkarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'أذكار أمي 🤲',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ==========================================
// 3. REMINDER & BACKGROUND SERVICE
// ==========================================
class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final FlutterTts _tts = FlutterTts();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isTtsInitialized = false;

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notifications.initialize(initSettings);

    await _tts.setLanguage("ar");
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    
    // ضمان اكتمال نطق الدعاء قبل تحرير الموارد
    await _tts.awaitSpeakCompletion(true);
    _isTtsInitialized = true;
  }

  // إعداد خدمة الخلفية المستقلة
  static Future<void> setupBackgroundService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'azkar_mom_channel',
        initialNotificationTitle: 'أذكار أمي 🤲',
        initialNotificationContent: 'التذكير الصوتي الدوري نشط في الخلفية',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(),
    );
  }

  // نقطة التشغيل في الـ Background Isolate المنفصل
  @pragma('vm:entry-point')
  static void onBackgroundStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    final reminderService = ReminderService();
    await reminderService.init();

    Timer? backgroundTimer;

    Future<void> startLoop() async {
      backgroundTimer?.cancel();
      final prefs = await SharedPreferences.getInstance();
      final interval = prefs.getInt('interval_minutes') ?? 5;

      backgroundTimer = Timer.periodic(Duration(minutes: interval), (_) async {
        final currentDuaas = prefs.getStringList('saved_duaas') ?? [];
        if (currentDuaas.isNotEmpty) {
          await reminderService.speakAndNotify(currentDuaas);
        }
      });
    }

    await startLoop();

    service.on('stopService').listen((event) {
      backgroundTimer?.cancel();
      reminderService.stopAudio();
      service.stopSelf();
    });

    service.on('updateInterval').listen((event) async {
      await startLoop();
    });
  }

  Future<void> speakAndNotify(List<String> duaas) async {
    if (duaas.isEmpty) return;

    final randomDuaa = duaas[Random().nextInt(duaas.length)];
    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    const androidDetails = AndroidNotificationDetails(
      'azkar_mom_channel',
      'أذكار وصدقة لأمي',
      channelDescription: 'التذكير الدوري بأدعية لوالدتي رحمها الله',
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
    );

    await _notifications.show(
      notificationId,
      '🤲 دعاء لوالدتي',
      randomDuaa,
      const NotificationDetails(android: androidDetails),
    );

    if (_isTtsInitialized) {
      await _tts.stop();
      await _tts.speak(randomDuaa);
    }
  }

  void stopAudio() {
    _tts.stop();
  }
}

// ==========================================
// 4. HOME SCREEN UI & LOGIC
// ==========================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> _duaas = [];
  int _intervalMinutes = 5;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadSavedData();
    _checkServiceStatus();
  }

  Future<void> _checkServiceStatus() async {
    final running = await FlutterBackgroundService().isRunning();
    setState(() {
      _isRunning = running;
    });
  }

  Future<void> _requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _duaas.clear();
      _duaas.addAll(prefs.getStringList('saved_duaas') ?? [
        "اللهم ارحم أمي واغفر لها 🤲",
        "اللهم اجعل أمي من أهل الجنة 🌿",
        "اللهم أنر قبر أمي بنورك 💫",
      ]);
      _intervalMinutes = prefs.getInt('interval_minutes') ?? 5;
    });
  }

  Future<void> _saveDuaas() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_duaas', _duaas);
  }

  Future<void> _saveInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('interval_minutes', minutes);
  }

  void _toggleService() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();

    if (!isRunning) {
      if (_duaas.isEmpty) return;
      await service.startService();
      ReminderService().speakAndNotify(_duaas);
      setState(() => _isRunning = true);
    } else {
      service.invoke("stopService");
      ReminderService().stopAudio();
      setState(() => _isRunning = false);
    }
  }

  void _notifyServiceIntervalChanged() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke("updateInterval");
    }
  }

  void _showDuaaDialog({int? index}) {
    final controller = TextEditingController(
      text: index != null ? _duaas[index] : '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(index != null ? 'تعديل الدعاء 🤲' : 'إضافة دعاء جديد 🤲'),
        content: TextField(
          controller: controller,
          maxLines: 2,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'اكتب الدعاء هنا...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                setState(() {
                  if (index != null) {
                    _duaas[index] = text;
                  } else {
                    _duaas.add(text);
                  }
                });
                _saveDuaas();
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ).then((_) => controller.dispose()); // تفريغ الذاكرة
  }

  void _showIntervalDialog() {
    final controller = TextEditingController(text: _intervalMinutes.toString());

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل المدة الزمانية (بالدقائق) ⏱️'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'مثال: 5',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text.trim());
              if (minutes != null && minutes > 0) {
                setState(() {
                  _intervalMinutes = minutes;
                });
                _saveInterval(minutes);
                _notifyServiceIntervalChanged();
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('صدقة جارية | أذكار أمي 🤲'),
          centerTitle: true,
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.teal.shade50,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'التكرار كل: $_intervalMinutes دقائق',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_calendar, color: Colors.teal),
                        onPressed: _showIntervalDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isRunning ? Colors.redAccent : Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _duaas.isEmpty ? null : _toggleService,
                      icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(
                        _isRunning ? 'إيقاف التذكير' : 'تشغيل التذكير الدوري',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: _duaas.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.menu_book_sharp, size: 60, color: Colors.grey),
                          SizedBox(height: 10),
                          Text(
                            'لا يوجد أدعية مضافة!\nاضغط على (+) لإضافة دعاء جديد.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _duaas.length,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (context, index) {
                        final duaa = _duaas[index];
                        return Dismissible(
                          key: Key('$duaa-$index'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.redAccent,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (direction) {
                            setState(() {
                              _duaas.removeAt(index);
                            });
                            _saveDuaas();
                            if (_duaas.isEmpty && _isRunning) {
                              _toggleService();
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم حذف الدعاء')),
                            );
                          },
                          child: Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              title: Text(
                                duaa,
                                style: const TextStyle(fontSize: 16),
                              ),
                              leading: IconButton(
                                icon: const Icon(Icons.volume_up, color: Colors.teal),
                                onPressed: () => ReminderService().speakAndNotify([duaa]),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit, color: Colors.grey),
                                onPressed: () => _showDuaaDialog(index: index),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          onPressed: () => _showDuaaDialog(),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
