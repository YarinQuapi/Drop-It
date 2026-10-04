import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api.dart';
import 'copy.dart';
import 'reminders.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DropItApp());
}

class DropItApp extends StatefulWidget {
  const DropItApp({super.key});

  @override
  State<DropItApp> createState() => _DropItAppState();
}

class _DropItAppState extends State<DropItApp> {
  final Api api = Api();
  final Reminders reminders = Reminders();
  Map<String, dynamic>? me;
  bool loading = true;
  String lang = 'en';

  Copy get t => Copy(lang);

  @override
  void initState() {
    super.initState();
    unawaited(boot());
  }

  Future<void> boot() async {
    await reminders.init();
    await api.loadToken();
    if (api.token != null) {
      try {
        me = await api.send('GET', '/api/auth/me');
        lang = me!['user']['language'] as String;
      } catch (_) {
        await api.setToken(null);
      }
    }
    if (mounted) setState(() => loading = false);
    await syncReminders();
  }

  Future<void> syncReminders() async {
    if (api.token == null) return;
    try {
      final fasting = await api.send('GET', '/api/fasting');
      await reminders.schedule(
        enabled: fasting['enabled'] == true,
        startHour: fasting['startHour'] as int,
        endHour: fasting['endHour'] as int,
        startText: t.reminderStart,
        endText: t.reminderEnd,
        doneText: t.reminderDone,
        endsAtIso: fasting['endsAt'] as String?,
      );
    } catch (_) {}
  }

  Future<void> afterAuth(Map<String, dynamic> auth) async {
    await api.setToken(auth['token'] as String);
    me = await api.send('GET', '/api/auth/me');
    lang = me!['user']['language'] as String;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final copy = t;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: copy.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A4D)),
        useMaterial3: true,
      ),
      home: Directionality(
        textDirection: lang == 'he' ? TextDirection.rtl : TextDirection.ltr,
        child: loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : me == null
                ? AuthScreen(api: api, t: copy, onAuth: afterAuth)
                : me!['hasProfile'] != true
                    ? SetupScreen(
                        api: api,
                        t: copy,
                        onReady: (next) => setState(() => me = next),
                        sync: syncReminders,
                      )
                    : HomeScreen(
                        api: api,
                        t: copy,
                        me: me!,
                        onMe: (next) => setState(() {
                          me = next;
                          lang = next['user']['language'] as String;
                        }),
                        onLogout: () async {
                          await api.send('POST', '/api/auth/logout');
                          await api.setToken(null);
                          setState(() => me = null);
                        },
                        sync: syncReminders,
                      ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.t, required this.onAuth});
  final Api api;
  final Copy t;
  final Future<void> Function(Map<String, dynamic>) onAuth;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool signup = false;
  String error = '';

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(signup ? t.signup : t.login, style: Theme.of(context).textTheme.headlineMedium),
            TextField(controller: email, decoration: InputDecoration(labelText: t.email), keyboardType: TextInputType.emailAddress),
            TextField(controller: password, decoration: InputDecoration(labelText: t.password), obscureText: true),
            if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                try {
                  final auth = await widget.api.send('POST', signup ? '/api/auth/signup' : '/api/auth/login', body: {
                    'email': email.text.trim(),
                    'password': password.text,
                    'language': Localizations.localeOf(context).languageCode == 'he' ? 'he' : 'en',
                  });
                  await widget.onAuth(auth);
                } on ApiException catch (err) {
                  setState(() => error = t.error(err.code));
                }
              },
              child: Text(signup ? t.signup : t.login),
            ),
            TextButton(onPressed: () => setState(() => signup = !signup), child: Text(signup ? t.login : t.signup)),
          ],
        ),
      ),
    );
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.api, required this.t, required this.onReady, required this.sync});
  final Api api;
  final Copy t;
  final ValueChanged<Map<String, dynamic>> onReady;
  final Future<void> Function() sync;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool? wants;
  int length = 16;
  int startHour = 20;
  int endHour = 12;
  String sex = 'female';
  final dob = TextEditingController();
  final height = TextEditingController();
  final weight = TextEditingController();
  String activity = 'sedentary';
  String pace = 'kg050';
  bool profileStep = false;
  String error = '';

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!profileStep) ...[
              Text(t.fastingQuestion, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton(onPressed: () => setState(() => wants = true), child: Text(t.yes)),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () => setState(() => wants = false), child: Text(t.no)),
              ]),
              if (wants == true) ...[
                DropdownButtonFormField<int>(
                  initialValue: length,
                  decoration: InputDecoration(labelText: t.fastingLength),
                  items: [12, 14, 16].map((value) => DropdownMenuItem(value: value, child: Text('$value ${t.hours}'))).toList(),
                  onChanged: (value) => setState(() => length = value ?? 16),
                ),
                hourPicker(t.startHour, startHour, (value) => setState(() => startHour = value)),
                hourPicker(t.endHour, endHour, (value) => setState(() => endHour = value)),
              ],
              if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
              FilledButton(
                onPressed: wants == null
                    ? null
                    : () async {
                        try {
                          await widget.api.send('PUT', '/api/fasting', body: {
                            'enabled': wants == true,
                            'lengthHours': length,
                            'startHour': startHour,
                            'endHour': endHour,
                          });
                          await widget.sync();
                          setState(() => profileStep = true);
                        } on ApiException catch (err) {
                          setState(() => error = t.error(err.code));
                        }
                      },
                child: Text(t.continueLabel),
              ),
            ] else ...[
              Text(t.profileTitle, style: Theme.of(context).textTheme.headlineSmall),
              DropdownButtonFormField<String>(
                initialValue: sex,
                decoration: InputDecoration(labelText: t.sex),
                items: [DropdownMenuItem(value: 'female', child: Text(t.female)), DropdownMenuItem(value: 'male', child: Text(t.male))],
                onChanged: (value) => setState(() => sex = value ?? 'female'),
              ),
              TextField(controller: dob, decoration: InputDecoration(labelText: '${t.dateOfBirth} (YYYY-MM-DD)')),
              TextField(controller: height, decoration: InputDecoration(labelText: t.height), keyboardType: TextInputType.number),
              TextField(controller: weight, decoration: InputDecoration(labelText: t.weightKg), keyboardType: TextInputType.number),
              DropdownButtonFormField<String>(
                initialValue: activity,
                decoration: InputDecoration(labelText: t.activity),
                items: ['sedentary', 'light', 'moderate', 'very', 'extra']
                    .map((value) => DropdownMenuItem(value: value, child: Text(t.activityLabel(value))))
                    .toList(),
                onChanged: (value) => setState(() => activity = value ?? 'sedentary'),
              ),
              DropdownButtonFormField<String>(
                initialValue: pace,
                decoration: InputDecoration(labelText: t.pace),
                items: ['kg025', 'kg050', 'kg100'].map((value) => DropdownMenuItem(value: value, child: Text(t.paceLabel(value)))).toList(),
                onChanged: (value) => setState(() => pace = value ?? 'kg050'),
              ),
              if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
              FilledButton(
                onPressed: () async {
                  try {
                    await widget.api.send('PUT', '/api/profile', body: {
                      'sex': sex,
                      'dateOfBirth': dob.text.trim(),
                      'heightCm': num.parse(height.text),
                      'weightKg': num.parse(weight.text),
                      'activity': activity,
                      'weeklyPace': pace,
                    });
                    widget.onReady(await widget.api.send('GET', '/api/auth/me'));
                  } on ApiException catch (err) {
                    setState(() => error = t.error(err.code));
                  } catch (_) {
                    setState(() => error = t.error('invalid_body'));
                  }
                },
                child: Text(t.save),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.t,
    required this.me,
    required this.onMe,
    required this.onLogout,
    required this.sync,
  });
  final Api api;
  final Copy t;
  final Map<String, dynamic> me;
  final ValueChanged<Map<String, dynamic>> onMe;
  final Future<void> Function() onLogout;
  final Future<void> Function() sync;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final pages = [
      TodayScreen(api: widget.api, t: t, admin: widget.me['user']['isAdmin'] == true, sync: widget.sync),
      WeekScreen(api: widget.api, t: t),
      WeightScreen(api: widget.api, t: t),
      SettingsScreen(api: widget.api, t: t, me: widget.me, onMe: widget.onMe, sync: widget.sync),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(t.appName),
        actions: [TextButton(onPressed: widget.onLogout, child: Text(t.logout))],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.today), label: t.today),
          NavigationDestination(icon: const Icon(Icons.calendar_view_week), label: t.week),
          NavigationDestination(icon: const Icon(Icons.show_chart), label: t.weight),
          NavigationDestination(icon: const Icon(Icons.settings), label: t.settings),
        ],
      ),
    );
  }
}

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.api, required this.t, required this.admin, required this.sync});
  final Api api;
  final Copy t;
  final bool admin;
  final Future<void> Function() sync;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Map<String, dynamic>? day;
  Map<String, dynamic>? fasting;
  String error = '';
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    unawaited(load());
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final nextDay = await widget.api.send('GET', '/api/days/today');
      final nextFast = await widget.api.send('GET', '/api/fasting');
      setState(() {
        day = nextDay;
        fasting = nextFast;
        error = '';
      });
    } on ApiException catch (err) {
      setState(() => error = widget.t.error(err.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final totals = (day?['totals'] as Map?)?.cast<String, dynamic>();
    final entries = ((day?['entries'] as List?) ?? []).cast<Map>();
    final running = fasting?['running'] == true;
    final endsAt = fasting?['endsAt'] as String?;
    final left = endsAt == null ? Duration.zero : DateTime.parse(endsAt).difference(DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (day != null) ...[
          Text('${t.goal}: ${day!['goalKcal']}'),
          Text('${t.eaten}: ${totals?['calories']}'),
          Text('${t.remaining}: ${((day!['goalKcal'] as num) - (totals?['calories'] as num))}'),
          Text(t.estimate),
          Text('${t.protein}: ${totals?['protein']}  ${t.carbohydrates}: ${totals?['carbohydrates']}'),
          Text('${t.fat}: ${totals?['fat']}  ${t.fiber}: ${totals?['fiber']}'),
          Text('${t.sugars}: ${totals?['sugars']}  ${t.sodium}: ${totals?['sodium']}'),
        ],
        const Divider(),
        if (fasting != null && fasting!['enabled'] == true) ...[
          Text(t.fasting),
          if (running) Text('${t.timeLeft}: ${_clock(left)}'),
          FilledButton(
            onPressed: () async {
              try {
                await widget.api.send('POST', running ? '/api/fasting/stop' : '/api/fasting/start');
                await load();
                await widget.sync();
              } on ApiException catch (err) {
                setState(() => error = t.error(err.code));
              }
            },
            child: Text(running ? t.stopFast : t.startFast),
          ),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () async {
                final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
                if (code != null) await lookup(code);
              },
              child: Text(t.scan),
            ),
          ),
        ]),
        TextButton(onPressed: () async {
          final code = await askText(context, t.barcode);
          if (code != null && code.isNotEmpty) await lookup(code);
        }, child: Text(t.lookUp)),
        if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
        if (entries.isEmpty) Text(t.emptyDay),
        for (final entry in entries)
          ListTile(
            title: Text(entry['name'] as String),
            subtitle: Text('${entry['amount']} · ${entry['calories']} kcal'),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                await widget.api.send('DELETE', '/api/days/today/entries/${entry['id']}');
                await load();
              },
            ),
          ),
      ],
    );
  }

  Future<void> lookup(String barcode) async {
    final t = widget.t;
    final result = await widget.api.send('GET', '/api/foods/barcode/${Uri.encodeComponent(barcode)}');
    if (!mounted) return;
    Map<String, dynamic>? food = (result['food'] as Map?)?.cast<String, dynamic>();
    if (result['status'] == 'none') {
      food = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(builder: (_) => FoodScreen(api: widget.api, t: t, barcode: barcode)),
      );
    } else if (result['status'] == 'list') {
      final foods = (result['foods'] as List).cast<Map>();
      food = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (context) => ListView(
          children: [
            ListTile(title: Text(t.chooseFood)),
            for (final item in foods)
              ListTile(
                title: Text(item['name'] as String),
                subtitle: Text(item['verified'] == true ? t.verified : ''),
                onTap: () => Navigator.pop(context, item.cast<String, dynamic>()),
              ),
          ],
        ),
      );
    }
    if (food == null || !mounted) return;
    food = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) => FoodActions(api: widget.api, t: t, food: food!, admin: widget.admin),
    );
    if (food == null || !mounted) return;
    final amount = await askText(context, '${t.amount} (${food['basis'] == 'solid' ? t.grams : t.milliliters})');
    if (amount == null) return;
    try {
      await widget.api.send('POST', '/api/days/today/entries', body: {
        'foodId': food['id'],
        'amount': num.parse(amount),
      });
      await load();
      await widget.sync();
    } on ApiException catch (err) {
      setState(() => error = t.error(err.code));
    }
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: MobileScanner(
        onDetect: (capture) {
          if (done) return;
          final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
          if (value == null || value.isEmpty) return;
          done = true;
          Navigator.pop(context, value);
        },
      ),
    );
  }
}

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key, required this.api, required this.t});
  final Api api;
  final Copy t;

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  Map<String, dynamic>? week;
  String? on;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final query = on == null ? '' : '?on=$on';
    final data = await widget.api.send('GET', '/api/weeks$query');
    setState(() => week = data);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (week == null) return const Center(child: CircularProgressIndicator());
    final days = (week!['days'] as List).cast<Map>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          TextButton(onPressed: () { on = _shift(week!['sunday'] as String, -7); load(); }, child: Text(t.previousWeek)),
          TextButton(onPressed: () { on = _shift(week!['sunday'] as String, 7); load(); }, child: Text(t.nextWeek)),
        ]),
        Text('${t.calorieIntake}: ${week!['calorieIntake']}'),
        Text('${t.successCount}: ${week!['successCount']}'),
        Text('${t.weightChange}: ${week!['weightChangeKg'] ?? t.noWeightChange}'),
        for (final day in days)
          ListTile(
            title: Text(day['day'] as String),
            subtitle: Text('${day['calories']} / ${day['goalKcal']}'),
            trailing: Text(day['future'] == true || (day['success'] != true && day['calories'] == 0)
                ? t.notYet
                : day['success'] == true
                    ? t.success
                    : t.missed),
          ),
      ],
    );
  }
}

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key, required this.api, required this.t});
  final Api api;
  final Copy t;

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  List<Map<String, dynamic>> weights = [];
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final data = await widget.api.send('GET', '/api/weights');
    setState(() => weights = (data['weights'] as List).cast<Map<String, dynamic>>());
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: controller, decoration: InputDecoration(labelText: t.weightKg), keyboardType: TextInputType.number),
        FilledButton(
          onPressed: () async {
            await widget.api.send('POST', '/api/weights', body: {'weightKg': num.parse(controller.text)});
            controller.clear();
            await load();
          },
          child: Text(t.logWeight),
        ),
        const SizedBox(height: 12),
        if (weights.isEmpty) Text(t.graphEmpty) else SizedBox(height: 180, child: CustomPaint(painter: WeightPainter(weights), child: const SizedBox.expand())),
        for (final point in weights.reversed) ListTile(title: Text('${point['weightKg']} kg'), subtitle: Text(point['loggedAt'] as String)),
      ],
    );
  }
}

class WeightPainter extends CustomPainter {
  WeightPainter(this.weights);
  final List<Map<String, dynamic>> weights;

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.length < 2) {
      if (weights.isNotEmpty) {
        canvas.drawCircle(Offset(size.width / 2, size.height / 2), 4, Paint()..color = const Color(0xFF1F7A4D));
      }
      return;
    }
    final times = weights.map((point) => DateTime.parse(point['loggedAt'] as String).millisecondsSinceEpoch.toDouble()).toList();
    final values = weights.map((point) => (point['weightKg'] as num).toDouble()).toList();
    final minT = times.reduce((a, b) => a < b ? a : b);
    final maxT = times.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final paint = Paint()
      ..color = const Color(0xFF1F7A4D)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < weights.length; i++) {
      final x = maxT == minT ? size.width / 2 : (times[i] - minT) / (maxT - minT) * (size.width - 16) + 8;
      final y = maxV == minV ? size.height / 2 : size.height - 8 - (values[i] - minV) / (maxV - minV) * (size.height - 16);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = const Color(0xFF1F7A4D));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WeightPainter oldDelegate) => true;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api, required this.t, required this.me, required this.onMe, required this.sync});
  final Api api;
  final Copy t;
  final Map<String, dynamic> me;
  final ValueChanged<Map<String, dynamic>> onMe;
  final Future<void> Function() sync;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? profile;
  Map<String, dynamic>? fasting;
  bool autoPublish = false;

  @override
  void initState() {
    super.initState();
    autoPublish = widget.me['user']['autoPublishFoods'] == true;
    unawaited(load());
  }

  Future<void> load() async {
    final profileResponse = await widget.api.send('GET', '/api/profile');
    final fastingResponse = await widget.api.send('GET', '/api/fasting');
    setState(() {
      profile = (profileResponse['profile'] as Map?)?.cast<String, dynamic>();
      fasting = fastingResponse;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: widget.me['user']['language'] as String,
          decoration: InputDecoration(labelText: t.language),
          items: [DropdownMenuItem(value: 'en', child: Text(t.english)), DropdownMenuItem(value: 'he', child: Text(t.hebrew))],
          onChanged: (value) async {
            if (value == null) return;
            await widget.api.send('PUT', '/api/profile/settings', body: {'language': value, 'autoPublishFoods': autoPublish});
            widget.onMe(await widget.api.send('GET', '/api/auth/me'));
          },
        ),
        SwitchListTile(
          title: Text(t.autoPublish),
          value: autoPublish,
          onChanged: (value) async {
            setState(() => autoPublish = value);
            await widget.api.send('PUT', '/api/profile/settings', body: {
              'language': widget.me['user']['language'],
              'autoPublishFoods': value,
            });
          },
        ),
        if (fasting != null)
          FastingEditor(
            t: t,
            fasting: fasting!,
            onSave: (body) async {
              await widget.api.send('PUT', '/api/fasting', body: body);
              await load();
              await widget.sync();
            },
          ),
        if (profile != null) Text('${t.weightKg}: ${profile!['weightKg']} · ${t.goal}'),
      ],
    );
  }
}

class FoodActions extends StatefulWidget {
  const FoodActions({super.key, required this.api, required this.t, required this.food, required this.admin});
  final Api api;
  final Copy t;
  final Map<String, dynamic> food;
  final bool admin;

  @override
  State<FoodActions> createState() => _FoodActionsState();
}

class _FoodActionsState extends State<FoodActions> {
  late Map<String, dynamic> food = widget.food;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(food['name'] as String, style: Theme.of(context).textTheme.titleLarge),
          if (food['verified'] == true) Text(t.verified),
          if (food['owned'] == true)
            OutlinedButton(
              onPressed: () async {
                final path = food['published'] == true ? 'unpublish' : 'publish';
                final result = await widget.api.send('POST', '/api/foods/${food['id']}/$path');
                setState(() => food = (result['food'] as Map).cast<String, dynamic>());
              },
              child: Text(food['published'] == true ? t.unpublish : t.publish),
            ),
          if (widget.admin && food['published'] == true && food['verified'] != true)
            OutlinedButton(
              onPressed: () async {
                final result = await widget.api.send('POST', '/api/foods/${food['id']}/verify');
                setState(() => food = (result['food'] as Map).cast<String, dynamic>());
              },
              child: Text(t.verify),
            ),
          FilledButton(onPressed: () => Navigator.pop(context, food), child: Text(t.add)),
        ],
      ),
    );
  }
}

class FastingEditor extends StatefulWidget {
  const FastingEditor({super.key, required this.t, required this.fasting, required this.onSave});
  final Copy t;
  final Map<String, dynamic> fasting;
  final Future<void> Function(Map<String, dynamic> body) onSave;

  @override
  State<FastingEditor> createState() => _FastingEditorState();
}

class _FastingEditorState extends State<FastingEditor> {
  late bool enabled = widget.fasting['enabled'] == true;
  late int length = widget.fasting['lengthHours'] as int;
  late int startHour = widget.fasting['startHour'] as int;
  late int endHour = widget.fasting['endHour'] as int;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Column(
      children: [
        SwitchListTile(title: Text(t.fasting), value: enabled, onChanged: (value) => setState(() => enabled = value)),
        DropdownButtonFormField<int>(
          initialValue: length,
          decoration: InputDecoration(labelText: t.fastingLength),
          items: [12, 14, 16].map((value) => DropdownMenuItem(value: value, child: Text('$value ${t.hours}'))).toList(),
          onChanged: (value) => setState(() => length = value ?? length),
        ),
        hourPicker(t.startHour, startHour, (value) => setState(() => startHour = value)),
        hourPicker(t.endHour, endHour, (value) => setState(() => endHour = value)),
        FilledButton(
          onPressed: () => widget.onSave({
            'enabled': enabled,
            'lengthHours': length,
            'startHour': startHour,
            'endHour': endHour,
          }),
          child: Text(t.save),
        ),
      ],
    );
  }
}

class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, required this.api, required this.t, required this.barcode});
  final Api api;
  final Copy t;
  final String barcode;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  final name = TextEditingController();
  String basis = 'solid';
  final calories = TextEditingController(text: '0');
  final protein = TextEditingController(text: '0');
  final carbohydrates = TextEditingController(text: '0');
  final fat = TextEditingController(text: '0');
  final fiber = TextEditingController(text: '0');
  final sugars = TextEditingController(text: '0');
  final sodium = TextEditingController(text: '0');
  String error = '';

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      appBar: AppBar(title: Text(t.createFood)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${t.barcode}: ${widget.barcode}'),
          TextField(controller: name, decoration: InputDecoration(labelText: t.name)),
          DropdownButtonFormField<String>(
            initialValue: basis,
            items: [DropdownMenuItem(value: 'solid', child: Text(t.solid)), DropdownMenuItem(value: 'liquid', child: Text(t.liquid))],
            onChanged: (value) => setState(() => basis = value ?? 'solid'),
          ),
          TextField(controller: calories, decoration: InputDecoration(labelText: t.calories), keyboardType: TextInputType.number),
          TextField(controller: protein, decoration: InputDecoration(labelText: t.protein), keyboardType: TextInputType.number),
          TextField(controller: carbohydrates, decoration: InputDecoration(labelText: t.carbohydrates), keyboardType: TextInputType.number),
          TextField(controller: fat, decoration: InputDecoration(labelText: t.fat), keyboardType: TextInputType.number),
          TextField(controller: fiber, decoration: InputDecoration(labelText: t.fiber), keyboardType: TextInputType.number),
          TextField(controller: sugars, decoration: InputDecoration(labelText: t.sugars), keyboardType: TextInputType.number),
          TextField(controller: sodium, decoration: InputDecoration(labelText: t.sodium), keyboardType: TextInputType.number),
          if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
          FilledButton(
            onPressed: () async {
              try {
                final created = await widget.api.send('POST', '/api/foods', body: {
                  'barcode': widget.barcode,
                  'name': name.text.trim(),
                  'basis': basis,
                  'calories': num.parse(calories.text),
                  'protein': num.parse(protein.text),
                  'carbohydrates': num.parse(carbohydrates.text),
                  'fat': num.parse(fat.text),
                  'fiber': num.parse(fiber.text),
                  'sugars': num.parse(sugars.text),
                  'sodium': num.parse(sodium.text),
                });
                if (context.mounted) Navigator.pop(context, (created['food'] as Map).cast<String, dynamic>());
              } on ApiException catch (err) {
                setState(() => error = t.error(err.code));
              }
            },
            child: Text(t.save),
          ),
        ],
      ),
    );
  }
}

Widget hourPicker(String label, int value, ValueChanged<int> onChanged) {
  return DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [for (var hour = 0; hour < 24; hour++) DropdownMenuItem(value: hour, child: Text('${hour.toString().padLeft(2, '0')}:00'))],
    onChanged: (next) => onChanged(next ?? value),
  );
}

Future<String?> askText(BuildContext context, String label) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label),
      content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

String _clock(Duration duration) {
  final positive = duration.isNegative ? Duration.zero : duration;
  final hours = positive.inHours.toString().padLeft(2, '0');
  final minutes = positive.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = positive.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String _shift(String day, int count) {
  final date = DateTime.parse('${day}T00:00:00Z').add(Duration(days: count));
  final month = date.month.toString().padLeft(2, '0');
  final dayText = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$dayText';
}
